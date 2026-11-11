# Purpose: soft-body jiggle for BodyBuilder characters: the chest and glute volumes (nodes carrying the meta "soft" = slider value 0..1) lag behind their anchor with a damped spring, overshoot and settle, with a little squash and stretch. Driven by the real movement of the anchor, so walking, stopping, jumping, landing, turning and dancing all move it. Attached automatically by game/body_builder.gd.
# Dependencies: core/jiggle_spring.gd, data/jiggle.json (tuning). Skips all work while the character is not visible.
extends Node3D

const JiggleSpring = preload("res://core/jiggle_spring.gd")

static var _cfg: Dictionary = {}

var _nodes: Array[MeshInstance3D] = []
var _springs: Array = []
var _rest := PackedVector3Array()
var _base_scale := PackedVector3Array()
var _prev_pos := PackedVector3Array()
var _prev_vel := PackedVector3Array()
var _gain := 4.0
var _max_accel := 60.0
var _squash := 0.2
var _primed := false


# Finds the soft nodes under `model`'s torso; adds this driver to the model only when there are any.
func setup(model: Node3D) -> void:
	if _cfg.is_empty():
		_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/jiggle.json"))
	_gain = float(_cfg["gain"])
	_max_accel = float(_cfg["max_accel"])
	_squash = float(_cfg["squash"])
	var torso: Node = model.get_node_or_null("Torso")
	if torso == null:
		return
	for child in torso.get_children():
		if child is MeshInstance3D and child.has_meta("soft"):
			var node: MeshInstance3D = child
			var amount := lerpf(float(_cfg["amount_min"]), float(_cfg["amount_max"]), clampf(float(node.get_meta("soft")), 0.0, 1.0))
			var spring := JiggleSpring.new()
			spring.setup(float(_cfg["frequency_hz"]), float(_cfg["damping"]), float(_cfg["max_offset"]) * amount)
			_nodes.append(node)
			_springs.append(spring)
			_rest.append(node.position)
			_base_scale.append(node.scale)
			_prev_pos.append(Vector3.ZERO)
			_prev_vel.append(Vector3.ZERO)
	if not _nodes.is_empty():
		name = "Jiggle"
		model.add_child(self)


func _process(delta: float) -> void:
	if delta <= 0.0 or delta > 0.1 or not is_visible_in_tree():
		_primed = false
		return
	for i in _nodes.size():
		var node := _nodes[i]
		var parent := node.get_parent() as Node3D
		var xf := parent.global_transform
		var anchor := xf * _rest[i]
		if not _primed:
			_prev_pos[i] = anchor
			_prev_vel[i] = Vector3.ZERO
			continue
		var vel := (anchor - _prev_pos[i]) / delta
		var acc := (vel - _prev_vel[i]) / delta
		_prev_pos[i] = anchor
		_prev_vel[i] = vel
		if acc.length() > _max_accel:
			acc = acc.normalized() * _max_accel
		var local := xf.basis.orthonormalized().transposed() * acc
		var spring: JiggleSpring = _springs[i]
		spring.step(delta, -local * _gain)
		node.position = _rest[i] + spring.offset
		var s := clampf(spring.offset.y / maxf(spring.limit, 0.0001), -1.0, 1.0)
		node.scale = _base_scale[i] * Vector3(1.0 - 0.5 * _squash * s, 1.0 + _squash * s, 1.0 - 0.5 * _squash * s)
	_primed = true
