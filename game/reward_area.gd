# Purpose: the reward area that appears in the middle of the cleared colosseum: gold floor disc, a chest, and (after the chest is opened) a door back to the island.
# Dependencies: game/worm_model.gd. game/game_session.gd creates it, asks for positions, and calls open_chest().
extends Node3D

const WormModel = preload("res://game/worm_model.gd")

const CHEST_POS := Vector3(0, 0, 0)
const DOOR_POS := Vector3(7, 0, -12)  # clear of the cover pillars

var _lid: Node3D
var _worm: Node3D
var _beam: MeshInstance3D
var _worm_time := -1.0  # seconds since the chest opened (-1 = not playing)
var _door: Node3D
var _chest_open := false


func _ready() -> void:
	_floor_disc()
	_chest()
	_door_frame()


func chest_position() -> Vector3:
	return CHEST_POS


func door_position() -> Vector3:
	return DOOR_POS


func is_chest_open() -> bool:
	return _chest_open


func is_door_ready() -> bool:
	return _door.visible


# Lifts the lid, shows the worm, and makes the door appear.
func open_chest() -> void:
	if _chest_open:
		return
	_chest_open = true
	_beam.visible = false
	_door.visible = true
	create_tween().tween_property(_lid, "rotation:x", -1.9, 0.5)
	_worm.visible = true
	_worm_time = 0.0


# The worm wriggles slowly up out of the chest, hangs in the air, then fades.
const WORM_SECONDS := 6.0


func _process(delta: float) -> void:
	if _worm_time < 0.0:
		return
	_worm_time += delta
	WormModel.pose(_worm, _worm_time, 1.6)
	var rise := smoothstep(0.0, 3.5, _worm_time)
	_worm.position = CHEST_POS + Vector3(0, 0.75 + rise * 1.2, 0)
	_worm.rotation.y = _worm_time * 1.2
	# stands upright as it comes out of the chest
	_worm.rotation.z = lerpf(0.0, PI * 0.5, smoothstep(0.0, 1.5, _worm_time))
	var mat: StandardMaterial3D = _worm.get_meta("material")
	mat.albedo_color.a = clampf((WORM_SECONDS - _worm_time) / 1.5, 0.0, 1.0)
	if _worm_time > WORM_SECONDS:
		_worm.visible = false
		_worm_time = -1.0


