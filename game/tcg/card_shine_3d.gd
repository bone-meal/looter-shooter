# Purpose: the cosmetic foils (rainbow 2 %, pony 0.2 %) on the 3D card table: the same moving shine as the flat cards
# (game/tcg/card_shine.gd), as a spatial material over a baked card picture, so foils move on the table too. PONY flows
# fast with sparkles and a pulse (an animated card), RAINBOW slides slowly. One material per picture and finish (kept
# for the last 48 pictures, like the baker).
# Dependencies: none.
extends RefCounted

const CODE := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D picture : source_color, filter_linear_mipmap;
uniform float pony = 0.0;
vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec4 base = texture(picture, UV);
	float t = TIME * (0.25 + pony * 1.2);
	vec2 p = UV;
	float band = (p.x * 0.8 + p.y * 1.2) * 3.0 - t;
	float hue = fract(band * 0.35 + (pony > 0.5 ? 0.82 + 0.18 * sin(band * 2.0) : 0.0));
	vec3 foil = hsv(hue, pony > 0.5 ? 0.45 : 0.7, 1.0);
	float sweep = pow(0.5 + 0.5 * sin(band * 2.2), pony > 0.5 ? 2.0 : 6.0);
	vec2 cell = floor(p * vec2(60.0, 84.0));
	float glitter = step(pony > 0.5 ? 0.985 : 0.993, hash(cell + floor(t * (pony > 0.5 ? 8.0 : 3.0))));
	float amount = (pony > 0.5 ? 0.38 + 0.1 * sin(TIME * 2.0) : 0.22) * sweep;
	float plaque = step(0.6, p.y) * step(p.y, 0.89) * step(0.12, p.x) * step(p.x, 0.88);
	amount *= 1.0 - plaque * 0.75;
	glitter *= 1.0 - plaque;
	ALBEDO = base.rgb + foil * amount + vec3(glitter) * (0.6 + pony * 0.6);
	ROUGHNESS = 0.45;
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""

static var _shader: Shader
static var _materials := {}


# The foil material for a baked card picture; finish "rainbow" or "pony".
static func material(picture: Texture2D, finish: String) -> ShaderMaterial:
	var key := "%d %s" % [picture.get_rid().get_id(), finish]
	if not _materials.has(key):
		if _shader == null:
			_shader = Shader.new()
			_shader.code = CODE
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("picture", picture)
		m.set_shader_parameter("pony", 1.0 if finish == "pony" else 0.0)
		_materials[key] = m
		if _materials.size() > 48:
			_materials.erase(_materials.keys()[0])
	return _materials[key]
