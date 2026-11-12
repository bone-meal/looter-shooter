# Purpose: developer-time tool for the wall buys' chalk outlines. Pictures every gun body side-on as a plain white
# shape on black (tools/shots/chalk_<body>.png, 512 x 256, muzzle to the right, each fitted to its picture);
# tools/make_chalk_guns.py turns those into the outline sheet assets/ui/chalk_guns.png. Needs a display.
# Dependencies: game/weapon_models.gd, core/data_store.gd (data/weapons.json: which bodies exist).
extends Node3D

const WeaponModels = preload("res://game/weapon_models.gd")
const DataStore = preload("res://core/data_store.gd")

const SIZE := Vector2i(512, 256)
const FILL := 0.6  # how much of the picture the gun takes (tools/make_chalk_guns.py crops and fits it again)


func _ready() -> void:
	get_window().size = SIZE
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(camera)
	camera.current = true
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color.WHITE
	var done := PackedStringArray()
	for body: String in DataStore.load_json("res://data/weapons.json")["weapons"]:
		var gun := WeaponModels.build(body)
		gun.position = Vector3.ZERO
		gun.rotation.y = -PI * 0.5  # the muzzle (-z) to the right of the picture
		add_child(gun)
		var box := AABB()
		var first := true
		for piece: Node in gun.find_children("*", "MeshInstance3D", true, false):
			(piece as MeshInstance3D).material_override = white
			var part: AABB = (piece as MeshInstance3D).global_transform * (piece as MeshInstance3D).get_aabb()
			box = part if first else box.merge(part)
			first = false
		camera.size = maxf(box.size.y, box.size.x * float(SIZE.y) / float(SIZE.x)) / FILL  # the height the camera sees
		camera.position = box.get_center() + Vector3(0, 0, 5)
		for _i in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/shots/chalk_%s.png" % body)
		done.append("%s %.2f x %.2f m" % [body, box.size.x, box.size.y])
		gun.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open("res://tools/chalk_shot.log", FileAccess.WRITE)
	file.store_string("\n".join(done) + "\nCHALK_SHOT_DONE\n")
	file.close()
	get_tree().quit()
