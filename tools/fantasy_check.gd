# Purpose: developer check of the fantasy world's data and pure rules, no graphics: every id that one file mentions
# exists in the file that defines it, the spell rules resolve the director's examples and every secret, the whole
# quest line can be played to its end in order (simulated), the level curve against the quest rewards, and what the
# terrain looks like in numbers. Writes tools/fantasy_check.log. Run scene tools/fantasy_check.tscn.
# It also lists every text the writers' files are missing, checks the fishing waters, the boss moves and that every
# model a layout names exists, and lays out every place once to count what stands there. Round 4: every town gate
# can be walked through, walls have no other holes, nothing blocks the way into a room.
# Dependencies: core/fantasy_data.gd (rules + writers' text), spell_book.gd, skill_levels.gd, fantasy_bag.gd,
# quest_log.gd, fantasy_terrain.gd, fantasy_layout.gd.
extends Node

const SpellBook = preload("res://core/spell_book.gd")
const CombatRules = preload("res://core/combat_rules.gd")
const GroundRules = preload("res://core/ground_rules.gd")
const SkillLevels = preload("res://core/skill_levels.gd")
const FantasyBag = preload("res://core/fantasy_bag.gd")
const QuestLog = preload("res://core/quest_log.gd")
const FantasyTerrain = preload("res://core/fantasy_terrain.gd")
const FantasyLayout = preload("res://core/fantasy_layout.gd")
const FantasyData = preload("res://core/fantasy_data.gd")
const FantasyInteriors = preload("res://core/fantasy_interiors.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var all := FantasyData.load_all()
	var spells: Dictionary = all["spells"]
	var skilling: Dictionary = all["skilling"]
	var gear: Dictionary = all["gear"]
	var quests: Dictionary = all["quests"]
	var world: Dictionary = all["world"]
	var enemies: Dictionary = all["enemies"]["enemies"]
	for missing: String in all["problems"]:
		_need(false, "writing: " + missing)
	_lines.append("writers' files: %d sections read" % _count_sections(all["text"]))
	_check_round_two(all)
	var items: Dictionary = gear["items"]
	# --- references between files ---
	for id: String in skilling["nodes"]:
		var node: Dictionary = skilling["nodes"][id]
		_need(items.has(String(node["gives"])), "node %s gives unknown item %s" % [id, node["gives"]])
		_need((skilling["skills"] as Dictionary).has(String(node["skill"])), "node %s uses unknown skill" % id)
	for recipe: Dictionary in skilling["recipes"]:
		for id: String in (recipe["in"] as Dictionary).keys() + (recipe["out"] as Dictionary).keys():
			_need(items.has(id), "recipe %s uses unknown item %s" % [recipe["id"], id])
	for log_id: String in skilling["fire"]["xp_per_log"]:
		_need(items.has(log_id), "fire uses unknown log %s" % log_id)
	for id: String in enemies:
		for drop: String in enemies[id]["drops"]:
			_need(items.has(drop), "enemy %s drops unknown item %s" % [id, drop])
	var place_ids := {}
	for p: Dictionary in world["places"]:
		place_ids[String(p["id"])] = true
		if p.has("boss"):
			_need(enemies.has(String(p["boss"])), "place %s has unknown boss" % p["id"])
	var npc_ids := {}
	for npc: Dictionary in world["npcs"]:
		npc_ids[String(npc["id"])] = true
		_need(place_ids.has(String(npc["place"])), "npc %s stands at unknown place" % npc["id"])
	for region: Dictionary in world["regions"]:
		for id: String in region["enemies"]:
			_need(enemies.has(id), "region %s lists unknown enemy %s" % [region["id"], id])
		for id: String in region["nodes"]:
			_need((skilling["nodes"] as Dictionary).has(id), "region %s lists unknown node %s" % [region["id"], id])
	var book := SpellBook.new(spells)
	for problem in book.problems():
		_need(false, problem)
	for quest: Dictionary in quests["quests"]:
		_need(npc_ids.has(String(quest["giver"])), "quest %s has unknown giver" % quest["id"])
		for s: Dictionary in quest["steps"]:
			match String(s["type"]):
				"talk": _need(npc_ids.has(String(s["npc"])), "quest %s talks to unknown npc" % quest["id"])
				"kill": _need(enemies.has(String(s["enemy"])), "quest %s kills unknown enemy %s" % [quest["id"], s["enemy"]])
				"have": _need(items.has(String(s["item"])), "quest %s wants unknown item %s" % [quest["id"], s["item"]])
				"reach": _need(place_ids.has(String(s["place"])), "quest %s reaches unknown place" % quest["id"])
				"skill": _need((skilling["skills"] as Dictionary).has(String(s["skill"])), "quest %s wants unknown skill" % quest["id"])
				"cast":
					if s.has("secret"):
						_need(not book.secret_for(_secret_sequence(spells, String(s["secret"]))).is_empty(), "quest %s casts unknown secret" % quest["id"])
					elif s.has("substance"):
						_need((spells["substances"] as Dictionary).has(String(s["substance"])), "quest %s casts unknown substance" % quest["id"])
		var rewards: Dictionary = quest["rewards"]
		for id: String in rewards.get("items", {}):
			_need(items.has(id), "quest %s rewards unknown item %s" % [quest["id"], id])
		if rewards.has("secret"):
			_need(_secret_sequence(spells, String(rewards["secret"])) != "", "quest %s teaches unknown secret" % quest["id"])
	_lines.append("data problems: %d" % _problems)
	# --- spells: the director's examples and the secrets ---
	for sequence: String in ["W", "WWW", "WFA", "FWA", "AFW", "EEF", "AAAAA", "WFEA", "AWAAWAWWA"]:
		var spell := book.resolve(sequence)
		_lines.append("spell %-10s -> %-18s %-7s dmg %.0f heal %.0f mana %.0f %s" % [sequence, spell["name"], spell["kind"], spell["damage"], spell["heal"], spell["mana"], "(secret)" if String(spell["secret"]) != "" else ""])
	var names := {}
	for a: String in ["W", "F", "E", "A"]:
		for b: String in ["", "W", "F", "E", "A"]:
			for c: String in ["", "W", "F", "E", "A"]:
				for d: String in ["", "W", "F", "E", "A"]:
					names[String(book.resolve(a + b + c + d)["name"])] = true
	_lines.append("different spell names from up to 4 elements: %d; secrets: %d" % [names.size(), (spells["secrets"] as Array).size()])
	# --- quests: play the whole line in order ---
	var log := QuestLog.new(quests)
	var skills := SkillLevels.new(skilling)
	var total_xp := 0
	var finished := 0
	var guard := 0
	while guard < 200:
		guard += 1
		var started := false
		for id in log.ids():
			if log.can_start(id):
				log.start(id)
				started = true
		for id: String in log.active.keys():
			var steps_left := 50
			while log.active.has(id) and steps_left > 0:
				steps_left -= 1
				var s := log.step(id)
				var changes: Array = []
				match String(s["type"]):
					"have": changes = log.check({String(s["item"]): int(s["count"])}, {})
					"skill": changes = log.check({}, {String(s["skill"]): int(s["level"])})
					"kill":
						for _n in int(s["count"]):
							total_xp += int(enemies[String(s["enemy"])]["xp"])
							changes = log.note({"type": "kill", "enemy": s["enemy"]})
					"cast":
						for _n in int(s["count"]):
							changes = log.note({"type": "cast", "sequence": s.get("sequence", ""), "substance": s.get("substance", ""), "secret": s.get("secret", "")})
					"talk": changes = log.note({"type": "talk", "npc": s["npc"]})
					"reach": changes = log.note({"type": "reach", "place": s["place"]})
					"fire": changes = log.note({"type": "fire"})
				for change: Dictionary in changes:
					if bool(change["finished"]):
						finished += 1
						total_xp += int((change["rewards"] as Dictionary).get("xp", 0))
						if (change["rewards"] as Dictionary).has("pigment") or int(log.quest(String(change["quest"]))["chapter"]) == 8:
							skills.xp["magic"] = total_xp
							_lines.append("after %s (%s): Magic xp %d = level %d, advised %d, slots from story %d" % [change["quest"], log.quest(String(change["quest"]))["name"], total_xp, skills.level("magic"), int(log.quest(String(change["quest"])).get("level", 0)), log.pigments()])
		if not started and log.active.is_empty():
			break
	_lines.append("quests finished %d of %d; guns unlocked %s; secrets taught %d; chapter now %d" % [finished, log.ids().size(), str(log.guns_unlocked()), log.secrets().size(), log.chapter()])
	var saved: Variant = JSON.parse_string(JSON.stringify(log.to_dict()))
	var again := QuestLog.new(quests)
	again.from_dict(saved)
	_lines.append("quest log survives a save: %s; edited save (last quest only) keeps %d quests" % [str(again.done.size() == log.done.size()), _edited_keeps(quests)])
	# --- skills and bag ---
	_lines.append("xp for level 2 / 10 / 25 / 50: %d / %d / %d / %d" % [skills.xp_for(2), skills.xp_for(10), skills.xp_for(25), skills.xp_for(50)])
	var bag := FantasyBag.new(gear)
	bag.add("oak_staff")
	bag.add("iron_axe")
	_lines.append("bag: starts with %s; better staff and axe equip themselves: %s, axe tier %d" % [str(bag.to_dict()["items"]), bag.equipped["staff"], bag.tool_tier("axe")])
	# --- terrain ---
	var terrain := FantasyTerrain.new(world)
	for region: Dictionary in world["regions"]:
		var lo := INF
		var hi := -INF
		for i in 200:
			var a := float(i) * 2.399
			var r := float(region["radius"]) * sqrt(float(i) / 200.0)
			var h := terrain.height(float(region["center"][0]) + cos(a) * r, float(region["center"][1]) + sin(a) * r)
			lo = minf(lo, h)
			hi = maxf(hi, h)
		_lines.append("terrain %-13s height %.1f .. %.1f m, level at heart %d" % [region["id"], lo, hi, terrain.level_at(float(region["center"][0]), float(region["center"][1]))])
	var spawn: Array = world["spawn"]
	_lines.append("spawn height %.1f m in %s; corner of the map %.1f m (sea level %.1f)" % [terrain.height(float(spawn[0]), float(spawn[1])), terrain.region_at(float(spawn[0]), float(spawn[1]))["id"], terrain.height(990, 990), terrain.sea])
	_lines.append("FANTASY_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/fantasy_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	print("\n".join(_lines))
	get_tree().quit()


func _edited_keeps(quests: Dictionary) -> int:
	var log := QuestLog.new(quests)
	log.from_dict({"done": ["m34"], "active": {}})
	return log.done.size()


func _secret_sequence(spells: Dictionary, id: String) -> String:
	for secret: Dictionary in spells["secrets"]:
		if String(secret["id"]) == id:
			return String(secret["sequence"])
	return ""


func _need(ok: bool, what: String) -> void:
	if not ok:
		_problems += 1
		_lines.append("PROBLEM: " + what)


func _count_sections(text: Dictionary) -> int:
	var n := 0
	for kind: String in text:
		n += (text[kind] as Dictionary).size()
	return n


# The combat tools: the numbers are all there and the rules do what the data file says.
func _check_combat(combat: Dictionary) -> void:
	for part: String in ["dodge", "ward", "weakness", "strike", "words"]:
		_need(combat.has(part), "combat.json has no %s" % part)
	var ward: Dictionary = combat["ward"]
	var late := CombatRules.ward(ward, 20.0, 5.0, true, 100.0)
	_need(is_equal_approx(float(late["taken"]), 20.0 * (1.0 - float(ward["block"]))) and is_equal_approx(float(late["mana"]), 20.0 * float(ward["block"]) * float(ward["mana_per_damage"])), "a held ward does not block what the data says")
	var timed := CombatRules.ward(ward, 20.0, 0.0, true, 0.0)
	_need(bool(timed["perfect"]) and float(timed["taken"]) == 0.0 and float(timed["mana"]) == 0.0, "a just-in-time ward is not free and whole")
	_need(float(CombatRules.ward(ward, 20.0, 5.0, false, 100.0)["taken"]) == 20.0, "a ward stops a hit from behind")
	_need(float(CombatRules.ward(ward, 20.0, 5.0, true, 0.0)["taken"]) == 20.0, "a ward with no mana still blocks")
	_need(CombatRules.in_front(Vector2(0, -1), Vector2(0.2, -1), float(ward["arc_deg"])) and not CombatRules.in_front(Vector2(0, -1), Vector2(0, 1), float(ward["arc_deg"])), "the ward's arc is wrong")
	var weakness: Dictionary = combat["weakness"]
	_need(String(CombatRules.elements(weakness, "FW", "F", "W")["kind"]) == "weak", "a weak element in the mix does not count")
	_need(String(CombatRules.elements(weakness, "W", "F", "W")["kind"]) == "strong" and String(CombatRules.elements(weakness, "E", "F", "W")["kind"]) == "", "strong / plain elements are judged wrong")
	for key: String in ["weak", "strong", "perfect"]:
		_need(String(combat["words"].get(key, "")) != "", "no combat word for %s" % key)


# What spells leave on the ground: the rules agree with the data file, and plain spells leave what one expects.
func _check_ground(ground: Dictionary, spells: Dictionary) -> void:
	for part: String in ["spikes", "fire", "water", "shock"]:
		_need(ground.has(part), "ground.json has no %s" % part)
	var water: Dictionary = ground["water"]
	_need(is_equal_approx(GroundRules.pooled(water, 3.0, 4.0), 5.0), "two puddles do not add their areas")
	_need(GroundRules.pooled(water, 50.0, 50.0) == float(water["max_radius"]), "a flood grows past its cap")
	_need(GroundRules.boiled(water, 3.0, 5.0) == 0.0 and GroundRules.boiled(water, 5.0, 3.0) == 4.0, "fire boils a puddle wrongly")
	_need(GroundRules.flooded(water, float(water["flood_radius"])) and not GroundRules.flooded(water, float(water["min_radius"])), "flood size is judged wrong")
	var book := SpellBook.new(spells)
	var expect := {"E": ["spikes"], "EF": ["fire"], "W": ["water"], "FW": [], "AF": ["shock"], "A": []}
	for sequence: String in expect:
		var left := GroundRules.leaves(ground, book.resolve(sequence))
		_need(Array(left) == expect[sequence], "spell %s leaves %s on the ground, expected %s" % [sequence, str(left), str(expect[sequence])])
	var leaving := 0
	for secret: Dictionary in spells["secrets"]:
		if not GroundRules.leaves(ground, book.resolve(String(secret["sequence"]))).is_empty():
			leaving += 1
	print("ground: %d of %d secret spells leave something on the ground" % [leaving, (spells["secrets"] as Array).size()])


# Fishing waters, boss moves, tribes, layouts.
func _check_round_two(all: Dictionary) -> void:
	var world: Dictionary = all["world"]
	var nodes: Dictionary = all["skilling"]["nodes"]
	var enemies: Dictionary = all["enemies"]["enemies"]
	for region: Dictionary in world["regions"]:
		for water: String in ["fresh", "salt"]:
			var id := String(region["fish"].get(water, ""))
			if id != "":
				_need(nodes.has(id), "region %s fishes unknown node %s" % [region["id"], id])
				_need(not nodes.has(id) or String(nodes[id].get("water", "")) in [water, "lava"], "region %s: %s is not a %s water spot" % [region["id"], id, water])
	var kinds := ["slam", "charge", "summon", "zones", "volley", "pull", "rain", "beam", "blink"]
	var bosses := 0
	for id: String in enemies:
		var moves: Array = enemies[id].get("moves", [])
		if bool(enemies[id].get("boss", false)):
			bosses += 1
			_need(moves.size() >= 2, "boss %s has fewer than two special attacks" % id)
		for move: Dictionary in moves:
			_need(String(move["kind"]) in kinds, "%s: unknown move kind %s" % [id, move["kind"]])
			_need(String(move["kind"]) != "summon" or enemies.has(String(move.get("enemy", ""))), "%s summons an unknown creature" % id)
		_need(String(enemies[id].get("walks", "")) in ["land", "swim", "fly"], "enemy %s has no way of moving" % id)
		var weak := String(enemies[id].get("weak", ""))
		var strong := String(enemies[id].get("strong", ""))
		_need(all["spells"]["elements"].has(weak) and all["spells"]["elements"].has(strong) and weak != strong, "enemy %s needs a weak and a different strong element" % id)
	_check_combat(all["combat"])
	_check_ground(all["ground"], all["spells"])
	var tribes: Dictionary = all["enemies"]["tribes"]
	for banner: String in tribes["camps"]:
		_need(enemies.has(banner + "_warrior"), "tribe %s has no warrior" % banner)
	var terrain := FantasyTerrain.new(world)
	var layout := FantasyLayout.new(terrain, all["layouts"], all["props"], nodes)
	layout.interiors = FantasyInteriors.new(all["interiors"], all["props"])  # before anything is laid out: walk-in houses get their furniture
	var props: Dictionary = all["props"]
	var total := 0
	for place: Dictionary in world["places"]:
		var items := layout.place_items(place)
		total += items.size()
		for item: Dictionary in items:
			_need(props.has(String(item["model"])), "place %s uses a model without a size: %s" % [place["id"], item["model"]])
			_need(FileAccess.file_exists("res://assets/models/fantasy/%s.gltf" % item["model"]), "missing model file %s" % item["model"])
		_lines.append("  %-16s %-13s %3d things" % [place["id"], place["kind"], items.size()])
	# interiors: every room's furniture is a model, every loot table gives known items, the main story has its walk-in houses
	var inside: Dictionary = all["interiors"]
	var items: Dictionary = all["gear"]["items"]
	for kind: String in inside["rooms"]:
		for piece: Dictionary in inside["rooms"][kind]["items"]:
			_need(props.has(String(piece["model"])), "room %s uses unknown model %s" % [kind, piece["model"]])
			_need(not piece.has("loot") or (inside["loot"] as Dictionary).has(piece["loot"]), "room %s uses unknown loot table %s" % [kind, piece.get("loot", "")])
	for table: String in inside["loot"]:
		for id: String in inside["loot"][table]["items"]:
			_need(items.has(id), "loot table %s gives unknown item %s" % [table, id])
	for start: String in inside["buildings"]:
		for kind: String in inside["buildings"][start]:
			_need((inside["rooms"] as Dictionary).has(kind), "building %s is an unknown kind of room %s" % [start, kind])
	var rules: FantasyInteriors = layout.interiors
	var doors := 0
	var walk_ins := 0
	var chests := 0
	for place: Dictionary in world["places"]:
		var own := 0
		for item: Dictionary in layout.place_items(place):
			if rules.walk_in(String(item["model"])):
				own += 1
			elif not bool(item.get("inside", false)) and rules.kind_of(String(item["model"]), float(item["x"]), float(item["z"])) != "":
				doors += 1
			if String(item.get("loot", "")) != "":
				chests += 1
		walk_ins += own
		var story := false
		for npc: Dictionary in world["npcs"]:
			if bool(npc.get("indoors", false)) and String(npc["place"]) == String(place["id"]):
				story = true
		_need(not story or own == 1, "place %s needs exactly one walk-in house for its main-story people (has %d)" % [place["id"], own])
	_lines.append("interiors: %d walk-in houses with %d containers, %d buildings with a door to a room, %d kinds of room, %d loot tables" % [walk_ins, chests, doors, (inside["rooms"] as Dictionary).size(), (inside["loot"] as Dictionary).size()])
	var spots := {"fresh": 0, "salt": 0, "lava": 0}
	var sites := 0
	for cz in range(-8, 9):
		for cx in range(-8, 9):
			if not layout.site(Vector2i(cx, cz)).is_empty():
				sites += 1
	for kz in range(-20, 21):
		for kx in range(-20, 21):
			for entry: Array in layout.nodes(Vector2i(kx, kz)):
				var water := String(nodes[String(entry[1])].get("water", ""))
				if water != "":
					spots[water] = int(spots[water]) + 1
	_lines.append("layout: %d things in %d places, %d roadside sites, fishing spots %s, %d bosses with special attacks" % [total, (world["places"] as Array).size(), sites, str(spots), bosses])
	_need(int(spots["fresh"]) > 0 and int(spots["salt"]) > 0, "no fishing spots were placed on fresh or salt water")
	_check_ways(all, layout)
	# every fantasy sound can be found (and muted) on the Sounds page of the settings
	var listed := {}
	for group: Dictionary in (JSON.parse_string(FileAccess.get_file_as_string("res://data/sound_list.json")) as Dictionary)["groups"]:
		for sound: Dictionary in group["sounds"]:
			listed[String(sound["id"])] = true
	for id: String in all["sounds"]["sounds"]:
		_need(listed.has(id), "sound %s is missing from data/sound_list.json" % id)
	for id: String in all["sounds"]["ambience"]:
		_need(listed.has("ambience_" + id), "ambience %s is missing from data/sound_list.json" % id)


# Round 4: what can be bumped into. Every gate of a walled place can be walked through and there is no other way
# through its wall; no furniture stands where a room is entered; how many slits between buildings were closed.
func _check_ways(all: Dictionary, layout: FantasyLayout) -> void:
	var world: Dictionary = all["world"]
	var props: Dictionary = all["props"]
	var closed := 0
	var began := Time.get_ticks_msec()
	for place: Dictionary in world["places"]:
		closed += layout.plugs(String(place["id"]), layout.place_items(place)).size()
		for rule: Dictionary in all["layouts"]["kinds"].get(String(place["kind"]), []):
			if not rule.has("wall") or int(rule.get("gates", 0)) == 0:
				continue
			var cx := float(place["pos"][0])
			var cz := float(place["pos"][1])
			var radius := float(rule["ring"]) * float(place["flat"])
			var gates := int(rule["gates"])
			for k in gates:
				var a := PI / 2.0 + float(k) * TAU / float(gates)
				var stopped := 0
				for step in range(-14, 15):  # 7 m each side of the wall
					var r := radius + float(step) * 0.5
					if layout.push_out(cx + cos(a) * r, cz + sin(a) * r, 0.45).distance_to(Vector2(cx + cos(a) * r, cz + sin(a) * r)) > 0.01:
						stopped += 1
				_need(stopped == 0, "%s: gate %d cannot be walked through (%d blocked steps)" % [place["id"], k, stopped])
			var gate: Dictionary = props[String(rule["gate"])]
			var passage := float(gate["w"]) * 0.5
			var leaks := 0
			var steps := int(TAU * radius / 0.2)
			for i in steps:
				var a := float(i) * TAU / float(steps)
				var by_gate := false
				for k in gates:
					if absf(angle_difference(a, PI / 2.0 + float(k) * TAU / float(gates))) * radius < passage:
						by_gate = true
				var x := cx + cos(a) * radius
				var z := cz + sin(a) * radius
				if not by_gate and layout.terrain.water_at(x, z) == "" and layout.push_out(x, z, 0.4).distance_to(Vector2(x, z)) < 0.01:
					leaks += 1
			_need(leaks == 0, "%s: the wall has %d holes that are not gates" % [place["id"], leaks])
	_lines.append("ways: %d slits between buildings closed with posts (worked out in %d ms for all places)" % [closed, Time.get_ticks_msec() - began])
	var rules: FantasyInteriors = layout.interiors
	var inside: Dictionary = all["interiors"]
	var left_out := 0
	var rooms := 0
	for model: String in props:  # every building that has a room, at the size its room really is
		var kinds := {}
		for start: String in inside["buildings"]:
			if model.begins_with(start) and not rules.walk_in(model):
				for kind: String in inside["buildings"][start]:
					kinds[kind] = true
		var half := rules.half_size(model)
		for kind: String in kinds:
			rooms += 1
			for piece: Dictionary in rules.furniture(kind, half):
				if layout.covers(piece, rules.entry(half), 0.5):
					left_out += 1
					_need(String(piece["loot"]) == "" and String(piece["station"]) == "", "room %s in %s: %s stands where the room is entered" % [kind, model, piece["model"]])
	_lines.append("rooms: %d building and room pairs; %d plain pieces of furniture are left out because they would stand in the way in" % [rooms, left_out])
