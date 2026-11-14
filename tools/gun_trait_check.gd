# Purpose: developer check of gun TRAITS (data/gun_traits.json, core/gun_gen.gd, core/gun_stats.gd; locked 2026-11-14
# diary/DECISIONS_SEA.md): how many each tier rolls, never twice, the host refuses edited traits and old guns with
# traits, final_stats gives each trait's value, every description formats. Log tools/gun_trait_check.log
# (GUN_TRAIT_CHECK_DONE problems=n).
# Dependencies: core/gun_gen.gd, core/gun_stats.gd, core/gun_db.gd, the gun data files.
extends Node

const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const GunDb = preload("res://core/gun_db.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_say("12 common traits read (+ the pony-only ones: tools/loot_1e_check)", db.common_traits().size() == 12)
	var formats := true
	for t: Dictionary in db.traits:
		formats = formats and not (String(t["desc"]) % "5").is_empty()
	_say("every trait text formats", formats)
	for tier: String in ["grey", "blue", "purple", "gold", "orange", "rainbow"]:
		var ok := true
		for i in 40:
			var gun := GunGen.generate(db, rng, 0.0, "", tier, "", 10)
			var list: Array = gun["traits"]
			var ids := {}
			for t: Dictionary in list:
				ids[String(t["id"])] = true
			ok = ok and list.size() == db.trait_count(tier) and ids.size() == list.size() and GunGen.validate(db, gun) == ""
		_say("%s guns roll %d trait(s), never twice, and pass the host" % [tier, db.trait_count(tier)], ok)
	var orange := GunGen.generate(db, rng, 0.0, "m16", "orange", "", 30)
	var stats := GunStats.final_stats(db, orange)
	_say("final_stats gives both traits a value", (stats["traits"] as Dictionary).size() == 2)
	var edited := orange.duplicate(true)
	(edited["traits"] as Array).append({"id": "ricochet", "q": 0.9})
	_say("a third trait is refused", GunGen.validate(db, edited) != "")
	edited = orange.duplicate(true)
	(edited["traits"] as Array)[1] = (edited["traits"] as Array)[0].duplicate()
	_say("the same trait twice is refused", GunGen.validate(db, edited) != "")
	edited = orange.duplicate(true)
	((edited["traits"] as Array)[0] as Dictionary)["id"] = "laser_eyes"
	_say("an unknown trait is refused", GunGen.validate(db, edited) != "")
	edited = orange.duplicate(true)
	((edited["traits"] as Array)[0] as Dictionary)["q"] = 0.1
	_say("a trait below the tier's quality is refused", GunGen.validate(db, edited) != "")
	var old := orange.duplicate(true)
	old["v"] = 2
	old.erase("lvl")
	_say("an old v2 gun with traits is refused", GunGen.validate(db, old) != "")
	old.erase("traits")
	_say("the same old gun without traits is legal", GunGen.validate(db, old) == "")
	_finish()


func _json(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % name))


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("GUN_TRAIT_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/gun_trait_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
