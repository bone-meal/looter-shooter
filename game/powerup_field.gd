# Purpose: the islands' power-ups lying in the world: a slowly turning, glowing shape under a thin beam of its colour.
# It blinks before it goes. A fixed pool of pickups (no nodes made or freed while playing). On the machine that
# decides (`deciding`: alone or hosting) it also notices who walks into one and when one's time is up; the other
# machines only show what the host tells them.
# Dependencies: none (rules and effects live in core/powerup_rules.gd and game/game_session.gd). Data:
# data/powerups.json, given to setup(). Shapes are built here from boxes, balls and cylinders, merged per material.
extends Node3D

signal touched(id: int, kind: String)  # deciding machine only: a player walked into it (it is already gone here)
signal expired(id: int)  # deciding machine only: nobody took it in time

const SIZE := 8  # pickups that can lie around at once (the oldest gives way)
const HOVER := 1.0  # metres above where the enemy fell
const SHAPE_SCALE := 1.6  # the shapes below are modelled about 0.45 m across; this is how big they hang there
const DARK := Color(0.12, 0.12, 0.14)
const CHECK_EVERY := 0.1  # seconds between two looks at who stands where

var bodies := Callable()  # func() -> Array of the players' bodies that can take one
var deciding := true

var _cfg: Dictionary
var _holders: Array[Node3D] = []
var _shapes: Array[MeshInstance3D] = []
var _beams: Array[MeshInstance3D] = []
var _ids := PackedInt32Array()  # 0 = free
var _kinds: Array[String] = []
var _ages := PackedFloat32Array()
var _meshes := {}  # kind -> ArrayMesh
var _lights := {}  # kind -> beam material
var _check := 0.0


