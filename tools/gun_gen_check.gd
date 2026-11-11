# Purpose: developer check of gun generation: tier distribution, validation of 20000 generated guns, tamper detection, luck shift, and one sample gun per tier with final stats. Writes tools/gun_gen_check.log and quits. Run scene tools/gun_gen_check.tscn.
# Dependencies: core/gun_db.gd, gun_gen.gd, gun_stats.gd, core/data_store.gd.
extends Node

const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const DataStore = preload("res://core/data_store.gd")
const SkillState = preload("res://core/skill_state.gd")


func _ready() -> void:
	var db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"), DataStore.load_json("res://data/gun_uniques.json"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var log: PackedStringArray = []
	var counts: Dictionary = {}
	var bad := 0
	for _i in 20000:
		var gun := GunGen.generate(db, rng)
		var why := GunGen.validate(db, gun)
		if why != "":
			bad += 1
			if bad < 5:
				log.append("INVALID %s: %s" % [JSON.stringify(gun), why])
		counts[gun["tier"]] = int(counts.get(gun["tier"], 0)) + 1
	log.append("20000 guns, invalid: %d" % bad)
	for t: Dictionary in db.tiers:
		log.append("  %-8s %5d  (%.2f%%)" % [t["id"], int(counts.get(t["id"], 0)), float(counts.get(t["id"], 0)) / 200.0])
	# luck shifts tiers up
	var lucky_counts: Dictionary = {}
	for _i in 20000:
		var t := GunGen.pick_tier(db, rng, 0.8)
		lucky_counts[t] = int(lucky_counts.get(t, 0)) + 1
	log.append("with luck 0.8:")
	for t: Dictionary in db.tiers:
		log.append("  %-8s %5d" % [t["id"], int(lucky_counts.get(t["id"], 0))])
	# tamper tests
	var g := GunGen.generate(db, rng, 0.0, "ak47", "grey")
	var tests: Array[String] = []
	var t1 := g.duplicate(true)
	t1["tier"] = "pony"
	tests.append("tier edited -> '%s'" % GunGen.validate(db, t1))
	var t2 := g.duplicate(true)
	for k: String in t2["rolls"]:
		t2["rolls"][k] = 1.0
	tests.append("roll maxed -> '%s'" % GunGen.validate(db, t2))
	var t3 := g.duplicate(true)
	t3["rolls"]["damage"] = 0.2
	t3["rolls"]["fire_rate"] = 0.2
	tests.append("extra roll -> '%s'" % GunGen.validate(db, t3))
	var t4 := g.duplicate(true)
	t4["parts"]["sight"] = {"kind": "nope", "maker": "kestrel"}
	tests.append("unknown part -> '%s'" % GunGen.validate(db, t4))
	var t5 := g.duplicate(true)
	t5["body"] = "pistol_basic"
	t5["parts"]["grip"] = {"kind": "vertical", "maker": "brawn"}
	tests.append("part not for body -> '%s'" % GunGen.validate(db, t5))
	var gs := GunGen.generate(db, rng, 0.0, "ak47", "orange")
	var t6 := gs.duplicate(true)
	t6["skills"].pop_back()
	tests.append("skill removed -> '%s'" % GunGen.validate(db, t6))
	var t7 := gs.duplicate(true)
	t7["skills"][0]["q"] = 1.5
	tests.append("skill quality out of band -> '%s'" % GunGen.validate(db, t7))
	var t8 := gs.duplicate(true)
	t8["skills"][1] = t8["skills"][0].duplicate()
	tests.append("skill repeated -> '%s'" % GunGen.validate(db, t8))
	var t9 := g.duplicate(true)
	t9["skills"] = [{"id": "nova_burst", "q": 0.5}]
	tests.append("grey gun with skill -> '%s'" % GunGen.validate(db, t9))
	var old := g.duplicate(true)
	old["v"] = 1
	old.erase("skills")
	tests.append("old v1 gun without skills legal -> '%s'" % GunGen.validate(db, old))
	var pony := GunGen.generate(db, rng, 0.0, "ak47", "pony")
	tests.append("pony skills %s cd x%s" % [JSON.stringify(pony["skills"]), db.tier("pony")["skill_cd"]])
	for e: Dictionary in pony["skills"]:
		tests.append("  %s | cd %.1f s" % [SkillState.describe(db, e), SkillState.cooldown(db, e, "pony")])
	log.append_array(tests)
	# json round trip stays valid
	var round_trip: Variant = JSON.parse_string(JSON.stringify(GunGen.generate(db, rng, 0.0, "m16", "rainbow")))
	log.append("json round trip valid: %s" % (GunGen.validate(db, round_trip as Dictionary) == ""))
	# samples
	for t: Dictionary in db.tiers:
		var gun := GunGen.generate(db, rng, 0.0, "ak47", String(t["id"]))
		var s := GunStats.final_stats(db, gun)
		log.append("%s | dmg %.1f rate %.2f mag %d reload %.2f spread %.4f recoil x%.2f crit %.0f%% buffs %s" % [GunStats.display_name(db, gun), s["damage"], s["fire_rate"], s["mag_size"], s["reload_time"], s["spread"], s["recoil"], float(s["crit_chance"]) * 100.0, JSON.stringify(s["buffs"])])
	# hand-made uniques: each must be legal, survive a save, and be refused when edited
	for id: String in db.uniques:
		var unique_gun := GunGen.unique(db, id)
		var saved: Variant = JSON.parse_string(JSON.stringify(unique_gun))
		var edited: Dictionary = unique_gun.duplicate(true)
		(edited["buffs"] as Array)[0]["id"] = "lifesteal" if String((edited["buffs"] as Array)[0]["id"]) != "lifesteal" else "free_shot"
		var u := GunStats.final_stats(db, unique_gun)
		log.append("%s | legal %s, after save %s, edited refused %s | dmg %.1f rate %.2f mag %d reload %.2f spread %.4f recoil x%.2f crit %.0f%% combos %d" % [GunStats.display_name(db, unique_gun),
			GunGen.validate(db, unique_gun) == "", GunGen.validate(db, saved as Dictionary) == "", GunGen.validate(db, edited) != "", u["damage"], u["fire_rate"], u["mag_size"], u["reload_time"], u["spread"], u["recoil"], float(u["crit_chance"]) * 100.0, (u["combos"] as Array).size()])
	var base: Dictionary = db.weapons["ak47"]
	log.append("base ak47: dmg %s rate %s mag %s reload %s spread %s" % [base["damage"], base["fire_rate"], base["mag_size"], base["reload_time"], base["spread"]])
	var f := FileAccess.open("res://tools/gun_gen_check.log", FileAccess.WRITE)
	f.store_string("\n".join(log))
	f.close()
	get_tree().quit()
