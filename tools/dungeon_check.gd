# Purpose: check of the dungeon puzzle rules (sea step 9a) on the test dungeon "proving_vault": push the block onto the
# plate (latching door d), pull the lever (door c), take the key, unlock door e, open the chest, save / load.
# Prints DUNGEON CHECK problems=n. Run: godot --headless --path . --script res://tools/dungeon_check.gd
# Also the fight hall's fight and doors (sea step 9c) and The Tidewater Temple's plan (9c-2).
# Dependencies: core/sea/dungeon_rules.gd, data/sea/dungeons.json.
extends SceneTree

const DungeonRules = preload("res://core/sea/dungeon_rules.gd")

var problems := 0


func _ok(what: String, cond: bool) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		problems += 1


func _init() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/dungeons.json"))
	var r := DungeonRules.new("proving_vault", cfg["dungeons"]["proving_vault"], float(cfg["tile"]))
	_ok("map 13 x 15", r.size == Vector2i(13, 15))
	_ok("door d shut", not r.door_open("d"))
	_ok("pushed from the east it goes west", r.push_to("B", Vector2i(4, 7)) == Vector2i(2, 7))
	_ok("push from the north onto the plate", r.push("B", Vector2i(3, 6)) and r.cell_of_thing("B") == Vector2i(3, 8))
	_ok("plate pressed by the block", r.press([]) and bool(r.state["pressed"]["P"]))
	_ok("door d open (latched)", r.door_open("d") and bool(r.state["doors"].get("d", false)))
	_ok("door c shut", not r.door_open("c"))
	_ok("lever pulled", r.pull("L") and r.door_open("c"))
	_ok("door e locked, no key", not r.use_key("e"))
	_ok("key taken", r.take_key("K") and int(r.state["keys"]) == 1)
	_ok("key not taken twice", not r.take_key("K"))
	_ok("door e unlocked", r.use_key("e") and r.door_open("e") and int(r.state["keys"]) == 0)
	_ok("chest gives its loot once", r.open_chest("C") == "dungeon_small" and r.open_chest("C") == "")
	var saved := JSON.parse_string(JSON.stringify(r.to_dict())) as Dictionary
	var r2 := DungeonRules.new("proving_vault", cfg["dungeons"]["proving_vault"], float(cfg["tile"]))
	r2.from_dict(saved)
	_ok("loaded: block on the plate, doors open", r2.cell_of_thing("B") == Vector2i(3, 8) and r2.door_open("d") and r2.door_open("e") and r2.door_open("c"))
	_ok("blocked cell not passable", not r2.passable(Vector2i(3, 8)) and r2.passable(Vector2i(2, 2)))
	# sea step 9c: the fight hall: door g shut while F goes on, door h opens when F is cleared; foes keep off walls / shut doors
	var f := DungeonRules.new("fight_hall", cfg["dungeons"]["fight_hall"], float(cfg["tile"]))
	_ok("fight hall: g open, h shut", f.door_open("g") and not f.door_open("h"))
	_ok("fight starts once", f.start_fight("F") and not f.start_fight("F"))
	_ok("g shut while it goes on", not f.door_open("g") and not f.body_can(Vector2i(5, 4), 0.0))
	_ok("second wave, then none", f.next_wave("F") and not f.next_wave("F"))
	f.clear_fight("F")
	_ok("cleared: g and h open", f.door_open("g") and f.door_open("h") and f.body_can(Vector2i(5, 10), 0.0))
	_ok("cleared fight does not start again", not f.start_fight("F"))
	_ok("foes: floor yes, wall / chest no", f.body_can(Vector2i(2, 6), 0.0) and not f.body_can(Vector2i(0, 6), 0.0) and not f.body_can(Vector2i(5, 12), 0.0))
	_temple(cfg)
	print("DUNGEON CHECK problems=%d" % problems)
	quit()


