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


# limit = how many of the data's waves this run has (0 = all of them: a colosseum ticket buys the first few).
func _init(data: Dictionary, limit: int = 0) -> void:
	_waves = (data["waves"] as Array).slice(0, limit) if limit > 0 else data["waves"]
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


# More enemies for the wave being fought.
func add(ids: Array[String]) -> void:
	_pending.append_array(ids)


# Admin command /wave: the next wave to come in is `number` (whatever is still waiting of this one is dropped).
func skip_to(number: int) -> void:
	_index = clampi(number, 1, _waves.size()) - 2
	_pending.clear()
	_waiting = false
	cleared = false


# Wave being fought (1-based; 1 before the first wave starts).
func wave_number() -> int:
	return maxi(_index + 1, 1)


func wave_count() -> int:
	return _waves.size()


# Enemies still to beat in this wave: the living plus those not yet sent in.
func left(alive: int) -> int:
	return alive + _pending.size()


# What to announce between the fights ("" while a wave is being fought: the HUD shows its number and the enemies left).
func status() -> String:
	if cleared:
		return "ARENA CLEARED"
	if _waiting:
		return "Wave %d / %d incoming" % [_index + 2, _waves.size()]
	return ""
