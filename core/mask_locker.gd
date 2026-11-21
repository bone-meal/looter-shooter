# Purpose: the masks a player owns (polish1 D5c): mask id -> copies (drop masks can be won again and traded; achievement
# and playtime masks are one each), the one worn ("" = none), saved in the profile ("masks") and checked on load
# (unknown ids dropped). Pure rules.
# Dependencies: core/mask_db.gd (the rules object passed in).
extends RefCounted

const MOST_COPIES := 99

var db: RefCounted
var owned := {}  # id -> copies
var worn := ""


func _init(mask_db: RefCounted) -> void:
	db = mask_db


func has(id: String) -> bool:
	return int(owned.get(id, 0)) > 0


func add(id: String) -> bool:
	if not bool(db.call("has", id)):
		return false
	owned[id] = mini(int(owned.get(id, 0)) + 1, MOST_COPIES)
	return true


# One copy out (a trade); the worn mask comes off when the last copy goes.
func remove(id: String) -> bool:
	if not has(id):
		return false
	owned[id] = int(owned[id]) - 1
	if int(owned[id]) <= 0:
		owned.erase(id)
		if worn == id:
			worn = ""
	return true


func wear(id: String) -> bool:
	if id != "" and not has(id):
		return false
	worn = id
	return true


# Owned ids in the data's order.
func order() -> Array:
	var out: Array = []
	for id: String in db.call("ids"):
		if has(id):
			out.append(id)
	return out


func to_dict() -> Dictionary:
	return {"owned": owned.duplicate(), "worn": worn}


func from_dict(d: Variant) -> void:
	owned = {}
	worn = ""
	if not d is Dictionary:
		return
	var src: Variant = (d as Dictionary).get("owned", {})
	if src is Dictionary:
		for id: Variant in src:
			var n: Variant = src[id]
			if id is String and bool(db.call("has", id)) and (n is int or n is float) and int(n) > 0:
				owned[id] = mini(int(n), MOST_COPIES)
	var w: Variant = (d as Dictionary).get("worn", "")
	if w is String and has(w):
		worn = w
