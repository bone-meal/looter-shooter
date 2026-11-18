# Purpose: developer check for the ship holds (sea step 8b-2): loads each ship with a hold (data/sea/ships.json
# "hold") as the game dresses it and saves pictures from inside the hold and down the hatch into tools/shots/hold_*.jpg.
# Run: the scene tools/hold_shot.tscn (a window; a few seconds).
# Dependencies: game/fantasy_models.gd, data/sea/ships.json, assets/models/sea/ship_<id>.gltf.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.current = true
	var ships: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/ships.json")) as Dictionary)["ships"]
	for id: String in ships:
		var sp: Dictionary = ships[id]
		if not sp.has("hold"):
			continue
		var model := (load(String(sp["model"])) as PackedScene).instantiate() as Node3D
		add_child(model)
		for found in model.find_children("*", "MeshInstance3D", true, false):
			FantasyModels.dress((found as MeshInstance3D).mesh)
		var h: Dictionary = sp["hold"]
		var st: Dictionary = h["stair"]
		var d := float(sp["deck"])
		var fl := float(h["floor"])
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.75, 0.45)
		lamp.light_energy = 1.6
		lamp.omni_range = 7.0
		lamp.position = Vector3(float(h["lamp"][0]), d - 0.55, float(h["lamp"][1]))
		model.add_child(lamp)
		var foot_z := float(st["low"]) - signf(float(st["high"]) - float(st["low"])) * 0.6
		var views := [
			["in", Vector3(-float(h["hw"]) + 0.5, fl + 1.6, float(h["to"]) - 0.4), Vector3(float(h["hw"]) * 0.3, fl + 0.6, float(h["from"]))],
			["chest", Vector3(0.0, fl + 1.6, foot_z), Vector3(float(h["chest"][0]), fl + 0.3, float(h["chest"][1]))],
			["stair", Vector3(float(st["x"]) + 0.3, fl + 1.5, foot_z - signf(float(st["high"]) - float(st["low"])) * 1.2), Vector3(float(st["x"]), d + 0.8, float(st["high"]) + 1.0)],
			["deck", Vector3(float(st["x"]) + 2.0, d + 2.6, float(st["high"]) + 3.0), Vector3(float(st["x"]), d - 0.5, (float(st["low"]) + float(st["high"])) * 0.5)],
		]
		for v: Array in views:
			cam.position = v[1]
			cam.look_at(v[2], Vector3.UP)
			for i in 8:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("res://tools/shots/hold_%s_%s.jpg" % [id, v[0]], 0.88)
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit()
