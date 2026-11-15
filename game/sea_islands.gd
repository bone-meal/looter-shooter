# Purpose: the sea world's islands streamed by distance (sea step 4): within data/sea/islands.json `near` metres of
# the player an island's full model stands (loaded then, freed when it falls behind), out to `far` only a plain
# silhouette (a low cone in the island's colour) so the horizon is never empty, beyond that nothing (the fog).
# Island positions are sea coordinates; the nodes hang under the sea world's root, which carries the floating origin.
# Dependencies: assets/models/sea/<model>.glb (tools/blender/sea_islands.py), data/sea/islands.json.
extends Node3D

const MODELS := "res://assets/models/sea/"

var _cfg: Dictionary
var _shown := {}  # island id -> {"full": Node3D or null, "far": MeshInstance3D}


func setup(cfg: Dictionary) -> void:
	_cfg = cfg


# Call every half second with the player's sea position.
func follow(sea_pos: Vector3) -> void:
	var near := float(_cfg["near"])
	var far := float(_cfg["far"])
	for island: Dictionary in _cfg["islands"]:
		var id := String(island["id"])
		var at := Vector2(float(island["pos"][0]), float(island["pos"][1]))
		var d := at.distance_to(Vector2(sea_pos.x, sea_pos.z)) - float(island["radius"])
		var entry: Dictionary = _shown.get(id, {})
		if d > far * 1.05:
			if not entry.is_empty():
				_free(entry)
				_shown.erase(id)
			continue
		if entry.is_empty():
			entry = {"full": null, "far": _silhouette(island)}
			_shown[id] = entry
		var want_full := d < near
		if want_full and entry["full"] == null:
			entry["full"] = _full(island)
		elif not want_full and d > near * 1.15 and entry["full"] != null:
			(entry["full"] as Node3D).queue_free()
			entry["full"] = null
		(entry["far"] as Node3D).visible = entry["full"] == null


func _full(island: Dictionary) -> Node3D:
	var path := MODELS + String(island["model"]) + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var made: Node3D = (load(path) as PackedScene).instantiate()
	add_child(made)
	made.position = Vector3(float(island["pos"][0]), 0.0, float(island["pos"][1]))
	_solid(made)
	return made


# Every mesh of an island model gets a trimesh collider (the islands are walked on and sailed into).
func _solid(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		(node as MeshInstance3D).create_trimesh_collision()
		(node as MeshInstance3D).material_override = _ground()
	for child in node.get_children():
		_solid(child)


static var _ground_mat: StandardMaterial3D


# The test islands are painted in their vertex colours (sand, grass, rock).
static func _ground() -> StandardMaterial3D:
	if _ground_mat == null:
		_ground_mat = StandardMaterial3D.new()
		_ground_mat.vertex_color_use_as_albedo = true
		_ground_mat.roughness = 0.95
	return _ground_mat


func _silhouette(island: Dictionary) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	var r := float(island["radius"])
	cone.top_radius = r * 0.25
	cone.bottom_radius = r
	cone.height = clampf(r * 0.35, 6.0, 160.0)
	cone.radial_segments = 16
	cone.rings = 1
	var mesh := MeshInstance3D.new()
	mesh.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.42, 0.3)
	mat.roughness = 1.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.position = Vector3(float(island["pos"][0]), cone.height * 0.5 - 2.0, float(island["pos"][1]))
	return mesh


func _free(entry: Dictionary) -> void:
	if entry["full"] != null:
		(entry["full"] as Node3D).queue_free()
	(entry["far"] as Node3D).queue_free()


func shown_count() -> Vector2i:  # (full models, silhouettes) for checks
	var full := 0
	var far := 0
	for id: String in _shown:
		if _shown[id]["full"] != null:
			full += 1
		elif (_shown[id]["far"] as Node3D).visible:
			far += 1
	return Vector2i(full, far)
