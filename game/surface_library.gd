# Purpose: named world surfaces (sand, sandstone, wood...) from data/surfaces.json, backed by CC0 PBR texture sets in
# assets/cc0/textures/. One shared material per surface. configure() switches every surface in place between the flat-colour
# look and the textured look, so world builders ask for a surface once and never care which look is active.
# Dependencies: data/surfaces.json. Configured by game/render_style.gd. Missing textures fall back to the flat colour.
# Also read by game/ground_blend.gd (definition, texture, current settings).
extends RefCounted

const DATA_PATH := "res://data/surfaces.json"
const TEX_DIR := "res://assets/cc0/textures/"

static var _defs := {}      # surface id -> {set, tile, tint, uv}
static var _mats := {}      # surface id -> StandardMaterial3D
static var _flat := {}      # surface id -> Color used by the flat look
static var _textured := false
static var _tex_res := "1k"
static var _maps := 3       # 1 = colour only, 2 = + normal map, 3 = + occlusion/roughness map


# The shared material of a surface. `flat` is its colour in the flat look (first caller decides).
static func material(id: String, flat: Color) -> StandardMaterial3D:
	if _mats.has(id):
		var cached: StandardMaterial3D = _mats[id]
		return cached
	var m := StandardMaterial3D.new()
	_mats[id] = m
	_flat[id] = flat
	_apply(id)
	return m


static func configure(textured: bool, tex_res: String, maps: int) -> void:
	if textured == _textured and tex_res == _tex_res and maps == _maps:
		return
	_textured = textured
	_tex_res = tex_res
	_maps = maps
	for id: String in _mats:
		_apply(id)


static func is_textured() -> bool:
	return _textured


static func map_count() -> int:
	return _maps


# The colour multiplier of a "gain" surface while textures are on (white otherwise), for shaders that mix surfaces themselves.
static func gain(id: String) -> Color:
	var def := definition(id)
	if not _textured or not def.has("gain"):
		return Color.WHITE
	var g: Array = def["gain"]
	return Color(g[0], g[1], g[2])


# The data entry of a surface ({} when unknown).
static func definition(id: String) -> Dictionary:
	if _defs.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			var list: Array = (parsed as Dictionary).get("surfaces", [])
			for entry: Dictionary in list:
				_defs[String(entry["id"])] = entry
	var found: Dictionary = _defs.get(id, {})
	return found


static func _apply(id: String) -> void:
	var m: StandardMaterial3D = _mats[id]
	var def := definition(id)
	var set_id := String(def.get("set", ""))
	var diff: Texture2D = null
	if _textured and set_id != "":
		diff = texture(set_id, "diff")
	var nor: Texture2D = null
	var arm: Texture2D = null
	if diff != null and _maps >= 2:
		nor = texture(set_id, "nor")
	if diff != null and _maps >= 3:
		arm = texture(set_id, "arm")
	var flat: Color = _flat[id]
	m.albedo_color = flat if diff == null else Color.html(String(def.get("tint", "#ffffff")))
	if diff != null and bool(def.get("grain", false)):  # a surface coloured by its model: a grey copy of the texture adds only the grain
		var grey := texture(set_id, "grain")
		if grey != null:
			diff = grey
			m.albedo_color = Color(2.0, 2.0, 2.0)  # the grey copy averages one half
	m.albedo_texture = diff
	m.normal_enabled = nor != null
	m.normal_texture = nor
	m.ao_enabled = arm != null
	m.ao_texture = arm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness_texture = arm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var own_uv := bool(def.get("uv", false))
	var tile := maxf(float(def.get("tile", 2.0)), 0.01)
	m.uv1_triplanar = diff != null and not own_uv
	m.uv1_world_triplanar = m.uv1_triplanar
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / tile if diff != null else Vector3.ONE
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


# Loads one map of a texture set at the configured size, or at the other size when that file is missing.
static func texture(set_id: String, map_name: String) -> Texture2D:
	for res: String in [_tex_res, "1k", "2k"]:
		var path := "%s%s/%s_%s_%s.jpg" % [TEX_DIR, set_id, set_id, map_name, res]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null
