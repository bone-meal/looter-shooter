# Purpose: the card game between players online (locked build step 13). A thin network shell around
# core/tcg/table_book.gd: the HOST keeps the book of the three player tables and runs every match there; players send
# only intents (sit, leave, their deck, moves); what the book answers goes to the players concerned or to everyone
# (all see the seats and every match, spectators included). This machine hears it through `message`
# (seats / pick / countdown / match / refused / result). A client's claims are type-checked here, judged by the book.
# Host quits = the match is void (a new host's book is empty; the session drops the table on host change).
# Dependencies: game/net_session.gd (parent; `net`), core/tcg/table_book.gd, core/tcg/card_db.gd. Node name "Tcg".
extends Node

const TableBook = preload("res://core/tcg/table_book.gd")
const CardDb = preload("res://core/tcg/card_db.gd")

signal message(what: String, args: Array)

const TABLES := 3

var net: Node3D
var book: RefCounted  # only the host's is used
var _tick := 0.0


func _ready() -> void:
	book = TableBook.new(CardDb.from_files(), TABLES)


func sit(table: int) -> void:
	_to_host("sit", [table])


func leave() -> void:
	_to_host("leave", [])


func deck(chosen: Dictionary) -> void:
	_to_host("deck", [chosen])


func intent(move: Dictionary) -> void:
	_to_host("intent", [move])


# The host's book learns where the tables stand once its club is built.
func set_spots(spots: Array) -> void:
	book.call("set_spots", spots)


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
		"sit":
			if first is int:
				out = book.call("sit", peer, int(first), net.roster)
		"leave":
			out = book.call("leave", peer, net.roster)
		"deck":
			if first is Dictionary:
				out = book.call("deck", peer, first, net.roster)
		"intent":
			if first is Dictionary:
				out = book.call("intent", peer, first, net.roster)
	_deliver(out)


func _deliver(out: Array) -> void:
	for entry: Array in out:
		var to := int(entry[0])
		if to == 0:  # everyone
			message.emit(String(entry[1]), entry[2])
			_to_client.rpc(String(entry[1]), entry[2])
		elif to == net.my_id():
			message.emit(String(entry[1]), entry[2])
		elif net.roster.has(to):
			_to_client.rpc_id(to, String(entry[1]), entry[2])


@rpc("authority", "call_remote", "reliable")
func _to_client(what: String, args: Array) -> void:
	message.emit(what, args)


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.25 or not net.can_send() or not net.is_host():
		return
	_deliver(book.call("tick", _tick, net.roster, net.positions()))
	_tick = 0.0
