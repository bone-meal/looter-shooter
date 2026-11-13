# Purpose: the island's rounds shared by a party. The HOST runs every island enemy (game/island_rounds.gd): spawning,
# chasing, blows, health, the round itself. Other machines show puppets, send their hits as requests and are told the
# results: which enemies exist and where, who died, which round it is, and what each hit PAID (a hit, a kill, a
# headshot kill, a melee kill): the shooter's machine never pays itself for a host-run enemy. POWER-UPS are the
# host's too: it says which one lies where, when one is gone, and what the whole party just got (it alone sees who
# walked into one).
# The host checks who sent a request, that the enemy exists and that the numbers are finite; like the shared boss it
# does not cap the damage a client claims (director's decision).
# Dependencies: game/net_session.gd (parent; `net`), game/island_rounds.gd (`rounds`), game/wave_director.gd
# (`director`), game/enemy.gd, core/score_card.gd (`card`). Node name must be "Rounds" on every machine.
extends Node

const BLOWS := ["", "headshot", "melee"]
const PAYS := ["hit", "kill", "headshot", "melee"]
const EFFECTS := ["slow", "burn", "freeze", "weaken", "push"]
const SWITCH := 99  # ask_power: build the switch and throw it
const ORIGIN := Vector3(500, 0, 0)  # game/island.gd CENTER: the land's positions are counted from here

signal round_started(number: int, kind: String)  # on a client: what the host announced
signal round_ended(number: int, kind: String)
signal power_dropped(id: int, kind: String, at: Vector3)  # on a client: a power-up lies there now
signal power_gone(id: int)  # on a client: it was taken or its time ran out
signal power_taken(kind: String)  # on a client: somebody took it, so the whole party has it
signal debris_opened(index: int, show_it: bool)  # on a client: that way is clear (show_it false = it already was when we came)
signal window_set(window: int, boards: int)  # on a client (and on the host after a client nailed one): that window has this many boards now
signal nail_paid(points: int)  # on a client: the host let us nail a board back and this is what it pays
signal seat_asked(peer: int, aboard: bool)  # on the host: a client standing by the boat wants a seat, or gives its seat up
signal helm_input(peer: int, throttle: float, rudder: float)  # on the host: what a client does with the keys at the tiller
signal boat_state(x: float, z: float, yaw: float, speed: float, seats: PackedInt32Array)  # on a client: the boat as the host runs it
signal build_bits(bits: int)  # the buildables' state changed (core/build_state.gd `set_bits`): on a client, and on the host after a client's ask
signal power_bits(bits: int)  # the power's state changed (core/power_state.gd `set_bits`): on a client, and on the host after a client's ask
signal box_asked(peer: int, action: int)  # on the host: a client standing at the mystery box asks to spin (0) or to take the gun (1)
signal box_state(state: String, spot: int, owner: int, gun: Dictionary, took: bool)  # on a client: what the box does now
signal trap_asked(peer: int, trap: int)  # on the host: a client standing at a trap's lever wants it on
signal trap_started(trap: int, by: int)  # on a client: that trap runs now, switched on by that player
signal debris_billed(index: int)  # on a client: the host cleared the debris we asked for; we pay its price

var net: Node3D
var rounds: Node  # game/island_rounds.gd of this machine (it runs only on the host)
var director: Node3D
var card: RefCounted  # our own score card
var land: RefCounted  # core/archipelago.gd of this machine (which debris is cleared)
var shelters: RefCounted  # core/shelter_rules.gd of this machine (the host decides about boards)
var power: RefCounted  # core/power_state.gd of this machine
var builds: RefCounted  # core/build_state.gd of this machine
var boat_near := Callable()  # func(at: Vector3) -> bool: that spot is near enough to the boat to climb aboard
var build_near := Callable()  # func(at: Vector3) -> int: the code (BuildState.code_of) of the part or bench at that spot, -1 = none
var power_near := Callable()  # func(at: Vector3) -> int: the power part lying at that spot, SWITCH at the workbench, -1 = neither
var box_near := Callable()  # func(at: Vector3) -> bool: that spot is at the mystery box
var trap_near := Callable()  # func(at: Vector3) -> int: the trap whose lever is at that spot, -1 = none
var on_gun_side := Callable()  # func() -> bool: our player is where island enemies can reach (not in Aurelind)
var round_number := 0  # client: the round as the host last told it
var round_kind := "normal"
var round_left := 0
var fighting := false

