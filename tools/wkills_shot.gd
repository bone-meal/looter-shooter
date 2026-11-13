# Purpose: developer picture of the "W kills" counter on all eight gun models (left side towards the camera, as the
# player sees a held gun). Saves tools/shots/wkills.jpg and quits. Needs a display (not headless).
# Dependencies: game/weapon_models.gd, game/wkills_display.gd.
extends Node3D

const WeaponModels = preload("res://game/weapon_models.gd")
const WKillsDisplay = preload("res://game/wkills_display.gd")
const BODIES := ["pistol_basic", "ak47", "m16", "m60", "shotgun_double", "sniper_basic", "rocket_launcher", "grenade_launcher"]


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -60, 0)
	add_child(sun)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.45, 0.55, 0.65)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(world)
	for i in BODIES.size():
		var model := WeaponModels.build(String(BODIES[i]))
		add_child(model)
		model.rotation_degrees = Vector3(0, -90, 0)  # muzzle (-Z) to the right, left side (-X) to the camera
		model.position = Vector3(float(i % 4) * 1.1 - 1.65, 1.0 - float(floori(float(i) / 4.0)) * 0.8, 0)
		WKillsDisplay.show(model, {"wkills": 1234})
	var eye := Camera3D.new()
	eye.position = Vector3(0, 0.6, -3.2)
	eye.rotation_degrees = Vector3(0, 180, 0)
	eye.fov = 14.0
	eye.current = true
	add_child(eye)
	for _f in 8:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://tools/shots/wkills.jpg"), 0.9)
	get_tree().quit()
