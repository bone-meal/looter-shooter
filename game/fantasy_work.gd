# Purpose: what the interact key does in the fantasy world and the skilling that follows from it: gathering (chop,
# mine, fish, reap, pick: needs the skill level and the right tool, takes seconds, gives an item and experience, and
# keeps going until the node is used up), crafting at stations (recipes: cook at a fire, smith at a forge, build at a
# workbench, brew at a cauldron, saw at a sawhorse, craft at a crafting table), and talking to people (quests are offered and reported there).
# Dependencies: game/fantasy_world.gd (bag, skills, perks, quests, gather nodes, places), core/skill_perks.gd, data/fantasy/skilling.json.
extends Node

const SkillPerks = preload("res://core/skill_perks.gd")

signal talk_opened(person: Dictionary)
signal station_opened(kind: String)

const WATERS := {"fresh": "freshwater", "salt": "saltwater", "lava": "lava"}
const VERBS := {"woodcutting": "Chop", "mining": "Mine", "fishing": "Fish at", "farming": "Reap", "alchemy": "Pick", "hunting": "Follow", "archaeology": "Dig at"}
const STATION_NAMES := {"fire": "Cook at the fire", "forge": "Work the forge", "workbench": "Use the workbench", "cauldron": "Brew at the cauldron",
	"sawhorse": "Saw at the sawhorse", "crafting_table": "Craft at the table", "coach": "Hire a coach"}  # (polish1 E5) the coach house itself opens the coach page too
const TALK_REACH := 3.0

var world: Node3D  # game/fantasy_world.gd
var town_lock := Callable()  # set by the sea's home port (game/sea_town.gd): recipe -> why the town cannot make it yet ("" = it can)
var town_share := Callable()  # recipe -> share of its materials used (a grand shipyard builds for less)

var _node := {}  # the gather node being worked ({} = idle)
var _done := 0.0
var _needed := 1.0
var _cfg: Dictionary


func setup(fantasy_world: Node3D) -> void:
	world = fantasy_world
	_cfg = world.skilling["gather"]


# Why this node cannot be worked right now ("" = it can).
func blocked(def: Dictionary) -> String:
	if int(world.skills.level(String(def["skill"]))) < int(def["level"]):
		return "needs %s %d" % [world.skills.skill_name(String(def["skill"])), int(def["level"])]
	var tool := String(def.get("tool", ""))
	if tool != "" and int(world.bag.tool_tier(tool)) < int(def.get("tool_tier", 1)):
		return "needs a better %s" % tool
	return ""


func prompt(key: String) -> String:
	var local: Vector3 = world.player_local()
	var person: Dictionary = world.places.person_near(local, TALK_REACH)
	if not person.is_empty() and bool(person.get("coach", false)):  # (polish1 E5) a coachman
		return "[%s] Hire a coach (%s)" % [key, person["name"]]
	if not person.is_empty():
		return "[%s] Talk to %s" % [key, person["name"]]
	if world.agility.busy():
		return ""
	var station: Dictionary = world.places.station_near(local, TALK_REACH)
	if not station.is_empty() and String(station["kind"]) == "agility":
		return world.agility.obstacle_prompt(station, key)
	if not station.is_empty():
		return "[%s] %s" % [key, STATION_NAMES[String(station["kind"])]]
	var shortcut: Dictionary = world.agility.shortcut_near(local)
	if not shortcut.is_empty():
		return world.agility.shortcut_prompt(shortcut, key)
	var snare: Dictionary = world.snares.near(local)
	if not snare.is_empty():
		return world.snares.prompt(snare, key)
	if not _node.is_empty():
		return ""
	var node := _near_node(local)
	if node.is_empty():
		return ""
	var def: Dictionary = world.skilling["nodes"][String(node["id"])]
	var why := blocked(def)
	if why != "":
		return "%s: %s" % [def["name"], why]
	var water := String(def.get("water", ""))
	return "[%s] %s %s%s" % [key, VERBS[String(def["skill"])], String(def["name"]).to_lower(), "" if water == "" else "  (%s)" % WATERS[water]]


# The nearest thing to gather that is in reach: a fishing spot lies out in the water, so a line reaches further than a hand.
func _near_node(local: Vector3) -> Dictionary:
	var node: Dictionary = world.gather.nearest(local, float(_cfg["reach_water"]))
	if node.is_empty():
		return node
	var at: Vector3 = node["at"]
	if Vector2(local.x - at.x, local.z - at.z).length() > _reach_of(node):
		return world.gather.nearest(local, float(_cfg["reach"]))
	return node


func _reach_of(node: Dictionary) -> float:
	return float(_cfg["reach_water"] if world.skilling["nodes"][String(node["id"])].has("water") else _cfg["reach"])


