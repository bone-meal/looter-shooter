# Purpose: developer check. Lays every knife type of data/knives.json out in a grid, each with its name and its
# chance at character creation, and saves two pictures: res://tools/shots/knives_a.jpg (from the side) and
# knives_b.jpg (from above the spine at an angle). Triangles per type go to tools/knife_shot.log.
# Dependencies: game/knife_models.gd.
extends Node3D

const KnifeModels = preload("res://game/knife_models.gd")

const COLUMNS := 4
const CELL := Vector2(0.47, 0.21)


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.4, 0.46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(camera)
	camera.current = true
	var lines := PackedStringArray()
	var ids: Array = KnifeModels.db().ids()
	var rows := ceili(ids.size() / float(COLUMNS))
	for i in ids.size():
		var id := String(ids[i])
		var knife := KnifeModels.build(id)
		knife.rotation.y = -PI * 0.5  # tip to the right of the picture
		knife.position = Vector3((i % COLUMNS) * CELL.x, -floorf(float(i) / COLUMNS) * CELL.y, 0.0)
		add_child(knife)
		var label := Label3D.new()
		label.text = "%s  %.1f %%" % [KnifeModels.db().name_of(id), KnifeModels.db().chance_pct(id)]
		label.pixel_size = 0.0006
		label.font_size = 40
		label.position = knife.position + Vector3(0.0, -0.075, 0.0)
		add_child(label)
		lines.append("%s: %d triangles" % [id, KnifeModels.triangles(id)])
	var middle := Vector3((COLUMNS - 1) * CELL.x * 0.5 + 0.07, -(rows - 1) * CELL.y * 0.5 - 0.02, 0.0)
	camera.size = maxf(rows * CELL.y + 0.08, ((COLUMNS - 1) * CELL.x + 0.5) * 9.0 / 16.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var views := {"a": Vector3(0, 0, 1.5), "b": Vector3(0.0, 0.9, 1.2)}
	for view: String in views:
		camera.position = middle + views[view]
		camera.look_at(middle)
		for _i in 4:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("res://tools/shots/knives_%s.jpg" % view, 0.92)
	lines.append("KNIFE_SHOT_DONE")
	var f := FileAccess.open("res://tools/knife_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	get_tree().quit()
