# Purpose: the timing of knife attacks: an attack starts, its blow lands a moment later, and the next one has to
# wait out the interval. Pure: no nodes, no rendering.
# Dependencies: none. An attack is the dictionary core/knife_db.gd gives (interval, hit_at, swing ...).
extends RefCounted

var kind := ""  # the attack going on or last made ("slash" / "stab"), "" before the first

var _started := -100.0
var _interval := 0.0
var _hit_at := 0.0
var _landed := true


# Starts an attack if the last one is over. Returns true when it started.
func try_start(attack_kind: String, attack: Dictionary, now: float) -> bool:
	if now < _started + _interval:
		return false
	kind = attack_kind
	_started = now
	_interval = float(attack["interval"])
	_hit_at = float(attack["hit_at"])
	_landed = false
	return true


# True exactly once per attack: the moment its blow lands. Call every frame.
func lands(now: float) -> bool:
	if _landed or now < _started + _hit_at:
		return false
	_landed = true
	return true


# 0..1 through the attack's swing (1 = over, also before the first attack).
func swing(now: float) -> float:
	if _interval <= 0.0:
		return 1.0
	return clampf((now - _started) / minf(_interval, 0.5), 0.0, 1.0)


func busy(now: float) -> bool:
	return now < _started + _interval


# Puts the knife away mid-attack: a blow that has not landed yet never does.
func cancel() -> void:
	_landed = true
	_interval = 0.0
