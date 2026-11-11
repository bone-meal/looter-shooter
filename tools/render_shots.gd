# Purpose: developer check: renders a small test scene (several characters, a gun, crates, ground, sea) once per lighting shader preset and graphics extreme, saving PNGs to tools/shots/; also checks that customize-menu sliders reach the saved look and a remote player's model. Writes tools/render_shots.log and quits. Run scene tools/render_shots.tscn.
# Dependencies: game/render_style.gd, game/body_builder.gd, game/weapon_models.gd, game/customize_menu.gd, game/remote_player.gd, game/appearance_data.gd.
extends Node3D

const RenderStyle = preload("res://game/render_style.gd")
const BodyBuilder = preload("res://game/body_builder.gd")
const WeaponModels = preload("res://game/weapon_models.gd")
const CustomizeMenu = preload("res://game/customize_menu.gd")
const RemotePlayer = preload("res://game/remote_player.gd")
const AppearanceData = preload("res://game/appearance_data.gd")
const P = preload("res://game/body_parts.gd")
const BodyMotion = preload("res://game/body_motion.gd")

var _log := PackedStringArray()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var env := Environment.new()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var style := RenderStyle.new()
	style.env = env
	style.sun = sun
	add_child(style)
	_build_scene()
	var cam := Camera3D.new()
	cam.position = Vector3(0.6, 1.5, 4.2)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	_check_sliders()
	var runs := [["high", "off"], ["high", "toon"], ["high", "vivid"], ["high", "cinematic"], ["ultimate", "ultimate"], ["potato", "off"]]
	for run: Array in runs:
		style.apply(String(run[0]), String(run[1]))
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "res://tools/shots/%s_%s.png" % [run[0], run[1]]
		img.save_png(path)
		_log.append("shot %s draws=%d" % [path, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	style.apply("high", "vivid")
	for target: Vector3 in [Vector3(-1.5, 1.55, 0.0), Vector3(-0.5, 1.6, 0.0), Vector3(0.5, 1.55, 0.0)]:
		cam.position = target + Vector3(0.25, 0.05, 1.1)
		cam.look_at(target + Vector3(0, -0.15, 0), Vector3.UP)
		for i in 4:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/shots/close_%d.png" % int(target.x * 10.0 + 20.0))
	var f := FileAccess.open("res://tools/render_shots.log", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _build_scene() -> void:
	var db := AppearanceData.db()
	var ground := P.box(self, Vector3(30, 0.2, 30), Vector3(0, -0.1, 0), P.mat(Color(0.86, 0.78, 0.55)))
	ground.name = "Ground"
	P.box(self, Vector3(200, 0.1, 200), Vector3(0, -0.4, -60), P.mat(Color(0.15, 0.45, 0.65)))
	P.box(self, Vector3(0.8, 0.8, 0.8), Vector3(-2.2, 0.4, -1.5), P.mat(Color(0.55, 0.35, 0.2)))
	P.box(self, Vector3(0.6, 0.6, 0.6), Vector3(-2.0, 1.1, -1.4), P.mat(Color(0.55, 0.35, 0.2)), Vector3(0, 25, 0))
	var looks := []
	var a := db.default_for("female")
	looks.append(a)
	var b := db.default_for("male")
	b["outfit"] = "knight"
	looks.append(b)
	var c := db.default_for("female")
	c["outfit"] = "lifeguard"
	c["hair"] = "twin_tails"
	c["hair_color"] = "#d94a8c"
	c["face"] = "happy"
	looks.append(c)
	var d := db.default_for("male")
	d["outfit"] = String(db.outfits[40]["id"])
	d["hair"] = "afro"
	d["skin"] = 9
	looks.append(d)
	for i in looks.size():
		var model := BodyBuilder.build(looks[i])
		model.position = Vector3(-1.5 + i * 1.0, 0, 0)
		model.rotation_degrees.y = 180.0 + (i - 1.5) * 12.0
		add_child(model)
		if i == 1:
			BodyMotion.animate(model, 0.0, 0.0, 0.0, true)  # weapon hold pose
		elif i == 3:
			BodyMotion.animate(model, 1.0, 1.3, 0.0, false)  # mid-stride
	var gun := WeaponModels.build("ak47")
	gun.position = Vector3(1.7, 1.2, 1.5)
	gun.rotation_degrees.y = 70.0
	add_child(gun)


# Moves the customize menu's height slider and checks the look, then a remote player's model scale.
func _check_sliders() -> void:
	var db := AppearanceData.db()
	var menu := CustomizeMenu.new()
	add_child(menu)
	menu.open(db.default_for("female"))
	var sliders: Dictionary = menu.get("_sliders")
	(sliders["height"] as HSlider).value = 1.12
	(sliders["weight"] as HSlider).value = 1.3
	var look: Dictionary = menu.look
	_log.append("menu syncing_stuck=%s height=%s weight=%s" % [str(menu.get("_syncing")), str(look["height"]), str(look["weight"])])
	var remote := RemotePlayer.new()
	add_child(remote)
	remote.set_appearance(look)
	var model: Node3D = remote.get("_model")
	_log.append("remote model scale=%s" % str(model.scale))
	remote.queue_free()
	menu.queue_free()
