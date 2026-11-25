# Purpose: the fantasy world shared by a party. The HOST runs every creature and boss (spawning, chasing, attacks,
# health) and keeps the one party quest log; other machines show puppets, send what they do as requests (a hit on a
# creature, an effect, a quest event, taking a quest, a spell to show) and are told the results. The host checks each
# request: who sent it, that the creature exists, that the numbers are finite and within what the party's progress
# makes possible. Skills and bags stay each player's own (their signed profile); the gathering SPOTS are shared
# (polish1 item 114: a node one player uses is used up for all; hibernation and woken spots come from the host).
# Dependencies: game/net_session.gd (parent; `net`), game/fantasy_world.gd (`world`), game/wave_director.gd, game/enemy.gd.
extends Node

const WORLD_X := 15000.0  # bodies beyond this x are in the fantasy world (it lies at x = 20000)
const EVENT_TYPES := ["talk", "reach", "cast", "fire", "track"]  # kills are never taken from a client; track = tracks followed (Hunting)
const EFFECTS := ["slow", "burn", "freeze", "weaken", "push"]

var net: Node3D
var world: Node3D  # game/fantasy_world.gd, once the session has built it
var director: Node3D

var _enemies := {}  # net id -> creature (real on the host, puppet elsewhere)
var _next_id := 1
var _state_timer := 0.0
var _ask_timer := 0.0
var _bound := {}  # ghost instance id -> true once its `struck` signal is connected
var _was_inside := false
var on_cross := Callable()  # (polish1 F1a) the session's: take this machine's party member over a border (to, crossing)


func bind(fantasy_world: Node3D, wave_director: Node3D) -> void:
	world = fantasy_world
	director = wave_director
	world.party = self
	world.spawner.spawned.connect(_on_spawned)
	world.spawner.targets = _bodies


func unbind() -> void:
	if world != null and is_instance_valid(world):
		world.party = null
	world = null
	director = null
	_enemies.clear()
	_bound.clear()


func is_client() -> bool:
	return net.can_send() and not net.is_host()


# --- who is in there ---

# Host: the bodies of everyone standing in the fantasy world.
func _bodies() -> Array:
	var out: Array = []
	if world != null and world.inside:
		out.append(net.local_player())
	if net.can_send():
		for body: Node3D in net.target_nodes():
			if body.global_position.x > WORLD_X:
				out.append(body)
	return out


func _process(delta: float) -> void:
	if world == null or not net.can_send():
		return
	if net.is_host():
		_host_tick(delta)
		return
	if world.inside and not _was_inside:
		_ask_all.rpc_id(1)  # just walked in: what is alive, and where is the party's quest log
	if not world.inside and _was_inside:
		_enemies.clear()  # the session removed the puppets with everything else
	_was_inside = world.inside
	_ask_timer = maxf(_ask_timer - delta, 0.0)


func _host_tick(delta: float) -> void:
	var bodies := _bodies()
	world.spawner.active = not bodies.is_empty()
	for body: Node3D in net.target_nodes():
		if not _bound.has(body.get_instance_id()) and body.has_signal("struck"):
			_bound[body.get_instance_id()] = true
			body.connect("struck", _on_ghost_struck.bind(body))
	_state_timer += delta
	if _state_timer < 0.1 or _enemies.is_empty():
		return
	_state_timer = 0.0
	var ids := PackedInt32Array()
	var spots := PackedVector3Array()
	var turns := PackedFloat32Array()
	var healths := PackedFloat32Array()
	for id: int in _enemies.keys():
		var held: Variant = _enemies[id]  # (a typed variable cannot hold a freed creature: that error stopped every state after the first one was gone)
		if not is_instance_valid(held):
			_enemies.erase(id)
			continue
		var enemy: Node3D = held
		ids.append(id)
		spots.append(enemy.global_position)
		turns.append(enemy.rotation.y)
		healths.append(float(enemy.health.hp) / float(enemy.health.max_hp))
	_state.rpc(ids, spots, turns, healths)


# --- creatures: host to everyone ---

func _on_spawned(enemy: Node3D) -> void:
	if not net.can_send() or not net.is_host():
		return
	var id := _next_id
	_next_id += 1
	_enemies[id] = enemy
	enemy.set_meta("net_id", id)
	enemy.connect("died", func(_e: Node) -> void: _on_real_died(id))
	enemy.connect("felled", func(_e: Node) -> void: _on_real_died(id))  # fell to another creature: the others see it fall, nobody is paid
	enemy.connect("attacked", func(origin: Vector3, aim: Vector3) -> void: _fire.rpc(id, origin, aim))
	_spawn.rpc(id, String(enemy.get("enemy_id")), enemy.global_position)


func _on_real_died(id: int) -> void:
	_enemies.erase(id)
	_died.rpc(id)