func _mesh(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _floor_disc() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 5.0
	disc.bottom_radius = 5.0
	disc.height = 0.04
	_mesh(disc, Color(0.9, 0.75, 0.3), Vector3(0, 0.03, 0))


func _chest() -> void:
	var wood := Color(0.5, 0.28, 0.1)
	var gold := Color(1.0, 0.78, 0.2)
	# hollow body: floor + four walls, so the inside is visible when the lid is up
	_mesh(_box(Vector3(1.2, 0.06, 0.8)), Color(0.18, 0.1, 0.05), CHEST_POS + Vector3(0, 0.03, 0))
	_mesh(_box(Vector3(1.2, 0.7, 0.06)), wood, CHEST_POS + Vector3(0, 0.35, 0.37))
	_mesh(_box(Vector3(1.2, 0.7, 0.06)), wood, CHEST_POS + Vector3(0, 0.35, -0.37))
	_mesh(_box(Vector3(0.06, 0.7, 0.8)), wood, CHEST_POS + Vector3(0.57, 0.35, 0))
	_mesh(_box(Vector3(0.06, 0.7, 0.8)), wood, CHEST_POS + Vector3(-0.57, 0.35, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mesh(_box(Vector3(0.1, 0.72, 0.1)), gold, CHEST_POS + Vector3(sx * 0.6, 0.36, sz * 0.4))
	_mesh(_box(Vector3(1.22, 0.08, 0.82)), gold, CHEST_POS + Vector3(0, 0.04, 0))
	# gold rim around the opening
	_mesh(_box(Vector3(1.22, 0.05, 0.07)), gold, CHEST_POS + Vector3(0, 0.7, 0.38))
	_mesh(_box(Vector3(1.22, 0.05, 0.07)), gold, CHEST_POS + Vector3(0, 0.7, -0.38))
	_mesh(_box(Vector3(0.07, 0.05, 0.82)), gold, CHEST_POS + Vector3(0.58, 0.7, 0))
	_mesh(_box(Vector3(0.07, 0.05, 0.82)), gold, CHEST_POS + Vector3(-0.58, 0.7, 0))
	# treasure pile inside, kept below the rim and inside the walls
	var pile := SphereMesh.new()
	pile.radius = 0.5
	pile.height = 0.5
	pile.radial_segments = 10
	pile.rings = 4
	_mesh(pile, Color(1.0, 0.82, 0.25), CHEST_POS + Vector3(0, 0.3, 0)).scale = Vector3(1.0, 1.0, 0.6)
	# arched lid (half-round, flat underneath), hinged on the back edge
	_lid = Node3D.new()
	_lid.position = CHEST_POS + Vector3(0, 0.7, -0.4)
	add_child(_lid)
	var lid_top := _mesh(_arch_mesh(1.2, 0.4), wood, Vector3.ZERO, _lid)
	(lid_top.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	for sx in [-0.5, 0.0, 0.5]:
		var band := _mesh(_arch_mesh(0.1, 0.43), gold, Vector3(sx, -0.005, 0.0), _lid)
		(band.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(_box(Vector3(0.16, 0.2, 0.06)), gold, Vector3(0, 0.1, 0.82), _lid)  # lock plate
	# glow beam while closed
	var beam := CylinderMesh.new()
	beam.top_radius = 0.45
	beam.bottom_radius = 0.7
	beam.height = 6.0
	beam.radial_segments = 12
	_beam = _mesh(beam, Color(1.0, 0.85, 0.3, 0.18), CHEST_POS + Vector3(0, 3.4, 0))
	var bm := _beam.material_override as StandardMaterial3D
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_worm = WormModel.build()
	_worm.scale = Vector3.ONE * 1.8
	_worm.visible = false
	add_child(_worm)
	var body := StaticBody3D.new()
	body.position = CHEST_POS + Vector3(0, 0.4, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.8, 0.8)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


# Half-round prism along X: semicircle in the YZ plane centered at (y=0, z=0.4+offset), flat bottom, closed ends.
func _arch_mesh(length: float, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 10
	var hx := length * 0.5
	var cz := 0.4
	for i in steps:
		var a0 := PI * float(i) / steps
		var a1 := PI * float(i + 1) / steps
		var p0 := Vector2(cz + cos(a0) * 0.4, sin(a0) * radius)
		var p1 := Vector2(cz + cos(a1) * 0.4, sin(a1) * radius)
		# curved surface (outward facing)
		_tri(st, Vector3(-hx, p0.y, p0.x), Vector3(hx, p0.y, p0.x), Vector3(hx, p1.y, p1.x))
		_tri(st, Vector3(-hx, p0.y, p0.x), Vector3(hx, p1.y, p1.x), Vector3(-hx, p1.y, p1.x))
		# end caps
		_tri(st, Vector3(-hx, 0, cz), Vector3(-hx, p1.y, p1.x), Vector3(-hx, p0.y, p0.x))
		_tri(st, Vector3(hx, 0, cz), Vector3(hx, p0.y, p0.x), Vector3(hx, p1.y, p1.x))
	# flat underside
	_tri(st, Vector3(-hx, 0, 0.0), Vector3(hx, 0, 0.0), Vector3(hx, 0, 0.8))
	_tri(st, Vector3(-hx, 0, 0.0), Vector3(hx, 0, 0.8), Vector3(-hx, 0, 0.8))
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _door_frame() -> void:
	_door = Node3D.new()
	_door.position = DOOR_POS
	_door.visible = false
	add_child(_door)
	var stone := Color(0.55, 0.5, 0.45)
	_mesh(_box(Vector3(0.5, 4.2, 0.5)), stone, Vector3(-1.5, 2.1, 0), _door)
	_mesh(_box(Vector3(0.5, 4.2, 0.5)), stone, Vector3(1.5, 2.1, 0), _door)
	_mesh(_box(Vector3(3.5, 0.5, 0.5)), stone, Vector3(0, 4.35, 0), _door)
	var glow := QuadMesh.new()
	glow.size = Vector2(2.5, 4.1)
	var mi := _mesh(glow, Color(0.4, 0.8, 1.0), Vector3(0, 2.05, 0), _door)
	var mat := mi.material_override as StandardMaterial3D
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
