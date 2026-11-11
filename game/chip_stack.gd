# Purpose: a small stack of casino chips on a table with the amount floating above it (shows what is bet). Rebuilt only when the amount changes.
# Dependencies: none (used by game/blackjack_table.gd and game/roulette_table.gd).
extends Node3D

const DENOMS := [100, 25, 10, 5, 1]
const COLORS := [Color(0.08, 0.08, 0.1), Color(0.1, 0.6, 0.25), Color(0.15, 0.35, 0.85), Color(0.85, 0.12, 0.12), Color(0.92, 0.92, 0.9)]
const CHIP_R := 0.032
const CHIP_H := 0.009
const MAX_CHIPS := 7

static var _mesh: CylinderMesh
static var _mats: Array[StandardMaterial3D] = []

var amount := 0
var _label := Label3D.new()


func _ready() -> void:
	if _mesh == null:
		_mesh = CylinderMesh.new()
		_mesh.top_radius = CHIP_R
		_mesh.bottom_radius = CHIP_R
		_mesh.height = CHIP_H
		_mesh.radial_segments = 14
		_mesh.rings = 1
		for c: Color in COLORS:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			_mats.append(m)
	_label.font_size = 32
	_label.pixel_size = 0.0022
	_label.modulate = Color(1.0, 0.9, 0.45)
	_label.outline_size = 8
	_label.shaded = false
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	add_child(_label)
	visible = false


# Shows `value` coins as up to MAX_CHIPS chips (largest denominations first). 0 hides the stack.
func set_amount(value: int) -> void:
	if value == amount:
		return
	amount = value
	for c in get_children():
		if c != _label:
			c.queue_free()
	visible = value > 0
	if value <= 0:
		return
	var left := value
	var count := 0
	for i in DENOMS.size():
		while left >= int(DENOMS[i]) and count < MAX_CHIPS:
			left -= int(DENOMS[i])
			_add_chip(i, count)
			count += 1
	if count == 0:
		_add_chip(4, 0)
		count = 1
	_label.text = str(value)
	_label.position = Vector3(0, CHIP_H * float(count) + 0.05, 0)


func _add_chip(color_index: int, level: int) -> void:
	var n := MeshInstance3D.new()
	n.mesh = _mesh
	n.material_override = _mats[color_index]
	n.position = Vector3(0, CHIP_H * (float(level) + 0.5), 0)
	add_child(n)
