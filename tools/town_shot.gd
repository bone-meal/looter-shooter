# Purpose: developer tool (sea step 7). Pictures of the home port town's building models, one at a time, framed
# close from the front three-quarter (a) and the back three-quarter (b): res://tools/shots/town_<model>_a/b.jpg;
# with --thumbs also the ledger's pictures of every level, res://assets/ui/town/<model>.png (360 x 220, a soft sky
# behind). Models after `--`: `--models=harbour_master_1,tavern_0 [--thumbs] [--only-thumbs]`; no list = every
# model in assets/models/sea/town/. Writes tools/town_shot.log (triangles and draw calls per model).
# Dependencies: game/fantasy_models.gd, game/surface_library.gd.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const DIR := "res://assets/models/sea/town/"


func _ready() -> void:
	var models := PackedStringArray()
	var thumbs := false
	var only_thumbs := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--models="):
			models = arg.trim_prefix("--models=").split(",", false)
		elif arg == "--thumbs":
			thumbs = true
		elif arg == "--only-thumbs":
			thumbs = true
			only_thumbs = true
	if models.is_empty():
		for file in DirAccess.get_files_at(DIR):
			if file.ends_with(".gltf") and file != "town_sign.gltf":
				models.append(file.get_basename())
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.66, 0.78, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.53, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	floor_mesh.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.2, 0.26, 0.13)
	floor_mesh.material_override = ground
	add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.current = true
	SurfaceLibrary.configure(true, "1k", 2)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/town"))
	var lines := PackedStringArray()
	for id in models:
		var made := FantasyModels.scene("../sea/town/" + id)
		if made == null:
			lines.append("%s MISSING" % id)
			continue
		add_child(made)
		var box := FantasyModels.bounds(made)
		var above := AABB(Vector3(box.position.x, maxf(box.position.y, -0.5), box.position.z), Vector3(box.size.x, box.end.y - maxf(box.position.y, -0.5), box.size.z))
		var middle := above.get_center()
		var radius := above.size.length() * 0.5
		var away := radius / tan(deg_to_rad(camera.fov * 0.5)) * 1.05
		var views := {"a": Vector3(0.55, 0.42, -1.0), "b": Vector3(-0.6, 0.5, 1.0)}
		var door := made.find_child("Door", true, false) as Node3D
		var lit: Array = []
		if made.find_child("Lamp_1", true, false) != null and door != null:  # a walk-in building: a view from inside the door too
			views["i"] = Vector3.ZERO
			for k in range(1, 6):
				var spot := made.find_child("Lamp_%d" % k, true, false) as Node3D
				if spot != null:
					var lamp := OmniLight3D.new()
					lamp.position = spot.position
					lamp.light_color = Color(1.0, 0.82, 0.58)
					lamp.light_energy = 1.6
					lamp.omni_range = 9.0
					add_child(lamp)
					lit.append(lamp)
		for view: String in views:
			if only_thumbs and view != "a":
				continue
			camera.fov = 40.0
			if view == "i":
				camera.fov = 72.0
				camera.position = door.position + Vector3(0.0, 2.3, 3.4)
				camera.look_at(camera.position + Vector3(0.0, -0.15, 1.0))
			else:
				camera.position = middle + (views[view] as Vector3).normalized() * away
				camera.look_at(middle)
			for _i in 4:
				await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			if not only_thumbs:
				image.save_jpg("res://tools/shots/town_%s_%s.jpg" % [id, view], 0.9)
			if thumbs and view == "a":
				var w := image.get_width()
				var h := image.get_height()
				var cut := Rect2i(int(w * 0.08), int(h * 0.12), int(w * 0.84), int(h * 0.76))
				var thumb := image.get_region(cut)
				thumb.resize(360, 220, Image.INTERPOLATE_LANCZOS)
				thumb.save_png("res://assets/ui/town/%s.png" % id)
			lines.append("%s %s: draws=%d tris=%d" % [id, view, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
		made.queue_free()
		for lamp: Node in lit:
			lamp.queue_free()
		await get_tree().process_frame
	lines.append("TOWN_SHOT_DONE")
	var f := FileAccess.open("res://tools/town_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
