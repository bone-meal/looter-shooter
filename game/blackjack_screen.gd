# Purpose: the blackjack table's screen (polish1 items 73-74, real game UI: game/ui_skin.gd). A felt panel that shows
# the dealer's cards and yours as real card faces (dealt in step with the table), each hand's total in a badge (the
# hand in play lit gold), the dealer's words, your chips and the bet as a chip stack with its amount; before a round a
# row of real chips to pick the bet + DEAL, during it HIT / STAND / DOUBLE / SPLIT as big buttons; Leave in the
# corner. Collects input only; game/casino_games.gd runs the game and the wallet.
# Dependencies: game/chip_art.gd, game/ui_skin.gd, core/blackjack_rules.gd (card ranks and totals).
extends Control

const ChipArt = preload("res://game/chip_art.gd")
const UiSkin = preload("res://game/ui_skin.gd")
const Blackjack = preload("res://core/blackjack_rules.gd")

signal deal_requested(bet: int)
signal action_requested(action: String)
signal bet_changed(amount: int)  # chip picked before the deal (for the 3D table)
signal closed

const GOLD := Color(1.0, 0.8, 0.25)
const FELT := Color(0.05, 0.3, 0.15)
const PANEL := Vector2(1040, 470)
const CARD := Vector2(74, 104)
const ACTIONS := ["hit", "stand", "double", "split"]
const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

var _bets: Array = []
var _bet := 0
var _coins := 0
var _busy := false
var _in_round := false
var _totals := ""
var _message := ""
var _options: Dictionary = {}
var _dealer: Array[int] = []  # the dealer's cards on the table so far
var _hole := false  # the dealer's second card is still face down
var _hands: Array = []  # Array[int] per hand on the table so far
var _active := 0
var _hits: Array = []  # [Rect2, Callable, key]
var _mouse := Vector2(-1, -1)
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -PANEL.x * 0.5
	offset_right = PANEL.x * 0.5
	offset_top = -PANEL.y - 110.0  # clear of the HUD's bottom bar
	offset_bottom = -110.0


# cfg = the "blackjack" section of data/casino.json
func setup(cfg: Dictionary) -> void:
	_bets = cfg["bets"]
	_bet = int(_bets[0])


func open(coins: int) -> void:
	_coins = coins
	_in_round = false
	_busy = false
	_totals = ""
	_message = "Pick a bet and press DEAL."
	_dealer.clear()
	_hands.clear()
	visible = true
	queue_redraw()


func close() -> void:
	if _busy or _in_round:
		return
	visible = false
	closed.emit()


func set_busy(busy: bool) -> void:
	_busy = busy
	queue_redraw()


# options = BlackjackRules.options() while a round is running, {} otherwise.
func show_state(coins: int, in_round: bool, totals: String, message: String, options: Dictionary) -> void:
	_coins = coins
	_in_round = in_round
	_totals = totals
	_message = message
	_options = options
	queue_redraw()


# The cards on the table right now (game/casino_games.gd calls this as it deals): dealer's, whether the hole card is
# still down, the player's hands and which one is in play.
func show_hands(dealer: Array[int], hole_down: bool, hands: Array, active: int) -> void:
	_dealer = dealer
	_hole = hole_down
	_hands = hands
	_active = active
	queue_redraw()


func current_bet() -> int:
	return _bet


# Checks: press a control by key ("deal", "hit", "stand", "double", "split", "leave", "bet 25").
func press(key: String) -> bool:
	for hit: Array in _hits:
		if String(hit[2]) == key:
			(hit[1] as Callable).call()
			queue_redraw()
			return true
	return false


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


func _on_bet(b: int) -> void:
	if _busy or _in_round:
		return
	_bet = b
	bet_changed.emit(_bet)


func _on_deal() -> void:
	if _busy or _in_round or _coins < _bet:
		return
	deal_requested.emit(_bet)


func _on_action(a: String) -> void:
	if _busy or not _in_round or not bool(_options.get(a, false)):
		return
	action_requested.emit(a)


