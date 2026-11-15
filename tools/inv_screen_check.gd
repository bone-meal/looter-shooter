# Purpose: checks the inventory screen's card buttons (Equip / Unequip / Wear / Take off / Drop) and the tabs without a
# window: run tools/inv_screen_check.tscn; prints and writes tools/inv_screen_check.log: INV_SCREEN problems=N. Dependencies: game/inventory_screen.gd and the
# core inventory, item and gun data.
extends Node

const Screen = preload("res://game/inventory_screen.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const DataStore = preload("res://core/data_store.gd")

var _problems := 0
var _log: Array[String] = []


func _ready() -> void:
	var items := ItemDb.new(DataStore.load_json("res://data/items.json"))
	var gun_db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	var inv := InventoryState.new(items)
	inv.set_gun_db(gun_db)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var gun_a: Dictionary = GunGen.generate(gun_db, rng, 0.0, "ak47", "purple", "", 5)
	var gun_b: Dictionary = GunGen.generate(gun_db, rng, 0.0, "m16", "blue", "", 5)
	inv.add_gun(GunGen.generate(gun_db, rng, 0.0, "m16", "green", "", 5))  # the two holsters first
	inv.add_gun(GunGen.generate(gun_db, rng, 0.0, "m16", "green", "", 5))
	inv.add_gun(gun_a)
	inv.add_gun(gun_b)
	inv.set_holster_count(3)  # one free holster for Equip
	var ring := ""
	for id: String in items._items.keys():
		if items.equip_slot(id) == "ring":
			ring = id
	inv.add(ring, 1)
	inv.add("worm", 2)
	var s := Screen.new()
	s.inventory = inv
	s.items = items
	s.gun_db = gun_db
	add_child(s)
	s.tab = "guns"
	s._make_order()
	_expect(s._order.size() > 0 and s._order[0] == 0 and s._order[1] == 1 and inv.item_id(s._order[2]) == "", "guns tab: the two guns then empties")
	s.tab = "gear"
	s._make_order()
	_expect(inv.item_id(s._order[0]) == ring, "gear tab: the ring first")
	s.tab = "items"
	s._make_order()
	_expect(inv.item_id(s._order[0]) == "worm", "items tab: the worms first")
	s.tab = "all"
	s._make_order()
	_expect(s._order.size() == inv.SIZE, "all tab: every slot")
	var free := inv.free_holster()
	s._focus = 0
	_expect(s._actions().size() == 2, "a backpack gun offers Equip and Drop")
	s._act("equip")
	_expect(inv.holster_gun(free) == gun_a and inv.item_id(0) == "", "Equip put the gun in the free holster")
	s._act("unequip")
	_expect(inv.gun_at(s._focus) == gun_a and inv.holster_gun(free).is_empty(), "Unequip put it back in the backpack")
	var ring_slot := -1
	for i in inv.SIZE:
		if inv.item_id(i) == ring:
			ring_slot = i
	s._focus = ring_slot
	s._act("wear")
	_expect(inv.equipment["ring_1"].get("id", "") == ring, "Wear put the ring on")
	s._act("take_off")
	_expect(inv.equipment["ring_1"].is_empty() and inv.item_id(s._focus) == ring, "Take off put it back")
	var dropped := []
	s.dropped.connect(func(g: Dictionary) -> void: dropped.append(g))
	for i in inv.SIZE:
		if inv.gun_at(i) == gun_b:
			s._focus = i
	s._act("drop")
	_expect(dropped.size() == 1 and dropped[0] == gun_b, "Drop handed the gun to the session")
	_expect(inv.cursor.is_empty(), "nothing left on the mouse")
	print("INV_SCREEN problems=%d" % _problems)
	var f := FileAccess.open("res://tools/inv_screen_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_log) + "\nINV_SCREEN problems=%d\n" % _problems)
	f.close()
	s.free()
	get_tree().quit()


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_problems += 1
		print("PROBLEM: " + what)
		_log.append("PROBLEM: " + what)


func _json(shot_name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % shot_name))
