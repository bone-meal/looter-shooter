# Purpose: the giant pachinko machine on the casino back wall: cabinet, peg board, pooled balls drawn from core/pachinko_sim.gd, pocket trays, sweeping aim marker, chasing side lights and the launch console. Draws only; the sim decides where balls land and what they pay.
# Dependencies: core/pachinko_sim.gd, core/data_store.gd, data/pachinko.json. game/game_session.gd spends coins, calls launch() and listens to ball_landed.
extends Node3D

const Sim = preload("res://core/pachinko_sim.gd")
const DataStore = preload("res://core/data_store.gd")

signal ball_landed(pocket: int, coins: int, pocket_name: String)

const S := 0.62  # metres per sim unit
const GOLD := Color(1.0, 0.8, 0.25)
const PINK := Color(1.0, 0.1, 0.6)
const CYAN := Color(0.1, 0.9, 1.0)
const CONSOLE_LOCAL := Vector3(0, -8.8, 2.85)
const LAMPS_PER_SIDE := 16

var sim: Sim

var _names: Array = []
var _sweep := 1.4
var _balls: MultiMesh
var _pegs: MultiMesh
var _row_start := PackedInt32Array()
var _peg_flash := PackedFloat32Array()
var _peg_on := PackedByteArray()
var _peg_active := PackedInt32Array()
var _pocket_mats: Array[StandardMaterial3D] = []
var _pocket_base: Array[Color] = []
var _pocket_glow := PackedFloat32Array()
var _popups: Array[Label3D] = []
var _popup_t := PackedFloat32Array()
var _marker: Node3D
var _needle: Node3D
var _lamps: Array[StandardMaterial3D] = []
var _lamp_step := -1
var _t := 0.0


func _ready() -> void:
	var data: Dictionary = DataStore.load_json("res://data/pachinko.json")
	sim = Sim.new(data)
	_sweep = float(data["aim_sweep_speed"])
	_names = data["pocket_names"]
	_cabinet()
	_build_pegs()
	_build_pockets()
	_build_balls()
	_rail()
	_marquee()
	_side_lamps()
	_console()


func ball_cost() -> int:
	return sim.ball_cost


func balls_in_play() -> int:
	return sim.count


# 0..1 position of the sweeping marker right now (0.5 = the bullseye line).
func aim_now() -> float:
	return 0.5 + 0.5 * sin(_t * _sweep)


func launch() -> bool:
	return sim.launch(aim_now())


func console_position() -> Vector3:
	return to_global(CONSOLE_LOCAL)


# sim coordinates (x right, y down) -> local position
func _p(sx: float, sy: float, z: float = 0.0) -> Vector3:
	return Vector3((sx - sim.width * 0.5) * S, -sy * S, z)


func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid: bool = false) -> MeshInstance3D:
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
	return n


func _label(text: String, size_px: int, pixel: float, color: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.pixel_size = pixel
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0)
	l.modulate = color
	l.shaded = false
	l.double_sided = false
	l.position = pos
	add_child(l)
	return l


func _cabinet() -> void:
	# whole-wall panel (the machine IS the wall), play field and gold frame
	_box(self, Vector3(10.6, 10.0, 0.3), Vector3(0, -3.8, -0.25), _mat(Color(0.12, 0.05, 0.2)))
	var fw := sim.width * S
	var top := -0.4 * S
	var bottom := -(sim.floor_y + 1.0) * S
	var h := top - bottom
	var cy := (top + bottom) * 0.5
	_box(self, Vector3(fw + 0.5, h + 0.2, 0.1), Vector3(0, cy, -0.12), _mat(Color(0.04, 0.03, 0.14)))
	var gold := _mat(GOLD, true)
	_box(self, Vector3(fw + 0.8, 0.2, 0.3), Vector3(0, top + 0.2, 0.0), gold)
	_box(self, Vector3(fw + 0.8, 0.2, 0.3), Vector3(0, bottom - 0.1, 0.0), gold)
	_box(self, Vector3(0.2, h + 0.4, 0.3), Vector3(-fw * 0.5 - 0.3, cy, 0.0), gold)
	_box(self, Vector3(0.2, h + 0.4, 0.3), Vector3(fw * 0.5 + 0.3, cy, 0.0), gold)


