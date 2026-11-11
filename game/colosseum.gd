# Purpose: builds the oval Roman colosseum arena: sand floor, podium wall, stepped seating, a column gallery on top,
# four gate portals and the cover pillars. Returns the gate spawn points for game/wave_director.gd.
# Dependencies: game/sweep_mesh.gd, game/surface_library.gd, game/model_library.gd, game/look_props.gd.
# Cheap by design: every ring is one swept mesh (one draw call), copies are MultiMeshes, all collision is one static body.
extends RefCounted

const SweepMesh = preload("res://game/sweep_mesh.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")
const ModelLibrary = preload("res://game/model_library.gd")
const LookProps = preload("res://game/look_props.gd")

const HALF_X := 36.0          # inner wall half-width (x)
const HALF_Z := 26.0          # inner wall half-depth (z)
const SWEEP := 96             # segments around the oval
const WALL_HEIGHT := 5.0
const WALL_THICKNESS := 1.2
const STEPS := 9              # seat rows
const STEP_DEPTH := 1.0
const STEP_RISE := 6.6 / 9.0
const GALLERY_DEPTH := 2.4    # walkway behind the top row, where the columns stand
const COLUMN_COUNT := 64
const COLUMN_HEIGHT := 5.2
const GATE_ANGLES := [0.0, PI * 0.5, PI, PI * 1.5]
const GATE_INSET := 3.0
const GATE_WIDTH := 4.3
const GATE_HEIGHT := 4.2

const SAND := Color(0.85, 0.74, 0.5)
const SAND_DARK := Color(0.75, 0.63, 0.4)
const WALL := Color(0.72, 0.62, 0.48)
const TIER := Color(0.82, 0.74, 0.6)
const COLUMN := Color(0.88, 0.82, 0.7)
const GATE := Color(0.12, 0.1, 0.1)
const PILLAR := Color(0.6, 0.52, 0.4)

const PILLARS := [Vector3(-14, 0, -8), Vector3(14, 0, -8), Vector3(-14, 0, 8), Vector3(14, 0, 8), Vector3(0, 0, -15), Vector3(0, 0, 15)]
const PILLAR_RADIUS := 1.2
const PILLAR_HEIGHT := 3.0


# Builds everything under parent. Returns spawn points just inside each gate.
static func build(parent: Node3D) -> Array[Vector3]:
	var body := StaticBody3D.new()
	parent.add_child(body)
	_floor(parent, body)
	_rings(parent, body)
	_columns(parent)
	_pillars(parent, body)
	_weeds(parent)
	return _gates(parent)


static func _ellipse_point(angle: float, offset: float) -> Vector3:
	return Vector3((HALF_X + offset) * cos(angle), 0.0, (HALF_Z + offset) * sin(angle))


# Rotation about Y that turns local +X along the ellipse tangent.
static func _tangent_yaw(angle: float, offset: float) -> float:
	var tx := -(HALF_X + offset) * sin(angle)
	var tz := (HALF_Z + offset) * cos(angle)
	return atan2(-tz, tx)


static func _top() -> float:
	return WALL_HEIGHT + STEP_RISE * STEPS


static func _place(parent: Node3D, mesh: Mesh, surface: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = surface
	parent.add_child(mi)
	return mi


static func _floor(parent: Node3D, body: StaticBody3D) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)

	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.2
	disc.radial_segments = 64
	disc.rings = 1
	var sand := _place(parent, disc, SurfaceLibrary.material("arena_sand", SAND))
	sand.transform = Transform3D(Basis.from_scale(Vector3(HALF_X + 1.0, 1, HALF_Z + 1.0)), Vector3(0, -0.1, 0))
	var center := _place(parent, disc, SurfaceLibrary.material("arena_center", SAND_DARK))
	center.transform = Transform3D(Basis.from_scale(Vector3(9, 1, 9)), Vector3(0, -0.09, 0))


