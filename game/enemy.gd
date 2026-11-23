# Purpose: one enemy (skeleton swordsman, skeleton archer, clockwork bear boss, a modelled wastelander or a fantasy creature): chases the player and attacks using stats from data/enemies.json.
# Dependencies: core/health_state.gd, core/enemy_brain.gd, game/character_models.gd, game/fantasy_models.gd. Projectile pool, blood effects and target are passed in by game/wave_director.gd.
extends CharacterBody3D

signal died(enemy: Node)
signal attacked(origin: Vector3, aim: Vector3)  # a ranged attack started (online: the host tells other machines to show it)
signal puppet_hit(damage: float)  # a puppet was shot (online: the damage goes to the host as an intent)
signal felled(enemy: Node)  # killed by another creature, not by a player: nobody is paid (the fantasy tribes fighting each other)
signal puppet_effect(kind: String, amount: float, seconds: float)
signal cut_done(way: int)  # (polish1 D4d) a rope-cutter finished cutting this treetop way (the host's island rounds pass it on)  # a puppet was slowed, burned, frozen, weakened or pushed (the host decides if it sticks)

const GullFeast = preload("res://game/gull_feast.gd")
const HealthState = preload("res://core/health_state.gd")
const EnemyBrain = preload("res://core/enemy_brain.gd")
const CharacterModels = preload("res://game/character_models.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const EnemyRig = preload("res://game/enemy_rig.gd")
const RigidSkin = preload("res://game/rigid_skin.gd")

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
var nav_map := RID()  # (polish1 D4a) island enemies: the islands' navigation map (game/island_nav.gd); unset = straight at the target
var route := Callable()  # (polish1 D4d) climbing enemies: func(from: Vector3, to: Vector3) -> Dictionary (core/treetop_rules.gd route, world spots)
var cut_job := Callable()  # (polish1 D4d) rope-cutters: func(from: Vector3) -> {"way", "at": Vector3 world} or {} (the nearest bought rope way)
var _plan := {}
var _plan_at := 0.0
var _climb := {}  # while climbing: {"points": [Vector3 world ...], "i": int}
var _cut := {}
var _cut_held := 0.0
var _orbit := 0.0  # gliders: where round its prey it cruises
var _swoop := false
var _climb_at := 0.0  # (no climbing again for a moment after one: it may have to walk off first)
var _cut_rest := 0.0  # a rope-cutter hunts players until this engine time after each cut
var _path := PackedVector3Array()
var _path_i := 0
var _path_at := 0.0
var _path_goal := Vector3.INF
var feud := ""  # fantasy tribes: the banner this warrior fights for ("" = none)
var _near_t := 0.0  # (polish1 item 153) time to the next close-by sound
var sounds: Node  # the game's sound player (game/fantasy_sounds.gd with data/sounds.json), set by game/wave_director.gd; null = silent
var order_goal := Vector3.INF  # squad order (game/squad_command.gd): walk to this spot instead of straight at the target
var order_attack := true  # squad order: it may strike now (false = it waits its turn)
var order_until := 0.0  # engine time the order stops counting (orders are renewed a few times a second)
var space: Node3D = null  # sea crews (sea step 8b): it walks and faces in this node's space (its ship's deck, with a deck walker)
var aim_fix := Callable()  # sea crews: func(origin, aim, target) -> aim: leads a target on a moving ship (null = straight at him)
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
var _taunt_by: Node3D  # taunted: chases this one until _taunt_until (taunt)
var _taunt_until := 0.0
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
var _rig: EnemyRig  # (polish1 D2) a reworked enemy's own animation (game/enemy_rig.gd), null for the older models
var _skin: Skeleton3D  # (bug update) the folded model: shots are tested against its pieces where they are this frame
var _boxes: Array = []  # each bone's piece box (bone space), game/rigid_skin.gd parts()
var _heads := PackedByteArray()
var _reach := 0.0  # metres from the feet to the farthest piece (scaled)
var _pad := 0.03  # a piece's box grows this much (bone units) so thin parts are not missed
static var _moves := {}  # data/enemy_moves.json styles, read once
static var _glow_material: StandardMaterial3D  # Keeper's Lantern glow, shared by every enemy
var _glowing := false
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
var _dodge_from := Vector3.INF  # (polish1 item 144) where its last run of turning aside began ...
var _dodge_tries := 0  # ... and how many times it turned aside there without getting a metre away
var _temper := ""  # a wild animal (stats "temper"): skittish runs away, defensive fights back when pressed; "" = always hunts
var _provoked_until := 0.0  # hurt (or crowded, if defensive) until this engine time
var _wander_at := 0.0  # a wandering animal picks a new way to amble at this engine time ...
var _wander_yaw := 0.0
var _wander_go := false  # ... and whether it walks or stands grazing


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
	_temper = String(stats.get("temper", ""))
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
	if is_instance_valid(_taunt_by) and Time.get_ticks_msec() / 1000.0 < _taunt_until:
		return  # taunted: it keeps after whoever taunted it
	_target = target


# Key Ring's jingle, Golden Goose's honk: it comes for `by` for `seconds` (a puppet asks the host: game/net_rounds.gd).
func taunt(by: Node3D, seconds: float) -> void:
	if puppet:
		puppet_effect.emit("taunt", 0.0, seconds)
		return
	_taunt_by = by
	_taunt_until = Time.get_ticks_msec() / 1000.0 + seconds
	_target = by


# What it chases now (a gun skill's decoy hands it back afterwards: game/skill_summons.gd).
func current_target() -> Node3D:
	return _target


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
	if _skin != null and not _boxes.is_empty():  # (bug update) a reworked enemy: the point is on (or by) a head piece
		var sk := _skin.global_transform
		for i in _boxes.size():
			if _heads[i] == 0 or (_boxes[i] as AABB).size == Vector3.ZERO:
				continue
			var xf := sk * _skin.get_bone_global_pose(i)
			if xf.basis.x.length_squared() < 1e-6:
				continue
			if (_boxes[i] as AABB).grow(_pad * 3.0).has_point(xf.affine_inverse() * point):
				return true
		return false
	var part := float(_stats.get("head_share", share))
	return part > 0.0 and point.y >= global_position.y + _size.y * (1.0 - part)


# (bug update) Where its head is now (the middle of the head piece; the old head zone for older models).
func head_point() -> Vector3:
	if _skin != null and not _boxes.is_empty():
		var hb := _skin.find_bone("Head")
		if hb >= 0 and (_boxes[hb] as AABB).size != Vector3.ZERO:
			return _skin.global_transform * _skin.get_bone_global_pose(hb) * (_boxes[hb] as AABB).get_center()
	return global_position + Vector3(0.0, _size.y * 0.93, 0.0)


# (bug update) The top of the shown pieces at rest, in the model's own (unscaled) space.
func _parts_top() -> float:
	var top := 0.0
	for i in _boxes.size():
		var box: AABB = _boxes[i]
		if box.size == Vector3.ZERO:
			continue
		var xf := _skin.get_bone_global_pose(i)
		if xf.basis.x.length_squared() < 1e-6:
			continue
		for c in 8:
			top = maxf(top, (xf * box.get_endpoint(c)).y)
	return top


# (bug update) Where the segment from..to first meets one of this enemy's pieces as they stand this frame:
# {position, normal, head} or {} (missed, dead, or not a reworked model). Used for gunshots (game/player.gd _shot_ray).
func ray_parts(from: Vector3, to: Vector3) -> Dictionary:
	if _skin == null or _boxes.is_empty() or health.is_dead():
		return {}
	var centre := global_position + Vector3(0.0, _reach * 0.5, 0.0)
	var seg := to - from
	var along := clampf((centre - from).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
	if (from + seg * along).distance_to(centre) > _reach * 0.8 + 0.5:
		return {}
	var sk := _skin.global_transform
	var best := {}
	var best_d := INF
	var head := {}
	var head_d := INF
	for i in _boxes.size():
		var box: AABB = _boxes[i]
		if box.size == Vector3.ZERO:
			continue
		var xf := sk * _skin.get_bone_global_pose(i)
		if xf.basis.x.length_squared() < 1e-6:  # a variant not shown (its bones shrink to nothing)
			continue
		var inv := xf.affine_inverse()
		var met: Variant = box.grow(_pad).intersects_segment(inv * from, inv * to)
		if met == null:
			continue
		var point: Vector3 = xf * (met as Vector3)
		var d := from.distance_squared_to(point)
		if _heads[i] == 1 and d < head_d:  # a shot through a head piece counts on the head even where a bulky body
			head_d = d  # piece's box (armour, a hump, a collar) wraps round it
			head = {"position": point, "normal": (point - xf * box.get_center()).normalized(), "head": true}
		if d < best_d:
			best_d = d
			best = {"position": point, "normal": (point - xf * box.get_center()).normalized(), "head": _heads[i] == 1}
	return head if not head.is_empty() else best


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
		if EnemyRig.rigged(creature):  # (polish1 D2) its own gait, idle, blows and death; one of its variants
			if _moves.is_empty():
				_moves = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_moves.json"))
			var dice := RandomNumberGenerator.new()
			dice.randomize()
			_skin = RigidSkin.fold(creature, model_name)  # one skinned mesh instead of a mesh per pivot
			var parts := RigidSkin.parts(model_name)
			_rig = EnemyRig.new()
			_rig.setup(creature, (_moves.get("styles", {}) as Dictionary).get(String(_stats.get("moves", model_name)), {}), dice)
			if _skin != null and parts.has("boxes"):  # (bug update) hit volumes = the pieces themselves
				_boxes = parts["boxes"]
				_heads = parts["heads"]
				# FantasyModels.bounds reads each piece in its pivot's space, which made the reworked models ~1.35x
				# their data height (heads above the box): measured again on the shown variant's pieces
				var top := _parts_top()
				if top > 0.1:
					creature.scale = Vector3.ONE * (_size.y / top)
				_reach = float(parts["reach"]) * creature.scale.x
				_pad = 0.03 / maxf(creature.scale.x, 0.05)
				add_to_group("hit_parts")
		elif _stats["attack_type"] == "melee":
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


# The way to the target along the navigation path (asked again every half second or when the target has moved),
# flat; ZERO when there is no path (then it goes straight as before).
func _nav_step(goal: Vector3) -> Vector3:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _path_at or goal.distance_to(_path_goal) > 2.0 or (_path_i >= _path.size() and not _path.is_empty()):
		_path = NavigationServer3D.map_get_path(nav_map, global_position, goal, true)
		_path_i = 0  # (polish1 item 144) the path's first point is where it joins the mesh: pressed against a rock it is off the mesh and goes there first, not straight at the next corner through the rock
		_path_goal = goal
		_path_at = now + randf_range(0.4, 0.6)
	while _path_i < _path.size():
		var d := _path[_path_i] - global_position
		d.y = 0.0
		if d.length() > 0.7:
			return d.normalized()
		_path_i += 1
	return Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _falling:
		if _rig != null:  # (polish1 D2) it goes limp or falls apart as it drops
			_rig.pose(delta, 0.0, _walk_phase, 0.0, 0.0, 0.0, 0.0, false)
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
	if _stats.has("near_sound"):  # (polish1 item 153) a quiet sound now and then while it closes in (crabs scuttle)
		_near_t -= delta
		if _near_t <= 0.0:
			_near_t = float(_stats.get("near_every", 1.0)) * randf_range(0.8, 1.25)
			if global_position.distance_to(_target.global_position) < float(_stats.get("near_range", 8.0)) and velocity.length() > 0.5:
				_say(String(_stats["near_sound"]))
	if not _climb.is_empty():  # (polish1 D4d) up or down a trunk or a stilt
		_climbing(delta)
		return
	if bool(_stats.get("flies", false)):  # (polish1 D4d) a glider
		_fly(delta)
		return
	if not walker.is_valid() and not is_on_floor():
		velocity.y -= _gravity * delta
	if _temper != "" and _roam(delta):
		return

	var goal := _errand()  # (polish1 D4d) climbers and rope-cutters may walk somewhere else first
	var errand := goal.is_finite()
	if not errand:
		goal = _target.global_position
	var to_target := (space.to_local(_target.global_position) - position) if space != null else _target.global_position - global_position
	to_target.y = 0.0
	var flat := (space.to_local(goal) - position) if space != null else goal - global_position
	flat.y = 0.0
	var distance := flat.length()
	var dir := flat / distance if distance > 0.01 else Vector3.ZERO
	if nav_map.is_valid() and distance > 0.6:  # (polish1 D4a) round ridges, ruins, huts and up hills by the islands' navigation mesh
		var step := _nav_step(goal)
		if step != Vector3.ZERO and (errand or distance > 2.5 or _path.size() > 2):  # (polish1 item 144) close by too when something stands between them (the way bends)
			dir = step
	if errand:
		distance = maxf(distance, to_target.length())  # (it keeps walking to its errand; blows are for its prey only)
		if _at_cut(delta):
			dir = Vector3.ZERO
	if distance > 0.01:
		rotation.y = atan2(-dir.x, -dir.z)
	var now := Time.get_ticks_msec() / 1000.0
	var level := _level_with(_target)  # (a target up on a ledge: keep going for it, the dungeon walker climbs)
	if not level and distance < 0.4:
		dir = Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))  # (right under him at the ledge's foot: on the way it faced)
	var move: float = (1.0 if errand else (float(_brain.move_sign(distance)) if level else 1.0)) * _speed * (1.0 - _slow_amount if now < _slow_until else 1.0)
	if dir == Vector3.ZERO:
		move = 0.0
	if not level and not errand and space == null and distance < 2.0:  # (bug update) its prey up on a deck it cannot climb to:
		move = 0.0  # it waits below instead of walking back and forth on the spot under him
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
				_path_at = 0.0  # (polish1 item 144) a fresh way from where it is stuck
				if global_position.distance_to(_dodge_from) < 1.0:
					_dodge_tries += 1
				else:
					_dodge_tries = 0
					_dodge_from = global_position
				if now - _dodge_until > 3.0:
					_dodge_side = 1.0 if randf() < 0.5 else -1.0
				elif _dodge_tries >= 2:  # turning that way got it nowhere twice: the other way round, for longer
					_dodge_side = -_dodge_side
					_dodge_tries = 0
				_dodge_until = now + (0.8 if _dodge_tries == 0 else 1.2)
		else:
			_blocked = 0.0

	if frozen:
		return
	_animate(delta)
	if errand:
		distance = to_target.length()
	if _strike_at > 0.0 and now >= _strike_at:
		_strike_at = 0.0
		_land_blow(distance if _level_with(_target) else INF)
	elif not busy and (order_attack or not ordered) and level and _brain.try_attack(distance, now):
		_attack()


