# Purpose: pure gun generation and checking. Rolls a gun (body, manufacturer, tier, parts, stat rolls, buffs) from a seeded RNG, and validates a gun dictionary so the host can reject edited guns.
# Dependencies: core/gun_db.gd. A gun is {"v", "body", "maker", "tier", "parts": {slot: {"kind", "maker"}}, "rolls": {stat: quality 0..1}, "buffs": [{"id", "q"}], "skills": [{"id", "q"}]}: IDs and rolled values only, so it saves and sends as plain data.
# A hand-made unique (data/gun_uniques.json) carries one more key, "unique": id, and must match that id's gun exactly.
extends RefCounted

const SkillState = preload("res://core/skill_state.gd")
const VERSION := 2  # 1 = guns from before skills existed (no "skills" key, still legal)
const EPS := 0.002


# Picks a tier id. luck >= 0 shifts weight toward higher tiers (weight x (1 + luck)^tier_index); min_tier "" = no floor, otherwise lower tiers cannot drop.
static func pick_tier(db: RefCounted, rng: RandomNumberGenerator, luck: float = 0.0, min_tier: String = "") -> String:
	var total := 0.0
	var weights: Array[float] = []
	var floor_index: int = maxi(db.tier_index(min_tier), 0) if min_tier != "" else 0
	for i in db.tiers.size():
		var w: float = float(db.tiers[i]["weight"]) * pow(1.0 + maxf(luck, 0.0), float(i))
		if i < floor_index:
			w = 0.0
		weights.append(w)
		total += w
	var pick := rng.randf() * total
	for i in weights.size():
		pick -= weights[i]
		if pick <= 0.0:
			return String(db.tiers[i]["id"])
	return String(db.tiers[db.tiers.size() - 1]["id"])


# body "" = random body, tier_id "" = rolled by pick_tier (with the min_tier floor).
static func generate(db: RefCounted, rng: RandomNumberGenerator, luck: float = 0.0, body: String = "", tier_id: String = "", min_tier: String = "") -> Dictionary:
	var body_ids: Array = db.bodies.keys()
	var body_id := body if body != "" else String(body_ids[rng.randi_range(0, body_ids.size() - 1)])
	var tid := tier_id if tier_id != "" else pick_tier(db, rng, luck, min_tier)
	var tier: Dictionary = db.tier(tid)
	var maker_ids: Array = db.makers.keys()
	var maker_id := String(maker_ids[rng.randi_range(0, maker_ids.size() - 1)])
	var q_lo: float = float(tier["quality"][0])
	var q_hi: float = float(tier["quality"][1])
	var gun := {"v": VERSION, "body": body_id, "maker": maker_id, "tier": tid, "parts": {}, "rolls": {}, "buffs": [], "skills": []}
	# parts
	var fill: float = float(tier["part_fill"])
	var gun_parts: Dictionary = gun["parts"]
	for slot: String in db.bodies[body_id]["slots"]:
		if rng.randf() > fill:
			continue
		var kinds: Array = db.parts[slot].keys()
		gun_parts[slot] = {"kind": String(kinds[rng.randi_range(0, kinds.size() - 1)]), "maker": String(maker_ids[rng.randi_range(0, maker_ids.size() - 1)])}
	# stat rolls: weighted pick without repeats, weights from the gun's manufacturer
	var pool: Array = db.stats.keys()
	var maker_weights: Dictionary = db.makers[maker_id]["roll_weights"]
	var rolls: Dictionary = gun["rolls"]
	for _n in mini(int(tier["stat_rolls"]), pool.size()):
		var stat := _weighted(pool, maker_weights, rng)
		pool.erase(stat)
		rolls[stat] = snappedf(rng.randf_range(q_lo, q_hi), 0.001)
	# buffs: weighted pick without repeats, the manufacturer's pool counts triple
	var candidates: Array = []
	for b: Dictionary in db.buffs:
		candidates.append(String(b["id"]))
	var favoured: Array = db.makers[maker_id]["buff_pool"]
	var buff_weights: Dictionary = {}
	for id: String in favoured:
		buff_weights[id] = 3.0
	var gun_buffs: Array = gun["buffs"]
	for _n in mini(int(tier["buffs"]), candidates.size()):
		var id := _weighted(candidates, buff_weights, rng)
		candidates.erase(id)
		gun_buffs.append({"id": id, "q": snappedf(rng.randf_range(q_lo, q_hi), 0.001)})
	gun["skills"] = SkillState.roll(db, rng, tid)
	if tid == String(db.tiers[db.tiers.size() - 1]["id"]) and rng.randf() < db.unique_chance:  # a top-tier drop may be a hand-made unique
		var fitting: Array = []
		for id: String in db.uniques:
			if body == "" or String(db.uniques[id]["body"]) == body:
				fitting.append(id)
		if not fitting.is_empty():
			return unique(db, String(fitting[rng.randi_range(0, fitting.size() - 1)]))
	return gun


