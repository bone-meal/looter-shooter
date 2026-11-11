# Purpose: one 3D slot machine: cabinet, three real cylinder drums (20 symbol facets each, one mesh per drum) that spin and stop one after another with a bounce, jackpot marquee with the pot, chase bulbs that flash on wins, a lever that pulls. Draws only; the result is decided by core/slot_math.gd and passed in.
# Dependencies: game/symbol_art.gd, data/slots.json (strip order), core/data_store.gd.
extends Node3D

const SymbolArt = preload("res://game/symbol_art.gd")
const DataStore = preload("res://core/data_store.gd")

signal finished  # all three reels have stopped

const FACETS := 20
const STEP := TAU / 20.0
const REEL_W := 0.36
const APOTHEM := 0.69
const RADIUS := 0.7
const REEL_X: Array[float] = [-0.41, 0.0, 0.41]
const WINDOW_Y := 1.5
const SPIN_SPEED := 12.0  # rad/s while spinning
const GOLD := Color(1.0, 0.8, 0.25)
const PINK := Color(1.0, 0.1, 0.6)
const CYAN := Color(0.1, 0.9, 1.0)
const BULBS := 14

var _strip: Array = []
var _drums: Array[MeshInstance3D] = []
var _state: Array[int] = [0, 0, 0]  # 0 idle, 1 spinning, 2 settling
var _stops: Array[int] = [0, 0, 0]
var _stop_at: Array[float] = [0.0, 0.0, 0.0]
var _t_spin := 0.0
var _spinning := false
var _bulbs: Array[StandardMaterial3D] = []
var _flash_t := 0.0
var _flash_jackpot := false
var _t := 0.0
var _pot_label: Label3D
var _screen_label: Label3D
var _lever: Node3D
var _lever_t := 0.0
var _settled := 0
var _bulb_step := -1


func _ready() -> void:
	_strip = DataStore.load_json("res://data/slots.json")["strip"]
	_cabinet()
	for k in 3:
		_drums.append(_make_drum(k))
	_lights_and_labels()
	_lever_build()
	for k in 3:
		_drums[k].rotation.x = _angle_for_stop(k * 7 % FACETS)


func is_busy() -> bool:
	return _spinning


func set_pot(pot: float) -> void:
	_pot_label.text = "%d" % floori(pot)


func set_screen(text: String) -> void:
	_screen_label.text = text


# Starts the spin; reels land on `stops` (strip indices) one after another, then `finished` is emitted.
func spin_to(stops: Array[int]) -> void:
	_stops = stops
	_spinning = true
	_t_spin = 0.0
	_settled = 0
	_lever_t = 0.6
	_flash_t = 0.0
	for k in 3:
		_state[k] = 1
		_stop_at[k] = 1.0 + 0.55 * float(k)


# Win animation: bulbs flash (longer and faster for the jackpot).
func flash_win(jackpot: bool) -> void:
	_flash_t = 4.0 if jackpot else 1.6
	_flash_jackpot = jackpot


# Drum rotation (radians about X) that brings strip index `stop` to the front. Facet j holds strip[-j].
func _angle_for_stop(stop: int) -> float:
	return float(posmod(-stop, FACETS)) * STEP


func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	parent.add_child(n)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		parent.add_child(body)


