# Purpose: the ground material of the sea's island kit (director: textured blend ground + per-island tints; 2026-11-16
# "looks painted on, make it more detailed": every layer looked at twice (turned and scaled) and blended by noise so
# it never tiles, meadow patches, ragged sharp edges to paths and streets, normal maps on paths and streets, real
# cobble and flagstone textures for the town). Per pixel
# it blends five surfaces of data/surfaces.json: sand, grass above the beach, rock on steep slopes (read on the cliff
# face, not from above), wet sand at the waterline and the trodden ground of paths; each layer is coloured by the
# island's own tint (data/sea/islands.json "ground") and the model's vertex colour adds light and dark patches. The
# weights come per corner from the model (tools/blender/sea_isle_kit.py): UV = (grass, rock), UV2 = (wet, trodden),
# vertex alpha = forest floor. A trodden weight above 1 marks a town street (weight + 2), paved by `paving`.
# Without textures it is the same blend in the plain tints. One shader source with #defines (Compatibility + Forward+).
# Dependencies: game/surface_library.gd (texture sets, gains, current quality). Configured by game/render_style.gd.
extends RefCounted

const SurfaceLibrary = preload("res://game/surface_library.gd")

const CODE := """
shader_type spatial;
#ifdef TOON
render_mode cull_back, diffuse_toon, specular_toon;
#else
render_mode cull_back;
#endif

uniform vec3 tint_sand = vec3(0.9, 0.82, 0.62);
uniform vec3 tint_grass = vec3(0.45, 0.62, 0.3);
uniform vec3 tint_rock = vec3(0.55, 0.52, 0.48);
uniform vec3 tint_wet = vec3(0.62, 0.55, 0.42);
uniform vec3 tint_path = vec3(0.55, 0.45, 0.33);
uniform vec3 tint_forest = vec3(0.4, 0.36, 0.24);
uniform float paving = 0.0;  // the town's streets: 0 dirt, 1 cobbles, 2 flagstones (game/sea_town.gd, by the town's growth)

#ifdef TEXTURED
uniform vec4 tiles = vec4(3.0);
uniform float tile_path = 3.0;
uniform float tile_forest = 3.0;
uniform float tile_cobble = 2.6;
uniform float tile_paving = 1.8;
uniform vec3 gain_sand = vec3(1.0);
uniform vec3 gain_grass = vec3(1.0);
uniform vec3 gain_rock = vec3(1.0);
uniform vec3 gain_wet = vec3(1.0);
uniform vec3 gain_path = vec3(1.0);
uniform vec3 gain_forest = vec3(1.0);
uniform vec3 gain_cobble = vec3(1.0);
uniform vec3 gain_paving = vec3(1.0);
uniform sampler2D tex_sand : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_grass : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_rock : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_wet : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_path : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_forest : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_cobble : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_paving : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
#ifdef NORMALS
uniform sampler2D nor_sand : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_grass : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_rock : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_path : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_cobble : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_paving : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
#endif
#endif

varying vec3 world_pos;
varying vec3 world_nor;
varying vec4 mix_w;
varying float woods;

// A tint chosen by eye turned into what the ground really reflects (the same sum as game/fantasy_ground.gd).
vec3 toned(vec3 c) {
	vec3 lin = pow(max(c, vec3(0.0)), vec3(2.2));
	float lum = dot(lin, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(lum), lin, 0.7) * 0.62;
}

// A texel made into detail around 1: its brightness against the set's mean brightness, with a little of its own hue
// (a per-channel gain alone turns the grey highlights of a brown rock blue).
vec3 detail(vec3 t, vec3 g) {
	const vec3 W = vec3(0.2126, 0.7152, 0.0722);
	float l = dot(t, W) / dot(1.0 / g, W);
	return mix(vec3(l), t * g, 0.3);
}

float hash12(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise (about 1 cell per unit): breaks up tiling and paints large patches.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 turned(vec2 p) {  // the second look at a texture: turned 37 degrees and shifted, so the two never repeat together
	return mat2(vec2(0.7986, 0.6018), vec2(-0.6018, 0.7986)) * p + vec2(17.3, 41.9);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mix_w = vec4(UV.x, 1.0 - UV.y, UV2.x, 1.0 - UV2.y);  // glTF stores v flipped (tools/blender/sea_isle_kit.py)
	woods = COLOR.a;
#ifdef NORMALS
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, -1.0);
#endif
}

void fragment() {
	vec3 shade = COLOR.rgb;
	vec2 p = world_pos.xz;
	float big = vnoise(p / 23.0);  // patches tens of metres across
	float mid = vnoise(p / 4.7);
	// sharp, ragged edges instead of the smooth fade between ground corners (it read as painted on)
	float path_raw = clamp(mix_w.a, 0.0, 1.0);
	float path_w = smoothstep(0.18, 0.55, path_raw + (mid - 0.5) * 0.35);
	float street_w = smoothstep(0.35, 0.6, clamp(mix_w.a - 1.0, 0.0, 1.0) + (mid - 0.5) * 0.12);
	float grass_w = smoothstep(0.25, 0.75, mix_w.r + (big - 0.5) * 0.3);
#ifdef TEXTURED
	vec2 face = abs(world_nor.x) > abs(world_nor.z) ? vec2(world_pos.z, world_pos.y) : vec2(world_pos.x, world_pos.y);
	float swap = smoothstep(0.3, 0.7, vnoise(p / 9.0));  // which of the two looks shows where
	vec3 sand = detail(mix(texture(tex_sand, p / tiles.x).rgb, texture(tex_sand, turned(p) / (tiles.x * 1.7)).rgb, swap), gain_sand) * toned(tint_sand);
	vec3 grass = detail(mix(texture(tex_grass, p / tiles.y).rgb, texture(tex_grass, turned(p) / (tiles.y * 1.6)).rgb, swap), gain_grass) * toned(tint_grass);
	grass *= mix(0.82, 1.12, big) * mix(0.94, 1.05, mid);  // light and dark meadow patches, sun-dried in places
	grass = mix(grass, grass * vec3(1.12, 1.02, 0.78), smoothstep(0.62, 0.85, big) * 0.6);
	vec3 rock = detail(mix(texture(tex_rock, face / tiles.z).rgb, texture(tex_rock, face / (tiles.z * 3.1)).rgb, 0.4), gain_rock) * toned(tint_rock);
	vec3 wet = detail(texture(tex_wet, p / tiles.w).rgb, gain_wet) * toned(tint_wet);
	vec3 path = detail(mix(texture(tex_path, p / tile_path).rgb, texture(tex_path, turned(p) / (tile_path * 1.5)).rgb, swap), gain_path) * toned(tint_path);
	vec3 floor_c = detail(texture(tex_forest, p / tile_forest).rgb, gain_forest) * toned(tint_forest);
	vec3 cobble = detail(texture(tex_cobble, p / tile_cobble).rgb, gain_cobble) * toned(vec3(0.43, 0.41, 0.37));
	vec3 slabs = detail(texture(tex_paving, p / tile_paving).rgb, gain_paving) * toned(vec3(0.5, 0.47, 0.42));
#else
	vec3 sand = toned(tint_sand);
	vec3 grass = toned(tint_grass) * mix(0.85, 1.1, big);
	vec3 rock = toned(tint_rock);
	vec3 wet = toned(tint_wet);
	vec3 path = toned(tint_path);
	vec3 floor_c = toned(tint_forest);
	vec3 cobble = toned(vec3(0.5, 0.47, 0.43));
	vec3 slabs = toned(vec3(0.62, 0.58, 0.52));
#endif
	path *= mix(0.88, 1.08, mid);
	vec3 c = mix(sand, wet, mix_w.b);
	c = mix(c, grass, grass_w);
	c = mix(c, floor_c, woods * grass_w);
	c = mix(c, path, path_w);
	float paved = paving > 0.5 ? street_w : 0.0;
	vec3 street = paving < 1.5 ? cobble : slabs;
	street *= mix(0.9, 1.06, big);  // wear: some stretches darker with traffic and damp
	c = mix(c, street, paved);
	c = mix(c, rock, mix_w.g);
	ALBEDO = c * shade;
#if defined(TEXTURED) && defined(NORMALS)
	vec3 n = mix(texture(nor_sand, p / tiles.x).rgb, texture(nor_grass, p / tiles.y).rgb, grass_w);
	n = mix(n, texture(nor_path, p / tile_path).rgb, path_w);
	n = mix(n, paving < 1.5 ? texture(nor_cobble, p / tile_cobble).rgb : texture(nor_paving, p / tile_paving).rgb, paved);
	NORMAL_MAP = mix(n, texture(nor_rock, face / tiles.z).rgb, mix_w.g);
	NORMAL_MAP_DEPTH = mix(1.0, 1.8, paved);
#endif
	ROUGHNESS = mix(mix(0.95, 0.55, mix_w.b), 0.8, paved);
	SPECULAR = 0.3;
}
"""

