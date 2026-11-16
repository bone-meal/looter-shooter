# Purpose: the ground material of the sea's island kit (director: textured blend ground + per-island tints). Per pixel
# it blends five surfaces of data/surfaces.json: sand, grass above the beach, rock on steep slopes (read on the cliff
# face, not from above), wet sand at the waterline and the trodden ground of paths; each layer is coloured by the
# island's own tint (data/sea/islands.json "ground") and the model's vertex colour adds light and dark patches. The
# weights come per corner from the model (tools/blender/sea_isle_kit.py): UV = (grass, rock), UV2 = (wet, trodden),
# vertex alpha = forest floor.
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

#ifdef TEXTURED
uniform vec4 tiles = vec4(3.0);
uniform float tile_path = 3.0;
uniform float tile_forest = 3.0;
uniform vec3 gain_sand = vec3(1.0);
uniform vec3 gain_grass = vec3(1.0);
uniform vec3 gain_rock = vec3(1.0);
uniform vec3 gain_wet = vec3(1.0);
uniform vec3 gain_path = vec3(1.0);
uniform vec3 gain_forest = vec3(1.0);
uniform sampler2D tex_sand : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_grass : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_rock : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_wet : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_path : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_forest : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
#ifdef NORMALS
uniform sampler2D nor_sand : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_grass : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_rock : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
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
#ifdef TEXTURED
	vec2 p = world_pos.xz;
	// rock is read on the face it stands in (x or z facing), so cliffs are not smeared
	vec2 face = abs(world_nor.x) > abs(world_nor.z) ? vec2(world_pos.z, world_pos.y) : vec2(world_pos.x, world_pos.y);
	vec3 sand = detail(mix(texture(tex_sand, p / tiles.x).rgb, texture(tex_sand, p / (tiles.x * 5.3)).rgb, 0.4), gain_sand) * toned(tint_sand);
	vec3 grass = detail(mix(texture(tex_grass, p / tiles.y).rgb, texture(tex_grass, p / (tiles.y * 5.3)).rgb, 0.45), gain_grass) * toned(tint_grass);
	vec3 rock = detail(mix(texture(tex_rock, face / tiles.z).rgb, texture(tex_rock, face / (tiles.z * 4.1)).rgb, 0.35), gain_rock) * toned(tint_rock);
	vec3 wet = detail(texture(tex_wet, p / tiles.w).rgb, gain_wet) * toned(tint_wet);
	vec3 path = detail(texture(tex_path, p / tile_path).rgb, gain_path) * toned(tint_path);
	vec3 floor_c = detail(texture(tex_forest, p / tile_forest).rgb, gain_forest) * toned(tint_forest);
#else
	vec3 sand = toned(tint_sand);
	vec3 grass = toned(tint_grass);
	vec3 rock = toned(tint_rock);
	vec3 wet = toned(tint_wet);
	vec3 path = toned(tint_path);
	vec3 floor_c = toned(tint_forest);
#endif
	vec3 c = mix(sand, wet, mix_w.b);
	c = mix(c, grass, mix_w.r);
	c = mix(c, floor_c, woods * mix_w.r);
	c = mix(c, path, mix_w.a);
	c = mix(c, rock, mix_w.g);
	ALBEDO = c * shade;
#if defined(TEXTURED) && defined(NORMALS)
	vec3 n = mix(texture(nor_sand, p / tiles.x).rgb, texture(nor_grass, p / tiles.y).rgb, mix_w.r);
	NORMAL_MAP = mix(n, texture(nor_rock, face / tiles.z).rgb, mix_w.g);
#endif
	ROUGHNESS = mix(0.95, 0.55, mix_w.b);
	SPECULAR = 0.3;
}
"""

const LAYERS := {"sand": "g_sand", "grass": "g_grass", "rock": "g_rock", "wet": "g_coast", "path": "g_dirt", "forest": "g_forest"}
const TINTS := {"sand": "#e6d2a0", "grass": "#76a04c", "rock": "#8f8780", "wet": "#a08a68", "path": "#8c7454", "forest": "#6e6a3c"}

static var _materials := {}  # island id -> ShaderMaterial
static var _tints := {}  # island id -> {layer: Color}
static var _shaders := {}  # "#define ..." prefix -> Shader
static var _toon := false


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
	var order := ["sand", "grass", "rock", "wet", "path", "forest"]
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
			if i < 3 and normals:
				var nor := SurfaceLibrary.texture(set_id, "nor")
				if nor == null:
					normals = false
				else:
					m.set_shader_parameter("nor_" + layer, nor)
	m.set_shader_parameter("tiles", tiles)
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
