# Purpose: the 3D roulette table: a felt layout with the 37 numbers, and a real spinning wheel (37 coloured pockets in true European order) with a ball that orbits against the wheel, spirals in and drops into the pre-rolled pocket. Draws only; core/roulette_rules.gd picks the number and game_session calls spin_to().
# Dependencies: core/roulette_rules.gd (WHEEL order, colours).
# Layout (table-local): felt layout centred at the origin (x long), wheel at x = WHEEL_X, tabletop y = TOP.
extends Node3D

const Roulette = preload("res://core/roulette_rules.gd")
const ChipStack = preload("res://game/chip_stack.gd")

signal finished  # the ball has settled

const TOP := 0.95
const WHEEL_X := -1.75
const WHEEL_R := 0.5
const POCKET_R0 := 0.26
const POCKET_R1 := 0.42
const SPIN_TIME := 5.5
const WHEEL_SPEED := 0.8  # rad/s
const CELL_X0 := -0.95
const CELL_W := 0.19
const OUTSIDE := ["low", "even", "red", "black", "odd", "high"]

var _stacks: Dictionary = {}  # bet key -> ChipStack

var _wheel: Node3D
var _ball: MeshInstance3D
var _spinning := false
var _t := 0.0
var _target_rel := 0.0
var _turns := 6.0
var _result := 0
var _wheel_angle := 0.0


func _ready() -> void:
	_felt()
	_zone_labels()
	_build_wheel()


func is_busy() -> bool:
	return _spinning


func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, solid: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	add_child(n)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)


func _felt() -> void:
	var wood := _mat(Color(0.3, 0.14, 0.06))
	_box(Vector3(3.8, 0.1, 1.4), Vector3(-0.5, TOP - 0.05, 0), _mat(Color(0.05, 0.4, 0.2)))  # felt (layout + wheel end)
	_box(Vector3(3.8, 0.16, 0.14), Vector3(-0.5, TOP - 0.02, 0.77), wood)
	_box(Vector3(3.8, 0.16, 0.14), Vector3(-0.5, TOP - 0.02, -0.77), wood)
	_box(Vector3(0.14, 0.16, 1.4), Vector3(-2.47, TOP - 0.02, 0), wood)
	_box(Vector3(0.14, 0.16, 1.4), Vector3(1.47, TOP - 0.02, 0), wood)
	_box(Vector3(3.7, 0.85, 1.3), Vector3(-0.5, 0.425, 0), _mat(Color(0.12, 0.05, 0.08)), true)
	_box(Vector3(3.82, 0.04, 1.42), Vector3(-0.5, TOP - 0.11, 0), _mat(Color(1.0, 0.8, 0.25), true))
	# number cells: 0 on the left, then 3 rows x 12 columns (1 at the bottom-left of the grid like a real layout)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -0.95
	var cw := 0.19
	var ch := 0.2
	for n in 37:
		var cx := x0
		var cz := 0.0
		if n == 0:
			cx = x0 - 0.12
			cz = 0.0
			_cell(st, cx, cz, 0.2, 0.6, Color(0.1, 0.6, 0.2))
		else:
			var col := floori(float(n - 1) / 3.0)
			var row := (n - 1) % 3  # 0 = bottom row (1,4,7..), 2 = top row (3,6,9..)
			cx = x0 + cw * 0.5 + cw * float(col) + 0.02
			cz = 0.2 - 0.2 * float(row) + 0.0
			var c := Color(0.8, 0.08, 0.1) if Roulette.is_red(n) else Color(0.06, 0.06, 0.08)
			_cell(st, cx, cz, cw - 0.015, ch - 0.015, c)
		var label := Label3D.new()
		label.text = str(n)
		label.font_size = 40
		label.pixel_size = 0.0035
		label.modulate = Color(1, 1, 1)
		label.shaded = false
		label.rotation_degrees.x = -90.0
		label.position = Vector3(cx, TOP + 0.004, cz)
		add_child(label)
	var layout := MeshInstance3D.new()
	layout.mesh = st.commit()
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	layout.material_override = lm
	add_child(layout)


# One flat coloured cell on the felt (x/z centre, size).
func _cell(st: SurfaceTool, cx: float, cz: float, w: float, d: float, color: Color) -> void:
	var y := TOP + 0.001
	var a := Vector3(cx - w * 0.5, y, cz - d * 0.5)
	var b := Vector3(cx + w * 0.5, y, cz - d * 0.5)
	var c := Vector3(cx + w * 0.5, y, cz + d * 0.5)
	var e := Vector3(cx - w * 0.5, y, cz + d * 0.5)
	for v in [a, c, b, a, e, c]:
		st.set_color(color)
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


