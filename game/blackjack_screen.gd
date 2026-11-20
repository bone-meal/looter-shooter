# Purpose: the blackjack table's screen (polish1 item 74, real game UI: game/ui_skin.gd): chips and the bet as a chip
# stack, the hand totals large, the dealer's words, a row of real chips to pick the bet + DEAL before a round, HIT /
# STAND / DOUBLE / SPLIT as big buttons during it, Leave inside the panel. Collects input only;
# game/casino_games.gd runs the game and the wallet.
# Dependencies: game/chip_art.gd, game/ui_skin.gd.
extends Control

const ChipArt = preload("res://game/chip_art.gd")
const UiSkin = preload("res://game/ui_skin.gd")

signal deal_requested(bet: int)
signal action_requested(action: String)
signal bet_changed(amount: int)  # chip picked before the deal (for the 3D table)
signal closed

const GOLD := Color(1.0, 0.8, 0.25)
const PANEL := Vector2(900, 270)
const ACTIONS := ["hit", "stand", "double", "split"]

var _bets: Array = []
var _bet := 0
var _coins := 0
var _busy := false
var _in_round := false
var _totals := ""
var _message := ""
var _options: Dictionary = {}
var _hits: Array = []  # [Rect2, Callable, key]
var _mouse := Vector2(-1, -1)
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -PANEL.x * 0.5
	offset_right = PANEL.x * 0.5
	offset_top = -PANEL.y - 14.0
	offset_bottom = -14.0


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
	UiSkin.pill(self, _font, r, label, big and enabled, over, 24 if big else 15)
	if enabled:
		_hits.append([r, act, key])
	else:
		draw_style_box(UiSkin._box(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), int(r.size.y * 0.5), 0), r)


func _draw() -> void:
	_hits.clear()
	UiSkin.panel(self, Rect2(Vector2.ZERO, PANEL))
	ChipArt.draw_value(self, Vector2(40, 38), 15.0, 25)
	draw_string(_font, Vector2(64, 46), "%d" % _coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiSkin.TEXT)
	draw_string(_font, Vector2(170, 46), "BET", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
	ChipArt.draw_stack(self, Vector2(222, 40), 15.0, _bet, _bets, _font)
	draw_string(_font, Vector2(24, 96), _totals, HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 48.0, 26, UiSkin.TEXT)
	draw_string(_font, Vector2(24, 134), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 48.0, 21, GOLD)
	var by := PANEL.y - 104.0
	if not _in_round:
		draw_string(_font, Vector2(24, by + 6.0), "YOUR BET", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.ACCENT)
		for i in _bets.size():
			var v := int(_bets[i])
			var at := Vector2(52.0 + float(i) * 70.0, by + 46.0)
			var on := v == _bet
			if on:
				draw_circle(at, 31.0, Color(GOLD, 0.35))
			var can := not _busy and v <= _coins
			ChipArt.draw_value(self, at - Vector2(0, 4.0 if on else 0.0), 26.0 if on else 24.0, v, _font)
			if not can:
				draw_circle(at, 25.0, Color(0, 0, 0, 0.5))
			else:
				_hits.append([Rect2(at - Vector2(28, 28), Vector2(56, 56)), _on_bet.bind(v), "bet %d" % v])
		_button(Rect2(Vector2(PANEL.x - 300.0, by + 20.0), Vector2(270, 54)), "DEAL", "deal", not _busy and _coins >= _bet, _on_deal, true)
	else:
		var w := (PANEL.x - 48.0 - 3.0 * 14.0) / 4.0
		for i in ACTIONS.size():
			var a: String = ACTIONS[i]
			var r := Rect2(Vector2(24.0 + float(i) * (w + 14.0), by + 14.0), Vector2(w, 58))
			_button(r, a.to_upper(), a, not _busy and bool(_options.get(a, false)), _on_action.bind(a), true)
	_button(Rect2(Vector2(PANEL.x - 230.0, 18), Vector2(206, 38)), "Leave table (Esc)", "leave", not _busy and not _in_round, close)
