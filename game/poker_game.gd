# Purpose: runs the casino's Texas Hold'em table against the house (polish1 item 167): sitting down (stakes + buy-in
# taken from the wallet), hands one after another with the house players thinking for a moment before each move,
# your moves from the screen, what happened told on the screen and shown on the 3D table, a house player who busts
# replaced by the next with a fresh buy-in, rebuys, and standing up (your table chips back to the wallet; mid-hand you
# fold first). Rules in core/poker_rules.gd, the house in core/poker_ai.gd, numbers in data/poker.json.
# Dependencies: core/poker_rules.gd, core/poker_ai.gd, core/wallet.gd, game/poker_table.gd, game/poker_screen.gd.
extends Node

const Rules = preload("res://core/poker_rules.gd")
const Ai = preload("res://core/poker_ai.gd")
const PokerScreen = preload("res://game/poker_screen.gd")
const DataStore = preload("res://core/data_store.gd")

signal finished  # chips changed: the session saves the profile

const ME := 0

var table: Node3D  # game/poker_table.gd
var screen := PokerScreen.new()
var _wallet: RefCounted
var _player: CharacterBody3D
var _hud: Control
var _rng := RandomNumberGenerator.new()
var _cfg: Dictionary = {}
var _rules: Rules
var _styles: Array = []  # seat -> house style ({} for us)
var _next_house := 0
var _open := false
var _running := false  # a hand is being played out
var _waiting := false  # waiting for our move
var _leaving := false
var _hands_won := 0
var auto_hands := 0  # (dev) the house AI plays our seat for this many hands (tests)


func setup(wallet: RefCounted, poker_table: Node3D, layer: CanvasLayer, player: CharacterBody3D, hud: Control) -> void:
	_wallet = wallet
	table = poker_table
	_player = player
	_hud = hud
	_cfg = DataStore.load_json("res://data/poker.json")
	_rng.randomize()
	screen.cfg = _cfg
	layer.add_child(screen)
	screen.sit_requested.connect(_sit)
	screen.move_requested.connect(_on_move)
	screen.rebuy_requested.connect(_rebuy)
	screen.closed.connect(request_close)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(screen) and screen.get_parent() == null:
		screen.free()


func is_open() -> bool:
	return _open


func near(pos: Vector3) -> bool:
	return table != null and Vector2(pos.x - table.global_position.x, pos.z - table.global_position.z).length() < 2.9


func open() -> void:
	_open = true
	_leaving = false
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var spot: Vector3 = table.to_global(table.call("seat_spot", ME))
	_player.call("teleport", Vector3(spot.x, _player.global_position.y, spot.z), 0.0)
	_player.call("look_at_point", table.global_position + Vector3(0, 0.95, 0))
	screen.open(int(_wallet.get("balance")))


# Esc / Leave: stand up. Mid-hand our cards are folded first; our chips at the table go back to the wallet.
func request_close() -> void:
	if not _open:
		return
	if _rules != null and _running and _rules.in_hand(ME):
		if _rules.current == ME:
			_rules.act(ME, {"do": "fold"})
		else:
			_rules.seats[ME]["folded"] = true
	_leaving = true
	_cash_out()
	_open = false
	_running = false
	_waiting = false
	screen.close_screen()
	table.call("clear")
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	finished.emit()


func _cash_out() -> void:
	if _rules == null:
		return
	var chips := int(_rules.seats[ME]["chips"])
	if chips > 0:
		_wallet.call("add", chips)
		_hud.call("notice", "You stand up from the poker table with %d chips." % chips)
	_rules.seats[ME]["chips"] = 0
	_rules = null


func _sit(stakes: int, buy_in: int) -> void:
	if not _wallet.call("spend", buy_in):
		return
	var st: Dictionary = (_cfg["stakes"] as Array)[stakes]
	_rules = Rules.new()
	_rules.small_blind = int(st["sb"])
	_rules.big_blind = int(st["bb"])
	_rules.add_seat("You", buy_in)
	_styles = [{}]
	var house: Array = _cfg["house"]
	for k in int(_cfg.get("seats", 6)) - 1:
		var h: Dictionary = house[_next_house % house.size()]
		_next_house += 1
		_rules.add_seat(String(h["name"]), _house_buy_in(st))
		_styles.append(h)
	screen.wallet = int(_wallet.get("balance"))
	finished.emit()
	_play.call_deferred()


func _house_buy_in(st: Dictionary) -> int:
	return int(st["bb"]) * _rng.randi_range(int(st["min_bb"]) + 20, int(st["max_bb"]))


func _rebuy() -> void:
	if _rules == null:
		return
	var st := _stake()
	var amount := floori(float(int(st["bb"]) * int(st["max_bb"])) * 0.5)
	if not _wallet.call("spend", amount):
		_hud.call("notice", "Not enough chips to buy in again (%d)." % amount)
		return
	_rules.seats[ME]["chips"] = amount
	_rules.seats[ME]["out"] = false
	screen.wallet = int(_wallet.get("balance"))
	screen.set_busted(false)
	finished.emit()
	_play.call_deferred()


func _stake() -> Dictionary:
	for st: Dictionary in _cfg["stakes"]:
		if int(st["bb"]) == _rules.big_blind:
			return st
	return (_cfg["stakes"] as Array)[0]


