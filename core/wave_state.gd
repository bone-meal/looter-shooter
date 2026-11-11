# Purpose: pure wave progression: which enemy ID to spawn next, pacing, intermissions, cleared state.
# Dependencies: none. Settings come from data/waves.json (see tools/validate_data.gd).
extends RefCounted

var cleared := false

var _waves: Array
var _max_alive: int
var _spawn_interval: float
var _wave_delay: float
var _index := -1
var _pending: Array[String] = []
var _next_time := 0.0
var _waiting := false


func _init(data: Dictionary) -> void:
	_waves = data["waves"]
	_max_alive = int(data["max_alive"])
	_spawn_interval = float(data["spawn_interval"])
	_wave_delay = float(data["wave_delay"])


# Call every tick. Returns an enemy ID to spawn now, or "" for none.
func update(now: float, alive: int) -> String:
	if cleared:
		return ""
	if _pending.is_empty():
		if alive > 0:
			return ""
		if _index + 1 >= _waves.size():
			cleared = true  # last wave beaten: done now, no intermission
			return ""
		if not _waiting:
			_waiting = true
			_next_time = now + _wave_delay
		if now < _next_time:
			return ""
		if _index + 1 >= _waves.size():
			cleared = true
			return ""
		_index += 1
		_waiting = false
		var wave: Dictionary = _waves[_index]
		for id in wave:
			for i in int(wave[id]):
				_pending.append(String(id))
		_next_time = now
	if alive < _max_alive and now >= _next_time:
		_next_time = now + _spawn_interval
		return _pending.pop_front()
	return ""


# Wave being fought (1-based; 1 before the first wave starts).
func wave_number() -> int:
	return maxi(_index + 1, 1)


func status(alive: int) -> String:
	if cleared:
		return "ARENA CLEARED"
	if _waiting:
		return "next wave %d/%d incoming" % [_index + 2, _waves.size()]
	return "wave %d/%d  enemies %d" % [_index + 1, _waves.size(), alive + _pending.size()]
