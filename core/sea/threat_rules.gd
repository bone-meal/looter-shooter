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


# Enemy damage (and health) at sea, x region 1's.
static func player_mult(threat: Dictionary, region_n: int) -> float:
	return ItemLevel.damage_mult(region_level(threat, region_n)) / ItemLevel.damage_mult(region_level(threat, 1))


# Hull damage at sea, x the base ship's.
static func hull_mult(threat: Dictionary, hull_cfg: Dictionary, region_n: int) -> float:
	var ships: Array = threat["ship_by_region"]
	var expect := String(ships[clampi(region_n, 1, ships.size()) - 1])
	var hulls: Dictionary = hull_cfg["hull"]
	return float(hulls.get(expect, 400.0)) / float(hulls.get(String(threat["base_ship"]), 400.0))
