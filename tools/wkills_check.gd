# Purpose: developer check of the "W kills" gun counter (core/gun_gen.gd with data/gun_loot.json wkills_chance): about a
# quarter of rolled guns carry it, a gun with it is still legal (uniques too) and survives a save, a broken count is
# refused, a re-roll keeps it, a kill adds one, and the name says so. Log tools/wkills_check.log (WKILLS_CHECK_DONE problems=n).
# Dependencies: core/gun_db.gd, core/gun_gen.gd, core/gun_stats.gd, core/data_store.gd.
extends Node

const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const DataStore = preload("res://core/data_store.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"), DataStore.load_json("res://data/gun_uniques.json"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var with := 0
	var bad := 0
	for _i in 8000:
		var gun := GunGen.generate(db, rng)
		if gun.has("wkills"):
			with += 1
		if GunGen.validate(db, gun) != "":
			bad += 1
	_say("%d of 8000 rolled guns carry W kills (%.1f %%, data %.0f %%), all legal (%d not)" % [with, with / 80.0, db.wkills_chance * 100.0, bad], absf(with / 8000.0 - db.wkills_chance) < 0.02 and bad == 0)
	var gun := GunGen.generate(db, rng, 0.0, "ak47", "orange")
	gun["wkills"] = 0
	for _k in 142:
		GunGen.count_kill(gun)
	var saved: Variant = JSON.parse_string(JSON.stringify(gun))
	_say("142 kills counted, and the gun stays legal after a save (count %s)" % str((saved as Dictionary)["wkills"]), int(gun["wkills"]) == 142 and GunGen.validate(db, saved as Dictionary) == "")
	var broken := gun.duplicate()
	broken["wkills"] = -3
	var text := gun.duplicate()
	text["wkills"] = "lots"
	var half := gun.duplicate()
	half["wkills"] = 2.5
	_say("a broken count is refused", GunGen.validate(db, broken) != "" and GunGen.validate(db, text) != "" and GunGen.validate(db, half) != "")
	var plain := gun.duplicate()
	plain.erase("wkills")
	_say("a gun without it counts nothing", not GunGen.count_kill(plain) and not plain.has("wkills"))
	var again := GunGen.keep_wkills(gun, GunGen.generate(db, rng, 0.0, "ak47", "rainbow"))
	_say("a re-roll at the upgrade machine keeps the counter and its count", int(again.get("wkills", -1)) == 142 and GunGen.validate(db, again) == "")
	var unique_ids: Array = db.uniques.keys()
	if not unique_ids.is_empty():
		var special := GunGen.unique(db, String(unique_ids[0]))
		special["wkills"] = 7
		_say("a hand-made unique with the counter is still legal", GunGen.validate(db, special) == "")
	_say("its name starts with W kills (%s)" % GunStats.display_name(db, gun), GunStats.display_name(db, gun).begins_with("W kills ") and not GunStats.display_name(db, plain).begins_with("W kills"))

	_lines.append("WKILLS_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/wkills_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