# The one legal gun for a unique id (data/gun_uniques.json), or {} for an unknown id: top tier, the listed parts all by the
# gun's own maker, every stat rolled at the maximum, the listed buffs and skills at full quality.
static func unique(db: RefCounted, id: String) -> Dictionary:
	if not db.uniques.has(id):
		return {}
	var def: Dictionary = db.uniques[id]
	var maker := String(def["maker"])
	var gun := {"v": VERSION, "unique": id, "body": String(def["body"]), "maker": maker, "tier": String(db.tiers[db.tiers.size() - 1]["id"]), "parts": {}, "rolls": {}, "buffs": [], "skills": []}
	var kinds: Dictionary = def["parts"]
	for slot: String in kinds:
		gun["parts"][slot] = {"kind": String(kinds[slot]), "maker": maker}
	for stat: String in db.stats:
		gun["rolls"][stat] = 1.0
	for buff_id: String in def["buffs"]:
		(gun["buffs"] as Array).append({"id": buff_id, "q": 1.0})
	for skill_id: String in def["skills"]:
		(gun["skills"] as Array).append({"id": skill_id, "q": 1.0})
	return gun


static func _weighted(options: Array, weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for o: String in options:
		total += float(weights.get(o, 1.0))
	var pick := rng.randf() * total
	for o: String in options:
		pick -= float(weights.get(o, 1.0))
		if pick <= 0.0:
			return o
	return String(options[options.size() - 1])


# Returns "" when the gun is legal, otherwise a short reason. The host calls this before trusting a gun from a client or a save.
static func validate(db: RefCounted, gun: Dictionary) -> String:
	if gun.has("unique"):  # a unique is legal only as the exact gun its id stands for
		var real := unique(db, String(gun["unique"]))
		return "" if not real.is_empty() and _same(real, gun) else "unknown or edited unique"
	for key in ["v", "body", "maker", "tier", "parts", "rolls", "buffs"]:
		if not gun.has(key):
			return "missing %s" % key
	if not (gun["parts"] is Dictionary) or not (gun["rolls"] is Dictionary) or not (gun["buffs"] is Array):
		return "wrong field types"
	var version := int(gun["v"])
	if version != VERSION and version != 1:
		return "unknown version"
	if version == 1 and gun.has("skills"):
		return "old gun with skills"
	if not db.bodies.has(String(gun["body"])) or not db.makers.has(String(gun["maker"])):
		return "unknown body or maker"
	var ti: int = db.tier_index(String(gun["tier"]))
	if ti < 0:
		return "unknown tier"
	var tier: Dictionary = db.tiers[ti]
	var lo: float = float(tier["quality"][0]) - EPS
	var hi: float = float(tier["quality"][1]) + EPS
	var body_slots: Array = db.bodies[String(gun["body"])]["slots"]
	var gun_parts: Dictionary = gun["parts"]
	for slot: String in gun_parts:
		var p: Variant = gun_parts[slot]
		if not (p is Dictionary) or not body_slots.has(slot):
			return "bad part slot %s" % slot
		var pd: Dictionary = p
		if not db.parts[slot].has(String(pd.get("kind", ""))) or not db.makers.has(String(pd.get("maker", ""))):
			return "unknown part in %s" % slot
	var rolls: Dictionary = gun["rolls"]
	if rolls.size() != mini(int(tier["stat_rolls"]), db.stats.size()):
		return "wrong number of stat rolls"
	for stat: String in rolls:
		if not db.stats.has(stat):
			return "unknown stat %s" % stat
		var q: float = float(rolls[stat])
		if q < lo or q > hi:
			return "roll %s out of tier range" % stat
	var gun_buffs: Array = gun["buffs"]
	if gun_buffs.size() != int(tier["buffs"]):
		return "wrong number of buffs"
	var seen: Array[String] = []
	for b: Variant in gun_buffs:
		if not (b is Dictionary):
			return "bad buff"
		var bd: Dictionary = b
		var bid := String(bd.get("id", ""))
		if db.buff_def(bid).is_empty() or seen.has(bid):
			return "unknown or repeated buff"
		seen.append(bid)
		var bq: float = float(bd.get("q", -1.0))
		if bq < lo or bq > hi:
			return "buff out of tier range"
	if version == VERSION:
		if not gun.has("skills"):
			return "missing skills"
		return SkillState.check(db, String(gun["tier"]), gun["skills"], EPS)
	return ""


# Deep comparison that survives a save and load (JSON turns whole numbers into floats).
static func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db_: Dictionary = b
		if da.size() != db_.size():
			return false
		for key: Variant in da:
			if not db_.has(key) or not _same(da[key], db_[key]):
				return false
		return true
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not _same(aa[i], ab[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= EPS
	return typeof(a) == typeof(b) and a == b
