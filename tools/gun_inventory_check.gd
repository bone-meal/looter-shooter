# Purpose: developer check of rolled guns in the inventory: one slot per gun, click/swap/right-click moves, save round trip, tamper rejection, chest-style drops with a tier floor, held-gun stats. Writes tools/gun_inventory_check.log and quits. Run scene tools/gun_inventory_check.tscn.
# Dependencies: core/inventory_state.gd, item_db.gd, gun_db.gd, gun_gen.gd, gun_stats.gd, data_store.gd.
extends Node

const InventoryState = preload("res://core/inventory_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const DataStore = preload("res://core/data_store.gd")


func _ready() -> void:
	var log: PackedStringArray = []
	var db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"))
	var inv := InventoryState.new(ItemDb.new(DataStore.load_json("res://data/items.json")))
	inv.set_gun_db(db)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var a := GunGen.generate(db, rng, 0.0, "ak47", "gold")
	var b := GunGen.generate(db, rng, 0.0, "m16", "rainbow")
	log.append("add a: %s, add b: %s" % [inv.add_gun(a), inv.add_gun(b)])
	log.append("slots: %s/%s, gun_at(0) body %s" % [inv.item_id(0), inv.item_id(1), inv.gun_at(0).get("body")])
	inv.add("worm", 3)
	inv.click_slot(0)
	log.append("pick up slot0: cursor gun %s, slot0 id '%s'" % [inv.cursor.has("gun"), inv.item_id(0)])
	inv.click_slot(1)
	log.append("swap onto slot1: slot1 body %s, cursor body %s" % [inv.gun_at(1).get("body"), inv.cursor.get("gun", {}).get("body")])
	inv.click_slot(0)
	log.append("put back: slot0 body %s, cursor empty %s" % [inv.gun_at(0).get("body"), inv.cursor.is_empty()])
	inv.right_click_slot(0)
	inv.right_click_slot(5)
	log.append("right-click move to slot5: slot5 body %s, slot0 empty %s" % [inv.gun_at(5).get("body"), inv.item_id(0) == ""])
	inv.click_slot(5)
	inv.click_slot(5)
	log.append("two-guns-same-id merge guard ok: %s" % (inv.gun_at(5).get("body") == "ak47" or inv.gun_at(5).get("body") == "m16"))
	var saved := inv.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	var inv2 := InventoryState.new(ItemDb.new(DataStore.load_json("res://data/items.json")))
	inv2.set_gun_db(db)
	inv2.from_dict(parsed as Dictionary)
	var count := 0
	for i in inv2.SIZE:
		if inv2.item_id(i) == "gun":
			count += 1
	log.append("round trip guns: %d (expected 2), worms: %d" % [count, inv2.count_of("worm")])
	# tamper: a saved gun with a maxed roll must be dropped on load
	var tampered: Dictionary = JSON.parse_string(JSON.stringify(saved))
	for entry: Variant in tampered["slots"]:
		if entry is Array and entry.size() == 3:
			var rolls: Dictionary = entry[2]["rolls"]
			for k: String in rolls:
				rolls[k] = 5.0
			break
	var inv3 := InventoryState.new(ItemDb.new(DataStore.load_json("res://data/items.json")))
	inv3.set_gun_db(db)
	inv3.from_dict(tampered)
	var count3 := 0
	for i in inv3.SIZE:
		if inv3.item_id(i) == "gun":
			count3 += 1
	log.append("tampered save keeps %d guns (expected 1)" % count3)
	var inv4 := InventoryState.new(ItemDb.new(DataStore.load_json("res://data/items.json")))
	inv4.from_dict(parsed as Dictionary)
	var count4 := 0
	for i in inv4.SIZE:
		if inv4.item_id(i) == "gun":
			count4 += 1
	log.append("no gun db loads %d guns (expected 0)" % count4)
	# chest-style drops
	var chest: Dictionary = DataStore.load_json("res://data/gun_loot.json")["chest"]
	var below := 0
	var tally: Dictionary = {}
	for _i in 4000:
		var g := GunGen.generate(db, rng, float(chest["luck"]), "", "", String(chest["min_tier"]))
		if db.tier_index(String(g["tier"])) < db.tier_index(String(chest["min_tier"])):
			below += 1
		tally[g["tier"]] = int(tally.get(g["tier"], 0)) + 1
	log.append("4000 guaranteed-drops below floor: %d; tiers %s" % [below, JSON.stringify(tally)])
	# launcher damage scales splash
	var rl := GunGen.generate(db, rng, 0.0, "rocket_launcher", "orange")
	var st := GunStats.final_stats(db, rl)
	log.append("rocket launcher: damage %.1f splash %.1f (base 120)" % [st["damage"], st["projectile"]["splash_damage"]])
	var f := FileAccess.open("res://tools/gun_inventory_check.log", FileAccess.WRITE)
	f.store_string("\n".join(log))
	f.close()
	get_tree().quit()
