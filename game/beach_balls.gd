# Purpose: the BEACH BALL BOMBARDIER's balls (diary/DESIGN_UNIQUES.md, region 1 chase gun): a small pool of light,
# floaty beach balls stepped on the physics tick. A ball bounces off enemies' heads (every bounce hits), off the
# ground and walls, and pops (a blast) when its bounces or time run out, when someone SHOOTS it (any gun:
# shot_through) or after it was kicked about: walking into a ball KICKS it where you look, and every kick
# (a volley) makes its pop bigger. Numbers come from the gun's data "cfg" (data/gun_uniques.json beach_ball_bombardier).
# ONLINE (game/net_beachballs.gd): our own balls are told to the others; their balls fly here as COPIES that deal no
# damage and pop only when the owner says so; kicking or shooting a copy is sent to its owner.
# Dependencies: game/explosives.gd (blast, its enemy source, damage numbers, score, sounds), game/net_beachballs.gd
# (group "net_beachballs", optional),
# assets/models/weapons/uniques/beach_ball.gltf (falls back to a plain sphere).
extends Node3D

const POOL_SIZE := 8
const MODEL := "res://assets/models/weapons/uniques/beach_ball.gltf"
const HEAD_REACH := 0.45  # metres round an enemy's head that count as touching it
const UNIQUE_ID := "beach_ball_bombardier"  # whose data "cfg" a copy uses before any ball of ours was thrown

var explosives: Node3D  # game/explosives.gd: blast(), source (enemy_list), numbers, score, sounds
var kicker: Node3D  # the local player: walking into a ball kicks it (aim_flat(), look pitch from its camera)

var _balls: Array[Node3D] = []
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _bounces := PackedInt32Array()
var _ground := PackedInt32Array()
var _volleys := PackedInt32Array()
var _damage := PackedFloat32Array()  # one head bounce's damage
var _pop := PackedFloat32Array()  # the pop's damage before volleys
var _radius := PackedFloat32Array()  # the pop's blast radius
var _kick_ready := PackedFloat32Array()  # time from which this ball may be kicked again
var _hit_ready := PackedFloat32Array()  # time from which this ball may hit a head again
var _owner := PackedInt32Array()  # 0 = our own ball; else the peer whose ball this is a copy of
var _their_slot := PackedInt32Array()  # a copy's number on its owner's machine
var _cfg: Dictionary = {}
var _query := PhysicsRayQueryParameters3D.new()
var _clock := 0.0


func _ready() -> void:
	add_to_group("beach_balls")
	var scene: PackedScene = load(MODEL) if ResourceLoader.exists(MODEL) else null
	for i in POOL_SIZE:
		var ball: Node3D
		if scene != null:
			ball = scene.instantiate() as Node3D
		else:
			var plain := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			plain.mesh = sphere
			ball = plain
		ball.visible = false
		add_child(ball)
		_balls.append(ball)
	_vel.resize(POOL_SIZE)  # (packed arrays are values: each is resized by name)
	_life.resize(POOL_SIZE)
	_bounces.resize(POOL_SIZE)
	_ground.resize(POOL_SIZE)
	_volleys.resize(POOL_SIZE)
	_damage.resize(POOL_SIZE)
	_pop.resize(POOL_SIZE)
	_radius.resize(POOL_SIZE)
	_kick_ready.resize(POOL_SIZE)
	_hit_ready.resize(POOL_SIZE)
	_owner.resize(POOL_SIZE)
	_their_slot.resize(POOL_SIZE)
	if _cfg.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_uniques.json"))
		if data is Dictionary:
			_cfg = (((data as Dictionary).get("uniques", {}) as Dictionary).get(UNIQUE_ID, {}) as Dictionary).get("cfg", {})


# A new ball from `origin` along `dir` (the gun's cfg: speed, size, damage shares). Reuses the oldest when all are out.
func launch(origin: Vector3, dir: Vector3, cfg: Dictionary, gun_damage: float, blast_radius: float) -> void:
	_cfg = cfg
	var i := _free_slot()
	var size := float(cfg.get("ball_radius", 0.22))
	_balls[i].scale = Vector3.ONE * size
	_balls[i].position = origin
	_balls[i].rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	_balls[i].visible = true
	_vel[i] = dir * float(cfg.get("speed", 16.0))
	_life[i] = float(cfg.get("life", 7.0))
	_bounces[i] = 0
	_ground[i] = 0
	_volleys[i] = 0
	_damage[i] = gun_damage * float(cfg.get("bounce_damage", 0.5))
	_pop[i] = gun_damage * float(cfg.get("pop_damage", 1.2))
	_radius[i] = blast_radius
	_kick_ready[i] = _clock + 0.35  # not kicked by the shooter the moment it leaves the gun
	_hit_ready[i] = 0.0
	_owner[i] = 0
	_tell("launch", i, origin, _vel[i])


