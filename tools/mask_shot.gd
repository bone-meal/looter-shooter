# Purpose: developer check of the game masks (polish1 D5c): a woman and a man wearing the mask (hair given, to show it
# is left off), pictures from the 3/4 front, side and back close on the heads, the mask alone at each graphics detail
# (hi / lo mesh), and triangles / draw calls, to res://tools/shots/mask_<id>_<view>.jpg + tools/mask_shot.log.
# `-- --id=<mask>` (else tools/mask_shot_id.txt, else plague_doctor), `--tier=<0-4>`, `--wait=<frames>` (particles settle).
# The woman stands still, the man is shown as if running (the mask shader's per-wearer `moving`).
# Dependencies: game/rigged_body.gd, game/mask_model.gd, game/surface_library.gd.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")
const RiggedBody = preload("res://game/rigged_body.gd")
const MaskModel = preload("res://game/mask_model.gd")


func _ready() -> void:
	var id := "plague_doctor"
	if FileAccess.file_exists("res://tools/mask_shot_id.txt"):  # (run from the editor / MCP without arguments)
		id = FileAccess.get_file_as_string("res://tools/mask_shot_id.txt").strip_edges()
	var wait := 40
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="):
			id = arg.trim_prefix("--id=")
		elif arg.begins_with("--tier="):
			MaskModel.tier = int(arg.trim_prefix("--tier="))
		elif arg.begins_with("--wait="):
			wait = int(arg.trim_prefix("--wait="))
	var env := Environment.new()
	var sky := Sky.new()  # a sky, as in the game: metals need something to reflect
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 150, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-20, -20, 0)
	back.light_energy = 0.7
	back.light_color = Color(0.7, 0.8, 1.0)
	add_child(back)
	var camera := Camera3D.new()
	camera.fov = 30.0
	add_child(camera)
	camera.current = true
	SurfaceLibrary.configure(true, "1k", 2)
	var lines := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var bodies: Array = []
	for row in 2:
		var look := {"gender": "female" if row == 0 else "male", "rig_outfit": "peasant", "rig_hair": "long" if row == 0 else "parted", "skin": 3 + row * 3, "mask": id}
		var body := RiggedBody.build(look)
		if body == null:
			lines.append("body %d NOT BUILT" % row)
			continue
		add_child(body)
		body.position = Vector3(float(row) * 0.9, 0.0, 0.0)
		body.rotation.y = PI
		bodies.append(body)
		var anchor: Node3D = body.call("head_anchor")
		lines.append("%s: mask on the head %s, pieces %d" % [look["gender"], str(anchor.get_node_or_null("Mask") != null), (body.call("skeleton") as Node).get_child_count()])
	var views := {"34": Vector3(1.1, 1.75, 1.5), "side": Vector3(1.7, 1.66, 0.0), "back": Vector3(-0.9, 1.8, -1.6), "front": Vector3(0.0, 1.68, 1.9)}  # the bodies face +Z here
	for view: String in views:
		for body: Node3D in bodies:
			var at: Vector3 = (body.call("head_anchor") as Node3D).global_position + Vector3(0, 0.08, 0)
			camera.position = at + (views[view] - Vector3(0, 1.62, 0)).normalized() * 0.95
			camera.look_at(at)
			for b: Node3D in bodies:
				b.visible = b == body
			for _i in wait:
				for b: Node3D in bodies:
					b.call("animate", 0.0, false)
					var mm := (b.call("head_anchor") as Node3D).get_node_or_null("Mask/MaskMesh") as MeshInstance3D
					if mm != null and bodies.find(b) == 1:  # the man's pictures show the mask as if he were running
						mm.set_instance_shader_parameter("moving", 1.0)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var file := "res://tools/shots/mask_%s_%s_%s.jpg" % [id, view, "f" if bodies.find(body) == 0 else "m"]
			get_viewport().get_texture().get_image().save_jpg(file, 0.92)
			lines.append("%s %s: draws=%d tris=%d frame %.1f ms" % [view, file, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	lines.append("MASK_SHOT_DONE")
	var f := FileAccess.open("res://tools/mask_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
