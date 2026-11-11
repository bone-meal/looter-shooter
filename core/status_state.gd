# Purpose: pure elemental status effects on one character: fire and toxic deal damage over time, ice slows. No nodes.
# Dependencies: none. Numbers come from the "status" block in data/player.json.
extends RefCounted

var _config: Dictionary
var _timers := {"fire": 0.0, "ice": 0.0, "toxic": 0.0}


func _init(config: Dictionary) -> void:
	_config = config


# Starts (or refreshes) an effect. `resist` 0..1 shortens it.
func apply(element: String, resist: float) -> void:
	if not _config.has(element):
		return
	_timers[element] = maxf(_timers[element], float(_config[element]["seconds"]) * (1.0 - resist))


# Advances timers. Returns the damage-over-time dealt during `delta`.
func tick(delta: float) -> float:
	var damage := 0.0
	for element in _timers:
		if _timers[element] <= 0.0:
			continue
		if _config[element].has("dps"):
			damage += float(_config[element]["dps"]) * minf(delta, _timers[element])
		_timers[element] = maxf(_timers[element] - delta, 0.0)
	return damage


func speed_multiplier() -> float:
	return float(_config["ice"]["slow"]) if _timers["ice"] > 0.0 else 1.0


func full_seconds(element: String) -> float:
	return float(_config[element]["seconds"])


func remaining(element: String) -> float:
	return _timers[element]


func clear() -> void:
	for element in _timers:
		_timers[element] = 0.0
