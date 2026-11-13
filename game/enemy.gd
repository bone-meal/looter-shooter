# Purpose: one enemy (skeleton swordsman, skeleton archer, clockwork bear boss, a modelled wastelander or a fantasy creature): chases the player and attacks using stats from data/enemies.json.
# Dependencies: core/health_state.gd, core/enemy_brain.gd, game/character_models.gd, game/fantasy_models.gd. Projectile pool, blood effects and target are passed in by game/wave_director.gd.
extends CharacterBody3D

signal died(enemy: Node)
signal attacked(origin: Vector3, aim: Vector3)  # a ranged attack started (online: the host tells other machines to show it)
signal puppet_hit(damage: float)  # a puppet was shot (online: the damage goes to the host as an intent)
signal felled(enemy: Node)  # killed by another creature, not by a player: nobody is paid (the fantasy tribes fighting each other)
signal puppet_effect(kind: String, amount: float, seconds: float)  # a puppet was slowed, burned, frozen, weakened or pushed (the host decides if it sticks)

const HealthState = preload("res://core/health_state.gd")
const EnemyBrain = preload("res://core/enemy_brain.gd")
const CharacterModels = preload("res://game/character_models.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")

const BONE_COLOR := Color(0.9, 0.88, 0.8)
const BONE_FLASH := Color(1.0, 0.35, 0.35)
const BRASS := Color(0.72, 0.55, 0.22)
const BOX_FLASH := Color(1, 1, 1)
const AIM_HEIGHT := 1.2  # aim at the player's chest
const SWING_TIME := 0.3
const WALK_SWING := 0.7
const PUSH_DECAY := 14.0  # m/s lost per second by a knockback
const DODGE_TURN := 1.25  # radians it turns aside to get round something

var enemy_id := ""
var elite := ""  # affix name when this is an elite (set by game/wave_director.gd before add_child), else ""
var element := "physical"  # "physical", "fire", "ice" or "toxic" (set by game/wave_director.gd before add_child)
var element_tint := Color.WHITE
var one_blow := Callable()  # func() -> bool: any hit kills right now (the islands' insta-kill power-up; never a boss)
var puppet := false  # online copy of a boss simulated on the host: no AI, follows net_pos/net_yaw, damage goes to the host
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var walker: Callable  # fantasy world: (from, step) -> where the body ends up. When set the enemy moves by it without physics: around houses, trees and deep water, the same on every machine
var feud := ""  # fantasy tribes: the banner this warrior fights for ("" = none)
var sounds: Node  # the game's sound player (game/fantasy_sounds.gd with data/sounds.json), set by game/wave_director.gd; null = silent
var order_goal := Vector3.INF  # squad order (game/squad_command.gd): walk to this spot instead of straight at the target
var order_attack := true  # squad order: it may strike now (false = it waits its turn)
var order_until := 0.0  # engine time the order stops counting (orders are renewed a few times a second)
var calm_until := 0.0  # engine time until which it has given up the chase (its prey is in a safe place): no special attacks (game/boss_moves.gd)
var health: HealthState
var _slow_until := 0.0  # gun buff: seconds (engine time) until the slow ends
var _slow_amount := 0.0
var _burn_until := 0.0  # gun buff: damage over time
var _burn_dps := 0.0
var _burn_tick := 0.0
var _freeze_until := 0.0  # skills: frozen in place until this engine time
var _vuln_until := 0.0  # skills/buffs: takes extra damage until this engine time
var _vuln_mult := 1.0
var _push := Vector3.ZERO  # skills: knockback / pull velocity, fades on its own