@rpc("authority", "call_remote", "reliable")
func _spawn(id: int, enemy_id: String, pos: Vector3) -> void:
	if world == null or not world.inside or _enemies.has(id) or not pos.is_finite():
		return
	var stats: Dictionary = world.spawner.stats_of(enemy_id)
	if stats.is_empty():
		return
	var puppet: Node3D = director.call("spawn_custom", enemy_id, stats.duplicate(true), pos)
	puppet.set("puppet", true)
	puppet.set("net_pos", pos)
	puppet.set_meta("fantasy", true)
	if bool(stats.get("boss", false)):
		puppet.set_meta("fantasy_boss", true)
	puppet.connect("puppet_hit", func(damage: float) -> void: _hit.rpc_id(1, id, damage))
	puppet.connect("puppet_effect", func(kind: String, amount: float, seconds: float) -> void: _effect.rpc_id(1, id, kind, amount, seconds))
	_enemies[id] = puppet


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(ids: PackedInt32Array, spots: PackedVector3Array, turns: PackedFloat32Array, healths: PackedFloat32Array) -> void:
	if world == null or not world.inside or spots.size() != ids.size() or turns.size() != ids.size() or healths.size() != ids.size():
		return
	var unknown := false
	for i in ids.size():
		var puppet: Variant = _enemies.get(ids[i])
		if not is_instance_valid(puppet):
			unknown = true
			continue
		if spots[i].is_finite():
			puppet.set("net_pos", spots[i])
			puppet.set("net_yaw", turns[i])
			puppet.health.hp = clampf(healths[i], 0.0, 1.0) * float(puppet.health.max_hp)
	for id: int in _enemies.keys():  # gone on the host (wandered off, went back to sleep): gone here
		if not ids.has(id):
			if is_instance_valid(_enemies[id]):
				director.call("despawn", _enemies[id])
			_enemies.erase(id)
	if unknown and _ask_timer <= 0.0:
		_ask_timer = 1.0
		_ask_all.rpc_id(1)


@rpc("authority", "call_remote", "reliable")
func _fire(id: int, origin: Vector3, aim: Vector3) -> void:
	if is_instance_valid(_enemies.get(id)) and origin.is_finite() and aim.is_finite():
		_enemies[id].call("shoot_burst", origin, aim)


# Host: a boss started one of its special attacks; the others draw it (game/boss_moves.gd decides nothing there).
func send_move(boss: Node3D, index: int, at: Vector3, roll: int) -> void:
	if net.can_send() and net.is_host() and boss.has_meta("net_id"):
		_move.rpc(int(boss.get_meta("net_id")), index, at, roll)


@rpc("authority", "call_remote", "reliable")
func _move(id: int, index: int, at: Vector3, roll: int) -> void:
	if world != null and world.inside and is_instance_valid(_enemies.get(id)) and at.is_finite():
		world.moves.replay(_enemies[id], index, at, roll)
		world.show_move(_enemies[id], index)


@rpc("authority", "call_remote", "reliable")
func _died(id: int) -> void:
	if is_instance_valid(_enemies.get(id)):
		_enemies[id].call("die_now")
	_enemies.erase(id)


# A host-run creature hit one of the other players: their machine takes the damage (armour and all).
func _on_ghost_struck(amount: float, element: String, body: Node3D) -> void:
	for peer: int in net.roster:
		if net.player_node(peer) == body:
			_struck.rpc_id(peer, amount, element)


@rpc("authority", "call_remote", "reliable")
func _struck(amount: float, element: String) -> void:
	if is_finite(amount) and amount > 0.0 and world != null and world.inside:
		net.local_player().call("take_damage", amount, element)


@rpc("any_peer", "call_remote", "reliable")
func _ask_all() -> void:
	if not net.is_host() or world == null:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not net.roster.has(peer):
		return
	for id: int in _enemies:
		if is_instance_valid(_enemies[id]):
			_spawn.rpc_id(peer, id, String(_enemies[id].get("enemy_id")), (_enemies[id] as Node3D).global_position)
	_log.rpc_id(peer, world.quests.to_dict())
	send_node_state(peer)  # (polish1 item 114) which spots are used up, hibernating or woken
	_country.rpc_id(peer, String(world.country))  # (polish1 F1a) the party is in the host's country


# --- (polish1 F1a) crossing a border: the whole party goes, the host decides ---

# Anyone at a crossing asks; the host takes everyone over (itself included).
func ask_cross(to: String, crossing: String) -> void:
	if is_client():
		_ask_cross.rpc_id(1, to, crossing)
	else:
		_host_cross(to, crossing)


func _host_cross(to: String, crossing: String) -> void:
	if world == null:
		return
	var p: Dictionary = world.terrain.place(crossing)
	if p.is_empty() or String(p.get("kind", "")) != "crossing" or String(p.get("to", "")) != to:
		return
	if net.can_send():
		_cross.rpc(to, crossing)
	if on_cross.is_valid():
		on_cross.call(to, crossing)


