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
const ShieldModel = preload("res://game/shield_model.gd")
const DataStore = preload("res://core/data_store.gd")
const UniqueAttach = preload("res://game/unique_attach.gd")
const LanternGlow = preload("res://game/lantern_glow.gd")
const Mixtape = preload("res://game/signatures/mixtape.gd")
const EmblemBadge = preload("res://game/emblem_badge.gd")
const ToolModels = preload("res://game/tool_models.gd")

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
var _held_shown := ""  # the whole held string last shown ("m16@mixtape", "sniper_basic@fish_story#4321"); _held_id is its gun body alone
var _held_piece: Node3D  # the chase gun's gimmick on the held model (Fish Story's tag shows the record)
var _speaker: AudioStreamPlayer3D  # a Mixtape's song heard from this player (game/net_mixtape.gd), made when first needed
var _slung: MeshInstance3D  # the shield on this player's back, while he carries one and holds something else
var _smoking := false
var _emote := ""
var _emote_t := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _phase := 0.0
var _cigarette: Node3D
var deck_ship: Node3D = null  # the ship this player stands on (game/net_session.gd ghost_deck): his walk is measured on its deck
var _swimming := false
var _last_local := Vector3.ZERO


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


# Shows this player swimming (sea step 5b): the body lies forward in the water.
func set_swimming(on: bool) -> void:
	if on == _swimming or _down:
		return
	_swimming = on
	if _model != null:
		_model.rotation.x = -PI * 0.4 if on else 0.0
		_model.position.y = 0.9 if on else 0.0


# True while this player cannot be fought: lying down, or out of the round (then the ghost is hidden).
func is_down() -> bool:
	return _down or not visible


func _process(delta: float) -> void:
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	if deck_ship != null and is_instance_valid(deck_ship):  # on a sailing ship only his own steps count
		var local := deck_ship.global_transform.affine_inverse() * global_position
		moved = Vector2(local.x - _last_local.x, local.z - _last_local.z).length()
		_last_local = local
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
	if _slung != null and _slung.get_parent() != null:
		_slung.get_parent().remove_child(_slung)
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
	_place_slung()
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


# Shows what this player holds: a gun's body id ("m16@mixtape" = a chase gun with its gimmick, "#n" after it = Fish
# Story's record on its tag), "knife:<type>",
# "shield" (held up), or nothing; "|shield" behind it = a shield hangs on his back (game/player.gd `held_id`). Empty
# or unknown = hands empty.
func set_held(shown: String) -> void:
	var on_back := shown.ends_with("|shield")
	if on_back != (_slung != null and _slung.visible):
		if _slung == null:
			_slung = ShieldModel.build()
		_slung.visible = on_back
		_place_slung()
	var id := shown.trim_suffix("|shield")
	if id == _held_shown:
		return
	if id.begins_with("tool:"):  # a sea tool in his hand (sea step 9b): a new use count plays its move
		var tool := id.trim_prefix("tool:").get_slice("#", 0)
		if _held_model != null and is_instance_valid(_held_model) and _held_shown.begins_with("tool:" + tool + "#"):
			_held_shown = id
			ToolModels.use(_held_model)
			return
		_held_shown = id
		_held_id = ""
		_held_piece = null
		if _held_model != null:
			_held_model.queue_free()
		_held_model = ToolModels.build(tool)
		_place_tool(tool)
		ToolModels.draw(_held_model)
		ToolModels.set_open(_held_model, true)  # (the glider is only out while he glides)
		return
	if _held_piece != null and is_instance_valid(_held_piece) and id.get_slice("#", 0) == _held_shown.get_slice("#", 0):
		_held_shown = id  # same gun, a new record (Fish Story) or its lantern thrown / lit again: only that part changes
		UniqueAttach.show_extra(_held_piece, id.get_slice("@", 1).get_slice("#", 0), id.get_slice("#", 1))
		return
	_held_shown = id
	_held_id = id.get_slice("@", 0)
	_held_piece = null
	if _held_model != null:
		_held_model.queue_free()
		_held_model = null
	if id.is_empty():
		return
	if id == "shield":
		_held_model = ShieldModel.build()
	else:
		_held_model = KnifeModels.build(id.trim_prefix("knife:")) if id.begins_with("knife:") else WeaponModels.build(_held_id)
		if id.contains("@") and _held_model != null:
			_held_piece = UniqueAttach.apply_id(_held_model, id.get_slice("@", 1).get_slice("#", 0))
			if _held_piece != null:
				_held_piece.set_meta("lantern_held", true)  # a Keeper's Lantern in his hand lights our world too
				if _held_piece.is_in_group("lanterns"):
					LanternGlow.ensure(get_parent())
				UniqueAttach.show_extra(_held_piece, id.get_slice("@", 1).get_slice("#", 0), id.get_slice("#", 1))
	_place_held()


# Where his gun's muzzle is now (sea step 12b: his shots' flash and tracers start here): the held model's front end,
# else his chest.
func muzzle_point() -> Vector3:
	if _held_model != null and is_instance_valid(_held_model) and _held_model.is_inside_tree():
		return _held_model.global_transform * Vector3(0.0, 0.03, -0.6)
	return global_position + Vector3(0.0, 1.35, 0.0)


# A Mixtape's song from this player (`stream` from `pos` seconds), as 3D sound: as loud and as far as the holder's own.
func play_song(stream: AudioStream, pos: float) -> void:
	if _speaker == null:
		_speaker = AudioStreamPlayer3D.new()
		_speaker.unit_size = Mixtape.LOUD_UNTIL
		_speaker.max_distance = Mixtape.HEARD_TO
		_speaker.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_speaker.volume_db = Mixtape.VOLUME_DB
		_speaker.position = Vector3(0, 1.2, 0)
		add_child(_speaker)
	_speaker.stream = stream
	if stream != null:
		_speaker.play(clampf(pos, 0.0, maxf(stream.get_length() - 0.5, 0.0)))


func stop_song() -> void:
	if _speaker != null:
		_speaker.stop()


# The slung shield hangs on a rigged body's back; a code-built body has no place for it and shows none.
func _place_slung() -> void:
	if _slung == null or _model == null:
		return
	if _slung.get_parent() != null:
		_slung.get_parent().remove_child(_slung)
	if _model.has_method("back_anchor"):
		(_model.call("back_anchor") as Node3D).add_child(_slung)


# Puts the held weapon in the right hand of a rigged body, or at the fixed spot in front of a code-built one.
func _place_tool(tool: String) -> void:
	if _model != null and _model.has_method("grip"):
		_model.call("grip", null)
		_model.call("support", null)
	if tool == "glider" and _model != null and _model.has_method("back_anchor"):
		(_model.call("back_anchor") as Node3D).add_child(_held_model)
		_held_model.rotation.y = PI
	elif _model != null and _model.has_method("hand_anchor"):
		(_model.call("hand_anchor") as Node3D).add_child(_held_model)
	else:
		_held_model.position = HAND if tool != "glider" else Vector3(0.0, 1.35, 0.2)
		add_child(_held_model)


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