func interact() -> void:
	var local: Vector3 = world.player_local()
	var person: Dictionary = world.places.person_near(local, TALK_REACH)
	if not person.is_empty() and bool(person.get("coach", false)):  # (polish1 E5) the coach page
		station_opened.emit("coach")
		return
	if not person.is_empty():
		var told: Array = []  # (polish1 item 103) quests waiting on a talk with this person: what they say for it
		for qid: String in world.quests.active:
			var s: Dictionary = world.quests.step(qid)
			if String(s.get("type", "")) == "talk" and String(s.get("npc", "")) == String(person["id"]):
				told.append(qid)
		world.report({"type": "talk", "npc": String(person["id"])})
		var said: Array = []
		for qid: String in told:
			var steps: Array = world.quests.quest(qid)["steps"]
			for s2: Dictionary in steps:
				if String(s2.get("type", "")) == "talk" and String(s2.get("npc", "")) == String(person["id"]):
					var line := String(s2.get("says", ""))
					var next := String(world.quests.step_text(qid))
					said.append({"quest": qid, "line": line if line != "" else next, "next": next})
		var shown := person.duplicate()
		shown["told"] = said
		talk_opened.emit(shown)
		return
	if world.agility.busy():
		return
	var station: Dictionary = world.places.station_near(local, TALK_REACH)
	if not station.is_empty() and String(station["kind"]) == "agility":
		world.agility.cross(station)
		return
	if not station.is_empty():
		station_opened.emit(String(station["kind"]))
		return
	var shortcut: Dictionary = world.agility.shortcut_near(local)
	if not shortcut.is_empty():
		world.agility.use_shortcut(shortcut)
		return
	var snare: Dictionary = world.snares.near(local)
	if not snare.is_empty():
		world.snares.collect(snare)
		return
	var node := _near_node(local)
	if node.is_empty():
		return
	var def: Dictionary = world.skilling["nodes"][String(node["id"])]
	if blocked(def) != "":
		return
	_node = node
	_done = 0.0
	var spare := int(world.bag.tool_tier(String(def.get("tool", "")))) - int(def.get("tool_tier", 1)) if def.has("tool") else 0
	_needed = float(def["seconds"]) / (1.0 + float(_cfg["tool_speed"]) * float(maxi(spare, 0))) * maxf(1.0 - world.perk(String(def["skill"]), "speed"), 0.2)


# 0..1 while something is being gathered, -1 when idle (the HUD draws a bar), and what is being worked.
func progress() -> float:
	return -1.0 if _node.is_empty() else clampf(_done / _needed, 0.0, 1.0)


func working_on() -> String:
	return "" if _node.is_empty() else String(world.skilling["nodes"][String(_node["id"])]["name"])


func _process(delta: float) -> void:
	if _node.is_empty():
		return
	var local: Vector3 = world.player_local()
	var at: Vector3 = _node["at"]
	if not world.inside or Vector2(local.x - at.x, local.z - at.z).length() > _reach_of(_node) + 0.8 or world.gather.is_spent(_node):
		_node = {}
		return
	_done += delta
	if _done < _needed:
		return
	_done = 0.0
	var def: Dictionary = world.skilling["nodes"][String(_node["id"])]
	var skill := String(def["skill"])
	world.sound("gather_" + skill, world.world_of(at))
	if def.has("animal"):  # tracks: read them, and the trail leads on to the animal
		world.follow_tracks(String(def["animal"]), at)
	elif def.has("finds"):  # a dig: one of its relics, picked by weight (Archaeology)
		var find := _pick_find(def["finds"])
		var many := 2 if randf() < world.perk(skill, "double") else 1
		world.give(find, many)
		world.worked.emit(skill, find, many, false)
	else:
		var odds := success(world.skilling, skill, int(world.skills.level(skill)), int(def["level"]))
		if randf() >= odds:  # (polish1 item 121) a miss is fine, but it says so
			var words := String((world.skilling.get("success", {}) as Dictionary).get(skill, {}).get("miss_words", "Nothing this time."))
			world.emit_signal("notice", words)
			world.gain_xp(skill, maxi(floori(float(def["xp"]) / 4.0), 1))
			return
		var count := 2 if randf() < world.perk(skill, "double") else 1
		if randf() < odds - 1.0:  # over 100 %: a bonus find
			count += 1
		world.give(String(def["gives"]), count)
		world.worked.emit(skill, String(def["gives"]), count, false)
	for find: Dictionary in [] if def.has("animal") or def.has("finds") else SkillPerks.bonus_finds(world.skilling.get("unlocks", {}), skill, int(world.skills.level(skill))):
		if randf() < float(find["chance"]):
			world.give(String(find["item"]), 1)
	world.gain_xp(skill, int(def["xp"]))
	if bool(def.get("once", false)) or randf() < float(_cfg["deplete_chance"]) * (1.0 - world.perk(skill, "keep")):
		world.gather_use(_node, float(def["respawn"]) * maxf(1.0 - world.perk(skill, "regrow"), 0.2))  # (polish1 item 114) shared online
		_node = {}