func setup(config: Dictionary) -> void:
	_cfg = config
	var column := CylinderMesh.new()
	column.top_radius = 0.04
	column.bottom_radius = 0.1
	column.height = 7.0
	column.radial_segments = 8
	column.rings = 1
	for kind: String in config["kinds"]:
		var color := Color(String(config["kinds"][kind]["color"]))
		_meshes[kind] = _build(String(config["kinds"][kind]["shape"]), color)
		var light := StandardMaterial3D.new()
		light.albedo_color = Color(color.r, color.g, color.b, 0.3)
		light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		light.cull_mode = BaseMaterial3D.CULL_DISABLED
		_lights[kind] = light
	for _n in SIZE:
		var holder := Node3D.new()
		holder.visible = false
		var shape := MeshInstance3D.new()
		shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shape.scale = Vector3.ONE * SHAPE_SCALE
		holder.add_child(shape)
		var beam := MeshInstance3D.new()
		beam.mesh = column
		beam.position = Vector3(0, 3.6, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(beam)
		add_child(holder)
		_holders.append(holder)
		_shapes.append(shape)
		_beams.append(beam)
		_ids.append(0)
		_kinds.append("")
		_ages.append(0.0)


# A power-up appears where an enemy fell (`at` = the ground there).
func drop(id: int, kind: String, at: Vector3) -> void:
	if not _meshes.has(kind) or id <= 0:
		return
	var slot := _ids.find(0)
	if slot < 0:  # all in use: the one that has lain longest gives way
		slot = 0
		for i in SIZE:
			if _ages[i] > _ages[slot]:
				slot = i
	_ids[slot] = id
	_kinds[slot] = kind
	_ages[slot] = 0.0
	_shapes[slot].mesh = _meshes[kind]
	_beams[slot].material_override = _lights[kind]
	_holders[slot].position = at + Vector3(0, HOVER, 0)
	_holders[slot].visible = true


func remove(id: int) -> void:
	var slot := _ids.find(id)
	if slot >= 0 and id > 0:
		_free(slot)


func clear() -> void:
	for slot in SIZE:
		_free(slot)


func count() -> int:
	return SIZE - _ids.count(0)


# Where the pickup with this id lies (ZERO when there is none): tools only.
func spot_of(id: int) -> Vector3:
	var slot := _ids.find(id)
	return _holders[slot].position if (slot >= 0 and id > 0) else Vector3.ZERO


func _free(slot: int) -> void:
	_ids[slot] = 0
	_holders[slot].visible = false


func _process(delta: float) -> void:
	if _cfg.is_empty() or _ids.count(0) == SIZE:
		return
	var lasts := float(_cfg["seconds_on_ground"])
	var blink := float(_cfg["blink_seconds"])
	for slot in SIZE:
		if _ids[slot] == 0:
			continue
		_ages[slot] += delta
		var age := _ages[slot]
		_shapes[slot].rotation.y = age * 1.8
		_shapes[slot].position.y = 0.08 * sin(age * 2.6)
		var left := lasts - age
		_holders[slot].visible = left > blink or fmod(age * (3.0 if left > blink * 0.4 else 7.0), 1.0) < 0.6
		if deciding and left <= 0.0:
			var gone := _ids[slot]
			_free(slot)
			expired.emit(gone)
	if not deciding or not bodies.is_valid():
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_EVERY
	var reach := float(_cfg["reach"])
	var here: Array = bodies.call()
	for slot in SIZE:
		if _ids[slot] == 0:
			continue
		var at := _holders[slot].position
		for body: Node3D in here:
			var feet := body.global_position
			if Vector2(feet.x - at.x, feet.z - at.z).length() <= reach and absf(feet.y + HOVER - at.y) < 2.2:
				var id := _ids[slot]
				var kind := _kinds[slot]
				_free(slot)
				touched.emit(id, kind)
				break


# --- shapes: a few boxes, balls and cylinders merged into one mesh of two surfaces (the colour that glows, dark trim) ---

func _build(shape: String, color: Color) -> ArrayMesh:
	var main := SurfaceTool.new()
	var trim := SurfaceTool.new()
	main.begin(Mesh.PRIMITIVE_TRIANGLES)
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	match shape:
		"ammo_tin":  # a tin of rounds with a carrying handle
			_box(main, Vector3(0.44, 0.26, 0.24), Vector3(0, 0, 0))
			_box(trim, Vector3(0.46, 0.05, 0.26), Vector3(0, 0.15, 0))
			_box(trim, Vector3(0.2, 0.03, 0.03), Vector3(0, 0.24, 0))
			_box(trim, Vector3(0.03, 0.07, 0.03), Vector3(-0.1, 0.2, 0))
			_box(trim, Vector3(0.03, 0.07, 0.03), Vector3(0.1, 0.2, 0))
			_box(trim, Vector3(0.05, 0.09, 0.02), Vector3(-0.12, 0.08, 0.125))
			_box(trim, Vector3(0.05, 0.09, 0.02), Vector3(0.12, 0.08, 0.125))
		"skull":
			_ball(main, 0.2, Vector3(0, 0.06, 0))
			_box(main, Vector3(0.2, 0.13, 0.2), Vector3(0, -0.12, 0.04))
			_ball(trim, 0.062, Vector3(-0.08, 0.05, 0.16))
			_ball(trim, 0.062, Vector3(0.08, 0.05, 0.16))
			_box(trim, Vector3(0.035, 0.05, 0.03), Vector3(0, -0.04, 0.19))
			for n in 3:
				_box(trim, Vector3(0.012, 0.07, 0.02), Vector3(-0.05 + 0.05 * float(n), -0.15, 0.135))
		"coins":  # two coins on edge
			_disc(main, 0.2, 0.05, Vector3(-0.09, 0, -0.03))
			_disc(main, 0.2, 0.05, Vector3(0.1, 0.03, 0.04))
			_disc(trim, 0.12, 0.056, Vector3(-0.09, 0, -0.03))
			_disc(trim, 0.12, 0.056, Vector3(0.1, 0.03, 0.04))
		_:  # "sea_mine": an iron ball with a painted band and horns
			_ball(trim, 0.2, Vector3.ZERO)
			_rod(main, 0.205, 0.06, Transform3D(Basis.IDENTITY, Vector3.ZERO))
			for n in 6:
				var turn := Basis(Vector3.UP, TAU * float(n) / 6.0)
				_rod(main, 0.028, 0.12, Transform3D(turn * Basis(Vector3.RIGHT, PI * 0.5 - 0.6), turn * Vector3(0, 0.14, 0.17)))
				_rod(main, 0.028, 0.12, Transform3D(turn * Basis(Vector3.RIGHT, PI * 0.5 + 0.6), turn * Vector3(0, -0.14, 0.17)))
			_rod(main, 0.028, 0.12, Transform3D(Basis.IDENTITY, Vector3(0, 0.24, 0)))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.roughness = 0.5
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = DARK
	dark.roughness = 0.8
	var mesh := ArrayMesh.new()
	main.commit(mesh)
	trim.commit(mesh)
	mesh.surface_set_material(0, glow)
	mesh.surface_set_material(1, dark)
	return mesh


func _box(tool: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	tool.append_from(mesh, 0, Transform3D(Basis.IDENTITY, at))


func _ball(tool: SurfaceTool, radius: float, at: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	tool.append_from(mesh, 0, Transform3D(Basis.IDENTITY, at))


# An upright cylinder moved by `place`.
func _rod(tool: SurfaceTool, radius: float, height: float, place: Transform3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	tool.append_from(mesh, 0, place)


# A coin standing on its edge, its faces toward +Z and -Z.
func _disc(tool: SurfaceTool, radius: float, thick: float, at: Vector3) -> void:
	_rod(tool, radius, thick, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at))
