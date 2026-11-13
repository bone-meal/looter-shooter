# Purpose: the islands' buildables as things in the world: every part lying where it is to be found (under a thin
# warm beam, so it is told from the power switch's cold ones) and each thing's bench. The shield's bench is a
# workbench with the finished shield leaning on it; the boat's is a slipway of two rails into the sea.
# Draws only; core/build_state.gd decides and the session asks.
# Dependencies: game/surface_library.gd, game/shield_model.gd. `setup(sites)`, then `show_state(thing, found, built)`.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")
const ShieldModel = preload("res://game/shield_model.gd")

const BEAM := Color(1.0, 0.8, 0.35, 0.3)
# What a lying part looks like: the size of its box, per thing id and part number (anything else = a small crate).
const SHAPES := {
	"shield": [Vector3(0.62, 0.05, 0.96), Vector3(0.42, 0.14, 0.42), Vector3(0.66, 0.05, 0.16)],
	"boat": [Vector3(1.7, 0.16, 0.5), Vector3(0.08, 0.08, 1.2), Vector3(0.3, 0.32, 0.3), Vector3(0.8, 0.22, 0.4)],
}

var _parts: Array = []  # per thing: Array of Node3D, one per part
var _done: Array = []  # per thing: the node shown once it is built (null = nothing to show at the bench)


# sites = one per thing, in the data's order: {"id", "parts": Array[Vector3] (world), "bench": Vector3, "yaw": float}.
func setup(sites: Array) -> void:
	var wood := SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
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
	for site: Dictionary in sites:
		var id := String(site["id"])
		var lying: Array = []
		var spots: Array = site["parts"]
		for i in spots.size():
			var part := Node3D.new()
			part.position = spots[i]
			add_child(part)
			lying.append(part)
			var sizes: Array = SHAPES.get(id, [])
			var size: Vector3 = sizes[i] if i < sizes.size() else Vector3(0.4, 0.3, 0.4)
			_box(part, size, Vector3(0.0, size.y * 0.5 + 0.03, 0.0), wood, false).rotation.y = float(i) * 1.3 + 0.4
			var beam := MeshInstance3D.new()
			beam.mesh = column
			beam.material_override = light
			beam.position = Vector3(0, 3.2, 0)
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			part.add_child(beam)
		_parts.append(lying)
		var stand := StaticBody3D.new()
		stand.position = site["bench"]
		stand.rotation.y = float(site["yaw"])
		add_child(stand)
		var shown: Node3D = null
		if id == "boat":  # a slipway: two rails running out toward the sea (a bench's -Z looks away from the island's middle)
			for side: float in [-0.8, 0.8]:
				_box(stand, Vector3(0.16, 0.16, 7.0), Vector3(side, -0.1, -3.0), wood, false).rotation.x = -0.1
			_box(stand, Vector3(0.22, 1.1, 0.22), Vector3(-1.2, 0.55, 0.0), wood, true)  # the post the prompt belongs to
		else:
			_box(stand, Vector3(1.6, 0.9, 0.7), Vector3(0, 0.45, 0), wood, true)
			if id == "shield":
				shown = ShieldModel.build()
				shown.position = Vector3(0.0, 0.52, 0.44)  # leaning on the bench's front, its face outward
				shown.rotation = Vector3(0.3, PI, 0.0)
				stand.add_child(shown)
		_done.append(shown)


# What the party has found of a thing (true = picked up, so it no longer lies there) and whether it is built.
func show_state(thing: int, found: Array[bool], built: bool) -> void:
	var lying: Array = _parts[thing]
	for i in lying.size():
		(lying[i] as Node3D).visible = not found[i]
	if _done[thing] != null:
		(_done[thing] as Node3D).visible = built


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material, solid: bool) -> MeshInstance3D:
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
	return part
