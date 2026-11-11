# Purpose: developer render of world gun drops (one per tier, beams + name tags) and the three vendor kiosks. Saves tools/shots/loot_a.png and loot_b.png (a second time, to show the animated colours) and quits. Run scene tools/loot_shot.tscn.
# Dependencies: game/loot_field.gd, game/gun_vendor.gd, core/gun_db.gd, core/gun_gen.gd, core/data_store.gd.
extends Node3D

const LootField = preload("res://game/loot_field.gd")
const GunVendor = preload("res://game/gun_vendor.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const DataStore = preload("res://core/data_store.gd")

var _t := 0.0
var _shot := 0


func _ready() -> void:
	get_window().size = Vector2i(1152, 648)
	var db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.06, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	floor_mesh.mesh = pm
	add_child(floor_mesh)
	var field := LootField.new()
	field.setup(db, DataStore.load_json("res://data/drops.json"))
	add_child(field)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var tiers := ["grey", "green", "blue", "purple", "gold", "orange", "rainbow", "pony"]
	for i in 8:
		field.spawn(GunGen.generate(db, rng, 0.0, "ak47", tiers[i]), Vector3(-7.0 + 2.0 * float(i), 0.0, 0.0))
	var crates: Array = DataStore.load_json("res://data/gun_loot.json")["vendor"]
	for i in crates.size():
		var v := GunVendor.new()
		v.crate = crates[i]
		v.position = Vector3(-3.0 + 3.0 * float(i), 0.0, 6.0)
		v.rotation_degrees.y = 90.0
		add_child(v)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.2, 11.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.6, 0.0), Vector3.UP)
	cam.current = true


func _process(delta: float) -> void:
	_t += delta
	if _shot == 0 and _t > 1.2:
		_save("loot_a")
		_shot = 1
	elif _shot == 1 and _t > 2.4:
		_save("loot_b")
		get_tree().quit()


func _save(shot_name: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/shots/%s.png" % shot_name))