var _stats: Dictionary
var _brain: EnemyBrain
var _target: Node3D
var _pool: Node3D
var _blood: Node3D
var _speed: float
var run_fx := {}  # a colosseum run's effects (core/colosseum_rules.gd `effects`): set by the wave director, {} everywhere else
var _berserk_at := 0.0  # health at which it goes berserk (0 = never, or done)
var _size: Vector3
var _accent: Color
var _base_color: Color
var _flash_color: Color
var _material := StandardMaterial3D.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _leg_l: Node3D
var _leg_r: Node3D
var _sword_arm: Node3D
var _wind_key: Node3D  # clockwork bear's back key
var _decor: Node3D  # element add-ons (flames, crystals, droplets)
var _swings: Array[Node3D] = []  # fantasy creatures: legs that swing against each other (names SwingA*, SwingB*)
var _flaps: Array[Node3D] = []  # wings (FlapL, FlapR)
var _pulse: Node3D  # the part of a blob or spirit that breathes
var _model: Node3D  # a fantasy creature's body (leans when hit, sinks when it dies)
var _own: Array[StandardMaterial3D] = []  # a fantasy creature's own materials, one per kind of part
var _own_base: Array[Color] = []  # their colours before any tint
var _walk_phase := 0.0
var _flinch := 0.0  # 1 right after a hit, fades: the body leans back
var _chips := Color(0, 0, 0, 0)  # what flies off a fantasy creature when hit (stats "debris"); alpha 0 = blood
var _falling := false
static var limbs_move := true  # graphics tier: on the lowest one fantasy creatures glide without swinging limbs or beating wings
var _swing_left := 0.0
var _strike_at := 0.0  # a wound-up melee blow lands at this engine time (0 = none coming); stats "attack_windup"
var _windup := 0.0  # how long that wind-up is (for the tell: the body rears back)
var _lunge := 0.0  # 1 right after the blow, fades: the body throws itself forward
var _hold_until := 0.0  # winding up a special attack (game/boss_moves.gd): stands still, no ordinary attacks
var _rally_until := 0.0  # a war cry: faster and harder until this engine time
var _rally_speed := 1.0
var _rally_damage := 1.0
var _guard_until := 0.0  # behind its shield: takes only _guard_mult of every hit until this engine time (a stagger ends it)
var _guard_mult := 1.0
var _crawling := false  # see cripple()
var _blocked := 0.0  # seconds it has been walking without getting anywhere
var _dodge_until := 0.0  # it walks turned aside until this engine time ...
var _dodge_side := 1.0  # ... to this side (+1 / -1)


# Call before add_child.
func configure(id: String, stats: Dictionary, target: Node3D, pool: Node3D, blood: Node3D) -> void:
	enemy_id = id
	_stats = stats
	_target = target
	_pool = pool
	_blood = blood
	health = HealthState.new(float(stats["max_hp"]))
	_brain = EnemyBrain.new(stats)
	_speed = float(stats["speed"])
	var s: Array = stats["size"]
	_size = Vector3(s[0], s[1], s[2])
	var c: Array = stats["color"]
	_accent = Color(c[0], c[1], c[2])


# Optional "body_color" in the enemy data re-skins a model (raiders, ferals, the wasteland bosses).
func _body_color(default: Color) -> Color:
	if _stats.has("body_color"):
		var c: Array = _stats["body_color"]
		return Color(c[0], c[1], c[2])
	return default


# Online host: which player the boss chases and shoots at.
func set_target(target: Node3D) -> void:
	_target = target


# How far its blow or shot reaches (metres).
func reach() -> float:
	return float(_stats["attack_range"])


func head_height() -> float:
	return _size.y


# Left crawling (a blast took a good part of it, data/island_rounds.json "cripple"): from now on it drags itself
# along at `pace` times its speed, bent to the ground.
func cripple(pace: float) -> void:
	if _crawling or puppet:
		return
	_crawling = true
	_speed *= pace


func crawling() -> bool:
	return _crawling


