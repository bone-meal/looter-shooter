# Purpose: (polish1 item 71) darts between two players online, for chips. The host keeps every board's match: a
# player OPENS a board (game + stake), another JOINS it, then the host plays the rules (core/darts_rules.gd): a
# player's throw is only the point it aimed at (an intent); the host adds the throw's spread, scores it, and sends
# the landing and the new state to everyone (the players play it out; everyone else sees the darts on the board).
# The winner is the host's call (also when the other player leaves the lobby). Chips stay on each player's machine:
# each pays the stake when opening / joining, the winner's machine is paid twice the stake.
# Dependencies: game/net_session.gd (parent; `net`), core/darts_rules.gd, core/data_store.gd, data/darts.json.
# Node name must be "Darts" on every machine.
extends Node

const Rules = preload("res://core/darts_rules.gd")
const DataStore = preload("res://core/data_store.gd")

signal tables_changed(tables: Array)  # per board: {} free, or {"state" open|playing, "mode", "stake", "players", "names"}
signal started(board: int, players: Array, names: Array, snap: Dictionary)
signal thrown(board: int, thrower: int, p: Vector2, snap: Dictionary)  # thrower = 0 / 1 (the player's place in `players`)
signal ended(board: int, winner_peer: int, reason: String)
signal refused(text: String)

const TURN_PAUSE := 1.6  # seconds the players' machines show a finished turn before the next player may throw
const FLIGHT := 0.3

var net: Node3D
var tables: Array = []  # the latest table list (every machine)

var _cfg: Dictionary
var _matches := {}  # host: board -> {"state", "mode", "stake", "players", "names", "rules", "ready_at"}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_cfg = DataStore.load_json("res://data/darts.json")
	_rng.randomize()
	net.roster_changed.connect(_on_roster)


func online() -> bool:
	return net != null and net.can_send()


func ask_open(board: int, mode: String, stake: int) -> void:
	_call_host("_open_to_host", [board, mode, stake])


func ask_join(board: int) -> void:
	_call_host("_join_to_host", [board])


func ask_leave(board: int) -> void:
	_call_host("_leave_to_host", [board])


func ask_throw(board: int, aim: Vector2) -> void:
	_call_host("_throw_to_host", [board, aim])


# The host runs its own asks directly (it is peer 1).
func _call_host(method: String, args: Array) -> void:
	if not online():
		return
	if net.is_host():
		_as_host(1, method, args)
	else:
		callv("rpc_id", [1, method] + args)


func _as_host(peer: int, method: String, args: Array) -> void:
	match method:
		"_open_to_host":
			_host_open(peer, int(args[0]), String(args[1]), int(args[2]))
		"_join_to_host":
			_host_join(peer, int(args[0]))
		"_leave_to_host":
			_host_leave(peer, int(args[0]), "left")
		"_throw_to_host":
			_host_throw(peer, int(args[0]), args[1])


@rpc("any_peer", "call_remote", "reliable")
func _open_to_host(board: int, mode: String, stake: int) -> void:
	if net.is_host():
		_host_open(multiplayer.get_remote_sender_id(), board, mode, stake)


@rpc("any_peer", "call_remote", "reliable")
func _join_to_host(board: int) -> void:
	if net.is_host():
		_host_join(multiplayer.get_remote_sender_id(), board)


@rpc("any_peer", "call_remote", "reliable")
func _leave_to_host(board: int) -> void:
	if net.is_host():
		_host_leave(multiplayer.get_remote_sender_id(), board, "left")


@rpc("any_peer", "call_remote", "reliable")
func _throw_to_host(board: int, aim: Vector2) -> void:
	if net.is_host():
		_host_throw(multiplayer.get_remote_sender_id(), board, aim)


func _boards() -> int:
	return (_cfg["boards"] as Array).size()


func _host_open(peer: int, board: int, mode: String, stake: int) -> void:
	if board < 0 or board >= _boards() or _matches.has(board) or not net.roster.has(peer):
		_tell_refused(peer, "That board is taken.")
		return
	var stake_ok := false
	for s: Variant in _cfg["stakes"]:
		stake_ok = stake_ok or int(s) == stake
	if mode not in ["501", "clock"] or not stake_ok:
		_tell_refused(peer, "That game is not offered.")
		return
	for b: int in _matches:  # one match at a time per player
		if (_matches[b]["players"] as Array).has(peer):
			_tell_refused(peer, "You are already at a board.")
			return
	_matches[board] = {"state": "open", "mode": mode, "stake": stake, "players": [peer], "names": [String(net.roster[peer])], "rules": null, "ready_at": 0.0}
	_send_tables()