# Podium wall, seat rows with the gallery walkway, and the outer face. All solid, so shots stop on them.
static func _rings(parent: Node3D, body: StaticBody3D) -> void:
	var wall_tile := _tile("arena_wall")
	var wall := PackedVector2Array([Vector2(-0.2, 0.0), Vector2(-0.2, 0.45), Vector2(0.0, 0.6), Vector2(0.0, WALL_HEIGHT - 0.4),
		Vector2(-0.15, WALL_HEIGHT - 0.4), Vector2(-0.15, WALL_HEIGHT), Vector2(WALL_THICKNESS, WALL_HEIGHT)])
	var seats := PackedVector2Array([Vector2(WALL_THICKNESS, WALL_HEIGHT)])
	for i in STEPS:
		var last := seats[seats.size() - 1]
		seats.append(last + Vector2(0.0, STEP_RISE))
		seats.append(last + Vector2(STEP_DEPTH, STEP_RISE))
	var rim := seats[seats.size() - 1] + Vector2(GALLERY_DEPTH, 0.0)
	seats.append(rim)
	var outer := PackedVector2Array([rim, Vector2(rim.x, 0.0)])
	var parts := [
		[wall, SurfaceLibrary.material("arena_wall", WALL), wall_tile],
		[seats, SurfaceLibrary.material("arena_tier", TIER), _tile("arena_tier")],
		[outer, SurfaceLibrary.material("arena_wall", WALL), wall_tile],
	]
	for part: Array in parts:
		var mesh := SweepMesh.build(part[0], HALF_X, HALF_Z, SWEEP, float(part[2]))
		_place(parent, mesh, part[1])
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)


static func _tile(surface_id: String) -> float:
	return maxf(float(SurfaceLibrary.definition(surface_id).get("tile", 2.0)), 0.01)


static func _gallery_offset() -> float:
	return WALL_THICKNESS + STEP_DEPTH * STEPS + GALLERY_DEPTH * 0.5


# Column ring on the gallery with a stone beam across the tops (visual only).
static func _columns(parent: Node3D) -> void:
	var stone := SurfaceLibrary.material("arena_column", COLUMN)
	var offset := _gallery_offset()
	var top := _top()
	var h := COLUMN_HEIGHT
	var shaft := PackedVector2Array([Vector2(0.0, h), Vector2(0.8, h), Vector2(0.8, h - 0.24), Vector2(0.65, h - 0.4), Vector2(0.52, h - 0.5),
		Vector2(0.6, 0.55), Vector2(0.72, 0.4), Vector2(0.8, 0.4), Vector2(0.8, 0.0)])
	var xforms: Array[Transform3D] = []
	for k in COLUMN_COUNT:
		var pos := _ellipse_point(TAU * float(k) / COLUMN_COUNT, offset)
		pos.y = top
		xforms.append(Transform3D(Basis.IDENTITY, pos))
	_field(parent, SweepMesh.build(shaft, 0.0, 0.0, 14, 1.0), xforms, stone)
	var beam := PackedVector2Array([Vector2(offset - 0.8, top + h), Vector2(offset - 0.8, top + h + 1.0), Vector2(offset + 0.8, top + h + 1.0),
		Vector2(offset + 0.8, top + h), Vector2(offset - 0.8, top + h)])
	_place(parent, SweepMesh.build(beam, HALF_X, HALF_Z, SWEEP, 1.0), stone)


static func _pillars(parent: Node3D, body: StaticBody3D) -> void:
	var h := PILLAR_HEIGHT
	var r := PILLAR_RADIUS
	var drum := PackedVector2Array([Vector2(0.0, h), Vector2(r + 0.14, h), Vector2(r + 0.14, h - 0.22), Vector2(r, h - 0.32),
		Vector2(r, 0.32), Vector2(r + 0.14, 0.22), Vector2(r + 0.14, 0.0)])
	var shape := CylinderShape3D.new()
	shape.radius = PILLAR_RADIUS
	shape.height = PILLAR_HEIGHT
	var xforms: Array[Transform3D] = []
	for p: Vector3 in PILLARS:
		xforms.append(Transform3D(Basis.IDENTITY, p))
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = p + Vector3(0, PILLAR_HEIGHT * 0.5, 0)
		body.add_child(cs)
	_field(parent, SweepMesh.build(drum, 0.0, 0.0, 20, 1.0), xforms, SurfaceLibrary.material("arena_pillar", PILLAR))


