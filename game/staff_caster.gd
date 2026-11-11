# Purpose: staff magic in the hands: while the shoot key is held with the staff out, mana gathers at the staff's tip
# and each element key adds one element to the cast (up to the staff's slots, each costing mana); letting go casts
# whatever the sequence makes (core/spell_book.gd) through game/spell_effects.gd. Also builds and holds the staff
# model. The staff is out whenever no gun is in the hands inside the fantasy world.
# Dependencies: game/fantasy_world.gd (mana, slots, power, quest reports), game/player.gd (view, hand, channelling),
# game/spell_effects.gd.
extends Node3D

signal sequence_changed(sequence: String)
signal refused(why: String)  # "full" or "mana": the element box flashes
signal cast_done(spell: Dictionary, sequence: String, origin: Vector3, aim: Vector3)

const FantasyModels = preload("res://game/fantasy_models.gd")
var world: Node3D  # game/fantasy_world.gd
var sequence := ""
var channelling := false

var _player: Node3D
var _fx: Node3D
var _staff := Node3D.new()
var ring_turns := true  # graphics tier: the ring round the orb turns slowly
var _ring: Node3D
var _gem := StandardMaterial3D.new()
var _tip: MeshInstance3D
var _glow: MeshInstance3D
var _glow_mat := StandardMaterial3D.new()
var _shown_staff := ""
var _time := 0.0


func setup(fantasy_world: Node3D, player: Node3D, fx: Node3D) -> void:
	world = fantasy_world
	_player = player
	_fx = fx
	_build_staff()
	(player.call("hand_parent") as Node3D).add_child(_staff)
	_staff.visible = false


func staff_out() -> bool:
	return world.inside and not bool(_player.call("holding_gun"))


func tip_world() -> Vector3:
	return _tip.global_position


func _process(delta: float) -> void:
	_time += delta
	var out := staff_out()
	_staff.visible = out
	if out and ring_turns and _ring != null:
		_ring.rotate_object_local(Vector3.UP, delta * 1.1)
	if not out:
		if channelling:
			_stop()
		return
	var id := String(world.bag.equipped.get("staff", ""))
	if id != _shown_staff:
		_shown_staff = id
	var raise := 0.12 if channelling else 0.0
	if bool(_player.get("third_person")):
		var hold: Vector3 = _player.call("hand_position")
		_staff.position = hold + Vector3(0.06, -0.38 + raise, 0.0)
		_staff.rotation_degrees = Vector3(-14.0 - (22.0 if channelling else 0.0), 0.0, -6.0)
	else:  # first person: low on the right, leaning away so the stone sits right of the crosshair
		_staff.position = Vector3(0.36, -0.82 + raise + sin(_time * 1.7) * 0.008, -0.55)
		_staff.rotation_degrees = Vector3(-36.0 - (12.0 if channelling else 0.0), 0.0, -4.0)
	var want: bool = bool(_player.get("controls_enabled")) and Input.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if want and not channelling:
		channelling = true
		_player.set("channelling", true)
		sequence = ""
		sequence_changed.emit(sequence)
	elif not want and channelling:
		var built := sequence
		_stop()
		_cast(built)
	_glow.visible = channelling
	if channelling:
		var size := 0.22 + 0.06 * float(sequence.length()) + sin(_time * 18.0) * 0.014
		_glow.scale = Vector3.ONE * size
		_glow_mat.albedo_color = _blend(sequence)


func _unhandled_input(event: InputEvent) -> void:
	if not channelling:
		return
	var elements: Dictionary = world.spells.data["elements"]
	for letter: String in elements:
		if event.is_action_pressed(String(elements[letter]["action"])):
			add(letter)
			get_viewport().set_input_as_handled()
			return


# Adds one element to the cast being built.
func add(letter: String) -> void:
	if sequence.length() >= int(world.slots()):
		refused.emit("full")
		return
	var cost := float(world.spells.mana_cost(letter))
	if float(world.mana) < cost:
		refused.emit("mana")
		return
	world.mana -= cost
	sequence += letter
	sequence_changed.emit(sequence)


func _stop() -> void:
	channelling = false
	_player.set("channelling", false)
	sequence = ""
	sequence_changed.emit(sequence)


func _cast(built: String) -> void:
	var spell: Dictionary = world.spells.resolve(built)
	if spell.is_empty():
		return
	var origin: Vector3 = _player.call("view_origin")
	var aim: Vector3 = _player.call("view_forward")
	_fx.call("cast", spell, origin, aim, tip_world(), float(world.spell_power(float(spell["damage"]))), float(world.spell_power(float(spell["heal"]))))
	world.report({"type": "cast", "sequence": built, "substance": String(spell.get("substance", "")), "secret": String(spell["secret"])})
	cast_done.emit(spell, built, origin, aim)


# The colour of everything gathered so far.
func _blend(built: String) -> Color:
	if built == "":
		return Color(0.85, 0.85, 1.0, 0.7)
	var total := Color(0, 0, 0, 0)
	for letter in built:
		var c: Array = world.spells.data["elements"][letter]["color"]
		total += Color(c[0], c[1], c[2], 0.0)
	return Color(total.r / built.length(), total.g / built.length(), total.b / built.length(), 0.9)


func _build_staff() -> void:
	# Every staff looks the same for now (the director's reference): a black shaft with silver rings, a head of two
	# prongs closing into twin points, a glowing blue orb between them and a silver ring tilted round the orb.
	_gem.albedo_color = Color(0.3, 0.62, 1.0)
	_gem.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var model := FantasyModels.held("staff_orb", _gem)
	_staff.add_child(model)
	_tip = model.find_child("Orb", true, false) as MeshInstance3D
	_ring = model.find_child("Ring", true, false) as Node3D
	if _ring != null:
		_ring.rotation = Vector3(deg_to_rad(62.0), 0.0, deg_to_rad(18.0))
	_glow = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.5
	orb.height = 1.0
	orb.radial_segments = 12
	orb.rings = 6
	_glow.mesh = orb
	_glow.material_override = _glow_mat
	_glow.position.y = _tip.position.y if _tip != null else 1.44  # at the orb
	_glow.visible = false
	_staff.add_child(_glow)
