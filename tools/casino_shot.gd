# Purpose: developer render of the casino annex: builds it alone, launches pachinko balls, saves tools/shots/casino_*.png and quits. Run scene tools/casino_shot.tscn.
# Dependencies: game/casino_room.gd, game/pachinko_wall.gd.
extends Node3D

const CasinoRoom = preload("res://game/casino_room.gd")

var _wall: Node3D
var _slots: Array = []
var _bj_node: Node3D
var _rt_node: Node3D
var _cam: Camera3D
var _t := 0.0
var _shot := 0


func _ready() -> void:
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
	var built := CasinoRoom.build(self, Vector3.ZERO)
	_wall = built["pachinko"]
	_slots = built["slots"]
	_bj_node = built["blackjack"]
	_rt_node = built["roulette"]
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	_cam.position = Vector3(17.5, 1.7, 5.0)
	_cam.look_at(Vector3(17.5, 4.5, -6.5), Vector3.UP)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5 * float(_wall.sim.count + 1) and _wall.sim.count < 25 and _t < 6.0:
		_wall.launch()
	if _shot == 0 and _t > 7.0:
		_save("casino_wall")
		_cam.position = Vector3(17.5, 1.7, 0.5)
		_cam.look_at(Vector3(17.5, 3.0, -6.5), Vector3.UP)
		_shot = 1
		_t = 7.0
	elif _shot == 1 and _t > 7.3:
		_save("casino_close")
		_shot = 2
		_cam.position = Vector3(19.0, 1.7, 0.6)
		_cam.look_at(Vector3(21.6, 1.6, 0.0), Vector3.UP)
		var a: Array[int] = [0, 5, 9]
		var b: Array[int] = [19, 9, 3]
		_slots[1].spin_to(a)
		_slots[2].spin_to(b)
		_t = 7.3
	elif _shot == 2 and _t > 8.9:
		_save("slot_spinning")
		_shot = 3
	elif _shot == 3 and _t > 12.0:
		_save("slot_stopped")
		_shot = 4
		_t = 12.0
		_cam.position = Vector3(15.2, 2.2, 5.6)
		_cam.look_at(Vector3(15.2, 0.9, 2.2), Vector3.UP)
		var tb = _bj_node
		tb.place("d:0", 12, true)
		tb.place("d:1", 7, false)
		tb.place("p0:0", 0, true)
		tb.place("p0:1", 9, true)
		var stakes: Array[int] = [135]
		tb.show_bets(stakes)
	elif _shot == 4 and _t > 13.2:
		_save("blackjack")
		_shot = 5
		_cam.position = Vector3(15.0, 2.4, 1.6)
		_cam.look_at(Vector3(15.0, 0.9, -1.4), Vector3.UP)
		_rt_node.spin_to(17)
		_rt_node.show_bets({"straight:17": 5, "red": 25, "dozen:2": 10, "column:3": 50, "straight:0": 1})
	elif _shot == 5 and _t > 15.0:
		_save("roulette_mid")
		_shot = 6
	elif _shot == 6 and _t > 20.0:
		_save("roulette_end")
		var f := FileAccess.open("res://tools/shots/casino_info.log", FileAccess.WRITE)
		f.store_string("draws %d balls %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), _wall.sim.count])
		f.close()
		get_tree().quit()


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/shots/%s.png" % name))