# True when a hit at `point` landed on the head: the top `share` of the height (the enemy's own "head_share" in
# data/enemies.json wins; 0 = this thing has no head).
func head_hit(point: Vector3, share: float) -> bool:
	var part := float(_stats.get("head_share", share))
	return part > 0.0 and point.y >= global_position.y + _size.y * (1.0 - part)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 3  # world + player (1) and other enemies (2)
	if elite != "":
		var tag := Label3D.new()
		tag.text = "ELITE  %s" % elite
		tag.font_size = 40
		tag.pixel_size = 0.006
		tag.modulate = Color(1.0, 0.8, 0.25)
		tag.outline_size = 10
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position.y = _size.y + 0.6
		add_child(tag)

	var model_name := String(_stats.get("model", "box"))
	if model_name.begins_with("skeleton_"):
		var bone := _body_color(BONE_COLOR)
		_base_color = bone if element == "physical" else bone.lerp(element_tint, 0.6)
		_flash_color = BONE_FLASH
		_material.albedo_color = _base_color
		var model := CharacterModels.skeleton(model_name.trim_prefix("skeleton_"), _material, _accent)
		model.scale = Vector3.ONE * (_size.y / 1.8)
		add_child(model)
		if element != "physical":
			_decor = CharacterModels.element_decor(element, element_tint)
			model.add_child(_decor)
		_leg_l = model.get_node_or_null("LegL")
		_leg_r = model.get_node_or_null("LegR")
		if model_name == "skeleton_sword":
			_sword_arm = model.get_node_or_null("ArmR")
	elif model_name == "clockwork_bear":
		_base_color = _body_color(BRASS)
		_flash_color = BONE_FLASH
		_material.albedo_color = _base_color
		var bear := CharacterModels.clockwork_bear(_material, _accent)
		bear.scale = Vector3.ONE * (_size.y / 1.8)
		add_child(bear)
		_leg_l = bear.get_node_or_null("LegL")
		_leg_r = bear.get_node_or_null("LegR")
		_wind_key = bear.get_node_or_null("Key")
	elif CharacterModels.has_wastelander(model_name):
		var cloth := _body_color(Color(0.5, 0.45, 0.4))
		_base_color = cloth if element == "physical" else cloth.lerp(element_tint, 0.6)
		_flash_color = BONE_FLASH
		_material.albedo_color = _base_color
		var person := CharacterModels.wastelander(model_name, _material, _accent)
		person.scale = Vector3.ONE * (_size.y / 1.8)
		add_child(person)
		_leg_l = person.get_node_or_null("LegL")
		_leg_r = person.get_node_or_null("LegR")
		if _stats["attack_type"] == "melee":
			_sword_arm = person.get_node_or_null("ArmR")
	elif FantasyModels.has_creature(model_name):
		_base_color = Color.WHITE if element == "physical" else Color.WHITE.lerp(element_tint, 0.5)  # the model carries its own colours
		_flash_color = BONE_FLASH
		var creature := FantasyModels.creature(model_name, _accent, _own)
		for mat in _own:
			_own_base.append(mat.albedo_color)
		_set_tint(_base_color)
		creature.scale = Vector3.ONE * (_size.y / maxf(FantasyModels.bounds(creature).end.y, 0.1))
		if _stats.has("debris"):
			var chip: Array = _stats["debris"]
			_chips = Color(chip[0], chip[1], chip[2], 1.0)
		add_child(creature)
		_model = creature
		for found in creature.find_children("Swing*", "Node3D", true, false):
			_swings.append(found as Node3D)
		for found in creature.find_children("Flap*", "Node3D", true, false):
			_flaps.append(found as Node3D)
		_pulse = creature.find_child("Pulse", true, false) as Node3D
		if _stats["attack_type"] == "melee":
			_sword_arm = creature.find_child("ArmR", true, false) as Node3D
	else:
		_base_color = _accent
		_flash_color = BOX_FLASH
		_material.albedo_color = _base_color
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = _size
		mesh.mesh = box
		mesh.position.y = _size.y * 0.5
		mesh.material_override = _material
		add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = _size
	shape.shape = box_shape
	shape.position.y = _size.y * 0.5
	add_child(shape)


