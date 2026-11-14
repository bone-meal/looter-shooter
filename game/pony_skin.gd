# Purpose: the animated "cool skin" for pony-tier guns: pastel iridescent bands that flow along the gun plus sparkles,
# in the colours of the gun's pony family (data/pony_families.json: hue, span, sat). Applied to the world drop model
# and the held gun model.
# Dependencies: none (one shader; one material per family, built on first use).
extends RefCounted

const CODE := """
shader_type spatial;
uniform float hue_mid = 0.82;
uniform float hue_span = 0.18;
uniform float sat = 0.45;
varying vec3 lp;
vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}
void vertex() {
	lp = VERTEX;
}
void fragment() {
	float band = lp.z * 7.0 + lp.y * 5.0 - TIME * 1.6;
	float hue = fract(hue_mid + hue_span * sin(band) + TIME * 0.05 * hue_span);
	vec3 c = hsv(hue, sat, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float spark = step(0.975, fract(sin(dot(floor(lp * 70.0), vec3(12.9898, 78.233, 37.719)) + floor(TIME * 6.0) * 0.37) * 43758.5453));
	ALBEDO = c * 0.55;
	EMISSION = c * (0.4 + 0.5 * fres) + vec3(spark);
}
"""

static var _shader: Shader
static var _mats := {}  # family id ("" = the old pastel look) -> its material


# The skin's material for a family ({} look = the old pastel one).
static func material(family: String = "", look: Dictionary = {}) -> ShaderMaterial:
	if not _mats.has(family):
		if _shader == null:
			_shader = Shader.new()
			_shader.code = CODE
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		if not look.is_empty():
			mat.set_shader_parameter("hue_mid", float(look.get("hue", 0.82)))
			mat.set_shader_parameter("hue_span", float(look.get("span", 0.18)))
			mat.set_shader_parameter("sat", float(look.get("sat", 0.45)))
		_mats[family] = mat
	return _mats[family]


# Puts the skin on every mesh under `node` (or removes it again when `on` is false); `look` = the family's colours.
static func apply(node: Node, on: bool, family: String = "", look: Dictionary = {}) -> void:
	_put(node, material(family, look) if on else null)


static func _put(node: Node, mat: ShaderMaterial) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_put(c, mat)
