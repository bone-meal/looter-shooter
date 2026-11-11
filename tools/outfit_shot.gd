# Purpose: developer check. Stands one rigged character per outfit of data/characters.json in two rows (women in
# front, men behind), built the way the game builds them, and saves pictures from the front and the back to
# res://tools/shots/outfits_<n>_front.jpg / _back.jpg (six outfits a picture) plus triangles and draw calls to
# tools/outfit_shot.log. `-- --only=farmer,guard` shows just those.
# Dependencies: game/rigged_body.gd, game/surface_library.gd, data/characters.json.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")
const RiggedBody = preload("res://game/rigged_body.gd")
const PER_SHOT := 6

var _bodies: Array = []


func _ready() -> void:
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.64)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 200, 0)
	sun.light_energy = 1.7
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.3, 0.33, 0.2)
	floor_mesh.material_override = ground
	add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.current = true
	SurfaceLibrary.configure(true, "1k", 2)
	var ids: Array = (RiggedBody.data()["outfits"] as Dictionary).keys()
	if not only.is_empty():
		ids = Array(only)
	var lines := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var shots := ceili(float(ids.size()) / float(PER_SHOT))
	for shot in shots:
		for body: Node in _bodies:
			body.queue_free()
		_bodies.clear()
		await get_tree().process_frame
		var count := mini(PER_SHOT, ids.size() - shot * PER_SHOT)
		for i in count:
			var id := String(ids[shot * PER_SHOT + i])
			for row in 2:
				var look := {"gender": "female" if row == 0 else "male", "rig_outfit": id, "rig_hair": "long" if row == 0 else "parted", "skin": (i * 3 + row * 4) % 10, "hair_color": "#4a3324"}
				var body := RiggedBody.build(look)
				if body == null:
					lines.append("%s %s: NOT BUILT" % [id, look["gender"]])
					continue
				add_child(body)
				body.position = Vector3(float(i) * 1.1 + 0.55 * float(row), 0.0, -1.3 * float(row))
				body.rotation.y = PI  # towards the front camera
				_bodies.append(body)
		var middle := float(count - 1) * 0.55
		for view: String in ["front", "back"]:
			var side := 1.0 if view == "front" else -1.0
			camera.position = Vector3(middle + 0.3, 2.0, (2.8 + 0.9 * float(count)) * side - 0.65)
			camera.look_at(Vector3(middle + 0.3, 0.9, -0.65))
			for body: Node3D in _bodies:
				body.rotation.y = PI  # they keep facing the front camera: the back view shows their backs
				body.call("animate", 0.0, false)
			for _i in 5:
				for body: Node3D in _bodies:
					body.call("animate", 0.0, false)
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("res://tools/shots/outfits_%d_%s.jpg" % [shot, view], 0.9)
			lines.append("shot %d %s (%s): draws=%d tris=%d" % [shot, view, ",".join(PackedStringArray(ids.slice(shot * PER_SHOT, shot * PER_SHOT + count))), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	lines.append("OUTFIT_SHOT_DONE")
	var f := FileAccess.open("res://tools/outfit_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
