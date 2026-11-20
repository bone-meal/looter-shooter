# Purpose: (polish1 item 71) 8-ball between two players online, for chips. The host keeps every table's match: a
# player OPENS a table (stake), another JOINS it, the host racks. A shot is only an intent (cue ball spot if in hand,
# angle, power, spin, called pocket): the host plays it to rest with its own physics (core/pool_sim.gd), judges it
# (core/pool_rules.gd) and sends everyone the table before the shot, the shot itself, the table after it and the
# rules' state: every machine plays the same shot on its own table and snaps to the host's end (players and anyone
# watching). The host's shot clock runs out into a foul; the host names the winner (also when a player leaves).
# Dependencies: game/net_session.gd (parent; `net`), core/pool_sim.gd, core/pool_rules.gd, core/data_store.gd,
# data/pool.json. Node name must be "Pool" on every machine.
extends Node

const Sim = preload("res://core/pool_sim.gd")
const Rules = preload("res://core/pool_rules.gd")
const DataStore = preload("res://core/data_store.gd")

signal tables_changed(tables: Array)  # per table: {} free, or {"state", "stake", "players", "names"}
signal started(table: int, players: Array, names: Array, start: Dictionary, rules: Dictionary)
signal shot(table: int, data: Dictionary)  # {"shooter", "start", "params" [angle, power, spin, called] or [], "end", "rules"}
signal ended(table: int, winner_peer: int, reason: String)
signal refused(text: String)

const GRACE := 4.0  # seconds past the shot clock before the host calls it (the players' clocks show the real one)

var net: Node3D
var tables: Array = []

var _cfg: Dictionary
var _matches := {}  # host: table -> {"state", "stake", "players", "names", "sim", "rules", "clock"}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_cfg = DataStore.load_json("res://data/pool.json")
	_rng.randomize()
	net.roster_changed.connect(_on_roster)


func online() -> bool:
	return net != null and net.can_send()


func ask_open(table: int, stake: int) -> void:
	_call_host("_open_to_host", [table, stake])


func ask_join(table: int) -> void:
	_call_host("_join_to_host", [table])


func ask_leave(table: int) -> void:
	_call_host("_leave_to_host", [table])


# cue = where we put the cue ball (ball in hand), Vector2.INF when not.
func ask_shot(table: int, cue: Vector2, angle: float, power: float, spin: Vector2, called: int) -> void:
	_call_host("_shot_to_host", [table, cue, angle, power, spin, called])


func _call_host(method: String, args: Array) -> void:
	if not online():
		return
	if net.is_host():
		match method:
			"_open_to_host":
				_host_open(1, int(args[0]), int(args[1]))
			"_join_to_host":
				_host_join(1, int(args[0]))
			"_leave_to_host":
				_host_leave(1, int(args[0]), "left")
			"_shot_to_host":
				_host_shot(1, args)
	else:
		callv("rpc_id", [1, method] + args)


@rpc("any_peer", "call_remote", "reliable")
func _open_to_host(table: int, stake: int) -> void:
	if net.is_host():
		_host_open(multiplayer.get_remote_sender_id(), table, stake)


@rpc("any_peer", "call_remote", "reliable")
func _join_to_host(table: int) -> void:
	if net.is_host():
		_host_join(multiplayer.get_remote_sender_id(), table)


@rpc("any_peer", "call_remote", "reliable")
func _leave_to_host(table: int) -> void:
	if net.is_host():
		_host_leave(multiplayer.get_remote_sender_id(), table, "left")


@rpc("any_peer", "call_remote", "reliable")
func _shot_to_host(table: int, cue: Vector2, angle: float, power: float, spin: Vector2, called: int) -> void:
	if net.is_host():
		_host_shot(multiplayer.get_remote_sender_id(), [table, cue, angle, power, spin, called])


func _count() -> int:
	return (_cfg["tables"] as Array).size()


func _host_open(peer: int, table: int, stake: int) -> void:
	var stake_ok := false
	for s: Variant in _cfg["stakes"]:
		stake_ok = stake_ok or int(s) == stake
	if table < 0 or table >= _count() or _matches.has(table) or not net.roster.has(peer) or not stake_ok:
		_tell_refused(peer, "That table is taken.")
		return
	for t: int in _matches:
		if (_matches[t]["players"] as Array).has(peer):
			_tell_refused(peer, "You are already at a table.")
			return
	_matches[table] = {"state": "open", "stake": stake, "players": [peer], "names": [String(net.roster[peer])], "sim": null, "rules": null, "clock": 0.0}
	_send_tables()


func _host_join(peer: int, table: int) -> void:
	var m: Dictionary = _matches.get(table, {})
	if m.is_empty() or String(m["state"]) != "open" or (m["players"] as Array).has(peer) or not net.roster.has(peer):
		_tell_refused(peer, "Nobody is waiting at that table.")
		return
	(m["players"] as Array).append(peer)
	(m["names"] as Array).append(String(net.roster[peer]))
	m["state"] = "playing"
	var sim := Sim.new(_cfg)
	sim.rack(_rng)
	var rules := Rules.new()
	rules.start()
	m["sim"] = sim
	m["rules"] = rules
	m["clock"] = _now() + float(_cfg["shot_clock"]) + GRACE
	_send_tables()
	_started_show.rpc(table, m["players"], m["names"], sim.to_dict(), rules.to_dict())
	started.emit(table, m["players"], m["names"], sim.to_dict(), rules.to_dict())


