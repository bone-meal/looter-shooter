# Purpose: developer check of the boss trophies (polish1 E4): a woman (peasant clothes) and a man (ranger clothes) each
# wearing a set of trophy pieces (data/boss_trophies.json), pictured from the 3/4 front and from behind, upper body,
# to res://tools/shots/trophy_<set>_<view>_<f|m>.jpg + tools/trophy_shot.log (draw calls, triangles).
# `-- --ids=a+b,c` (sets of pieces worn together, + between pieces; else tools/trophy_shot_ids.txt, else harvest_king).
# Dependencies: game/rigged_body.gd, game/surface_library.gd.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")
const RiggedBody = preload("res://game/rigged_body.gd")


func _ready() -> void:
	var sets := "harvest_king"
	if FileAccess.file_exists("res://tools/trophy_shot_ids.txt"):
		sets = FileAccess.get_file_as_string("res://tools/trophy_shot_ids.txt").strip_edges()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="):
			sets = arg.trim_prefix("--ids=")
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 150, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-20, -20, 0)
	back.light_energy = 0.7
	add_child(back)
	var camera := Camera3D.new()
	camera.fov = 32.0
	add_child(camera)
	camera.current = true
	SurfaceLibrary.configure(true, "1k", 2)
	var lines := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	for set_words: String in sets.split(",", false):
		var worn := Array(set_words.split("+", false))
		var bodies: Array = []
		for row in 2:
			var look := {"gender": "female" if row == 0 else "male", "rig_outfit": "peasant" if row == 0 else "ranger", "rig_hair": "long" if row == 0 else "parted", "skin": 3 + row * 3, "boss_trophies": worn}
			var body := RiggedBody.build(look)
			if body == null:
				lines.append("body %d NOT BUILT" % row)
				continue
			add_child(body)
			body.rotation.y = PI
			bodies.append(body)
			lines.append("%s %s: pieces on the skeleton %d, on the head %d" % [set_words, look["gender"], (body.call("skeleton") as Node).get_child_count(), (body.call("head_anchor") as Node).get_child_count()])
		var views := {"34": Vector3(1.3, 1.55, 1.9), "back": Vector3(-0.9, 1.65, -2.0)}  # the bodies face +Z here
		for view: String in views:
			for body: Node3D in bodies:
				var at: Vector3 = (body.call("head_anchor") as Node3D).global_position + Vector3(0, -0.22, 0)
				camera.position = at + (views[view] - Vector3(0, 1.4, 0)).normalized() * 1.7
				camera.look_at(at)
				for b: Node3D in bodies:
					b.visible = b == body
				for _i in 20:
					body.call("animate", 0.0, false)
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var file := "res://tools/shots/trophy_%s_%s_%s.jpg" % [set_words.replace("+", "_"), view, "f" if bodies.find(body) == 0 else "m"]
				get_viewport().get_texture().get_image().save_jpg(file, 0.9)
				lines.append("%s %s: draws=%d tris=%d" % [view, file, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
		for body: Node3D in bodies:
			body.queue_free()
		await get_tree().process_frame
	lines.append("TROPHY_SHOT_DONE")
	var f := FileAccess.open("res://tools/trophy_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
