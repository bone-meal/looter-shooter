# Purpose: developer check for the sea creatures (sea step 8c): the shark and the Tide Wyrm as the game dresses them
# (game/fantasy_models.gd), the wyrm's segments laid on a wave like game/sea_serpent.gd does; pictures into
# tools/shots/seacreature_*.jpg. Run the scene tools/sea_creature_shot.tscn.
# Dependencies: game/fantasy_models.gd, game/sea_serpent.gd (lay_body), assets/models/fantasy/creatures/sea_*.gltf.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")
const SeaSerpent = preload("res://game/sea_serpent.gd")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	water.mesh = plane
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.45, 0.55, 0.55)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wm
	add_child(water)
	var own: Array[StandardMaterial3D] = []
	var shark := FantasyModels.creature("sea_shark", Color(0.2, 0.2, 0.2), own)
	shark.position = Vector3(-6, -0.55, 0)
	shark.rotation.y = 0.6
	add_child(shark)
	var own2: Array[StandardMaterial3D] = []
	var wyrm := FantasyModels.creature("sea_serpent", Color(0.4, 0.9, 1.0), own2)
	add_child(wyrm)
	wyrm.position = Vector3(6, 0, -4)
	wyrm.rotation.y = -0.4
	SeaSerpent.lay_body(wyrm, 1.3, 1.0, 0.0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for v: Array in [["shark", Vector3(-3.5, 1.4, 3.0), Vector3(-6, -0.2, 0)], ["wyrm", Vector3(-2, 6, 14), Vector3(4, 1.5, -10)], ["wyrm_head", Vector3(9.5, 2.5, -1.5), Vector3(6, 1.2, -4)]]:
		cam.position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for i in 8:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("res://tools/shots/seacreature_%s.jpg" % v[0], 0.88)
	get_tree().quit()
