# Purpose: the lit cigarette 3D model: white paper, glowing pulsing ember, and a thin drifting smoke plume. Attached to the player's mouth.
# Dependencies: none. build() returns a Node3D (pointing along -Z); call animate(node, t) each frame while it is visible.
extends RefCounted

const EMBER := Color(1.0, 0.45, 0.1)


static func build() -> Node3D:
	var root := Node3D.new()
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.96, 0.94, 0.88)
	var filter := StandardMaterial3D.new()
	filter.albedo_color = Color(0.85, 0.55, 0.2)
	var ember := StandardMaterial3D.new()
	ember.albedo_color = EMBER
	ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tube := CylinderMesh.new()
	tube.top_radius = 0.012
	tube.bottom_radius = 0.012
	tube.height = 0.1
	tube.radial_segments = 8
	tube.rings = 1
	var body := MeshInstance3D.new()
	body.mesh = tube
	body.material_override = paper
	body.rotation_degrees.x = 90.0
	body.position.z = -0.05
	root.add_child(body)
	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0125
	tip_mesh.bottom_radius = 0.0125
	tip_mesh.height = 0.03
	tip_mesh.radial_segments = 8
	tip_mesh.rings = 1
	tip.mesh = tip_mesh
	tip.material_override = filter
	tip.rotation_degrees.x = 90.0
	tip.position.z = -0.0
	root.add_child(tip)
	var glow := MeshInstance3D.new()
	glow.name = "Ember"
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.014
	glow_mesh.height = 0.028
	glow_mesh.radial_segments = 8
	glow_mesh.rings = 4
	glow.mesh = glow_mesh
	glow.material_override = ember
	glow.position.z = -0.102
	root.add_child(glow)
	root.add_child(_smoke())
	return root


static func _smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.position = Vector3(0, 0.01, -0.105)
	p.amount = 14
	p.lifetime = 1.8
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.initial_velocity_min = 0.12
	p.initial_velocity_max = 0.2
	p.gravity = Vector3(0, 0.05, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var puff := SphereMesh.new()
	puff.radius = 0.02
	puff.height = 0.04
	puff.radial_segments = 6
	puff.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.88, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = mat
	p.mesh = puff
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.6))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 2.6))
	p.scale_amount_curve = grow
	return p


# Pulses the ember so it looks like it is being drawn on.
static func animate(root: Node3D, t: float) -> void:
	var ember: MeshInstance3D = root.get_node("Ember")
	var pulse := 0.8 + 0.2 * sin(t * 3.0) + 0.15 * sin(t * 11.0)
	ember.scale = Vector3.ONE * pulse
	(ember.material_override as StandardMaterial3D).albedo_color = EMBER.lerp(Color(1.0, 0.85, 0.4), clampf(pulse - 0.8, 0.0, 0.4))