# The wave director hands over the run's effects after configure().
func set_run_fx(fx: Dictionary) -> void:
	run_fx = fx
	_berserk_at = health.max_hp * float(fx.get("berserk_below", 0.0))


func _physics_process(delta: float) -> void:
	if _falling:
		return
	if _berserk_at > 0.0 and health.hp <= _berserk_at:  # Berserkers: nearly dead, it gets faster and hits harder
		_berserk_at = 0.0
		var rage := float(run_fx.get("berserk_mult", 1.0))
		_speed *= rage
		_stats = _stats.duplicate()
		_stats["damage"] = float(_stats["damage"]) * rage
	if puppet:
		var d := net_pos - position
		velocity = Vector3(d.x, 0.0, d.z) * 8.0  # only drives the walk animation
		var k := 1.0 - exp(-10.0 * delta)
		position = position.lerp(net_pos, k)
		rotation.y = lerp_angle(rotation.y, net_yaw, k)
		_animate(delta)
		return
	if not is_instance_valid(_target):
		return
	if not walker.is_valid() and not is_on_floor():
		velocity.y -= _gravity * delta

	var flat := _target.global_position - global_position
	flat.y = 0.0
	var distance := flat.length()
	var dir := flat / distance if distance > 0.01 else Vector3.ZERO
	if distance > 0.01:
		rotation.y = atan2(-dir.x, -dir.z)
	var now := Time.get_ticks_msec() / 1000.0
	var move := _brain.move_sign(distance) * _speed * (1.0 - _slow_amount if now < _slow_until else 1.0)
	if now < _burn_until and now >= _burn_tick:
		_burn_tick = now + 0.5
		on_hit(_burn_dps * 0.5)
	var frozen := now < _freeze_until
	if frozen:
		move = 0.0
		_strike_at = 0.0  # a stagger breaks off the blow it was winding up
	if now < _rally_until:
		move *= _rally_speed
	var walk := dir * move
	var ordered := now < order_until
	if ordered and not frozen:  # a squad order: go where the squad wants this one, still facing the target
		var to_goal := order_goal - global_position
		to_goal.y = 0.0
		var pace := _speed * (1.0 - _slow_amount if now < _slow_until else 1.0) * (_rally_speed if now < _rally_until else 1.0)
		walk = to_goal.normalized() * pace if to_goal.length() > 0.4 else Vector3.ZERO
	var busy := _strike_at > 0.0 or now < _hold_until
	if busy:
		walk = Vector3.ZERO  # rooted while it winds up: the moment to step aside
	if now < _dodge_until:
		walk = walk.rotated(Vector3.UP, _dodge_side * DODGE_TURN)  # going round whatever stood in the way
	velocity.x = walk.x + _push.x
	velocity.z = walk.z + _push.z
	_push = _push.move_toward(Vector3.ZERO, PUSH_DECAY * delta)
	if walker.is_valid():
		var before := position
		position = walker.call(position, Vector3(velocity.x, 0.0, velocity.z) * delta)
		velocity.x = (position.x - before.x) / maxf(delta, 0.001)  # the legs swing by what was really walked
		velocity.z = (position.z - before.z) / maxf(delta, 0.001)
	else:
		move_and_slide()
		# Walking straight at its prey it can run into a rock, a tree or the back of another enemy: when it gets
		# nowhere for a moment it turns aside for a while, and keeps to that side while the same thing blocks it.
		var wanted := Vector2(walk.x, walk.z).length()
		var real := get_real_velocity()
		if wanted > 0.5 and Vector2(real.x, real.z).length() < wanted * 0.3:
			_blocked += delta
			if _blocked > 0.35 and now >= _dodge_until:
				_blocked = 0.0
				if now - _dodge_until > 3.0:
					_dodge_side = 1.0 if randf() < 0.5 else -1.0
				_dodge_until = now + 0.8
		else:
			_blocked = 0.0

	if frozen:
		return
	_animate(delta)
	if _strike_at > 0.0 and now >= _strike_at:
		_strike_at = 0.0
		_land_blow(distance)
	elif not busy and (order_attack or not ordered) and _brain.try_attack(distance, now):
		_attack()


