# Purpose: the shine of the cosmetic card finishes (locked: rainbow foil 2 %, pony foil 0.2 % per pulled card): a
# canvas shader laid over a card face. RAINBOW = a holographic band of colours that slides across the card as the
# mouse moves over it, with a faint glitter. PONY = the pony guns' pastel bands (game/pony_skin.gd look) flowing all the
# time over the whole card with brighter sparkles and a slow pulse: an animated card. The band slides with time (the
# rainbow slowly, the pony fast). One material per finish and card size, shared by every face of that size.
# Dependencies: none.
extends RefCounted

const CODE := """
shader_type canvas_item;
uniform float pony = 0.0;
uniform vec2 card_size = vec2(600.0, 840.0);
varying vec2 local;
vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() {
	local = VERTEX / card_size;
}
void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float t = TIME * (0.25 + pony * 1.2);
	vec2 p = local;
	float band = (p.x * 0.8 + p.y * 1.2) * 3.0 - t;
	float hue = fract(band * 0.35 + (pony > 0.5 ? 0.82 + 0.18 * sin(band * 2.0) : 0.0));
	vec3 foil = hsv(hue, pony > 0.5 ? 0.45 : 0.7, 1.0);
	float sweep = pow(0.5 + 0.5 * sin(band * 2.2), pony > 0.5 ? 2.0 : 6.0);
	vec2 cell = floor(p * vec2(90.0, 126.0));
	float glitter = step(pony > 0.5 ? 0.985 : 0.993, hash(cell + floor(t * (pony > 0.5 ? 8.0 : 3.0))));
	float amount = (pony > 0.5 ? 0.38 + 0.1 * sin(TIME * 2.0) : 0.22) * sweep;
	float plaque = step(0.6, p.y) * step(p.y, 0.89) * step(0.12, p.x) * step(p.x, 0.88);
	amount *= 1.0 - plaque * 0.75;  // the rules text stays readable
	glitter *= 1.0 - plaque;
	vec3 col = base.rgb + foil * amount + vec3(glitter) * (0.6 + pony * 0.6);
	COLOR = vec4(col, base.a);
}
"""

static var _materials: Dictionary = {}


# finish = "rainbow" or "pony"; returns the shared material for faces of this size ("" = none).
static func material(finish: String, face_size: Vector2) -> ShaderMaterial:
	if finish == "":
		return null
	var key := "%s %dx%d" % [finish, int(face_size.x), int(face_size.y)]
	if not _materials.has(key):
		var shader := Shader.new()
		shader.code = CODE
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("pony", 1.0 if finish == "pony" else 0.0)
		m.set_shader_parameter("card_size", face_size)
		_materials[key] = m
	return _materials[key]
