# Purpose: shared drawing pieces for the chase guns' effects (director 2026-11-15 "finish modeling"): the modelled
# shapes of assets/models/fx/ (tools/blender/fx_models.py), cached glowing / see-through materials, a soft round spot
# and a fade-out texture made once, and small CPU particle bursts (embers, puffs, bubbles, sparks) drawn as soft
# billboards. Everything is cached so an effect costs no new materials or textures after the first.
# Cheap by design for the HD 620: unshaded materials, no shadows, few particles (CPUParticles3D, Compatibility-safe).
# Dependencies: assets/models/fx/*.gltf.
extends RefCounted

const FOLDER := "res://assets/models/fx/"

static var _scenes := {}
static var _mats := {}
static var _dot: GradientTexture2D
static var _fade: GradientTexture2D
static var _quad: QuadMesh


# A new copy of a modelled effect shape (null if the file is missing).
static func shape(id: String) -> Node3D:
	if not _scenes.has(id):
		var path := FOLDER + id + ".gltf"
		_scenes[id] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scenes[id]
	return scene.instantiate() as Node3D if scene != null else null


# An unshaded material: additive glow (fire, light, foam) or alpha (gas, water). Cached by its look.
static func glow(color: Color, additive := true, texture: Texture2D = null) -> StandardMaterial3D:
	var key := "%s|%s|%d" % [color.to_html(), str(additive), texture.get_instance_id() if texture != null else 0]
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if texture != null:
		mat.albedo_texture = texture
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.texture_repeat = false  # (a fade must not wrap round into its bright end)
	_mats[key] = mat
	return mat


# Gives every mesh under `node` the material (the effect shapes' own colours are only for previews).
static func paint(node: Node, mat: Material) -> void:
	if node == null:
		return
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = mat
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# A soft round spot: white middle fading to nothing at the edge (particles, glows).
static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_dot = GradientTexture2D.new()
		_dot.gradient = grad
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
	return _dot


# Bright at the top edge (v = 0) fading to nothing at the bottom (v = 1): light shafts.
static func fade_down() -> GradientTexture2D:
	if _fade == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
		_fade = GradientTexture2D.new()
		_fade.gradient = grad
		_fade.fill_from = Vector2(0.5, 0.0)
		_fade.fill_to = Vector2(0.5, 1.0)
		_fade.width = 8
		_fade.height = 64
	return _fade


# A small particle emitter of soft glowing spots. one_shot = a single burst that frees itself.
static func particles(color: Color, amount: int, life: float, size: float, up: float, spread: float, gravity: float, one_shot: bool, additive := true) -> CPUParticles3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	var p := CPUParticles3D.new()
	p.mesh = _quad
	var key := "particles|%s" % str(additive)
	if not _mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = soft_dot()
		mat.texture_repeat = false
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_mats[key] = mat
	p.material_override = _mats[key]
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = up * 0.6
	p.initial_velocity_max = up
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(color, 0.0), color, Color(color, 0.0)])
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	if one_shot:
		p.finished.connect(p.queue_free)
	return p


# A one-shot burst of particles at a spot in the world.
static func burst(world: Node, at: Vector3, color: Color, amount: int, life: float, size: float, speed: float, gravity := -4.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	var p := particles(color, amount, life, size, speed, 180.0, gravity, true)
	world.add_child(p)
	p.global_position = at


# One modelled flame tongue: orange outside, a bright core inside. Null without the model.
static func flame(outer := Color(1.0, 0.42, 0.06, 0.85), inner := Color(1.0, 0.86, 0.38, 0.95)) -> Node3D:
	var tongue := shape("flame_tongue")
	if tongue == null:
		return null
	paint(tongue, glow(outer, false))  # see-through, not added: added colours turn white in daylight
	var core := tongue.find_child("Core", true, false)
	if core != null:
		paint(core, glow(inner, false))
	return tongue