func _button(r: Rect2, label: String, key: String, enabled: bool, act: Callable, big: bool = false) -> void:
	var over := r.has_point(_mouse) and enabled
	UiSkin.pill(self, _font, r, label, big and enabled, over, 26 if big else 17)
	if enabled:
		_hits.append([r, act, key])
	else:
		draw_style_box(UiSkin._box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), int(r.size.y * 0.5), 0), r)


func _draw() -> void:
	_hits.clear()
	UiSkin.panel(self, Rect2(Vector2.ZERO, PANEL))
	# top line: chips, the bet, Leave
	ChipArt.draw_value(self, Vector2(42, 40), 17.0, 25)
	draw_string(_font, Vector2(68, 50), "%d" % _coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UiSkin.TEXT)
	draw_string(_font, Vector2(230, 50), "BET", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT_DIM)
	ChipArt.draw_value(self, Vector2(290, 42), 17.0, _bet, _font)
	draw_string(_font, Vector2(316, 50), "%d" % _bet, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GOLD)
	_button(Rect2(Vector2(PANEL.x - 250.0, 20), Vector2(226, 42)), "Leave table (Esc)", "leave", not _busy and not _in_round, close)
	# the felt with both rows of cards
	var felt := Rect2(Vector2(24, 76), Vector2(PANEL.x - 48.0, 254))
	draw_style_box(UiSkin._box(FELT, Color(GOLD, 0.55), 14, 2), felt)
	_row(Vector2(felt.position.x + 20.0, felt.position.y + 12.0), "DEALER", [_dealer], 0 if not _hole else -1, true)
	_row(Vector2(felt.position.x + 20.0, felt.position.y + 132.0), "YOU", _hands, _active if _in_round else -1, false)
	if not _in_round and not _hands.is_empty():  # the round's outcome, large on the felt
		var verdict := _message.split("     ")[0]
		draw_string_outline(_font, Vector2(felt.position.x + felt.size.x * 0.5, felt.position.y + felt.size.y * 0.5 + 16.0), verdict, HORIZONTAL_ALIGNMENT_CENTER, felt.size.x * 0.5 - 20.0, 40, 8, Color(0, 0, 0, 0.85))
		draw_string(_font, Vector2(felt.position.x + felt.size.x * 0.5, felt.position.y + felt.size.y * 0.5 + 16.0), verdict, HORIZONTAL_ALIGNMENT_CENTER, felt.size.x * 0.5 - 20.0, 40, GOLD)
	draw_string(_font, Vector2(24, felt.end.y + 34.0), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 48.0, 24, GOLD)
	# controls
	var by := PANEL.y - 78.0
	if not _in_round:
		for i in _bets.size():
			var v := int(_bets[i])
			var at := Vector2(56.0 + float(i) * 78.0, by + 30.0)
			var on := v == _bet
			var can := not _busy and v <= _coins
			if on:
				draw_circle(at, 34.0, Color(GOLD, 0.45))
				draw_arc(at, 34.0, 0.0, TAU, 32, GOLD, 3.0, true)
			ChipArt.draw_value(self, at - Vector2(0, 5.0 if on else 0.0), 28.0 if on else 26.0, v, _font)
			if not can:
				draw_circle(at, 27.0, Color(0, 0, 0, 0.55))
			else:
				_hits.append([Rect2(at - Vector2(30, 30), Vector2(60, 60)), _on_bet.bind(v), "bet %d" % v])
		_button(Rect2(Vector2(PANEL.x - 324.0, by + 2.0), Vector2(300, 60)), "DEAL", "deal", not _busy and _coins >= _bet, _on_deal, true)
	else:
		var w := (PANEL.x - 48.0 - 3.0 * 16.0) / 4.0
		for i in ACTIONS.size():
			var a: String = ACTIONS[i]
			_button(Rect2(Vector2(24.0 + float(i) * (w + 16.0), by + 2.0), Vector2(w, 60)), a.to_upper(), a, not _busy and bool(_options.get(a, false)), _on_action.bind(a), true)


