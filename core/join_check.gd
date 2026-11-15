# Purpose: the host's check of a joining player's profile (name, items, holsters, equipment) against the item data. Returns "" when fine, else a short reason.
# Dependencies: core/inventory_state.gd (sizes, slot names), core/item_db.gd (passed in).
extends RefCounted

const InventoryState = preload("res://core/inventory_state.gd")
const ArmourGen = preload("res://core/armour_gen.gd")

const MAX_NAME := 20


static func check(profile: Variant, db: RefCounted) -> String:
	if not (profile is Dictionary):
		return "bad profile"
	var p: Dictionary = profile
	var player_name: Variant = p.get("name")
	if not (player_name is String) or String(player_name).strip_edges().is_empty() or String(player_name).length() > MAX_NAME:
		return "bad name"
	var inv: Variant = p.get("inv")
	if not (inv is Dictionary):
		return "no inventory"
	if inv.get("version", -1) != InventoryState.VERSION:
		return "game version mismatch"
	var slots: Variant = inv.get("slots")
	if not (slots is Array) or slots.size() > InventoryState.SIZE:
		return "bad inventory"
	var ready: Variant = inv.get("holsters")
	if not (ready is Array) or ready.size() > InventoryState.HOLSTERS:
		return "bad inventory"
	for entry in ready:
		if entry is Array and entry.size() == 2 and entry[0] is String and db.has_item(entry[0]) and db.kind(entry[0]) != "weapon":
			return "not a gun in a holster"
	for entry in slots + ready:
		if not (entry is Array):
			return "bad inventory"
		if entry.is_empty():
			continue
		if entry.size() == 3 and entry[0] is String and entry[2] is Dictionary:  # a rolled gun (the host checks guns where they are used) or armour piece
			if entry[0] != "gun" and ArmourGen.validate(db, entry[0], entry[2]) != "":
				return "impossible armour piece"
			continue
		if entry.size() != 2 or not (entry[0] is String) or not (entry[1] is int):
			return "bad inventory"
		if not db.has_item(entry[0]):
			return "unknown item"
		if entry[1] < 1 or entry[1] > db.stack_max(entry[0]):
			return "impossible item count"
	var worn: Variant = inv.get("equipment")
	if not (worn is Dictionary):
		return "bad equipment"
	for slot in worn:
		if not (slot is String) or not InventoryState.EQUIP_SLOTS.has(slot):
			return "bad equipment slot"
		var id: Variant = worn[slot]
		if id is Array and id.size() == 3 and id[0] is String:  # a rolled piece
			if ArmourGen.validate(db, id[0], id[2]) != "":
				return "impossible armour piece"
			id = id[0]
		if not (id is String) or not db.has_item(id) or not (db.equip_slot(id) == slot or (db.equip_slot(id) == "ring" and String(slot).begins_with("ring_"))):
			return "item in wrong slot"
	return ""
