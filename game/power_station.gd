# Purpose: the islands' power as things in the world: the parts of the switch lying about (each under a thin beam so
# it is found) and the workbench where the switch is built and thrown, with a lamp that shows red or green.
# Draws only; core/power_state.gd decides and the session asks.
# Dependencies: game/surface_library.gd. `setup(places)` with world positions; `show_state(found, on)` after changes.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")

const BEAM := Color(0.5, 0.9, 1.0, 0.3)

var _parts: Array[Node3D] = []
var _lamp: StandardMaterial3D
var _lever: MeshInstance3D


# part_spots = world positions of the parts, bench = world position of the workbench, yaw = the way it faces.
func setup(part_spots: Array[Vector3], bench: Vector3, yaw: float) -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.3, 0.31, 0.34)
	iron.metallic = 0.6
	iron.roughness = 0.5
	var light := StandardMaterial3D.new()
	light.albedo_color = BEAM
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	light.cull_mode = BaseMaterial3D.CULL_DISABLED
	var column := CylinderMesh.new()
	column.top_radius = 0.04
	column.bottom_radius = 0.09
	column.height = 6.0
	column.radial_segments = 8
	column.rings = 1
	for i in part_spots.size():
		var part := Node3D.new()
		part.position = part_spots[i]
		add_child(part)
		_parts.append(part)
		var shape := BoxMesh.new()
		shape.size = [Vector3(0.12, 0.12, 0.7), Vector3(0.22, 0.22, 0.34), Vector3(0.5, 0.16, 0.5)][i % 3]  # a lever, a fuse, a coil
		var piece := MeshInstance3D.new()
		piece.mesh = shape
		piece.material_override = iron
		piece.position = Vector3(0, 0.25, 0)
		piece.rotation = Vector3(0.3, float(i) * 1.1, 0.2)
		part.add_child(piece)
		var beam := MeshInstance3D.new()
		beam.mesh = column
		beam.material_override = light
		beam.position = Vector3(0, 3.2, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.add_child(beam)
	var wood := SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
	var stand := StaticBody3D.new()
	stand.position = bench
	stand.rotation.y = yaw
	add_child(stand)
	_box(stand, Vector3(1.6, 0.9, 0.7), Vector3(0, 0.45, 0), wood, true)  # the bench
	_box(stand, Vector3(0.7, 0.9, 0.18), Vector3(0, 1.45, -0.2), iron, false)  # the switch box on its back board
	_lamp = StandardMaterial3D.new()
	_lamp.emission_enabled = true
	_lamp.emission_energy_multiplier = 1.5
	var bulb := SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	var lamp := MeshInstance3D.new()
	lamp.mesh = bulb
	lamp.material_override = _lamp
	lamp.position = Vector3(0, 2.0, -0.2)
	stand.add_child(lamp)
	var handle := BoxMesh.new()
	handle.size = Vector3(0.07, 0.42, 0.07)
	_lever = MeshInstance3D.new()
	_lever.mesh = handle
	_lever.material_override = iron
	_lever.position = Vector3(0.18, 1.45, -0.05)
	stand.add_child(_lever)


# What the party has found (true = picked up, so it no longer lies there) and whether the power is on.
func show_state(found: Array[bool], on: bool) -> void:
	for i in _parts.size():
		_parts[i].visible = not found[i]
	_lamp.albedo_color = Color(0.2, 0.9, 0.3) if on else Color(0.9, 0.15, 0.1)
	_lamp.emission = _lamp.albedo_color
	_lever.visible = on or not found.has(false)  # the lever is on the box once every part is there
	_lever.rotation.x = -0.7 if on else 0.7


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)
	if solid:
		var box := BoxShape3D.new()
		box.size = size
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = at
		parent.add_child(shape)
