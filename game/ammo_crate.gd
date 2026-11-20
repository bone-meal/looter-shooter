# Purpose: (polish1 D4b, hold-out huts) the AMMO CRATE inside every hut: a green military crate with its lid propped
# open, rows of brass rounds and a stencilled "AMMO" plate. game/game_session.gd sells a refill of every gun's spare
# ammo here (price from data/archipelago.json shelters "ammo"); pop() bounces the lid when it is used. Solid (a box).
# Dependencies: none.
extends Node3D

var price := 1500
var _lid: Node3D


func _ready() -> void:
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.22, 0.3, 0.17)
	green.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.15, 0.1)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.85, 0.65, 0.25)
	brass.metallic = 0.6
	brass.roughness = 0.35
	_box(Vector3(1.1, 0.55, 0.65), Vector3(0, 0.275, 0), green)
	for x: float in [-0.5, 0.5]:  # corner rails
		_box(Vector3(0.06, 0.58, 0.68), Vector3(x, 0.29, 0), dark)
	_box(Vector3(1.02, 0.04, 0.57), Vector3(0, 0.5, 0), dark)  # the inside, dark
	var round_mesh := CylinderMesh.new()
	round_mesh.top_radius = 0.012
	round_mesh.bottom_radius = 0.018
	round_mesh.height = 0.12
	round_mesh.radial_segments = 6
	round_mesh.rings = 1
	round_mesh.material = brass
	var rounds := MultiMesh.new()
	rounds.transform_format = MultiMesh.TRANSFORM_3D
	rounds.mesh = round_mesh
	rounds.instance_count = 60
	for i in 60:
		rounds.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(-0.45 + float(i % 15) * 0.064, 0.58, -0.2 + floorf(float(i) / 15.0) * 0.13)))
	var rn := MultiMeshInstance3D.new()
	rn.multimesh = rounds
	add_child(rn)
	_lid = Node3D.new()  # hinged at the back edge, propped open
	_lid.position = Vector3(0, 0.55, -0.33)
	_lid.rotation.x = -1.9
	add_child(_lid)
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.1, 0.05, 0.66)
	lid.mesh = lm
	lid.material_override = green
	lid.position = Vector3(0, 0.0, 0.33)
	_lid.add_child(lid)
	var plate := Label3D.new()
	plate.text = "AMMO"
	plate.font_size = 64
	plate.pixel_size = 0.004
	plate.modulate = Color(0.95, 0.9, 0.6)
	plate.outline_size = 0
	plate.position = Vector3(0, 0.3, 0.33)
	add_child(plate)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 0.6, 0.66)
	shape.shape = box
	shape.position = Vector3(0, 0.3, 0)
	body.add_child(shape)
	add_child(body)


func _box(size: Vector3, at: Vector3, m: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	var n := MeshInstance3D.new()
	n.mesh = b
	n.material_override = m
	n.position = at
	add_child(n)


func pop() -> void:
	var t := create_tween()
	t.tween_property(_lid, "rotation:x", -1.4, 0.12)
	t.tween_property(_lid, "rotation:x", -1.9, 0.3).set_trans(Tween.TRANS_BOUNCE)