# A melee foe in a dungeon's space reaches only a target about level with it, not one on a ledge above or below it
# (sea step 9c-2).
func _level_with(target: Node3D) -> bool:
	if String(_stats.get("attack_type", "")) != "melee":
		return true
	if space == null:  # (polish1 D4d) no clawing a player on a deck above (or below) through the planks
		return bool(_stats.get("flies", false)) or absf(target.global_position.y - global_position.y) <= 2.2
	if not space.has_method("usable_at"):
		return true  # (only in a dungeon's space: decks keep their old reach)
	return absf(space.to_local(target.global_position).y - position.y) <= 1.2


# (polish1 D4d) A climber's or rope-cutter's next place to walk to (world), INF = straight for its prey. Starts a climb
# when it stands at one.
func _errand() -> Vector3:
	var now := Time.get_ticks_msec() / 1000.0
	var wants := _target.global_position
	if bool(_stats.get("cuts", false)) and cut_job.is_valid() and now >= _cut_rest:
		if now >= _plan_at or _cut.is_empty():
			_cut = cut_job.call(global_position)
		if not _cut.is_empty():
			wants = _cut["at"]
	if not bool(_stats.get("climbs", false)) or not route.is_valid():
		return wants if not _cut.is_empty() else Vector3.INF
	if now >= _plan_at:
		_plan_at = now + randf_range(0.4, 0.6)
		_plan = route.call(global_position, wants)
	if _plan.has("climb") and now >= _climb_at:
		var start: Vector3 = _plan["climb"][0]
		var end: Vector3 = _plan["climb"][1]
		if Vector2(start.x - global_position.x, start.z - global_position.z).length() < 0.9 and absf(start.y - global_position.y) < 1.4:
			var over := maxf(start.y, end.y) + 1.4  # over the railing
			var pts: Array = [Vector3(start.x, over, start.z), Vector3(end.x, over, end.z), end] if end.y > start.y else [Vector3(start.x, over, start.z), Vector3(end.x, over, end.z), end]
			_climb = {"points": pts, "i": 0}
			collision_mask = 0  # (through the railing and leaves while it climbs; bullets still find it)
			_plan = {}
			return Vector3.INF
	if _plan.has("goal"):
		return _plan["goal"]
	return wants if not _cut.is_empty() else Vector3.INF


