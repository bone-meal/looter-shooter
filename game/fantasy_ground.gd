# Purpose: the ground material of the fantasy world. With textures on, each piece of land blends four surfaces of
# data/surfaces.json per pixel: the ground of its two nearest regions, rock on steep slopes and the trodden ground of
# places and paths; the land's own colour (per corner) tints all of it, so regions keep their colours and distant flat
# land matches. Without textures it is the plain coloured land. One shader source with #defines, valid in
# Compatibility and Forward+.
# Dependencies: game/surface_library.gd (texture sets, gains, current quality). Configured by game/render_style.gd.
# The mix weights come per corner from game/fantasy_land.gd (CUSTOM0: second region, rock, trodden).
extends RefCounted

const SurfaceLibrary = preload("res://game/surface_library.gd")

const CODE := """
shader_type spatial;
#ifdef TOON
render_mode cull_back, diffuse_toon, specular_toon;
#else
render_mode cull_back;
#endif

#ifdef TEXTURED
uniform vec4 tiles = vec4(3.0);
uniform vec3 gain_a = vec3(1.0);
uniform vec3 gain_b = vec3(1.0);
uniform vec3 gain_rock = vec3(1.0);
uniform vec3 gain_yard = vec3(1.0);
uniform sampler2D tex_a : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_b : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_rock : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_yard : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
#ifdef NORMALS
uniform sampler2D nor_a : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_b : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_rock : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nor_yard : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
#endif
#endif

varying vec3 world_pos;
varying vec4 mix_w;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mix_w = CUSTOM0;
#ifdef NORMALS
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, -1.0);
#endif
}

// A land colour chosen by eye turned into what the ground really reflects (the models are baked with the same sum:
// tools/blender/fantasy_kit.py real).
vec3 toned(vec3 c) {
	vec3 lin = pow(max(c, vec3(0.0)), vec3(2.2));
	float lum = dot(lin, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(lum), lin, 0.7) * 0.62;
}

void fragment() {
#ifdef TEXTURED
	vec2 p = world_pos.xz;
	vec2 steep = vec2(world_pos.x + world_pos.z, world_pos.y);
	// each ground is read twice, once large: the large copy hides the repeat in the distance
	vec3 a = mix(texture(tex_a, p / tiles.x).rgb, texture(tex_a, p / (tiles.x * 5.3)).rgb, 0.45) * gain_a;
	vec3 b = mix(texture(tex_b, p / tiles.y).rgb, texture(tex_b, p / (tiles.y * 5.3)).rgb, 0.45) * gain_b;
	vec3 grain = mix(a, b, mix_w.r);
	grain = mix(grain, texture(tex_rock, steep / tiles.z).rgb * gain_rock, mix_w.g);
	grain = mix(grain, texture(tex_yard, p / tiles.w).rgb * gain_yard, mix_w.b);
	ALBEDO = grain * toned(COLOR.rgb);
#ifdef NORMALS
	vec3 n = mix(texture(nor_a, p / tiles.x).rgb, texture(nor_b, p / tiles.y).rgb, mix_w.r);
	n = mix(n, texture(nor_rock, steep / tiles.z).rgb, mix_w.g);
	NORMAL_MAP = mix(n, texture(nor_yard, p / tiles.w).rgb, mix_w.b);
#endif
	ROUGHNESS = 0.94;
	SPECULAR = 0.3;
#else
	ALBEDO = toned(COLOR.rgb);
	ROUGHNESS = 1.0;
#endif
}
"""

const ROCK := "g_rock"

static var _materials := {}  # "a|b|yard" -> ShaderMaterial
static var _shaders := {}  # "#define ..." prefix -> Shader
static var _toon := false


# The material for land whose two regions use surfaces `a` and `b` and whose trodden ground is `yard`.
static func material(a: String, b: String, yard: String) -> ShaderMaterial:
	var key := "%s|%s|%s" % [a, b, yard]
	if not _materials.has(key):
		_materials[key] = ShaderMaterial.new()
		_fill(key)
	return _materials[key]


# The same sum as the shader's toned(): for things coloured from the land's palette outside this shader (grass tufts).
static func toned(c: Color) -> Color:
	var lin := Color(pow(c.r, 2.2), pow(c.g, 2.2), pow(c.b, 2.2))
	var lum := 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
	return Color(lerpf(lum, lin.r, 0.7) * 0.62, lerpf(lum, lin.g, 0.7) * 0.62, lerpf(lum, lin.b, 0.7) * 0.62)


static func configure(toon: bool) -> void:
	_toon = toon
	for key: String in _materials:
		_fill(key)


static func _fill(key: String) -> void:
	var m: ShaderMaterial = _materials[key]
	var names := key.split("|")
	var ids := [names[0], names[1], ROCK, names[2]]
	var slots := ["a", "b", "rock", "yard"]
	var textured := SurfaceLibrary.is_textured()
	var normals := textured and SurfaceLibrary.map_count() >= 2
	var tiles := Vector4(3, 3, 3, 3)
	if textured:
		for i in 4:
			var def := SurfaceLibrary.definition(String(ids[i]))
			var set_id := String(def.get("set", ""))
			var diff := SurfaceLibrary.texture(set_id, "diff")
			if diff == null:
				textured = false  # a set is missing on this machine: plain coloured land
				break
			tiles[i] = float(def.get("tile", 3.0))
			m.set_shader_parameter("tex_" + String(slots[i]), diff)
			var gain := SurfaceLibrary.gain(String(ids[i]))
			m.set_shader_parameter("gain_" + String(slots[i]), Vector3(gain.r, gain.g, gain.b))
			var nor := SurfaceLibrary.texture(set_id, "nor") if normals else null
			if nor == null:
				normals = false
			else:
				m.set_shader_parameter("nor_" + String(slots[i]), nor)
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