# Sea step 9c-2: The Tidewater Temple: every thing a door / fight names exists, every room is reached with every door
# open, keys match the key doors, the block puzzles solve, the arena's tide rises by wave, the Great Key opens its door.
func _temple(cfg: Dictionary) -> void:
	var t := DungeonRules.new("tidewater_temple", cfg["dungeons"]["tidewater_temple"], float(cfg["tile"]))
	var bad: Array = []
	for ch: String in t.things:
		var th: Dictionary = t.things[ch]
		for k: String in ["lever", "fight", "shut_while"]:
			if th.has(k) and not t.things.has(String(th[k])):
				bad.append("%s %s" % [th.get("name", ch), k])
		for p: String in th.get("plates", []):
			if not t.things.has(p):
				bad.append("%s plate" % th.get("name", ch))
	_ok("temple: every named thing exists %s" % str(bad), bad.is_empty())
	var keys := t.of_kind("key").size()
	var key_doors := 0
	for d: String in t.of_kind("door"):
		if String(t.things[d].get("open", "")) == "key":
			key_doors += 1
	_ok("temple: keys %d = key doors %d" % [keys, key_doors], keys == key_doors)
	# every floor cell reached from the way in with every door open (pits and ledges crossed: hook / climb)
	var start: Vector2i = t.cell_of_thing(t.of_kind("arrive")[0])
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + d
			if not seen.has(n) and t.is_floor(n) and String(t.things.get(t.char_at(n), {}).get("open", "")) != "sealed":
				seen[n] = true
				todo.append(n)
	var floors := 0
	for z in t.size.y:
		for x in t.size.x:
			var cc := Vector2i(x, z)
			if t.is_floor(cc) and String(t.things.get(t.char_at(cc), {}).get("open", "")) != "sealed":
				floors += 1
	_ok("temple: all %d floor cells reached (%d)" % [floors, seen.size()], seen.size() == floors)
	_ok("temple: 7 fights", t.of_kind("fight").size() == 7)
	# the hub's block onto plate a, a player on plate b: the east door latches
	var blk := _named(t, "block_r3")
	var ok3 := t.push(blk, Vector2i(16, 15)) and t.push(blk, Vector2i(14, 16)) and t.push(blk, Vector2i(14, 15))
	t.press([Vector2i(16, 13)])
	_ok("temple: hub plates open the east door", ok3 and t.door_open(_named(t, "door_r3_east")))
	var a := _named(t, "block_r9_a")
	var b := _named(t, "block_r9_b")
	var ok9 := a != "" and t.push(b, Vector2i(10, 14)) and t.push(b, Vector2i(9, 14)) and t.push(b, Vector2i(7, 15))
	t.press([])
	_ok("temple: west blocks open the shrine door", ok9 and t.door_open(_named(t, "door_r9_r10")))
	var b19 := _named(t, "block_r19")
	var ok19 := t.push(b19, Vector2i(10, 21)) and t.push(b19, Vector2i(8, 20))
	t.press([])
	_ok("temple: shell shrine block opens its door", ok19 and t.door_open(_named(t, "door_r19_r20")))
	var arena := _named(t, "fight_arena")
	t.start_fight(arena)
	var l0 := t.flood_level(arena)
	t.next_wave(arena)
	t.next_wave(arena)
	_ok("temple: tide 0.5 -> 1.9 by wave 3, door behind shut", is_equal_approx(l0, 0.5) and is_equal_approx(t.flood_level(arena), 1.9) and not t.door_open(_named(t, "door_arena")))
	_ok("temple: arena floor flooded, a ledge climbable", t.in_flood(arena, Vector2i(24, 9)) and t.body_can(Vector2i(19, 1), 0.0, true) and not t.body_can(Vector2i(19, 1), 0.0) and is_equal_approx(t.height_of(_cell(t, "ring_arena_4")), 3.0))
	t.clear_fight(arena)
	_ok("temple: cleared: tide out, way on open", t.flood_level(arena) == 0.0 and t.door_open(_named(t, "door_arena_out")))
	var great := _named(t, "door_great")
	_ok("temple: great door shut without the Great Key", not t.use_key(great))
	_ok("temple: Great Key taken opens it", t.take_key(_named(t, "bigkey")) and t.use_key(great) and t.door_open(great) and int(t.state["keys"]) == 0)
	_ok("temple: sealed door stays shut", not t.use_key(_named(t, "door_sealed")) and not t.door_open(_named(t, "door_sealed")))


func _named(t: RefCounted, name: String) -> String:
	for ch: String in t.get("things"):
		if String(t.get("things")[ch].get("name", "")) == name:
			return ch
	return ""


func _cell(t: RefCounted, name: String) -> Vector2i:
	return t.call("cell_of_thing", _named(t, name))