# A rope-cutter at its rope: it stands and cuts; when done the way falls (cut_done). True while it is cutting.
func _at_cut(delta: float) -> bool:
	if _cut.is_empty():
		return false
	var at: Vector3 = _cut["at"]
	if Vector2(at.x - global_position.x, at.z - global_position.z).length() > 1.3 or absf(at.y - global_position.y) > 1.5:
		_cut_held = 0.0
		return false
	_cut_held += delta
	if _cut_held >= float(_stats.get("cut_seconds", 2.5)):
		_cut_held = 0.0
		cut_done.emit(int(_cut["way"]))
		_cut = {}
		_plan_at = 0.0
		_cut_rest = Time.get_ticks_msec() / 1000.0 + 12.0
	return true


# Up or down along its climbing points at climb_speed, then back to walking.
func _climbing(delta: float) -> void:
	var pts: Array = _climb["points"]
	var i := int(_climb["i"])
	var to: Vector3 = pts[i]
	var step := float(_stats.get("climb_speed", 3.0)) * delta
	var d := to - global_position
	if d.length() <= step:
		global_position = to
		_climb["i"] = i + 1
		if i + 1 >= pts.size():
			_climb = {}
			collision_mask = 3
			velocity = Vector3.ZERO
			_climb_at = Time.get_ticks_msec() / 1000.0 + 1.0
	else:
		global_position += d / d.length() * step
		if absf(d.y) < 0.1:
			rotation.y = atan2(-d.x, -d.z)
	velocity = d.normalized() * float(_stats.get("climb_speed", 3.0))  # (drives the limbs)
	if _rig != null:
		_rig.climbing = not _climb.is_empty()
	_animate(delta)