@rpc("any_peer", "call_remote", "reliable")
func _ask_cross(to: String, crossing: String) -> void:
	if net.is_host() and net.roster.has(multiplayer.get_remote_sender_id()):
		_host_cross(to, crossing)


@rpc("authority", "call_remote", "reliable")
func _cross(to: String, crossing: String) -> void:
	if on_cross.is_valid():
		on_cross.call(to, crossing)


# A joiner whose own save stood in another country follows the host to the host's (arriving at its spawn).
@rpc("authority", "call_remote", "reliable")
func _country(id: String) -> void:
	if world != null and String(world.country) != id and on_cross.is_valid():
		on_cross.call(id, "")


# --- requests from the other machines ---

# The most one hit can do with the best staff and level the party's chapter allows, a strong potion and a soaked
# target: anything above that is not something this game can produce.
func _hit_cap() -> float:
	var chapter := clampi(int(world.quests.chapter()), 1, 8)
	var best := 1.0
	var staffs: Array = []
	for item: String in world.bag.all_ids():
		if String(world.bag.def(item)["kind"]) == "staff":
			staffs.append(float(world.bag.def(item)["power"]))
	staffs.sort()
	if not staffs.is_empty():
		best = staffs[mini(chapter, staffs.size() - 1)]
	var level := int(world.terrain.regions[mini(chapter, world.terrain.regions.size() - 1)]["level"][1]) + 5
	var biggest := 0.0
	for key: String in world.spells.data["substances"]:
		biggest = maxf(biggest, float(world.spells.data["substances"][key]["damage"]) * pow(float(world.spells.data["max_slots"]), float(world.spells.data["damage_power"])) * 1.3)
	for secret: Dictionary in world.spells.data["secrets"]:
		biggest = maxf(biggest, float(secret["damage"]))
	return biggest * best * (1.0 + 0.06 * float(level)) * 1.35 * 1.5


@rpc("any_peer", "call_remote", "reliable")
func _hit(id: int, damage: float) -> void:
	if not net.is_host() or world == null or not net.roster.has(multiplayer.get_remote_sender_id()):
		return
	if not is_instance_valid(_enemies.get(id)) or not is_finite(damage) or damage <= 0.0:
		return
	_enemies[id].call("on_hit", minf(damage, _hit_cap()))


@rpc("any_peer", "call_remote", "reliable")
func _effect(id: int, kind: String, amount: float, seconds: float) -> void:
	if not net.is_host() or world == null or not net.roster.has(multiplayer.get_remote_sender_id()):
		return
	if not is_instance_valid(_enemies.get(id)) or not (kind in EFFECTS) or not is_finite(amount) or not is_finite(seconds):
		return
	var enemy: Node = _enemies[id]
	var hold := 0.25 if enemy.has_meta("fantasy_boss") else 1.0
	match kind:
		"slow":
			enemy.call("apply_slow", clampf(amount, 0.0, 0.8), clampf(seconds, 0.0, 10.0))
		"burn":
			enemy.call("apply_burn", clampf(amount, 0.0, _hit_cap() * 0.25), clampf(seconds, 0.0, 10.0))
		"freeze":
			enemy.call("apply_freeze", clampf(seconds, 0.0, 8.0) * hold)
		"weaken":
			enemy.call("apply_vulnerable", clampf(amount, 1.0, 2.0), clampf(seconds, 0.0, 10.0))
		"push":
			if not enemy.has_meta("fantasy_boss"):
				enemy.call("push", Vector3(amount, 0.0, seconds).limit_length(20.0))  # push sends its x and z here


# --- (polish1 item 114) gathering spots, shared: the host decides ---

func send_node_use(tag: String, seconds: float) -> void:
	_node_use.rpc_id(1, tag, seconds)


@rpc("any_peer", "call_remote", "reliable")
func _node_use(tag: String, seconds: float) -> void:
	if not net.is_host() or world == null or not net.roster.has(multiplayer.get_remote_sender_id()):
		return
	var parts := tag.split(":")
	if parts.size() != 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int() or not is_finite(seconds):
		return
	var node: Dictionary = world.gather.call("_by_tag", tag)
	var secs := clampf(seconds, 1.0, 600.0)
	var change: Dictionary = world.gather.call("use", node, secs) if not node.is_empty() else {"tag": tag, "spent": secs, "hib": 0.0, "wake": ""}
	if node.is_empty():
		world.gather.call("apply", change)
	send_node_change(change)


func send_node_change(change: Dictionary) -> void:
	if net.can_send() and net.is_host():
		_node_change.rpc(change)


@rpc("authority", "call_remote", "reliable")
func _node_change(change: Dictionary) -> void:
	if world != null:
		world.gather.call("apply", change)


