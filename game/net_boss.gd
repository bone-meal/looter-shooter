# Purpose: the boss shared by all players. The host simulates the real boss (chases the nearest player, decides attacks and damage); every other machine shows a puppet and sends its shots to the host as damage intents.
# Dependencies: game/net_session.gd (parent; `net`), game/wave_director.gd (`director`), game/enemy.gd, data/net.json.
extends Node

var net: Node3D
var director: Node3D  # our wave director

var _boss: CharacterBody3D  # real boss on the host, puppet elsewhere
var _cooldown := 0.0  # host: seconds a just-killed boss still counts as beaten for late boss waves
var _waiting := false  # our director asked for the boss and has no answer yet
var _state_timer := 0.0
var _retarget := 0.0


func bind_director(d: Node3D) -> void:
	director = d
	d.boss_handler = _on_boss_wave


func unbind() -> void:
	if director != null and is_instance_valid(director):
		director.boss_handler = Callable()
	director = null
	if is_instance_valid(_boss):
		_boss.queue_free()
	_boss = null
	_waiting = false


# Our director reached the boss entry of its waves.
func _on_boss_wave(_d: Node3D) -> void:
	_waiting = true
	if net.is_host():
		_host_request(1)
	else:
		_ask_boss.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _ask_boss() -> void:
	if net.is_host():
		_host_request(multiplayer.get_remote_sender_id())


func _host_request(peer: int) -> void:
	var answer := "attach"
	if not is_instance_valid(_boss):
		if _cooldown > 0.0:
			answer = "dead"  # killed moments ago by someone else: counts as beaten
		else:
			_spawn_real_boss()
	if peer == 1:
		_resolve(answer)
	else:
		if answer == "attach" and is_instance_valid(_boss):
			_boss_spawned.rpc_id(peer, _boss.position)  # make sure that machine has the puppet (ignored if it already does)
		_reply.rpc_id(peer, answer)


func _spawn_real_boss() -> void:
	if director == null:
		return
	var boss: CharacterBody3D = director.create_shared_boss(false, director.boss_spawn_position())
	boss.died.connect(_on_real_boss_died)
	boss.attacked.connect(_on_real_boss_attacked)
	_boss = boss
	_boss_spawned.rpc(boss.position)


@rpc("authority", "call_remote", "reliable")
func _boss_spawned(pos: Vector3) -> void:
	if director == null or is_instance_valid(_boss):
		return
	var puppet: CharacterBody3D = director.create_shared_boss(true, pos)
	puppet.puppet_hit.connect(_on_puppet_hit)
	_boss = puppet


@rpc("authority", "call_remote", "reliable")
func _reply(answer: String) -> void:
	_resolve(answer)


func _resolve(answer: String) -> void:
	if not _waiting or director == null:
		return
	_waiting = false
	if answer == "dead" or not is_instance_valid(_boss):
		director.boss_already_dead()
	else:
		director.attach_boss(_boss)


func _process(delta: float) -> void:
	if net == null or not net.is_host():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_instance_valid(_boss):
		return
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.5
		_boss.set_target(_nearest_player(_boss.global_position))
	_state_timer += delta
	if _state_timer >= 1.0 / float(net.config("boss_state_hz")):
		_state_timer = 0.0
		_boss_state.rpc(_boss.global_position, _boss.rotation.y, _boss.health.hp / _boss.health.max_hp)


func _nearest_player(from: Vector3) -> Node3D:
	var best: Node3D = net.local_player()
	var best_d := INF
	for t in net.target_nodes():
		var d := from.distance_squared_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


@rpc("authority", "call_remote", "unreliable_ordered")
func _boss_state(pos: Vector3, yaw: float, ratio: float) -> void:
	if not is_instance_valid(_boss) or not pos.is_finite():
		return
	_boss.net_pos = pos
	_boss.net_yaw = yaw
	_boss.health.hp = clampf(ratio, 0.0, 1.0) * _boss.health.max_hp


func _on_real_boss_attacked(origin: Vector3, aim: Vector3) -> void:
	_boss_fire.rpc(origin, aim)


@rpc("authority", "call_remote", "reliable")
func _boss_fire(origin: Vector3, aim: Vector3) -> void:
	if is_instance_valid(_boss) and origin.is_finite() and aim.is_finite():
		_boss.shoot_burst(origin, aim)


func _on_real_boss_died(_enemy: Node) -> void:
	_cooldown = float(net.config("boss_cooldown_seconds"))
	_boss_died.rpc()


@rpc("authority", "call_remote", "reliable")
func _boss_died() -> void:
	if is_instance_valid(_boss):
		_boss.die_now()


# Host migration: this machine is the new host, so our puppet becomes the real boss (same position and health).
func adopt_as_host() -> void:
	if not is_instance_valid(_boss) or not _boss.puppet:
		return
	_boss.puppet = false
	_boss.position = _boss.net_pos
	_boss.died.connect(_on_real_boss_died)
	_boss.attacked.connect(_on_real_boss_attacked)


# Host migration finished: a boss request that was lost with the old host is asked again.
func after_migration() -> void:
	if _waiting:
		_on_boss_wave(director)


# A puppet was shot on this machine: ask the host to apply it.
func _on_puppet_hit(damage: float) -> void:
	_hit_boss.rpc_id(1, damage)


@rpc("any_peer", "call_remote", "reliable")
func _hit_boss(damage: float) -> void:
	if not net.is_host() or not is_instance_valid(_boss):
		return
	var id := multiplayer.get_remote_sender_id()
	if not net.roster.has(id) or not is_finite(damage) or damage <= 0.0:
		return
	_boss.on_hit(damage)
