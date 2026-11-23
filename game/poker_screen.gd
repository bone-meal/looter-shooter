# Purpose: the poker table's screen (polish1 item 167, real game UI: game/ui_skin.gd). Before sitting: the stakes
# (blinds) and the buy-in. At the table: the felt with every seat round it (name, chips, bet, what they just did, their
# two cards: yours face up, the others' backs until the showdown, the dealer button, the one to act lit gold), the
# five community cards and the pot in the middle, your best hand named, the last moves; on your turn FOLD, CHECK /
# CALL, and a RAISE with its amount (- / +, MIN, 1/2 POT, POT, ALL IN); between hands REBUY if you are out; Leave
# (stands up and cashes your chips out; mid-hand it folds first). Collects input only; game/poker_game.gd runs it.
# Dependencies: game/ui_skin.gd, game/chip_art.gd, core/poker_rules.gd (hand names).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const ChipArt = preload("res://game/chip_art.gd")
const Rules = preload("res://core/poker_rules.gd")

signal sit_requested(stakes: int, buy_in: int)
signal move_requested(move: Dictionary)
signal rebuy_requested
signal closed

const GOLD := Color(1.0, 0.8, 0.25)
const FELT := Color(0.04, 0.27, 0.16)
const PANEL := Vector2(1180, 560)
const CARD := Vector2(52, 74)
const BIG := Vector2(64, 90)
const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]

var cfg: Dictionary = {}  # data/poker.json
var wallet := 0  # chips in the wallet (not at the table)
var _seated := false
var _stakes := 0
var _buy_frac := 0.5
var _view: Dictionary = {}
var _me := 0
var _legal: Dictionary = {}
var _raise_to := 0
var _said: Dictionary = {}  # seat -> what it last did ("Raise 60", "Fold" ...)
var _log: PackedStringArray = []
var _banner := ""
var _busted := false
var _hits: Array = []
var _mouse := Vector2(-1, -1)
var _font: Font = ThemeDB.fallback_font
var _t := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -PANEL.x * 0.5
	offset_right = PANEL.x * 0.5
	offset_top = -PANEL.y - 100.0
	offset_bottom = -100.0


func open(coins: int) -> void:
	wallet = coins
	_seated = false
	_view = {}
	_said = {}
	_log = PackedStringArray()
	_banner = ""
	_busted = false
	visible = true
	queue_redraw()


func close_screen() -> void:
	visible = false


# The hand as we may see it (core/poker_rules.gd view()), our seat, what we may do now ({} = not our turn).
func show_hand(view: Dictionary, me: int, legal: Dictionary) -> void:
	_seated = true
	_view = view
	_me = me
	_legal = legal
	if not legal.is_empty():
		_raise_to = clampi(_raise_to, int(legal["min_to"]), int(legal["max_to"]))
		if _raise_to < int(legal["min_to"]) or _raise_to > int(legal["max_to"]) or _raise_to == 0:
			_raise_to = int(legal["min_to"])
	queue_redraw()


func say(seat: int, words: String, line: String) -> void:
	if seat >= 0:
		_said[seat] = words
	if line != "":
		_log.append(line)
		if _log.size() > 4:
			_log.remove_at(0)
	queue_redraw()


func new_hand() -> void:
	_said = {}
	_banner = ""
	queue_redraw()


func set_banner(text: String) -> void:
	_banner = text
	queue_redraw()


func set_busted(on: bool) -> void:
	_busted = on
	queue_redraw()


# Checks: press a control by key ("stakes 1", "buyin max", "sit", "fold", "call", "check", "raise", "min", "half",
# "pot", "allin", "more", "less", "rebuy", "leave").
func press(key: String) -> bool:
	for hit: Array in _hits:
		if String(hit[2]) == key:
			(hit[1] as Callable).call()
			queue_redraw()
			return true
	return false


func _process(delta: float) -> void:
	if visible:
		_t += delta
		if not _legal.is_empty():
			queue_redraw()  # the gold pulse on our seat


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		queue_redraw()
	var b := event as InputEventMouseButton
	if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
		for hit: Array in _hits:
			if (hit[0] as Rect2).has_point(b.position):
				(hit[1] as Callable).call()
				break
		accept_event()
		queue_redraw()


