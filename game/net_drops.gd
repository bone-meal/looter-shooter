# Purpose: guns a player drops are shared online (director, round 5: only PLAYER drops; enemy and chest drops stay
# each player's own). The HOST keeps the list (core/shared_drops.gd): a dropped gun is laid down for everyone, and
# the first player who asks for it gets it. Signals tell this machine's game what to show and what its player got.
# The host checks that a dropped gun is a legal roll (`legal`) and that it is laid near its player.
# Dependencies: game/net_session.gd (parent; `net`), core/shared_drops.gd. Node name must be "Drops" on every machine.
extends Node

const SharedDrops = preload("res://core/shared_drops.gd")

signal spawned(id: int, gun: Dictionary, pos: Vector3)
signal removed(id: int)
signal granted(gun: Dictionary)  # this machine's player picked it up
signal refused(gun: Dictionary)  # the host would not lay it down: it goes back into the bag

const REACH := 8.0  # metres: a gun must be laid this near its player

var net: Node3D
var book := SharedDrops.new()  # only the host's is used
var legal := Callable()  # host: func(gun: Dictionary) -> bool, set by game/game_session.gd

var _tick := 0.0


func _ready() -> void:
	net.roster_changed.connect(_on_roster_changed)


func drop(gun: Dictionary, pos: Vector3) -> void:
	if net.is_host():
		_lay(net.my_id(), gun, pos)
	else:
		_drop_to_host.rpc_id(1, gun, pos)


func take(id: int) -> void:
	if net.is_host():
		_give(net.my_id(), id)
	else:
		_take_to_host.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _drop_to_host(gun: Dictionary, pos: Vector3) -> void:
	var id := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(id):
		_lay(id, gun, pos)


@rpc("any_peer", "call_remote", "reliable")
func _take_to_host(id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(peer):
		_give(peer, id)


func _lay(peer: int, gun: Dictionary, pos: Vector3) -> void:
	var where: Dictionary = net.positions()
	var near: bool = where.has(peer) and (where[peer] as Vector3).distance_to(pos) <= REACH
	if not near or not legal.is_valid() or not bool(legal.call(gun)):
		if peer == net.my_id():
			refused.emit(gun)
		else:
			_refused.rpc_id(peer, gun)
		return
	var made := book.add(gun, pos, Time.get_ticks_msec() / 1000.0)
	for old: int in made["gone"]:
		_gone.rpc(old)
		removed.emit(old)
	_laid.rpc(int(made["id"]), gun, pos)
	spawned.emit(int(made["id"]), gun, pos)


func _give(peer: int, id: int) -> void:
	var gun := book.take(id)
	if gun.is_empty():
		return  # somebody else was first
	_gone.rpc(id)
	removed.emit(id)
	if peer == net.my_id():
		granted.emit(gun)
	else:
		_granted.rpc_id(peer, gun)


@rpc("authority", "call_remote", "reliable")
func _laid(id: int, gun: Dictionary, pos: Vector3) -> void:
	spawned.emit(id, gun, pos)


@rpc("authority", "call_remote", "reliable")
func _gone(id: int) -> void:
	removed.emit(id)


@rpc("authority", "call_remote", "reliable")
func _granted(gun: Dictionary) -> void:
	granted.emit(gun)


@rpc("authority", "call_remote", "reliable")
func _refused(gun: Dictionary) -> void:
	refused.emit(gun)


# Somebody joined: the host tells everyone again what lies around (a machine that already shows a drop skips it).
func _on_roster_changed(_roster: Dictionary) -> void:
	if net.can_send() and net.is_host():
		for entry: Array in book.all():
			_laid.rpc(int(entry[0]), entry[1], entry[2])


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 1.0 or not net.can_send() or not net.is_host():
		return
	_tick = 0.0
	for id: int in book.expired(Time.get_ticks_msec() / 1000.0):
		_gone.rpc(id)
		removed.emit(id)
