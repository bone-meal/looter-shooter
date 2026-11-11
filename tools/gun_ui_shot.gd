# Purpose: developer render of the inventory screen with rolled guns of every tier and a hover tooltip (compare vs the held gun). Saves tools/shots/gun_ui_a.png and gun_ui_b.png, then quits. Run scene tools/gun_ui_shot.tscn.
# Dependencies: game/inventory_screen.gd, core/inventory_state.gd, gun_db.gd, gun_gen.gd, item_db.gd, data_store.gd.
extends Node

const InventoryScreen = preload("res://game/inventory_screen.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const DataStore = preload("res://core/data_store.gd")

var _screen: Control
var _t := 0.0
var _shot := 0


func _ready() -> void:
	get_window().size = Vector2i(1152, 648)
	var db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"))
	var items := ItemDb.new(DataStore.load_json("res://data/items.json"))
	var inv := InventoryState.new(items)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var bodies := ["ak47", "m16", "shotgun_double", "sniper_basic", "pistol_basic", "m60", "rocket_launcher", "grenade_launcher"]
	var tiers := ["gold", "grey", "green", "blue", "purple", "orange", "rainbow", "pony"]
	for i in 8:
		inv.add_gun(GunGen.generate(db, rng, 0.0, bodies[i], tiers[i]))
	var layer := CanvasLayer.new()
	add_child(layer)
	_screen = InventoryScreen.new()
	_screen.inventory = inv
	_screen.items = items
	_screen.gun_db = db
	_screen.selected_hotbar = 0
	layer.add_child(_screen)
	_screen.open()
	await get_tree().process_frame
	_screen._mouse = _screen._slot_rect(6).get_center()


func _process(delta: float) -> void:
	_t += delta
	if _shot == 0 and _t > 1.0:
		_save("gun_ui_a")
		_shot = 1
		_screen._mouse = _screen._slot_rect(7).get_center()
	elif _shot == 1 and _t > 1.9:
		_save("gun_ui_b")
		get_tree().quit()


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/shots/%s.png" % name))
