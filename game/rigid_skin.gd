# Purpose: (polish1 D2) folds a reworked enemy's rigid parts into ONE skinned mesh: every pivot node of the model
# (Hips, Spine, ArmL ...) becomes a bone and every part hangs 100 % on its own pivot's bone, so it still moves as rigid
# pieces (game/enemy_rig.gd turns the bones) but draws as one surface per material (about 4-6 draw calls instead of
# ~22 node meshes, each again in every shadow pass). The folded mesh and skin are built once per model and shared;
# each enemy keeps its own materials (tint, hit flash) as surface overrides. Each piece's box is kept as its hit volume
# (parts(): game/enemy.gd ray_parts shoots against the pieces where they really are, the head pieces count as the head).
# Dependencies: none (works on any instantiated model whose meshes sit on named Node3D pivots). Used by game/enemy.gd.
extends RefCounted

static var _made := {}  # model id -> {mesh, skin, bones: PackedStringArray, parents: PackedInt32Array, rests: Array[Transform3D], kinds: PackedStringArray}


# Replaces the model's pivot nodes with a Skeleton3D "RigidSkin" (one bone per pivot, same names) + one MeshInstance3D;
# returns the skeleton (null if the model has nothing to fold).
static func fold(model: Node3D, id: String) -> Skeleton3D:
	if not _made.has(id):
		_made[id] = _build(model)
	var made: Dictionary = _made[id]
	if made.is_empty():
		return null
	var own := {}  # kind -> this model's own material for it
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var piece := found as MeshInstance3D
		for s in piece.mesh.get_surface_count():
			var source := piece.mesh.surface_get_material(s)
			var kind := String(source.resource_name) if source != null else ""
			if not own.has(kind):
				own[kind] = piece.get_active_material(s)
	for child in model.get_children():
		child.queue_free()  # the pivots and their parts: the bones and the folded mesh take over
	var skeleton := Skeleton3D.new()
	skeleton.name = "RigidSkin"
	var bones: PackedStringArray = made["bones"]
	var parents: PackedInt32Array = made["parents"]
	var rests: Array = made["rests"]
	for i in bones.size():
		skeleton.add_bone(bones[i])
		skeleton.set_bone_parent(i, parents[i])
		skeleton.set_bone_rest(i, rests[i])
		skeleton.set_bone_pose_position(i, (rests[i] as Transform3D).origin)
		skeleton.set_bone_pose_rotation(i, (rests[i] as Transform3D).basis.get_rotation_quaternion())
	model.add_child(skeleton)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = made["mesh"]
	body.skin = made["skin"]
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	var kinds: PackedStringArray = made["kinds"]
	for s in kinds.size():
		if own.has(kinds[s]) and own[kinds[s]] != null:
			body.set_surface_override_material(s, own[kinds[s]])
	return skeleton


static func _build(model: Node3D) -> Dictionary:
	var pivots: Array[Node3D] = []
	_collect(model, model, pivots)
	if pivots.is_empty():
		return {}
	var bones := PackedStringArray()
	var parents := PackedInt32Array()
	var rests: Array[Transform3D] = []
	var globals: Array[Transform3D] = []
	for node in pivots:
		bones.append(String(node.name))
		var up := node.get_parent() as Node3D
		parents.append(pivots.find(up) if up != model else -1)
		rests.append(node.transform)
		globals.append(_to_root(node, model))
	var skin := Skin.new()
	for i in bones.size():
		skin.add_named_bind(bones[i], globals[i].affine_inverse())
	# one surface per kind of material, every vertex on its pivot's bone
	var kinds := PackedStringArray()
	var tools: Array[SurfaceTool] = []
	var materials: Array[Material] = []
	for b in pivots.size():
		var piece := pivots[b] as MeshInstance3D
		if piece == null or piece.mesh == null:
			continue
		for s in piece.mesh.get_surface_count():
			var source := piece.mesh.surface_get_material(s)
			var kind := String(source.resource_name) if source != null else ""
			var k := kinds.find(kind)
			if k < 0:
				k = kinds.size()
				kinds.append(kind)
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
				tools.append(st)
				materials.append(source)
			var arrays := piece.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
			var colors: Variant = arrays[Mesh.ARRAY_COLOR]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var to_root := globals[b]
			var order: PackedInt32Array = index
			if order.is_empty():
				order.resize(verts.size())
				for v in verts.size():
					order[v] = v
			var st2 := tools[k]
			for v in order:
				st2.set_normal((to_root.basis * normals[v]).normalized())
				if uvs != null:
					st2.set_uv((uvs as PackedVector2Array)[v])
				if colors != null:
					st2.set_color((colors as PackedColorArray)[v])
				st2.set_bones(PackedInt32Array([b, 0, 0, 0]))
				st2.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
				st2.add_vertex(to_root * verts[v])
	# (bug update) hit volumes: every piece's own box in its bone's space, which pieces are the head, how far it reaches
	var boxes: Array[AABB] = []
	var heads := PackedByteArray()
	var reach := 0.0
	for b in pivots.size():
		var piece := pivots[b] as MeshInstance3D
		boxes.append(piece.mesh.get_aabb() if piece != null and piece.mesh != null else AABB())
		var up := b
		var head := 0
		while up >= 0:
			if bones[up] == "Head" or bones[up] == "Jaw":
				head = 1
				break
			up = parents[up]
		heads.append(head)
		if piece != null and piece.mesh != null:
			var box := piece.mesh.get_aabb()
			for c in 8:
				reach = maxf(reach, (globals[b] * box.get_endpoint(c)).length())
	var mesh := ArrayMesh.new()
	for k in tools.size():
		tools[k].generate_tangents()  # the materials' normal maps need them
		tools[k].commit(mesh)
		mesh.surface_set_material(k, materials[k])
	return {"mesh": mesh, "skin": skin, "bones": bones, "parents": parents, "rests": rests, "kinds": kinds, "boxes": boxes, "heads": heads, "reach": reach}


# (bug update) The folded model's hit volumes (see _build): {boxes: Array[AABB] per bone, heads: 1 = head piece, reach:
# metres from the model's root to its farthest point, unscaled}; empty before fold() made it.
static func parts(id: String) -> Dictionary:
	return _made.get(id, {})


# Every Node3D under the model, parents before children (the model root itself is not a bone).
static func _collect(node: Node, model: Node3D, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D:
			out.append(child as Node3D)
			_collect(child, model, out)


static func _to_root(node: Node3D, model: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var at: Node = node
	while at != model and at is Node3D:
		t = (at as Node3D).transform * t
		at = at.get_parent()
	return t
