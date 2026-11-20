# Purpose: text chat and command permissions between players. The host relays every chat line under the sender's
# roster name (never a name the client claims), keeps the list of operators (/op) and runs world commands that
# clients send as text. /tp of OTHER players (Minecraft style): an operator asks the host, the host checks him and
# tells the moved player's machine where to go (a player or a place in a world); that machine moves its own body.
# Dependencies: game/net_session.gd (parent; `net`), core/chat_command.gd. Node name must be "Chat" on every machine.
extends Node

const ChatCommand = preload("res://core/chat_command.gd")

signal line(sender: String, text: String)  # a chat line to show (also our own, echoed)
signal reply(text: String)  # the host's answer to a command we sent
signal op_changed(allowed: bool)  # the host gave or took our right to use commands
signal unboxed(sender: String, text: String)  # (polish1 item 72) someone opened a crate and got gold or better: told to everyone
signal tp_ordered(target: Dictionary, by: String)  # an operator teleports us: {"kind": "player", "id"} or {"kind": "pos", "world", "at"}

const MIN_GAP := 0.4  # host: seconds a client must leave between lines

var net: Node3D
var world_command := Callable()  # host: func(peer: int, text: String) -> PackedStringArray, set by game/game_session.gd
var allowed := false  # client: the host made us an operator

var _ops := {}  # host: peer id -> true
var _last := {}  # host: peer id -> engine time of the last line


func say(text: String) -> void:
	var clean := ChatCommand.clean(text)
	if clean == "":
		return
	if not net.can_send():
		line.emit(net.local_name(), clean)  # playing alone
	elif net.is_host():
		_show.rpc(net.local_name(), clean)
		line.emit(net.local_name(), clean)
	else:
		_say_to_host.rpc_id(1, clean)


# (polish1 item 72) Tells the lobby what we unboxed ("a Legendary ... from a Gold Crate"); the host relays it under our
# roster name. Our own machine shows its line itself.
func announce_unbox(text: String) -> void:
	var clean := ChatCommand.clean(text)
	if clean == "" or not net.can_send():
		return
	if net.is_host():
		_unbox_show.rpc(net.local_name(), clean)
	else:
		_unbox_to_host.rpc_id(1, clean)


@rpc("any_peer", "call_remote", "reliable")
func _unbox_to_host(text: String) -> void:
	if not net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec() / 1000.0
	if not net.roster.has(id) or now - float(_last.get(id, -10.0)) < MIN_GAP:
		return
	_last[id] = now
	var clean := ChatCommand.clean(text)
	_unbox_show.rpc(String(net.roster[id]), clean)
	unboxed.emit(String(net.roster[id]), clean)


@rpc("authority", "call_remote", "reliable")
func _unbox_show(sender: String, text: String) -> void:
	unboxed.emit(sender, ChatCommand.clean(text))


# A client asks the host to run a command that changes the shared world.
func send_command(text: String) -> void:
	if net.can_send() and not net.is_host():
		_command_to_host.rpc_id(1, ChatCommand.clean(text))


func is_op(peer: int) -> bool:
	return peer == 1 or _ops.has(peer)


# Host: /op and /deop. Returns what to tell the host.
func set_op(player_name: String, on: bool) -> String:
	if not net.is_host():
		return "Only the host can do that."
	for id: int in net.roster:
		if String(net.roster[id]).to_lower() == player_name.to_lower() and id != 1:
			if on:
				_ops[id] = true
			else:
				_ops.erase(id)
			_op.rpc_id(id, on)
			return "%s can %s commands." % [net.roster[id], "now use" if on else "no longer use"]
	return "No player called %s." % player_name


@rpc("any_peer", "call_remote", "reliable")
func _say_to_host(text: String) -> void:
	if not net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec() / 1000.0
	if not net.roster.has(id) or now - float(_last.get(id, -10.0)) < MIN_GAP:
		return
	_last[id] = now
	var clean := ChatCommand.clean(text)
	if clean == "" or clean.begins_with("/"):
		return
	_show.rpc(String(net.roster[id]), clean)
	line.emit(String(net.roster[id]), clean)


@rpc("authority", "call_remote", "reliable")
func _show(sender: String, text: String) -> void:
	line.emit(sender, ChatCommand.clean(text))


@rpc("any_peer", "call_remote", "reliable")
func _command_to_host(text: String) -> void:
	if not net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not net.roster.has(id):
		return
	if not is_op(id) or not world_command.is_valid():
		_reply.rpc_id(id, "The host has not allowed you to use commands (/op).")
		return
	for answer: String in world_command.call(id, ChatCommand.clean(text)):
		_reply.rpc_id(id, answer)


@rpc("authority", "call_remote", "reliable")
func _reply(text: String) -> void:
	reply.emit(ChatCommand.clean(text))


@rpc("authority", "call_remote", "reliable")
func _op(on: bool) -> void:
	allowed = on
	op_changed.emit(on)



# --- /tp of other players ---

# An operator (or the host) moves player `who` to `target` (see tp_ordered).
func ask_tp(who: int, target: Dictionary) -> void:
	if net.is_host():
		_tp_check(1, who, target)
	else:
		_tp_ask.rpc_id(1, who, target)


@rpc("any_peer", "call_remote", "reliable")
func _tp_ask(who: int, target: Dictionary) -> void:
	if net.is_host():
		_tp_check(multiplayer.get_remote_sender_id(), who, target)


func _tp_check(from: int, who: int, target: Dictionary) -> void:
	if not is_op(from):
		if from != 1:
			_reply.rpc_id(from, "The host has not allowed you to use commands (/op).")
		return
	if not net.roster.has(who) and who != 1:
		return
	var kind := String(target.get("kind", ""))
	var clean := {}
	if kind == "player" and (net.roster.has(int(target.get("id", -1))) or int(target.get("id", -1)) == 1):
		clean = {"kind": "player", "id": int(target["id"])}
	elif kind == "pos" and target.get("at") is Vector3 and (target["at"] as Vector3).is_finite() and String(target.get("world", "")) in ["sea", "fantasy", "island"]:
		clean = {"kind": "pos", "world": String(target["world"]), "at": target["at"]}
	if clean.is_empty():
		return
	var by := String(net.roster.get(from, "the host"))
	if who == 1:
		tp_ordered.emit(clean, by)
	else:
		_tp_go.rpc_id(who, clean, by)


@rpc("authority", "call_remote", "reliable")
func _tp_go(target: Dictionary, by: String) -> void:
	tp_ordered.emit(target, ChatCommand.clean(by))