var _enemies := {}  # net id -> enemy (real on the host, puppet elsewhere)
var _next_id := 1
var _state_timer := 0.0
var _ask_timer := 0.0
var _bound := {}  # ghost instance id -> true once its `struck` signal is connected
var _asked := false  # client: we asked the host what is alive
var _pending := {}  # client: net id -> [damage, blow] of this frame's hits (a shotgun's pellets go out as one hit)


func bind(island_rounds: Node, wave_director: Node3D, score: RefCounted) -> void:
	rounds = island_rounds
	director = wave_director
	card = score
	_enemies.clear()
	_bound.clear()
	_pending.clear()
	_asked = false
	rounds.connect("spawned", _on_spawned)
	rounds.connect("round_started", func(number: int, kind: String) -> void: _tell_round(number, kind, true))
	rounds.connect("round_ended", func(number: int, kind: String) -> void: _tell_round(number, kind, false))


# The session is gone (back to the menu): nothing here points into it any more.
func unbind() -> void:
	rounds = null
	director = null
	card = null
	_enemies.clear()
	_bound.clear()
	_pending.clear()


func is_client() -> bool:
	return net.can_send() and not net.is_host()


func _process(delta: float) -> void:
	if rounds == null:
		return
	rounds.set("active", not is_client())  # alone or hosting: the rounds run here
	if not net.can_send():
		_asked = false
		return
	if not net.is_host():
		_ask_timer = maxf(_ask_timer - delta, 0.0)
		if not _asked:
			_asked = true
			_ask_all.rpc_id(1)
		for id: int in _pending:
			_hit.rpc_id(1, id, float(_pending[id][0]), String(_pending[id][1]))
		_pending.clear()
		return
	for body: Node3D in net.target_nodes():
		if not _bound.has(body.get_instance_id()) and body.has_signal("struck"):
			_bound[body.get_instance_id()] = true
			body.connect("struck", _on_ghost_struck.bind(body))
	_state_timer += delta
	if _state_timer < (0.1 if not _enemies.is_empty() else 1.0):
		return
	_state_timer = 0.0
	var ids := PackedInt32Array()
	var spots := PackedVector3Array()
	var turns := PackedFloat32Array()
	var healths := PackedFloat32Array()
	for id: int in _enemies.keys():
		var enemy: Node3D = _enemies[id]
		if not is_instance_valid(enemy):
			_enemies.erase(id)
			continue
		ids.append(id)
		spots.append(enemy.global_position)
		turns.append(enemy.rotation.y)
		healths.append(float(enemy.health.hp) / float(enemy.health.max_hp))
	_state.rpc(ids, spots, turns, healths, int(rounds.call("left")), int(rounds.get("rules").number), bool(rounds.get("rules").call("fighting")))


# --- host to everyone ---

func _on_spawned(enemy: Node3D) -> void:
	if not net.can_send() or not net.is_host():
		return
	var id := _next_id
	_next_id += 1
	_enemies[id] = enemy
	enemy.set_meta("net_id", id)
	enemy.connect("died", func(_e: Node) -> void: _on_real_died(id))
	enemy.connect("attacked", func(origin: Vector3, aim: Vector3) -> void: _fire.rpc(id, origin, aim))
	_spawn.rpc(id, String(enemy.get("enemy_id")), enemy.global_position, int(enemy.get_meta("tier")))


func _on_real_died(id: int) -> void:
	_enemies.erase(id)
	_died.rpc(id)


func _tell_round(number: int, kind: String, started: bool) -> void:
	if net.can_send() and net.is_host():
		_round.rpc(number, kind, started)


@rpc("authority", "call_remote", "reliable")
func _round(number: int, kind: String, started: bool) -> void:
	round_number = number
	round_kind = kind
	fighting = started
	if started:
		round_started.emit(number, kind)
	else:
		round_ended.emit(number, kind)


@rpc("authority", "call_remote", "reliable")
func _spawn(id: int, enemy_id: String, pos: Vector3, tier: int) -> void:
	if rounds == null or _enemies.has(id) or not pos.is_finite():
		return
	var stats: Dictionary = rounds.call("stats_of", enemy_id, tier)
	if stats.is_empty():
		return
	var puppet: Node3D = director.call("spawn_custom", enemy_id, stats, pos)
	puppet.set("puppet", true)
	puppet.set("net_pos", pos)
	puppet.set_meta("island", true)
	puppet.set_meta("tier", tier)
	puppet.set_meta("host_pays", true)  # the host says what our hits on it paid (_paid)
	puppet.connect("puppet_hit", func(damage: float) -> void: _note_hit(id, damage))
	puppet.connect("puppet_effect", func(kind: String, amount: float, seconds: float) -> void: _effect.rpc_id(1, id, kind, amount, seconds))
	_enemies[id] = puppet


