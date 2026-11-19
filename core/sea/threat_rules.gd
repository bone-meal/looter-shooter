# Purpose: how hard the sea's enemies hit and how much they take, by sea region (sea step 8f, LOCKED: "right ship per
# region" + "enemies grow with level"). PLAYER side: an enemy's damage (and health) grows by the same x per item level
# as armour defense and gun damage (core/item_level.gd), measured from region 1, so the numbers written in data are
# region 1's. SHIP side: every region expects a ship (data/sea/encounters.json threat.ship_by_region); hull damage is
# written for the base ship (a sloop) and scaled by the expected ship's hull, so the expected ship lasts the same
# time everywhere and a smaller one sinks faster.
# Dependencies: core/item_level.gd (data/item_levels.json); the encounters "threat" block and data/sea/hull.json are
# passed in.
extends RefCounted

const ItemLevel = preload("res://core/item_level.gd")


# The item level of a sea region's enemies: the region's drop band start + area_offset.
static func region_level(threat: Dictionary, region_n: int) -> int:
	return ItemLevel.region_band(clampi(region_n, 1, 7)).x + int(threat["area_offset"])


# NEW GAME+ (sea step 11, LOCKED: built now, opened after the Vault): the host's world's NG+ count, and what each adds
# (data/crossing.json "ng": item levels on every sea enemy and sea loot, luck on sea loot's gun tiers).
static var ng := 0
static var _ng_cfg := {}


static func ng_cfg() -> Dictionary:
	if _ng_cfg.is_empty():
		_ng_cfg = (JSON.parse_string(FileAccess.get_file_as_string("res://data/crossing.json")) as Dictionary)["ng"]
	return _ng_cfg


# Item levels NG+ adds now.
static func ng_levels() -> int:
	return ng * int(ng_cfg()["item_levels"])


# Luck NG+ adds to sea loot's gun tier rolls (core/gun_gen.gd generate's luck; core/loot_pool.gd x (1 + this)).
static func ng_luck() -> float:
	return float(ng) * float(ng_cfg()["luck_per"])


# A sea loot level with NG+ on top (never above the game's highest item level).
static func loot_level(lvl: int) -> int:
	return mini(lvl + ng_levels(), ItemLevel.max_level())


# Enemy damage (and health) at sea, x region 1's. NG+ levels count past the game's highest item level here (enemies only).
static func player_mult(threat: Dictionary, region_n: int) -> float:
	var growth := float(ItemLevel.cfg()["damage_growth"])
	return pow(growth, float(region_level(threat, region_n) + ng_levels() - 1)) / pow(growth, float(region_level(threat, 1) - 1))


# Hull damage at sea, x the base ship's.
static func hull_mult(threat: Dictionary, hull_cfg: Dictionary, region_n: int) -> float:
	var ships: Array = threat["ship_by_region"]
	var expect := String(ships[clampi(region_n, 1, ships.size()) - 1])
	var hulls: Dictionary = hull_cfg["hull"]
	return float(hulls.get(expect, 400.0)) / float(hulls.get(String(threat["base_ship"]), 400.0))
