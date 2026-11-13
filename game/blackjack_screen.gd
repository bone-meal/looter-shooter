# Purpose: blackjack overlay panel: chip (bet) buttons + DEAL before a round, HIT / STAND / DOUBLE / SPLIT during it, coins, hand totals and the result text. Collects input only; game/casino_games.gd runs the game and the wallet.
# Dependencies: none.
extends Control

const ChipArt = preload("res://game/chip_art.gd")

signal deal_requested(bet: int)
signal action_requested(action: String)
signal bet_changed(amount: int)  # chip picked before the deal (for the 3D table)
signal closed

const GOLD := Color(1.0, 0.8, 0.25)

var _bets: Array = []
var _bet := 0
var _coins := 0
var _busy := false
var _in_round := false
var _info := Label.new()
var _totals := Label.new()
var _result := Label.new()
var _bet_buttons: Array[Button] = []
var _deal := Button.new()
var _close := Button.new()
var _actions: Dictionary = {}  # "hit" -> Button ...
var _bet_row := HBoxContainer.new()
var _action_row := HBoxContainer.new()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# cfg = the "blackjack" section of data/casino.json
func setup(cfg: Dictionary) -> void:
	_bets = cfg["bets"]
	_bet = int(_bets[0])
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -210
	panel.offset_bottom = -20
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_info.add_theme_font_size_override("font_size", 20)
	v.add_child(ChipArt.row(_info))
	_totals.add_theme_font_size_override("font_size", 18)
	v.add_child(_totals)
	_result.add_theme_font_size_override("font_size", 22)
	_result.add_theme_color_override("font_color", GOLD)
	v.add_child(_result)
	_bet_row.add_theme_constant_override("separation", 6)
	v.add_child(_bet_row)
	var label := Label.new()
	label.text = "Bet:"
	_bet_row.add_child(label)
	for b in _bets:
		var btn := Button.new()
		btn.text = str(int(b))
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(56, 36)
		btn.pressed.connect(_on_bet.bind(int(b)))
		_bet_row.add_child(btn)
		_bet_buttons.append(btn)
	_deal.text = "DEAL"
	_deal.custom_minimum_size = Vector2(120, 36)
	_deal.pressed.connect(_on_deal)
	_bet_row.add_child(_deal)
	_action_row.add_theme_constant_override("separation", 8)
	v.add_child(_action_row)
	for a in ["hit", "stand", "double", "split"]:
		var ab := Button.new()
		ab.text = String(a).to_upper()
		ab.custom_minimum_size = Vector2(110, 44)
		ab.add_theme_font_size_override("font_size", 20)
		ab.pressed.connect(_on_action.bind(String(a)))
		_action_row.add_child(ab)
		_actions[a] = ab
	_close.text = "Leave table (Esc)"
	_close.pressed.connect(close)
	v.add_child(_close)
	_refresh()


func open(coins: int) -> void:
	_coins = coins
	_in_round = false
	_busy = false
	_totals.text = ""
	_result.text = "Pick a bet and press DEAL."
	visible = true
	_refresh()


func close() -> void:
	if _busy or _in_round:
		return
	visible = false
	closed.emit()


func set_busy(busy: bool) -> void:
	_busy = busy
	_refresh()


# options = BlackjackRules.options() while a round is running, {} otherwise.
func show_state(coins: int, in_round: bool, totals: String, message: String, options: Dictionary) -> void:
	_coins = coins
	_in_round = in_round
	_totals.text = totals
	_result.text = message
	for a in _actions:
		(_actions[a] as Button).disabled = _busy or not bool(options.get(a, false))
	_refresh()


func current_bet() -> int:
	return _bet


func _on_bet(b: int) -> void:
	if _busy or _in_round:
		return
	_bet = b
	bet_changed.emit(_bet)
	_refresh()


func _on_deal() -> void:
	if _busy or _in_round or _coins < _bet:
		return
	deal_requested.emit(_bet)


func _on_action(a: String) -> void:
	if _busy or not _in_round:
		return
	action_requested.emit(a)


func _refresh() -> void:
	_info.text = "Chips %d     Bet %d" % [_coins, _bet]
	_bet_row.visible = not _in_round
	_action_row.visible = _in_round
	for i in _bet_buttons.size():
		_bet_buttons[i].button_pressed = int(_bets[i]) == _bet
		_bet_buttons[i].disabled = _busy or int(_bets[i]) > _coins
	_deal.disabled = _busy or _in_round or _coins < _bet
	if not _in_round:
		for a in _actions:
			(_actions[a] as Button).disabled = true
	_close.disabled = _busy or _in_round