# Hands one after another until we stand up or run out of chips.
func _play() -> void:
	if _running or _rules == null:
		return
	_running = true
	while _open and _rules != null and int(_rules.seats[ME]["chips"]) > 0:
		_refill_house()
		if not _rules.start_hand(_rng):
			break
		screen.new_hand()
		_tell()
		_show()
		while _open and _rules != null and _rules.phase != "showdown":
			var who := _rules.current
			if who < 0:
				break
			if who == ME:
				_waiting = true
				_show()
				while _waiting and _open:
					if auto_hands > 0:  # (dev) the house AI plays our seat
						await get_tree().create_timer(0.3).timeout
						if _waiting and _open:
							_on_move(Ai.decide(_rules, ME, (_cfg["house"] as Array)[2], _rng))
						continue
					await get_tree().process_frame
				continue
			var style: Dictionary = _styles[who]
			await get_tree().create_timer(float(style.get("think_s", 1.2)) * _rng.randf_range(0.6, 1.3)).timeout
			if not _open or _rules == null:
				break
			var move := Ai.decide(_rules, who, style, _rng)
			if not _rules.act(who, move):
				_rules.act(who, {"do": "fold"})
			_tell()
			_show()
		if not _open or _rules == null:
			break
		_show()
		_announce()
		auto_hands = maxi(auto_hands - 1, 0)
		await get_tree().create_timer(3.2).timeout
	_running = false
	if _open and _rules != null and int(_rules.seats[ME]["chips"]) <= 0:
		screen.set_busted(true)
		screen.set_banner("Out of chips")


func _on_move(move: Dictionary) -> void:
	if not _waiting or _rules == null or _rules.current != ME:
		return
	if _rules.act(ME, move):
		_waiting = false
		_tell()
		_show()


# A house player with no chips left gets up; the next house player sits down with a fresh buy-in.
func _refill_house() -> void:
	if not bool(_cfg.get("rebuy_house", true)):
		return
	var house: Array = _cfg["house"]
	for i in range(1, _rules.seats.size()):
		if int(_rules.seats[i]["chips"]) <= 0:
			var h: Dictionary = house[_next_house % house.size()]
			_next_house += 1
			_rules.seats[i]["name"] = String(h["name"])
			_rules.seats[i]["chips"] = _house_buy_in(_stake())
			_rules.seats[i]["out"] = false
			_styles[i] = h
			screen.say(i, "sits down", "%s sits down." % String(h["name"]))


func _show() -> void:
	if _rules == null:
		return
	var view := _rules.view(ME)
	screen.wallet = int(_wallet.get("balance"))
	screen.show_hand(view, ME, _rules.legal(ME) if _waiting else {})
	table.call("set_view", view, ME)


# Turns the rules' events into words on the screen.
func _tell() -> void:
	for e: Dictionary in _rules.events:
		var seat := int(e.get("seat", -1))
		match String(e["kind"]):
			"deal":
				screen.say(-1, "", "Hand %d: %s the button." % [_rules.hand_no, _says(int(e["button"]), "has", "have")])
			"blind":
				screen.say(seat, "%s %d" % [String(e["what"]).capitalize(), int(e["amount"])], "")
			"fold":
				screen.say(seat, "Fold", "%s." % _says(seat, "folds", "fold"))
			"check":
				screen.say(seat, "Check", "%s." % _says(seat, "checks", "check"))
			"call":
				screen.say(seat, "Call %d" % int(e["amount"]), "%s %d." % [_says(seat, "calls", "call"), int(e["amount"])])
			"raise":
				screen.say(seat, ("All in %d" if bool(e.get("all_in", false)) else "Raise to %d") % int(e["to"]), "%s %d." % [_says(seat, "goes all in for", "go all in for") if bool(e.get("all_in", false)) else _says(seat, "raises to", "raise to"), int(e["to"])])
			"street":
				for i in _rules.seats.size():
					if _rules.in_hand(i) and not bool(_rules.seats[i]["all_in"]):
						screen.say(i, "", "")
				screen.say(-1, "", "The %s." % String(e["phase"]))
			"win":
				screen.say(seat, "Wins %d" % int(e["amount"]), "%s %d%s." % [_says(seat, "wins", "win"), int(e["amount"]), (" with %s" % String(e["hand"]).to_lower()) if String(e["hand"]) != "" else ""])
	_rules.events.clear()


# "Big Sal folds" / "You fold".
func _says(seat: int, verb_s: String, verb: String) -> String:
	return "You " + verb if seat == ME else "%s %s" % [String(_rules.seats[seat]["name"]), verb_s]


func _announce() -> void:
	var pots: Array = _rules.result.get("pots", [])
	if pots.is_empty():
		return
	var main: Dictionary = pots[0]
	var names: PackedStringArray = []
	for w: int in main["winners"]:
		names.append(String(_rules.seats[w]["name"]))
	if ME in (main["winners"] as Array):
		_hands_won += 1
	screen.set_banner("%s win%s%s" % [" and ".join(names), "" if names.size() > 1 or names[0] == "You" else "s", (" with " + String(main["hand"]).to_lower()) if String(main["hand"]) != "" else ""])


# (dev) One line: stakes, hand, phase, chips at the seats, the pot, our cards and the board.
func note() -> String:
	if _rules == null:
		return "open %s, not seated, wallet %d" % [str(_open), int(_wallet.get("balance"))]
	var chips: PackedStringArray = []
	for s: Dictionary in _rules.seats:
		chips.append("%s %d%s" % [String(s["name"]), int(s["chips"]), " F" if bool(s["folded"]) else ""])
	var mine: PackedStringArray = []
	for c: int in _rules.seats[ME]["cards"]:
		mine.append(Rules.card_name(c))
	var board: PackedStringArray = []
	for c: int in _rules.board:
		board.append(Rules.card_name(c))
	return "blinds %d/%d hand %d %s, current %d, pot %d | %s | mine %s board %s | won %d, wallet %d" % [_rules.small_blind, _rules.big_blind, _rules.hand_no, _rules.phase, _rules.current, _rules.pot(), ", ".join(chips), " ".join(mine), " ".join(board), _hands_won, int(_wallet.get("balance"))]