func _build_pegs() -> void:
	var total := 0
	for r in sim.rows:
		_row_start.append(total)
		total += sim.peg_count_in_row(r)
	var mesh := CylinderMesh.new()
	mesh.top_radius = sim.peg_radius * S * 1.2
	mesh.bottom_radius = sim.peg_radius * S * 1.2
	mesh.height = 0.14
	mesh.radial_segments = 8
	mesh.rings = 1
	var m := _mat(Color(1, 1, 1), true)
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	_pegs = MultiMesh.new()
	_pegs.transform_format = MultiMesh.TRANSFORM_3D
	_pegs.use_colors = true
	_pegs.mesh = mesh
	_pegs.instance_count = total
	var facing := Basis(Vector3.RIGHT, PI * 0.5)  # cylinder axis along z
	for r in sim.rows:
		for c in sim.peg_count_in_row(r):
			var i := _row_start[r] + c
			_pegs.set_instance_transform(i, Transform3D(facing, _p(sim.peg_x(r, c), sim.peg_y(r), 0.02)))
			_pegs.set_instance_color(i, GOLD * 0.8)
	_peg_flash.resize(total)
	_peg_flash.fill(0.0)
	_peg_on.resize(total)
	_peg_on.fill(0)
	var node := MultiMeshInstance3D.new()
	node.multimesh = _pegs
	add_child(node)


func _build_pockets() -> void:
	for i in sim.bins:
		var mult := sim.multiplier(i)
		var color := Color(0.45, 0.05, 0.12)
		if mult >= 2.0:
			color = GOLD
		elif mult >= 0.5:
			color = Color(0.1, 0.65, 0.3)
		elif mult > 0.0:
			color = Color(0.15, 0.35, 0.85)
		var mat := _mat(color, true)
		_pocket_mats.append(mat)
		_pocket_base.append(color)
		var cx := (float(i) + 0.5) * sim.bin_width
		_box(self, Vector3(sim.bin_width * S * 0.9, 0.5, 0.25), _p(cx, sim.floor_y + 0.45, 0.05), mat)
		var text := String(_names[i])
		if mult > 0.0:
			text += "\nx%.1f" % mult
		_label(text, 40, 0.0035, Color(1, 1, 1), _p(cx, sim.floor_y + 0.45, 0.2))
		var popup := _label("", 64, 0.008, GOLD, _p(cx, sim.floor_y - 1.0, 0.3))
		popup.visible = false
		_popups.append(popup)
	_pocket_glow.resize(sim.bins)
	_pocket_glow.fill(0.0)
	_popup_t.resize(sim.bins)
	_popup_t.fill(0.0)


func _build_balls() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = sim.ball_radius * S * 1.1
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 5
	var m := _mat(Color(0.85, 0.88, 0.95))
	m.metallic = 0.3
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = Color(0.7, 0.75, 0.85)
	m.emission_energy_multiplier = 0.5
	mesh.material = m
	_balls = MultiMesh.new()
	_balls.transform_format = MultiMesh.TRANSFORM_3D
	_balls.mesh = mesh
	_balls.instance_count = sim.max_balls
	_balls.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = _balls
	add_child(node)


# Top rail the aim marker slides along; the gold tick in the middle is the bullseye line.
func _rail() -> void:
	var x0 := (sim.aim_min_x - sim.width * 0.5) * S
	var x1 := (sim.aim_max_x - sim.width * 0.5) * S
	_box(self, Vector3(x1 - x0, 0.05, 0.06), Vector3((x0 + x1) * 0.5, -0.5, 0.05), _mat(CYAN, true))
	_box(self, Vector3(0.07, 0.5, 0.06), Vector3(0, -0.4, 0.05), _mat(GOLD, true))
	_marker = Node3D.new()
	_marker.position = Vector3(0, -0.28, 0.08)
	add_child(_marker)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.18
	cone.height = 0.36
	cone.radial_segments = 8
	cone.rings = 1
	var tip := MeshInstance3D.new()
	tip.mesh = cone
	tip.material_override = _mat(PINK, true)
	tip.rotation_degrees.x = 180.0  # point down
	_marker.add_child(tip)


func _marquee() -> void:
	var l := _label("PACHINKO", 96, 0.009, PINK, Vector3(0, 0.8, 0.1))
	l.outline_size = 24
	l.outline_modulate = Color(0.4, 0.0, 0.25)
	_label("press when the marker is on the gold line", 48, 0.006, GOLD, Vector3(0, 0.3, 0.1))


func _side_lamps() -> void:
	for side: float in [-1.0, 1.0]:
		for i in LAMPS_PER_SIDE:
			var mat := _mat(PINK, true)
			_lamps.append(mat)
			_box(self, Vector3(0.5, 0.3, 0.2), Vector3(side * 4.4, -0.3 - float(i) * 0.5, 0.0), mat)


