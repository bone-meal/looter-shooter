# Purpose: the moving parts of the gun in hand, posed every frame from the gun's state (core/weapon_state.gd): the
# SMG's cocking handle snaps back, the revolver's cylinder turns a chamber per shot and swings out to reload, hammers
# fall and are cocked again, the lever-action's lever cycles, the flare gun breaks open, the harpoon's spear and the
# crossbow's bolt are gone once fired and come back with the reload (the string drawn or loose), the flamethrower's
# fuel needle follows the fuel and its nozzle throws a flame while it fires (a small pilot flame always burns).
# Node names come from tools/blender/weapons_sea.py; models without them are left alone.
# Dependencies: game/fx_kit.gd (flame particles), core/weapon_state.gd (passed in).
extends RefCounted

const FxKit = preload("res://game/fx_kit.gd")

const HAMMER_DOWN := -0.6  # radians a fallen hammer turns forward from its cocked rest
const LEVER_OPEN := 0.9


static func pose(model: Node3D, weapon: RefCounted, now: float) -> void:
	var since := now - float(weapon.last_shot)
	var reload := float(weapon.reload_fraction(now))
	var loaded := int(weapon.ammo) > 0 or reload > 0.6
	var bolt := model.get_node_or_null("Bolt") as Node3D
	if bolt != null:
		bolt.position.z = 0.05 * _pulse(since, 0.07)
	var cylinder := model.get_node_or_null("Cylinder") as Node3D
	if cylinder != null:
		var want := float(int(weapon.mag_size) - int(weapon.ammo)) * TAU / 6.0
		var turned := float(model.get_meta("cylinder_turn", want))
		turned = lerpf(turned, want, minf(1.0, 0.35 + since * 8.0)) if since < 0.2 else want
		model.set_meta("cylinder_turn", turned)
		var out := sin(PI * reload)  # swung out to the left while reloading, spun as the rounds go in
		cylinder.position.x = -0.035 * out
		cylinder.rotation.z = turned + reload * TAU * 2.0
	var hammer := model.get_node_or_null("Hammer") as Node3D
	if hammer != null:
		var down := 1.0 - clampf((since - 0.08) / 0.25, 0.0, 1.0)  # falls, then is cocked again for the next shot
		if int(weapon.mag_size) == 1:  # single shots: it stays down until the reload cocks it
			down = 0.0 if loaded else 1.0
		hammer.rotation.x = HAMMER_DOWN * down
	var lever := model.get_node_or_null("Lever") as Node3D
	if lever != null:
		lever.rotation.x = LEVER_OPEN * _pulse(since - 0.12, 0.42)
	var breech := model.get_node_or_null("Breech") as Node3D
	if breech != null:
		breech.rotation.x = -0.7 * sin(PI * reload)
	var spear := model.get_node_or_null("Spear") as Node3D
	if spear != null:
		spear.visible = loaded
		spear.position.z = 0.6 * (1.0 - clampf((reload - 0.6) / 0.35, 0.0, 1.0)) if reload > 0.0 else 0.0
	var arrow := model.get_node_or_null("Arrow") as Node3D
	if arrow != null:
		arrow.visible = loaded
		(model.get_node("StringDrawn") as Node3D).visible = loaded
		(model.get_node("StringLoose") as Node3D).visible = not loaded
	var needle := model.get_node_or_null("Needle") as Node3D
	if needle != null:
		needle.rotation.x = lerpf(1.7, -1.7, float(weapon.ammo) / float(maxi(int(weapon.mag_size), 1)))
	var nozzle := model.get_node_or_null("Nozzle") as Node3D
	if nozzle != null:
		_flame(model, nozzle, since < 0.12 and model.is_visible_in_tree())


# 0 -> 1 -> 0 over `length` seconds after t = 0 (a part going and coming back).
static func _pulse(t: float, length: float) -> float:
	if t < 0.0 or t > length:
		return 0.0
	return sin(PI * t / length)


static func _flame(model: Node3D, nozzle: Node3D, on: bool) -> void:
	var stream := nozzle.get_node_or_null("Stream") as CPUParticles3D
	if stream == null:
		stream = FxKit.particles(Color(1.0, 0.5, 0.12, 0.75), 60, 0.5, 0.9, 16.0, 5.0, 1.5, false, false)
		stream.name = "Stream"
		stream.direction = Vector3.FORWARD  # down the barrel (-Z)
		stream.local_coords = false
		var grow := Curve.new()  # a thin tongue at the nozzle swelling into a wide billow (big sprites near the eye filled the view)
		grow.add_point(Vector2(0.0, 0.04))
		grow.add_point(Vector2(0.35, 0.45))
		grow.add_point(Vector2(1.0, 1.0))
		stream.scale_amount_curve = grow
		nozzle.add_child(stream)
		var pilot := FxKit.particles(Color(0.35, 0.6, 1.0, 0.9), 8, 0.25, 0.03, 0.4, 20.0, 0.6, false, true)  # the pilot light: small and blue
		pilot.name = "PilotFlame"
		var at := model.get_node_or_null("Pilot") as Node3D
		(at if at != null else nozzle).add_child(pilot)
	stream.emitting = on
