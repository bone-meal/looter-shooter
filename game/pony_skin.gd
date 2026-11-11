# Purpose: the animated "cool skin" for pony-tier guns: pastel iridescent bands that flow along the gun plus sparkles. Applied to the world drop model and the held gun model.
# Dependencies: none (one shared shader material, built on first use).
extends RefCounted

const CODE := """
shader_type spatial;
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
	float hue = fract(0.82 + 0.18 * sin(band) + TIME * 0.05);
	vec3 c = hsv(hue, 0.45, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float spark = step(0.975, fract(sin(dot(floor(lp * 70.0), vec3(12.9898, 78.233, 37.719)) + floor(TIME * 6.0) * 0.37) * 43758.5453));
	ALBEDO = c * 0.55;
	EMISSION = c * (0.4 + 0.5 * fres) + vec3(spark);
}
"""

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = CODE
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat


# Puts the skin on every mesh under `node` (or removes it again when `on` is false).
static func apply(node: Node, on: bool) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material() if on else null
	for c in node.get_children():
		apply(c, on)