# The chance a cycle of a gathering skill finds something (data/fantasy/skilling.json "success"); 1.0 for skills not
# listed; over 1.0 = the extra is a bonus item's chance.
static func success(skilling: Dictionary, skill: String, level: int, node_level: int) -> float:
	var rule: Dictionary = (skilling.get("success", {}) as Dictionary).get(skill, {})
	if rule.is_empty():
		return 1.0
	return clampf(float(rule["base"]) + float(rule["per_level"]) * float(level - node_level), float(rule["min"]), float(rule.get("most", 1.5)))


func _pick_find(finds: Dictionary) -> String:
	var total := 0.0
	for item: String in finds:
		total += float(finds[item])
	var roll := randf() * total
	for item: String in finds:
		roll -= float(finds[item])
		if roll <= 0.0:
			return item
	return String(finds.keys()[0])


# --- crafting ---

# Recipes of one station, the ones the player's level allows first.
func recipes(station: String) -> Array:
	var out: Array = []
	for recipe: Dictionary in world.skilling["recipes"]:
		if String(recipe["station"]) == station:
			out.append(recipe)
		elif station == "ship_parts" and _makes_ship_part(recipe):  # the home port's workshop makes the ship parts too
			out.append(recipe)
	return out


func _makes_ship_part(recipe: Dictionary) -> bool:
	for item: String in recipe["out"]:
		if String(world.bag.def(item).get("kind", "")) == "ship_part":
			return true
	return false


# What a recipe really takes (a grand shipyard's ships cost less).
func cost_of(recipe: Dictionary) -> Dictionary:
	var share := float(town_share.call(recipe)) if town_share.is_valid() else 1.0
	if share >= 0.999:
		return recipe["in"]
	var out := {}
	for item: String in recipe["in"]:
		out[item] = maxi(1, ceili(float(recipe["in"][item]) * share))
	return out


func recipe_text(recipe: Dictionary) -> String:
	var needs := PackedStringArray()
	for item: String in recipe["in"]:
		needs.append("%d %s" % [int(recipe["in"][item]), world.bag.item_name(item)])
	var makes := PackedStringArray()
	for item: String in recipe["out"]:
		makes.append("%s%s" % ["%d " % int(recipe["out"][item]) if int(recipe["out"][item]) > 1 else "", world.bag.item_name(item)])
	for item: String in recipe.get("needs", {}):
		needs.append("the %s (kept)" % world.bag.item_name(item))
	return "%s  <-  %s   (%s %d)" % [", ".join(makes), ", ".join(needs), world.skills.skill_name(String(recipe["skill"])), int(recipe["level"])]


# Why a recipe cannot be made right now ("" = it can).
func cannot_make(recipe: Dictionary) -> String:
	if int(world.skills.level(String(recipe["skill"]))) < int(recipe["level"]):
		return "Needs %s %d." % [world.skills.skill_name(String(recipe["skill"])), int(recipe["level"])]
	if town_lock.is_valid():
		var why_town := String(town_lock.call(recipe))
		if why_town != "":
			return why_town
	if not bool(world.bag.has_all(cost_of(recipe))):
		return "You lack the materials."
	if recipe.has("needs") and not bool(world.bag.has_all(recipe["needs"])):  # kept, not used up (a ship's plan)
		return "You need the %s." % world.bag.item_name(String((recipe["needs"] as Dictionary).keys()[0]))
	for item: String in recipe["out"]:
		if String(world.bag.def(item).get("kind", "")) == "gunside" and not bool(world.gun_room()):
			return "Your backpack (gun side) is full."
		if String(world.bag.def(item).get("kind", "")) == "backpack":  # bags go in order, one of each
			var size := int(world.bag.def(item)["bag"])
			if int(world.gun_bags()) >= size:
				return "Your backpack already has that bag."
			if int(world.gun_bags()) < size - 1:
				return "Make the smaller bag first."
	return ""


func make(recipe: Dictionary) -> String:
	var why := cannot_make(recipe)
	if why != "":
		return why
	var skill := String(recipe["skill"])
	if randf() >= world.perk(skill, "save"):  # thrifty perks: sometimes the materials are kept
		world.bag.take_all(cost_of(recipe))
	world.sound("craft_" + String(recipe["station"]))
	var extra := 1 if bool(recipe.get("batch", false)) and randf() < world.perk(skill, "double") else 0
	for item: String in recipe["out"]:
		var count := int(recipe["out"][item]) * (1 + extra)
		world.give(item, count)
		world.worked.emit(skill, item, count, true)
		world.report({"type": "make", "item": item, "count": count})  # (polish1 item 115) "make" quest steps need the real making
	world.gain_xp(String(recipe["skill"]), int(recipe["xp"]))
	if recipe.has("lore"):  # a collection completed: its story (data/fantasy/writing/skills.txt [lore <id>])
		var line := String(world.data["text"].get("lore", {}).get(String(recipe["lore"]), {}).get("text", ""))
		if line != "":
			world.notice.emit(line)
	return ""
