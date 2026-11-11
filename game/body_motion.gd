# Purpose: everyday body animation for any BodyBuilder model: walking (legs, counter-swinging arms, hip bob and twist), idle breathing, weight shifting, glances, blinking and an occasional arm fidget, and a two-handed hold pose when a weapon is out. Pure pose math, no allocation.
# Dependencies: none (uses the Torso/Head/ArmL/ArmR, LegL/LegR hierarchy from game/body_builder.gd).
extends RefCounted

const LEG_SWING := 0.65  # radians at full speed
const ARM_SWING := 0.5


# `move` 0..1 = walking speed fraction, `phase` = stride phase (radians), `t` = time in seconds.
static func animate(model: Node3D, move: float, phase: float, t: float, holding: bool) -> void:
	if model.has_method("head_anchor"):  # a rigged body (game/rigged_body.gd) plays its own clips
		model.call("animate", move, holding)
		return
	var torso: Node3D = model.get_node("Torso")
	var head: Node3D = torso.get_node("Head")
	var arm_l: Node3D = torso.get_node("ArmL")
	var arm_r: Node3D = torso.get_node("ArmR")
	var leg_l: Node3D = model.get_node("LegL")
	var leg_r: Node3D = model.get_node("LegR")
	var stride := sin(phase)
	var idle := 1.0 - move
	var breathe := sin(t * 1.9)
	leg_l.rotation = Vector3(stride * LEG_SWING * move, 0.0, 0.0)
	leg_r.rotation = Vector3(-stride * LEG_SWING * move, 0.0, 0.0)
	torso.rotation = Vector3(0.04 * move + breathe * 0.012 * idle, stride * 0.12 * move, 0.0)
	head.rotation = Vector3(-0.03 * move - breathe * 0.01 * idle, -stride * 0.1 * move + sin(t * 0.37) * 0.22 * idle, 0.0)
	var u := t + float(model.get_instance_id() % 97) * 0.37  # per-character offset so crowds do not blink or fidget together
	var shift := sin(t * 0.23) * idle
	torso.rotation.z = shift * 0.03
	head.rotation.y += sin(t * 0.9) * sin(t * 0.13) * 0.12 * idle
	var eyes: Node3D = head.get_node_or_null("Face/Eyes")
	if eyes != null:
		var b := fmod(u, 3.6)
		eyes.scale.y = 1.0 - 0.9 * (sin(b / 0.14 * PI) if b < 0.14 else 0.0)
	if holding:
		arm_r.rotation = Vector3(1.35, 0.0, 0.12)
		arm_l.rotation = Vector3(1.25, 0.0, -0.55)
	else:
		arm_l.rotation = Vector3(-stride * ARM_SWING * move + breathe * 0.03 * idle, 0.0, 0.07 + 0.03 * idle)
		var f := fmod(u, 13.0)
		var lift := sin(f / 1.6 * PI) * idle if f < 1.6 else 0.0  # every ~13 s the right hand lifts (a small wave / hair touch)
		arm_r.rotation = Vector3(stride * ARM_SWING * move - breathe * 0.03 * idle - lift * 1.1, 0.0, -0.07 - 0.03 * idle - lift * 0.35)
