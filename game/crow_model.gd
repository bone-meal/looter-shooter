# Purpose: the giant crow (~4 m tall): the model from assets/models/creatures/crow.gltf (modelled in Blender by
# tools/blender/creatures.py), or the old blocky one built here when that file is missing; plays idle, eat and flap poses.
# Dependencies: none. Pivots: Body, Body/Head, Body/WingL, Body/WingR. Faces -Z. `SADDLE` is where the rider stands (root-local).
extends RefCounted

const MODEL := "res://assets/models/creatures/crow.gltf"
const IDLE := 0
const EAT := 1
const FLAP := 2
const SADDLE := Vector3(0, 3.5, 0.2)


static func build() -> Node3D:
	if ResourceLoader.exists(MODEL):
		return (load(MODEL) as PackedScene).instantiate() as Node3D
	var root := Node3D.new()
	var black := _mat(Color(0.07, 0.07, 0.1), 0.25)
	var sheen := _mat(Color(0.13, 0.14, 0.2), 0.2)
	var beak := _mat(Color(0.95, 0.7, 0.2), 0.6)
	var white := _mat(Color(0.95, 0.95, 0.95), 0.5)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	_ball(body, 1.0, Vector3(0, 2.4, 0), black, Vector3(1.0, 0.9, 1.5))
	_ball(body, 0.7, Vector3(0, 2.2, 0.6), sheen, Vector3(1.0, 0.8, 1.0))
	_box(body, Vector3(0.9, 0.08, 1.8), Vector3(0, 2.2, 2.0), black, 12.0)  # tail
	for sx in [-0.4, 0.4]:
		_box(root, Vector3(0.12, 1.4, 0.12), Vector3(sx, 0.7, 0.1), beak)  # legs
		_box(root, Vector3(0.4, 0.08, 0.55), Vector3(sx, 0.04, -0.08), beak)  # feet
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 3.3, -1.1)
	body.add_child(head)
	_ball(head, 0.6, Vector3.ZERO, black, Vector3.ONE)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.2
	cone.height = 0.95
	cone.radial_segments = 8
	cone.rings = 1
	var tip := MeshInstance3D.new()
	tip.mesh = cone
	tip.material_override = beak
	tip.position = Vector3(0, -0.08, -0.85)
	tip.rotation_degrees.x = -90.0
	head.add_child(tip)
	for sx in [-0.34, 0.34]:
		_ball(head, 0.13, Vector3(sx, 0.12, -0.42), white, Vector3.ONE)
		_ball(head, 0.07, Vector3(sx * 1.1, 0.12, -0.52), _mat(Color.BLACK, 0.5), Vector3.ONE)
	for side in [["WingL", -1.0], ["WingR", 1.0]]:
		var wing := Node3D.new()
		wing.name = side[0]
		wing.position = Vector3(side[1] * 0.95, 2.9, 0.1)
		body.add_child(wing)
		_box(wing, Vector3(2.8, 0.1, 1.5), Vector3(side[1] * 1.4, 0, 0), black)
		_box(wing, Vector3(1.4, 0.08, 1.1), Vector3(side[1] * 3.2, 0, 0.2), sheen)
	return root


# mode: IDLE, EAT (pecking) or FLAP (flying). `t` is time in seconds.
static func pose(root: Node3D, mode: int, t: float) -> void:
	var body: Node3D = root.get_node("Body")
	var head: Node3D = root.get_node("Body/Head")
	var wing_l: Node3D = root.get_node("Body/WingL")
	var wing_r: Node3D = root.get_node("Body/WingR")
	match mode:
		FLAP:
			var flap := sin(t * 7.0) * 0.8
			wing_l.rotation.z = -flap
			wing_r.rotation.z = flap
			body.position.y = absf(sin(t * 7.0)) * 0.15
			head.rotation.x = 0.1
		EAT:
			body.position.y = 0.0
			head.rotation.x = 0.3 + sin(t * 14.0) * 0.5  # quick pecks
			wing_l.rotation.z = 0.15
			wing_r.rotation.z = -0.15
		_:
			body.position.y = sin(t * 1.6) * 0.04
			head.rotation.y = sin(t * 0.7) * 0.5  # looks around
			head.rotation.x = 0.0
			wing_l.rotation.z = 0.2 + sin(t * 1.2) * 0.04
			wing_r.rotation.z = -0.2 - sin(t * 1.2) * 0.04


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


static func _ball(parent: Node3D, radius: float, pos: Vector3, mat: Material, scale: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	n.scale = scale
	parent.add_child(n)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, tilt_x_deg: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	n.rotation_degrees.x = tilt_x_deg
	parent.add_child(n)
