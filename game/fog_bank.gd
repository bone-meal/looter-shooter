# Purpose: a FOG BANK you can see from afar and sail into (sea step 11, the crossing): a cluster of big soft
# see-through mounds of mist, brighter at their edges, slowly drifting. Drawing only: what happens inside is decided
# by the session (game/crossing.gd on the islands, the sail-back bank at sea). Pooled meshes, one shared material.
# Dependencies: none.
extends Node3D

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 col : source_color = vec4(0.86, 0.9, 0.93, 1.0);
uniform float strength = 0.55;
void fragment() {
	float edge = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = col.rgb;
	ALPHA = strength * smoothstep(0.0, 0.9, edge) * col.a;
}
"""

var _parts: Array = []  # [MeshInstance3D, base position, drift phase]
var _t := 0.0


# radius = how far the bank spreads (m); puffs = how many mounds; height = how tall they stand.
func build(radius: float, puffs: int, height: float, color: Color) -> void:
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("col", color)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in puffs:
		var mi := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radial_segments = 16
		ball.rings = 8
		var r := rng.randf_range(radius * 0.35, radius * 0.6)
		ball.radius = r
		ball.height = r * 2.0
		mi.mesh = ball
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * float(i) / float(puffs) + rng.randf_range(-0.3, 0.3)
		var d := rng.randf_range(0.0, radius * 0.6)
		var at := Vector3(cos(a) * d, height * rng.randf_range(0.2, 0.45), sin(a) * d)
		mi.position = at
		mi.scale = Vector3(1.0, height / (2.0 * r) * rng.randf_range(0.8, 1.2), 1.0)
		add_child(mi)
		_parts.append([mi, at, rng.randf_range(0.0, TAU)])


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	for p: Array in _parts:
		var mi: MeshInstance3D = p[0]
		var base: Vector3 = p[1]
		mi.position = base + Vector3(sin(_t * 0.07 + float(p[2])) * 3.0, sin(_t * 0.11 + float(p[2])) * 0.6, cos(_t * 0.05 + float(p[2])) * 3.0)
