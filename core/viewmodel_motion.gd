# Purpose: pure animation state for the held weapon: aim-down-sights blend, recoil kick, reload progress. No nodes.
# Dependencies: none. game/player.gd turns these numbers into model position, rotation and FOV every rendered frame.
extends RefCounted

var ads := 0.0     # 0 = hip, 1 = fully aimed (linear; use ads_eased for visuals)
var kick := 0.0    # 1 right after a shot, falls back to 0
var reload := 0.0  # 0 when not reloading, else 0..1 progress

var ads_speed := 9.0
var kick_decay := 10.0


func update(delta: float, wants_ads: bool, reload_fraction: float) -> void:
	reload = reload_fraction
	var target := 1.0 if (wants_ads and reload_fraction <= 0.0) else 0.0
	ads = move_toward(ads, target, ads_speed * delta)
	kick = maxf(kick - kick_decay * delta, 0.0)


func fire() -> void:
	kick = 1.0


func ads_eased() -> float:
	return smoothstep(0.0, 1.0, ads)


# 0 -> 1 -> 0 over the course of a reload (weapon dips, then comes back up).
func reload_curve() -> float:
	return sin(reload * PI) if reload > 0.0 else 0.0


func reset() -> void:
	ads = 0.0
	kick = 0.0
	reload = 0.0
