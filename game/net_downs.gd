# Purpose: who of the party is down on the islands. Each machine tells the host when its player goes DOWN (lying
# there, waiting for a revive), is OUT (bled out: back when the next round starts) or is UP again. The host passes the
# states on to everybody, decides revives (the reviver has to be up and standing by the downed player) and ends the
# run for the whole party when nobody on the islands is left standing.
# Dependencies: game/net_session.gd (parent; `net`). game/game_session.gd sets `on_island` and `round_now` and listens
# to the signals. Node name must be "Downs" on every machine.
extends Node

const STATES := ["up", "down", "out"]
const SLACK := 2.5  # metres added to the revive reach for what the host cannot see exactly (lag)

signal revived(share: float)  # somebody helped us up; share = how much of our health we get
signal gave_revive  # the host confirmed that we helped somebody up
signal party_over(round_reached: int)  # the run ended for everybody
signal states_changed

var net: Node3D
var states := {}  # peer id -> "down" or "out" (not listed = up)
var on_island := Callable()  # host: func(at: Vector3) -> bool
var round_now := Callable()  # host: func() -> int: the round being fought
var reach := 2.5  # metres from which a revive works (data/island_rounds.json "downs")
var health_share := 0.5  # health a revived player gets

var _check := 0.0


func state_of(peer: int) -> String:
	return String(states.get(peer, "up"))


# Tells the party our own state.
func report(state: String) -> void:
	if not net.can_send() or not (state in STATES):
		return
	if net.is_host():
		_set_state(1, state)
	else:
		_state_to_host.rpc_id(1, state)


# We held the key long enough next to that downed player.
func ask_revive(target: int) -> void:
	if not net.can_send():
		return
	if net.is_host():
		_do_revive(1, target)
	else:
		_revive_to_host.rpc_id(1, target)


func _process(delta: float) -> void:
	if not net.can_send() or not net.is_host():
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		for peer: int in states.keys():  # somebody left the session while down
			if not net.roster.has(peer):
				states.erase(peer)
		_check_over()


@rpc("any_peer", "call_remote", "reliable")
func _state_to_host(state: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(peer) and (state in STATES):
		_set_state(peer, state)


func _set_state(peer: int, state: String) -> void:
	if state == "up":
		states.erase(peer)
	else:
		states[peer] = state
	_states.rpc(states)
	states_changed.emit()
	_check_over()


@rpc("authority", "call_remote", "reliable")
func _states(all: Dictionary) -> void:
	states.clear()
	for peer: Variant in all:
		if peer is int and (all[peer] is String) and (all[peer] in STATES) and all[peer] != "up":
			states[peer] = all[peer]
	states_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _revive_to_host(target: int) -> void:
	if net.is_host():
		_do_revive(multiplayer.get_remote_sender_id(), target)


# Host: `by` wants to help `target` up. Only somebody who is up and close to a downed player can.
func _do_revive(by: int, target: int) -> void:
	if by == target or not net.roster.has(by) or state_of(target) != "down" or state_of(by) != "up":
		return
	var helper: Node3D = net.player_node(by)
	var fallen: Node3D = net.player_node(target)
	if helper == null or fallen == null or helper.global_position.distance_to(fallen.global_position) > reach + SLACK:
		return
	states.erase(target)
	_states.rpc(states)
	states_changed.emit()
	if target == net.my_id():
		revived.emit(health_share)
	else:
		_revived.rpc_id(target, health_share)
	if by == net.my_id():
		gave_revive.emit()
	else:
		_gave.rpc_id(by)


@rpc("authority", "call_remote", "reliable")
func _revived(share: float) -> void:
	revived.emit(clampf(share, 0.05, 1.0) if is_finite(share) else 0.5)


@rpc("authority", "call_remote", "reliable")
func _gave() -> void:
	gave_revive.emit()


# Host: when every player standing on the islands is down or out, the run is over for the party.
func _check_over() -> void:
	if not net.is_host() or states.is_empty() or not on_island.is_valid():
		return
	var there := 0
	var where: Dictionary = net.positions()
	for peer: int in where:
		if bool(on_island.call(where[peer])):
			there += 1
			if state_of(peer) == "up":
				return
	if there == 0:
		return
	var reached := int(round_now.call()) if round_now.is_valid() else 0
	states.clear()
	_states.rpc(states)
	_over.rpc(reached)
	states_changed.emit()
	party_over.emit(reached)


@rpc("authority", "call_remote", "reliable")
func _over(round_reached: int) -> void:
	states.clear()
	states_changed.emit()
	party_over.emit(maxi(round_reached, 0))
