# Purpose: developer check of the gun part rules. Verifies the combo data (core/gun_combos.gd problems), then builds
# every possible set of parts on every gun body and checks that no two part sets give the same final stats and effects,
# and reports how many sets carry a named combo and what the factory-matched bonus does. Writes tools/gun_combo_check.log.
# Run scene tools/gun_combo_check.tscn (it quits by itself).
# Dependencies: core/gun_db.gd, core/gun_stats.gd, core/gun_combos.gd, data/gun_loot.json, gun_parts.json, manufacturers.json, weapons.json.
extends Node

const GunDb = preload("res://core/gun_db.gd")
const GunStats = preload("res://core/gun_stats.gd")
const GunCombos = preload("res://core/gun_combos.gd")


func _ready() -> void:
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"))
	var lines := PackedStringArray()
	var problems := GunCombos.problems(db)
	lines.append("combo data problems: %d %s" % [problems.size(), ", ".join(problems)])
	var total := 0
	var clashes := 0
	for body: String in db.bodies:
		var slots: Array = db.bodies[body]["slots"]
		var sets: Array = [{}]
		for slot: String in slots:  # every kind in every slot (a slot may also be empty)
			var grown: Array = []
			for partial: Dictionary in sets:
				grown.append(partial)
				for kind: String in db.parts[slot]:
					var next := partial.duplicate()
					next[slot] = {"kind": kind, "maker": "vantor"}
					grown.append(next)
			sets = grown
		var seen := {}
		var named := 0
		for parts: Dictionary in sets:
			var gun := {"body": body, "maker": "kestrel", "tier": "grey", "parts": parts, "rolls": {}, "buffs": []}
			var stats := GunStats.final_stats(db, gun)
			var combo_ids := PackedStringArray()
			for combo: Dictionary in stats["combos"]:
				combo_ids.append(String(combo["id"]))
			if not combo_ids.is_empty():
				named += 1
			var key := "%.4f|%.4f|%d|%.4f|%.5f|%.4f|%.4f|%.4f|%s|%s" % [stats["damage"], stats["fire_rate"], stats["mag_size"], stats["reload_time"],
				stats["spread"], stats["recoil"], stats["ads_fov"], stats["crit_chance"], str(stats["buffs"]), ",".join(combo_ids)]
			if seen.has(key):
				clashes += 1
				if clashes <= 5:
					lines.append("  same stats: %s  %s  vs  %s" % [body, str(_kinds(parts)), str(_kinds(seen[key]))])
			seen[key] = parts
		total += sets.size()
		lines.append("%s: %d part sets, %d different stat lines, %d with a combo" % [body, sets.size(), seen.size(), named])
	lines.append("total part sets %d, sets sharing stats with another: %d" % [total, clashes])
	var full := {}
	for slot: String in db.slots:
		full[slot] = {"kind": String((db.parts[slot] as Dictionary).keys()[0]), "maker": "brawn"}
	var own := GunStats.final_stats(db, {"body": "ak47", "maker": "brawn", "tier": "grey", "parts": full, "rolls": {}, "buffs": []})
	var mixed := GunStats.final_stats(db, {"body": "ak47", "maker": "zephyr", "tier": "grey", "parts": full, "rolls": {}, "buffs": []})
	lines.append("factory matched (5 parts by the gun's maker) vs same parts on another maker's gun: damage %.2f vs %.2f, fire rate %.2f vs %.2f" % [own["damage"], mixed["damage"], own["fire_rate"], mixed["fire_rate"]])
	var sample := {"body": "ak47", "maker": "kestrel", "tier": "grey", "rolls": {}, "buffs": [], "parts": {"barrel": {"kind": "long", "maker": "kestrel"}, "sight": {"kind": "acog", "maker": "vantor"}, "muzzle": {"kind": "silencer", "maker": "vantor"}}}
	lines.append("name sample: %s  buffs %s" % [GunStats.display_name(db, sample), str(GunStats.final_stats(db, sample)["buffs"])])
	lines.append("GUN_COMBO_CHECK_DONE")
	var f := FileAccess.open("res://tools/gun_combo_check.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("\n".join(lines))
	get_tree().quit()


func _kinds(parts: Dictionary) -> Dictionary:
	var out := {}
	for slot: String in parts:
		out[slot] = parts[slot]["kind"]
	return out


func _json(file: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % file))