const LAYERS := {"sand": "g_sand", "grass": "g_grass", "rock": "g_rock", "wet": "g_coast", "path": "g_dirt", "forest": "g_forest", "cobble": "g_cobble", "paving": "g_paving"}
const TINTS := {"sand": "#e6d2a0", "grass": "#76a04c", "rock": "#8f8780", "wet": "#a08a68", "path": "#8c7454", "forest": "#6e6a3c"}

static var _materials := {}  # island id -> ShaderMaterial
static var _tints := {}  # island id -> {layer: Color}
static var _shaders := {}  # "#define ..." prefix -> Shader
static var _toon := false
static var _paving := {}  # island id -> 0 dirt / 1 cobbles / 2 flagstones on its town's streets


# The ground material of an island; `ground` = its data/sea/islands.json "ground" tints ({} = the defaults above).
static func material(island_id: String, ground: Dictionary) -> ShaderMaterial:
	if not _materials.has(island_id):
		var tints := {}
		for layer: String in TINTS:
			tints[layer] = Color.html(String(ground.get(layer, TINTS[layer])))
		_tints[island_id] = tints
		_materials[island_id] = ShaderMaterial.new()
		_fill(island_id)
	return _materials[island_id]


# The town's streets on an island (sea step 7b): 0 dirt, 1 cobbles, 2 flagstones.
static func set_paving(island_id: String, kind: int) -> void:
	_paving[island_id] = kind
	if _materials.has(island_id):
		(_materials[island_id] as ShaderMaterial).set_shader_parameter("paving", float(kind))