# Ferns and rubble along the foot of the wall (textured look only, no collision).
static func _weeds(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var kinds: Array = ModelLibrary.meshes("fern_02").duplicate()
	var rubble := ModelLibrary.mesh("rock_09", "rock_09_LOD0")
	if rubble != null:
		kinds.append(["rubble", rubble])
	for entry: Array in kinds:
		var is_rubble := String(entry[0]) == "rubble"
		var xforms: Array[Transform3D] = []
		for i in 12:
			var angle := rng.randf_range(0.0, TAU)
			var near_gate := false
			for gate: float in GATE_ANGLES:
				if absf(angle_difference(angle, gate)) < 0.14:
					near_gate = true
			if near_gate:
				continue
			var pos := _ellipse_point(angle, -rng.randf_range(0.5, 1.3))
			var big := rng.randf_range(3.0, 7.0) if is_rubble else rng.randf_range(0.8, 1.5)
			var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(big, big, big))
			xforms.append(Transform3D(turn, pos))
		var field := _field(parent, entry[1] as Mesh, xforms, null)
		field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		LookProps.add_scatter(field)


# Gate portals set into the inner wall: stone jambs and lintel around a dark opening, with an iron gate in the
# textured look. Returns the spawn point inside each.
static func _gates(parent: Node3D) -> Array[Vector3]:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var stones: Array[Transform3D] = []
	var darks: Array[Transform3D] = []
	var doors: Array[Transform3D] = []
	var spawns: Array[Vector3] = []
	for a: float in GATE_ANGLES:
		var inward := -Vector3(cos(a), 0.0, sin(a))
		var face := _ellipse_point(a, 0.0)
		var turn := Basis(Vector3.UP, _tangent_yaw(a, 0.0))
		var along := turn.x
		var jamb := Vector3(0.7, GATE_HEIGHT, 1.0)
		for side: float in [-1.0, 1.0]:
			stones.append(Transform3D(turn * Basis.from_scale(jamb), face + along * side * (GATE_WIDTH + jamb.x) * 0.5 + inward * 0.35 + Vector3(0, GATE_HEIGHT * 0.5, 0)))
		stones.append(Transform3D(turn * Basis.from_scale(Vector3(GATE_WIDTH + 2.0, 0.9, 1.1)), face + inward * 0.35 + Vector3(0, GATE_HEIGHT + 0.45, 0)))
		stones.append(Transform3D(turn * Basis.from_scale(Vector3(GATE_WIDTH + 2.5, 0.25, 1.25)), face + inward * 0.35 + Vector3(0, GATE_HEIGHT + 1.02, 0)))
		darks.append(Transform3D(turn * Basis.from_scale(Vector3(GATE_WIDTH, GATE_HEIGHT, 0.5)), face + inward * 0.05 + Vector3(0, GATE_HEIGHT * 0.5, 0)))
		doors.append(Transform3D(turn * Basis.from_scale(Vector3(1.45, 1.45, 1.45)), face + inward * 0.45))
		spawns.append(Vector3((HALF_X - GATE_INSET) * cos(a), 0.1, (HALF_Z - GATE_INSET) * sin(a)))
	_field(parent, unit, stones, SurfaceLibrary.material("arena_portal", WALL))
	_field(parent, unit, darks, SurfaceLibrary.material("arena_gate_recess", GATE))
	for entry: Array in ModelLibrary.meshes("large_iron_gate"):
		LookProps.add(_field(parent, entry[1] as Mesh, doors, null), true)
	return spawns


# One MultiMesh for many copies of a mesh. surface = null keeps the mesh's own materials.
static func _field(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], surface: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = surface
	parent.add_child(inst)
	return inst
