# Purpose: pure burn clock of the Lit Cigarette a player is smoking: how many seconds it has left, burning only while
# the caller says so, lit anew only once the last one burnt out. No nodes.
# Dependencies: none. Data: data/cigarette.json, passed to setup().
extends RefCounted

var cfg: Dictionary = {}
var left := 0.0  # seconds the cigarette being smoked still burns (0 = none lit: the next one worn starts full)


func setup(config: Dictionary) -> void:
	cfg = config


func full() -> float:
	return float(cfg.get("burn_seconds", 1800.0))


# A cigarette is in the mouth: one burnt out before (or never lit) = a fresh one is lit now.
func light() -> void:
	if left <= 0.0:
		left = full()


# Time passes with it in the mouth; `burning` = on the gun side and not paused. Returns true the moment it burns out.
func tick(delta: float, burning: bool) -> bool:
	if not burning or left <= 0.0:
		return false
	left = maxf(left - delta, 0.0)
	return left <= 0.0


# 0..1 of the cigarette still there.
func share() -> float:
	return clampf(left / maxf(full(), 1.0), 0.0, 1.0)


func warning() -> bool:
	return left > 0.0 and left <= float(cfg.get("warn_seconds", 120.0))


# How many cigarettes a reward chest holds after a run of `waves` waves (`longest` = the longest ticket's waves).
func chest_count(waves: int, longest: int) -> int:
	var chest: Dictionary = cfg.get("chest", {})
	return int(chest.get("final" if waves >= longest else "normal", 0))
