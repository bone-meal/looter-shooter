# Purpose: pure rules of the boss TROPHIES (polish1 E4, items 131 / 133): the pieces in data/boss_trophies.json plus a
# GHOST copy "<id>_ghost" of every boss trophy (same pieces, drawn as a blue echo, dropped by that boss's phantom),
# which body spots each piece takes, and `clean` = any list of worn ids made safe (known ids, no two on one spot).
# Dependencies: none (the parsed data/boss_trophies.json is passed in).
extends RefCounted

var spots: Array = []
var _defs := {}  # id -> {name, about, boss, set, ghost, spots, wear}
var _order: Array = []


func _init(data: Dictionary) -> void:
	spots = data.get("spots", [])
	var src: Dictionary = data.get("trophies", {})
	for id: String in src:
		var d: Dictionary = (src[id] as Dictionary).duplicate(true)
		_defs[id] = d
		_order.append(id)
	for id: String in src:  # the ghost copies come after the real ones
		var d: Dictionary = _defs[id]
		if d.has("boss") and not bool(d.get("ghost", false)):
			var ghost := d.duplicate(true)
			ghost["ghost"] = true
			ghost["phantom"] = String(d["boss"])
			ghost.erase("boss")
			var called := String(d["name"])
			ghost["name"] = "Ghostly " + (called.substr(4) if called.begins_with("The ") else called)
			ghost["about"] = "The echo of a trophy, shed by the phantom of the same great creature."
			_defs[id + "_ghost"] = ghost
			_order.append(id + "_ghost")


func ids() -> Array:
	return _order


func has(id: String) -> bool:
	return _defs.has(id)


func def(id: String) -> Dictionary:
	return _defs.get(id, {})


func name_of(id: String) -> String:
	return String(def(id).get("name", id))


func spots_of(id: String) -> Array:
	return def(id).get("spots", [])


func wear_of(id: String) -> Array:
	return def(id).get("wear", [])


func is_ghost(id: String) -> bool:
	return bool(def(id).get("ghost", false))


# The trophy a boss's first kill gives ("" = none).
func for_boss(boss: String) -> String:
	for id: String in _order:
		if String(_defs[id].get("boss", "")) == boss:
			return id
	return ""


# The pieces a boss's phantom can drop: its ghost trophy and every piece of the spectral set.
func ghost_of(boss: String) -> String:
	var real := for_boss(boss)
	return real + "_ghost" if real != "" and _defs.has(real + "_ghost") else ""


func set_pieces(set_id: String) -> Array:
	var out: Array = []
	for id: String in _order:
		if String(_defs[id].get("set", "")) == set_id:
			out.append(id)
	return out


# True when two pieces want the same spot.
func clash(a: String, b: String) -> bool:
	for spot: Variant in spots_of(a):
		if spots_of(b).has(spot):
			return true
	return false


# Any input -> worn ids that exist, each once, no two on one spot (the later one loses), at most one per spot.
func clean(worn: Variant) -> Array:
	var out: Array = []
	if not worn is Array:
		return out
	for id: Variant in worn:
		if not id is String or not _defs.has(id) or out.has(id) or out.size() >= spots.size():
			continue
		var free := true
		for other: String in out:
			if clash(id, other):
				free = false
		if free:
			out.append(id)
	return out


# Problems in the data (tools/boss_trophy_check.gd): unknown spots, pieces with no wear.
func problems(wear_table: Dictionary) -> Array:
	var out: Array = []
	for id: String in _order:
		var d: Dictionary = _defs[id]
		if spots_of(id).is_empty():
			out.append("%s: no spots" % id)
		for spot: Variant in spots_of(id):
			if not spots.has(spot):
				out.append("%s: unknown spot %s" % [id, spot])
		for w: Variant in wear_of(id):
			if not wear_table.has(w):
				out.append("%s: wear %s is not in data/characters.json" % [id, w])
		if not d.has("boss") and not d.has("set") and not d.has("phantom"):
			out.append("%s: no boss, phantom or set gives it" % id)
	return out
