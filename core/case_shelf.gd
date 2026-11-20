# Purpose: the crates a player owns but has not opened yet (polish1 item 72: bought crates go to the CASES tab and
# are opened there, CS:GO style). Counts by crate id, saved in the profile ("cases"); only crate ids the data knows
# are kept, each count 0..MOST. No nodes.
# Dependencies: none. Crate ids come from data/gun_loot.json "vendor".
extends RefCounted

const MOST := 999

var counts := {}  # crate id -> how many unopened


func add(id: String, n: int = 1) -> void:
	counts[id] = clampi(int(counts.get(id, 0)) + n, 0, MOST)


# Takes one out to open it; false when there is none.
func take(id: String) -> bool:
	if int(counts.get(id, 0)) <= 0:
		return false
	counts[id] = int(counts[id]) - 1
	if int(counts[id]) == 0:
		counts.erase(id)
	return true


func count(id: String) -> int:
	return int(counts.get(id, 0))


func total() -> int:
	var n := 0
	for id: String in counts:
		n += int(counts[id])
	return n


func to_dict() -> Dictionary:
	return counts.duplicate()


# `known` = the crate ids of the data; anything else in a save is dropped.
func from_dict(data: Variant, known: Array) -> void:
	counts.clear()
	if not data is Dictionary:
		return
	for id: Variant in data:
		if known.has(String(id)) and (data[id] is float or data[id] is int) and int(data[id]) > 0:
			counts[String(id)] = clampi(int(data[id]), 0, MOST)
