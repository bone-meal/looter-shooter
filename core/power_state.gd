# Purpose: pure rules of the islands' power: which parts of the switch the party has found, and whether the switch is
# built and on. No nodes.
# Dependencies: none. Data: data/power.json (how many parts there are), passed to the constructor.
extends RefCounted

var found: Array[bool] = []
var on := false


func _init(config: Dictionary) -> void:
	found.resize((config["parts"] as Array).size())
	found.fill(false)


func found_count() -> int:
	return found.count(true)


func all_found() -> bool:
	return not found.has(false)


# A part is picked up; false when it already was (or there is no such part).
func take(part: int) -> bool:
	if part < 0 or part >= found.size() or found[part]:
		return false
	found[part] = true
	return true


# The switch is built and thrown; false while a part is missing or it is on already.
func switch_on() -> bool:
	if on or not all_found():
		return false
	on = true
	return true


# Game over: dark again, the parts lie where they lay.
func reset() -> void:
	found.fill(false)
	on = false


# The whole state as one number (bit n = part n found, the bit after the last part = on), to send and to set.
func to_bits() -> int:
	var bits := 0
	for i in found.size():
		if found[i]:
			bits |= 1 << i
	return bits | ((1 << found.size()) if on else 0)


func set_bits(bits: int) -> void:
	for i in found.size():
		found[i] = (bits >> i) & 1 == 1
	on = (bits >> found.size()) & 1 == 1