func _button(r: Rect2, label: String, key: String, enabled: bool, act: Callable, big: bool = false) -> void:
	var over := r.has_point(_mouse) and enabled
	UiSkin.pill(self, _font, r, label, big and enabled, over, 22 if big else 16)
	if enabled:
		_hits.append([r, act, key])
	else:
		draw_style_box(UiSkin._box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), int(r.size.y * 0.5), 0), r)


func _stake() -> Dictionary:
	return (cfg.get("stakes", [{}]) as Array)[_stakes]


func _buy_in() -> int:
	var s := _stake()
	var lo := int(s.get("min_bb", 20)) * int(s.get("bb", 10))
	var hi := int(s.get("max_bb", 100)) * int(s.get("bb", 10))
	return clampi(int(lerpf(float(lo), float(hi), _buy_frac) / float(s.get("bb", 10))) * int(s.get("bb", 10)), lo, hi)


func _draw() -> void:
	_hits.clear()
	UiSkin.panel(self, Rect2(Vector2.ZERO, PANEL))
	ChipArt.draw_value(self, Vector2(40, 38), 16.0, 25)
	draw_string(_font, Vector2(64, 47), "%d in the wallet" % wallet, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiSkin.TEXT)
	var s := _stake()
	draw_string(_font, Vector2(PANEL.x * 0.5, 46), "TEXAS HOLD'EM   %s   %d / %d" % [String(s.get("name", "")).to_upper(), int(s.get("sb", 5)), int(s.get("bb", 10))], HORIZONTAL_ALIGNMENT_CENTER, -1, 20, GOLD)
	_button(Rect2(Vector2(PANEL.x - 250.0, 18), Vector2(228, 40)), "Stand up (Esc)" if _seated else "Leave (Esc)", "leave", true, func() -> void: closed.emit())
	if not _seated:
		_draw_pick()
		return
	var felt := Rect2(Vector2(22, 70), Vector2(PANEL.x - 44.0, 350))
	draw_style_box(UiSkin._box(FELT, Color(GOLD, 0.5), 170, 2), felt)
	_draw_middle(felt)
	var seats: Array = _view.get("seats", [])
	for i in seats.size():
		_draw_seat(i, seats[i], felt)
	_draw_bar(Rect2(Vector2(22, felt.end.y + 8.0), Vector2(PANEL.x - 44.0, PANEL.y - felt.end.y - 20.0)))


