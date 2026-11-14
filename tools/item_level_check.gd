# Purpose: developer check of item levels (core/item_level.gd, data/item_levels.json; locked diary/DECISIONS_SEA.md
# batch 5): rolled guns carry their level, the host accepts levels 1..max and old guns without one, rejects anything
# else, damage grows with the level, island and colosseum levels stop at the island cap, uniques keep their level.
# Log tools/item_level_check.log (ITEM_LEVEL_CHECK_DONE problems=n).
# Dependencies: core/item_level.gd, core/gun_gen.gd, core/gun_stats.gd, core/gun_db.gd, the gun data files.
extends Node

const ItemLevel = preload("res://core/item_level.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const GunDb = preload("res://core/gun_db.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var gun := GunGen.generate(db, rng, 0.0, "ak47", "purple", "", 15)
	_say("a rolled gun carries its level (15) and version 3", int(gun["lvl"]) == 15 and int(gun["v"]) == 3)
	_say("the host accepts it", GunGen.validate(db, gun) == "")
	var bad := gun.duplicate(true)
	bad["lvl"] = 0
	_say("level 0 is refused", GunGen.validate(db, bad) != "")
	bad["lvl"] = ItemLevel.max_level() + 1
	_say("a level above the max is refused", GunGen.validate(db, bad) != "")
	bad["lvl"] = 12.5
	_say("a broken level is refused", GunGen.validate(db, bad) != "")
	var old := gun.duplicate(true)
	old.erase("lvl")
	old.erase("traits")  # (traits came with v3 too)
	old["v"] = 2
	_say("an old v2 gun without a level is still legal (counts as level 1)", GunGen.validate(db, old) == "" and ItemLevel.of(old) == 1)
	old["lvl"] = 9
	_say("an old v2 gun WITH a level is refused", GunGen.validate(db, old) != "")
	var low := gun.duplicate(true)
	low["lvl"] = 1
	var high := gun.duplicate(true)
	high["lvl"] = 70
	var d1 := float(GunStats.final_stats(db, low)["damage"])
	var d70 := float(GunStats.final_stats(db, high)["damage"])
	_say("damage grows with the level (level 70 = %.1fx level 1)" % (d70 / d1), d70 / d1 > 10.0)
	_say("island rounds: round 1 = level 1, round 200 stops at the cap (%d)" % ItemLevel.for_round(200), ItemLevel.for_round(1) == 1 and ItemLevel.for_round(200) == int(ItemLevel.cfg()["island_cap"]))
	_say("colosseum wave 12 = level %d (at most the cap)" % ItemLevel.for_wave(12), ItemLevel.for_wave(12) <= int(ItemLevel.cfg()["island_cap"]) and ItemLevel.for_wave(1) >= 1)
	var r7 := ItemLevel.region_band(7)
	_say("sea region 7 drops levels %d-%d (ends at the max)" % [r7.x, r7.y], r7.y == ItemLevel.max_level() and ItemLevel.region_band(1).x == 1)
	if not db.uniques.is_empty():
		var id := String(db.uniques.keys()[0])
		var u := GunGen.unique(db, id, 18)
		_say("a unique at level 18 is legal", GunGen.validate(db, u) == "" and int(u["lvl"]) == 18)
		var u_old := u.duplicate(true)
		u_old.erase("lvl")
		u_old.erase("traits")
		u_old["v"] = 2
		_say("an old unique without a level is still legal", GunGen.validate(db, u_old) == "")
	_finish()


func _json(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % name))


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("ITEM_LEVEL_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/item_level_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
