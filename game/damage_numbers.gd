# Purpose: floating damage numbers: a fixed pool of billboard Label3D nodes that rise and fade. No allocation while playing.
# Dependencies: none. game/player.gd calls spawn() when a shot hits an enemy.
extends Node3D

const POOL_SIZE := 24
const LIFETIME := 0.8
const RISE_SPEED := 1.6

var _labels: Array[Label3D] = []
var _ages: PackedFloat32Array = PackedFloat32Array()
var _starts: PackedVector3Array = PackedVector3Array()
var _next := 0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in POOL_SIZE:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = true
		label.pixel_size = 0.0012
		label.font_size = 40
		label.outline_size = 12
		label.outline_modulate = Color(0, 0, 0, 1)
		label.visible = false
		add_child(label)
		_labels.append(label)
		_ages.append(LIFETIME)
		_starts.append(Vector3.ZERO)


func spawn(at: Vector3, amount: float) -> void:
	var label := _labels[_next]
	_starts[_next] = at + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
	_ages[_next] = 0.0
	label.text = str(roundi(amount))
	label.offset = Vector2.ZERO
	label.modulate = Color(1.0, 0.95, 0.5, 1.0)
	label.global_position = _starts[_next]
	label.visible = true
	_next = (_next + 1) % POOL_SIZE


# A short word over a creature ("WEAK!") from the same pool.
func say(at: Vector3, words: String, color: Color) -> void:
	spawn(at, 0.0)
	var label := _labels[(_next + POOL_SIZE - 1) % POOL_SIZE]
	label.text = words
	label.modulate = color
	label.offset = Vector2(0.0, 48.0)  # a line above the number it belongs to


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		if _ages[i] >= LIFETIME:
			continue
		_ages[i] += delta
		var label := _labels[i]
		if _ages[i] >= LIFETIME:
			label.visible = false
			continue
		label.global_position = _starts[i] + Vector3(0, _ages[i] * RISE_SPEED, 0)
		label.modulate.a = 1.0 - _ages[i] / LIFETIME
