# Purpose: pure inventory: the holsters (the guns carried ready: two, more with a perk or rare armour), a 36-slot
# backpack of stackable items, a cursor stack for mouse moves, and 18 equipment slots.
# A gun arriving goes into a free holster first. A ready gun's rounds are counted here (`loaded`); when it leaves its
# holster they are handed back through `returned` for whoever keeps the ammo pools (core/ammo_pools.gd).
# Dependencies: core/item_db.gd. Saved as IDs + counts with a version (to_dict / from_dict). No nodes, no rendering.
extends RefCounted

const SIZE := 36
const HOLSTERS := 4  # the most guns that can ever be carried ready
const FRESH := -1  # `loaded` of a gun that just arrived: its owner fills it from the pool the first time it is held
const VERSION := 4
const GunGen = preload("res://core/gun_gen.gd")
# Order matters: the equipment panel draws these in 3 columns of 6.
const EQUIP_SLOTS := ["hat", "head", "earrings", "necklace", "glasses", "mouth",
	"shirt", "chestplate", "gauntlets", "ring_1", "ring_2", "bracelet",
	"pants", "leg_armor", "cape", "waist", "boots", "foot_armor"]

var equipment := {}  # slot name -> {"id", "count"} or {}
var cursor := {}  # stack held by the mouse: {} or {"id": String, "count": int}
var holster_count := 2  # how many holsters are open
var holsters: Array[Dictionary] = []  # {} or a stack as in a slot: a plain weapon item or a rolled gun
var loaded: Array[int] = []  # rounds in each ready gun (FRESH = not loaded yet)
var returned := {}  # gun body -> rounds taken out of guns that left their holster, waiting to go back to the pool

var _db: RefCounted
var _gun_db: RefCounted  # core/gun_db.gd; guns in a save are checked against it (without it every saved gun is dropped)
var _slots: Array[Dictionary] = []


func _init(db: RefCounted) -> void:
	_db = db
	for i in SIZE:
		_slots.append({})
	for i in HOLSTERS:
		holsters.append({})
		loaded.append(0)
	for slot in EQUIP_SLOTS:
		equipment[slot] = {}


func set_gun_db(gun_db: RefCounted) -> void:
	_gun_db = gun_db


# The rolled gun in a slot ({} when the slot holds no gun).
func gun_at(slot: int) -> Dictionary:
	return _slots[slot].get("gun", {})


# Takes the rolled gun out of a slot, or off the mouse with slot -1, so it can be dropped into the world.
# {} when there is no rolled gun there (nothing is changed then).
func take_gun(slot: int) -> Dictionary:
	if slot < 0:
		var carried: Dictionary = cursor.get("gun", {})
		if not carried.is_empty():
			cursor = {}
		return carried
	var gun := gun_at(slot)
	if not gun.is_empty():
		_slots[slot] = {}
	return gun


# True for a stack that is a gun: a rolled one or a plain weapon item.
func is_weapon(stack: Dictionary) -> bool:
	return not stack.is_empty() and (stack.has("gun") or _db.kind(String(stack["id"])) == "weapon")


# The gun body of a stack ("" when it is no gun): what decides its model and its ammo pool.
func body_of(stack: Dictionary) -> String:
	if not is_weapon(stack):
		return ""
	return String(stack["gun"]["body"]) if stack.has("gun") else String(stack["id"])


func holster_body(index: int) -> String:
	return body_of(holsters[index])


# The rolled gun in a holster ({} for a plain weapon or an empty holster).
func holster_gun(index: int) -> Dictionary:
	return holsters[index].get("gun", {})


# The first open holster with nothing in it, -1 when all are taken.
func free_holster() -> int:
	for i in holster_count:
		if holsters[i].is_empty():
			return i
	return -1


# Click on a holster: pick up what is in it, or put the gun on the mouse there (swapping). Only guns go in, and a
# gun put there by hand starts empty: it has to be reloaded.
func click_holster(index: int) -> void:
	if index >= holster_count or (not cursor.is_empty() and not is_weapon(cursor)):
		return
	var old := holsters[index]
	_unload(index)
	holsters[index] = cursor
	cursor = old


# Opens or closes holsters. Guns in holsters that close go to the backpack; those that do not fit are returned
# (the caller lays them on the ground).
func set_holster_count(count: int) -> Array:
	holster_count = clampi(count, 1, HOLSTERS)
	var homeless: Array = []
	for i in range(holster_count, HOLSTERS):
		var stack := holsters[i]
		if stack.is_empty():
			continue
		_unload(i)
		holsters[i] = {}
		var slot := _empty_slot()
		if slot >= 0:
			_slots[slot] = stack
		else:
			homeless.append(stack)
	return homeless


# The rounds handed back by guns that left their holsters since the last call (gun body -> rounds).
func take_returned() -> Dictionary:
	var out := returned
	returned = {}
	return out


# Takes the gun out of a holster for good (sold, dropped, traded). {} when the holster is empty.
func take_holster(index: int) -> Dictionary:
	var stack := holsters[index]
	_unload(index)
	holsters[index] = {}
	return stack


func _unload(index: int) -> void:
	var body := holster_body(index)
	if body != "" and loaded[index] > 0:
		returned[body] = int(returned.get(body, 0)) + loaded[index]
	loaded[index] = 0


func _empty_slot() -> int:
	for i in SIZE:
		if _slots[i].is_empty():
			return i
	return -1


# Puts a rolled gun in a free holster, else in the first empty backpack slot. Returns false when there is no room.
func add_gun(gun: Dictionary) -> bool:
	var holster := free_holster()
	if holster >= 0:
		holsters[holster] = {"id": "gun", "count": 1, "gun": gun}
		loaded[holster] = FRESH
		return true
	for i in SIZE:
		if _slots[i].is_empty():
			_slots[i] = {"id": "gun", "count": 1, "gun": gun}
			return true
	return false


