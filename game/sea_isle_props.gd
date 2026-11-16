# Purpose: an island's props (director: "plenty of props"): the placed list data/sea/isles/<props>.json (palms,
# bushes, ferns, boulders, sea stacks, driftwood, shells, grass tufts, ruins ... made by tools/blender/sea_isle_*.py)
# drawn as one MultiMesh per model and patch of ground (patches sized by how far the model is drawn, so a patch behind
# the camera or out of range is not drawn),
# small clutter thinned and shortened on lower graphics tiers (data/sea/islands.json "props"), and the solid ones
# (trunks, boulders, stacks, walls) given simple colliders on one static body so ships run aground on them too.
# Set pieces (the list's "places": sea arch, cave, lighthouse, wreck, camp, jetty, ruins, tide pools) stand once each
# and are solid as modelled; their "water" parts get still pool water (game/isle_water.gd).
# Dependencies: assets/models/sea/props/<model>.gltf, assets/models/sea/places/<model>.gltf, game/fantasy_models.gd
# (materials by kind), game/isle_water.gd, data/sea/islands.json "props", data/sea/isles/<props>.json. Built under the
# island's node by game/sea_islands.gd.
extends RefCounted

const FantasyModels = preload("res://game/fantasy_models.gd")
const IsleWater = preload("res://game/isle_water.gd")
const MODELS := "res://assets/models/sea/props/"
const PLACES := "res://assets/models/sea/places/"
const LISTS := "res://data/sea/isles/"

static var _meshes := {}  # model id -> Mesh (dressed once)


# Adds the props of `island` (data/sea/islands.json entry with "props") under `holder` (the island's node, so they are
# freed with it). Returns how many copies are drawn. (Big islands stream theirs per chunk: game/sea_isle_stream.gd.)
static func build(holder: Node3D, island: Dictionary, cfg: Dictionary, graphics: String) -> int:
	var path := LISTS + String(island["props"]) + ".json"
	if not FileAccess.file_exists(path):
		return 0
	var list: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var drawn := draw(holder, list["props"], cfg, graphics)
	solids(holder, list["props"], list.get("solid", {}))
	for p: Array in list.get("places", []):
		if place(holder, p):
			drawn += 1
	return drawn


# One MultiMesh per model and patch for these props ([model, x, y, z, yaw, scale], island-local) under `holder`;
# small clutter thinned on lower tiers. Returns how many copies are drawn.
static func draw(holder: Node3D, props: Array, cfg: Dictionary, graphics: String) -> int:
	var tier: Dictionary = cfg["tiers"].get(graphics, cfg["tiers"]["medium"])
	var ranges: Dictionary = cfg["range"]
	var thin: Array = cfg["thin"]
	var groups := {}  # "model|patch" -> Array of Transform3D
	var kept := {}  # model -> how many seen (for thinning)
	for p: Array in props:
		var model := String(p[0])
		var seen := int(kept.get(model, 0))
		kept[model] = seen + 1
		if thin.has(model) and fposmod(float(seen) * 0.618034, 1.0) >= float(tier["share"]):
			continue
		var at := Vector3(float(p[1]), float(p[2]), float(p[3]))
		var turn := Basis(Vector3.UP, deg_to_rad(float(p[4]))).scaled(Vector3.ONE * float(p[5]))
		var cell := clampf(float(ranges.get(model, ranges["default"])) * 0.35, 40.0, 220.0)  # small clutter in small cells
		var key := "%s|%d|%d" % [model, floori(at.x / cell), floori(at.z / cell)]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(Transform3D(turn, at))
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
	return drawn


# A set piece: the model as it is, dressed, solid as modelled.
static func place(holder: Node3D, p: Array) -> bool:
	var path := PLACES + String(p[0]) + ".gltf"
	if not ResourceLoader.exists(path):
		return false
	var made := (load(path) as PackedScene).instantiate() as Node3D
	made.name = "Place_" + String(p[0])
	holder.add_child(made)
	made.position = Vector3(float(p[1]), float(p[2]), float(p[3]))
	made.rotation = Vector3(deg_to_rad(float(p[6])) if p.size() > 6 else 0.0, deg_to_rad(float(p[4])), 0.0)  # optional pitch (bridges)
	made.scale = Vector3.ONE * float(p[5])
	for found in made.find_children("*", "MeshInstance3D", true, false):
		var shown := found as MeshInstance3D
		FantasyModels.dress(shown.mesh)
		if not shown.mesh.has_meta("water_set"):
			shown.mesh.set_meta("water_set", true)
			var kinds: PackedStringArray = shown.mesh.get_meta("kinds", PackedStringArray())
			for i in kinds.size():
				if kinds[i] == "water":
					shown.mesh.surface_set_material(i, IsleWater.material("pool"))
		shown.create_trimesh_collision()
	return true


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
# Returns the static body holding them.
static func solids(holder: Node3D, props: Array, solid: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "PropSolids"
	holder.add_child(body)
	for p: Array in props:
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
	return body
