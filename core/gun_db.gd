# Purpose: read-only lookup over the gun loot data: tiers, manufacturers, parts, buffs, rolled-stat definitions and the base weapons that guns are built on. Pure data, no nodes.
# Dependencies: none. Data: data/gun_loot.json, gun_parts.json, manufacturers.json, weapons.json, skills.json, gun_uniques.json (checked by tools/validate_data.gd), gun_traits.json, loot_pools.json (read here).
extends RefCounted

var stats: Dictionary
var tiers: Array
var buffs: Array
var base_crit_chance: float
var slots: Array
var bodies: Dictionary
var parts: Dictionary
var makers: Dictionary
var weapons: Dictionary
var skills: Dictionary  # data/skills.json "skills" (the Q/E abilities)
var combos: Array  # data/gun_parts.json "combos": what parts do together (core/gun_combos.gd)
var matched: Array  # data/gun_parts.json "matched": bonus for parts by the gun's own maker
var uniques: Dictionary  # data/gun_uniques.json "uniques": hand-made pony guns by id (core/gun_gen.gd unique)
var unique_bonus: Dictionary  # stat bonus every unique gets on top of its rolls
var unique_chance: float  # how often a pony-tier drop is a unique
var wkills_chance: float  # data/gun_loot.json: share of rolled guns that carry the "W kills" counter
var traits: Array  # data/gun_traits.json "traits": the big build-defining effects (game/gun_traits.gd)
var trait_slots: Dictionary  # data/gun_traits.json "slots_by_tier": tier id -> how many traits it rolls
var families: Dictionary  # data/pony_families.json "families": pony family id -> {name, hue, span, sat, traits}
var sea: Dictionary  # data/sea_affixes.json (min_level, chance_by_level, affixes)
var pools: Dictionary  # data/loot_pools.json "pools": pool id -> {guns, luck, min_tier, unique_chance, unique_rolls, chase_share}
var world_pools: Array  # data/loot_pools.json: pools whose uniques may also come out of any pony drop


func _init(loot: Dictionary, part_data: Dictionary, maker_data: Dictionary, weapon_data: Dictionary, skill_data: Dictionary = {}, unique_data: Dictionary = {}) -> void:
	uniques = unique_data.get("uniques", {})
	unique_bonus = unique_data.get("bonus", {})
	unique_chance = float(unique_data.get("drop_chance", 0.0))
	stats = loot["stats"]
	tiers = loot["tiers"]
	buffs = loot["buffs"]
	base_crit_chance = float(loot["base_crit_chance"])
	wkills_chance = float(loot.get("wkills_chance", 0.0))
	slots = part_data["slots"]
	bodies = part_data["bodies"]
	parts = part_data["parts"]
	combos = part_data.get("combos", [])
	matched = part_data.get("matched", [])
	makers = maker_data["makers"]
	weapons = weapon_data["weapons"]
	skills = skill_data.get("skills", {})
	var trait_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_traits.json"))
	traits = (trait_data as Dictionary).get("traits", []) if trait_data is Dictionary else []
	trait_slots = (trait_data as Dictionary).get("slots_by_tier", {}) if trait_data is Dictionary else {}
	var family_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/pony_families.json"))
	families = (family_data as Dictionary).get("families", {}) if family_data is Dictionary else {}
	var sea_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea_affixes.json"))
	sea = sea_data if sea_data is Dictionary else {"affixes": {}}
	var pool_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/loot_pools.json"))
	pools = (pool_data as Dictionary).get("pools", {}) if pool_data is Dictionary else {}
	world_pools = (pool_data as Dictionary).get("world_pools", ["world"]) if pool_data is Dictionary else ["world"]



# The loot pool a unique drops from ("world" when its data names none).
func pool_of(unique_id: String) -> String:
	return String((uniques.get(unique_id, {}) as Dictionary).get("pool", "world"))


# Uniques that any pony drop may turn into (their pool is a world pool), optionally only for one body.
func world_uniques(body: String = "") -> Array:
	var out: Array = []
	for id: String in uniques:
		if world_pools.has(pool_of(id)) and (body == "" or String(uniques[id]["body"]) == body):
			out.append(id)
	return out


# A pool's uniques: chase guns (red text) when chase is true, else the plain ones.
func pool_uniques(pool_id: String, chase: bool) -> Array:
	var out: Array = []
	for id: String in uniques:
		if pool_of(id) == pool_id and (uniques[id] as Dictionary).has("red") == chase:
			out.append(id)
	return out

func tier_index(id: String) -> int:
	for i in tiers.size():
		if String(tiers[i]["id"]) == id:
			return i
	return -1


func tier(id: String) -> Dictionary:
	return tiers[tier_index(id)]


func trait_def(id: String) -> Dictionary:
	for t: Dictionary in traits:
		if String(t["id"]) == id:
			return t
	return {}


# The traits any gun may roll (pony-only family traits left out).
func common_traits() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in traits:
		if String(t.get("family", "")) == "":
			out.append(String(t["id"]))
	return out


func family_def(id: String) -> Dictionary:
	return families.get(id, {})


func sea_def(id: String) -> Dictionary:
	return (sea.get("affixes", {}) as Dictionary).get(id, {})


# The chance a gun of item level `lvl` rolls a sea affix (0 below min_level).
func sea_chance(lvl: int) -> float:
	var chance := 0.0
	if lvl < int(sea.get("min_level", 9999)):
		return 0.0
	for step: Array in sea.get("chance_by_level", []):
		if lvl >= int(step[0]):
			chance = float(step[1])
	return chance


func trait_count(tier_id: String) -> int:
	return int(trait_slots.get(tier_id, 0))


func buff_def(id: String) -> Dictionary:
	for b: Dictionary in buffs:
		if String(b["id"]) == id:
			return b
	return {}


func skill_def(id: String) -> Dictionary:
	return skills.get(id, {})
