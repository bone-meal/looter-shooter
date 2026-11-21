# Purpose: the RE-FORGE (polish1 D4e, item 38): the big forge-press that rerolls and tiers up guns, its own model
# (tools/blender/reforge_quest.py, not a perk machine). It sleeps cold until its quest wakes it; then, with the power on,
# its furnace mouth, gauges and glass tubes glow, the ship's wheel turns slowly and the drop hammer strikes on each use.
# Draws only; the session decides what it does.
# Dependencies: game/fantasy_models.gd. Set `title`, `price`, `tint` before add_child; `set_powered`, `set_awake`, `strike`.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")

var title := "Re-forge"
var price := 0
var tint := Color(0.75, 0.35, 0.95)

var _glow: StandardMaterial3D
var _tag: Label3D
var _spin: Node3D = null
var _hammer: Node3D = null
var _hammer_rest := Vector3.ZERO
var _light: OmniLight3D
var _powered := false
var _awake := false
var _tween: Tween = null


func _ready() -> void:
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = tint
	_glow.emission = tint
	_glow.roughness = 0.4
	var made := FantasyModels.scene("reforge_machine")
	add_child(made)
	for found in made.find_children("*", "MeshInstance3D", true, false):
		if String(found.name).begins_with("Glow") or String(found.get_parent().name).begins_with("Glow"):
			(found as MeshInstance3D).material_override = _glow
	_spin = made.find_child("Spin", true, false) as Node3D
	_hammer = made.find_child("Hammer", true, false) as Node3D
	if _hammer != null:
		_hammer_rest = _hammer.position
	_tag = Label3D.new()
	_tag.font_size = 44
	_tag.pixel_size = 0.004
	_tag.outline_size = 8
	var mark := made.find_child("Tag", true, false) as Node3D
	_tag.position = (mark.position if mark != null else Vector3(0.0, 3.6, 1.2)) + Vector3(0.0, 0.0, 0.05)
	add_child(_tag)
	_light = OmniLight3D.new()  # the furnace's glow on the deck (one light, no shadow)
	_light.position = Vector3(0.0, 1.7, 1.9)
	_light.light_color = tint
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	add_child(_light)
	var box := FantasyModels.bounds(made)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = Vector3(box.size.x * 0.85, box.size.y, box.size.z * 0.85)
	shape.shape = solid
	shape.position = box.get_center()
	body.add_child(shape)
	add_child(body)
	_show()


func _process(delta: float) -> void:
	if _spin != null and _powered and _awake:
		_spin.rotate_object_local(Vector3.RIGHT, delta * 0.6)
		_light.light_energy = 0.7 + sin(Time.get_ticks_msec() * 0.006) * 0.15  # the fire breathes


func set_powered(on: bool) -> void:
	_powered = on
	_show()


func set_awake(on: bool) -> void:
	_awake = on
	_show()


# The drop hammer comes down on the anvil twice (a gun was just worked on).
func strike() -> void:
	if _hammer == null:
		return
	if _tween != null:
		_tween.kill()
	_hammer.position = _hammer_rest
	_tween = create_tween()
	for i in 2:
		_tween.tween_property(_hammer, "position", _hammer_rest + Vector3(0, -0.72, 0), 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_tween.tween_property(_hammer, "position", _hammer_rest, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func _show() -> void:
	if _glow == null:
		return
	var lit := _powered and _awake
	_glow.emission_enabled = lit
	_glow.emission_energy_multiplier = 1.6
	_glow.albedo_color = tint if lit else tint.darkened(0.75)
	_light.visible = lit
	_tag.text = "RE-FORGE" if lit else "RE-FORGE\n(cold)"
	_tag.modulate = Color(1.0, 0.85, 1.0) if lit else Color(0.5, 0.5, 0.55)
