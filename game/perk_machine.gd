# Purpose: a perk machine: the perk's own model (polish1 item 37: tools/blender/perk_machines.py, a lighthouse, a bomb,
# an hourglass ... so each reads from afar by size, shape and colour) or, without one, a painted cabinet; the perk's name
# and price on it; its glowing parts in the perk's colour light up once the power is on (a windmill turns).
# Draws only; the session sells the perk to whoever presses interact at it.
# Dependencies: game/fantasy_models.gd (the models). Set `perk_id`, `title`, `price` and `tint` before add_child;
# `set_powered` when the power changes.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")

const BODY := Vector3(0.95, 1.95, 0.7)
const DARK := Color(0.16, 0.15, 0.17)

var perk_id := ""  # its model is assets/models/fantasy/perk_<id>.gltf when there is one
var title := ""
var price := 0
var tint := Color.WHITE

var _panel: StandardMaterial3D
var _tag: Label3D
var _spin: Node3D = null
var _on := false


func _ready() -> void:
	_panel = StandardMaterial3D.new()
	_panel.albedo_color = tint
	_panel.roughness = 0.4
	_panel.emission = tint
	_tag = Label3D.new()
	_tag.text = "%s\n%d" % [title, price]
	_tag.font_size = 40
	_tag.pixel_size = 0.0036
	_tag.outline_size = 6
	if perk_id != "" and FantasyModels.has_model("perk_" + perk_id):
		_modelled()
	else:
		_cabinet()
	set_powered(false)


func _modelled() -> void:
	var made := FantasyModels.scene("perk_" + perk_id)
	add_child(made)
	for found in made.find_children("*", "MeshInstance3D", true, false):
		if String(found.name).begins_with("Glow") or String(found.get_parent().name).begins_with("Glow"):
			(found as MeshInstance3D).material_override = _panel
	_spin = made.find_child("Spin", true, false) as Node3D
	var mark := made.find_child("Tag", true, false) as Node3D
	_tag.position = (mark.position if mark != null else Vector3(0.0, 1.2, 0.5)) + Vector3(0.0, 0.0, 0.03)
	add_child(_tag)
	var box := FantasyModels.bounds(made)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = Vector3(box.size.x * 0.85, box.size.y, box.size.z * 0.85)
	shape.shape = solid
	shape.position = box.get_center()
	body.add_child(shape)
	add_child(body)


func _process(delta: float) -> void:
	if _spin != null and _on:
		_spin.rotate_object_local(Vector3.BACK, delta * 2.2)


func _cabinet() -> void:
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
	var mesh := ArrayMesh.new()
	tools[0].commit(mesh)
	tools[1].commit(mesh)
	mesh.surface_set_material(0, shell)
	mesh.surface_set_material(1, _panel)
	var cabinet_node := MeshInstance3D.new()
	cabinet_node.mesh = mesh
	add_child(cabinet_node)
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


func set_powered(on: bool) -> void:
	_on = on
	_panel.emission_enabled = on
	_panel.emission_energy_multiplier = 0.9
	_panel.albedo_color = tint if on else tint.darkened(0.6)
	_tag.modulate = Color.WHITE if on else Color(0.55, 0.55, 0.55)