func active_count() -> int:
	var n := 0
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			n += 1
	return n


# A shot along `dir` from `from` (any gun, anyone's on this machine): pops the first ball on its line. True if one popped.
func shot_through(from: Vector3, dir: Vector3, reach: float) -> bool:
	var best := -1
	var best_t := reach
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		var to_ball := _balls[i].position - from
		var t := to_ball.dot(dir)
		if t < 0.0 or t > best_t:
			continue
		var size := _balls[i].scale.x * 1.15  # a little generous: they are meant to be hit
		if (to_ball - dir * t).length_squared() <= size * size:
			best = i
			best_t = t
	if best < 0:
		return false
	if _owner[best] != 0:  # somebody else's ball: gone here at once, its owner pops it for real
		var link := _link()
		if link != null:
			link.call("send", "shoot", _owner[best], _their_slot[best], _balls[best].position, Vector3.ZERO)
		_hide(best, true)
		return true
	_pop_ball(best)
	return true


func _physics_process(delta: float) -> void:
	_clock += delta
	if active_count() == 0:
		return
	var space := get_world_3d().direct_space_state
	_query.exclude = [kicker.get_rid()] if kicker is CollisionObject3D else []
	var enemies: Array = explosives.source.enemy_list() if explosives != null and explosives.source != null else []
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		var ball := _balls[i]
		var size := ball.scale.x
		_vel[i].y -= float(_cfg.get("gravity", 7.0)) * delta
		_vel[i] *= maxf(0.0, 1.0 - float(_cfg.get("drag", 0.25)) * delta)
		_kick(i)
		if _owner[i] == 0 and _head_bounce(i, enemies):
			continue
		var from := ball.position
		var to := from + _vel[i] * delta
		_query.from = from
		_query.to = to + _vel[i].normalized() * size
		var hit := space.intersect_ray(_query)
		if not hit.is_empty() and not (hit.collider as Object).has_method("on_hit"):
			var n: Vector3 = hit.normal
			_vel[i] = _vel[i].bounce(n) * float(_cfg.get("restitution", 0.65))
			ball.position = (hit.position as Vector3) + n * (size + 0.01)
			if n.y > 0.6 and _owner[i] == 0:  # (a copy waits for its owner to say it popped)
				_ground[i] += 1
				if _ground[i] >= int(_cfg.get("ground_bounces", 3)) or _vel[i].length() < 1.5:
					_pop_ball(i)
					continue
		else:
			ball.position = to
		ball.rotate_x(_vel[i].length() * delta / maxf(size, 0.05))  # it spins as it flies
		_life[i] -= delta
		if _life[i] <= 0.0:
			if _owner[i] == 0:
				_pop_ball(i)
			else:
				_hide(i, false)


# Touching an enemy's head: it hits and the ball springs up off it. True when this tick was a bounce.
func _head_bounce(i: int, enemies: Array) -> bool:
	if _clock < _hit_ready[i]:
		return false
	var ball := _balls[i]
	for enemy: Node3D in enemies:
		if not is_instance_valid(enemy) or enemy.health.is_dead():
			continue
		var head: Vector3 = enemy.global_position + Vector3(0, enemy.head_height(), 0)
		var reach := ball.scale.x + HEAD_REACH
		if ball.position.distance_squared_to(head) > reach * reach:
			continue
		enemy.on_hit(_damage[i], head, Vector3.UP)
		if explosives.numbers != null:
			explosives.numbers.spawn(head, _damage[i])
		if explosives.score != null and not enemy.health.is_dead() and not enemy.has_meta("host_pays"):
			explosives.score.hit()
		var away := ball.position - head
		away.y = 0.0
		_vel[i] = away.normalized() * maxf(Vector2(_vel[i].x, _vel[i].z).length() * 0.6, 2.0) + Vector3.UP * float(_cfg.get("head_bounce", 7.5))
		ball.position = head + Vector3.UP * reach
		_hit_ready[i] = _clock + 0.2
		_bounces[i] += 1
		if _bounces[i] >= int(_cfg.get("max_bounces", 6)):
			_pop_ball(i)
		else:
			_tell("move", i, ball.position, _vel[i])
		return true
	return false


