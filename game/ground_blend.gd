# Purpose: the material of the island ground. Blends three surfaces of data/surfaces.json per pixel: beach sand, a grass
# patch with a ragged edge around the island centre, and darker wet sand at the waterline. Flat look = one sand colour.
# One shader source compiled with #defines, valid in Compatibility and Forward+.
# Dependencies: game/surface_library.gd (texture sets and current quality). Configured by game/render_style.gd after it.
extends RefCounted

const SurfaceLibrary = preload("res://game/surface_library.gd")

const LAYERS := ["sand", "grass", "shore"]
const SURFACES := {"sand": "island_sand", "grass": "island_grass", "shore": "island_shore"}

const CODE := """
shader_type spatial;
#ifdef TOON
render_mode cull_back, diffuse_toon, specular_toon;
#else
render_mode cull_back;
#endif

uniform vec3 flat_color : source_color = vec3(0.9, 0.8, 0.55);
#ifdef TEXTURED
uniform vec2 patch_center = vec2(0.0);
uniform float patch_radius = 9.0;
uniform float water_level = -0.4;
uniform vec3 tiles = vec3(1.5, 2.0, 7.5);
uniform vec3 sand_tint : source_color = vec3(1.0);
uniform vec3 grass_tint : source_color = vec3(1.0);
uniform vec3 shore_tint : source_color = vec3(1.0);
uniform sampler2D sand_diff : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_diff : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D shore_diff : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
#ifdef NORMALS
uniform sampler2D sand_nor : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_nor : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D shore_nor : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
#endif
#ifdef ARM
uniform sampler2D sand_arm : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_arm : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D shore_arm : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
#endif
#endif

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#ifdef NORMALS
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, -1.0);
#endif
}

void fragment() {
#ifdef TEXTURED
	vec2 p = world_pos.xz;
	vec2 uv_sand = p / tiles.x;
	vec2 uv_grass = p / tiles.y;
	vec2 uv_shore = p / tiles.z;
	float ragged = texture(grass_diff, p / (tiles.y * 6.3)).g;
	float from_center = distance(p, patch_center) + (ragged - 0.3) * 6.0;
	float grass = 1.0 - smoothstep(patch_radius - 1.0, patch_radius + 1.0, from_center);
	float above = world_pos.y - water_level;
	float shore = 1.0 - smoothstep(0.08, 0.5, above);
	float wet = 1.0 - smoothstep(-0.05, 0.2, above);
	vec3 color = mix(texture(sand_diff, uv_sand).rgb * sand_tint, texture(grass_diff, uv_grass).rgb * grass_tint, grass);
	color = mix(color, texture(shore_diff, uv_shore).rgb * shore_tint, shore);
	ALBEDO = color * mix(1.0, 0.62, wet);
	float rough = 0.92;
#ifdef NORMALS
	vec3 n = mix(texture(sand_nor, uv_sand).rgb, texture(grass_nor, uv_grass).rgb, grass);
	NORMAL_MAP = mix(n, texture(shore_nor, uv_shore).rgb, shore);
#endif
#ifdef ARM
	vec3 arm = mix(texture(sand_arm, uv_sand).rgb, texture(grass_arm, uv_grass).rgb, grass);
	arm = mix(arm, texture(shore_arm, uv_shore).rgb, shore);
	AO = arm.r;
	rough = arm.g;
#endif
	ROUGHNESS = mix(rough, 0.3, wet);
	SPECULAR = 0.4;
#else
	ALBEDO = flat_color;
	ROUGHNESS = 1.0;
#endif
}
"""

static var _material: ShaderMaterial
static var _shaders := {}  # "#define ..." prefix -> Shader
static var _toon := false


# The one island ground material. center = world x,z of the grass patch.
static func material(flat: Color, center: Vector2, grass_radius: float, water_level: float) -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
	_material.set_shader_parameter("flat_color", flat)
	_material.set_shader_parameter("patch_center", center)
	_material.set_shader_parameter("patch_radius", grass_radius)
	_material.set_shader_parameter("water_level", water_level)
	_refresh()
	return _material


static func configure(toon: bool) -> void:
	_toon = toon
	if _material != null:
		_refresh()


static func _refresh() -> void:
	var maps := SurfaceLibrary.map_count()
	var textured := SurfaceLibrary.is_textured()
	var tiles := Vector3.ONE
	if textured:
		for i in LAYERS.size():
			var layer := String(LAYERS[i])
			var def := SurfaceLibrary.definition(String(SURFACES[layer]))
			var set_id := String(def.get("set", ""))
			var diff := SurfaceLibrary.texture(set_id, "diff")
			if diff == null:
				textured = false
				break
			tiles[i] = maxf(float(def.get("tile", 2.0)), 0.01)
			_material.set_shader_parameter(layer + "_tint", Color.html(String(def.get("tint", "#ffffff"))))
			_material.set_shader_parameter(layer + "_diff", diff)
			if maps >= 2:
				_material.set_shader_parameter(layer + "_nor", SurfaceLibrary.texture(set_id, "nor"))
			if maps >= 3:
				_material.set_shader_parameter(layer + "_arm", SurfaceLibrary.texture(set_id, "arm"))
	_material.set_shader_parameter("tiles", tiles)
	var defines := ""
	if textured:
		defines += "#define TEXTURED\n"
		if maps >= 2:
			defines += "#define NORMALS\n"
		if maps >= 3:
			defines += "#define ARM\n"
	if _toon:
		defines += "#define TOON\n"
	if not _shaders.has(defines):
		var shader := Shader.new()
		shader.code = defines + CODE
		_shaders[defines] = shader
	_material.shader = _shaders[defines]
