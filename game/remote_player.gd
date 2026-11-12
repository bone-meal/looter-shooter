# Purpose: another player's body in our world: their customized model, name label, held weapon, lit cigarette and a hit box that other players' shots can hit (PvP).
# Dependencies: game/rigged_body.gd (game/body_builder.gd when the character packs are missing), game/appearance_data.gd, game/weapon_models.gd, game/cigarette_model.gd. game/net_session.gd creates and moves it; it reports shots through `shot`.
extends StaticBody3D

const BodyBuilder = preload("res://game/body_builder.gd")
const RiggedBody = preload("res://game/rigged_body.gd")
const AppearanceData = preload("res://game/appearance_data.gd")
const DancePoses = preload("res://game/dance_poses.gd")
const BodyMotion = preload("res://game/body_motion.gd")
const RUN_SPEED := 7.0  # same as the player walk speed
const CigaretteModel = preload("res://game/cigarette_model.gd")
const WeaponModels = preload("res://game/weapon_models.gd")
const KnifeModels = preload("res://game/knife_models.gd")
const DataStore = preload("res://core/data_store.gd")
const EmblemBadge = preload("res://game/emblem_badge.gd")

const HAND := Vector3(0.26, 1.3, -0.5)  # where the weapon sits in the body model
const HEAD_HEIGHT := 1.6  # as game/player.gd: a shoulder-carried gun is placed from here

signal shot(damage: float)
signal struck(amount: float, element: String)  # an enemy run by this machine (the host) hit this player: their own machine takes the damage

var peer_id := 0
var display_name := ""
var appearance := {}
var card := {}  # public player card from the host: callsign, title, level, emblem_def (see net_session._make_card)

var _model: Node3D
var _label: Label3D
var _badge: Sprite3D
var _held_id := ""
var _down := false  # see set_down()
var _held_model: Node3D
var _smoking := false
var _emote := ""
var _emote_t := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _phase := 0.0
var _cigarette: Node3D


# Shows the player card: "Callsign  LV n" over the title, with the emblem above.
func set_card(new_card: Dictionary) -> void:
	card = new_card
	if _label != null:
		_apply_card()


func _apply_card() -> void:
	if card.is_empty():
		_label.text = display_name
		_badge.visible = false
		return
	var shown := String(card["callsign"]) if String(card["callsign"]) != "" else display_name
	_label.text = "%s  LV %d\n%s" % [shown, int(card["level"]), String(card["title"])]
	_badge.show_emblem(card["emblem_def"])
	_badge.visible = true


func _ready() -> void:
	collision_layer = 8  # only shots see it: players and enemies (layers 1-2) walk through
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.9, 0.7)
	shape.shape = box
	shape.position.y = 0.95
	add_child(shape)
	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.005
	_label.no_depth_test = true
	add_child(_label)
	_badge = EmblemBadge.new()
	add_child(_badge)
	_apply_card()
	_rebuild()


# Shows this player lying on the ground (down on the islands, waiting for a revive) or back on their feet.
func set_down(on: bool) -> void:
	if on == _down:
		return
	_down = on
	if _model != null:
		_model.rotation.x = -PI * 0.5 if on else 0.0
		_model.position.y = 0.25 if on else 0.0


# True while this player cannot be fought: lying down, or out of the round (then the ghost is hidden).
func is_down() -> bool:
	return _down or not visible


func _process(delta: float) -> void:
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	if delta > 0.0:
		_speed = lerpf(_speed, minf(moved / delta, 20.0), minf(delta * 8.0, 1.0))
	if _model == null:
		pass
	elif not _emote.is_empty():
		_emote_t += delta
		DancePoses.apply(_model, _emote, _emote_t)
	else:
		_phase += _speed * delta * 1.6
		BodyMotion.animate(_model, clampf(_speed / RUN_SPEED, 0.0, 1.0), _phase, Time.get_ticks_msec() / 1000.0, not _held_id.is_empty())
	if _cigarette != null and _cigarette.visible:
		CigaretteModel.animate(_cigarette, Time.get_ticks_msec() / 1000.0)


