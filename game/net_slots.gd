# Purpose: (director 2026-11-20) ONE slot jackpot for the whole lobby. The host keeps the pot: every spin anyone in the
# lobby makes grows it, and the host rolls each client's spin (reel stops and payout), so no client can claim a jackpot.
# The pot goes out to everyone after every spin; a jackpot is told to the whole lobby under the winner's roster name.
# Dependencies: game/net_session.gd (parent; `net`). game/game_session.gd sets host_spin / host_pot and listens.
# Node name must be "Slots" on every machine.
extends Node

signal pot(value: float)  # the lobby's pot changed
signal spun(stops: Array, total: int, jackpot_won: bool)  # client: the host's roll of our spin (total -1 = refused)
signal jackpot(sender: String, won: int)  # someone in the lobby hit the slots jackpot

const MIN_GAP := 0.8  # host: seconds a client must leave between spins (the reels turn for longer)

var net: Node3D
var host_spin := Callable()  # host: func(bet: int) -> {"stops", "total", "jackpot_won"}, {} when the bet is not allowed
var host_pot := Callable()  # host: func() -> float, the lobby's pot

var _last := {}  # host: peer id -> engine time of the last spin


func online() -> bool:
	return net != null and net.can_send()


func is_client() -> bool:
	return online() and not net.is_host()


func ask_spin(bet: int) -> void:
	_spin_to_host.rpc_id(1, bet)


func ask_pot() -> void:
	if is_client():
		_pot_to_host.rpc_id(1)


# Host: after its own spin.
func tell_pot(value: float) -> void:
	if online() and net.is_host():
		_pot_show.rpc(value)


# Host: its own jackpot.
func tell_jackpot(won: int) -> void:
	if online() and net.is_host():
		_jack_show.rpc(net.local_name(), won)


@rpc("any_peer", "call_remote", "reliable")
func _spin_to_host(bet: int) -> void:
	if not net.is_host() or not host_spin.is_valid():
		return
	var id := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec() / 1000.0
	if not net.roster.has(id) or now - float(_last.get(id, -10.0)) < MIN_GAP:
		_spun.rpc_id(id, [], -1, false)
		return
	_last[id] = now
	var r: Dictionary = host_spin.call(bet)
	if r.is_empty():
		_spun.rpc_id(id, [], -1, false)
		return
	_spun.rpc_id(id, r["stops"], int(r["total"]), bool(r["jackpot_won"]))
	var value: float = host_pot.call()
	_pot_show.rpc(value)
	pot.emit(value)
	if bool(r["jackpot_won"]):
		var who := String(net.roster[id])
		_jack_show.rpc(who, int(r["total"]))
		jackpot.emit(who, int(r["total"]))


@rpc("authority", "call_remote", "reliable")
func _spun(stops: Array, total: int, jackpot_won: bool) -> void:
	spun.emit(stops, total, jackpot_won)


@rpc("any_peer", "call_remote", "reliable")
func _pot_to_host() -> void:
	if net.is_host() and host_pot.is_valid():
		_pot_show.rpc_id(multiplayer.get_remote_sender_id(), float(host_pot.call()))


@rpc("authority", "call_remote", "reliable")
func _pot_show(value: float) -> void:
	pot.emit(value)


@rpc("authority", "call_remote", "reliable")
func _jack_show(sender: String, won: int) -> void:
	jackpot.emit(sender, won)
