# Purpose: the sea world's islands streamed by distance (sea step 4): within data/sea/islands.json `near` metres of
# the player an island's full model stands (loaded then, freed when it falls behind), out to `far` only a plain
# silhouette (a low cone in the island's colour) so the horizon is never empty, beyond that nothing (the fog).
# Island positions are sea coordinates; the nodes hang under the sea world's root, which carries the floating origin.
# Islands of the kit (an entry with "props"; director: kit + a showcase start island) get the blended textured ground
# (game/isle_ground.gd, tinted by the entry's "ground"), their props and set pieces (game/sea_isle_props.gd) and
# their rivers / waterfalls (<model>_water.glb, game/isle_water.gd). A big island (its data has "chunks") is streamed
# by chunk instead (game/sea_isle_stream.gd: near / far ground, collision and clutter near the player).
# Dependencies: assets/models/sea/<model>.glb (tools/blender/sea_islands.py, sea_isle_start.py), data/sea/islands.json,
# game/isle_ground.gd, game/sea_isle_props.gd, game/isle_water.gd, game/sea_isle_stream.gd.
extends Node3D

const IsleGround = preload("res://game/isle_ground.gd")
const IsleProps = preload("res://game/sea_isle_props.gd")
const IsleWater = preload("res://game/isle_water.gd")
const IsleStream = preload("res://game/sea_isle_stream.gd")
const MODELS := "res://assets/models/sea/"

var graphics := "medium"  # the graphics tier (game/sea_world.gd enter): how thick and far the props are drawn
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
		if entry["full"] != null and (entry["full"] as Node).has_node("Stream"):
			((entry["full"] as Node).get_node("Stream") as Object).call("follow", Vector2(sea_pos.x, sea_pos.z) - at)


func _full(island: Dictionary) -> Node3D:
	var path := MODELS + String(island["model"]) + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var made: Node3D = (load(path) as PackedScene).instantiate()
	add_child(made)
	made.position = Vector3(float(island["pos"][0]), 0.0, float(island["pos"][1]))
	var ground: Material = _ground()
	if island.has("props"):
		ground = IsleGround.material(String(island["id"]), island.get("ground", {}))
	var list: Dictionary = {}
	if island.has("props") and FileAccess.file_exists(IsleProps.LISTS + String(island["props"]) + ".json"):
		list = JSON.parse_string(FileAccess.get_file_as_string(IsleProps.LISTS + String(island["props"]) + ".json"))
	if list.has("chunks"):  # a big island: ground, collision and clutter streamed by chunk (game/sea_isle_stream.gd)
		var stream := IsleStream.new()
		stream.name = "Stream"
		made.add_child(stream)
		stream.setup(made, ground, list, _cfg["props"], graphics)
	else:
		_solid(made, ground)
		if island.has("props"):
			made.set_meta("props", IsleProps.build(made, island, _cfg["props"], graphics))
	var water_path := MODELS + String(island["model"]) + "_water.glb"
	if ResourceLoader.exists(water_path):  # rivers and waterfalls: seen, not solid
		var water := (load(water_path) as PackedScene).instantiate() as Node3D
		made.add_child(water)
		for found in water.find_children("*", "MeshInstance3D", true, false):
			var surface := found as MeshInstance3D
			surface.material_override = IsleWater.material("waterfall" if String(surface.name).begins_with("waterfall") else "water")
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return made


# Every mesh of an island model gets a trimesh collider (the islands are walked on and sailed into).
func _solid(node: Node, ground: Material) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		(node as MeshInstance3D).create_trimesh_collision()
		(node as MeshInstance3D).material_override = ground
	for child in node.get_children():
		_solid(child, ground)


static var _ground_mat: StandardMaterial3D


# The old test islands are painted in their vertex colours (sand, grass, rock).
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


func props_shown() -> int:  # copies of props standing (checks)
	var n := 0
	for id: String in _shown:
		var full: Variant = _shown[id]["full"]
		if full != null:
			n += int((full as Node3D).get_meta("props", 0))
			if (full as Node).has_node("Stream"):
				n += int((full as Node).get_node("Stream").call("drawn"))
	return n
