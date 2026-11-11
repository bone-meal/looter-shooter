# Purpose: pure RuneScape-style skill levels of the fantasy world: experience per skill, the level it gives, and what a
# save may contain. No nodes.
# Dependencies: none. Data: data/fantasy/skilling.json (skills, max_level, xp_base, xp_power).
extends RefCounted

var xp := {}  # skill id -> total experience

var _data: Dictionary


func _init(skill_data: Dictionary) -> void:
	_data = skill_data
	for id: String in _data["skills"]:
		xp[id] = 0


func ids() -> Array:
	return (_data["skills"] as Dictionary).keys()


func skill_name(id: String) -> String:
	return String(_data["skills"][id]["name"])


func max_level() -> int:
	return int(_data["max_level"])


# Total experience needed to BE level `at` (level 1 = 0).
func xp_for(at: int) -> int:
	return roundi(float(_data["xp_base"]) * pow(float(maxi(at - 1, 0)), float(_data["xp_power"])))


func level(id: String) -> int:
	var have := int(xp.get(id, 0))
	var at := 1
	while at < max_level() and have >= xp_for(at + 1):
		at += 1
	return at


# 0..1 of the way from this level to the next (1 at the cap).
func progress(id: String) -> float:
	var at := level(id)
	if at >= max_level():
		return 1.0
	var low := xp_for(at)
	return clampf(float(int(xp[id]) - low) / float(maxi(xp_for(at + 1) - low, 1)), 0.0, 1.0)


# Adds experience; returns how many levels were gained.
func add_xp(id: String, amount: int) -> int:
	if not xp.has(id) or amount <= 0:
		return 0
	var before := level(id)
	xp[id] = mini(int(xp[id]) + amount, xp_for(max_level()))
	return level(id) - before


func set_level(id: String, at: int) -> void:
	if xp.has(id):
		xp[id] = xp_for(clampi(at, 1, max_level()))


func levels() -> Dictionary:
	var out := {}
	for id: String in xp:
		out[id] = level(id)
	return out


func to_dict() -> Dictionary:
	return xp.duplicate()


# Loads saved experience; unknown skills are dropped and values clamped, so an edited file cannot break anything.
func from_dict(saved: Variant) -> void:
	if not saved is Dictionary:
		return
	for id: String in xp:
		xp[id] = clampi(int((saved as Dictionary).get(id, 0)), 0, xp_for(max_level()))
