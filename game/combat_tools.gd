# Purpose: the player's combat tools in the fantasy world (rules: core/combat_rules.gd, numbers:
# data/fantasy/combat.json): the DODGE step (key "dodge": a dash during which nothing hurts), the WARD (hold the
# aim key with the staff out: a shield to the front that eats mana; raised just in time it throws the hit back),
# and the staff STRIKE (let go of the cast key with an empty element box: a swing that gives mana back for every
# creature it hits). It stands between every hit and the player through `player.damage_gate`.
# Dependencies: game/fantasy_world.gd (mana, caster, spell_power, sound, spawner), game/player.gd (shove,
# damage_gate, struck_by, struck_from), core/combat_rules.gd, game/damage_numbers.gd (words over a creature).
extends Node3D

const CombatRules = preload("res://core/combat_rules.gd")

signal dodged
signal warded(perfect: bool)
signal struck(hits: int)

var cfg: Dictionary
var warding := false
var source: Node  # has enemy_list() (game/wave_director.gd)
var numbers: Node  # game/damage_numbers.gd

var _world: Node3D
var _player: Node3D
var _shield := Node3D.new()  # the ward: a faint disc of light with a bright rim, held in front
var _shield_mat := StandardMaterial3D.new()
var _rim_mat := StandardMaterial3D.new()
var _ward_since := 0.0
var _safe_until := 0.0
var _dodge_ready := 0.0
var _strike_ready := 0.0
var _flash := 0.0


func setup(fantasy_world: Node3D, player: Node3D, rules: Dictionary) -> void:
	_world = fantasy_world
	_player = player
	cfg = rules
	var dome := SphereMesh.new()
	dome.radius = 1.0
	dome.height = 2.0
	dome.radial_segments = 16
	dome.rings = 6
	var hoop := TorusMesh.new()
	hoop.inner_radius = 0.95
	hoop.outer_radius = 1.0
	hoop.rings = 24
	hoop.ring_segments = 6
	for part: Array in [[dome, _shield_mat, Vector3(1.0, 1.0, 0.12), Vector3.ZERO], [hoop, _rim_mat, Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)]]:
		var piece := MeshInstance3D.new()
		piece.mesh = part[0]
		var mat: StandardMaterial3D = part[1]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		piece.material_override = mat
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.scale = part[2]
		piece.rotation = part[3]
		_shield.add_child(piece)
	_shield.scale = Vector3(0.62, 0.72, 0.62)
	_shield.visible = false
	add_child(_shield)
	top_level = true


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# How far the dodge is from ready again, 0..1 (1 = ready), for the HUD.
func dodge_ready() -> float:
	return clampf(1.0 - (_dodge_ready - _now()) / maxf(float(cfg["dodge"]["cooldown"]), 0.01), 0.0, 1.0)


# Called by the world when it is entered and left: hits pass through us only while inside.
func set_active(on: bool) -> void:
	_player.set("damage_gate", _gate if on else Callable())
	if not on:
		_drop_ward()


