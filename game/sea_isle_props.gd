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
# island's node by game/sea_islands.gd, which works out groups_of() / solid_specs() off the main thread and adds the
# patches a few at a time (sea step 13g: no frame hitch when an island comes near).
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
	var drawn := 0
	for g: Dictionary in groups_of(props, cfg, graphics):
		drawn += add_group(holder, g)
	return drawn


# The props grouped into patches, each with its MultiMesh buffer ready: plain data, so it can be worked out off the
# main thread before the island is needed (sea step 13g). [{"model", "name", "buffer", "count", "range", "shadow"}].
static func groups_of(props: Array, cfg: Dictionary, graphics: String) -> Array:
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
	var out: Array = []
	for key: String in groups:
		var model := key.get_slice("|", 0)
		var at: Array = groups[key]
		var buffer := PackedFloat32Array()
		buffer.resize(at.size() * 12)
		for i in at.size():  # the MultiMesh layout: the 3 x 4 matrix row by row
			var t: Transform3D = at[i]
			var j := i * 12
			buffer[j] = t.basis.x.x
			buffer[j + 1] = t.basis.y.x
			buffer[j + 2] = t.basis.z.x
			buffer[j + 3] = t.origin.x
			buffer[j + 4] = t.basis.x.y
			buffer[j + 5] = t.basis.y.y
			buffer[j + 6] = t.basis.z.y
			buffer[j + 7] = t.origin.y
			buffer[j + 8] = t.basis.x.z
			buffer[j + 9] = t.basis.y.z
			buffer[j + 10] = t.basis.z.z
			buffer[j + 11] = t.origin.z
		out.append({"model": model, "name": key.replace("|", "_").replace("-", "m"), "buffer": buffer, "count": at.size(),
			"range": float(ranges.get(model, ranges["default"])) * float(tier["range"]), "shadow": (cfg["shadows"] as Array).has(model)})
	return out


# One patch of groups_of() as a MultiMesh under `holder` (main thread). Returns how many copies it draws.
static func add_group(holder: Node3D, g: Dictionary) -> int:
	var mesh := _mesh(String(g["model"]))
	if mesh == null:
		return 0
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = mesh
	many.instance_count = int(g["count"])
	many.buffer = g["buffer"]
	var shown := MultiMeshInstance3D.new()
	shown.multimesh = many
	shown.name = String(g["name"])
	shown.visibility_range_end = float(g["range"])
	shown.visibility_range_end_margin = 10.0
	shown.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if not bool(g["shadow"]):
		shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(shown)
	return int(g["count"])


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
	add_solids(body, solid_specs(props, solid))
	return body


# The colliders of solids() as plain data (off the main thread, sea step 13g): [kind "box" | "cyl", size, transform].
static func solid_specs(props: Array, solid: Dictionary) -> Array:
	var out: Array = []
	for p: Array in props:
		var model := String(p[0])
		if not solid.has(model):
			continue
		var scale := float(p[5])
		var at := Vector3(float(p[1]), float(p[2]), float(p[3]))
		var r := float(solid[model]) * scale
		if r <= 0.0:  # a wall: a box along its own x
			out.append(["box", Vector3(4.0, 2.0, 0.6) * scale, Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[4]))), at + Vector3(0.0, 1.0 * scale, 0.0))])
		else:
			var height := maxf(r * 2.0, 3.0 * scale)
			var lift := height * 0.5 - 0.3
			if model == "sea_stack":  # from the sea floor (20 m down) to its top (16 m up)
				height = 36.0 * scale
				lift = -2.0 * scale
			out.append(["cyl", Vector2(r, height), Transform3D(Basis(), at + Vector3(0.0, lift, 0.0))])
	return out


static func add_solids(body: StaticBody3D, specs: Array) -> void:
	for spec: Array in specs:
		var holder_shape := CollisionShape3D.new()
		if String(spec[0]) == "box":
			var box := BoxShape3D.new()
			box.size = spec[1]
			holder_shape.shape = box
		else:
			var cyl := CylinderShape3D.new()
			cyl.radius = (spec[1] as Vector2).x
			cyl.height = (spec[1] as Vector2).y
			holder_shape.shape = cyl
		holder_shape.transform = spec[2]
		body.add_child(holder_shape)
