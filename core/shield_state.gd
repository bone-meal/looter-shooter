# Purpose: pure rules of the buildable shield one player carries: whether he has one, how many hits it still takes,
# and whether a hit from a given side is stopped (on the back it covers behind, in hand it covers ahead). No nodes.
# Dependencies: none. Data: data/shield.json, passed to setup().
extends RefCounted

var cfg: Dictionary = {}
var owned := false
var hits_left := 0


func setup(config: Dictionary) -> void:
	cfg = config


func max_hits() -> int:
	return int(cfg.get("hits", 0))


# A fresh shield from the bench; false when he carries one already.
func give() -> bool:
	if owned or cfg.is_empty():
		return false
	owned = true
	hits_left = max_hits()
	return true


# Lost (game over) or put aside.
func drop() -> void:
	owned = false
	hits_left = 0


# `bearing` = the angle in radians between where the player looks and where the hit comes from (0 = from straight
# ahead, PI = from straight behind). In hand the shield covers the slice ahead, on the back the slice behind.
func stops(bearing: float, in_hand: bool) -> bool:
	if not owned:
		return false
	var half := deg_to_rad(float(cfg["arc_deg"])) * 0.5
	return absf(bearing) <= half if in_hand else PI - absf(bearing) <= half


# The shield takes `cost` hits. Returns true when that broke it (it is gone then).
func wear(cost: int) -> bool:
	if not owned or cost <= 0:
		return false
	hits_left -= cost
	if hits_left > 0:
		return false
	drop()
	return true
