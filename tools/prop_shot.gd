# Purpose: developer check. Stands fantasy prop models (houses, walls, gates ...) in a row with the materials the game
# gives them and saves two pictures, front and back three-quarter, to res://tools/shots/prop_<name>_a.jpg / _b.jpg,
# plus triangles and draw calls to tools/prop_shot.log. Models and name come after `--`:
# `--models=cottage_amber,hall_amber --name=amber`.
# Dependencies: game/fantasy_models.gd, game/surface_library.gd.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")


func _ready() -> void:
	var models := PackedStringArray()
	var title := "row"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--models="):
			models = arg.trim_prefix("--models=").split(",", false)
		elif arg.begins_with("--name="):
			title = arg.trim_prefix("--name=")
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
	sun.rotation_degrees = Vector3(-42, 205, 0)
	sun.light_energy = 1.9
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	floor_mesh.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.3, 0.33, 0.2)
	floor_mesh.material_override = ground
	add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.current = true
	SurfaceLibrary.configure(true, "1k", 2)
	var x := 0.0
	var tallest := 1.0
	var deep := 1.0
	for id in models:
		var made := FantasyModels.scene(id)
		if made == null:
			continue
		add_child(made)
		var size := FantasyModels.bounds(made)
		x += size.size.x * 0.5 + 1.2
		made.position = Vector3(x, 0, 0)
		x += size.size.x * 0.5 + 1.2
		tallest = maxf(tallest, size.size.y)
		deep = maxf(deep, size.size.z)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var lines := PackedStringArray()
	var back := maxf(x * 0.62, tallest * 1.5) + deep
	var views := {"a": Vector3(x * 0.5 + back * 0.45, tallest * 0.75, -back), "b": Vector3(x * 0.5 - back * 0.45, tallest * 0.9, back)}
	for view: String in views:
		camera.position = views[view]
		camera.look_at(Vector3(x * 0.5, tallest * 0.42, 0))
		for _i in 4:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("res://tools/shots/prop_%s_%s.jpg" % [title, view], 0.9)
		lines.append("%s %s: draws=%d tris=%d" % [title, view, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	lines.append("PROP_SHOT_DONE")
	var f := FileAccess.open("res://tools/prop_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
