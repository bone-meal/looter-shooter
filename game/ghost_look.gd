# Purpose: THE GHOSTLY LOOK (sea step 8d; director: ghost ships phase in and out, see-through and glowing): a ghost
# ship drawn in one pale, glowing, see-through material whose strength follows her phase (faded 0 .. solid 1), and
# a ghost crewman with a cold glow laid over his body (his own colours kept under it, so hit flashes still show).
# Dependencies: none (Godot materials only).
extends RefCounted

const FADED_ALPHA := 0.14
const SOLID_ALPHA := 0.6
const GLOW := Color(0.45, 1.0, 0.85)

static var _crew_glow: StandardMaterial3D


# A ship's own material for her phase: every mesh of hers shares it (made once per ship, kept in her meta).
static func ship(node: Node3D, phase: float) -> void:
	var mat: StandardMaterial3D = node.get_meta("ghost_mat") if node.has_meta("ghost_mat") else null
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		node.set_meta("ghost_mat", mat)
		node.set_meta("ghost_phase", -1.0)
	if absf(float(node.get_meta("ghost_phase")) - phase) < 0.01:
		return
	node.set_meta("ghost_phase", phase)
	var p := clampf(phase, 0.0, 1.0)
	mat.albedo_color = Color(GLOW.r * (0.55 + 0.45 * p), GLOW.g * (0.7 + 0.3 * p), GLOW.b * (0.7 + 0.3 * p), lerpf(FADED_ALPHA, SOLID_ALPHA, p))
	for mesh: Node in node.find_children("*", "GeometryInstance3D", true, false):
		if (mesh as GeometryInstance3D).material_override != mat and not mesh.has_meta("not_ghost"):
			(mesh as GeometryInstance3D).material_override = mat
			(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# A ghost crewman: a cold additive glow over his body (one shared material).
static func body(node: Node3D) -> void:
	if _crew_glow == null:
		_crew_glow = StandardMaterial3D.new()
		_crew_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_crew_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_crew_glow.albedo_color = Color(0.12, 0.42, 0.34)
	for mesh: Node in node.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).material_overlay = _crew_glow
		(mesh as GeometryInstance3D).transparency = 0.35
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
