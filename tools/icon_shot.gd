# Purpose: developer picture of the item icons in the real inventory window at 1920 x 1080 (tools/shots/icon_shot.png and
# icon_shot_card.png): rolled armour of every tier at rising item levels, rolled guns of several tiers, the docked card
# of a long-named pony gun (scrolling) and of an armour piece.
# Dependencies: game/inventory_screen.gd, core inventory / item / gun data, core/armour_gen.gd.
extends Node

const Screen = preload("res://game/inventory_screen.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const ArmourGen = preload("res://core/armour_gen.gd")
const DataStore = preload("res://core/data_store.gd")


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var items := ItemDb.new(DataStore.load_json("res://data/items.json"))
	var gun_db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	var inv := InventoryState.new(items)
	inv.set_gun_db(gun_db)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	inv.add_gun(GunGen.unique(gun_db, "mixtape", 30))
	inv.add_gun(GunGen.generate(gun_db, rng, 0.0, "lever_rifle", "pony", "", 55))
	var tiers := ["grey", "green", "blue", "purple", "gold", "orange", "rainbow", "pony"]
	var pieces := ["iron_helm", "captains_tricorn", "diving_helm", "coral_cuirass", "compass_pendant", "kraken_band", "storm_goggles", "brass_sabatons",
		"tin_hat", "pearl_studs", "steel_chestplate", "sharkskin_gloves", "ember_ring", "rope_bracelet", "storm_cloak", "sea_boots"]
	for i in pieces.size():
		inv.add_armour(ArmourGen.generate(items, rng, tiers[i % 8], 1 + i * 4, pieces[i], "auto"))
	for b: String in ["smg", "revolver", "crossbow", "flamethrower", "blunderbuss", "harpoon_gun", "flare_gun", "ak47"]:
		inv.add_gun(GunGen.generate(gun_db, rng, 0.0, b, tiers[rng.randi_range(1, 7)], "", rng.randi_range(5, 70)))
	inv.equipment["head"] = ArmourGen.generate(items, rng, "gold", 40, "diving_helm", "tidecaller")
	inv.equipment["ring_1"] = ArmourGen.generate(items, rng, "pony", 66, "kraken_band", "")
	var s := Screen.new()
	s.inventory = inv
	s.items = items
	s.gun_db = gun_db
	add_child(s)
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.knife_id = "kukri"
	s.knife_name = "Kukri"
	s.open()
	s.tab = "all"
	s._focus = Screen.HOLSTER_BASE + 1
	s._redraw_all()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shots/icon_shot.png")
	s._focus = 2 + 4
	s._redraw_all()
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shots/icon_shot_card.png")
	get_tree().quit()


func _json(file: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % file))