# Client: a puppet was hit. Everything that lands on one enemy within a frame goes to the host as one hit.
func _note_hit(id: int, damage: float) -> void:
	var blow := String(card.get("blow")) if card != null else ""
	if not (blow in BLOWS):
		blow = ""
	if _pending.has(id):
		_pending[id][0] = float(_pending[id][0]) + damage
		if blow != "":
			_pending[id][1] = blow
	else:
		_pending[id] = [damage, blow]


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(ids: PackedInt32Array, spots: PackedVector3Array, turns: PackedFloat32Array, healths: PackedFloat32Array, left: int, number: int, in_round: bool) -> void:
	if spots.size() != ids.size() or turns.size() != ids.size() or healths.size() != ids.size():
		return
	round_left = left
	round_number = number
	fighting = in_round
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
	for id: int in _enemies.keys():  # gone on the host (put away while nobody was on the island): gone here
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


@rpc("authority", "call_remote", "reliable")
func _died(id: int) -> void:
	if is_instance_valid(_enemies.get(id)):
		var before := String(card.get("blow")) if card != null else ""
		if card != null:
			card.set("blow", "other")  # whoever dealt the blow is paid by the host: this death pays nobody here
		_enemies[id].call("die_now")
		if card != null:
			card.set("blow", before)
	_enemies.erase(id)


# --- debris: a client asks, the host checks that it stands there and clears it for everybody ---

func ask_debris(index: int) -> void:
	if is_client():
		_debris_ask.rpc_id(1, index)


func tell_debris(index: int) -> void:
	if net.can_send() and net.is_host():
		_debris_open.rpc(index, true)