func item_id(slot: int) -> String:
	return String(_slots[slot].get("id", ""))


func item_count(slot: int) -> int:
	return int(_slots[slot].get("count", 0))


# Adds items (a gun to a free holster first; then existing stacks are filled before empty slots). Returns how many did not fit.
func add(id: String, count: int) -> int:
	var left := count
	var limit: int = _db.stack_max(id)
	while left > 0 and _db.kind(id) == "weapon" and free_holster() >= 0:
		var holster := free_holster()
		holsters[holster] = {"id": id, "count": 1}
		loaded[holster] = FRESH
		left -= 1
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


# How many of `id` are in the backpack and the holsters (not equipment).
func count_of(id: String) -> int:
	var n := 0
	for i in SIZE:
		if item_id(i) == id:
			n += item_count(i)
	for stack in holsters:
		if String(stack.get("id", "")) == id:
			n += 1
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


# Everything carried, taken off the player in one bundle: the ready guns and the whole backpack (what is worn stays).
# Rounds in the ready guns are handed back like any gun leaving its holster. The bundle is plain saved data.
func take_all() -> Dictionary:
	return_cursor()
	var things: Array = []
	for i in HOLSTERS:
		if not holsters[i].is_empty():
			_unload(i)
			things.append(_saved_stack(holsters[i]))
			holsters[i] = {}
	for i in SIZE:
		if not _slots[i].is_empty():
			things.append(_saved_stack(_slots[i]))
			_slots[i] = {}
	return {"things": things}


# Puts a bundle's things back (guns into free holsters first). Returns the bundle of what found no room.
func put_all(bundle: Variant) -> Dictionary:
	var rest: Array = []
	if bundle is Dictionary and bundle.get("things") is Array:
		for entry: Variant in bundle["things"]:
			var stack := _loaded_stack(entry)
			if stack.is_empty():
				continue
			if stack.has("gun"):
				if not add_gun(stack["gun"]):
					rest.append(_saved_stack(stack))
			else:
				var left := add(String(stack["id"]), int(stack["count"]))
				if left > 0:
					rest.append([stack["id"], left])
	return {"things": rest}


# How many stacks a bundle holds (0 for anything that is not one).
static func bundle_size(bundle: Variant) -> int:
	return (bundle["things"] as Array).size() if bundle is Dictionary and bundle.get("things") is Array else 0


# Puts the cursor stack back into the inventory (call when the screen closes). A gun goes to the backpack, or
# unloaded into a free holster when the backpack is full: it never comes back loaded for free.
func return_cursor() -> void:
	if cursor.is_empty():
		return
	if is_weapon(cursor):
		var slot := _empty_slot()
		if slot >= 0:
			_slots[slot] = cursor
			cursor = {}
		elif free_holster() >= 0:
			holsters[free_holster()] = cursor
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
	var ready: Array = []
	for i in HOLSTERS:
		ready.append(_saved_stack(holsters[i]))
	return {"version": VERSION, "slots": out, "equipment": worn, "holsters": ready, "loaded": loaded.duplicate()}


# One stack as it is written into a save, and back ({} for anything that is no known item or valid gun): for other
# places that keep stacks (the bank).
func stack_to_saved(s: Dictionary) -> Array:
	return _saved_stack(s)


func stack_from_saved(entry: Variant) -> Dictionary:
	return _loaded_stack(entry)


func _saved_stack(s: Dictionary) -> Array:
	if s.is_empty():
		return []
	return [s["id"], s["count"], s["gun"]] if s.has("gun") else [s["id"], s["count"]]


func from_dict(data: Dictionary) -> void:
	returned = {}
	load_equipment(data.get("equipment", {}))
	var saved: Array = data.get("slots", [])
	for i in mini(SIZE, saved.size()):
		_slots[i] = _loaded_stack(saved[i])
	var ready: Variant = data.get("holsters")
	var rounds: Variant = data.get("loaded")
	for i in HOLSTERS:
		holsters[i] = {}
		loaded[i] = 0
		if ready is Array and i < ready.size():
			var stack := _loaded_stack(ready[i])
			if is_weapon(stack):
				holsters[i] = stack
				loaded[i] = FRESH
				if rounds is Array and i < rounds.size() and (rounds[i] is int or rounds[i] is float):
					loaded[i] = clampi(int(rounds[i]), FRESH, 100000)
	if not ready is Array:  # a save from before the holsters: the first guns of the old hotbar (slots 0-8) are the ready ones
		for i in 9:
			var holster := free_holster()
			if holster >= 0 and is_weapon(_slots[i]):
				holsters[holster] = _slots[i]
				loaded[holster] = FRESH
				_slots[i] = {}
	set_holster_count(holster_count)  # nothing stays in a holster that is not open


# One saved stack back as a slot's stack; {} for anything that is not a known item or a valid gun.
func _loaded_stack(entry: Variant) -> Dictionary:
	if entry is Array and entry.size() == 3 and String(entry[0]) == "gun" and entry[2] is Dictionary:
		if _gun_db != null and GunGen.validate(_gun_db, entry[2]) == "":
			return {"id": "gun", "count": 1, "gun": entry[2]}
	elif entry is Array and entry.size() == 2 and String(entry[0]) != "gun" and _db.has_item(String(entry[0])):
		return {"id": String(entry[0]), "count": clampi(int(entry[1]), 1, _db.stack_max(String(entry[0])))}
	return {}


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
