# Purpose: developer check of the reworked enemies (polish1 D2): every style of data/enemy_moves.json on its model
# (game/fantasy_models.gd creature + game/enemy_rig.gd), one row per enemy in five poses - standing, two moments of
# its gait at full speed, the top of its wind-up, the blow - from the front and the side, saved to
# res://tools/shots/enemies_<view>.jpg; draw calls and triangles to tools/enemy_shot.log.
# Dependencies: game/fantasy_models.gd, game/enemy_rig.gd, game/surface_library.gd, data/enemy_moves.json.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")
const EnemyRig = preload("res://game/enemy_rig.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")
const RigidSkin = preload("res://game/rigid_skin.gd")


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.62)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.7
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.38, 0.28)
	ground.material_override = gm
	add_child(ground)
	SurfaceLibrary.configure(true, "1k", 3)
	var moves: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_moves.json"))
	var styles: Dictionary = moves["styles"]
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	if only.is_empty() and FileAccess.file_exists("res://tools/enemy_shot_only.txt"):  # (a run from the editor cannot pass arguments)
		only = FileAccess.get_file_as_string("res://tools/enemy_shot_only.txt").strip_edges().split(",", false)
	var ids: Array = styles.keys() if only.is_empty() else Array(only)
	var lines := PackedStringArray()
	var rigs: Array = []
	var states := [[0.0, 0.0, 0.0, 0.0], [1.0, PI * 0.5, 0.0, 0.0], [1.0, PI * 1.5, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]]
	for row in ids.size():
		var id := String(ids[row])
		if not FantasyModels.has_creature(id):
			lines.append("%s: NO MODEL" % id)
			continue
		var style: Dictionary = styles[id]
		var full := float((style.get("gait", {}) as Dictionary).get("full_at", 3.0))
		for col in states.size():
			var own: Array[StandardMaterial3D] = []
			var body := FantasyModels.creature(id, Color(0.6, 1.0, 0.95), own)
			add_child(body)
			body.position = Vector3(float(col) * 2.2, 0.0, -float(row) * 3.0)
			RigidSkin.fold(body, id)
			var rig := EnemyRig.new()
			var dice := RandomNumberGenerator.new()
			dice.seed = col + row * 7
			rig.setup(body, style, dice)
			var st: Array = states[col]
			rigs.append([rig, float(st[0]) * full, float(st[1]), float(st[2]), float(st[3])])
	for _i in 3:
		for r: Array in rigs:
			(r[0] as EnemyRig).pose(0.016, float(r[1]), float(r[2]), float(r[3]), float(r[4]), 0.0, 0.0, false)
	var camera := Camera3D.new()
	camera.fov = 38.0
	add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var mid := Vector3(4.4, 1.0, -float(ids.size() - 1) * 1.5)
	for view: String in ["front", "side"]:
		camera.position = mid + (Vector3(0.0, 2.2, -float(ids.size()) * 2.6 - 4.0) if view == "front" else Vector3(-float(ids.size()) * 2.4 - 6.0, 2.2, 0.0))  # they face -z
		camera.look_at(mid)
		for _f in 4:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("res://tools/shots/enemies_%s.jpg" % view, 0.9)
		lines.append("%s: draws=%d tris=%d for %d bodies" % [view, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), rigs.size()])
	lines.append("ENEMY_SHOT_DONE")
	var f := FileAccess.open("res://tools/enemy_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