func _build_wheel() -> void:
	_wheel = Node3D.new()
	_wheel.position = Vector3(WHEEL_X, TOP + 0.02, 0)
	add_child(_wheel)
	# outer bowl: a dark ring + a gold rim
	var bowl := CylinderMesh.new()
	bowl.top_radius = WHEEL_R
	bowl.bottom_radius = WHEEL_R + 0.03
	bowl.height = 0.06
	bowl.radial_segments = 32
	bowl.rings = 1
	var bm := MeshInstance3D.new()
	bm.mesh = bowl
	bm.material_override = _mat(Color(0.25, 0.1, 0.04))
	bm.position = Vector3(0, -0.02, 0)
	add_child_at(bm)
	var rim := TorusMesh.new()
	rim.inner_radius = WHEEL_R - 0.02
	rim.outer_radius = WHEEL_R + 0.02
	rim.rings = 32
	rim.ring_segments = 4
	var rm := MeshInstance3D.new()
	rm.mesh = rim
	rm.material_override = _mat(Color(1.0, 0.8, 0.25), true)
	rm.position = Vector3(0, 0.03, 0)
	rm.scale = Vector3(1.0, 0.6, 1.0)
	add_child_at(rm)
	# spinning part: coloured pockets in wheel order
	var spin := Node3D.new()
	spin.name = "Spin"
	spin.position = Vector3(0, 0.035, 0)
	_wheel.add_child(spin)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Roulette.WHEEL.size()
	for i in n:
		var num: int = Roulette.WHEEL[i]
		var color := Color(0.1, 0.6, 0.2)
		if num != 0:
			color = Color(0.8, 0.08, 0.1) if Roulette.is_red(num) else Color(0.06, 0.06, 0.08)
		var a0 := float(i) * TAU / float(n)
		var a1 := float(i + 1) * TAU / float(n)
		var p00 := Vector3(sin(a0) * POCKET_R0, 0, cos(a0) * POCKET_R0)
		var p01 := Vector3(sin(a0) * POCKET_R1, 0, cos(a0) * POCKET_R1)
		var p10 := Vector3(sin(a1) * POCKET_R0, 0, cos(a1) * POCKET_R0)
		var p11 := Vector3(sin(a1) * POCKET_R1, 0, cos(a1) * POCKET_R1)
		var shade := color.lightened(0.0 if i % 2 == 0 else 0.12)
		for v in [p00, p11, p01, p00, p10, p11]:
			st.set_color(shade)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		# gold divider between pockets
		var mid := Vector3(sin(a1) * (POCKET_R0 + POCKET_R1) * 0.5, 0.004, cos(a1) * (POCKET_R0 + POCKET_R1) * 0.5)
		var d := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(0.006, 0.012, POCKET_R1 - POCKET_R0)
		d.mesh = dm
		d.material_override = _mat(Color(0.95, 0.85, 0.5))
		d.position = mid
		d.rotation.y = a1
		spin.add_child(d)
	var pockets := MeshInstance3D.new()
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pockets.mesh = st.commit()
	pockets.material_override = lm
	spin.add_child(pockets)
	# inner wooden cone + knob
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = POCKET_R0
	cone.height = 0.1
	cone.radial_segments = 24
	cone.rings = 1
	var cm := MeshInstance3D.new()
	cm.mesh = cone
	cm.material_override = _mat(Color(0.5, 0.25, 0.1))
	cm.position = Vector3(0, 0.05, 0)
	spin.add_child(cm)
	var knob := SphereMesh.new()
	knob.radius = 0.035
	knob.height = 0.07
	knob.radial_segments = 8
	knob.rings = 4
	var km := MeshInstance3D.new()
	km.mesh = knob
	km.material_override = _mat(Color(1.0, 0.8, 0.25), true)
	km.position = Vector3(0, 0.11, 0)
	spin.add_child(km)
	# the ball (child of the wheel node, not of the spinning part, so we can drive its world angle)
	var ball := SphereMesh.new()
	ball.radius = 0.016
	ball.height = 0.032
	ball.radial_segments = 8
	ball.rings = 4
	_ball = MeshInstance3D.new()
	_ball.mesh = ball
	_ball.material_override = _mat(Color(1, 1, 1), true)
	_wheel.add_child(_ball)
	_place_ball(0.0, POCKET_R1 + 0.04, 0.03)
	var title := Label3D.new()
	title.text = "ROULETTE"
	title.font_size = 36
	title.pixel_size = 0.0025
	title.modulate = Color(1.0, 0.85, 0.4)
	title.shaded = false
	title.rotation_degrees.x = -90.0
	title.position = Vector3(WHEEL_X, TOP + 0.006, 0.62)
	add_child(title)


