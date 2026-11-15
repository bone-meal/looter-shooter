# Purpose: developer check of the chase guns' modelled effects (game/fx_kit.gd users): sets them all off side by side
# on a plain floor and saves pictures (tools/shots/fx_<n>.jpg) a moment apart, plus FX_SHOT_DONE in tools/fx_shot.log.
# Dependencies: game/swamp_gas.gd, game/fire_geyser.gd, game/firebomb.gd, game/whirlpool.gd, game/lighthouse_beam.gd,
# game/lightning_bolt.gd, game/signatures/split_decision.gd, game/golden_egg.gd, game/treasure_x.gd, game/snowball.gd.
extends Node3D


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.6, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.5, 0.55, 0.35)
	ground.material_override = dirt
	add_child(ground)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)
	var camera := Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 7, 20), Vector3(0, 1.2, 0))
	camera.fov = 70.0
	camera.current = true
	var cfg: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_uniques.json")) as Dictionary)["uniques"]
	var gas: Node3D = (load("res://game/swamp_gas.gd") as GDScript).new()
	add_child(gas)
	gas.call("puff", Vector3(-11, 1.2, -5), cfg["swamp_gas"]["cfg"], 10.0)
	var geyser: Node3D = (load("res://game/fire_geyser.gd") as GDScript).new()
	geyser.set("owned", false)
	add_child(geyser)
	geyser.call("erupt", Vector3(-5.5, 0, 0))
	var bomb: Node3D = (load("res://game/firebomb.gd") as GDScript).new()
	bomb.set("owned", false)
	bomb.set("cfg", cfg["keepers_lantern"]["cfg"])
	add_child(bomb)
	bomb.call("throw", Vector3(-2, 2, 2), Vector3(0, -4, 0), [] as Array[RID])
	(load("res://game/signatures/flush.gd") as GDScript).call("open", self, null, Vector3(2, 0, 2), false, cfg["flush"]["cfg"])
	var anchor := Node3D.new()
	anchor.position = Vector3(6, 1.3, -2)
	add_child(anchor)
	var beam: Node3D = (load("res://game/lighthouse_beam.gd") as GDScript).new()
	beam.set("owned", false)
	anchor.add_child(beam)
	var x: Node3D = (load("res://game/treasure_x.gd") as GDScript).new()
	add_child(x)
	x.position = Vector3(9, 0, 3)
	var ball: Node3D = (load("res://game/snowball.gd") as GDScript).new()
	ball.set("owned", false)
	ball.set("dir", Vector3(1, 0, 0))
	ball.set("cfg", cfg["avalanche_control"]["cfg"])
	add_child(ball)
	ball.position = Vector3(-10, 0, 5)
	var egg_script := load("res://game/golden_egg.gd") as GDScript
	var egg: Node3D = egg_script.new()
	egg.set("owned", false)
	egg.set("hatch_seconds", 1.0)
	add_child(egg)
	egg.call("throw", Vector3(-1, 1, 7), Vector3(0, 0, 0), [] as Array[RID])
	await get_tree().create_timer(0.45).timeout
	(load("res://game/lightning_bolt.gd") as GDScript).call("strike", self, Vector3(0, 20, -3), Vector3(0, 0, -3))
	(load("res://game/signatures/split_decision.gd") as GDScript).call("shards", self, Vector3(3, 1.2, 8))
	for n in 4:
		await get_tree().create_timer(0.05 if n == 0 else 0.35).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("res://tools/shots/fx_%d.jpg" % n, 0.9)
	var log_file := FileAccess.open("res://tools/fx_shot.log", FileAccess.WRITE)
	log_file.store_string("FX_SHOT_DONE\n")
	log_file.close()
	get_tree().quit()