func _console() -> void:
	var c := Node3D.new()
	c.position = CONSOLE_LOCAL
	add_child(c)
	_box(c, Vector3(2.6, 1.0, 1.0), Vector3(0, 0.5, 0), _mat(Color(0.2, 0.08, 0.3)), true)
	_box(c, Vector3(2.6, 0.06, 1.04), Vector3(0, 1.0, 0), _mat(PINK, true))
	var dial := CylinderMesh.new()
	dial.top_radius = 0.28
	dial.bottom_radius = 0.28
	dial.height = 0.06
	dial.radial_segments = 16
	dial.rings = 1
	var d := MeshInstance3D.new()
	d.mesh = dial
	d.material_override = _mat(Color(0.1, 0.1, 0.14))
	d.position = Vector3(-0.5, 1.06, 0.1)
	c.add_child(d)
	_needle = Node3D.new()
	_needle.position = Vector3(-0.5, 1.1, 0.1)
	c.add_child(_needle)
	_box(_needle, Vector3(0.04, 0.02, 0.24), Vector3(0, 0, -0.12), _mat(GOLD, true))
	var button := CylinderMesh.new()
	button.top_radius = 0.2
	button.bottom_radius = 0.22
	button.height = 0.1
	button.radial_segments = 12
	button.rings = 1
	var b := MeshInstance3D.new()
	b.mesh = button
	b.material_override = _mat(Color(1.0, 0.1, 0.15), true)
	b.position = Vector3(0.5, 1.08, 0.1)
	c.add_child(b)
	var l := Label3D.new()
	l.text = "LAUNCH  %d chips" % sim.ball_cost
	l.font_size = 48
	l.pixel_size = 0.005
	l.modulate = GOLD
	l.shaded = false
	l.position = Vector3(0, 0.6, 0.52)
	c.add_child(l)


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_t += delta
	var aim := aim_now()
	_marker.position.x = (lerpf(sim.aim_min_x, sim.aim_max_x, aim) - sim.width * 0.5) * S
	_needle.rotation_degrees.y = lerpf(-70.0, 70.0, aim)
	for pocket in sim.step(delta):
		_pocket_glow[pocket] = 1.0
		var coins := sim.payout(pocket)
		_popup_t[pocket] = 1.4
		if coins > 0:
			_popups[pocket].text = "+%d" % coins
			_popups[pocket].visible = true
		ball_landed.emit(pocket, coins, String(_names[pocket]))
	_draw_balls()
	_flash_pegs(delta)
	_glow_pockets(delta)
	_chase_lamps()


func _draw_balls() -> void:
	_balls.visible_instance_count = sim.count
	for i in sim.count:
		_balls.set_instance_transform(i, Transform3D(Basis.IDENTITY, _p(sim.xs[i], sim.ys[i], 0.04)))


func _flash_pegs(delta: float) -> void:
	for id in sim.hit_pegs:
		var row := floori(float(id) / 100.0)
		var idx := _row_start[row] + (id - row * 100)
		_peg_flash[idx] = 1.0
		if _peg_on[idx] == 0:
			_peg_on[idx] = 1
			_peg_active.append(idx)
	var k := 0
	while k < _peg_active.size():
		var idx := _peg_active[k]
		_peg_flash[idx] = maxf(_peg_flash[idx] - delta * 4.0, 0.0)
		_pegs.set_instance_color(idx, (GOLD * 0.8).lerp(Color(1.0, 0.4, 0.9), _peg_flash[idx]))
		if _peg_flash[idx] <= 0.0:
			_peg_on[idx] = 0
			_peg_active[k] = _peg_active[_peg_active.size() - 1]
			_peg_active.resize(_peg_active.size() - 1)
		else:
			k += 1


func _glow_pockets(delta: float) -> void:
	for i in sim.bins:
		if _pocket_glow[i] > 0.0:
			_pocket_glow[i] = maxf(_pocket_glow[i] - delta * 2.0, 0.0)
			_pocket_mats[i].albedo_color = _pocket_base[i].lerp(Color(1, 1, 1), _pocket_glow[i])
		if _popup_t[i] > 0.0:
			_popup_t[i] -= delta
			_popups[i].position.y += delta * 0.5
			if _popup_t[i] <= 0.0:
				_popups[i].visible = false
				_popups[i].position.y = _p(0.0, sim.floor_y - 1.0).y


func _chase_lamps() -> void:
	var step := floori(_t * 8.0)
	if step == _lamp_step:
		return
	_lamp_step = step
	for i in _lamps.size():
		var lit := (i + step) % 3 == 0
		_lamps[i].albedo_color = PINK if lit else Color(0.25, 0.04, 0.2)
