# Purpose: a perk machine: a painted cabinet with the perk's name and price that lights up once the power is on.
# Draws only; the session sells the perk to whoever presses interact at it.
# Dependencies: none. Set `title`, `price` and `tint` before add_child; `set_powered` when the power changes.
extends Node3D

const BODY := Vector3(0.95, 1.95, 0.7)
const DARK := Color(0.16, 0.15, 0.17)

var title := ""
var price := 0
var tint := Color.WHITE

var _panel: StandardMaterial3D
var _tag: Label3D


func _ready() -> void:
	var tools: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new()]
	for tool in tools:
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cabinet := BoxMesh.new()
	cabinet.size = BODY
	tools[0].append_from(cabinet, 0, Transform3D(Basis(), Vector3(0, BODY.y * 0.5, 0)))
	var cap := BoxMesh.new()
	cap.size = Vector3(BODY.x + 0.12, 0.14, BODY.z + 0.12)
	tools[0].append_from(cap, 0, Transform3D(Basis(), Vector3(0, BODY.y + 0.07, 0)))
	var front := BoxMesh.new()
	front.size = Vector3(BODY.x - 0.16, 1.05, 0.04)
	tools[1].append_from(front, 0, Transform3D(Basis(), Vector3(0, 1.22, BODY.z * 0.5 + 0.02)))
	var slot := BoxMesh.new()
	slot.size = Vector3(0.42, 0.26, 0.05)
	tools[0].append_from(slot, 0, Transform3D(Basis(), Vector3(0, 0.4, BODY.z * 0.5 + 0.02)))
	var shell := StandardMaterial3D.new()
	shell.albedo_color = DARK.lerp(tint, 0.25)
	shell.roughness = 0.6
	shell.metallic = 0.3
	_panel = StandardMaterial3D.new()
	_panel.albedo_color = tint
	_panel.roughness = 0.4
	_panel.emission = tint
	var mesh := ArrayMesh.new()
	tools[0].commit(mesh)
	tools[1].commit(mesh)
	mesh.surface_set_material(0, shell)
	mesh.surface_set_material(1, _panel)
	var cabinet_node := MeshInstance3D.new()
	cabinet_node.mesh = mesh
	add_child(cabinet_node)
	_tag = Label3D.new()
	_tag.text = "%s\n%d" % [title, price]
	_tag.font_size = 40
	_tag.pixel_size = 0.0036
	_tag.outline_size = 6
	_tag.position = Vector3(0, 1.22, BODY.z * 0.5 + 0.05)
	add_child(_tag)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY
	shape.shape = box
	shape.position = Vector3(0, BODY.y * 0.5, 0)
	body.add_child(shape)
	add_child(body)
	set_powered(false)


func set_powered(on: bool) -> void:
	_panel.emission_enabled = on
	_panel.emission_energy_multiplier = 0.9
	_panel.albedo_color = tint if on else tint.darkened(0.6)
	_tag.modulate = Color.WHITE if on else Color(0.55, 0.55, 0.55)
