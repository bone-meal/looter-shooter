# Purpose: pure Minecraft-style inventory: 9 hotbar slots (0-8) + 27 main slots, stackable items, a cursor stack for mouse moves, and 18 equipment slots.
# Dependencies: core/item_db.gd. Saved as IDs + counts with a version (to_dict / from_dict). No nodes, no rendering.
extends RefCounted

const HOTBAR := 9
const SIZE := 36
const VERSION := 3
const GunGen = preload("res://core/gun_gen.gd")
# Order matters: the equipment panel draws these in 3 columns of 6.
const EQUIP_SLOTS := ["hat", "head", "earrings", "necklace", "glasses", "mouth",
	"shirt", "chestplate", "gauntlets", "ring_1", "ring_2", "bracelet",
	"pants", "leg_armor", "cape", "waist", "boots", "foot_armor"]

var equipment := {}  # slot name -> {"id", "count"} or {}
var cursor := {}  # stack held by the mouse: {} or {"id": String, "count": int}

var _db: RefCounted
var _gun_db: RefCounted  # core/gun_db.gd; guns in a save are checked against it (without it every saved gun is dropped)
var _slots: Array[Dictionary] = []


func _init(db: RefCounted) -> void:
	_db = db
	for i in SIZE:
		_slots.append({})
	for slot in EQUIP_SLOTS:
		equipment[slot] = {}


func set_gun_db(gun_db: RefCounted) -> void:
	_gun_db = gun_db


# The rolled gun in a slot ({} when the slot holds no gun).
func gun_at(slot: int) -> Dictionary:
	return _slots[slot].get("gun", {})


# Puts a rolled gun (one slot each) in the first empty slot. Returns false when the inventory is full.
func add_gun(gun: Dictionary) -> bool:
	for i in SIZE:
		if _slots[i].is_empty():
			_slots[i] = {"id": "gun", "count": 1, "gun": gun}
			return true
	return false


func item_id(slot: int) -> String:
	return String(_slots[slot].get("id", ""))


func item_count(slot: int) -> int:
	return int(_slots[slot].get("count", 0))


# Adds items (hotbar first, filling existing stacks before empty slots). Returns how many did not fit.
func add(id: String, count: int) -> int:
	var left := count
	var limit: int = _db.stack_max(id)
	for i in SIZE:
		if left > 0 and item_id(i) == id and item_count(i) < limit:
			var moved := mini(limit - item_count(i), left)
			_slots[i]["count"] = item_count(i) + moved
			left -= moved
	for i in SIZE:
		if left > 0 and item_id(i) == "":
			var moved := mini(limit, left)
			_slots[i] = {"id": id, "count": moved}
			left -= moved
	return left


# Left click on a slot: pick up, place, merge or swap the whole stack.
func click_slot(slot: int) -> void:
	var here := _slots[slot]
	if cursor.is_empty():
		cursor = here
		_slots[slot] = {}
	elif here.is_empty():
		_slots[slot] = cursor
		cursor = {}
	elif here["id"] == cursor["id"] and not here.has("gun"):
		var room: int = _db.stack_max(here["id"]) - int(here["count"])
		var moved := mini(room, int(cursor["count"]))
		here["count"] = int(here["count"]) + moved
		cursor["count"] = int(cursor["count"]) - moved
		if int(cursor["count"]) <= 0:
			cursor = {}
	else:
		_slots[slot] = cursor
		cursor = here


# Right click on a slot: pick up half, or place a single item.
func right_click_slot(slot: int) -> void:
	var here := _slots[slot]
	if cursor.is_empty():
		if here.is_empty():
			return
		if here.has("gun"):
			cursor = here
			_slots[slot] = {}
			return
		var take := ceili(int(here["count"]) / 2.0)
		cursor = {"id": here["id"], "count": take}
		here["count"] = int(here["count"]) - take
		if int(here["count"]) <= 0:
			_slots[slot] = {}
	elif here.is_empty() and cursor.has("gun"):
		_slots[slot] = cursor
		cursor = {}
	elif here.is_empty():
		_slots[slot] = {"id": cursor["id"], "count": 1}
		_take_from_cursor()
	elif here["id"] == cursor["id"] and not here.has("gun") and int(here["count"]) < _db.stack_max(here["id"]):
		here["count"] = int(here["count"]) + 1
		_take_from_cursor()
	else:
		click_slot(slot)


