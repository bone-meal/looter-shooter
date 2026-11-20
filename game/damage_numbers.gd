# Purpose: floating damage numbers: a fixed pool of billboard Label3D nodes that rise and fade. No allocation while playing.
# (polish1 item 52) Hits on the SAME target while its number is still up STACK into one growing total that gets
# bigger as it climbs (20,000 should feel big); a crit / headshot shows in its own colour with a pop and tells the
# HUD (signal crit_hit: a faint red X on the crosshair).
# Dependencies: none. game/player.gd calls spawn() when a shot hits an enemy; the session connects crit_hit to the HUD.
extends Node3D

const POOL_SIZE := 24
const LIFETIME := 1.0
const STACK_S := 1.0  # a new hit on the same target while its number is still up adds to it
const RISE_SPEED := 1.6
const BASE_FONT := 40
const NORMAL := Color(1.0, 0.95, 0.5)
const CRIT := Color(1.0, 0.42, 0.12)

signal shown(amount: float)  # a number of our damage came up (the session keeps the total: core/stat_book.gd)
signal crit_hit  # a crit or a headshot landed (the HUD's red X)

var _labels: Array[Label3D] = []
var _ages: PackedFloat32Array = PackedFloat32Array()
var _starts: PackedVector3Array = PackedVector3Array()
var _totals: PackedFloat32Array = PackedFloat32Array()  # the stacked total each label shows
var _targets: PackedInt64Array = PackedInt64Array()  # the target's instance id (0 = none: never stacks)
var _pops: PackedFloat32Array = PackedFloat32Array()  # 1 -> 0 after each added hit: the number swells for a moment
var _next := 0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in POOL_SIZE:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = true
		label.pixel_size = 0.0012
		label.font_size = BASE_FONT
		label.outline_size = 12
		label.outline_modulate = Color(0, 0, 0, 1)
		label.visible = false
		add_child(label)
		_labels.append(label)
		_ages.append(LIFETIME)
		_starts.append(Vector3.ZERO)
		_totals.append(0.0)
		_targets.append(0)
		_pops.append(0.0)


# A number at `at`. With a target, a number of that target still up takes the amount instead (stacking).
func spawn(at: Vector3, amount: float, crit := false, target: Object = null) -> void:
	shown.emit(amount)
	if crit:
		crit_hit.emit()
	var id := target.get_instance_id() if target != null else 0
	var i := -1
	if id != 0:
		for k in POOL_SIZE:
			if _targets[k] == id and _ages[k] < STACK_S:
				i = k
				break
	if i < 0:
		i = _next
		_next = (_next + 1) % POOL_SIZE
		_totals[i] = 0.0
		_labels[i].modulate = NORMAL
	_targets[i] = id
	_totals[i] += amount
	_starts[i] = at + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
	_ages[i] = 0.0
	_pops[i] = 1.0 if crit else 0.5
	var label := _labels[i]
	label.text = _grouped(roundi(_totals[i]))
	label.font_size = BASE_FONT + int(9.0 * log(maxf(_totals[i], 1.0)) / log(10.0))  # 100 -> 58, 20,000 -> 78
	label.offset = Vector2.ZERO
	if crit:
		label.modulate = CRIT  # once a crit is in the stack the number keeps the crit colour
	label.global_position = _starts[i]
	label.visible = true


# A short word over a creature ("WEAK!") from the same pool.
func say(at: Vector3, words: String, color: Color) -> void:
	var i := _next
	spawn(at, 0.0)
	var label := _labels[i]
	_targets[i] = 0
	label.text = words
	label.font_size = BASE_FONT
	label.modulate = color
	label.offset = Vector2(0.0, 48.0)  # a line above the number it belongs to


# 20000 -> "20,000".
static func _grouped(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		if _ages[i] >= LIFETIME:
			continue
		_ages[i] += delta
		var label := _labels[i]
		if _ages[i] >= LIFETIME:
			label.visible = false
			_targets[i] = 0
			continue
		_pops[i] = maxf(_pops[i] - delta * 5.0, 0.0)
		label.pixel_size = 0.0012 * (1.0 + 0.45 * _pops[i])
		label.global_position = _starts[i] + Vector3(0, _ages[i] * RISE_SPEED, 0)
		label.modulate.a = 1.0 - _ages[i] / LIFETIME
