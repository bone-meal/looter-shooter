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
	if OS.get_cmdline_user_args().has("--beasts") or FileAccess.file_exists("res://tools/sea_creature_beasts.txt"):  # sea step 8e: the region creatures, out of the water (the file: a run from the editor tool)
		await _beasts()
		get_tree().quit()
		return
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


# Sea step 8e: Sunskate (wings up), Fogmaw (lure up, mouth open), Cinder Turtle - side by side above the water.
func _beasts() -> void:
	var placed := {}
	var x := -9.0
	for id: String in ["sea_sunskate", "sea_fogmaw", "sea_cinder_turtle", "sea_orca", "sea_squallbeak", "sea_siren_rock", "sea_siren"]:
		var own: Array[StandardMaterial3D] = []
		var body := FantasyModels.creature(id, Color(0.9, 0.5, 0.2), own)
		if body == null:
			continue
		add_child(body)
		body.position = Vector3(x, 0.4, 0.0) if id != "sea_siren" else Vector3(x - 9.0, 1.9, 0.0)  # (the siren sits on her rock)
		body.rotation.y = 2.3
		placed[id] = body
		x += 9.0
	var skate: Node3D = placed.get("sea_sunskate")
	if skate != null:
		for wing: String in ["WingL", "WingR"]:
			var w := skate.find_child(wing, true, false) as Node3D
			if w != null:
				w.rotation.z = 0.4 if wing == "WingL" else -0.4
	var eel: Node3D = placed.get("sea_fogmaw")
	if eel != null:
		var jaw := eel.find_child("Jaw", true, false) as Node3D
		if jaw != null:
			jaw.rotation.x = 0.5
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for v: Array in [["beasts2", Vector3(27, 8, 18), Vector3(27, 0.5, 0)], ["orca", Vector3(22, 3, 6), Vector3(18, 0.8, 0)], ["gull", Vector3(28.5, 2, 3), Vector3(27, 0.5, 0)], ["siren", Vector3(36, 3, 4.5), Vector3(36, 2.2, 0)], ["beasts", Vector3(0, 7, 15), Vector3(0, 0.5, 0)], ["skate", Vector3(-5, 3, 4), Vector3(-9, 0.5, 0)], ["fogmaw", Vector3(4, 2.5, 4), Vector3(0, 0.6, -1)], ["turtle", Vector3(13, 3, 5), Vector3(9, 0.8, 0)]]:
		cam.position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for i in 8:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("res://tools/shots/seacreature_%s.jpg" % v[0], 0.88)
