# Purpose: developer render of the casino gun vendor kiosks as a player sees them (from the door and up close). Saves tools/shots/vendor_*.png and quits. Run scene tools/vendor_shot.tscn.
# Dependencies: game/casino_room.gd, game/gun_vendor.gd.
extends Node3D

const CasinoRoom = preload("res://game/casino_room.gd")

var _cam: Camera3D
var _t := 0.0
var _shot := 0


func _ready() -> void:
	get_window().size = Vector2i(1152, 648)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	CasinoRoom.build(self, Vector3.ZERO)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	_cam.position = Vector3(17.5, 1.7, 5.4)
	_cam.look_at(Vector3(15.0, 1.5, 0.0), Vector3.UP)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))


func _process(delta: float) -> void:
	_t += delta
	if _shot == 0 and _t > 1.0:
		_save("vendor_entry")
		_cam.position = Vector3(15.6, 1.7, 2.7)
		_cam.look_at(Vector3(12.75, 1.3, 2.7), Vector3.UP)
		_shot = 1
		_t = 1.0
	elif _shot == 1 and _t > 1.3:
		_save("vendor_close")
		get_tree().quit()


func _save(shot_name: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/shots/%s.png" % shot_name))
