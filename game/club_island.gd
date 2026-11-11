# Purpose: builds the second island: a neon dance club (dance floor with color-cycling tiles, stage with performers, DJ booth, bar with bartender, tables, crowd), a disco ball and a glowing sign.
# Dependencies: game/party_people.gd (characters and all animation), game/casino_room.gd (the casino annex). Walls, floor and bar have colliders; the rest is visual.
extends RefCounted

const PartyPeople = preload("res://game/party_people.gd")
const CasinoRoom = preload("res://game/casino_room.gd")
const StaffCrew = preload("res://game/staff_crew.gd")

const CENTER := Vector3(1000, 0, 0)
const RADIUS := 26.0
const SPAWN := CENTER + Vector3(0, 0.1, 14)
const CROW_POS := CENTER + Vector3(12, 0, 12)
const WALL_H := 6.0
const MAGENTA := Color(1.0, 0.1, 0.6)
const CYAN := Color(0.1, 0.9, 1.0)

static var _anim: Node3D


# Returns {"spawn": Vector3, "crow": Vector3, "casino": Dictionary (see casino_room.gd)}.
static func build(parent: Node3D) -> Dictionary:
	_anim = PartyPeople.new()
	parent.add_child(_anim)
	_island(parent)
	_building(parent)
	_dance_floor(parent)
	_stage(parent)
	_bar(parent)
	_tables(parent)
	_people()
	return {"spawn": SPAWN, "crow": CROW_POS, "casino": CasinoRoom.build(parent, CENTER)}


static func _at(x: float, y: float, z: float) -> Vector3:
	return CENTER + Vector3(x, y, z)


static func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid: bool = false) -> MeshInstance3D:
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


static func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	parent.add_child(n)


static func _island(parent: Node3D) -> void:
	var water := PlaneMesh.new()
	water.size = Vector2(600, 600)
	var wm := _mat(Color(0.1, 0.45, 0.7))
	wm.roughness = 0.3
	var w := MeshInstance3D.new()
	w.mesh = water
	w.material_override = wm
	w.position = _at(0, -0.4, 0)
	parent.add_child(w)
	var sand := CylinderMesh.new()
	sand.top_radius = RADIUS
	sand.bottom_radius = RADIUS + 1.0
	sand.height = 1.0
	var s := MeshInstance3D.new()
	s.mesh = sand
	s.material_override = _mat(Color(0.88, 0.78, 0.55))
	s.position = _at(0, -0.5, 0)
	parent.add_child(s)
	var body := StaticBody3D.new()
	body.position = _at(0, -0.5, 0)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 1.0
	shape.shape = cyl
	body.add_child(shape)
	parent.add_child(body)


