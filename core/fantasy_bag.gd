# Purpose: pure fantasy-world inventory: how many of each item a player carries and what is equipped (staff, robe, axe,
# pickaxe, rod). Better staffs, robes and tools equip themselves when they arrive. No nodes.
# Dependencies: none. Data: data/fantasy/gear.json.
extends RefCounted

const SLOTS := ["staff", "robe", "axe", "pickaxe", "rod"]

var items := {}  # item id -> count
var equipped := {}  # slot -> item id ("" = nothing)

var _defs: Dictionary
var _start: Dictionary


func _init(gear_data: Dictionary) -> void:
	_defs = gear_data["items"]
	_start = gear_data["start"]
	reset()


# The starting kit of a new character.
func reset() -> void:
	items = {}
	for slot: String in SLOTS:
		equipped[slot] = ""
	for slot: String in _start["equip"]:
		add(String(_start["equip"][slot]), 1)
	for id: String in _start["bag"]:
		add(id, int(_start["bag"][id]))


func all_ids() -> Array:
	return _defs.keys()


func has_item(id: String) -> bool:
	return _defs.has(id)


func def(id: String) -> Dictionary:
	return _defs.get(id, {})


func item_name(id: String) -> String:
	return String(def(id).get("name", id))


func count(id: String) -> int:
	return int(items.get(id, 0))


# Which slot an item is worn in ("" for things that are not worn).
func slot_of(id: String) -> String:
	var d := def(id)
	match String(d.get("kind", "")):
		"staff": return "staff"
		"robe": return "robe"
		"tool": return String(d["slot"])
	return ""


func _rank(id: String) -> float:
	var d := def(id)
	return float(d.get("power", 0.0)) + float(d.get("hp", 0.0)) + float(d.get("tier", 0.0))


func add(id: String, amount: int = 1) -> void:
	if not _defs.has(id) or amount <= 0:
		return
	items[id] = count(id) + amount
	var slot := slot_of(id)
	if slot != "" and (String(equipped[slot]) == "" or _rank(id) > _rank(String(equipped[slot]))):
		equipped[slot] = id


func remove(id: String, amount: int = 1) -> bool:
	if count(id) < amount:
		return false
	items[id] = count(id) - amount
	if int(items[id]) <= 0:
		items.erase(id)
		for slot: String in SLOTS:  # the last one of a worn item is gone: wear the next best
			if String(equipped[slot]) == id:
				equipped[slot] = ""
				for other: String in items:
					if slot_of(other) == slot and (String(equipped[slot]) == "" or _rank(other) > _rank(String(equipped[slot]))):
						equipped[slot] = other
	return true


func equip(id: String) -> bool:
	var slot := slot_of(id)
	if slot == "" or count(id) <= 0:
		return false
	equipped[slot] = id
	return true


# True when the bag holds every {item: count} asked for.
func has_all(wanted: Dictionary) -> bool:
	for id: String in wanted:
		if count(id) < int(wanted[id]):
			return false
	return true


func take_all(wanted: Dictionary) -> bool:
	if not has_all(wanted):
		return false
	for id: String in wanted:
		remove(id, int(wanted[id]))
	return true


func staff() -> Dictionary:
	return def(String(equipped["staff"]))


func robe() -> Dictionary:
	return def(String(equipped["robe"]))


func tool_tier(slot: String) -> int:
	return int(def(String(equipped.get(slot, ""))).get("tier", 0))


func to_dict() -> Dictionary:
	return {"items": items.duplicate(), "equipped": equipped.duplicate()}


# Loads a save: unknown items are dropped, counts clamped, and only owned items stay equipped.
func from_dict(saved: Variant) -> void:
	if not saved is Dictionary or not (saved as Dictionary).get("items") is Dictionary:
		return
	items = {}
	for slot: String in SLOTS:
		equipped[slot] = ""
	var src: Dictionary = (saved as Dictionary)["items"]
	for id: String in src:
		if _defs.has(id):
			add(id, clampi(int(src[id]), 0, 9999))
	var worn: Variant = (saved as Dictionary).get("equipped")
	if worn is Dictionary:
		for slot: String in SLOTS:
			var id := String((worn as Dictionary).get(slot, ""))
			if id != "" and count(id) > 0 and slot_of(id) == slot:
				equipped[slot] = id
