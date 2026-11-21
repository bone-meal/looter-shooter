# Purpose: pure gun generation and checking. Rolls a gun (body, manufacturer, tier, parts, stat rolls, buffs) from a seeded RNG, and validates a gun dictionary so the host can reject edited guns.
# Dependencies: core/gun_db.gd, core/item_level.gd. A gun is {"v", "lvl", "body", "maker", "tier", "parts": {slot: {"kind", "maker"}}, "rolls": {stat: quality 0..1}, "buffs": [{"id", "q"}], "skills": [{"id", "q"}], "traits": [{"id", "q"}]}: IDs and rolled values only, so it saves and sends as plain data. "lvl" = item level and "traits" = the big effects (both v3 on; older guns count as level 1 with no traits).
# A hand-made unique (data/gun_uniques.json) carries one more key, "unique": id, and must match that id's gun exactly.
extends RefCounted

const SkillState = preload("res://core/skill_state.gd")
const ItemLevel = preload("res://core/item_level.gd")
const CamoChallenges = preload("res://core/camo_challenges.gd")
const WKILLS_MAX := 9999999  # the counter shows 7 digits
const RECORD_MAX := 1e12  # Fish Story's biggest hit can be no bigger
const OWNERS_MAX := 8  # (polish1 item 63) previous owners a gold+ gun remembers
const OWNER_NAME_MAX := 24
const VERSION := 4  # 4 = pony "family" + "sea" affix; 3 = item level "lvl" + traits; 2 = skills without a level; 1 = before skills (all still legal)
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


# body "" = random body, tier_id "" = rolled by pick_tier (with the min_tier floor); lvl = the item level where it drops;
# maker "" = a random manufacturer (a colosseum banner names one).
static func generate(db: RefCounted, rng: RandomNumberGenerator, luck: float = 0.0, body: String = "", tier_id: String = "", min_tier: String = "", lvl: int = 1, maker: String = "") -> Dictionary:
	var body_ids: Array = db.bodies.keys()
	var body_id := body if body != "" else String(body_ids[rng.randi_range(0, body_ids.size() - 1)])
	var tid := tier_id if tier_id != "" else pick_tier(db, rng, luck, min_tier)
	var tier: Dictionary = db.tier(tid)
	var maker_ids: Array = db.makers.keys()
	var maker_id := maker if db.makers.has(maker) else String(maker_ids[rng.randi_range(0, maker_ids.size() - 1)])
	var q_lo: float = float(tier["quality"][0])
	var q_hi: float = float(tier["quality"][1])
	var gun := {"v": VERSION, "lvl": clampi(lvl, 1, ItemLevel.max_level()), "body": body_id, "maker": maker_id, "tier": tid, "parts": {}, "rolls": {}, "buffs": [], "skills": [], "traits": []}
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
	var trait_pool: Array = db.common_traits()  # traits: the big effects, purple and up (data/gun_traits.json)
	var wanted: int = db.trait_count(tid)
	if is_pony(db, tid) and not db.families.is_empty():  # a pony belongs to a family: its first trait is one of the family's own
		var family_ids: Array = db.families.keys()
		var family := String(family_ids[rng.randi_range(0, family_ids.size() - 1)])
		gun["family"] = family
		var own: Array = db.family_def(family)["traits"]
		if wanted > 0:
			(gun["traits"] as Array).append({"id": String(own[rng.randi_range(0, own.size() - 1)]), "q": snappedf(rng.randf_range(q_lo, q_hi), 0.001)})
			wanted -= 1
	for _n in mini(wanted, trait_pool.size()):
		var trait_id := String(trait_pool[rng.randi_range(0, trait_pool.size() - 1)])
		trait_pool.erase(trait_id)
		(gun["traits"] as Array).append({"id": trait_id, "q": snappedf(rng.randf_range(q_lo, q_hi), 0.001)})
	if rng.randf() < db.sea_chance(int(gun["lvl"])):  # late-region guns: a sea affix (data/sea_affixes.json)
		var affix_ids: Array = (db.sea.get("affixes", {}) as Dictionary).keys()
		if not affix_ids.is_empty():
			gun["sea"] = {"id": String(affix_ids[rng.randi_range(0, affix_ids.size() - 1)]), "q": snappedf(rng.randf_range(q_lo, q_hi), 0.001)}
	if tid == String(db.tiers[db.tiers.size() - 1]["id"]) and rng.randf() < db.unique_chance:  # a top-tier drop may be a hand-made unique
		var fitting: Array = db.world_uniques(body)  # a boss's pool guns drop only from that boss (data/loot_pools.json)
		if not fitting.is_empty():
			gun = unique(db, String(fitting[rng.randi_range(0, fitting.size() - 1)]), int(gun["lvl"]))
	if rng.randf() < db.wkills_chance:
		gun["wkills"] = 0  # the "W kills" counter: kills made with it are counted on it (kept through re-rolls: keep_wkills)
	return gun