# How many of `id` are in the main inventory (not equipment).
func count_of(id: String) -> int:
	var n := 0
	for i in SIZE:
		if item_id(i) == id:
			n += item_count(i)
	return n


# Removes up to `count` of `id`. Returns how many were removed.
func remove(id: String, count: int) -> int:
	var left := count
	for i in range(SIZE - 1, -1, -1):
		if left > 0 and item_id(i) == id:
			var taken := mini(item_count(i), left)
			_slots[i]["count"] = item_count(i) - taken
			left -= taken
			if item_count(i) <= 0:
				_slots[i] = {}
	return count - left


# True if the cursor item may go in this equipment slot.
func can_equip_cursor(slot: String) -> bool:
	if cursor.is_empty():
		return false
	var wanted: String = _db.equip_slot(cursor["id"])
	return wanted == slot or (wanted == "ring" and slot.begins_with("ring_"))


# Click on an equipment slot: pick up what is worn, or wear the cursor item (swapping).
func click_equipment(slot: String) -> void:
	if cursor.is_empty():
		cursor = equipment[slot]
		equipment[slot] = {}
	elif can_equip_cursor(slot):
		var old: Dictionary = equipment[slot]
		equipment[slot] = {"id": cursor["id"], "count": 1}
		cursor = old


# Puts the cursor stack back into the inventory (call when the screen closes).
func return_cursor() -> void:
	if cursor.is_empty():
		return
	if cursor.has("gun"):
		if add_gun(cursor["gun"]):
			cursor = {}
		return
	var left := add(String(cursor["id"]), int(cursor["count"]))
	cursor = {} if left == 0 else {"id": cursor["id"], "count": left}


func to_dict() -> Dictionary:
	var out: Array = []
	for s in _slots:
		if s.is_empty():
			out.append([])
		elif s.has("gun"):
			out.append([s["id"], s["count"], s["gun"]])
		else:
			out.append([s["id"], s["count"]])
	var worn := {}
	for slot in EQUIP_SLOTS:
		if not equipment[slot].is_empty():
			worn[slot] = equipment[slot]["id"]
	return {"version": VERSION, "slots": out, "equipment": worn}


func from_dict(data: Dictionary) -> void:
	load_equipment(data.get("equipment", {}))
	var saved: Array = data.get("slots", [])
	for i in mini(SIZE, saved.size()):
		_slots[i] = {}
		var entry = saved[i]
		if entry is Array and entry.size() == 3 and String(entry[0]) == "gun" and entry[2] is Dictionary:
			if _gun_db != null and GunGen.validate(_gun_db, entry[2]) == "":
				_slots[i] = {"id": "gun", "count": 1, "gun": entry[2]}
		elif entry is Array and entry.size() == 2 and String(entry[0]) != "gun" and _db.has_item(String(entry[0])):
			var count := clampi(int(entry[1]), 1, _db.stack_max(String(entry[0])))
			_slots[i] = {"id": String(entry[0]), "count": count}


func load_equipment(worn: Dictionary) -> void:
	for slot in EQUIP_SLOTS:
		equipment[slot] = {}
		var id := String(worn.get(slot, ""))
		if id != "" and _db.has_item(id) and _db.equip_slot(id) != "":
			equipment[slot] = {"id": id, "count": 1}


func _take_from_cursor() -> void:
	cursor["count"] = int(cursor["count"]) - 1
	if int(cursor["count"]) <= 0:
		cursor = {}
