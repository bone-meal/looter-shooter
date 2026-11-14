# Purpose: read-only lookup over the gun loot data: tiers, manufacturers, parts, buffs, rolled-stat definitions and the base weapons that guns are built on. Pure data, no nodes.
# Dependencies: none. Data: data/gun_loot.json, gun_parts.json, manufacturers.json, weapons.json, skills.json, gun_uniques.json (checked by tools/validate_data.gd), gun_traits.json (read here).
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


func trait_count(tier_id: String) -> int:
	return int(trait_slots.get(tier_id, 0))


func buff_def(id: String) -> Dictionary:
	for b: Dictionary in buffs:
		if String(b["id"]) == id:
			return b
	return {}


func skill_def(id: String) -> Dictionary:
	return skills.get(id, {})