func on_hit(damage: float, point: Vector3 = Vector3.ZERO, normal: Vector3 = Vector3.UP) -> void:
	if health.is_dead():
		return
	var spot := point if point != Vector3.ZERO else global_position + Vector3(0, _size.y * 0.6, 0)
	_flinch = 1.0
	if puppet:
		puppet_hit.emit(damage)  # the host decides the real damage
		_blood.burst(spot, normal, false, _chips)
		_set_tint(_flash_color)
		get_tree().create_timer(0.1).timeout.connect(_reset_color)
		return
	if Time.get_ticks_msec() / 1000.0 < _vuln_until:
		damage *= _vuln_mult
	if Time.get_ticks_msec() / 1000.0 < _guard_until:
		damage *= _guard_mult
	if one_blow.is_valid() and bool(one_blow.call()) and not enemy_id.begins_with("boss"):
		damage = maxf(damage, float(health.hp))
	if run_fx.has("boss_body_damage") and enemy_id.begins_with("boss") and not head_hit(spot, 0.17):
		damage *= float(run_fx["boss_body_damage"])  # Bulletproof Bosses: only headshots count in full
	health.take_damage(damage)
	if health.is_dead():
		_blood.burst(spot, normal, true, _chips)
		died.emit(self)
		fall()
		return
	_blood.burst(spot, normal, false, _chips)
	_set_tint(_flash_color)
	get_tree().create_timer(0.1).timeout.connect(_reset_color)


# Gun buffs: slow by `amount` (0..1) for `seconds`, set on fire for `dps` damage per second.
func apply_slow(amount: float, seconds: float) -> void:
	if puppet:
		puppet_effect.emit("slow", amount, seconds)
		return
	_slow_amount = clampf(amount, 0.0, 0.8)
	_slow_until = Time.get_ticks_msec() / 1000.0 + seconds


func apply_burn(dps: float, seconds: float) -> void:
	if puppet:
		puppet_effect.emit("burn", dps, seconds)
		return
	_burn_dps = dps
	_burn_until = Time.get_ticks_msec() / 1000.0 + seconds


# Skills: stand still for `seconds` (tinted icy blue).
func apply_freeze(seconds: float) -> void:
	if puppet:
		puppet_effect.emit("freeze", 0.0, seconds)
		return
	_freeze_until = maxf(_freeze_until, Time.get_ticks_msec() / 1000.0 + seconds)
	_guard_until = 0.0  # a stagger knocks its guard down
	_set_tint(Color(0.6, 0.85, 1.0))
	get_tree().create_timer(seconds).timeout.connect(_reset_color)


# Skills/buffs: damage taken is multiplied by `mult` for `seconds` (the strongest active multiplier counts).
func apply_vulnerable(mult: float, seconds: float) -> void:
	if puppet:
		puppet_effect.emit("weaken", mult, seconds)
		return
	var now := Time.get_ticks_msec() / 1000.0
	_vuln_mult = maxf(mult, _vuln_mult if now < _vuln_until else 1.0)
	_vuln_until = maxf(_vuln_until, now + seconds)


# Skills: sets a knockback or pull velocity (m/s, flat) that fades quickly. Bosses and puppets ignore it.
func push(v: Vector3) -> void:
	if puppet and not enemy_id.begins_with("boss"):
		puppet_effect.emit("push", v.x, v.z)
	if puppet or enemy_id.begins_with("boss"):
		return
	_push = Vector3(v.x, 0.0, v.z)