func _host_leave(peer: int, table: int, reason: String) -> void:
	var m: Dictionary = _matches.get(table, {})
	if m.is_empty() or not (m["players"] as Array).has(peer):
		return
	var players: Array = m["players"]
	var winner := 0
	if String(m["state"]) == "playing":
		winner = int(players[1]) if int(players[0]) == peer else int(players[0])
	_matches.erase(table)
	_send_tables()
	_ended_show.rpc(table, winner, reason)
	ended.emit(table, winner, reason)


func _host_shot(peer: int, args: Array) -> void:
	var table := int(args[0])
	var m: Dictionary = _matches.get(table, {})
	if m.is_empty() or String(m["state"]) != "playing":
		return
	var rules: Rules = m["rules"]
	var sim: Sim = m["sim"]
	if int((m["players"] as Array)[rules.current]) != peer:
		return
	if not (args[1] is Vector2) or not (args[4] is Vector2):
		return
	var cue: Vector2 = args[1]
	if rules.ball_in_hand or sim.on_table[0] == 0:
		if not cue.is_finite() or not sim.place(0, cue):
			sim.place(0, _free_spot(sim, sim.head_spot()))
	_play(table, m, [float(args[2]), clampf(float(args[3]), 0.0, 1.0), (args[4] as Vector2).limit_length(0.85), int(args[5])])


# Plays a shot (or a timed-out turn: params []) on the host's table and tells everyone.
func _play(table: int, m: Dictionary, params: Array) -> void:
	var rules: Rules = m["rules"]
	var sim: Sim = m["sim"]
	var shooter := rules.current
	var start := sim.to_dict()
	var res: Dictionary
	if params.is_empty():
		sim.first_hit = -1
		sim.pocketed.clear()
		res = rules.judge(-1, [], false, sim.on_table, -1, true)
	else:
		var p := float(params[1])
		sim.shoot(float(params[0]), p * p * 0.85 + p * 0.15, params[2])
		sim.run_to_rest()
		res = rules.judge(sim.first_hit, sim.pocketed, sim.rail_after_contact, sim.on_table, int(params[3]))
	if bool(res["eight_respot"]):
		sim.place(8, _free_spot(sim, sim.foot_spot()))
	if sim.on_table[0] == 0:
		sim.place(0, _free_spot(sim, sim.head_spot()))
	var data := {"shooter": shooter, "start": start, "params": params, "end": sim.to_dict(), "rules": rules.to_dict()}
	m["clock"] = _now() + 12.0 + float(_cfg["shot_clock"]) + GRACE  # (the shot rolls on the players' tables first)
	_shot_show.rpc(table, data)
	shot.emit(table, data)
	if int(res["winner"]) >= 0:
		var winner := int((m["players"] as Array)[int(res["winner"])])
		_matches.erase(table)
		_send_tables()
		_ended_show.rpc(table, winner, "won")
		ended.emit(table, winner, "won")


func _process(_delta: float) -> void:
	if not online() or not net.is_host():
		return
	for t: int in _matches.keys():
		var m: Dictionary = _matches[t]
		if String(m["state"]) == "playing" and _now() > float(m["clock"]):
			_play(t, m, [])


func _free_spot(sim: Sim, at: Vector2) -> Vector2:
	for k in 40:
		var p := at + Vector2(float(k % 5) * 0.07 - 0.14, floorf(float(k) / 5.0) * 0.07 * (1.0 if k % 2 == 0 else -1.0))
		var ok := true
		for j in range(1, 16):
			if sim.on_table[j] == 1 and sim.pos[j].distance_to(p) < 2.1 * sim.r:
				ok = false
		if ok:
			return p
	return at


func _on_roster(roster: Dictionary) -> void:
	if not net.is_host():
		return
	_send_tables()
	for t: int in _matches.keys():
		for peer: Variant in (_matches[t]["players"] as Array):
			if not roster.has(int(peer)):
				_host_leave(int(peer), t, "left the lobby")
				break


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _send_tables() -> void:
	var list: Array = []
	for t in _count():
		var m: Dictionary = _matches.get(t, {})
		list.append({} if m.is_empty() else {"state": m["state"], "stake": m["stake"], "players": m["players"], "names": m["names"]})
	if online():
		_tables_show.rpc(list)
	tables = list
	tables_changed.emit(list)


func _tell_refused(peer: int, text: String) -> void:
	if peer == 1:
		refused.emit(text)
	else:
		_refused_show.rpc_id(peer, text)


@rpc("authority", "call_remote", "reliable")
func _tables_show(list: Array) -> void:
	tables = list
	tables_changed.emit(list)


@rpc("authority", "call_remote", "reliable")
func _started_show(table: int, players: Array, names: Array, start: Dictionary, rules: Dictionary) -> void:
	started.emit(table, players, names, start, rules)


@rpc("authority", "call_remote", "reliable")
func _shot_show(table: int, data: Dictionary) -> void:
	shot.emit(table, data)


@rpc("authority", "call_remote", "reliable")
func _ended_show(table: int, winner_peer: int, reason: String) -> void:
	ended.emit(table, winner_peer, reason)


@rpc("authority", "call_remote", "reliable")
func _refused_show(text: String) -> void:
	refused.emit(text)