# A newly rolled gun that replaces `old` (the upgrade machine): it keeps old's W kills counter and its count.
# (Its level is the new roll's own.)
static func keep_wkills(old: Dictionary, made: Dictionary) -> Dictionary:
	if old.has("wkills"):
		made["wkills"] = int(old["wkills"])
	return made


# (polish1 item 63) A gun changing hands in a trade: its W kills counter starts again at 0 for the new owner; from gold
# up the gun keeps a PREVIOUS-OWNER history (the last OWNERS_MAX: {"n": name, "k": kills}). Returns the gun to keep.
static func hand_over(db: RefCounted, gun: Dictionary, from_name: String) -> Dictionary:
	var out := gun.duplicate(true)
	if not out.has("wkills"):
		return out
	if db.tier_index(String(out.get("tier", ""))) >= db.tier_index("gold"):
		var past: Array = out.get("owners", [])
		past.append({"n": from_name.left(OWNER_NAME_MAX), "k": int(out["wkills"])})
		while past.size() > OWNERS_MAX:
			past.pop_front()
		out["owners"] = past
	out["wkills"] = 0
	return out


# One more kill made with this gun; false when it has no counter.
static func count_kill(gun: Dictionary) -> bool:
	if not gun.has("wkills"):
		return false
	gun["wkills"] = mini(int(gun["wkills"]) + 1, WKILLS_MAX)
	return true


# The one legal gun for a unique id (data/gun_uniques.json) at item level lvl, or {} for an unknown id: top tier, the
# listed parts all by the gun's own maker, every stat rolled at the maximum, the listed buffs and skills at full quality.
static func unique(db: RefCounted, id: String, lvl: int = 1) -> Dictionary:
	if not db.uniques.has(id):
		return {}
	var def: Dictionary = db.uniques[id]
	var maker := String(def["maker"])
	var gun := {"v": VERSION, "lvl": clampi(lvl, 1, ItemLevel.max_level()), "unique": id, "body": String(def["body"]), "maker": maker, "tier": String(db.tiers[db.tiers.size() - 1]["id"]), "parts": {}, "rolls": {}, "buffs": [], "skills": [], "traits": []}
	var kinds: Dictionary = def["parts"]
	for slot: String in kinds:
		gun["parts"][slot] = {"kind": String(kinds[slot]), "maker": maker}
	for stat: String in db.stats:
		gun["rolls"][stat] = 1.0
	for buff_id: String in def["buffs"]:
		(gun["buffs"] as Array).append({"id": buff_id, "q": 1.0})
	for skill_id: String in def["skills"]:
		(gun["skills"] as Array).append({"id": skill_id, "q": 1.0})
	for trait_id: String in def.get("traits", []):
		(gun["traits"] as Array).append({"id": trait_id, "q": 1.0})
	if def.has("family"):
		gun["family"] = String(def["family"])
	if def.has("sea"):
		gun["sea"] = {"id": String(def["sea"]), "q": 1.0}
	return gun


