# Purpose: the casino's Texas Hold'em table for this player (polish1 item 167): walking up (the screen), sitting down
# (stakes + buy-in taken from the wallet), the hands as this machine sees them on the screen and the 3D table, our
# moves, rebuys, standing up (the table chips back to the wallet). Alone a dealer here deals against the house players
# (game/poker_dealer.gd); in a lobby the host deals one shared table (game/net_poker.gd) where players sit with house
# players (a player's seat hides that chair's house player). Everyone near the table sees it played.
# Dependencies: game/poker_dealer.gd, game/net_poker.gd (link), core/poker_rules.gd (hand names), core/wallet.gd,
# game/poker_table.gd, game/poker_screen.gd, game/player.gd (teleport, look_at_point, controls_enabled), game/player_hud.gd.
extends Node

const Rules = preload("res://core/poker_rules.gd")
const Dealer = preload("res://game/poker_dealer.gd")
const PokerScreen = preload("res://game/poker_screen.gd")
const DataStore = preload("res://core/data_store.gd")

signal finished  # chips changed: the session saves the profile

const SOLO := 1  # our owner id at the dealer here

var table: Node3D  # game/poker_table.gd
var screen := PokerScreen.new()
var link: Node  # game/net_poker.gd (in a lobby)
var _people: Array = []  # seat -> the seated house player model (null for the empty chair)
var _wallet: RefCounted
var _player: CharacterBody3D
var _hud: Control
var _cfg: Dictionary = {}
var _dealer := Dealer.new()
var _net := false  # this sitting is at the lobby's table
var _open := false
var _view: Dictionary = {}  # the table as we see it now
var _seat := -1  # our seat (-1 = not seated)
var _told_hand := -1  # the hand whose winner the banner shows
var _hands_won := 0
var _bot := 0  # (dev) online on a guest: calls / checks for us this many hands


func setup(wallet: RefCounted, poker_table: Node3D, layer: CanvasLayer, player: CharacterBody3D, hud: Control, people: Array = []) -> void:
	_wallet = wallet
	table = poker_table
	_player = player
	_hud = hud
	_people = people
	_cfg = DataStore.load_json("res://data/poker.json")
	screen.cfg = _cfg
	layer.add_child(screen)
	screen.sit_requested.connect(_sit)
	screen.move_requested.connect(_on_move)
	screen.rebuy_requested.connect(_rebuy)
	screen.closed.connect(request_close)
	_dealer.cfg = _cfg
	add_child(_dealer)
	_dealer.changed.connect(func(events: Array) -> void:
		if not _net:
			var seat := _dealer.seat_of(SOLO)
			_apply(_dealer.view_for(seat), seat, false, events))
	_dealer.paid.connect(func(_o: int, chips: int) -> void: _paid(chips))


func set_link(net_poker: Node) -> void:
	link = net_poker
	link.connect("view_changed", func(v: Dictionary, seat: int, queued: bool, events: Array) -> void:
		if _net or _seat < 0:
			_apply(v, seat, queued, events))
	link.connect("paid_out", _paid)
	link.connect("refused", func(text: String, refund: int) -> void:
		_wallet.call("add", refund)
		_hud.call("notice", text)
		screen.wallet = int(_wallet.get("balance"))
		screen.set_note(text)
		finished.emit())
	link.connect("table_lost", func(chips: int) -> void:
		_wallet.call("add", chips)
		_hud.call("notice", "The host left: your %d table chips are back in your wallet." % chips)
		_net = false
		if _open:
			_leave_table_view()
		finished.emit())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(screen) and screen.get_parent() == null:
		screen.free()


func _online() -> bool:
	return link != null and bool(link.call("online"))


func is_open() -> bool:
	return _open


func near(pos: Vector3) -> bool:
	return table != null and Vector2(pos.x - table.global_position.x, pos.z - table.global_position.z).length() < 2.9


func open() -> void:
	_open = true
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screen.open(int(_wallet.get("balance")))
	if _online():
		var v: Dictionary = link.get("last_view")
		var players := 0
		for h: bool in v.get("human", []):
			players += 1 if h else 0
		screen.lock_stakes(int(v.get("stakes", -1)) if not v.is_empty() else -1)
		screen.set_note("The lobby's table: you sit with %s." % ("the house players" if players == 0 else "%d player%s and the house players" % [players, "" if players == 1 else "s"]))
		_go_to_seat(_free_chair(v))
	else:
		screen.lock_stakes(-1)
		screen.set_note("Five house players sit with you. Chips you win go back to your wallet when you stand up.")
		_go_to_seat(0)


# The chair we would get (for standing there while choosing): the empty chair, else the first house player's.
func _free_chair(v: Dictionary) -> int:
	var human: Array = v.get("human", [])
	for i in human.size():
		if not bool(human[i]):
			return i
	return 0


