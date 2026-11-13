# Purpose: pure record of everything a character has done, for the Combat Report (player card) and the achievements:
# plain totals ("kills", "damage_dealt", "seconds_played" ...) and counted groups ("kills_by_enemy" -> {enemy id: n},
# "kills_by_weapon", "gathered", "made", "spells" ...). Saved with the character as plain numbers. No nodes.
# Dependencies: none.
extends RefCounted

const LIMIT := 1.0e12  # no total grows past this (a broken save cannot make it absurd)
const GROUP_SIZE := 400  # most entries one group keeps (ids are data ids: far fewer exist)

var totals := {}  # name -> number
var groups := {}  # name -> {id: number}
var session_seconds := 0.0  # this sitting (not saved)


func add(name: String, amount: float = 1.0) -> void:
	if amount <= 0.0 or not is_finite(amount):
		return
	totals[name] = minf(float(totals.get(name, 0.0)) + amount, LIMIT)


func add_to(kind: String, id: String, amount: float = 1.0) -> void:
	if amount <= 0.0 or not is_finite(amount) or id == "":
		return
	var counts: Dictionary = groups.get(kind, {})
	if not counts.has(id) and counts.size() >= GROUP_SIZE:
		return
	counts[id] = minf(float(counts.get(id, 0.0)) + amount, LIMIT)
	groups[kind] = counts


# Keeps the higher of the old and the new number (a best round, a top speed).
func best(name: String, value: float) -> void:
	if is_finite(value) and value > float(totals.get(name, 0.0)):
		totals[name] = minf(value, LIMIT)


func total(name: String) -> float:
	return float(totals.get(name, 0.0))


func count_in(kind: String, id: String) -> float:
	return float((groups.get(kind, {}) as Dictionary).get(id, 0.0))


func group(name: String) -> Dictionary:
	return groups.get(name, {})


func group_sum(name: String) -> float:
	var sum := 0.0
	for id: String in group(name):
		sum += float(group(name)[id])
	return sum


# The entries of a group, largest first: [[id, number], ...] (at most `limit`, 0 = all).
func top(name: String, limit: int = 0) -> Array:
	var out: Array = []
	for id: String in group(name):
		out.append([id, float(group(name)[id])])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]) or (float(a[1]) == float(b[1]) and String(a[0]) < String(b[0])))
	return out if limit <= 0 else out.slice(0, limit)


# The id with the most in a group, "" when the group is empty (the favourite weapon).
func favourite(name: String) -> String:
	var first := top(name, 1)
	return String(first[0][0]) if not first.is_empty() else ""


func tick(seconds: float) -> void:
	if seconds > 0.0 and seconds < 10.0:
		session_seconds += seconds
		add("seconds_played", seconds)


func to_dict() -> Dictionary:
	return {"v": 1, "totals": totals.duplicate(), "groups": groups.duplicate(true)}


# Reads a saved record; anything that is not a finite number >= 0 is dropped.
func from_dict(saved: Variant) -> void:
	totals = {}
	groups = {}
	if not (saved is Dictionary):
		return
	var src: Dictionary = saved
	if src.get("totals") is Dictionary:
		for key: Variant in src["totals"]:
			var value: Variant = src["totals"][key]
			if (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0:
				totals[String(key)] = minf(float(value), LIMIT)
	if src.get("groups") is Dictionary:
		for name: Variant in src["groups"]:
			if not (src["groups"][name] is Dictionary):
				continue
			var counts := {}
			for id: Variant in src["groups"][name]:
				var value: Variant = src["groups"][name][id]
				if (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0 and counts.size() < GROUP_SIZE:
					counts[String(id)] = minf(float(value), LIMIT)
			groups[String(name)] = counts


# "1 h 05 min", "12 min", "45 s"
static func duration(seconds: float) -> String:
	var whole := floori(maxf(seconds, 0.0))
	var hours := floori(float(whole) / 3600.0)
	var minutes := floori(float(whole % 3600) / 60.0)
	if hours > 0:
		return "%d h %02d min" % [hours, minutes]
	if minutes > 0:
		return "%d min" % minutes
	return "%d s" % whole
