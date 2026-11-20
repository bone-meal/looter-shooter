# Purpose: the "W kills" counter on a gun model: a small dark plate on the left side of the gun with the kill count in
# glowing orange digits, updated live. Hidden on guns without the counter.
# Dependencies: none (the gun dictionary's "wkills", see core/gun_gen.gd).
extends RefCounted

const NODE := "WKills"
const DIGITS := Color(1.0, 0.55, 0.15)


# Shows (or hides) the counter of `gun` on `model`; cheap to call on every kill.
static func show(model: Node3D, gun: Dictionary) -> void:
	var plate := model.get_node_or_null(NODE) as Node3D
	if not gun.has("wkills"):
		if plate != null:
			plate.visible = false
		return
	if plate == null:
		plate = _build(model)
	plate.visible = true
	(plate.get_node("Count") as Label3D).text = "%07d" % int(gun["wkills"])


static func _build(model: Node3D) -> Node3D:
	var box := _bounds(model)
	var plate := Node3D.new()
	plate.name = NODE
	model.add_child(plate)
	var long := box.size.z >= box.size.x  # guns lie along their longer flat axis
	var middle := box.get_center()
	if long:  # on the left side (-X), a little behind the middle, flat on the gun's own side there (polish1 item 61:
		# the whole model's widest point, a scope or a drum, left it floating beside the receiver)
		var spot := Vector3(0.0, middle.y + box.size.y * 0.1, middle.z + box.size.z * 0.08)
		spot.x = _side_x(model, spot.y, spot.z, box.size.y * 0.25, box.size.z * 0.06, box.position.x)
		plate.position = Vector3(spot.x - 0.004, spot.y, spot.z)
		plate.rotation_degrees = Vector3(0, -90, 0)
	else:
		plate.position = Vector3(middle.x - box.size.x * 0.08, middle.y + box.size.y * 0.1, box.position.z + box.size.z - 0.004)
	var span := clampf(maxf(box.size.x, box.size.z) * 0.22, 0.05, 0.16)
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(span, span * 0.3)
	back.mesh = quad
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.06)
	dark.roughness = 0.4
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	back.material_override = dark
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.add_child(back)
	var count := Label3D.new()
	count.name = "Count"
	count.font_size = 48
	count.pixel_size = span / 48.0 / 4.6  # seven digits fill the plate
	count.modulate = DIGITS
	count.outline_size = 0
	count.shaded = false
	count.double_sided = true
	count.position = Vector3(0, 0, 0.002)
	count.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.add_child(count)
	return plate


# The outermost -X point of the model's meshes near (y, z) in the model's own space (fallback: `widest`).
static func _side_x(model: Node3D, y: float, z: float, dy: float, dz: float, widest: float) -> float:
	var best := INF
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name == NODE or not mi.visible or mi.mesh == null or mi.get_parent().name == NODE:
			continue
		var place := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != model:
			if walk is Node3D:
				place = (walk as Node3D).transform * place
			walk = walk.get_parent()
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var at := place * v
				if absf(at.y - y) <= dy and absf(at.z - z) <= dz:
					best = minf(best, at.x)
	return best if best != INF else widest


# The model's meshes in the model's own space.
static func _bounds(model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node: Node in model.find_children("*", "VisualInstance3D", true, false):
		var vis := node as VisualInstance3D
		if vis.name == NODE or not vis.visible:
			continue
		var place := Transform3D.IDENTITY
		var walk: Node = vis
		while walk != null and walk != model:
			if walk is Node3D:
				place = (walk as Node3D).transform * place
			walk = walk.get_parent()
		var local := place * vis.get_aabb()
		out = local if first else out.merge(local)
		first = false
	return out if not first else AABB(Vector3(-0.05, -0.05, -0.3), Vector3(0.1, 0.1, 0.6))
