# Purpose: loads the fantasy world's prop models (assets/models/fantasy/, made by tools/blender/fantasy_props.py) and
# gives every part the material of what it is made of: the model names each part's material after its kind (plaster,
# timber, roof, bark, leaf ... see tools/blender/fantasy_kit.py) and carries the part's colour per corner; "paint" is
# plain matte colour and "glow" unshaded warm light for windows, fire and crystals. `scene` = a model to place once (buildings), `mesh` = its main mesh for
# drawing many copies in one call (trees, rocks, herbs), `creature` = an enemy's body (tools/blender/fantasy_creatures.py).
# Dependencies: game/surface_library.gd (the textures behind each kind of part).
extends RefCounted

const SurfaceLibrary = preload("res://game/surface_library.gd")

const FOLDER := "res://assets/models/fantasy/"
const KINDS := ["plaster", "adobe", "timber", "wood", "roof", "thatch", "slate", "stone", "sandstone", "cloth", "leather", "metal", "bark", "pinebark", "leaf", "rock", "fur", "scale", "ice", "bone", "feather"]

static var _paint: StandardMaterial3D
static var _glow: StandardMaterial3D
static var _fixed := {}  # mesh -> true once its materials were replaced


static func has_model(id: String) -> bool:
	return ResourceLoader.exists(FOLDER + id + ".gltf")


static func scene(id: String) -> Node3D:
	if not has_model(id):
		return null
	var root := (load(FOLDER + id + ".gltf") as PackedScene).instantiate() as Node3D
	for found in root.find_children("*", "MeshInstance3D", true, false):
		_fix((found as MeshInstance3D).mesh)
	return root


static func mesh(id: String) -> Mesh:
	if not has_model(id):
		return null
	var root := (load(FOLDER + id + ".gltf") as PackedScene).instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	var out: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	root.free()
	if out != null:
		_fix(out)
	return out


static func has_creature(id: String) -> bool:
	return ResourceLoader.exists(FOLDER + "creatures/" + id + ".gltf")


# A creature's body. Each part keeps the texture of what it is made of, but in materials of its OWN (appended to
# `own`), so one creature can flash or freeze without the others; eyes and embers glow in `eye`.
# A model that is carried about (a staff): like a creature it gets materials of its own whose grain travels with it,
# and its glowing parts take `lit`.
static func held(id: String, lit: Material) -> Node3D:
	var root := (load(FOLDER + id + ".gltf") as PackedScene).instantiate() as Node3D
	var by_kind := {}
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var piece := found as MeshInstance3D
		for i in piece.mesh.get_surface_count():
			var made := piece.mesh.surface_get_material(i)
			var kind := String(made.resource_name) if made != null else "paint"
			if kind == "glow":
				piece.set_surface_override_material(i, lit)
				continue
			if not by_kind.has(kind):
				by_kind[kind] = surface(kind).duplicate()
				(by_kind[kind] as StandardMaterial3D).uv1_world_triplanar = false
			piece.set_surface_override_material(i, by_kind[kind])
	return root


# A material of `kind` in one flat colour, for things built from plain boxes (the walls and floor of a room).
static func tinted(kind: String, color: Color) -> StandardMaterial3D:
	var m := surface(kind).duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = false
	m.albedo_color = Color(m.albedo_color.r * color.r, m.albedo_color.g * color.g, m.albedo_color.b * color.b)
	return m


static func creature(id: String, eye: Color, own: Array[StandardMaterial3D]) -> Node3D:
	var root := (load(FOLDER + "creatures/" + id + ".gltf") as PackedScene).instantiate() as Node3D
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.albedo_color = eye
	var by_kind := {}
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var piece := found as MeshInstance3D
		for i in piece.mesh.get_surface_count():
			var made := piece.mesh.surface_get_material(i)
			var kind := String(made.resource_name) if made != null else "paint"
			if kind == "glow":
				piece.set_surface_override_material(i, lit)
				continue
			if not by_kind.has(kind):
				by_kind[kind] = surface(kind).duplicate()
				(by_kind[kind] as StandardMaterial3D).uv1_world_triplanar = false  # the grain travels with the body instead of sliding over it
				own.append(by_kind[kind])
			piece.set_surface_override_material(i, by_kind[kind])
	return root


# The bounding box of a model, for its collider.
static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var piece := found as MeshInstance3D
		var local := piece.transform * piece.mesh.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box


static func paint() -> StandardMaterial3D:
	if _paint == null:
		_paint = StandardMaterial3D.new()
		_paint.vertex_color_use_as_albedo = true
		_paint.vertex_color_is_srgb = true
		_paint.roughness = 1.0
		_paint.metallic_specular = 0.1
	return _paint


static func glow() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.albedo_color = Color(1.0, 0.86, 0.5)
	return _glow


# The material for a part made of `kind` (the material name the model scripts give it): a textured surface of
# data/surfaces.json ("fx_<kind>") that keeps the part's own colour, plain paint for anything else.
static func surface(kind: String) -> StandardMaterial3D:
	if kind == "glow":
		return glow()
	if not KINDS.has(kind):
		return paint()
	var m := SurfaceLibrary.material("fx_" + kind, Color.WHITE)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true  # the models store screen-encoded colours (tools/blender/fantasy_kit.py real)
	return m


static func _fix(target: Mesh) -> void:
	if _fixed.has(target):
		return
	_fixed[target] = true
	var kinds := PackedStringArray()  # what each surface is made of, kept for whoever merges meshes (game/fantasy_places.gd)
	for i in target.get_surface_count():
		var made := target.surface_get_material(i)
		kinds.append(String(made.resource_name) if made != null else "paint")
		target.surface_set_material(i, surface(kinds[i]))
	target.set_meta("kinds", kinds)