# (polish1 D4d) A glider: cruises a few metres over its prey, circling, swoops in for a blow and climbs away again.
func _fly(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var prey := _target.global_position + Vector3(0, 1.2, 0)
	var me := global_position + Vector3(0, _size.y * 0.5, 0)
	_orbit += delta * 0.6
	var goal := prey + Vector3(cos(_orbit) * 6.0, float(_stats.get("cruise", 4.0)), sin(_orbit) * 6.0)
	if not _swoop and _brain.ready_at(now) and me.distance_to(prey) < 14.0:
		_swoop = true
	if _swoop:
		goal = prey
	var to := goal - me
	var pace := _speed * (1.0 - _slow_amount if now < _slow_until else 1.0)
	if now < _freeze_until:
		pace = 0.0
	velocity = to.normalized() * minf(pace, to.length() * 3.0) + _push
	_push = _push.move_toward(Vector3.ZERO, PUSH_DECAY * delta)
	move_and_slide()
	if is_on_wall() or is_on_ceiling():
		global_position.y += 2.0 * delta  # (over what is in the way)
	if Vector2(velocity.x, velocity.z).length() > 0.3:
		rotation.y = atan2(-velocity.x, -velocity.z)
	_animate(delta)
	if _strike_at > 0.0 and now >= _strike_at:
		_strike_at = 0.0
		_land_blow(me.distance_to(prey))
		_swoop = false
	elif _swoop and me.distance_to(prey) <= float(_stats["attack_range"]) and _brain.try_attack(me.distance_to(prey), now):
		_attack()
		if _strike_at <= 0.0:
			_swoop = false


func on_hit(damage: float, point: Vector3 = Vector3.ZERO, normal: Vector3 = Vector3.UP) -> void:
	if health.is_dead():
		return
	_provoked_until = Time.get_ticks_msec() / 1000.0 + 12.0  # a wild animal that is hurt runs (or turns on you)
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


# A wild animal (stats "temper") while it is not fighting: it ambles and grazes, and runs straight away from anyone
# within notice_m metres or who has hurt it; a defensive one instead turns to fight (the ordinary chase) when hurt or
# crowded. Returns true while it is not fighting.
func _roam(delta: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var away := global_position - _target.global_position
	away.y = 0.0
	var near := away.length() < float(_stats.get("notice_m", 12.0))
	if _temper == "defensive" and (near or now < _provoked_until):
		if near:
			_provoked_until = maxf(_provoked_until, now + 6.0)
		return false
	if near:  # startled: it keeps running for a few seconds, well clear of whoever came close
		_provoked_until = maxf(_provoked_until, now + 4.0)
	var walk := Vector3.ZERO
	if now < _provoked_until:
		walk = away.normalized() * _speed
	else:
		if now >= _wander_at:
			_wander_at = now + randf_range(2.5, 6.0)
			_wander_yaw = randf() * TAU
			_wander_go = randf() < 0.55
		if _wander_go:
			walk = Vector3(-sin(_wander_yaw), 0.0, -cos(_wander_yaw)) * _speed * 0.22
	if now < _freeze_until:
		walk = Vector3.ZERO
	elif now < _slow_until:
		walk *= 1.0 - _slow_amount
	if now < _burn_until and now >= _burn_tick:
		_burn_tick = now + 0.5
		on_hit(_burn_dps * 0.5)
		if _falling or health.is_dead():
			return true
	if walk.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-walk.x, -walk.z), 1.0 - exp(-8.0 * delta))
	velocity.x = walk.x + _push.x
	velocity.z = walk.z + _push.z
	_push = _push.move_toward(Vector3.ZERO, PUSH_DECAY * delta)
	if walker.is_valid():
		var before := position
		position = walker.call(position, Vector3(velocity.x, 0.0, velocity.z) * delta)
		velocity.x = (position.x - before.x) / maxf(delta, 0.001)
		velocity.z = (position.z - before.z) / maxf(delta, 0.001)
	else:
		move_and_slide()
	_animate(delta)
	return true