# The pony tier (its skin is the pony one): its guns carry a family.
static func is_pony(db: RefCounted, tier_id: String) -> bool:
	return String(db.tier(tier_id).get("skin", "")) == "pony"


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
	var chal_problem := CamoChallenges.check(gun)  # (polish1 D5a part 3) the gun's own camo challenges: shape only (before the camo is set aside)
	if chal_problem != "":
		return chal_problem
	if gun.has("chal") or gun.has("chal_done"):
		gun = gun.duplicate()
		gun.erase("chal")
		gun.erase("chal_done")
	if gun.has("camo"):  # (polish1 D5a) a camo on the gun: looks only, checked for shape (data/camos.json ids)
		var camo: Variant = gun["camo"]
		if not camo is Dictionary or not (camo as Dictionary).get("id") is String or String(camo["id"]).length() > 40 \
				or not ((camo as Dictionary).get("wear") is float or (camo as Dictionary).get("wear") is int) or float(camo["wear"]) < 0.0 or float(camo["wear"]) > 1.0 \
				or not ((camo as Dictionary).get("seed") is float or (camo as Dictionary).get("seed") is int) or int(camo["seed"]) < 0 or int(camo["seed"]) > 1000 \
				or not (camo as Dictionary).get("challenge", false) is bool or (camo as Dictionary).size() > 4:
			return "bad camo"
		gun = gun.duplicate()
		gun.erase("camo")
	if gun.has("wkills"):
		var count: Variant = gun["wkills"]
		if not (count is int or count is float) or float(count) < 0.0 or float(count) > float(WKILLS_MAX) or not is_equal_approx(float(count), roundf(float(count))):
			return "bad W kills count"
		gun = gun.duplicate()
		gun.erase("wkills")  # the counter says nothing about the rest of the gun
	if gun.has("owners"):  # (polish1 item 63) its previous owners and their kills (gold and up)
		var past: Variant = gun["owners"]
		if not past is Array or (past as Array).size() > OWNERS_MAX or db.tier_index(String(gun.get("tier", ""))) < db.tier_index("gold"):
			return "bad owners"
		for entry: Variant in past:
			if not entry is Dictionary or not (entry as Dictionary).get("n") is String or String(entry["n"]).length() > OWNER_NAME_MAX or not ((entry as Dictionary).get("k") is int or (entry as Dictionary).get("k") is float) or float(entry["k"]) < 0.0 or float(entry["k"]) > float(WKILLS_MAX):
				return "bad owners"
		gun = gun.duplicate()
		gun.erase("owners")
	if gun.has("record"):  # a number the gun remembers (data/gun_uniques.json "keeps": Fish Story's biggest hit)
		var best: Variant = gun["record"]
		var keeps := String((db.uniques.get(String(gun.get("unique", "")), {}) as Dictionary).get("keeps", ""))
		if keeps != "record" or not (best is int or best is float) or float(best) < 0.0 or float(best) > RECORD_MAX or not is_equal_approx(float(best), roundf(float(best))):
			return "bad record"
		gun = gun.duplicate()
		gun.erase("record")
	var level_problem := _level_problem(gun)
	if level_problem != "":
		return level_problem
	if gun.has("unique"):  # a unique is legal only as the exact gun its id stands for (at its level; old ones had none)
		var real := unique(db, String(gun["unique"]), ItemLevel.of(gun))
		if not gun.has("lvl"):
			real.erase("lvl")
			real.erase("traits")
			real["v"] = gun.get("v", 2)
		elif int(gun.get("v", 0)) == 3 and not real.has("family") and not real.has("sea"):
			real["v"] = 3  # saved before families and sea affixes
		return "" if not real.is_empty() and _same(real, gun) else "unknown or edited unique"
	for key in ["v", "body", "maker", "tier", "parts", "rolls", "buffs"]:
		if not gun.has(key):
			return "missing %s" % key
	if not (gun["parts"] is Dictionary) or not (gun["rolls"] is Dictionary) or not (gun["buffs"] is Array):
		return "wrong field types"
	var version := int(gun["v"])
	if version < 1 or version > VERSION:
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
	if version >= 3:
		var trait_problem := _trait_problem(db, gun, lo, hi)
		if trait_problem != "":
			return trait_problem
	var sea_problem := _family_and_sea_problem(db, gun, version, lo, hi)
	if sea_problem != "":
		return sea_problem
	if version >= 2:
		if not gun.has("skills"):
			return "missing skills"
		return SkillState.check(db, String(gun["tier"]), gun["skills"], EPS)
	return ""