@rpc("any_peer", "call_remote", "reliable")
func _debris_ask(index: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not net.is_host() or land == null or not net.roster.has(peer) or index < 0 or index >= (land.get("bridges") as Array).size():
		return
	var body: Node3D = net.player_node(peer)
	if body == null or bool(land.call("is_open", index)):
		return
	var at := body.global_position - ORIGIN
	if int(land.call("debris_near", at.x, at.z)) != index:
		return  # not standing at it
	_debris_bill.rpc_id(peer, index)
	_debris_open.rpc(index, true)
	debris_opened.emit(index, true)  # the host's own session clears it too


@rpc("authority", "call_remote", "reliable")
func _debris_open(index: int, show_it: bool) -> void:
	debris_opened.emit(index, show_it)


@rpc("authority", "call_remote", "reliable")
func _debris_bill(index: int) -> void:
	debris_billed.emit(index)


# --- window boards: the host's enemies tear them, anybody may nail one back (the host checks they stand there) ---

func tell_window(window: int, boards: int) -> void:
	if net.can_send() and net.is_host():
		_window.rpc(window, boards)


func ask_nail(window: int) -> void:
	if is_client():
		_nail_ask.rpc_id(1, window)


@rpc("any_peer", "call_remote", "reliable")
func _nail_ask(window: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var body: Node3D = net.player_node(peer) if net.is_host() and net.roster.has(peer) else null
	if body == null or shelters == null:
		return
	var at := body.global_position - ORIGIN
	if window < 0 or int(shelters.call("window_near", at.x, at.z)) != window:
		return  # not standing at it
	var paid := int(shelters.call("nail", window, Time.get_ticks_msec() / 1000.0))
	if paid < 0:
		return
	var boards := int((shelters.get("boards") as PackedInt32Array)[window])
	_window.rpc(window, boards)
	window_set.emit(window, boards)
	if paid > 0:
		_nail_paid.rpc_id(peer, paid)


@rpc("authority", "call_remote", "reliable")
func _window(window: int, boards: int) -> void:
	window_set.emit(window, boards)


@rpc("authority", "call_remote", "reliable")
func _nail_paid(points: int) -> void:
	nail_paid.emit(clampi(points, 0, 100))


# --- the power switch: parts are found and the switch thrown for the whole party; the host checks who stands where ---

func ask_power(what: int) -> void:
	if is_client():
		_power_ask.rpc_id(1, what)


func tell_power_state(bits: int) -> void:
	if net.can_send() and net.is_host():
		_power_bits.rpc(bits)


@rpc("any_peer", "call_remote", "reliable")
func _power_ask(what: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var body: Node3D = net.player_node(peer) if net.is_host() and net.roster.has(peer) else null
	if body == null or power == null or not power_near.is_valid() or int(power_near.call(body.global_position)) != what:
		return
	if bool(power.call("switch_on") if what == SWITCH else power.call("take", what)):
		_power_bits.rpc(int(power.call("to_bits")))
		power_bits.emit(int(power.call("to_bits")))


@rpc("authority", "call_remote", "reliable")
func _power_bits(bits: int) -> void:
	power_bits.emit(bits)


# --- buildables (shield, boat): parts are found and things built for the whole party; the host checks who stands where ---

func ask_build(code: int) -> void:
	if is_client():
		_build_ask.rpc_id(1, code)


func tell_build_state(bits: int) -> void:
	if net.can_send() and net.is_host():
		_build_bits.rpc(bits)


@rpc("any_peer", "call_remote", "reliable")
func _build_ask(code: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var body: Node3D = net.player_node(peer) if net.is_host() and net.roster.has(peer) else null
	if body == null or builds == null or not build_near.is_valid() or code < 0 or int(build_near.call(body.global_position)) != code:
		return
	if bool(builds.call("apply", code)):
		_build_bits.rpc(int(builds.call("to_bits")))
		build_bits.emit(int(builds.call("to_bits")))


@rpc("authority", "call_remote", "reliable")
func _build_bits(bits: int) -> void:
	build_bits.emit(bits)


# --- the boat: the host sails it; a client asks for a seat and, at the tiller, sends what its keys say ---

func ask_seat(aboard: bool) -> void:
	if is_client():
		_seat_ask.rpc_id(1, aboard)


func send_helm(throttle: float, rudder: float) -> void:
	if is_client():
		_helm.rpc_id(1, throttle, rudder)


func tell_boat(x: float, z: float, yaw: float, speed: float, seats: PackedInt32Array) -> void:
	if net.can_send() and net.is_host():
		_boat.rpc(x, z, yaw, speed, seats)


@rpc("any_peer", "call_remote", "reliable")
func _seat_ask(aboard: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var body: Node3D = net.player_node(peer) if net.is_host() and net.roster.has(peer) else null
	if body != null and (not aboard or (boat_near.is_valid() and bool(boat_near.call(body.global_position)))):
		seat_asked.emit(peer, aboard)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _helm(throttle: float, rudder: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(peer) and is_finite(throttle) and is_finite(rudder):
		helm_input.emit(peer, clampf(throttle, -1.0, 1.0), clampf(rudder, -1.0, 1.0))


@rpc("authority", "call_remote", "unreliable_ordered")
func _boat(x: float, z: float, yaw: float, speed: float, seats: PackedInt32Array) -> void:
	boat_state.emit(x, z, yaw, speed, seats)


# --- the mystery box and the traps: a client asks, the host checks where it stands and its session decides ---

func ask_box(action: int) -> void:
	if is_client():
		_box_ask.rpc_id(1, action)


func tell_box(state: String, spot: int, owner: int, gun: Dictionary, took: bool) -> void:
	if net.can_send() and net.is_host():
		_box.rpc(state, spot, owner, gun, took)


@rpc("any_peer", "call_remote", "reliable")
func _box_ask(action: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var body: Node3D = net.player_node(peer) if net.is_host() and net.roster.has(peer) else null
	if body != null and box_near.is_valid() and bool(box_near.call(body.global_position)) and (action == 0 or action == 1):
		box_asked.emit(peer, action)


@rpc("authority", "call_remote", "reliable")
func _box(state: String, spot: int, owner: int, gun: Dictionary, took: bool) -> void:
	box_state.emit(state, spot, owner, gun, took)


func ask_trap(trap: int) -> void:
	if is_client():
		_trap_ask.rpc_id(1, trap)


func tell_trap(trap: int, by: int) -> void:
	if net.can_send() and net.is_host():
		_trap.rpc(trap, by)


@rpc("any_peer", "call_remote", "reliable")
func _trap_ask(trap: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var body: Node3D = net.player_node(peer) if net.is_host() and net.roster.has(peer) else null
	if body != null and trap_near.is_valid() and trap >= 0 and int(trap_near.call(body.global_position)) == trap:
		trap_asked.emit(peer, trap)


@rpc("authority", "call_remote", "reliable")
func _trap(trap: int, by: int) -> void:
	trap_started.emit(trap, by)


# --- power-ups: only the host speaks ---

func tell_power_drop(id: int, kind: String, at: Vector3) -> void:
	if net.can_send() and net.is_host():
		_power_drop.rpc(id, kind, at)


func tell_power_gone(id: int) -> void:
	if net.can_send() and net.is_host():
		_power_gone.rpc(id)


func tell_power(kind: String) -> void:
	if net.can_send() and net.is_host():
		_power.rpc(kind)


@rpc("authority", "call_remote", "reliable")
func _power_drop(id: int, kind: String, at: Vector3) -> void:
	if id > 0 and at.is_finite():
		power_dropped.emit(id, kind, at)


@rpc("authority", "call_remote", "reliable")
func _power_gone(id: int) -> void:
	power_gone.emit(id)


@rpc("authority", "call_remote", "reliable")
func _power(kind: String) -> void:
	power_taken.emit(kind)


# A host-run enemy hit one of the other players: their machine takes the damage (armour and all).
func _on_ghost_struck(amount: float, element: String, body: Node3D) -> void:
	for peer: int in net.roster:
		if net.player_node(peer) == body:
			_struck.rpc_id(peer, amount, element)


@rpc("authority", "call_remote", "reliable")
func _struck(amount: float, element: String) -> void:
	if is_finite(amount) and amount > 0.0 and (not on_gun_side.is_valid() or bool(on_gun_side.call())):
		net.local_player().call("take_damage", amount, element)


# What a hit of ours on a host-run enemy paid.
@rpc("authority", "call_remote", "reliable")
func _paid(what: String) -> void:
	if card == null or not (what in PAYS):
		return
	if what == "hit":
		card.call("hit")
		return
	var before := String(card.get("blow"))
	card.set("blow", "" if what == "kill" else what)
	card.call("kill")
	card.set("blow", before)


@rpc("any_peer", "call_remote", "reliable")
func _ask_all() -> void:
	if not net.is_host() or rounds == null:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not net.roster.has(peer):
		return
	if land != null:
		for index: int in land.call("open_list"):
			_debris_open.rpc_id(peer, index, false)
	if power != null:
		_power_bits.rpc_id(peer, int(power.call("to_bits")))
	if builds != null:
		_build_bits.rpc_id(peer, int(builds.call("to_bits")))
	if shelters != null:
		var boards: PackedInt32Array = shelters.get("boards")
		for window in boards.size():
			_window.rpc_id(peer, window, boards[window])
	for id: int in _enemies:
		if is_instance_valid(_enemies[id]):
			_spawn.rpc_id(peer, id, String(_enemies[id].get("enemy_id")), (_enemies[id] as Node3D).global_position, int(_enemies[id].get_meta("tier")))


# --- requests from the other machines ---

@rpc("any_peer", "call_remote", "reliable")
func _hit(id: int, damage: float, blow: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not net.is_host() or rounds == null or not net.roster.has(peer):
		return
	if not is_instance_valid(_enemies.get(id)) or not is_finite(damage) or damage <= 0.0 or not (blow in BLOWS):
		return
	var enemy: Node = _enemies[id]
	var before := String(card.get("blow")) if card != null else ""
	if card != null:
		card.set("blow", "other")  # not the host's kill, should it be one
	enemy.call("on_hit", damage)
	if card != null:
		card.set("blow", before)
	if enemy.health.is_dead():
		_paid.rpc_id(peer, "kill" if blow == "" else blow)
	else:
		_paid.rpc_id(peer, "hit")


@rpc("any_peer", "call_remote", "reliable")
func _effect(id: int, kind: String, amount: float, seconds: float) -> void:
	if not net.is_host() or rounds == null or not net.roster.has(multiplayer.get_remote_sender_id()):
		return
	if not is_instance_valid(_enemies.get(id)) or not (kind in EFFECTS) or not is_finite(amount) or not is_finite(seconds):
		return
	var enemy: Node = _enemies[id]
	var is_boss := String(enemy.get("enemy_id")).begins_with("boss")
	match kind:
		"slow":
			enemy.call("apply_slow", clampf(amount, 0.0, 0.8), clampf(seconds, 0.0, 10.0))
		"burn":
			enemy.call("apply_burn", maxf(amount, 0.0), clampf(seconds, 0.0, 10.0))
		"freeze":
			enemy.call("apply_freeze", clampf(seconds, 0.0, 8.0) * (0.25 if is_boss else 1.0))
		"weaken":
			enemy.call("apply_vulnerable", clampf(amount, 1.0, 2.0), clampf(seconds, 0.0, 10.0))
		"push":
			if not is_boss:
				enemy.call("push", Vector3(amount, 0.0, seconds).limit_length(20.0))  # push sends its x and z here


# Host migration: this machine is the new host. Its puppets cannot become real enemies (the old host held the
# round), so the island is cleared and the round the party was in starts again here.
func adopt_as_host() -> void:
	for id: int in _enemies.keys():
		if is_instance_valid(_enemies[id]):
			director.call("despawn", _enemies[id])
	_enemies.clear()
	if rounds != null and round_number > 0:
		rounds.set("active", true)
		rounds.call("skip_to", round_number)
