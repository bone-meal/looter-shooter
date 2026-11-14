# Purpose: the hub's countdown and ready-up for everyone (locked: diary/DECISIONS_HUB.md). The HOST runs
# core/hub_rules.gd: who is in the hub and on the stage comes from where the players stand (never from what a client
# claims), each player only says whether it holds F and asks to press the button (the host checks it stands at the
# pedestal). The host shows everyone what to see a few times a second and says "go" once: every machine still in
# the hub then leaves for the island. Alone, this machine is the host. Node "Hub" under game/net_session.gd (`hub`).
# /hub (operators) brings a player back: the host opens a new ready-up without a countdown.
# Dependencies: game/net_session.gd (parent; `net`), core/hub_rules.gd, data/hub.json.
extends Node

const HubRules = preload("res://core/hub_rules.gd")

signal view_changed(view: Dictionary)
signal go

var net: Node3D
var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hub.json"))
var rules := HubRules.new(cfg)  # the host's (or ours alone)
var view := {}  # what the host last showed
var center := Vector3.ZERO
var my_pos := Callable()  # func() -> Vector3 our player's world position (set by the session)
var _held := {}  # host: peer -> F held
var _my_held := false
var _send := 0.0
var _was_up := false


func _ready() -> void:
	var c: Array = cfg["center"]
	center = Vector3(float(c[0]), float(c[1]), float(c[2]))


func online() -> bool:
	return net != null and net.can_send()


func deciding() -> bool:
	return not online() or net.is_host()


func me() -> int:
	return net.my_id() if online() else 1


# Is a world point inside the hub (hall or trophy room)?
func inside(at: Vector3) -> bool:
	return rules.inside(at.x - center.x, at.z - center.z) and absf(at.y - center.y) < 40.0


# Our F key on the stage, every frame (only changes are sent).
func hold(down: bool) -> void:
	if down == _my_held:
		return
	_my_held = down
	if deciding():
		_held[me()] = down
	else:
		_held_ask.rpc_id(1, down)


func press_button() -> void:
	if deciding():
		_press(me())
	else:
		_press_ask.rpc_id(1)


# A new game began (Start / Load): a fresh hub with its countdown.
func reset() -> void:
	rules = HubRules.new(cfg)
	_held = {}
	_my_held = false
	view = {}
	_send = 0.0


# /hub: a new ready-up in the hub (no countdown), for whoever stands in it now. A client operator asks the host.
func reopen() -> void:
	if deciding():
		rules = HubRules.new(cfg)
		rules.press_button()
		_send = 0.0
	else:
		_reopen_ask.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _reopen_ask() -> void:
	if deciding() and net.chat.is_op(multiplayer.get_remote_sender_id()):
		reopen()


@rpc("any_peer", "call_remote", "reliable")
func _held_ask(down: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if deciding() and net.roster.has(peer):
		_held[peer] = down


@rpc("any_peer", "call_remote", "reliable")
func _press_ask() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if deciding() and net.roster.has(peer):
		_press(peer)


func _press(peer: int) -> void:
	var at: Variant = _where().get(peer)
	if at == null or rules.button:
		return
	var p: Array = cfg["pedestal"]
	if Vector2((at as Vector3).x - center.x - float(p[0]), (at as Vector3).z - center.z - float(p[1])).length() <= float(cfg["button_reach"]):
		rules.press_button()
		_send = 0.0


func _where() -> Dictionary:
	var out := {}
	if online():
		out = net.positions()
	elif my_pos.is_valid():
		out[1] = my_pos.call()
	return out


func _process(delta: float) -> void:
	var up := online()
	if up != _was_up:  # alone <-> online (or the host changed): the hub starts over for whoever stands in it
		_was_up = up
		rules = HubRules.new(cfg)
		_held = {}
		view = {}
	if not deciding():
		return
	var where := _where()
	for peer: int in where:
		var at: Vector3 = where[peer]
		if inside(at):
			rules.join(peer)
			rules.set_stage(peer, rules.on_stage(at.x - center.x, at.z - center.z) and at.y - center.y > float(cfg["stage_height"]) - 0.25)
		else:
			rules.leave(peer)
	for peer: int in rules.players.keys():
		if not where.has(peer):
			rules.leave(peer)
	var going := rules.tick(delta, _held)
	_send -= delta
	if _send <= 0.0 or going:
		_send = 0.2
		view = rules.view()
		view["open"] = not rules.launched
		view_changed.emit(view)
		if up:
			_view.rpc(view)
	if going:
		go.emit()
		if up:
			_go.rpc()


@rpc("authority", "call_remote", "unreliable_ordered")
func _view(v: Dictionary) -> void:
	view = v
	view_changed.emit(v)


@rpc("authority", "call_remote", "reliable")
func _go() -> void:
	go.emit()
