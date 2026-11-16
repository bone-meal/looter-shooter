# Purpose: an island's props (director: "plenty of props"): the placed list data/sea/isles/<props>.json (palms,
# bushes, ferns, boulders, sea stacks, driftwood, shells, grass tufts, ruins ... made by tools/blender/sea_isle_*.py)
# drawn as one MultiMesh per model and patch of ground (patches sized by how far the model is drawn, so a patch behind
# the camera or out of range is not drawn),
# small clutter thinned and shortened on lower graphics tiers (data/sea/islands.json "props"), and the solid ones
# (trunks, boulders, stacks, walls) given simple colliders on one static body so ships run aground on them too.
# Dependencies: assets/models/sea/props/<model>.gltf, game/fantasy_models.gd (materials by kind),
# data/sea/islands.json "props", data/sea/isles/<props>.json. Built under the island's node by game/sea_islands.gd.
extends RefCounted

const FantasyModels = preload("res://game/fantasy_models.gd")
const MODELS := "res://assets/models/sea/props/"
const LISTS := "res://data/sea/isles/"

static var _meshes := {}  # model id -> Mesh (dressed once)


# Adds the props of `island` (data/sea/islands.json entry with "props") under `holder` (the island's node, so they are
# freed with it). Returns how many copies are drawn.
static func build(holder: Node3D, island: Dictionary, cfg: Dictionary, graphics: String) -> int:
	var path := LISTS + String(island["props"]) + ".json"
	if not FileAccess.file_exists(path):
		return 0
	var list: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var tier: Dictionary = cfg["tiers"].get(graphics, cfg["tiers"]["medium"])
	var ranges: Dictionary = cfg["range"]
	var thin: Array = cfg["thin"]
	var groups := {}  # "model|quarter" -> Array of Transform3D
	var kept := {}  # model -> how many seen (for thinning)
	for p: Array in list["props"]:
		var model := String(p[0])
		var seen := int(kept.get(model, 0))
		kept[model] = seen + 1
		if thin.has(model) and fposmod(float(seen) * 0.618034, 1.0) >= float(tier["share"]):
			continue
		var at := Vector3(float(p[1]), float(p[2]), float(p[3]))
		var basis := Basis(Vector3.UP, deg_to_rad(float(p[4]))).scaled(Vector3.ONE * float(p[5]))
		var cell := clampf(float(ranges.get(model, ranges["default"])) * 0.8, 50.0, 500.0)  # small clutter in small cells
		var key := "%s|%d|%d" % [model, floori(at.x / cell), floori(at.z / cell)]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(Transform3D(basis, at))
	var drawn := 0
	for key: String in groups:
		var model := key.get_slice("|", 0)
		var mesh := _mesh(model)
		if mesh == null:
			continue
		var at: Array = groups[key]
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = mesh
		many.instance_count = at.size()
		for i in at.size():
			many.set_instance_transform(i, at[i])
		var shown := MultiMeshInstance3D.new()
		shown.multimesh = many
		shown.name = key.replace("|", "_").replace("-", "m")
		shown.visibility_range_end = float(ranges.get(model, ranges["default"])) * float(tier["range"])
		shown.visibility_range_end_margin = 10.0
		shown.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if not (cfg["shadows"] as Array).has(model):
			shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(shown)
		drawn += at.size()
	_colliders(holder, list)
	return drawn


static func _mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var path := MODELS + model + ".gltf"
	var out: Mesh = null
	if ResourceLoader.exists(path):
		var root := (load(path) as PackedScene).instantiate()
		var found := root.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			out = (found[0] as MeshInstance3D).mesh
			FantasyModels.dress(out)
		root.free()
	_meshes[model] = out
	return out


# Trunks, boulders and stacks are upright cylinders, the ruined walls boxes; everything else is walked through.
static func _colliders(holder: Node3D, list: Dictionary) -> void:
	var solid: Dictionary = list.get("solid", {})
	var body := StaticBody3D.new()
	body.name = "PropSolids"
	holder.add_child(body)
	for p: Array in list["props"]:
		var model := String(p[0])
		if not solid.has(model):
			continue
		var scale := float(p[5])
		var at := Vector3(float(p[1]), float(p[2]), float(p[3]))
		var holder_shape := CollisionShape3D.new()
		var r := float(solid[model]) * scale
		if r <= 0.0:  # a wall: a box along its own x
			var box := BoxShape3D.new()
			box.size = Vector3(4.0, 2.0, 0.6) * scale
			holder_shape.shape = box
			holder_shape.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[4]))), at + Vector3(0.0, 1.0 * scale, 0.0))
		else:
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = maxf(r * 2.0, 3.0 * scale)
			var lift := cyl.height * 0.5 - 0.3
			if model == "sea_stack":  # from the sea floor (20 m down) to its top (16 m up)
				cyl.height = 36.0 * scale
				lift = -2.0 * scale
			holder_shape.shape = cyl
			holder_shape.position = at + Vector3(0.0, lift, 0.0)
		body.add_child(holder_shape)
