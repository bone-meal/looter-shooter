# Purpose: the island kit's fresh water (director: rivers, a waterfall, tide pools on the start island): see-through
# water that streams along its strip (the models' UV v runs with the flow, tools/blender/sea_isle_kit.py water_strip),
# white water where it breaks, a waterfall that falls fast and foams. One shared material per kind ("water" = rivers
# and pools, "waterfall"), a small seamless noise texture made once. The sea itself is game/sea_ocean.gd.
# Dependencies: none.
extends RefCounted

const CODE := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.16, 0.42, 0.46);
uniform vec3 foam : source_color = vec3(0.92, 0.96, 0.96);
uniform float speed = 0.35;
uniform float froth = 0.0;
uniform float clear = 0.72;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;

void fragment() {
	vec2 a = vec2(UV.x * 0.6, UV.y * 0.35 - TIME * speed * 0.3);
	vec2 b = vec2(UV.x * 0.9 + 0.37, UV.y * 0.6 - TIME * speed * 0.55);
	float n1 = texture(grain, a).r;
	float n2 = texture(grain, b).r;
	float edge = smoothstep(0.78, 1.0, abs(UV.x * 2.0 - 1.0));
	float white = clamp(smoothstep(0.62, 0.82, n1 * 0.55 + n2 * 0.55) + edge * 0.6 + froth * smoothstep(0.35, 0.7, n2), 0.0, 1.0);
	ALBEDO = mix(deep, foam, white);
	ALPHA = mix(clear, 0.96, white);
	ROUGHNESS = mix(0.06, 0.6, white);
	SPECULAR = 0.6;
	NORMAL_MAP = vec3(0.5 + (n1 - 0.5) * 0.5, 0.5 + (n2 - 0.5) * 0.5, 1.0);
}
"""

static var _shader: Shader
static var _grain: NoiseTexture2D
static var _made := {}  # kind -> ShaderMaterial


static func material(kind: String) -> ShaderMaterial:
	if _made.has(kind):
		return _made[kind]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
		var noise := FastNoiseLite.new()
		noise.frequency = 0.03
		_grain = NoiseTexture2D.new()
		_grain.width = 128
		_grain.height = 128
		_grain.seamless = true
		_grain.noise = noise
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("grain", _grain)
	match kind:
		"waterfall":
			m.set_shader_parameter("speed", 3.2)
			m.set_shader_parameter("froth", 0.8)
			m.set_shader_parameter("clear", 0.82)
		"pool":
			m.set_shader_parameter("speed", 0.03)
			m.set_shader_parameter("clear", 0.6)
	_made[kind] = m
	return m