# Front is +z. Body 1.5 wide, 1.2 deep, 2.3 tall, plus marquee box on top.
func _cabinet() -> void:
	var body := _mat(Color(0.25, 0.06, 0.35))
	var gold := _mat(GOLD, true)
	# hollow body so the drums show through the window: back, sides, base, top (and an invisible collider)
	_box(self, Vector3(1.5, 2.3, 0.2), Vector3(0, 1.15, -1.1), body)
	_box(self, Vector3(0.2, 2.3, 1.2), Vector3(-0.65, 1.15, -0.6), body)
	_box(self, Vector3(0.2, 2.3, 1.2), Vector3(0.65, 1.15, -0.6), body)
	_box(self, Vector3(1.5, 1.1, 1.2), Vector3(0, 0.55, -0.6), body)
	_box(self, Vector3(1.5, 0.4, 1.2), Vector3(0, 2.1, -0.6), body)
	var solid := StaticBody3D.new()
	solid.position = Vector3(0, 1.15, -0.6)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 2.3, 1.2)
	shape.shape = box
	solid.add_child(shape)
	add_child(solid)
	_box(self, Vector3(1.28, 0.8, 0.05), Vector3(0, WINDOW_Y, -1.15), _mat(Color(0.05, 0.02, 0.1)))  # dark behind the drums
	_box(self, Vector3(1.5, 0.95, 0.12), Vector3(0, 0.55, 0.06), _mat(Color(0.18, 0.04, 0.26)))  # lower front panel
	_box(self, Vector3(1.0, 0.1, 0.3), Vector3(0, 0.98, 0.14), _mat(Color(0.12, 0.12, 0.16)))  # shelf
	# window frame around the drums (opening 1.28 x 0.8)
	_box(self, Vector3(1.5, 0.22, 0.14), Vector3(0, WINDOW_Y + 0.51, 0.07), gold)
	_box(self, Vector3(1.5, 0.22, 0.14), Vector3(0, WINDOW_Y - 0.51, 0.07), gold)
	_box(self, Vector3(0.12, 0.8, 0.14), Vector3(-0.69, WINDOW_Y, 0.07), gold)
	_box(self, Vector3(0.12, 0.8, 0.14), Vector3(0.69, WINDOW_Y, 0.07), gold)
	_box(self, Vector3(1.5, 0.45, 0.12), Vector3(0, 2.07, 0.06), _mat(Color(0.18, 0.04, 0.26)))  # above the window
	_box(self, Vector3(1.6, 0.7, 0.35), Vector3(0, 2.65, -0.15), _mat(Color(0.12, 0.03, 0.2)))  # marquee box
	_box(self, Vector3(0.5, 0.06, 0.2), Vector3(0, 0.12, 0.15), _mat(Color(0.05, 0.05, 0.07)))  # coin tray
	# payline marks beside the window: top, middle, bottom
	for k in 3:
		_box(self, Vector3(0.05, 0.05, 0.05), Vector3(-0.62, WINDOW_Y + 0.22 - 0.22 * float(k), 0.16), _mat(Color(1.0, 0.2, 0.2), true))
		_box(self, Vector3(0.05, 0.05, 0.05), Vector3(0.62, WINDOW_Y + 0.22 - 0.22 * float(k), 0.16), _mat(Color(1.0, 0.2, 0.2), true))


