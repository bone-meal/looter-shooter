# Purpose: developer check of gun drop rules: drops per kill and tier mix by wave, boss/elite floors, elite frequency and affix stats. Writes tools/drop_check.log and quits. Run scene tools/drop_check.tscn.
# Dependencies: core/drop_rules.gd, core/gun_db.gd, core/gun_gen.gd, core/data_store.gd.
extends Node

const DropRules = preload("res://core/drop_rules.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const DataStore = preload("res://core/data_store.gd")


func _ready() -> void:
	var db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"))
	var cfg: Dictionary = DataStore.load_json("res://data/drops.json")
	var enemies: Dictionary = DataStore.load_json("res://data/enemies.json")["enemies"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var log: PackedStringArray = []
	for wave in [1, 2, 3, 4]:
		var drops := 0
		var tally: Dictionary = {}
		var elites := 0
		var kills := 10000
		for _i in kills:
			var affix := DropRules.roll_elite(cfg, rng, "chaser", wave)
			if not affix.is_empty():
				elites += 1
			for g: Dictionary in DropRules.roll_drops(db, cfg, rng, "chaser", not affix.is_empty(), wave):
				drops += 1
				tally[g["tier"]] = int(tally.get(g["tier"], 0)) + 1
				if GunGen.validate(db, g) != "":
					log.append("INVALID drop")
		log.append("wave %d luck %.2f: %d chaser kills -> %d guns (%.1f%%), elites %.1f%%, tiers %s" % [wave, DropRules.wave_luck(cfg, wave), kills, drops, float(drops) / 100.0, float(elites) / 100.0, JSON.stringify(tally)])
	var boss_below := 0
	for _i in 2000:
		for g: Dictionary in DropRules.roll_drops(db, cfg, rng, "boss", false, 4):
			if db.tier_index(String(g["tier"])) < db.tier_index("purple"):
				boss_below += 1
	log.append("boss drops below purple in 2000 kills: %d" % boss_below)
	var boss_affix := DropRules.roll_elite(cfg, rng, "boss", 4)
	log.append("boss never elite: %s" % boss_affix.is_empty())
	var wave1_elite := 0
	for _i in 2000:
		if not DropRules.roll_elite(cfg, rng, "chaser", 1).is_empty():
			wave1_elite += 1
	log.append("wave 1 elites (expected 0): %d" % wave1_elite)
	for a: Dictionary in cfg["elite"]["affixes"]:
		var s := DropRules.apply_affix(enemies["chaser"], a)
		log.append("%s chaser: hp %.0f speed %.1f damage %.1f size %s (base hp 40 speed 4.5 dmg 8)" % [a["name"], s["max_hp"], s["speed"], s["damage"], JSON.stringify(s["size"])])
	var f := FileAccess.open("res://tools/drop_check.log", FileAccess.WRITE)
	f.store_string("\n".join(log))
	f.close()
	get_tree().quit()
