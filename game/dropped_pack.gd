# Purpose: the backpack a player leaves where they went down on the islands: everything they carried (ready guns and
# the whole bag), lying there with a thin beam of light over it so it can be found again. Only its owner sees it.
# Dependencies: none. game/game_session.gd creates it, keeps what is inside (`bundle`, the plain saved data of
# core/inventory_state.gd take_all) and frees it when it is emptied or lost.
extends Node3D

const CLOTH := Color(0.42, 0.3, 0.18)
const STRAP := Color(0.2, 0.14, 0.08)
const BEAM := Color(1.0, 0.82, 0.35, 0.35)
const REACH := 2.6  # metres from which it can be picked up

var bundle := {}  # {"things": [...]}

var _beam: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = CLOTH
	cloth.roughness = 0.9
	var strap := StandardMaterial3D.new()
	strap.albedo_color = STRAP
	_box(Vector3(0.44, 0.5, 0.26), Vector3(0, 0.25, 0), cloth)  # the sack
	_box(Vector3(0.46, 0.16, 0.28), Vector3(0, 0.5, 0.0), strap)  # its flap
	_box(Vector3(0.3, 0.22, 0.1), Vector3(0, 0.2, 0.17), strap)  # front pocket
	_box(Vector3(0.06, 0.46, 0.04), Vector3(-0.13, 0.26, -0.15), strap)  # shoulder straps
	_box(Vector3(0.06, 0.46, 0.04), Vector3(0.13, 0.26, -0.15), strap)
	rotation.z = 0.22  # slumped where it fell
	var light := StandardMaterial3D.new()
	light.albedo_color = BEAM
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	light.cull_mode = BaseMaterial3D.CULL_DISABLED
	var column := CylinderMesh.new()
	column.top_radius = 0.05
	column.bottom_radius = 0.12
	column.height = 9.0
	column.radial_segments = 8
	column.rings = 1
	_beam = MeshInstance3D.new()
	_beam.mesh = column
	_beam.material_override = light
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true  # straight up whatever way the sack leans
	add_child(_beam)


func _process(delta: float) -> void:
	_t += delta
	_beam.global_position = global_position + Vector3(0, 4.8, 0)
	_beam.scale = Vector3(1.0 + 0.25 * sin(_t * 3.0), 1.0, 1.0 + 0.25 * sin(_t * 3.0))


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = material
	add_child(part)