# Online: the host says this puppet died.
func die_now() -> void:
	_blood.burst(global_position + Vector3(0, _size.y * 0.6, 0), Vector3.UP, true, _chips)
	died.emit(self)
	fall()


# A blow from another creature (the fantasy tribes fight each other). A killing blow pays nobody: `felled`.
func take_damage(amount: float, _element: String = "physical") -> void:
	if puppet or _falling or health.is_dead():
		return
	set_meta("feud_hit", true)
	var blow := amount * (_vuln_mult if Time.get_ticks_msec() / 1000.0 < _vuln_until else 1.0)  # as on_hit will count it
	if blow < health.hp:
		on_hit(amount)
		return
	health.take_damage(amount)
	_blood.burst(global_position + Vector3(0, _size.y * 0.6, 0), Vector3.UP, true, _chips)
	felled.emit(self)
	fall()


# The body goes down and is cleared away. A modelled fantasy creature topples (or flattens, if it is a blob or a
# spirit) and sinks into the ground; everything else is gone at once, as before.
func fall() -> void:
	if _falling:
		return
	_falling = true
	collision_layer = 0
	collision_mask = 0
	if _model == null:
		queue_free()
		return
	var tween := create_tween()
	if _pulse != null:
		tween.tween_property(_model, "scale", _model.scale * Vector3(1.5, 0.06, 1.5), 0.45).set_ease(Tween.EASE_IN)
	else:
		tween.tween_property(_model, "rotation:z", (PI * 0.48) * (1.0 if randf() < 0.5 else -1.0), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(1.6)
	tween.tween_property(self, "position:y", position.y - maxf(_size.y, _size.x) * 0.9, 1.2)
	tween.tween_callback(queue_free)


func _reset_color() -> void:
	_set_tint(_base_color)


# Colours the whole body: the one shared material of the older models, or each of a fantasy creature's own.
func _set_tint(color: Color) -> void:
	_material.albedo_color = color
	for i in _own.size():
		_own[i].albedo_color = _own_base[i] * color


func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if _model != null:
		_flinch = move_toward(_flinch, 0.0, delta * 5.0)
		_lunge = move_toward(_lunge, 0.0, delta * 6.0)
		var tell := 0.0  # winding up a blow: it rears back, then throws itself forward
		if _strike_at > 0.0 and _windup > 0.0:
			tell = 1.0 - clampf((_strike_at - Time.get_ticks_msec() / 1000.0) / _windup, 0.0, 1.0)
		_model.rotation.x = 0.2 * _flinch + 0.4 * tell - 0.55 * _lunge - (1.25 if _crawling else 0.0)
	_walk_phase += speed * delta * 1.6
	if _leg_l != null:
		var swing := sin(_walk_phase) * WALK_SWING * clampf(speed / 3.0, 0.0, 1.0)
		_leg_l.rotation.x = swing
		_leg_r.rotation.x = -swing
	if limbs_move and (not _swings.is_empty() or not _flaps.is_empty() or _pulse != null):
		var beat := Time.get_ticks_msec() / 1000.0
		var stride := sin(_walk_phase) * WALK_SWING * clampf(speed / 3.0, 0.0, 1.0)
		for part in _swings:
			part.rotation.x = stride if String(part.name).begins_with("SwingA") else -stride
		for part in _flaps:
			part.rotation.z = (0.25 + sin(beat * 7.0) * 0.45) * (1.0 if String(part.name) == "FlapL" else -1.0)
		if _pulse != null:
			var breath := sin(beat * 4.0) * 0.06
			_pulse.scale = Vector3(1.0 + breath, 1.0 - breath, 1.0 + breath)
	if _decor != null:
		var t := Time.get_ticks_msec() / 1000.0
		if element == "toxic":
			_decor.rotation.y += delta * 2.0
		elif element == "fire":
			_decor.scale = Vector3(1.0, 1.0 + 0.12 * sin(t * 14.0), 1.0)
	if _wind_key != null:
		_wind_key.rotation.z += delta * 2.5
	if _sword_arm != null:
		if _swing_left > 0.0:
			_swing_left -= delta
			_sword_arm.rotation.x = lerpf(deg_to_rad(-150.0), deg_to_rad(60.0), 1.0 - maxf(_swing_left, 0.0) / SWING_TIME)
		else:
			_sword_arm.rotation.x = deg_to_rad(50.0)


func _attack() -> void:
	var damage := float(_stats["damage"])
	if _stats["attack_type"] == "melee":
		_swing_left = SWING_TIME
		_windup = float(_stats.get("attack_windup", 0.0))
		if _windup > 0.0:  # it rears back first; the blow lands when the wind-up is over, if the target is still there
			_strike_at = Time.get_ticks_msec() / 1000.0 + _windup
			_set_tint(Color(1.5, 1.35, 0.9))
			_say("atk_windup")
		else:
			_land_blow(0.0)
		return
	var origin := global_position + Vector3(0, _size.y * 0.7, 0)
	var aim := (_target.global_position + Vector3(0, AIM_HEIGHT, 0) - origin).normalized()
	attacked.emit(origin, aim)
	shoot_burst(origin, aim)


func _say(id: String) -> void:
	if sounds != null and id != "":
		sounds.call("play", id, global_position + Vector3(0.0, _size.y * 0.6, 0.0))


# The melee blow itself. `distance` = how far the target is now (it may have stepped away during the wind-up).
func _land_blow(distance: float) -> void:
	if _windup > 0.0:
		_reset_color()
		_lunge = 1.0
	_say(String(_stats.get("attack_sound", "")))
	if not is_instance_valid(_target) or distance > float(_stats["attack_range"]) * 1.3 + 0.3 or not _target.has_method("take_damage"):
		return  # a miss (or it swung at a place, not at somebody: the boards of a window)
	var damage := float(_stats["damage"]) * (_rally_damage if Time.get_ticks_msec() / 1000.0 < _rally_until else 1.0)
	_target.set("struck_by", self)  # a ward needs to know where the blow comes from (and whom to throw it back at)
	_target.take_damage(damage, element)
	if run_fx.has("vampire"):  # Vampires: it heals by what it hit for
		health.heal(damage * float(run_fx["vampire"]))


# A special attack is being wound up: stand still and leave ordinary attacks for `seconds`.
func hold(seconds: float) -> void:
	_hold_until = maxf(_hold_until, Time.get_ticks_msec() / 1000.0 + seconds)


# It raises its guard: only `taken` of every hit gets through for `seconds`, unless something staggers it.
func guard(taken: float, seconds: float) -> void:
	_guard_until = Time.get_ticks_msec() / 1000.0 + seconds
	_guard_mult = taken


# A war cry reached it: faster and harder for `seconds`.
func rally(speed_mult: float, damage_mult: float, seconds: float) -> void:
	_rally_until = Time.get_ticks_msec() / 1000.0 + seconds
	_rally_speed = speed_mult
	_rally_damage = damage_mult


# One shot of this enemy's projectile kind with its own speed and damage (a boss's special volley).
func shoot(origin: Vector3, aim: Vector3, speed: float, damage: float) -> void:
	_pool.fire(origin, aim.normalized(), speed, damage, element)


# Fires this enemy's projectile burst (also used to show the boss's attacks decided on the host).
func shoot_burst(origin: Vector3, aim: Vector3) -> void:
	_say(String(_stats.get("attack_sound", "")))
	var damage := float(_stats["damage"])
	var side := aim.cross(Vector3.UP).normalized()
	var burst := int(_stats["burst"])
	var spread := float(_stats["burst_spread"])
	var speed := float(_stats["projectile_speed"])
	for i in burst:
		var offset := i - (burst - 1) * 0.5
		_pool.fire(origin, (aim + side * offset * spread).normalized(), speed, damage, element)