# Walls, roof, neon trim and the sign. Building spans x -10..10, z -14..2; the door gap is 5 m wide in the front wall.
static func _building(parent: Node3D) -> void:
	var wall := _mat(Color(0.14, 0.07, 0.2))
	_box(parent, Vector3(20.4, WALL_H, 0.4), _at(0, WALL_H * 0.5, -14), wall, true)  # back
	_box(parent, Vector3(0.4, WALL_H, 16), _at(-10, WALL_H * 0.5, -6), wall, true)  # left
	_box(parent, Vector3(0.4, WALL_H, 16), _at(10, WALL_H * 0.5, -6), wall, true)  # right
	_box(parent, Vector3(7.5, WALL_H, 0.4), _at(-6.25, WALL_H * 0.5, 2), wall, true)  # front, left of door
	_box(parent, Vector3(7.5, WALL_H, 0.4), _at(6.25, WALL_H * 0.5, 2), wall, true)  # front, right of door
	_box(parent, Vector3(5, 1.5, 0.4), _at(0, WALL_H - 0.75, 2), wall, true)  # above the door
	_box(parent, Vector3(20.6, 0.3, 16.6), _at(0, WALL_H + 0.15, -6), _mat(Color(0.1, 0.05, 0.14)))  # roof
	_box(parent, Vector3(20, 0.1, 16), _at(0, 0.05, -6), _mat(Color(0.08, 0.06, 0.1)))  # floor
	var pink := _mat(MAGENTA, true)
	var blue := _mat(CYAN, true)
	_box(parent, Vector3(20.6, 0.15, 0.15), _at(0, WALL_H, 2.1), pink)  # trim along the front
	_box(parent, Vector3(0.15, WALL_H, 0.15), _at(-2.55, WALL_H * 0.5, 2.1), blue)  # door frame
	_box(parent, Vector3(0.15, WALL_H, 0.15), _at(2.55, WALL_H * 0.5, 2.1), blue)
	_box(parent, Vector3(0.15, 0.15, 16.6), _at(-10.2, WALL_H, -6), blue)  # trim along the sides
	_box(parent, Vector3(0.15, 0.15, 16.6), _at(10.2, WALL_H, -6), blue)
	var sign_label := Label3D.new()
	sign_label.text = "NEON CLUB"
	sign_label.font_size = 128
	sign_label.pixel_size = 0.012
	sign_label.outline_size = 24
	sign_label.outline_modulate = Color(0.4, 0.0, 0.25)
	sign_label.modulate = MAGENTA
	sign_label.shaded = false
	sign_label.double_sided = false
	sign_label.position = _at(0, WALL_H + 2.0, 2.3)
	parent.add_child(sign_label)
	_anim.sign_label = sign_label


static func _dance_floor(parent: Node3D) -> void:
	for ix in 5:
		for iz in 5:
			var m := _mat(PartyPeople.TILE_COLORS[(ix + iz * 2) % PartyPeople.TILE_COLORS.size()], true)
			_box(parent, Vector3(1.6, 0.04, 1.6), _at(-3.2 + ix * 1.6, 0.12, -7.2 + iz * 1.6), m)
			_anim.tiles.append(m)
	var ball := Node3D.new()
	ball.position = _at(0, 5.0, -4.4)
	parent.add_child(ball)
	var mesh := SphereMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.2
	mesh.radial_segments = 8
	mesh.rings = 5
	var bm := _mat(Color(0.85, 0.88, 0.95))
	bm.metallic = 0.9
	bm.roughness = 0.2
	var b := MeshInstance3D.new()
	b.mesh = mesh
	b.material_override = bm
	ball.add_child(b)
	_box(ball, Vector3(0.05, 1.2, 0.05), Vector3(0, 1.0, 0), _mat(Color(0.3, 0.3, 0.3)))  # cable
	_anim.ball = ball


static func _stage(parent: Node3D) -> void:
	_box(parent, Vector3(10, 0.6, 4), _at(0, 0.3, -12), _mat(Color(0.2, 0.1, 0.28)), true)
	_box(parent, Vector3(10.1, 0.08, 0.1), _at(0, 0.62, -10), _mat(MAGENTA, true))  # front edge light
	_box(parent, Vector3(9.6, 4.4, 0.1), _at(0, 3.0, -13.8), _mat(Color(0.35, 0.1, 0.55), true))  # backdrop screen
	_box(parent, Vector3(2.6, 1.0, 1.0), _at(6.2, 0.5, -12.6), _mat(Color(0.12, 0.12, 0.15)), true)  # DJ table
	_box(parent, Vector3(1.8, 0.1, 0.6), _at(6.2, 1.05, -12.5), _mat(CYAN, true))  # mixer glow


static func _bar(parent: Node3D) -> void:
	_box(parent, Vector3(1.2, 1.1, 8), _at(-7.6, 0.55, -6), _mat(Color(0.3, 0.16, 0.08)), true)
	_box(parent, Vector3(1.3, 0.08, 8.1), _at(-7.6, 1.12, -6), _mat(Color(0.65, 0.4, 0.2)))
	_box(parent, Vector3(0.1, 0.1, 8), _at(-6.95, 0.5, -6), _mat(CYAN, true))  # under-bar glow
	_box(parent, Vector3(0.5, 0.1, 7.5), _at(-9.7, 1.6, -6), _mat(Color(0.3, 0.16, 0.08)))  # bottle shelf
	for i in 8:
		var color: Color = PartyPeople.TILE_COLORS[i % PartyPeople.TILE_COLORS.size()]
		_cyl(parent, 0.07, 0.35, _at(-9.7, 1.82, -9.2 + i * 0.9), _mat(color.darkened(0.2)))
	for i in 4:
		_cyl(parent, 0.22, 0.7, _at(-6.4, 0.35, -8.0 + i * 1.8), _mat(Color(0.8, 0.1, 0.3)))  # stools


