# Purpose: hands world builders the meshes inside the CC0 glTF models in assets/cc0/models/ (one file often holds
# several variants as separate nodes). The meshes keep their imported PBR materials and automatic LODs.
# Dependencies: none. A model that is not downloaded or not imported yet gives an empty list, so builders skip that prop.
extends RefCounted

const DIR := "res://assets/cc0/models/"

static var _cache := {}  # model id -> Array of [node name, Mesh]


# Every mesh of a model, in file order.
static func meshes(model_id: String) -> Array:
	if not _cache.has(model_id):
		var found: Array = []
		var path := "%s%s/%s_1k.gltf" % [DIR, model_id, model_id]
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene != null:
				var root := scene.instantiate()
				_collect(root, found)
				root.free()
		_cache[model_id] = found
	var list: Array = _cache[model_id]
	return list


# The mesh of one named node (null when missing).
static func mesh(model_id: String, node_name: String) -> Mesh:
	for entry: Array in meshes(model_id):
		if String(entry[0]) == node_name:
			return entry[1] as Mesh
	return null


static func _collect(node: Node, into: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		into.append([String(node.name), (node as MeshInstance3D).mesh])
	for child in node.get_children():
		_collect(child, into)
