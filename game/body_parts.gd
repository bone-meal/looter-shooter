# Purpose: tiny helpers that add colored boxes, balls, cylinders and cones to a Node3D; shared by all character builders.
# Dependencies: none.
extends RefCounted

static var _cache := {}


# Shared flat-color material (cached by color; the cache is emptied if it grows too large).
static func mat(color: Color, glow := false) -> StandardMaterial3D:
	var key := color.to_html(false) + ("g" if glow else "")
	if _cache.size() > 300:
		_cache.clear()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		if glow:
			m.emission_enabled = true
			m.emission = color
		_cache[key] = m
	return _cache[key]


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _place(parent, mesh, pos, material, rot_deg)


static func ball(parent: Node3D, radius: float, pos: Vector3, material: Material, squash := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var node := _place(parent, mesh, pos, material, Vector3.ZERO)
	node.scale = squash
	return node


# Cylinder or cone: top radius 0 makes a cone pointing up.
static func cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return _place(parent, mesh, pos, material, rot_deg)


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 12
	mesh.ring_segments = 6
	return _place(parent, mesh, pos, material, rot_deg)


static func pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = pos
	parent.add_child(node)
	return node


static func _place(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material, rot_deg: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	node.rotation_degrees = rot_deg
	parent.add_child(node)
	return node