# Version 3 guns carry exactly their tier's number of traits, each known, never twice, at a quality inside the tier's range.
static func _trait_problem(db: RefCounted, gun: Dictionary, lo: float, hi: float) -> String:
	var list: Variant = gun.get("traits")
	if not (list is Array) or (list as Array).size() != db.trait_count(String(gun["tier"])):
		return "wrong number of traits"
	var seen: Array[String] = []
	for t: Variant in list:
		if not (t is Dictionary):
			return "bad trait"
		var id := String((t as Dictionary).get("id", ""))
		if db.trait_def(id).is_empty() or seen.has(id):
			return "unknown or repeated trait"
		seen.append(id)
		var q := float((t as Dictionary).get("q", -1.0))
		if q < lo or q > hi:
			return "trait out of tier range"
	return ""


# Version 4: a pony gun carries a known family and exactly one of that family's traits (others none); a sea affix
# is known, inside the tier's quality and only on a gun of a high enough level. Older guns carry neither.
static func _family_and_sea_problem(db: RefCounted, gun: Dictionary, version: int, lo: float, hi: float) -> String:
	if version < 4:
		if gun.has("family") or gun.has("sea"):
			return "old gun with a family or sea affix"
		for t: Variant in gun.get("traits", []):
			if t is Dictionary and String(db.trait_def(String((t as Dictionary).get("id", ""))).get("family", "")) != "":
				return "old gun with a pony-only trait"
		return ""
	var pony := is_pony(db, String(gun["tier"]))
	var family := String(gun.get("family", ""))
	if pony != gun.has("family") or (pony and not db.families.is_empty() and db.family_def(family).is_empty()):
		return "wrong pony family"
	var own := 0
	for t: Dictionary in gun.get("traits", []):
		var of := String(db.trait_def(String(t["id"])).get("family", ""))
		if of != "" and of != family:
			return "another family's trait"
		if of != "":
			own += 1
	if pony and db.trait_count(String(gun["tier"])) > 0 and own != 1:
		return "a pony needs one trait of its family"
	if gun.has("sea"):
		var affix: Variant = gun["sea"]
		if not (affix is Dictionary) or db.sea_def(String((affix as Dictionary).get("id", ""))).is_empty():
			return "unknown sea affix"
		var q := float((affix as Dictionary).get("q", -1.0))
		if q < lo or q > hi:
			return "sea affix out of tier range"
		if db.sea_chance(ItemLevel.of(gun)) <= 0.0:
			return "sea affix below its level"
	return ""


# Version 3 guns carry a whole item level inside 1..max; older ones carry none.
static func _level_problem(gun: Dictionary) -> String:
	var version := int(gun.get("v", 0))
	if version >= 3:
		var lvl: Variant = gun.get("lvl")
		if not (lvl is int or lvl is float) or not is_equal_approx(float(lvl), roundf(float(lvl))) or int(lvl) < 1 or int(lvl) > ItemLevel.max_level():
			return "bad item level"
	elif gun.has("lvl") or gun.has("traits"):
		return "old gun with an item level or traits"
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
