# Purpose: THE GHOSTLY LOOK (sea step 8d; director: ghost ships phase in and out, see-through and glowing): a ghost
# ship drawn in pale glowing see-through materials whose strength follows her phase (faded 0 .. solid 1): the hull
# and rigging with a mottled rot pattern, the sails TORN (holes from a noise mask), a cold lantern at her stern (bulb
# and halo) that brightens as she turns solid, and a slow flicker. Ghost crewmen get a cold glow over their own colours (hit flashes
# still show), and spectral flotsam the same glow. Her crew and anything else of the game's (meta "sea") riding her
# keep their own look.
# Dependencies: none (Godot materials, noise textures; the lantern is a glowing bulb + an additive halo, no real light:
# an OmniLight3D redraws everything it reaches on Compatibility).
extends RefCounted

const FADED_ALPHA := 0.16
const SOLID_ALPHA := 0.62
const GLOW := Color(0.45, 1.0, 0.85)

static var _crew_glow: StandardMaterial3D
static var _rot: NoiseTexture2D
static var _tears: NoiseTexture2D


static func _texture(holes: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR if holes else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035 if holes else 0.02
	noise.seed = 17 if holes else 5
	var ramp := Gradient.new()
	if holes:  # torn: the darkest cells are holes (alpha 0), the rest cloth
		ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		ramp.set_color(0, Color(1, 1, 1, 0))
		ramp.set_offset(0, 0.0)
		ramp.set_color(1, Color(1, 1, 1, 1))
		ramp.set_offset(1, 0.32)
	else:  # rot: mottled light and dark
		ramp.set_color(0, Color(0.45, 0.45, 0.45))
		ramp.set_color(1, Color(1, 1, 1))
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


static func _material(texture: NoiseTexture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = texture
	mat.uv1_triplanar = true  # (the ship models' own UVs are not laid out for a pattern)
	mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	return mat


# A ship's look for her phase (called every frame while she is shown): materials and lantern made once.
static func ship(node: Node3D, phase: float) -> void:
	if not node.has_meta("ghost_mat"):
		_dress(node)
	var hull: StandardMaterial3D = node.get_meta("ghost_mat")
	var cloth: StandardMaterial3D = node.get_meta("ghost_sail")
	var halo: StandardMaterial3D = node.get_meta("ghost_lamp")
	var p := clampf(phase, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	var flicker := 1.0 + 0.12 * sin(t * 7.3 + float(node.get_instance_id() % 97)) * sin(t * 2.1)
	var colour := Color(GLOW.r * (0.55 + 0.45 * p), GLOW.g * (0.7 + 0.3 * p), GLOW.b * (0.7 + 0.3 * p), clampf(lerpf(FADED_ALPHA, SOLID_ALPHA, p) * flicker, 0.0, 1.0))
	hull.albedo_color = colour
	cloth.albedo_color = Color(colour.r * 0.9, colour.g, colour.b, colour.a * 0.85)
	halo.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, clampf((0.25 + 0.6 * p) * flicker, 0.0, 1.0))


static func _dress(node: Node3D) -> void:
	if _rot == null:
		_rot = _texture(false)
		_tears = _texture(true)
	var hull := _material(_rot)
	var cloth := _material(_tears)
	node.set_meta("ghost_mat", hull)
	node.set_meta("ghost_sail", cloth)
	var sails: Array = node.call("sail_meshes") if node.has_method("sail_meshes") else []
	for mesh: Node in node.find_children("*", "GeometryInstance3D", true, false):
		if _game_thing(mesh, node):
			continue
		(mesh as GeometryInstance3D).material_override = cloth if sails.has(mesh) else hull
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spec: Dictionary = node.get("spec") if node.get("spec") is Dictionary else {}
	var outline: Array = spec.get("outline", [[6.0, 0.0]])
	var lamp := Node3D.new()  # her stern lantern: a cold bulb and a halo round it
	lamp.position = Vector3(0.0, float(spec.get("deck", 1.5)) + 2.6, float(outline[0][0]) - 0.8)
	node.add_child(lamp)
	var bulb := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.18
	ball.height = 0.36
	ball.radial_segments = 10
	ball.rings = 5
	bulb.mesh = ball
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.albedo_color = Color(0.75, 1.0, 0.92)
	bulb.material_override = lit
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.add_child(bulb)
	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 3.2)
	glow.mesh = quad
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var fade := GradientTexture2D.new()
	fade.fill = GradientTexture2D.FILL_RADIAL
	fade.fill_from = Vector2(0.5, 0.5)
	fade.fill_to = Vector2(0.5, 0.0)
	var ring := Gradient.new()
	ring.set_color(0, Color(1, 1, 1, 1))
	ring.set_color(1, Color(1, 1, 1, 0))
	fade.gradient = ring
	halo.albedo_texture = fade
	glow.material_override = halo
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.add_child(glow)
	node.set_meta("ghost_lamp", halo)


# Something of the game's riding her (a crewman, a deck chest): it keeps its own look.
static func _game_thing(mesh: Node, ship_node: Node) -> bool:
	var at := mesh
	while at != null and at != ship_node:
		if at.has_meta("sea") or at.has_meta("net_id"):
			return true
		at = at.get_parent()
	return false


# A ghost crewman (or spectral cargo): a cold additive glow over his body (one shared material).
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
