# Purpose: a great creature's END as a moment (polish1 E4, item 131), seen the same on every machine (puppets fall too):
# it shudders, sinks to its knees and topples slowly, a column of gold light rises where it fell with its own debris
# (straw, splinters, ice ...) drifting up, a ring runs out over the ground, then the body sinks away. A phantom (its
# echo, item 133) instead lifts, thins and is gone in a cold blue column. Cheap: one cylinder, one ring, one particle
# emitter of 60, all unshaded and freed after 5 s; no lights, no shadows.
# Dependencies: none (called by game/enemy.gd fall()).
extends RefCounted

const GOLD := Color(1.0, 0.82, 0.4)
const COLD := Color(0.5, 0.78, 1.0)
const SECONDS := 5.0


static func play(enemy: Node3D, model: Node3D, size: Vector3, chips: Color, phantom: bool) -> void:
	var hue := COLD if phantom else GOLD
	_column(enemy, size, hue, Color(chips.r, chips.g, chips.b, 1.0) if chips.a > 0.0 and not phantom else hue)
	var tween := enemy.create_tween()
	if model == null:
		tween.tween_interval(1.0)
		tween.tween_callback(enemy.queue_free)
		return
	if phantom:  # the echo lifts and thins away
		tween.tween_property(model, "position:y", model.position.y + size.y * 0.35, 2.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(model, "scale", model.scale * Vector3(1.15, 1.3, 1.15), 1.2)
		tween.tween_property(model, "scale", model.scale * 0.02, 1.0).set_ease(Tween.EASE_IN)
		tween.tween_interval(0.6)
		tween.tween_callback(enemy.queue_free)
		return
	var side := 1.0 if randf() < 0.5 else -1.0
	for k in 6:  # a shudder
		tween.tween_property(model, "rotation:z", 0.06 * (1.0 if k % 2 == 0 else -1.0), 0.07)
	tween.tween_property(model, "rotation:z", 0.0, 0.07)
	tween.tween_property(model, "position:y", model.position.y - size.y * 0.18, 0.5).set_ease(Tween.EASE_IN_OUT)  # to its knees
	tween.parallel().tween_property(model, "rotation:x", 0.22, 0.5)
	tween.tween_interval(0.35)
	tween.tween_property(model, "rotation:z", PI * 0.47 * side, 1.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)  # topples
	tween.tween_interval(1.4)
	tween.tween_property(enemy, "position:y", enemy.position.y - maxf(size.y, size.x) * 0.9, 1.4)
	tween.tween_callback(enemy.queue_free)


# The light column, the drifting debris and the ring over the ground, at the creature's feet (not its child: it
# outlives the body a moment).
static func _column(enemy: Node3D, size: Vector3, hue: Color, bits: Color) -> void:
	var root := Node3D.new()
	enemy.get_parent().add_child(root)
	root.global_position = enemy.global_position
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color(hue, 0.0)
	var pillar := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = maxf(size.x, size.z) * 0.3
	tube.bottom_radius = maxf(size.x, size.z) * 0.4
	tube.height = size.y * 4.0
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 16
	tube.rings = 1
	pillar.mesh = tube
	pillar.material_override = glow
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position.y = tube.height * 0.5
	root.add_child(pillar)
	var ring_mat := glow.duplicate() as StandardMaterial3D
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.position.y = 0.15
	root.add_child(ring)
	var motes := CPUParticles3D.new()
	motes.amount = 60
	motes.lifetime = 2.6
	motes.one_shot = false
	motes.explosiveness = 0.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = maxf(size.x, size.z) * 0.5
	motes.direction = Vector3.UP
	motes.spread = 25.0
	motes.gravity = Vector3(0.0, 0.6, 0.0)
	motes.initial_velocity_min = 1.0
	motes.initial_velocity_max = 2.6
	var bit := QuadMesh.new()
	bit.size = Vector2(0.12, 0.12)
	var bit_mat := StandardMaterial3D.new()
	bit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bit_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	bit_mat.vertex_color_use_as_albedo = true
	bit.material = bit_mat
	motes.mesh = bit
	motes.color = bits
	motes.position.y = size.y * 0.4
	root.add_child(motes)
	var t := root.create_tween()
	t.tween_property(glow, "albedo_color:a", 0.32, 0.8)
	t.parallel().tween_property(ring, "scale", Vector3(size.x * 6.0, 0.05, size.x * 6.0), 1.6).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(ring_mat, "albedo_color:a", 0.7, 0.3)
	t.tween_property(ring_mat, "albedo_color:a", 0.0, 0.8)
	t.parallel().tween_interval(1.6)
	t.tween_callback(func() -> void: motes.emitting = false)
	t.tween_property(glow, "albedo_color:a", 0.0, SECONDS - 3.2)
	t.tween_callback(root.queue_free)