func _make_drum(k: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_h := RADIUS * sin(PI / float(FACETS))
	for j in FACETS:
		var a := float(j) * STEP
		var n := Vector3(0.0, sin(a), cos(a))
		var center := n * APOTHEM
		var tangent := Vector3(0.0, cos(a), -sin(a))
		var uv := SymbolArt.uv_rect(String(_strip[posmod(-j, FACETS)]))
		var bl := center - tangent * half_h + Vector3(-REEL_W * 0.5, 0, 0)
		var br := center - tangent * half_h + Vector3(REEL_W * 0.5, 0, 0)
		var top_r := center + tangent * half_h + Vector3(REEL_W * 0.5, 0, 0)
		var tl := center + tangent * half_h + Vector3(-REEL_W * 0.5, 0, 0)
		var uv_bl := Vector2(uv.position.x, uv.end.y)
		var uv_br := uv.end
		var uv_tr := Vector2(uv.end.x, uv.position.y)
		var uv_tl := uv.position
		for tri in [[bl, uv_bl], [br, uv_br], [top_r, uv_tr], [bl, uv_bl], [top_r, uv_tr], [tl, uv_tl]]:
			st.set_normal(n)
			st.set_uv(tri[1])
			st.add_vertex(tri[0])
	var m := StandardMaterial3D.new()
	m.albedo_texture = SymbolArt.atlas()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = m
	node.position = Vector3(REEL_X[k], WINDOW_Y, -APOTHEM - 0.03)
	add_child(node)
	return node


func _lights_and_labels() -> void:
	# chase bulbs around the window and marquee
	for i in BULBS:
		var mat := _mat(GOLD, true)
		_bulbs.append(mat)
		var side := i % 2 == 0
		var row := floori(float(i) / 2.0)
		var y := WINDOW_Y - 0.42 + float(row) * 0.14
		_box(self, Vector3(0.07, 0.07, 0.06), Vector3(-0.73 if side else 0.73, y, 0.1), mat)
	var jp := Label3D.new()
	jp.text = "JACKPOT"
	jp.font_size = 56
	jp.pixel_size = 0.0035
	jp.modulate = PINK
	jp.outline_size = 10
	jp.shaded = false
	jp.double_sided = false
	jp.position = Vector3(0, 2.8, 0.04)
	add_child(jp)
	_pot_label = Label3D.new()
	_pot_label.font_size = 80
	_pot_label.pixel_size = 0.0038
	_pot_label.modulate = GOLD
	_pot_label.outline_size = 12
	_pot_label.shaded = false
	_pot_label.double_sided = false
	_pot_label.position = Vector3(0, 2.55, 0.04)
	_pot_label.text = "500"
	add_child(_pot_label)
	_box(self, Vector3(1.0, 0.22, 0.04), Vector3(0, 1.0, 0.31), _mat(Color(0.02, 0.05, 0.08)))
	_screen_label = Label3D.new()
	_screen_label.font_size = 40
	_screen_label.pixel_size = 0.0035
	_screen_label.modulate = CYAN
	_screen_label.shaded = false
	_screen_label.double_sided = false
	_screen_label.position = Vector3(0, 1.0, 0.34)
	_screen_label.text = "FREE PLAY  -  press F"
	add_child(_screen_label)


func _lever_build() -> void:
	_lever = Node3D.new()
	_lever.position = Vector3(0.82, 1.2, 0.0)
	add_child(_lever)
	var arm := CylinderMesh.new()
	arm.top_radius = 0.025
	arm.bottom_radius = 0.025
	arm.height = 0.5
	arm.radial_segments = 6
	arm.rings = 1
	var a := MeshInstance3D.new()
	a.mesh = arm
	a.material_override = _mat(Color(0.8, 0.8, 0.85))
	a.position = Vector3(0, 0.25, 0)
	_lever.add_child(a)
	var knob := SphereMesh.new()
	knob.radius = 0.07
	knob.height = 0.14
	knob.radial_segments = 8
	knob.rings = 5
	var kn := MeshInstance3D.new()
	kn.mesh = knob
	kn.material_override = _mat(Color(1.0, 0.1, 0.15), true)
	kn.position = Vector3(0, 0.52, 0)
	_lever.add_child(kn)


func _process(delta: float) -> void:
	_t += delta
	if _spinning:
		_t_spin += delta
		for k in 3:
			if _state[k] == 1:
				_drums[k].rotation.x += SPIN_SPEED * delta
				if _t_spin >= _stop_at[k]:
					_begin_settle(k)
	if _lever_t > 0.0:
		_lever_t = maxf(_lever_t - delta, 0.0)
		_lever.rotation_degrees.x = sin(clampf(_lever_t / 0.6, 0.0, 1.0) * PI) * 55.0
	_flash_t = maxf(_flash_t - delta, 0.0)
	_animate_bulbs()


func _begin_settle(k: int) -> void:
	_state[k] = 2
	var cur := _drums[k].rotation.x
	var target := _angle_for_stop(_stops[k])
	var turns := ceilf((cur + STEP * 3.0 - target) / TAU)
	var end_angle := target + turns * TAU
	var tw := create_tween()
	tw.tween_property(_drums[k], "rotation:x", end_angle, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.finished.connect(_on_reel_settled.bind(k))


func _on_reel_settled(k: int) -> void:
	_state[k] = 0
	_drums[k].rotation.x = _angle_for_stop(_stops[k])
	_settled += 1
	if _settled >= 3:
		_spinning = false
		finished.emit()


func _animate_bulbs() -> void:
	var rate := 14.0 if _flash_t > 0.0 and _flash_jackpot else (9.0 if _flash_t > 0.0 else 3.0)
	var step := floori(_t * rate)
	if step == _bulb_step:
		return
	_bulb_step = step
	for i in _bulbs.size():
		var lit := (i + step) % 3 == 0 if _flash_t <= 0.0 else (step % 2 == 0) == (i % 2 == 0)
		var color := PINK if (_spinning or _flash_t > 0.0) else GOLD
		_bulbs[i].albedo_color = color if lit else color.darkened(0.8)