# Swaps the body for a new look (a no-op when nothing changed).
func set_appearance(look: Dictionary) -> void:
	var clean := AppearanceData.db().sanitize(look)
	if _model != null and clean.hash() == appearance.hash():
		return
	appearance = clean
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	if _held_model != null and _held_model.get_parent() != null:
		_held_model.get_parent().remove_child(_held_model)  # it may hang in the old body's hand
	if _model != null:
		_model.queue_free()
	appearance = AppearanceData.db().sanitize(appearance)
	_model = RiggedBody.build(appearance)  # rigged character when the packs are installed
	if _model == null:
		_model = BodyBuilder.build(appearance)
	add_child(_model)
	_label.position = Vector3(0, 2.1 * float(appearance["height"]), 0)
	_badge.position = _label.position + Vector3(0, 0.42, 0)
	_cigarette = null
	_apply_smoking()
	_place_held()
	_emote_t = 0.0


# Plays a looping dance ("" = stop).
func set_emote(id: String) -> void:
	if id == _emote:
		return
	if not id.is_empty() and not DancePoses.has(id):
		return
	_emote = id
	_emote_t = 0.0
	if id.is_empty() and _model != null:
		DancePoses.reset(_model)


# Shows or hides the lit cigarette in the mouth.
func set_smoking(on: bool) -> void:
	_smoking = on
	_apply_smoking()


func _apply_smoking() -> void:
	if _smoking and _cigarette == null and _model != null:
		_cigarette = CigaretteModel.build()
		_cigarette.position = Vector3(0.035, 0.05, -0.098)  # same spot as on our own body
		_cigarette.rotation_degrees.x = 10.0
		if _model.has_method("head_anchor"):
			(_model.call("head_anchor") as Node3D).add_child(_cigarette)
		else:
			_model.get_node("Torso/Head").add_child(_cigarette)
	if _cigarette != null:
		_cigarette.visible = _smoking


# Shows the weapon this player holds (empty or unknown ID = hands empty).
func set_held(id: String) -> void:
	if id == _held_id:
		return
	_held_id = id
	if _held_model != null:
		_held_model.queue_free()
		_held_model = null
	if id.is_empty():
		return
	_held_model = KnifeModels.build(id.trim_prefix("knife:")) if id.begins_with("knife:") else WeaponModels.build(id)
	_place_held()


# Puts the held weapon in the right hand of a rigged body, or at the fixed spot in front of a code-built one.
func _place_held() -> void:
	if _held_model == null or _model == null:
		return
	if _held_model.get_parent() != null:
		_held_model.get_parent().remove_child(_held_model)
	var view: Dictionary = DataStore.load_json("res://data/weapons.json")["weapons"].get(_held_id, {}).get("view", {})
	if _model.has_method("grip"):
		_model.call("grip", null)
	if _model.has_method("hand_anchor") and view.has("shoulder_hold"):  # a launcher rides on the shoulder; both hands reach for it
		var at: Array = view["shoulder_hold"]
		_held_model.position = Vector3(at[0], HEAD_HEIGHT + float(at[1]), at[2])
		add_child(_held_model)
		var hand := Node3D.new()
		var spot: Array = view.get("shoulder_grip", [0.0, -0.12, 0.03])
		hand.position = Vector3(spot[0], spot[1], spot[2])
		_held_model.add_child(hand)
		_model.call("grip", hand)
		_model.call("support", _held_model.get_node_or_null("Support"))
	elif _model.has_method("hand_anchor"):
		_held_model.position = Vector3.ZERO
		(_model.call("hand_anchor") as Node3D).add_child(_held_model)
		_model.call("support", _held_model.get_node_or_null("Support"))  # long guns: left hand on the fore-end
	else:
		_held_model.position = HAND
		add_child(_held_model)


# Called by the shooter's hitscan.
# Host-run enemies call this on whoever they hit (same name as game/player.gd).
func take_damage(amount: float, element: String = "physical") -> void:
	struck.emit(amount, element)


func on_hit(damage: float, _point: Vector3 = Vector3.ZERO, _normal: Vector3 = Vector3.UP) -> void:
	shot.emit(damage)