func _go_to_seat(seat: int) -> void:
	var spot: Vector3 = table.to_global(table.call("seat_spot", seat) * (1.0 if seat == 0 else 1.25))
	_player.call("teleport", Vector3(spot.x, _player.global_position.y, spot.z), 0.0)
	_player.call("look_at_point", table.global_position + Vector3(0, 0.95, 0))


# Esc / Stand up: our chips at the table come back (the dealer pays them); mid-hand our cards fold.
func request_close() -> void:
	if not _open:
		return
	if _seat >= 0 or (_net and bool(_view.get("_queued", false))):
		if _net:
			link.call("ask_leave")
		else:
			_dealer.leave(SOLO)
	elif _net:
		link.call("ask_leave")  # (a sit still on its way: the host gives it back)
	_leave_table_view()
	finished.emit()


func _leave_table_view() -> void:
	_open = false
	_seat = -1
	screen.close_screen()
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not _net:
		table.call("clear")
		_view = {}
		_show_people([])


func _paid(chips: int) -> void:
	if chips <= 0:
		return
	_wallet.call("add", chips)
	_hud.call("notice", "%d chips from the poker table go back to your wallet." % chips)
	screen.wallet = int(_wallet.get("balance"))
	finished.emit()


func _sit(stakes: int, buy_in: int) -> void:
	if not _wallet.call("spend", buy_in):
		return
	screen.wallet = int(_wallet.get("balance"))
	finished.emit()
	if _online():
		_net = true
		screen.set_note("Taking a seat...")
		link.call("ask_sit", stakes, buy_in)
		return
	_net = false
	var why := _dealer.sit(SOLO, "You", stakes, buy_in)
	if why != "":
		_wallet.call("add", buy_in)
		screen.set_note(why)


func _rebuy() -> void:
	var st: Dictionary = (_cfg["stakes"] as Array)[maxi(int(_view.get("stakes", 0)), 0)]
	var amount := floori(float(int(st["bb"]) * int(st["max_bb"])) * 0.5)
	if not _wallet.call("spend", amount):
		_hud.call("notice", "Not enough chips to buy in again (%d)." % amount)
		return
	screen.wallet = int(_wallet.get("balance"))
	finished.emit()
	if _net:
		link.call("ask_rebuy", amount)
		return
	var why := _dealer.rebuy(SOLO, amount)
	if why != "":
		_wallet.call("add", amount)
		_hud.call("notice", why)


func _on_move(mv: Dictionary) -> void:
	if _net:
		link.call("ask_move", mv)
	else:
		_dealer.move(SOLO, mv)


# The table moved on: the 3D table (everyone), the house players in their chairs, and our screen when we are at it.
func _apply(v: Dictionary, seat: int, queued: bool, events: Array) -> void:
	_view = v
	_view["_queued"] = queued
	if v.is_empty() or v.get("seats", []).is_empty():
		table.call("clear")
		_show_people([])
		if _open and _seat >= 0:  # the table closed under us
			_seat = -1
			screen.open(int(_wallet.get("balance")))
		return
	table.call("set_view", v, seat)
	_show_people(v.get("human", []))
	if not _open:
		return
	var was := _seat
	_seat = seat
	if seat < 0:
		if queued:
			screen.set_note("You sit down when this hand ends...")
		return
	if was != seat:
		_go_to_seat(seat)
	screen.wallet = int(_wallet.get("balance"))
	if int(v.get("hand_no", 0)) != _told_hand and String(v.get("phase", "")) == "preflop":
		screen.new_hand()
	_tell(events, v, seat)
	screen.show_hand(v, seat, v.get("legal", {}))
	if _bot > 0 and not (v.get("legal", {}) as Dictionary).is_empty():
		var owe := int((v["legal"] as Dictionary)["call"])
		get_tree().create_timer(0.4).timeout.connect(func() -> void: _on_move({"do": "call" if owe > 0 else "check"}))
	var mine: Dictionary = (v["seats"] as Array)[seat]
	var between := String(v.get("phase", "")) in ["idle", "showdown"]
	screen.set_busted(int(mine["chips"]) <= 0 and between)
	if String(v.get("phase", "")) == "showdown" and int(v.get("hand_no", 0)) != _told_hand:
		_told_hand = int(v.get("hand_no", 0))
		_announce(v, seat)
		_bot = maxi(_bot - 1, 0)


# A player in a chair hides the house player who sat there (online).
func _show_people(human: Array) -> void:
	for i in _people.size():
		var p: Node3D = _people[i]
		if p != null and is_instance_valid(p):
			p.visible = not (i < human.size() and bool(human[i]))