# One row of hands: its label, each hand's cards side by side with its total in a badge; `lit` = the hand in play
# (-1 none); `dealer` = the second card may be face down.
func _row(at: Vector2, label: String, hands: Array, lit: int, dealer: bool) -> void:
	draw_string(_font, at + Vector2(0, 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.75))
	var x := at.x + 96.0
	for h in hands.size():
		var cards: Array = hands[h]
		if cards.is_empty():
			continue
		var shown: Array[int] = []
		for i in cards.size():
			var down := dealer and _hole and i == 1
			_card(Rect2(Vector2(x + float(i) * (CARD.x * 0.62), at.y), CARD), int(cards[i]), down)
			if not down:
				shown.append(int(cards[i]))
		var badge_x := x + float(cards.size() - 1) * CARD.x * 0.62 + CARD.x + 10.0
		var value := Blackjack.evaluate(shown)
		var total := int(value["total"])
		var soft := bool(value["soft"]) and total < 21 and not dealer and _in_round and h == lit  # "7 / 17" only while you still choose
		var text := "%d / %d" % [total - 10, total] if soft else "%d" % total
		var colour := UiSkin.BAD if total > 21 else (GOLD if (h == lit and not dealer) else Color(1, 1, 1, 0.9))
		var badge := Rect2(Vector2(badge_x, at.y + CARD.y * 0.5 - 20.0), Vector2(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 24.0, 40))
		draw_style_box(UiSkin._box(Color(0, 0, 0, 0.6), colour, 20, 2), badge)
		draw_string(_font, badge.position + Vector2(12, 28), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, colour)
		if h == lit and not dealer and hands.size() > 1:
			draw_string(_font, Vector2(x, at.y - 2.0), "IN PLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD)
		x = badge.end.x + 40.0


# A playing card: white face, rank and suit in the corners and big in the middle; face down = the casino's back.
func _card(r: Rect2, card: int, down: bool) -> void:
	draw_style_box(UiSkin._box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 9, 0), Rect2(r.position + Vector2(3, 4), r.size))
	if down:
		draw_style_box(UiSkin._box(Color(0.55, 0.08, 0.14), Color(0.96, 0.94, 0.9), 8, 3), r)
		draw_style_box(UiSkin._box(Color(0, 0, 0, 0), Color(1.0, 0.8, 0.35, 0.6), 5, 1), r.grow(-8.0))
		ChipArt.draw_value(self, r.get_center(), 14.0, 25)
		return
	draw_style_box(UiSkin._box(Color(0.98, 0.97, 0.94), Color(0.25, 0.25, 0.28), 8, 1), r)
	var suit := Blackjack.suit_of(card)
	var red := suit == 1 or suit == 2
	var ink := Color(0.78, 0.08, 0.12) if red else Color(0.08, 0.08, 0.1)
	var rank: String = RANKS[Blackjack.rank_of(card)]
	draw_string(_font, r.position + Vector2(7, 22), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	_suit(r.position + Vector2(15, 34), 7.0, suit, ink)
	_suit(r.get_center() + Vector2(0, 8), 17.0, suit, ink)


# A suit drawn as shapes (0 spades, 1 hearts, 2 diamonds, 3 clubs).
func _suit(c: Vector2, s: float, suit: int, ink: Color) -> void:
	match suit:
		1:  # heart
			draw_circle(c + Vector2(-s * 0.48, -s * 0.25), s * 0.52, ink)
			draw_circle(c + Vector2(s * 0.48, -s * 0.25), s * 0.52, ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.98, -s * 0.08), c + Vector2(s * 0.98, -s * 0.08), c + Vector2(0, s * 0.95)]), ink)
		2:  # diamond
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.72, 0), c + Vector2(0, s), c + Vector2(-s * 0.72, 0)]), ink)
		0:  # spade
			draw_circle(c + Vector2(-s * 0.45, s * 0.12), s * 0.48, ink)
			draw_circle(c + Vector2(s * 0.45, s * 0.12), s * 0.48, ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.92, s * 0.1), c + Vector2(-s * 0.92, s * 0.1)]), ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.2), c + Vector2(s * 0.35, s), c + Vector2(-s * 0.35, s)]), ink)
		_:  # club
			draw_circle(c + Vector2(0, -s * 0.45), s * 0.42, ink)
			draw_circle(c + Vector2(-s * 0.48, s * 0.12), s * 0.42, ink)
			draw_circle(c + Vector2(s * 0.48, s * 0.12), s * 0.42, ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0), c + Vector2(s * 0.3, s), c + Vector2(-s * 0.3, s)]), ink)