func _process(delta: float) -> void:
	if not bool(_world.get("inside")):
		return
	var staff: bool = _world.get("caster").call("staff_out")
	var free: bool = bool(_player.get("controls_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var want := staff and free and Input.is_action_pressed("aim") and not bool(_world.get("caster").get("channelling")) and float(_world.get("mana")) > 0.0
	if want and not warding:
		warding = true
		_ward_since = _now()
		_player.call("set_pace", float(cfg["ward"]["move_mult"]))
	elif not want and warding:
		_drop_ward()
	_flash = maxf(_flash - delta * 3.0, 0.0)
	_shield.visible = warding or _flash > 0.0
	if _shield.visible:
		var forward: Vector3 = _player.call("view_forward")
		var ahead := Vector3(forward.x, 0.0, forward.z).normalized()
		var chest := _player.global_position + Vector3(0.0, 1.2, 0.0)
		_shield.global_position = chest + ahead * 1.2
		_shield.look_at(chest + ahead * 3.0, Vector3.UP)
		_shield_mat.albedo_color = Color(0.45, 0.75, 1.0, 0.07).lerp(Color(1.0, 0.95, 0.7, 0.45), _flash)
		_rim_mat.albedo_color = Color(0.55, 0.82, 1.0, 0.6).lerp(Color(1.0, 0.95, 0.7, 1.0), _flash)
	if free and Input.is_action_just_pressed("dodge"):
		dodge()


func _drop_ward() -> void:
	if warding:
		warding = false
		_player.call("set_pace", 1.0)


# The dodge step: a dash the way the player is walking (backwards when standing still).
func dodge() -> void:
	var now := _now()
	if now < _dodge_ready:
		return
	var rule: Dictionary = cfg["dodge"]
	_dodge_ready = now + float(rule["cooldown"])
	_safe_until = now + float(rule["safe_seconds"])
	var forward: Vector3 = _player.call("view_forward")
	var ahead := Vector3(forward.x, 0.0, forward.z).normalized()
	var right := ahead.cross(Vector3.UP)
	var keys := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var way := (right * keys.x - ahead * keys.y) if keys.length() > 0.2 else -ahead
	# a shove fades by 30 m/s each second, so this start speed covers about speed x seconds metres
	_player.call("shove", way.normalized() * float(rule["speed"]))
	_world.call("sound", "dodge")
	dodged.emit()


# Every hit on the player comes through here first; returns what is left of it.
func _gate(amount: float, _element: String) -> float:
	var now := _now()
	if now < _safe_until:
		return 0.0
	if not warding:
		return amount
	var attacker: Variant = _player.get("struck_by")
	var from: Vector3 = _player.get("struck_from")
	if is_instance_valid(attacker):
		from = (attacker as Node3D).global_position
	var forward: Vector3 = _player.call("view_forward")
	var frontal := true  # a hit with no known source (another machine's creature) counts as frontal
	if from.is_finite():
		var to := from - _player.global_position
		frontal = CombatRules.in_front(Vector2(forward.x, forward.z), Vector2(to.x, to.z), float(cfg["ward"]["arc_deg"]))
	var result := CombatRules.ward(cfg["ward"], amount, now - _ward_since, frontal, float(_world.get("mana")))
	_world.set("mana", maxf(float(_world.get("mana")) - float(result["mana"]), 0.0))
	if float(result["stopped"]) > 0.0:
		_flash = 1.0
		_world.call("sound", "ward_perfect" if bool(result["perfect"]) else "ward_block")
		warded.emit(bool(result["perfect"]))
	if bool(result["perfect"]) and is_instance_valid(attacker) and (attacker as Node).has_method("on_hit"):
		var back := amount * float(cfg["ward"]["reflect"])
		var at: Vector3 = (attacker as Node3D).global_position + Vector3(0.0, 1.2, 0.0)
		numbers.call("spawn", at, back)
		numbers.call("say", at, String(cfg["words"]["perfect"]), Color(1.0, 0.92, 0.6))
		(attacker as Node).call("on_hit", back, at, Vector3.UP)
		if is_instance_valid(attacker) and (attacker as Node).has_method("apply_freeze"):
			(attacker as Node).call("apply_freeze", float(cfg["ward"]["stagger_seconds"]))
	return float(result["taken"])


# The staff strike (the caster calls this when the cast key is let go with nothing gathered).
func strike() -> void:
	var now := _now()
	if now < _strike_ready or warding:
		return
	var rule: Dictionary = cfg["strike"]
	_strike_ready = now + float(rule["cooldown"])
	var forward: Vector3 = _player.call("view_forward")
	var here := _player.global_position
	var damage := float(_world.call("spell_power", float(rule["damage"])))
	var hits := 0
	for enemy: Variant in source.call("enemy_list"):
		if not is_instance_valid(enemy):
			continue
		var to: Vector3 = (enemy as Node3D).global_position - here
		var reach := float(rule["reach"]) + float((enemy as Node3D).get("_size").x) * 0.5
		if Vector2(to.x, to.z).length() > reach or absf(to.y) > 3.0:
			continue
		if not CombatRules.in_front(Vector2(forward.x, forward.z), Vector2(to.x, to.z), float(rule["arc_deg"])):
			continue
		var at: Vector3 = (enemy as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		(enemy as Node).call("on_hit", damage, at, Vector3.UP)
		numbers.call("spawn", at, damage)
		if is_instance_valid(enemy):
			(enemy as Node).call("push", Vector3(to.x, 0.0, to.z).normalized() * 4.0)
		hits += 1
	if hits > 0:
		_world.set("mana", minf(float(_world.get("mana")) + float(rule["mana_per_hit"]) * float(hits), float(_world.call("max_mana"))))
	_world.call("sound", "strike_hit" if hits > 0 else "strike_miss")
	struck.emit(hits)
