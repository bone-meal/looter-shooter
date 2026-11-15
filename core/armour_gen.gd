# Purpose: rolls a piece of armour (tier, item level, bonus rolls, set) and checks a rolled piece from a save, a trade
# or a joiner. A rolled piece is a stack {"id": <armour item id>, "count": 1, "arm": {v, tier, lvl, rolls, set}}.
# Dependencies: core/item_db.gd (passed in; its `armour` = data/items.json "armour_loot"). Pure, no nodes.
extends RefCounted

const VERSION := 1
const EPS := 0.002
const KEYS := ["v", "tier", "lvl", "rolls", "set"]


# tier_id = a gun tier id (pick it with core/gun_gen.gd pick_tier); base "" = any armour piece that drops;
# set_id "auto" = the tier's set chance decides, with the set of the level's sea region; "" = no set.
static func generate(items: RefCounted, rng: RandomNumberGenerator, tier_id: String, lvl: int, base: String = "", set_id: String = "auto") -> Dictionary:
	var cfg: Dictionary = items.armour
	var tier: Dictionary = cfg["tiers"][tier_id]
	if base == "":
		var bases: Array[String] = items.armour_drops()
		base = bases[rng.randi_range(0, bases.size() - 1)]
	var pool: Array = (cfg["rolls"] as Dictionary).keys()
	var rolls := {}
	var q: Array = tier["quality"]
	for i in mini(int(tier["rolls"]), pool.size()):
		var pick: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		rolls[pick] = snappedf(rng.randf_range(float(q[0]), float(q[1])), 0.001)
	if set_id == "auto":
		set_id = set_for_level(cfg, lvl) if rng.randf() < float(tier["set_chance"]) else ""
	var level := clampi(lvl, 1, int(cfg["max_level"]))
	return {"id": base, "count": 1, "arm": {"v": VERSION, "tier": tier_id, "lvl": level, "rolls": rolls, "set": set_id}}


# The set of the sea region an item level belongs to (region = ceil(lvl / 10), 1..7).
static func set_for_level(cfg: Dictionary, lvl: int) -> String:
	var region := clampi(ceili(float(lvl) / 10.0), 1, 7)
	for id: String in cfg["sets"]:
		if int(cfg["sets"][id]["region"]) == region:
			return id
	return ""


# "" when `arm` is a piece the game itself could have rolled for item `id`, else a short reason.
static func validate(items: RefCounted, id: String, arm: Variant) -> String:
	if not items.rollable(id):
		return "not a rolled armour piece"
	if not arm is Dictionary:
		return "bad piece"
	var a: Dictionary = arm
	var cfg: Dictionary = items.armour
	for key: Variant in a:
		if not KEYS.has(key):
			return "unknown field"
	if not (a.get("v") is int or a.get("v") is float) or int(a["v"]) != VERSION:
		return "bad version"
	var tier_id: Variant = a.get("tier")
	if not tier_id is String or not (cfg["tiers"] as Dictionary).has(tier_id):
		return "unknown tier"
	var lvl: Variant = a.get("lvl")
	if not (lvl is int or lvl is float) or float(lvl) != floorf(float(lvl)) or int(lvl) < 1 or int(lvl) > int(cfg["max_level"]):
		return "bad level"
	var tier: Dictionary = cfg["tiers"][tier_id]
	var rolls: Variant = a.get("rolls")
	if not rolls is Dictionary or (rolls as Dictionary).size() != mini(int(tier["rolls"]), (cfg["rolls"] as Dictionary).size()):
		return "wrong number of rolls"
	var q: Array = tier["quality"]
	for roll: Variant in rolls:
		var value: Variant = rolls[roll]
		if not (cfg["rolls"] as Dictionary).has(roll) or not (value is float or value is int):
			return "unknown roll"
		if float(value) < float(q[0]) - EPS or float(value) > float(q[1]) + EPS:
			return "roll out of range"
	var set_id: Variant = a.get("set")
	if not set_id is String or (set_id != "" and not (cfg["sets"] as Dictionary).has(set_id)):
		return "unknown set"
	return ""
