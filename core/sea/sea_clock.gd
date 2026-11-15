# Purpose: pure rules for the sea world's day (sea step 4): a full day in data/sea/world.json clock.day_minutes, where
# the sun stands at any time of day, and how much daylight there is (0 night .. 1 noon) with soft dawns and dusks.
# The time comes from one shared clock (the host's, sent online in step 12), so every machine sees the same sky.
# Dependencies: none.
extends RefCounted

var day_seconds := 1800.0
var dawn := 0.22
var dusk := 0.78
var start := 0.3


func _init(cfg: Dictionary) -> void:
	day_seconds = float(cfg["day_minutes"]) * 60.0
	dawn = float(cfg["dawn"])
	dusk = float(cfg["dusk"])
	start = float(cfg.get("start", 0.3))


# Time of day 0..1 (0 = midnight, 0.5 = noon) after `seconds` of the shared clock.
func day_part(seconds: float) -> float:
	return fposmod(start + seconds / day_seconds, 1.0)


# The sun's height above the horizon in degrees (negative at night) and its compass bearing (degrees, east at dawn).
func sun(part: float) -> Vector2:
	var arc := (part - dawn) / (dusk - dawn)  # 0 at dawn .. 1 at dusk
	var height := sin(arc * PI) * 62.0 if arc >= 0.0 and arc <= 1.0 else -sin(clampf(absf(arc - (0.0 if arc < 0.0 else 1.0)) * PI * 1.5, 0.0, PI * 0.5)) * 25.0
	return Vector2(height, 90.0 + arc * 180.0)


# 0 at night .. 1 in full day, rising and falling over about an hour of game time round dawn and dusk.
func daylight(part: float) -> float:
	var soft := 0.035
	return clampf(minf((part - dawn + soft) / (2.0 * soft), (dusk + soft - part) / (2.0 * soft)), 0.0, 1.0)


# How golden the light is (1 at sunrise and sunset, 0 at noon and night).
func golden(part: float) -> float:
	var near := minf(absf(part - dawn), absf(part - dusk))
	return clampf(1.0 - near / 0.06, 0.0, 1.0)