# Turns the table's events into words on the screen ("You" for our seat).
func _tell(events: Array, v: Dictionary, me: int) -> void:
	var seats: Array = v.get("seats", [])
	for e: Dictionary in events:
		var seat := int(e.get("seat", -1))
		match String(e.get("kind", "")):
			"deal":
				screen.say(-1, "", "Hand %d: %s the button." % [int(v.get("hand_no", 0)), _says(seats, me, int(e["button"]), "has", "have")])
			"blind":
				screen.say(seat, "%s %d" % [String(e["what"]).capitalize(), int(e["amount"])], "")
			"fold":
				screen.say(seat, "Fold", "%s." % _says(seats, me, seat, "folds", "fold"))
			"check":
				screen.say(seat, "Check", "%s." % _says(seats, me, seat, "checks", "check"))
			"call":
				screen.say(seat, "Call %d" % int(e["amount"]), "%s %d." % [_says(seats, me, seat, "calls", "call"), int(e["amount"])])
			"raise":
				screen.say(seat, ("All in %d" if bool(e.get("all_in", false)) else "Raise to %d") % int(e["to"]), "%s %d." % [_says(seats, me, seat, "goes all in for", "go all in for") if bool(e.get("all_in", false)) else _says(seats, me, seat, "raises to", "raise to"), int(e["to"])])
			"street":
				for i in seats.size():
					var s: Dictionary = seats[i]
					if not bool(s["folded"]) and not bool(s["out"]) and not bool(s["all_in"]):
						screen.say(i, "", "")
				screen.say(-1, "", "The %s." % String(e["phase"]))
			"win":
				screen.say(seat, "Wins %d" % int(e["amount"]), "%s %d%s." % [_says(seats, me, seat, "wins", "win"), int(e["amount"]), (" with %s" % String(e["hand"]).to_lower()) if String(e["hand"]) != "" else ""])
			"sit":
				if seat != me:
					screen.say(seat, "sits down", "%s sits down." % String(e["name"]))
			"leave":
				screen.say(seat, "stood up", "%s stands up." % String(e["name"]))
			"clock":
				screen.say(seat, "Out of time", "%s out of time." % ("You are" if seat == me else "%s is" % _name(seats, seat)))


func _name(seats: Array, seat: int) -> String:
	return String((seats[seat] as Dictionary)["name"]) if seat >= 0 and seat < seats.size() else "?"


# "Big Sal folds" / "You fold".
func _says(seats: Array, me: int, seat: int, verb_s: String, verb: String) -> String:
	return "You " + verb if seat == me else "%s %s" % [_name(seats, seat), verb_s]


func _announce(v: Dictionary, me: int) -> void:
	var pots: Array = (v.get("result", {}) as Dictionary).get("pots", [])
	if pots.is_empty():
		return
	var main: Dictionary = pots[0]
	var names: PackedStringArray = []
	var mine := false
	for w: int in main["winners"]:
		if w == me:
			mine = true
			names.append("You")
		else:
			names.append(_name(v["seats"], w))
	if mine:
		_hands_won += 1
	screen.set_banner("%s win%s%s" % [" and ".join(names), "" if names.size() > 1 or mine else "s", (" with " + String(main["hand"]).to_lower()) if String(main["hand"]) != "" else ""])


# (dev) The house AI plays our seat for n hands (alone, or online on the host's own seat; a guest calls / checks).
func set_auto(hands: int) -> void:
	if _net:
		var d: Node = link.call("dealer")
		if d != null:
			(d.get("auto") as Dictionary)[1] = hands
		else:
			_bot = hands
	else:
		_dealer.auto[SOLO] = hands


# (dev) One line: stakes, hand, phase, chips at the seats, the pot, our cards and the board.
func note() -> String:
	if _view.is_empty() or _view.get("seats", []).is_empty():
		return "open %s, not seated, online %s, wallet %d" % [str(_open), str(_net), int(_wallet.get("balance"))]
	var chips: PackedStringArray = []
	for s: Dictionary in _view["seats"]:
		chips.append("%s %d%s" % [String(s["name"]), int(s["chips"]), " F" if bool(s["folded"]) else ""])
	var mine: PackedStringArray = []
	if _seat >= 0:
		for c: int in (_view["seats"] as Array)[_seat]["cards"]:
			mine.append(Rules.card_name(c))
	var board: PackedStringArray = []
	for c: int in _view.get("board", []):
		board.append(Rules.card_name(c))
	return "%s blinds %d/%d hand %d %s, current %d, seat %d, pot %d | %s | mine %s board %s | won %d, wallet %d" % ["online" if _net else "solo", int(_view["sb"]), int(_view["bb"]), int(_view["hand_no"]), String(_view["phase"]), int(_view["current"]), _seat, int(_view["pot"]), ", ".join(chips), " ".join(mine), " ".join(board), _hands_won, int(_wallet.get("balance"))]
