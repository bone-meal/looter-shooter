# Purpose: KITE FLYER's kite (diary/DESIGN_UNIQUES.md, region 5 chase gun): flies high behind whoever holds the gun on
# a string from the reel ("Line" marker of the kite_reel gimmick), swaying with the wind. dive() sends it down onto a
# spot and back (the lightning it caught strikes there: the caller deals any damage). On a TEAMMATE's machine the kite
# is a string to grab: a player in the air who touches the string is towed behind the holder (player tow_point) until
# he jumps again or the holder is gone. A child of the gimmick with top_level, so it goes when the gun goes.
# Dependencies: game/island_weather.gd (wind, wind_yaw), the kite model; game/player.gd tow_point (the local player).
extends Node3D

const MODEL := "res://assets/models/weapons/uniques/kite.gltf"
const GROUP := "kites"
const BEHIND := 4.0
const HIGH := 7.0
const GRAB_REACH := 1.1

var owned := true  # the holder's own kite (false = a teammate's copy here: it can be grabbed)
var local_player: Node3D  # this machine's player (the one who may grab a teammate's string)

var _hand: Node3D
var _body: Node3D
var _string: MeshInstance3D
var _weather: Node
var _dive_from := Vector3.ZERO
var _dive_to := Vector3.ZERO
var _dive_t := -1.0  # 0..1 going down, 1..2 coming back, < 0 = flying
var _dive_done: Callable
var _towing := false
var _towed_since := 0.0
var _grab_after := 0.0


func _ready() -> void:
	top_level = true
	add_to_group(GROUP)
	_hand = (get_parent() as Node3D).find_child("Line", true, false) as Node3D if get_parent() is Node3D else null
	if _hand == null:
		_hand = get_parent() as Node3D
	if ResourceLoader.exists(MODEL):
		_body = (load(MODEL) as PackedScene).instantiate() as Node3D
		_body.rotation.y = PI * 0.5  # the sail (built facing +x) faces the holder
		add_child(_body)
	_string = MeshInstance3D.new()
	var cord := CylinderMesh.new()
	cord.top_radius = 0.008
	cord.bottom_radius = 0.008
	cord.height = 1.0
	cord.radial_segments = 4
	cord.rings = 1
	_string.mesh = cord
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.95, 0.92)
	_string.material_override = mat
	_string.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_string.top_level = true
	add_child(_string)
	global_position = _home()
	if local_player == null:
		var link: Node = get_tree().get_first_node_in_group("net_chase")
		if link != null and link.get("net") != null:
			local_player = link.get("net").call("local_player")


# Where it flies: behind and above the hand, pushed a little downwind.
func _home() -> Vector3:
	if _hand == null or not is_instance_valid(_hand):
		return global_position
	var back := _hand.global_transform.basis.z  # the gun points along -z
	back = Vector3(back.x, 0.0, back.z).normalized() if Vector2(back.x, back.z).length() > 0.05 else Vector3.BACK
	var wind := 0.25
	var yaw := 0.0
	if _weather == null or not is_instance_valid(_weather):
		_weather = get_tree().get_first_node_in_group("island_weather")
	if _weather != null:
		wind = float(_weather.call("wind"))
		yaw = float(_weather.call("wind_yaw"))
	var t := Time.get_ticks_msec() / 1000.0
	var drift := Vector3(-sin(yaw), 0.0, -cos(yaw)) * wind * 2.0
	var sway := Vector3(sin(t * 1.3), 0.4 * sin(t * 2.1), cos(t * 0.9)) * (0.4 + wind * 0.8)
	return _hand.global_position + back * BEHIND + Vector3.UP * (HIGH - (1.0 - wind) * 1.5) + drift + sway


func dive(spot: Vector3, done: Callable = Callable()) -> void:
	_dive_from = global_position
	_dive_to = spot
	_dive_t = 0.0
	_dive_done = done


func diving() -> bool:
	return _dive_t >= 0.0


func _process(delta: float) -> void:
	var shown := _hand != null and is_instance_valid(_hand) and _hand.is_visible_in_tree()
	visible = shown
	_string.visible = shown
	if not shown:
		_let_go()
		return
	if _dive_t >= 0.0:
		_dive_t += delta / (0.45 if _dive_t < 1.0 else 1.0)
		if _dive_t < 1.0:
			global_position = _dive_from.lerp(_dive_to, _dive_t * _dive_t)
		else:
			if _dive_done.is_valid():
				_dive_done.call()
				_dive_done = Callable()
			global_position = _dive_to.lerp(_home(), minf(_dive_t - 1.0, 1.0))
			if _dive_t >= 2.0:
				_dive_t = -1.0
	else:
		global_position = global_position.lerp(_home(), minf(1.0, delta * 2.0))
	if global_position.distance_to(_hand.global_position) > 0.2:
		look_at(_hand.global_position, Vector3.UP)
	var a := _hand.global_position
	var b := global_position + Vector3(0, -0.2, 0)
	_string.global_position = (a + b) * 0.5
	var along := b - a
	if along.length() > 0.05:
		_string.global_transform.basis = Basis(Quaternion(Vector3.UP, along.normalized())).scaled(Vector3(1.0, along.length(), 1.0))
	if not owned:
		_tow(delta)


# How far a point is from the string.
func line_distance(point: Vector3) -> float:
	var a := _hand.global_position
	var b := global_position
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return point.distance_to(a + ab * t)


func towing() -> bool:
	return _towing


# A teammate's string: grab it from the air, glide behind its holder, jump again to let go.
func _tow(_delta: float) -> void:
	var me := local_player
	if me == null or not is_instance_valid(me) or not me.has_method("is_on_floor"):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not _towing:
		if now >= _grab_after and not bool(me.call("is_on_floor")) and line_distance(me.global_position + Vector3(0, 1.0, 0)) < GRAB_REACH:
			_towing = true
			_towed_since = now
		return
	var back := _hand.global_transform.basis.z
	back = Vector3(back.x, 0.0, back.z).normalized() if Vector2(back.x, back.z).length() > 0.05 else Vector3.BACK
	me.set("tow_point", _hand.global_position + back * 3.0 + Vector3.UP * 1.5)
	if (now - _towed_since > 0.4 and Input.is_action_just_pressed("jump")) or me.global_position.distance_to(_hand.global_position) > 25.0:
		_let_go()


func _let_go() -> void:
	if not _towing:
		return
	_towing = false
	_grab_after = Time.get_ticks_msec() / 1000.0 + 1.0
	if local_player != null and is_instance_valid(local_player):
		local_player.set("tow_point", Vector3.INF)


func _exit_tree() -> void:
	_let_go()


# Whose kite this is (0 = ours / unknown): the remote player body it hangs from.
func peer() -> int:
	var n: Node = get_parent()
	while n != null:
		if "peer_id" in n:
			return int(n.get("peer_id"))
		n = n.get_parent()
	return 0