func _host_join(peer: int, board: int) -> void:
	var m: Dictionary = _matches.get(board, {})
	if m.is_empty() or String(m["state"]) != "open" or (m["players"] as Array).has(peer) or not net.roster.has(peer):
		_tell_refused(peer, "Nobody is waiting at that board.")
		return
	(m["players"] as Array).append(peer)
	(m["names"] as Array).append(String(net.roster[peer]))
	m["state"] = "playing"
	var r := Rules.new(_cfg)
	r.start(String(m["mode"]), 2)
	m["rules"] = r
	m["ready_at"] = _now()
	_send_tables()
	var snap := r.snapshot({})
	_started_show.rpc(board, m["players"], m["names"], snap)
	started.emit(board, m["players"], m["names"], snap)


func _host_leave(peer: int, board: int, reason: String) -> void:
	var m: Dictionary = _matches.get(board, {})
	if m.is_empty() or not (m["players"] as Array).has(peer):
		return
	var players: Array = m["players"]
	var winner := 0
	if String(m["state"]) == "playing":  # the one who stays wins
		winner = int(players[1]) if int(players[0]) == peer else int(players[0])
	_matches.erase(board)
	_send_tables()
	_ended_show.rpc(board, winner, reason)
	ended.emit(board, winner, reason)


func _host_throw(peer: int, board: int, aim: Variant) -> void:
	var m: Dictionary = _matches.get(board, {})
	if m.is_empty() or String(m["state"]) != "playing" or not (aim is Vector2):
		return
	var r: Rules = m["rules"]
	var players: Array = m["players"]
	if int(players[r.current]) != peer or _now() < float(m["ready_at"]):
		return  # not this player's turn, or the last dart / turn is still being shown
	var spread := float(_cfg["aim"]["spread"])
	var p: Vector2 = (aim as Vector2).limit_length(300.0) + Vector2(_rng.randfn(0.0, spread), _rng.randfn(0.0, spread))
	var thrower := r.current
	var res := r.throw_dart(p)
	var snap := r.snapshot(res)
	m["ready_at"] = _now() + FLIGHT + (TURN_PAUSE if bool(res["turn_over"]) else 0.0)
	_thrown_show.rpc(board, thrower, p, snap)
	thrown.emit(board, thrower, p, snap)
	if bool(res["won"]):
		var winner := int(players[r.winner])
		_matches.erase(board)
		_send_tables()
		_ended_show.rpc(board, winner, "won")
		ended.emit(board, winner, "won")
	elif bool(res["turn_over"]):
		r.next_turn()


func _on_roster(roster: Dictionary) -> void:
	if not net.is_host():
		return
	_send_tables()  # (a newcomer learns who waits at which board)
	for b: int in _matches.keys():
		for peer: Variant in (_matches[b]["players"] as Array):
			if not roster.has(int(peer)):
				_host_leave(int(peer), b, "left the lobby")
				break


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _send_tables() -> void:
	var list: Array = []
	for b in _boards():
		var m: Dictionary = _matches.get(b, {})
		list.append({} if m.is_empty() else {"state": m["state"], "mode": m["mode"], "stake": m["stake"], "players": m["players"], "names": m["names"]})
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
func _started_show(board: int, players: Array, names: Array, snap: Dictionary) -> void:
	started.emit(board, players, names, snap)


@rpc("authority", "call_remote", "reliable")
func _thrown_show(board: int, thrower: int, p: Vector2, snap: Dictionary) -> void:
	thrown.emit(board, thrower, p, snap)


@rpc("authority", "call_remote", "reliable")
func _ended_show(board: int, winner_peer: int, reason: String) -> void:
	ended.emit(board, winner_peer, reason)


@rpc("authority", "call_remote", "reliable")
func _refused_show(text: String) -> void:
	refused.emit(text)
