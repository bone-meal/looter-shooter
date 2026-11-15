# Purpose: developer check of the loot pools (data/loot_pools.json, core/loot_pool.gd) and the named uniques
# (data/gun_uniques.json): every unique builds and passes the host's check at several item levels and only names real
# parts / buffs / skills / traits / sea affixes, every pool named by a unique exists, boss pool guns never come out of
# an ordinary pony drop, and each pool drops uniques about as often as its data says. Log tools/loot_pool_check.log
# (LOOT_POOL_CHECK_DONE problems=n).
# Dependencies: core/gun_gen.gd, core/gun_db.gd, core/gun_stats.gd, core/loot_pool.gd.
extends Node

const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const GunDb = preload("res://core/gun_db.gd")
const LootPool = preload("res://core/loot_pool.gd")

var _lines: Array[String] = []
var _problems := 0


func _ready() -> void:
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	_uniques(db)
	_pools(db, rng)
	_finish()


func _uniques(db: GunDb) -> void:
	var bad: Array[String] = []
	var long_names: Array[String] = []
	for id: String in db.uniques:
		var def: Dictionary = db.uniques[id]
		var why := ""
		var body := String(def["body"])
		if not db.bodies.has(body) or not db.makers.has(String(def["maker"])):
			why = "body / maker"
		for slot: String in def["parts"]:
			if why == "" and (not (db.bodies[body]["slots"] as Array).has(slot) or not (db.parts.get(slot, {}) as Dictionary).has(String(def["parts"][slot]))):
				why = "part %s" % slot
		for b: String in def["buffs"]:
			var found := false
			for buff: Dictionary in db.buffs:
				found = found or String(buff["id"]) == b
			if why == "" and not found:
				why = "buff %s" % b
		for s: String in def["skills"]:
			if why == "" and not db.skills.has(s):
				why = "skill %s" % s
		for t: String in def.get("traits", []):
			if why == "" and (db.trait_def(t).is_empty() or String(db.trait_def(t).get("family", "")) != ""):
				why = "trait %s" % t
		if why == "" and def.has("sea") and db.sea_def(String(def["sea"])).is_empty():
			why = "sea affix"
		var pool := db.pool_of(id)
		if why == "" and not db.pools.has(pool) and not db.world_pools.has(pool):
			why = "pool %s" % pool
		for lvl: int in [1, 35, 70]:
			var gun := GunGen.unique(db, id, lvl)
			if why == "" and GunGen.validate(db, gun) != "":
				why = "level %d: %s" % [lvl, GunGen.validate(db, gun)]
		if why != "":
			bad.append("%s (%s)" % [id, why])
		var title := GunStats.display_name(db, GunGen.unique(db, id, 1))
		if title.length() > 34:
			long_names.append(title)
	_say("%d uniques build, pass the host's check at levels 1 / 35 / 70 and name only real things %s" % [db.uniques.size(), str(bad)], bad.is_empty())
	_say("every unique's title fits the card (34 letters) %s" % str(long_names), long_names.is_empty())
	var counts := {}
	for id: String in db.uniques:
		var key := "%s %s" % [db.pool_of(id), "chase" if (db.uniques[id] as Dictionary).has("red") else "plain"]
		counts[key] = int(counts.get(key, 0)) + 1
	_lines.append("     pool contents: %s" % str(counts))


func _pools(db: GunDb, rng: RandomNumberGenerator) -> void:
	var leaked := 0
	for _i in 4000:
		var gun := GunGen.generate(db, rng, 0.0, "", "pony", "", 20)
		if gun.has("unique") and not db.world_pools.has(db.pool_of(String(gun["unique"]))):
			leaked += 1
	_say("4000 pony drops: no boss / raid / vault / sea gun among them (%d leaked)" % leaked, leaked == 0)
	for pool_id: String in db.pools:
		var pool: Dictionary = db.pools[pool_id]
		var kills := 3000
		var uniques := 0
		var guns := 0
		var wrong := 0
		var low_tier := 0
		var min_index: int = db.tier_index(String(pool.get("min_tier", ""))) if String(pool.get("min_tier", "")) != "" else 0
		for _k in kills:
			for gun: Dictionary in LootPool.roll(db, rng, pool_id, 45):
				if gun.has("unique"):
					uniques += 1
					if db.pool_of(String(gun["unique"])) != pool_id:
						wrong += 1
				else:
					guns += 1
					if db.tier_index(String(gun["tier"])) < min_index:
						low_tier += 1
				if GunGen.validate(db, gun) != "" or int(gun["lvl"]) != 45:
					wrong += 1
		var has_any := not db.pool_uniques(pool_id, true).is_empty() or not db.pool_uniques(pool_id, false).is_empty()
		var expect := float(pool.get("unique_chance", 0.0)) * float(pool.get("unique_rolls", 1)) * float(kills) if has_any else 0.0
		var near := absf(float(uniques) - expect) <= maxf(4.0 * sqrt(maxf(expect, 1.0)), 3.0)
		_say("%s: %d kills -> %d guns (%d each), %d uniques (expected ~%d), none below %s, all legal at level 45 and from this pool" % [pool_id, kills, guns, int(pool.get("guns", 0)), uniques, roundi(expect), String(pool.get("min_tier", "any"))], near and wrong == 0 and low_tier == 0 and guns == kills * int(pool.get("guns", 0)))
	_say("an unknown pool drops nothing", LootPool.roll(db, rng, "nope", 10).is_empty())


func _json(shot_name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % shot_name))


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("LOOT_POOL_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/loot_pool_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
