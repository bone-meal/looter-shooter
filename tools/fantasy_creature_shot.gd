# Purpose: developer check. Stands all the fantasy world's creatures in rows as real Enemy nodes (so sizes, joints and
# materials are the ones the game uses) and saves pictures to res://tools/shots/fantasy_creatures_<n>.png, plus draw
# calls and triangles per row to tools/fantasy_creature_shot.log.
# Dependencies: game/enemy.gd, data/fantasy/enemies.json.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")
const Enemy = preload("res://game/enemy.gd")
const DataStore = preload("res://core/data_store.gd")
const PER_ROW := 3


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
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.9
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.25, 0.28, 0.16)
	floor_mesh.material_override = ground
	add_child(floor_mesh)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	SurfaceLibrary.configure(true, "1k", 2)  # the textured look, as in the game's realistic preset
	var enemies: Dictionary = DataStore.load_json("res://data/fantasy/enemies.json")["enemies"]
	var ids := enemies.keys()
	var lines := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var rows := ceili(float(ids.size()) / float(PER_ROW))
	for row in rows:
		var made: Array = []
		var x := 0.0
		var tallest := 1.0
		for i in PER_ROW:
			var index := row * PER_ROW + i
			if index >= ids.size():
				break
			var stats: Dictionary = enemies[ids[index]]
			var enemy := Enemy.new()
			enemy.configure(String(ids[index]), stats, null, null, null)
			enemy.set_physics_process(false)
			x += float(stats["size"][0]) * 0.5 + 1.0
			enemy.position = Vector3(x, 0, 0)
			enemy.rotation.y = PI + 0.5  # three-quarter view towards the camera
			x += float(stats["size"][0]) * 0.5 + 1.0
			tallest = maxf(tallest, float(stats["size"][1]))
			add_child(enemy)
			made.append(enemy)
		camera.position = Vector3(x * 0.5, tallest * 0.6, maxf(x * 0.5, tallest * 1.5))
		camera.look_at(Vector3(x * 0.5, tallest * 0.45, 0))
		for _i in 4:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/shots/fantasy_creatures_%d.png" % row)
		lines.append("row %d: draws=%d tris=%d" % [row, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
		for enemy: Node in made:
			enemy.queue_free()
		await get_tree().process_frame
	lines.append("DONE")
	var f := FileAccess.open("res://tools/fantasy_creature_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
