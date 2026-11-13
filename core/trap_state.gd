# Purpose: pure timing of the islands' traps: which one runs until when and which is still cooling down. No nodes.
# Dependencies: none. Data: data/traps.json "traps", passed to the constructor. Time is the caller's clock in seconds.
extends RefCounted

var traps: Array

var _until := PackedFloat32Array()  # per trap: it runs until then
var _ready_at := PackedFloat32Array()  # per trap: it can be switched on again from then


func _init(list: Array) -> void:
	traps = list
	_until.resize(list.size())
	_ready_at.resize(list.size())
	reset()


func running(trap: int, now: float) -> bool:
	return now < _until[trap]


# Seconds it still runs, and seconds until it can be switched on again (0 = now).
func left(trap: int, now: float) -> float:
	return maxf(_until[trap] - now, 0.0)


func wait(trap: int, now: float) -> float:
	return maxf(_ready_at[trap] - now, 0.0)


# Switched on (the caller has taken the price); false while it runs or cools down.
func start(trap: int, now: float) -> bool:
	if trap < 0 or trap >= traps.size() or now < _ready_at[trap]:
		return false
	_until[trap] = now + float(traps[trap]["seconds"])
	_ready_at[trap] = _until[trap] + float(traps[trap]["cooldown"])
	return true


# Game over: everything off and ready.
func reset() -> void:
	_until.fill(-1.0)
	_ready_at.fill(-1.0)