func _draw_pick() -> void:
	draw_string(_font, Vector2(40, 110), "STAKES", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT_DIM)
	var stakes: Array = cfg.get("stakes", [])
	for i in stakes.size():
		var st: Dictionary = stakes[i]
		var r := Rect2(Vector2(40.0 + float(i) * 300.0, 124), Vector2(280, 70))
		var on := i == _stakes
		draw_style_box(UiSkin._box(Color(0.06, 0.08, 0.1, 0.95) if not on else Color(0.18, 0.14, 0.05, 0.95), GOLD if on else UiSkin.EDGE, 12, 2), r)
		draw_string(_font, r.position + Vector2(16, 30), String(st["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD if on else UiSkin.TEXT)
		draw_string(_font, r.position + Vector2(16, 56), "blinds %d / %d   buy-in %d - %d" % [int(st["sb"]), int(st["bb"]), int(st["min_bb"]) * int(st["bb"]), int(st["max_bb"]) * int(st["bb"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
		_hits.append([r, func() -> void: _stakes = i, "stakes %d" % i])
	draw_string(_font, Vector2(40, 240), "BUY-IN", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT_DIM)
	var marks := [["min", 0.0], ["half", 0.5], ["max", 1.0]]
	for k in marks.size():
		var f := float(marks[k][1])
		_button(Rect2(Vector2(40.0 + float(k) * 150.0, 254), Vector2(136, 44)), String(marks[k][0]).to_upper(), "buyin %s" % marks[k][0], true, func() -> void: _buy_frac = f, is_equal_approx(f, _buy_frac))
	ChipArt.draw_value(self, Vector2(540, 276), 20.0, _buy_in(), _font)
	draw_string(_font, Vector2(570, 286), "%d chips" % _buy_in(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GOLD)
	draw_string(_font, Vector2(40, 350), "Five house players sit with you. Chips you win go back to your wallet when you stand up.", HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 80.0, 16, UiSkin.TEXT_DIM)
	var can := wallet >= _buy_in()
	_button(Rect2(Vector2(PANEL.x - 360.0, PANEL.y - 96.0), Vector2(320, 64)), "SIT DOWN" if can else "Not enough chips", "sit", can, func() -> void: sit_requested.emit(_stakes, _buy_in()), true)


func _draw_middle(felt: Rect2) -> void:
	var c := felt.get_center() + Vector2(0, -6)
	var board: Array = _view.get("board", [])
	for k in 5:
		var r := Rect2(c + Vector2(-2.5 * (BIG.x + 8.0) + float(k) * (BIG.x + 8.0) + 4.0, -BIG.y * 0.5 - 6.0), BIG)
		if k < board.size():
			_card(r, int(board[k]), false)
		else:
			draw_style_box(UiSkin._box(Color(0, 0, 0, 0.18), Color(1, 1, 1, 0.12), 8, 1), r)
	var pot := int(_view.get("pot", 0))
	if pot > 0:
		ChipArt.draw_value(self, c + Vector2(-60, BIG.y * 0.5 + 26.0), 13.0, pot, null)
		draw_string(_font, c + Vector2(-40, BIG.y * 0.5 + 33.0), "POT %d" % pot, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD)
	if _banner != "":
		draw_string_outline(_font, c + Vector2(0, -BIG.y * 0.5 - 22.0), _banner, HORIZONTAL_ALIGNMENT_CENTER, felt.size.x * 0.6, 26, 7, Color(0, 0, 0, 0.85))
		draw_string(_font, c + Vector2(0, -BIG.y * 0.5 - 22.0), _banner, HORIZONTAL_ALIGNMENT_CENTER, felt.size.x * 0.6, 26, GOLD)


# Seat boxes round the oval: ours at the bottom middle, the rest round the sides and the top (the dealer's side).
func _seat_at(i: int, n: int, felt: Rect2) -> Vector2:
	var order := [90.0, 148.0, 32.0, 206.0, 334.0, 250.0]
	var a := deg_to_rad(float(order[i % order.size()]) if n <= order.size() else 90.0 + 360.0 * float(i) / float(n))
	return felt.get_center() + Vector2(cos(a) * felt.size.x * 0.4, sin(a) * felt.size.y * 0.4)


func _draw_seat(i: int, s: Dictionary, felt: Rect2) -> void:
	var at := _seat_at(i, (_view.get("seats", []) as Array).size(), felt)
	var r := Rect2(at - Vector2(92, 36), Vector2(184, 72))
	var acting := int(_view.get("current", -1)) == i
	var dim := bool(s.get("folded", false)) or bool(s.get("out", false))
	var edge := GOLD if acting else (Color(0.5, 0.9, 1.0) if i == _me else UiSkin.EDGE)
	if acting:
		draw_style_box(UiSkin._box(Color(0, 0, 0, 0), Color(GOLD, 0.25 + 0.25 * sin(_t * 6.0)), 14, 6), r.grow(4.0))
	draw_style_box(UiSkin._box(Color(0.03, 0.04, 0.06, 0.55 if dim else 0.92), edge, 12, 2), r)
	var tint := Color(1, 1, 1, 0.45 if dim else 1.0)
	draw_string(_font, r.position + Vector2(10, 22), String(s.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 120, 15, UiSkin.TEXT * tint)
	draw_string(_font, r.position + Vector2(10, 44), "%d" % int(s.get("chips", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD * tint)
	var said := String(_said.get(i, ""))
	if bool(s.get("all_in", false)):
		said = "ALL IN"
	elif bool(s.get("out", false)):
		said = "out"
	draw_string(_font, r.position + Vector2(10, 64), said, HORIZONTAL_ALIGNMENT_LEFT, 110, 13, (UiSkin.BAD if said == "Fold" else UiSkin.TEXT_DIM))
	var cards: Array = s.get("cards", [])
	if not bool(s.get("folded", false)):
		for k in cards.size():
			var cr := Rect2(r.position + Vector2(r.size.x - 66.0 + float(k) * 22.0, 8.0), CARD * 0.78)
			if i == _me:
				cr = Rect2(r.position + Vector2(r.size.x + 6.0 + float(k) * (CARD.x + 4.0), -2.0), CARD)
			_card(cr, int(cards[k]), int(cards[k]) < 0)
	var bet := int(s.get("bet", 0))
	if bet > 0:
		var toward := (felt.get_center() - at).normalized()
		var bp := at + toward * (absf(toward.x) * 112.0 + absf(toward.y) * 56.0)  # just past the seat box's edge, toward the pot
		ChipArt.draw_value(self, bp, 11.0, bet, null)
		draw_string(_font, bp + Vector2(15, 6), "%d" % bet, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT)
	if int(_view.get("button", -1)) == i:
		var dp := r.position + Vector2(-12, 12)
		draw_circle(dp, 11.0, Color(0.96, 0.95, 0.9))
		draw_string(_font, dp + Vector2(-5, 6), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.05, 0.05, 0.08))


func _draw_bar(bar: Rect2) -> void:
	var mine: Dictionary = (_view.get("seats", []) as Array)[_me] if _me < (_view.get("seats", []) as Array).size() else {}
	var cards: Array = mine.get("cards", [])
	var board: Array = _view.get("board", [])
	var hand := ""
	if cards.size() == 2 and int(cards[0]) >= 0 and not bool(mine.get("folded", false)):
		if board.size() >= 3:
			hand = Rules.hand_name(Rules.score(cards + board))
		else:
			hand = "Pocket pair" if int(cards[0]) % 13 == int(cards[1]) % 13 else "%s-%s%s" % [RANKS[int(cards[0]) % 13], RANKS[int(cards[1]) % 13], " suited" if floori(int(cards[0]) / 13.0) == floori(int(cards[1]) / 13.0) else ""]
	draw_string(_font, bar.position + Vector2(4, 22), ("You have: " + hand) if hand != "" else "", HORIZONTAL_ALIGNMENT_LEFT, 360, 18, Color(0.6, 0.95, 1.0))
	for k in _log.size():
		draw_string(_font, bar.position + Vector2(380, 18 + 17 * k), _log[k], HORIZONTAL_ALIGNMENT_LEFT, 420, 14, UiSkin.TEXT_DIM if k < _log.size() - 1 else UiSkin.TEXT)
	var by := bar.end.y - 58.0
	if _busted:
		_button(Rect2(Vector2(bar.position.x, by), Vector2(260, 54)), "REBUY", "rebuy", true, func() -> void: rebuy_requested.emit(), true)
		draw_string(_font, Vector2(bar.position.x + 280, by + 34), "You are out of chips at this table.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiSkin.TEXT_DIM)
		return
	if _legal.is_empty():
		draw_string(_font, Vector2(bar.position.x, by + 34), "Waiting..." if int(_view.get("current", -1)) >= 0 else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiSkin.TEXT_DIM)
		return
	var owe := int(_legal["call"])
	_button(Rect2(Vector2(bar.position.x, by), Vector2(150, 54)), "FOLD", "fold", bool(_legal["fold"]), func() -> void: move_requested.emit({"do": "fold"}), true)
	if owe > 0:
		_button(Rect2(Vector2(bar.position.x + 162, by), Vector2(200, 54)), "CALL %d" % owe, "call", true, func() -> void: move_requested.emit({"do": "call"}), true)
	else:
		_button(Rect2(Vector2(bar.position.x + 162, by), Vector2(200, 54)), "CHECK", "check", true, func() -> void: move_requested.emit({"do": "check"}), true)
	if not bool(_legal["can_raise"]):
		return
	var lo := int(_legal["min_to"])
	var hi := int(_legal["max_to"])
	var bb := int(_view.get("bb", 10))
	var pot := int(_view.get("pot", 0))
	var x := bar.position.x + 380.0
	_button(Rect2(Vector2(x, by + 8), Vector2(38, 38)), "-", "less", _raise_to > lo, func() -> void: _raise_to = maxi(lo, _raise_to - bb))
	draw_string(_font, Vector2(x + 44, by + 36), "%d" % _raise_to, HORIZONTAL_ALIGNMENT_CENTER, 80, 20, GOLD)
	_button(Rect2(Vector2(x + 128, by + 8), Vector2(38, 38)), "+", "more", _raise_to < hi, func() -> void: _raise_to = mini(hi, _raise_to + bb))
	var presets := [["MIN", "min", lo], ["1/2 POT", "half", int(_view.get("to_call", 0)) + int(float(pot + owe) * 0.5)], ["POT", "pot", int(_view.get("to_call", 0)) + pot + owe], ["ALL IN", "allin", hi]]
	for k in presets.size():
		var v := clampi(int(presets[k][2]), lo, hi)
		_button(Rect2(Vector2(x + 178 + float(k) * 92.0, by + 8), Vector2(86, 38)), String(presets[k][0]), String(presets[k][1]), true, func() -> void: _raise_to = v)
	var label := ("ALL IN %d" % hi) if _raise_to >= hi else ("RAISE TO %d" % _raise_to if int(_view.get("to_call", 0)) > 0 else "BET %d" % _raise_to)
	_button(Rect2(Vector2(bar.end.x - 220.0, by), Vector2(220, 54)), label, "raise", true, func() -> void: move_requested.emit({"do": "allin"} if _raise_to >= hi else {"do": "raise", "to": _raise_to}), true)


# A playing card: white face, rank and suit; down = the casino's back.
func _card(r: Rect2, card: int, down: bool) -> void:
	draw_style_box(UiSkin._box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 7, 0), Rect2(r.position + Vector2(2, 3), r.size))
	if down:
		draw_style_box(UiSkin._box(Color(0.12, 0.16, 0.45), Color(0.96, 0.94, 0.9), 6, 2), r)
		draw_style_box(UiSkin._box(Color(0, 0, 0, 0), Color(1.0, 0.8, 0.35, 0.55), 4, 1), r.grow(-5.0))
		return
	draw_style_box(UiSkin._box(Color(0.98, 0.97, 0.94), Color(0.25, 0.25, 0.28), 6, 1), r)
	var suit := floori(card / 13.0)
	var red := suit == 1 or suit == 2
	var ink := Color(0.78, 0.08, 0.12) if red else Color(0.08, 0.08, 0.1)
	var px := clampi(int(r.size.y * 0.28), 12, 26)
	draw_string(_font, r.position + Vector2(5, px + 2), RANKS[card % 13], HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
	_suit(r.get_center() + Vector2(0, r.size.y * 0.12), r.size.x * 0.22, suit, ink)


# A suit drawn as shapes (core/poker_rules.gd order: 0 clubs, 1 diamonds, 2 hearts, 3 spades).
func _suit(c: Vector2, s: float, suit: int, ink: Color) -> void:
	match suit:
		2:  # heart
			draw_circle(c + Vector2(-s * 0.48, -s * 0.25), s * 0.52, ink)
			draw_circle(c + Vector2(s * 0.48, -s * 0.25), s * 0.52, ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.98, -s * 0.08), c + Vector2(s * 0.98, -s * 0.08), c + Vector2(0, s * 0.95)]), ink)
		1:  # diamond
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.72, 0), c + Vector2(0, s), c + Vector2(-s * 0.72, 0)]), ink)
		3:  # spade
			draw_circle(c + Vector2(-s * 0.45, s * 0.12), s * 0.48, ink)
			draw_circle(c + Vector2(s * 0.45, s * 0.12), s * 0.48, ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.92, s * 0.1), c + Vector2(-s * 0.92, s * 0.1)]), ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.2), c + Vector2(s * 0.35, s), c + Vector2(-s * 0.35, s)]), ink)
		_:  # club
			draw_circle(c + Vector2(0, -s * 0.45), s * 0.42, ink)
			draw_circle(c + Vector2(-s * 0.48, s * 0.12), s * 0.42, ink)
			draw_circle(c + Vector2(s * 0.48, s * 0.12), s * 0.42, ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.1), c + Vector2(s * 0.3, s), c + Vector2(-s * 0.3, s)]), ink)
