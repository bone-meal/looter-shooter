# Purpose: the boss trophies a player owns and wears (polish1 E4): owned ids (one each: trophies are earned, not
# traded), the worn ones (a piece per body spot, core/boss_trophy_db.gd clean), saved in the profile ("boss_trophies")
# and checked on load (unknown ids dropped). Pure rules.
# Dependencies: core/boss_trophy_db.gd (the rules object passed in).
extends RefCounted

var db: RefCounted
var owned := {}  # id -> true
var worn: Array = []


func _init(trophy_db: RefCounted) -> void:
	db = trophy_db


func has(id: String) -> bool:
	return owned.has(id)


# True when it is new.
func add(id: String) -> bool:
	if has(id) or not bool(db.call("has", id)):
		return false
	owned[id] = true
	return true


# Puts a piece on; anything on the same spots comes off.
func wear(id: String) -> bool:
	if not has(id):
		return false
	var kept: Array = []
	for other: String in worn:
		if other != id and not bool(db.call("clash", id, other)):
			kept.append(other)
	kept.append(id)
	worn = db.call("clean", kept)
	return true


func take_off(id: String) -> void:
	worn.erase(id)


func is_worn(id: String) -> bool:
	return worn.has(id)


# Owned ids in the data's order.
func order() -> Array:
	var out: Array = []
	for id: String in db.call("ids"):
		if has(id):
			out.append(id)
	return out


func to_dict() -> Dictionary:
	return {"owned": owned.keys(), "worn": worn.duplicate()}


func from_dict(d: Variant) -> void:
	owned = {}
	worn = []
	if not d is Dictionary:
		return
	var src: Variant = (d as Dictionary).get("owned", [])
	if src is Array:
		for id: Variant in src:
			if id is String and bool(db.call("has", id)):
				owned[id] = true
	var on: Array = []
	var w: Variant = (d as Dictionary).get("worn", [])
	if w is Array:
		for id: Variant in w:
			if id is String and has(id):
				on.append(id)
	worn = db.call("clean", on)
