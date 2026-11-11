# Purpose: developer check for NPC personality and idle animation: a dealer with npc id, camera walks up; logs plate/bubble/head turn, blink and fidget samples to tools/npc_check.log and saves tools/shots/npc_close.png, then quits. Run scene tools/npc_check.tscn.
# Dependencies: game/staff_crew.gd, game/npc_chatter.gd, game/body_motion.gd.
extends Node3D

const StaffCrew = preload("res://game/staff_crew.gd")
const NpcChatter = preload("res://game/npc_chatter.gd")

var _crew: Node3D
var _model: Node3D
var _cam: Camera3D
var _t := 0.0
var _min_eye := 1.0
var _max_lift := 0.0
var _max_head := 0.0
var _bubble_text := ""
var _plate_text := ""
var _shot := false
var _log := ""


func _ready() -> void:
	get_window().size = Vector2i(900, 600)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	add_child(sun)
	NpcChatter.player_name = "Tester"
	_crew = StaffCrew.new()
	add_child(_crew)
	_model = _crew.add("idle", StaffCrew.look("casino_pink", "twin_tails", "#f48fb1", "giggle", 1), Vector3.ZERO, 0.0, null, "dealer_blackjack")
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(1.8, 1.6, -9.0)
	_cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	if _t > 1.0:
		_cam.position = _cam.position.move_toward(Vector3(1.2, 1.7, -2.6), delta * 3.0)
		_cam.look_at(Vector3(0, 1.55, 0), Vector3.UP)
	var eyes := _model.get_node_or_null("Torso/Head/Face/Eyes") as Node3D
	if eyes != null:
		_min_eye = minf(_min_eye, eyes.scale.y)
	_max_lift = maxf(_max_lift, absf((_model.get_node("Torso/ArmR") as Node3D).rotation.x))
	_max_head = maxf(_max_head, absf((_model.get_node("Torso/Head") as Node3D).rotation.y))
	for child in _model.get_children():
		if child is NpcChatter:
			for lab in child.get_children():
				if lab is Label3D:
					if (lab as Label3D).visible and (lab as Label3D).text.contains("Tester"):
						_bubble_text = (lab as Label3D).text
					elif (lab as Label3D).text.contains(" - "):
						_plate_text = (lab as Label3D).text
	if _t > 6.0 and not _shot:
		_shot = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
		get_viewport().get_texture().get_image().save_png("res://tools/shots/npc_close.png")
	if _t > 16.0:
		_log += "plate: %s\nbubble: %s\nmin eye scale (blink): %.2f\nmax right arm lift: %.2f\nmax head yaw: %.2f\n" % [_plate_text, _bubble_text, _min_eye, _max_lift, _max_head]
		var ok := _plate_text != "" and _bubble_text != "" and _min_eye < 0.4 and _max_lift > 0.3 and _max_head > 0.1
		_log += "RESULT: %s\n" % ("ok" if ok else "FAIL")
		var f := FileAccess.open("res://tools/npc_check.log", FileAccess.WRITE)
		f.store_string(_log)
		f.close()
		get_tree().quit()