func add_child_at(n: Node3D) -> void:
	_wheel.add_child(n)


func _place_ball(angle: float, radius: float, height: float) -> void:
	_ball.position = Vector3(sin(angle) * radius, 0.035 + height, cos(angle) * radius)


# Spins the wheel one way and the ball the other; after SPIN_TIME the ball drops into pocket `number`.
func spin_to(number: int) -> void:
	_result = number
	var index: int = Roulette.WHEEL.find(number)
	_target_rel = float(index) * TAU / float(Roulette.WHEEL.size()) + 0.5 * TAU / float(Roulette.WHEEL.size())
	_turns = 6.0
	_t = 0.0
	_spinning = true


func _process(delta: float) -> void:
	var spin: Node3D = _wheel.get_node("Spin")
	_wheel_angle += WHEEL_SPEED * delta * (1.0 if not _spinning else 1.6)
	spin.rotation.y = _wheel_angle
	if not _spinning:
		_place_ball(_wheel_angle + _target_rel, POCKET_R0 + 0.07, 0.012)
		return
	_t += delta
	var u := clampf(_t / SPIN_TIME, 0.0, 1.0)
	# angle of the ball relative to the wheel: unwinds from -turns*TAU to the pocket angle; radius spirals in, then a small hop
	var rel := _target_rel - _turns * TAU * pow(1.0 - u, 2.0)
	var radius := lerpf(POCKET_R1 + 0.05, POCKET_R0 + 0.07, smoothstep(0.55, 0.95, u))
	var hop := maxf(0.0, sin(clampf((u - 0.9) / 0.1, 0.0, 1.0) * PI * 3.0)) * 0.03 * (1.0 - u) * 10.0
	_place_ball(_wheel_angle + rel, radius, 0.03 * (1.0 - smoothstep(0.7, 0.95, u)) + hop)
	if _t >= SPIN_TIME:
		_spinning = false
		finished.emit()


# Felt position (table-local) where a bet key's chips sit.
func bet_position(key: String) -> Vector3:
	var parts := key.split(":")
	var kind := parts[0]
	var n := int(parts[1]) if parts.size() > 1 else 0
	var x := CELL_X0 + 0.02
	if kind == "straight":
		if n == 0:
			return Vector3(CELL_X0 - 0.12, TOP, 0.0)
		var col := floori(float(n - 1) / 3.0)
		return Vector3(x + CELL_W * 0.5 + CELL_W * float(col), TOP, 0.2 - 0.2 * float((n - 1) % 3))
	if kind == "column":
		return Vector3(1.43, TOP + 0.06, 0.2 - 0.2 * float(n - 1))
	if kind == "dozen":
		return Vector3(x + CELL_W * float(4 * (n - 1) + 2), TOP, 0.4)
	return Vector3(x + CELL_W * float(2 * OUTSIDE.find(kind) + 1), TOP, 0.56)


# Shows one chip stack per bet key; keys no longer bet are hidden.
func show_bets(bets: Dictionary) -> void:
	for key: String in bets:
		if not _stacks.has(key):
			var st: Node3D = ChipStack.new()
			st.position = bet_position(key)
			add_child(st)
			_stacks[key] = st
		_stacks[key].set_amount(int(bets[key]))
	for key: String in _stacks:
		if not bets.has(key):
			_stacks[key].set_amount(0)


func _zone_labels() -> void:
	var names := ["1st 12", "2nd 12", "3rd 12"]
	for i in 3:
		_zone_label(names[i], Vector3(CELL_X0 + 0.02 + CELL_W * float(4 * i + 2), TOP + 0.004, 0.4))
	var outside := ["1-18", "EVEN", "RED", "BLACK", "ODD", "19-36"]
	for i in 6:
		_zone_label(outside[i], Vector3(CELL_X0 + 0.02 + CELL_W * float(2 * i + 1), TOP + 0.004, 0.56))


func _zone_label(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 36
	label.pixel_size = 0.0035
	label.modulate = Color(1.0, 0.85, 0.4)
	label.shaded = false
	label.rotation_degrees.x = -90.0
	label.position = pos
	add_child(label)
