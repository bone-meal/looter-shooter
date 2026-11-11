# Purpose: personality for an NPC built with BodyBuilder: a name plate ("Name - Title"), a speech bubble with greeting lines (uses the player's name) and idle chatter while the camera is near, and the head turning to follow the camera. Lines and ranges live in data/npcs.json by npc id.
# Dependencies: data/npcs.json. Runs after its parent's animation (child node), so the head turn overrides the idle head pose. Set NpcChatter-static `player_name` from game_session.
extends Node3D

static var player_name := ""
static var _data: Dictionary = {}

var _cfg: Dictionary = {}
var _head: Node3D
var _bubble: Label3D
var _rng := RandomNumberGenerator.new()
var _dist := 999.0
var _look_w := 0.0
var _show_left := 0.0
var _idle_in := 8.0
var _greet_cd := 0.0
var _inside := false
var _check := 0.0


# Builds the plate and bubble under `model`. Does nothing when the id is not in data/npcs.json.
func setup(model: Node3D, npc_id: String) -> void:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/npcs.json"))
	var npcs: Dictionary = _data["npcs"]
	if not npcs.has(npc_id):
		return
	_cfg = npcs[npc_id]
	_rng.randomize()
	_head = model.get_node_or_null("Torso/Head")
	var plate := Label3D.new()
	plate.text = "%s - %s" % [_cfg["name"], _cfg["title"]]
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.pixel_size = 0.004
	plate.outline_size = 8
	plate.position = Vector3(0.0, 2.15, 0.0)
	add_child(plate)
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.pixel_size = 0.0045
	_bubble.outline_size = 10
	_bubble.modulate = Color(1.0, 0.95, 0.7)
	_bubble.position = Vector3(0.0, 2.45, 0.0)
	_bubble.visible = false
	add_child(_bubble)
	_idle_in = _rng.randf_range(2.0, float(_data["idle_gap"][1]))
	model.add_child(self)


func _say(lines: Array) -> void:
	var line := String(lines[_rng.randi() % lines.size()])
	var who := player_name if player_name != "" else "friend"
	_bubble.text = line.replace("{player}", who)
	_bubble.modulate.a = 1.0
	_bubble.visible = true
	_show_left = float(_data["bubble_seconds"])


func _process(delta: float) -> void:
	if _cfg.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.2
		_dist = global_position.distance_to(cam.global_position)
	var turn_target := 1.0 if _dist < float(_data["look_range"]) else 0.0
	_look_w = move_toward(_look_w, turn_target, delta * 2.0)
	if _look_w > 0.01 and _head != null:
		var local: Vector3 = (get_parent() as Node3D).to_local(cam.global_position)
		var yaw := clampf(atan2(-local.x, -local.z), -1.0, 1.0)
		_head.rotation.y = lerpf(_head.rotation.y, yaw, _look_w)
	_greet_cd = maxf(_greet_cd - delta, 0.0)
	var near := _dist < float(_data["greet_range"])
	if near and not _inside and _greet_cd <= 0.0:
		_say(_cfg["greet"])
		_greet_cd = float(_data["greet_cooldown"])
	_inside = near
	if _show_left > 0.0:
		_show_left -= delta
		_bubble.modulate.a = clampf(_show_left / 0.5, 0.0, 1.0)
		if _show_left <= 0.0 or _dist > float(_data["chatter_range"]):
			_bubble.visible = false
			_show_left = 0.0
	elif _dist < float(_data["chatter_range"]):
		_idle_in -= delta
		if _idle_in <= 0.0:
			_say(_cfg["idle"])
			var gap: Array = _data["idle_gap"]
			_idle_in = _rng.randf_range(float(gap[0]), float(gap[1]))
