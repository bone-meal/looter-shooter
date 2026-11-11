# Purpose: the shared ocean material. configure() switches it in place between a flat colour (old look, Potato tier)
# and moving water: two drifting wave normal layers, colour that deepens with the real water depth, and foam where
# the water meets the shore. One shader source, compiled with #defines, valid in Compatibility and Forward+.
# Dependencies: none. Configured by game/render_style.gd.
extends RefCounted

const CODE := """
shader_type spatial;
#ifdef TOON
render_mode cull_back, diffuse_toon, specular_toon;
#else
render_mode cull_back;
#endif

uniform vec3 flat_color : source_color = vec3(0.1, 0.45, 0.7);
#ifdef WAVES
uniform vec3 shallow_color : source_color = vec3(0.13, 0.5, 0.5);
uniform vec3 deep_color : source_color = vec3(0.015, 0.11, 0.2);
uniform sampler2D wave_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float wave_size = 9.0;
uniform float wave_speed = 0.35;
uniform float wave_strength = 0.6;
uniform float clarity = 4.0;
uniform float foam_width = 0.3;
#endif

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
#ifdef WAVES
	vec2 uv = world_pos.xz / wave_size;
	vec2 drift = vec2(TIME * wave_speed / wave_size);
	vec3 n1 = texture(wave_normal, uv + drift * vec2(1.0, 0.35)).rgb;
	vec3 n2 = texture(wave_normal, uv * 2.3 - drift * vec2(0.4, 1.0)).rgb;
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = wave_strength;
	float raw = texture(depth_tex, SCREEN_UV).x;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
#endif
	vec4 behind = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	behind.xyz /= behind.w;
	float water_depth = max(VERTEX.z - behind.z, 0.0);
	float deep = clamp(water_depth / clarity, 0.0, 1.0);
	float foam = (1.0 - smoothstep(0.0, foam_width, water_depth)) * 0.75;
	ALBEDO = mix(mix(shallow_color, deep_color, deep), vec3(0.95), foam);
	ALPHA = clamp(0.35 + 0.63 * deep + foam, 0.0, 1.0);
	ROUGHNESS = mix(0.07, 0.6, foam);
	SPECULAR = 0.5;
#else
	ALBEDO = flat_color;
	ROUGHNESS = 0.3;
#endif
}
"""

static var _material: ShaderMaterial
static var _shaders := {}  # "#define ..." prefix -> Shader
static var _detail := 0
static var _toon := false


# The one ocean material. `flat` is its colour in the flat look.
static func material(flat: Color) -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.set_shader_parameter("flat_color", flat)
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.012
		noise.fractal_octaves = 4
		var waves := NoiseTexture2D.new()
		waves.width = 512
		waves.height = 512
		waves.seamless = true
		waves.as_normal_map = true
		waves.bump_strength = 5.0
		waves.generate_mipmaps = true
		waves.noise = noise
		_material.set_shader_parameter("wave_normal", waves)
		_use_shader()
	return _material


# detail 0 = flat colour, 1 or more = moving water. toon keeps the cel-shaded lighting of the toon presets.
static func configure(detail: int, toon: bool) -> void:
	_detail = detail
	_toon = toon
	if _material != null:
		_use_shader()


static func _use_shader() -> void:
	var defines := ""
	if _detail > 0:
		defines += "#define WAVES\n"
	if _toon:
		defines += "#define TOON\n"
	if not _shaders.has(defines):
		var shader := Shader.new()
		shader.code = defines + CODE
		_shaders[defines] = shader
	_material.shader = _shaders[defines]