# Host: everything about the spots for a player who has just joined.
func send_node_state(peer: int) -> void:
	if net.can_send() and net.is_host() and world != null:
		_node_state.rpc_id(peer, world.gather.call("state"))


@rpc("authority", "call_remote", "reliable")
func _node_state(list: Array) -> void:
	if world == null:
		return
	for change: Variant in list:
		if change is Dictionary:
			world.gather.call("apply", change)


# --- the party's quests ---

func send_event(event: Dictionary) -> void:
	_event.rpc_id(1, event)


@rpc("any_peer", "call_remote", "reliable")
func _event(event: Dictionary) -> void:
	if not net.is_host() or world == null or not net.roster.has(multiplayer.get_remote_sender_id()):
		return
	if not (String(event.get("type", "")) in EVENT_TYPES):
		return
	var clean := {"type": String(event["type"])}
	for key: String in ["npc", "place", "sequence", "substance", "secret", "animal"]:
		if event.has(key):
			clean[key] = String(event[key]).left(40)
	for key: String in ["x", "z"]:  # where a followed trail ends (map metres)
		if event.has(key) and (event[key] is float or event[key] is int) and is_finite(float(event[key])):
			clean[key] = clampf(float(event[key]), -4000.0, 4000.0)
	world.host_event(clean)


func send_accept(quest_id: String) -> void:
	_accept.rpc_id(1, quest_id)


@rpc("any_peer", "call_remote", "reliable")
func _accept(quest_id: String) -> void:
	if net.is_host() and world != null and net.roster.has(multiplayer.get_remote_sender_id()):
		world.accept(quest_id.left(40))


func send_claim(quest_id: String, step: int) -> void:
	_claim.rpc_id(1, quest_id, step)


@rpc("any_peer", "call_remote", "reliable")
func _claim(quest_id: String, step: int) -> void:
	if net.is_host() and world != null and net.roster.has(multiplayer.get_remote_sender_id()):
		world.host_claim(quest_id.left(40), step)


func send_log() -> void:
	if net.can_send():
		_log.rpc(world.quests.to_dict())


@rpc("authority", "call_remote", "reliable")
func _log(saved: Dictionary) -> void:
	if world != null:
		world.adopt_log(saved)


func send_reward(quest_id: String) -> void:
	if net.can_send():
		_reward.rpc(quest_id)


@rpc("authority", "call_remote", "reliable")
func _reward(quest_id: String) -> void:
	if world != null and world.quests.ids().has(quest_id):
		world.reward(quest_id)


func send_slain(enemy_id: String) -> void:
	if net.can_send():
		_slain.rpc(enemy_id)


@rpc("authority", "call_remote", "reliable")
func _slain(enemy_id: String) -> void:
	if world != null and world.inside:
		world.spawner.pay(enemy_id)


# --- spells drawn on the other machines ---

func send_cast(sequence: String, origin: Vector3, aim: Vector3) -> void:
	if not net.can_send():
		return
	if net.is_host():
		_cast_show.rpc(1, sequence, origin, aim)
	else:
		_cast_to_host.rpc_id(1, sequence, origin, aim)


@rpc("any_peer", "call_remote", "unreliable")
func _cast_to_host(sequence: String, origin: Vector3, aim: Vector3) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not net.is_host() or world == null or not net.roster.has(peer) or sequence.length() > int(world.spells.data["max_slots"]) or not origin.is_finite() or not aim.is_finite():
		return
	if world.inside:
		world.show_cast(sequence, origin, aim)
	_cast_show.rpc(peer, sequence, origin, aim)


@rpc("authority", "call_remote", "unreliable")
func _cast_show(peer: int, sequence: String, origin: Vector3, aim: Vector3) -> void:
	if world != null and world.inside and peer != net.my_id() and origin.is_finite() and aim.is_finite():
		world.show_cast(sequence, origin, aim)


# --- host migration ---

# This machine is the new host: its puppets become the real creatures, where they stand and with the health they had.
func adopt_as_host() -> void:
	if world == null:
		return
	for id: int in _enemies.keys():
		var enemy: Variant = _enemies[id]
		if not is_instance_valid(enemy) or not bool(enemy.get("puppet")):
			continue
		enemy.set("puppet", false)
		enemy.position = enemy.get("net_pos")
		enemy.set("walker", world.spawner.walker_for(world.spawner.stats_of(String(enemy.get("enemy_id")))))
		enemy.connect("felled", func(_e: Node) -> void: _on_real_died(id))
		enemy.connect("died", func(_e: Node) -> void: _on_real_died(id))
		enemy.connect("attacked", func(origin: Vector3, aim: Vector3) -> void: _fire.rpc(id, origin, aim))
		world.spawner.adopt(enemy)
		_next_id = maxi(_next_id, id + 1)
