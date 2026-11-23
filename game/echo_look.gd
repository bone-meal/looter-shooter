# Purpose: the translucent blue ECHO look (not game/ghost_look.gd, the sea's ghost ships) (polish1 E4, items 131 / 133): ghost trophies and the spectral set worn by
# players, and the phantom bosses. One shared material: see-through blue, brighter at the edges (a rim), a slow shimmer
# drifting up; skinned pieces keep their bones. Cheap: no textures, no extra passes, no shadows.
# Dependencies: none.
extends RefCounted

const CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.45, 0.72, 1.0, 1.0);
uniform float body = 0.28;
uniform float rim = 0.75;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float edge = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	edge = edge * edge;
	float shimmer = 0.5 + 0.5 * sin(wpos.y * 9.0 - TIME * 2.2 + sin(wpos.x * 3.0 + wpos.z * 2.0));
	ALBEDO = tint.rgb * (0.55 + 0.45 * shimmer) + vec3(0.35, 0.5, 0.7) * edge;
	ALPHA = clamp(body + shimmer * 0.08 + edge * rim, 0.0, 0.92);
}
"""

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
	return _material


# Every mesh under `node` (a crown, a whole creature's model) takes the echo look.
static func cover(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = material()
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		cover(child)
