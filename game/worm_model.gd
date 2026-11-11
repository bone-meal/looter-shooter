# Purpose: builds and wriggles the placeholder Pink Earthworm 3D model (a chain of small spheres). Used for the held worm and the worm over the chest.
# Dependencies: none. build() returns a Node3D whose "material" meta is its StandardMaterial3D (so callers can fade it).
extends RefCounted

const SEGMENTS := 10
const SPACING := 0.055
const RADIUS := 0.038
const PINK := Color(0.95, 0.55, 0.68)


static func build() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PINK
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	root.set_meta("material", mat)
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	for i in SEGMENTS:
		var seg := MeshInstance3D.new()
		seg.mesh = sphere
		seg.material_override = mat
		var s := 1.25 if i == 0 else (1.0 - 0.03 * i)  # slightly fatter head
		seg.scale = Vector3.ONE * s
		root.add_child(seg)
	pose(root, 0.0, 1.0)
	return root


# Lays the segments along a travelling sine wave. `t` is time in seconds, `amount` scales the wiggle (0 = straight).
static func pose(root: Node3D, t: float, amount: float) -> void:
	var half := SEGMENTS * 0.5
	for i in SEGMENTS:
		root.get_child(i).position = Vector3((i - half) * SPACING, sin(t * 7.0 + i * 0.8) * 0.03 * amount, cos(t * 7.0 + i * 0.8) * 0.02 * amount)
