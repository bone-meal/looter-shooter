# Purpose: the body sliders of rigged characters. A rigged character is its clothes, so each clothing mesh gets blend
# shapes computed once from where every vertex sits on the body (rest pose, metres, y up, +z front): "weight" (wider or
# slimmer torso and limbs), "bust", "glutes", and "bust_bounce" / "glutes_bounce" (the same areas moved up and down,
# driven by game/rigged_jiggle.gd). Areas and amounts per body are data: data/characters.json bodies.<id>.shape.
# Dependencies: none (game/rigged_body.gd calls it).
extends RefCounted

const SHAPES := ["weight", "bust", "glutes", "bust_bounce", "glutes_bounce"]

static var _cache := {}  # source mesh id -> ArrayMesh with the blend shapes


# A copy of `source` with the blend shapes (cached per source mesh). `regions` is the body's "shape" data.
static func shaped(source: ArrayMesh, regions: Dictionary) -> ArrayMesh:
	var id := source.get_instance_id()
	if _cache.has(id):
		return _cache[id]
	var weight: Dictionary = regions["weight"]
	var areas := {"bust": regions["bust"], "glutes": regions["glutes"]}
	var mesh := ArrayMesh.new()
	for shape: String in SHAPES:
		mesh.add_blend_shape(shape)
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		for extra in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[extra] = null
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var still := PackedVector3Array()  # blend shapes are stored as offsets from the base mesh: start with none
		still.resize(vertices.size())
		var flat := PackedFloat32Array()
		if arrays[Mesh.ARRAY_TANGENT] != null:
			flat.resize((arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size())
		var moved := {}
		for shape: String in SHAPES:
			moved[shape] = still.duplicate()
		var wide: PackedVector3Array = moved["weight"]
		for i in vertices.size():
			var v := vertices[i]
			var band := smoothstep(float(weight["from"]), float(weight["from"]) + 0.15, v.y) * (1.0 - smoothstep(float(weight["to"]) - 0.12, float(weight["to"]), v.y))
			wide[i] = Vector3(normals[i].x, 0.0, normals[i].z) * (float(weight["amount"]) * band)
		for area: String in areas:
			var spec: Dictionary = areas[area]
			var at: Array = spec["at"]
			var push: Array = spec["push"]
			var radius := float(spec["radius"])
			var out: PackedVector3Array = moved[area]
			var bounce: PackedVector3Array = moved[area + "_bounce"]
			for i in vertices.size():
				var v := vertices[i]
				var near := Vector3(absf(v.x) - float(at[0]), v.y - float(at[1]), v.z - float(at[2])).length_squared() / (radius * radius)
				if near < 6.0:
					var pull := exp(-near)
					out[i] = Vector3(signf(v.x) * float(push[0]), float(push[1]), float(push[2])) * pull
					bounce[i] = Vector3(0.0, float(spec["bounce"]) * pull, 0.0)
		var shapes: Array = []
		for shape: String in SHAPES:
			var one: Array = []
			one.resize(Mesh.ARRAY_MAX)
			one[Mesh.ARRAY_VERTEX] = moved[shape]
			one[Mesh.ARRAY_NORMAL] = still  # shading keeps the base normals
			if not flat.is_empty():
				one[Mesh.ARRAY_TANGENT] = flat
			shapes.append(one)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if bones.size() == vertices.size() * 8 else 0
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes, {}, flags)
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	_cache[id] = mesh
	return mesh


# Sets the three slider shapes on a piece. weight 0.8..1.4 (1 = as modelled); bust and glutes 0..1 around `neutral`.
static func apply(piece: MeshInstance3D, weight: float, bust: float, glutes: float, neutral: float) -> void:
	piece.set_blend_shape_value(0, (weight - 1.0) / 0.4)
	piece.set_blend_shape_value(1, (bust - neutral) * 1.5)
	piece.set_blend_shape_value(2, (glutes - neutral) * 1.5)