static func _tables(parent: Node3D) -> void:
	for i in 3:
		var z := -4.5 - i * 3.0
		_cyl(parent, 0.7, 0.08, _at(7.5, 0.95, z), _mat(Color(0.25, 0.2, 0.3)))
		_cyl(parent, 0.08, 0.95, _at(7.5, 0.47, z), _mat(Color(0.2, 0.2, 0.22)))
		_cyl(parent, 0.04, 0.05, _at(7.5, 1.02, z), _mat(MAGENTA, true))  # candle glow


static func _add(parent_node: Node3D, role: String, pos: Vector3, yaw_deg: float, phase: float, shirt: Color, pants: Color, skin: Color, hair: Color, skirt: bool = false) -> void:
	var p := PartyPeople.build(shirt, pants, skin, hair, skirt)
	p.position = pos
	p.rotation_degrees.y = yaw_deg
	parent_node.add_child(p)
	_anim.add_person(p, role, phase)


static func _people() -> void:
	var skins := [Color(0.95, 0.78, 0.65), Color(0.78, 0.55, 0.4), Color(0.55, 0.37, 0.26), Color(0.9, 0.7, 0.55)]
	var hairs := [Color(0.1, 0.07, 0.05), Color(0.6, 0.3, 0.1), Color(0.9, 0.8, 0.4), Color(0.9, 0.2, 0.5), Color(0.2, 0.7, 0.9)]
	var shirts := PartyPeople.TILE_COLORS
	# crowd on the dance floor
	for i in 12:
		var x := -3.0 + (i % 4) * 2.0 + (0.4 if i % 2 == 0 else -0.3)
		var z := -6.8 + floorf(i / 4.0) * 2.0
		_add(_anim, "dancer", _at(x, 0.14, z), randf_range(-30.0, 30.0) + 180.0 * 0.0, randf() * 6.0, shirts[i % shirts.size()], Color(0.15, 0.15, 0.3), skins[i % skins.size()], hairs[(i * 3) % hairs.size()], i % 3 == 0)
	# performers on the stage, facing the crowd (+z)
	for i in 4:
		_add(_anim, "performer", _at(-3.6 + i * 2.4, 0.6, -11.4), 180.0, i * 1.3, shirts[(i + 1) % shirts.size()], Color(0.1, 0.1, 0.2), skins[i % skins.size()], hairs[(i + 2) % hairs.size()], i % 2 == 0)
	# DJ behind the table
	_add(_anim, "dj", _at(6.2, 0.0, -13.4), 180.0, 0.0, Color(0.1, 0.1, 0.12), Color(0.1, 0.1, 0.12), skins[1], hairs[0])
	# bartender behind the bar: a bunny-girl staff member (same original uniform as the casino staff)
	var crew: StaffCrew = StaffCrew.new()
	_anim.add_child(crew)
	crew.add("idle", StaffCrew.look("casino_cyan", "twin_buns", "#7a4a2a", "gentle_smile", 3), _at(-8.9, 0.0, -6.0), -90.0)
	# patrons on stools
	_add(_anim, "sitter", _at(-6.4, -0.2, -8.0), 90.0, 0.0, Color(0.9, 0.3, 0.2), Color(0.2, 0.2, 0.3), skins[0], hairs[1])
	_add(_anim, "sitter", _at(-6.4, -0.2, -4.4), 90.0, 2.0, Color(0.2, 0.5, 0.9), Color(0.2, 0.2, 0.3), skins[3], hairs[2])