# Gun buffs: slow by `amount` (0..1) for `seconds`, set on fire for `dps` damage per second.
func apply_slow(amount: float, seconds: float) -> void:
	if puppet:
		puppet_effect.emit("slow", amount, seconds)
		return
	_slow_amount = clampf(amount, 0.0, 0.8)
	_slow_until = Time.get_ticks_msec() / 1000.0 + seconds


# Burning right now (gun buff Kindling: core data/gun_loot.json).
func is_burning() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _burn_until


func apply_burn(dps: float, seconds: float) -> void:
	if puppet:
		puppet_effect.emit("burn", dps, seconds)
		_burn_until = Time.get_ticks_msec() / 1000.0 + seconds  # (known here so is_burning answers; the host does the burning)
		return
	_burn_dps = dps
	_burn_until = Time.get_ticks_msec() / 1000.0 + seconds


# Skills: stand still for `seconds` (tinted icy blue).
func apply_freeze(seconds: float) -> void:
	if puppet:
		puppet_effect.emit("freeze", 0.0, seconds)
		_set_tint(Color(0.6, 0.85, 1.0))  # (shown here at once; the host does the freezing)
		get_tree().create_timer(seconds).timeout.connect(_reset_color)
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
	if _rig != null:
		_rig.die()
	if String(_stats.get("remains", "")) == "gulls" and _pulse == null and GullFeast.room(get_tree()):
		_gull_remains()
		return
	var tween := create_tween()
	if _pulse != null:
		tween.tween_property(_model, "scale", _model.scale * Vector3(1.5, 0.06, 1.5), 0.45).set_ease(Tween.EASE_IN)
	else:
		tween.tween_property(_model, "rotation:z", (PI * 0.48) * (1.0 if randf() < 0.5 else -1.0), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(1.6)
	tween.tween_property(self, "position:y", position.y - maxf(_size.y, _size.x) * 0.9, 1.2)
	tween.tween_callback(queue_free)


# (polish1 item 36) A crab's body stays: it flips onto its back, the gulls come down on it (game/gull_feast.gd) and it
# shrinks away while they peck, then is gone.
func _gull_remains() -> void:
	var feast := GullFeast.new()
	feast.at = global_position
	get_parent().add_child(feast)
	var tween := create_tween()
	tween.tween_property(_model, "rotation:z", PI * (1.0 if randf() < 0.5 else -1.0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(_model, "position:y", _size.y * 0.55, 0.5)
	tween.tween_interval(GullFeast.ARRIVE + 0.6)
	tween.tween_property(_model, "scale", _model.scale * 0.05, GullFeast.PECK - 0.6).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _reset_color() -> void:
	_set_tint(_base_color)


# Colours the whole body: the one shared material of the older models, or each of a fantasy creature's own.
# Lit by a Keeper's Lantern (game/lantern_glow.gd): a warm glow over the whole body, so it shows in the fog.
func set_glow(on: bool) -> void:
	if on == _glowing:
		return
	_glowing = on
	if _glow_material == null:
		_glow_material = StandardMaterial3D.new()
		_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow_material.albedo_color = Color(0.55, 0.35, 0.12)
	for mesh in find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).material_overlay = _glow_material if on else null


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
		_model.rotation.x = (0.2 * _flinch + 0.4 * tell - 0.55 * _lunge if _rig == null else 0.0) - (1.25 if _crawling else 0.0)
		if _rig != null:
			_swing_left = maxf(_swing_left - delta, 0.0)
			_rig.pose(delta, speed, _walk_phase, tell, _lunge, _swing_left / SWING_TIME, _flinch, _stats["attack_type"] != "melee")
		if _stats.has("hop"):  # (polish1 A7) it moves in hops (data "hop" = the hop's height in m)
			_model.position.y = absf(sin(_walk_phase * 0.6)) * float(_stats["hop"]) * clampf(speed / 2.0, 0.0, 1.0)
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
	if _rig != null:
		_rig.fired()
	var origin := global_position + Vector3(0, _size.y * 0.7, 0)
	var aim := (_target.global_position + Vector3(0, AIM_HEIGHT, 0) - origin).normalized()
	if aim_fix.is_valid():
		aim = aim_fix.call(origin, aim, _target)
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
	if puppet and speed_mult == 1.0 and damage_mult < 1.0:  # (sea step 12d) Soft Wing on a host-run enemy: the host softens its blows
		puppet_effect.emit("soothe", damage_mult, seconds)
		return
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