static func configure(toon: bool) -> void:
	_toon = toon
	for id: String in _materials:
		_fill(id)


static func _fill(island_id: String) -> void:
	var m: ShaderMaterial = _materials[island_id]
	var tints: Dictionary = _tints[island_id]
	for layer: String in tints:
		var c: Color = tints[layer]
		m.set_shader_parameter("tint_" + layer, Vector3(c.r, c.g, c.b))
	var textured := SurfaceLibrary.is_textured()
	var normals := textured and SurfaceLibrary.map_count() >= 2
	var tiles := Vector4(3, 3, 3, 3)
	var order := ["sand", "grass", "rock", "wet", "path", "forest", "cobble", "paving"]
	if textured:
		for i in order.size():
			var layer := String(order[i])
			var def := SurfaceLibrary.definition(String(LAYERS[layer]))
			var set_id := String(def.get("set", ""))
			var diff := SurfaceLibrary.texture(set_id, "diff")
			if diff == null:
				textured = false  # a set is missing on this machine: the plain tinted blend
				break
			if i < 4:
				tiles[i] = float(def.get("tile", 3.0))
			else:
				m.set_shader_parameter("tile_" + layer, float(def.get("tile", 3.0)))
			m.set_shader_parameter("tex_" + layer, diff)
			var gain := SurfaceLibrary.gain(String(LAYERS[layer]))
			m.set_shader_parameter("gain_" + layer, Vector3(gain.r, gain.g, gain.b))
			if (i < 3 or layer in ["path", "cobble", "paving"]) and normals:
				var nor := SurfaceLibrary.texture(set_id, "nor")
				if nor == null:
					normals = false
				else:
					m.set_shader_parameter("nor_" + layer, nor)
	m.set_shader_parameter("tiles", tiles)
	m.set_shader_parameter("paving", float(_paving.get(island_id, 0)))
	var prefix := ""
	if _toon:
		prefix += "#define TOON\n"
	if textured:
		prefix += "#define TEXTURED\n"
		if normals:
			prefix += "#define NORMALS\n"
	if not _shaders.has(prefix):
		var shader := Shader.new()
		shader.code = CODE.replace("shader_type spatial;", "shader_type spatial;\n" + prefix)
		_shaders[prefix] = shader
	m.shader = _shaders[prefix]