# The local player walking into a ball kicks it where they look; each kick is a volley (a bigger pop).
func _kick(i: int) -> void:
	if kicker == null or _clock < _kick_ready[i]:
		return
	var reach := _balls[i].scale.x + float(_cfg.get("kick_reach", 0.9))
	var body := kicker.global_position + Vector3(0, 1.0, 0)
	if _balls[i].position.distance_squared_to(body) > reach * reach:
		return
	var flat: Vector3 = kicker.call("aim_flat")
	_vel[i] = (flat + Vector3.UP * 0.9).normalized() * float(_cfg.get("kick_speed", 10.0))
	_kick_ready[i] = _clock + 0.4
	if _owner[i] != 0:  # somebody else's ball: it flies on here at once, its owner makes it a volley
		var link := _link()
		if link != null:
			link.call("send", "kick", _owner[i], _their_slot[i], _balls[i].position, _vel[i])
		_life[i] = maxf(_life[i], 4.0)
		return
	_volleys[i] += 1
	_life[i] = maxf(_life[i], 3.0)  # a kicked ball stays up a while longer
	_ground[i] = 0
	_tell("move", i, _balls[i].position, _vel[i])


func _pop_ball(i: int) -> void:
	var at := _balls[i].position
	_life[i] = 0.0
	_balls[i].visible = false
	_tell("pop", i, at, Vector3.ZERO)
	if explosives != null:
		var damage := _pop[i] * (1.0 + float(_volleys[i]) * float(_cfg.get("volley_bonus", 0.25)))
		explosives.blast(at, _radius[i], damage)
		if explosives.sounds != null:
			explosives.sounds.call("play", "explosion", at)


func _free_slot() -> int:
	var oldest := 0
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			return i
		if _life[i] < _life[oldest]:
			oldest = i
	_balls[oldest].visible = false
	return oldest


# ---- online (game/net_beachballs.gd) ----

# Another player's ball, launched on his machine: a copy flies here.
func remote_launch(holder: int, slot: int, origin: Vector3, vel: Vector3) -> void:
	var i := _copy_of(holder, slot)
	if i < 0:
		i = _free_slot()
	_owner[i] = holder
	_their_slot[i] = slot
	_balls[i].scale = Vector3.ONE * float(_cfg.get("ball_radius", 0.22))
	_balls[i].position = origin
	_balls[i].visible = true
	_vel[i] = vel
	_life[i] = float(_cfg.get("life", 7.0)) + 1.0
	_kick_ready[i] = _clock + 0.35


# The owner says his ball is here, going this way now (a head bounce, a kick).
func remote_move(holder: int, slot: int, pos: Vector3, vel: Vector3) -> void:
	var i := _copy_of(holder, slot)
	if i < 0:
		remote_launch(holder, slot, pos, vel)
		return
	_balls[i].position = pos
	_vel[i] = vel
	_life[i] = maxf(_life[i], 4.0)


# The owner's ball popped (his blast did the damage): ours shows the pop.
func remote_pop(holder: int, slot: int, at: Vector3) -> void:
	var i := _copy_of(holder, slot)
	if i >= 0:
		_hide(i, false)
	if explosives != null:
		explosives.show_flash(at, float(_cfg.get("copy_flash", 3.0)))
		if explosives.sounds != null:
			explosives.sounds.call("play", "explosion", at)


# A teammate kicked our ball (on his machine): it goes his way and counts as a volley.
func friend_kick(slot: int, vel: Vector3) -> void:
	if slot < 0 or slot >= POOL_SIZE or _life[slot] <= 0.0 or _owner[slot] != 0:
		return
	_vel[slot] = vel.limit_length(float(_cfg.get("kick_speed", 10.0)) * 1.5)
	_volleys[slot] += 1
	_life[slot] = maxf(_life[slot], 3.0)
	_ground[slot] = 0
	_tell("move", slot, _balls[slot].position, _vel[slot])


# A teammate shot our ball: it pops (our blast, our damage).
func friend_shot(slot: int) -> void:
	if slot >= 0 and slot < POOL_SIZE and _life[slot] > 0.0 and _owner[slot] == 0:
		_pop_ball(slot)


func _copy_of(holder: int, slot: int) -> int:
	for i in POOL_SIZE:
		if _life[i] > 0.0 and _owner[i] == holder and _their_slot[i] == slot:
			return i
	return -1


func _hide(i: int, flash: bool) -> void:
	_life[i] = 0.0
	_balls[i].visible = false
	if flash and explosives != null:
		explosives.show_flash(_balls[i].position, 1.0)


func _tell(kind: String, i: int, a: Vector3, b: Vector3) -> void:
	if _owner[i] != 0:
		return
	var link := _link()
	if link != null:
		link.call("send", kind, int(link.call("my_id")), i, a, b)


func _link() -> Node:
	return get_tree().get_first_node_in_group("net_beachballs") if is_inside_tree() else null
