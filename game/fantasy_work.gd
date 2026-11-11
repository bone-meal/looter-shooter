# Purpose: what the interact key does in the fantasy world and the skilling that follows from it: gathering (chop,
# mine, fish, reap, pick: needs the skill level and the right tool, takes seconds, gives an item and experience, and
# keeps going until the node is used up), crafting at stations (recipes: cook at a fire, smith at a forge, build at a
# workbench, brew at a cauldron), and talking to people (quests are offered and reported there).
# Dependencies: game/fantasy_world.gd (bag, skills, quests, gather nodes, places), data/fantasy/skilling.json.
extends Node

signal talk_opened(person: Dictionary)
signal station_opened(kind: String)

const WATERS := {"fresh": "freshwater", "salt": "saltwater", "lava": "lava"}
const VERBS := {"woodcutting": "Chop", "mining": "Mine", "fishing": "Fish at", "farming": "Reap", "alchemy": "Pick"}
const STATION_NAMES := {"fire": "Cook at the fire", "forge": "Work the forge", "workbench": "Use the workbench", "cauldron": "Brew at the cauldron"}
const TALK_REACH := 3.0

var world: Node3D  # game/fantasy_world.gd

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
	if not person.is_empty():
		return "[%s] Talk to %s" % [key, person["name"]]
	var station: Dictionary = world.places.station_near(local, TALK_REACH)
	if not station.is_empty():
		return "[%s] %s" % [key, STATION_NAMES[String(station["kind"])]]
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
	if not person.is_empty():
		world.report({"type": "talk", "npc": String(person["id"])})
		talk_opened.emit(person)
		return
	var station: Dictionary = world.places.station_near(local, TALK_REACH)
	if not station.is_empty():
		station_opened.emit(String(station["kind"]))
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
	_needed = float(def["seconds"]) / (1.0 + float(_cfg["tool_speed"]) * float(maxi(spare, 0)))


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
	world.sound("gather_" + String(def["skill"]), world.world_of(at))
	world.give(String(def["gives"]), 1)
	world.gain_xp(String(def["skill"]), int(def["xp"]))
	if randf() < float(_cfg["deplete_chance"]):
		world.gather.spend(_node, float(def["respawn"]))
		_node = {}


# --- crafting ---

# Recipes of one station, the ones the player's level allows first.
func recipes(station: String) -> Array:
	var out: Array = []
	for recipe: Dictionary in world.skilling["recipes"]:
		if String(recipe["station"]) == station:
			out.append(recipe)
	return out


func recipe_text(recipe: Dictionary) -> String:
	var needs := PackedStringArray()
	for item: String in recipe["in"]:
		needs.append("%d %s" % [int(recipe["in"][item]), world.bag.item_name(item)])
	var makes := PackedStringArray()
	for item: String in recipe["out"]:
		makes.append("%s%s" % ["%d " % int(recipe["out"][item]) if int(recipe["out"][item]) > 1 else "", world.bag.item_name(item)])
	return "%s  <-  %s   (%s %d)" % [", ".join(makes), ", ".join(needs), world.skills.skill_name(String(recipe["skill"])), int(recipe["level"])]


# Why a recipe cannot be made right now ("" = it can).
func cannot_make(recipe: Dictionary) -> String:
	if int(world.skills.level(String(recipe["skill"]))) < int(recipe["level"]):
		return "Needs %s %d." % [world.skills.skill_name(String(recipe["skill"])), int(recipe["level"])]
	if not bool(world.bag.has_all(recipe["in"])):
		return "You lack the materials."
	return ""


func make(recipe: Dictionary) -> String:
	var why := cannot_make(recipe)
	if why != "":
		return why
	world.bag.take_all(recipe["in"])
	world.sound("craft_" + String(recipe["station"]))
	for item: String in recipe["out"]:
		world.give(item, int(recipe["out"][item]))
	world.gain_xp(String(recipe["skill"]), int(recipe["xp"]))
	return ""
