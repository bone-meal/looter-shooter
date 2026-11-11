# Purpose: soft secondary motion on a rigged character: when the body speeds up or stops, a damped spring
# (core/jiggle_spring.gd, tuned by data/jiggle.json like the old bodies) moves the "bust_bounce" and "glutes_bounce"
# blend shapes of the clothing pieces up and down, more for larger slider values. Stops itself while not visible.
# Dependencies: core/jiggle_spring.gd, data/jiggle.json, the blend shapes made by game/body_shape.gd.
extends Node3D

const JiggleSpring = preload("res://core/jiggle_spring.gd")

static var _tuning := {}

var _pieces: Array = []  # MeshInstance3D with the shapes of game/body_shape.gd
var _amounts := Vector2.ZERO  # how strongly bust (x) and glutes (y) move, from the sliders
var _spring := JiggleSpring.new()
var _last_position := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _started := false  # the first frame only records where the body is


func setup(pieces: Array, bust: float, glutes: float) -> void:
	if _tuning.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/jiggle.json"))
		if parsed is Dictionary:
			_tuning = parsed
	_pieces = pieces
	var low := float(_tuning.get("amount_min", 0.8))
	var high := float(_tuning.get("amount_max", 1.8))
	_amounts = Vector2(lerpf(low, high, bust) if bust > 0.05 else 0.0, lerpf(low, high, glutes) if glutes > 0.05 else 0.0)
	_spring.setup(float(_tuning.get("frequency_hz", 6.0)), float(_tuning.get("damping", 0.1)), float(_tuning.get("max_offset", 0.07)))
	set_process(_amounts != Vector2.ZERO)


func _process(delta: float) -> void:
	if delta <= 0.0 or not is_visible_in_tree():
		return
	if not _started:
		_started = true
		_last_position = global_position
		return
	var velocity := (global_position - _last_position) / delta
	var accel := ((velocity - _last_velocity) / delta).limit_length(float(_tuning.get("max_accel", 120.0)))
	_last_position = global_position
	_last_velocity = velocity
	_spring.step(delta, -accel * float(_tuning.get("gain", 40.0)) * 0.01)
	var swing := clampf((_spring.offset.y + 0.5 * Vector2(_spring.offset.x, _spring.offset.z).length()) / maxf(_spring.limit, 0.001), -1.0, 1.0)
	for piece: MeshInstance3D in _pieces:
		piece.set_blend_shape_value(3, swing * _amounts.x)
		piece.set_blend_shape_value(4, -swing * _amounts.y)
