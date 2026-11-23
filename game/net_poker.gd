# Purpose: (polish1 item 167) the casino's poker table online. The host deals (game/poker_dealer.gd): a player asks to
# SIT (stakes + buy-in), MOVE (fold / check / call / raise: an intent, taken only on their turn), REBUY or LEAVE; the
# host checks it, plays the house players and the turn clock, and sends every machine the table as that machine may see
# it (its own cards only; everyone sees the cards shown at a showdown). Chips stay on each player's machine: the buy-in
# is taken there before asking (given back when the host refuses), and the host says how many chips go back to the
# wallet when the player stands up. When the host is lost (migration) or this machine leaves the lobby, a seated
# player's table chips go back to their wallet (the hand in play is called off).
# Dependencies: game/net_session.gd (parent; `net`), game/poker_dealer.gd, core/data_store.gd, data/poker.json.
# Node name must be "Poker" on every machine.
extends Node

const Dealer = preload("res://game/poker_dealer.gd")
const DataStore = preload("res://core/data_store.gd")

signal view_changed(view: Dictionary, seat: int, queued: bool, events: Array)  # {} = no table
signal paid_out(chips: int)  # chips back to this machine's wallet
signal refused(text: String, refund: int)  # the host said no; `refund` chips go back to the wallet
signal table_lost(chips: int)  # the host is gone: this machine's table chips back to the wallet

var net: Node3D
var last_view: Dictionary = {}  # every machine: the table as this machine sees it
var my_seat := -1

var _cfg: Dictionary
var _dealer: Dealer  # host only
var _held := 0  # this machine's chips at the table (and a buy-in waiting for a seat), for a lost host


func _ready() -> void:
	_cfg = DataStore.load_json("res://data/poker.json")
	net.roster_changed.connect(_on_roster)
	_new_dealer()


func _new_dealer() -> void:
	if _dealer != null:
		_dealer.queue_free()
	_dealer = Dealer.new()
	_dealer.cfg = _cfg
	_dealer.turn_s = float(_cfg.get("turn_s_online", 30.0))
	add_child(_dealer)
	_dealer.changed.connect(_on_dealer_changed)
	_dealer.paid.connect(_on_dealer_paid)


func online() -> bool:
	return net != null and net.can_send()


# (dev) the host's dealer, so a check can let the house AI play a seat.
func dealer() -> Dealer:
	return _dealer if net != null and net.is_host() else null


func ask_sit(stakes: int, buy_in: int) -> void:
	_held += buy_in
	_call_host("_sit_to_host", [stakes, buy_in])


func ask_move(mv: Dictionary) -> void:
	_call_host("_move_to_host", [mv])


func ask_rebuy(amount: int) -> void:
	_held += amount
	_call_host("_rebuy_to_host", [amount])


func ask_leave() -> void:
	_held = 0  # the host pays it back (paid_out)
	_call_host("_leave_to_host", [])


# Called by game/net_session.gd when the host is lost or this machine leaves the lobby.
func after_host_lost() -> void:
	var chips := _held
	_held = 0
	my_seat = -1
	last_view = {}
	_new_dealer()
	view_changed.emit({}, -1, false, [])
	if chips > 0:
		table_lost.emit(chips)


func _call_host(method: String, args: Array) -> void:
	if not online():
		return
	if net.is_host():
		_as_host(1, method, args)
	else:
		callv("rpc_id", [1, method] + args)


func _as_host(peer: int, method: String, args: Array) -> void:
	if not net.roster.has(peer) and peer != 1:
		return
	match method:
		"_sit_to_host":
			var stakes := int(args[0])
			var buy_in := int(args[1])
			var why := _dealer.sit(peer, String(net.roster.get(peer, "Player")), stakes, buy_in)
			if why != "":
				_tell_refused(peer, why, buy_in)
		"_move_to_host":
			if args[0] is Dictionary:
				var mv: Dictionary = args[0]
				var clean := {"do": String(mv.get("do", "fold"))}
				if mv.has("to"):
					clean["to"] = int(mv["to"])
				_dealer.move(peer, clean)
		"_rebuy_to_host":
			var why2 := _dealer.rebuy(peer, int(args[0]))
			if why2 != "":
				_tell_refused(peer, why2, int(args[0]))
		"_leave_to_host":
			_dealer.leave(peer)


@rpc("any_peer", "call_remote", "reliable")
func _sit_to_host(stakes: int, buy_in: int) -> void:
	if net.is_host():
		_as_host(multiplayer.get_remote_sender_id(), "_sit_to_host", [stakes, buy_in])


@rpc("any_peer", "call_remote", "reliable")
func _move_to_host(mv: Variant) -> void:
	if net.is_host():
		_as_host(multiplayer.get_remote_sender_id(), "_move_to_host", [mv])


@rpc("any_peer", "call_remote", "reliable")
func _rebuy_to_host(amount: int) -> void:
	if net.is_host():
		_as_host(multiplayer.get_remote_sender_id(), "_rebuy_to_host", [amount])


@rpc("any_peer", "call_remote", "reliable")
func _leave_to_host() -> void:
	if net.is_host():
		_as_host(multiplayer.get_remote_sender_id(), "_leave_to_host", [])


# Host: the table moved on: every machine gets it as it may see it.
func _on_dealer_changed(events: Array) -> void:
	if not net.is_host():
		return
	var peers: Array = net.roster.keys()
	if not peers.has(1):
		peers.append(1)
	for peer: int in peers:
		var seat := _dealer.seat_of(peer)
		var v := _dealer.view_for(seat)
		var q := _dealer.queued(peer)
		if peer == 1:
			_show(v, seat, q, events)
		elif online():
			_view_show.rpc_id(peer, v, seat, q, events)


func _on_dealer_paid(peer: int, chips: int) -> void:
	if peer == 1:
		_paid_show(chips)
	elif online() and net.roster.has(peer):
		_paid_show.rpc_id(peer, chips)


func _on_roster(roster: Dictionary) -> void:
	if not net.is_host():
		return
	for i in _dealer.owners.size():
		var o := int(_dealer.owners[i])
		if o != 0 and o != 1 and not roster.has(o):
			_dealer.leave(o)  # left the lobby: their machine took its chips back (after_host_lost is theirs to call on leaving)
	for peer: int in roster:  # a newcomer sees the table
		if peer != 1 and online():
			_view_show.rpc_id(peer, _dealer.view_for(-1), -1, false, [])


func _tell_refused(peer: int, text: String, refund: int) -> void:
	if peer == 1:
		_refused_show(text, refund)
	elif online():
		_refused_show.rpc_id(peer, text, refund)


func _show(v: Dictionary, seat: int, q: bool, events: Array) -> void:
	last_view = v
	my_seat = seat
	if seat >= 0 and not v.is_empty():
		var s: Dictionary = (v["seats"] as Array)[seat]
		_held = int(s["chips"]) + (int(s["put"]) if String(v.get("phase", "")) not in ["idle", "showdown"] else 0)
	view_changed.emit(v, seat, q, events)


@rpc("authority", "call_remote", "reliable")
func _view_show(v: Dictionary, seat: int, q: bool, events: Array) -> void:
	_show(v, seat, q, events)


@rpc("authority", "call_remote", "reliable")
func _paid_show(chips: int) -> void:
	paid_out.emit(chips)


@rpc("authority", "call_remote", "reliable")
func _refused_show(text: String, refund: int) -> void:
	_held = maxi(_held - refund, 0)
	refused.emit(text, refund)
