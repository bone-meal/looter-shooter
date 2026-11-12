# Purpose: trading between players. A thin network shell around core/trade_desk.gd: the HOST keeps the desk, every
# player's action goes to it (the host's own directly), and what the desk answers is sent to the players concerned.
# This machine's player hears it through `message` (asked / waiting / table / refused / done / ended).
# A client's claims are type-checked here and judged by the desk (`desk.legal`); nothing a client sends is trusted.
# Dependencies: game/net_session.gd (parent; `net`), core/trade_desk.gd. Node name must be "Trade" on every machine.
extends Node

const TradeDesk = preload("res://core/trade_desk.gd")

signal message(what: String, args: Array)

var net: Node3D
var desk := TradeDesk.new()  # only the host's is used

var _tick := 0.0


func ask(peer: int) -> void:
	_to_host("ask", [peer])


func answer(yes: bool) -> void:
	_to_host("answer", [yes])


# thing: {"ref": inventory slot, "gun": {...}} or {"ref": slot, "id": armour item id}
func offer(thing: Dictionary) -> void:
	_to_host("offer", [thing])


func withdraw(ref: int) -> void:
	_to_host("withdraw", [ref])


func set_ready(on: bool) -> void:
	_to_host("ready", [on])


func confirm() -> void:
	_to_host("confirm", [])


func cancel() -> void:
	_to_host("cancel", [])


func _to_host(what: String, args: Array) -> void:
	if not net.can_send():
		return
	if net.is_host():
		_handle(net.my_id(), what, args)
	else:
		_from_client.rpc_id(1, what, args)


@rpc("any_peer", "call_remote", "reliable")
func _from_client(what: String, args: Array) -> void:
	if not net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if net.roster.has(id):
		_handle(id, what, args)


func _handle(peer: int, what: String, args: Array) -> void:
	var first: Variant = args[0] if args.size() > 0 else null
	var out: Array = []
	match what:
		"ask":
			if first is int:
				out = desk.ask(peer, int(first), net.roster, Time.get_ticks_msec() / 1000.0)
		"answer":
			if first is bool:
				out = desk.answer(peer, bool(first), net.roster)
		"offer":
			if first is Dictionary:
				out = desk.offer(peer, first as Dictionary, net.roster)
		"withdraw":
			if first is int:
				out = desk.withdraw(peer, int(first), net.roster)
		"ready":
			if first is bool:
				out = desk.set_ready(peer, bool(first), net.roster)
		"confirm":
			out = desk.confirm(peer, net.roster)
		"cancel":
			out = desk.cancel(peer, net.roster)
	_deliver(out)


func _deliver(out: Array) -> void:
	for entry: Array in out:
		var to := int(entry[0])
		if to == net.my_id():
			message.emit(String(entry[1]), entry[2])
		elif net.roster.has(to):
			_to_client.rpc_id(to, String(entry[1]), entry[2])


@rpc("authority", "call_remote", "reliable")
func _to_client(what: String, args: Array) -> void:
	message.emit(what, args)


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.5 or not net.can_send() or not net.is_host():
		return
	_tick = 0.0
	_deliver(desk.tick(net.roster, net.positions(), Time.get_ticks_msec() / 1000.0))
