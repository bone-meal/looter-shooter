# Purpose: check of the dungeon puzzle rules (sea step 9a) on the test dungeon "proving_vault": push the block onto the
# plate (latching door d), pull the lever (door c), take the key, unlock door e, open the chest, save / load.
# Prints DUNGEON CHECK problems=n. Run: godot --headless --path . --script res://tools/dungeon_check.gd
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
	print("DUNGEON CHECK problems=%d" % problems)
	quit()
