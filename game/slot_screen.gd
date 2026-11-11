# Purpose: the slot machine overlay panel: coins, jackpot pot, bet per line buttons (total cost shown), SPIN, paytable, last result, Close. Only collects input and shows numbers; game_session runs the spin and the wallet.
# Dependencies: game/symbol_art.gd (paytable icons), data/slots.json passed in via setup().
extends Control

const SymbolArt = preload("res://game/symbol_art.gd")

signal spin_requested(bet_per_line: int)
signal closed

const GOLD := Color(1.0, 0.8, 0.25)

var _bets: Array = []
var _pays: Dictionary = {}
var _lines := 5
var _bet := 1
var _coins := 0
var _pot := 0.0
var _busy := false
var _message := ""
var _bet_buttons: Array[Button] = []
var _spin_button := Button.new()
var _close_button := Button.new()
var _info := Label.new()
var _result := Label.new()
var _font: Font = ThemeDB.fallback_font
var _pay_box := Control.new()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# data = parsed data/slots.json
func setup(data: Dictionary) -> void:
	_bets = data["bets"]
	_pays = data["pays"]
	_lines = (data["lines"] as Array).size()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -190
	panel.offset_bottom = -20
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_info.add_theme_font_size_override("font_size", 20)
	v.add_child(_info)
	_result.add_theme_font_size_override("font_size", 22)
	_result.add_theme_color_override("font_color", GOLD)
	v.add_child(_result)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var label := Label.new()
	label.text = "Bet per line:"
	row.add_child(label)
	for b in _bets:
		var btn := Button.new()
		btn.text = str(int(b))
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(52, 36)
		btn.pressed.connect(_on_bet.bind(int(b)))
		row.add_child(btn)
		_bet_buttons.append(btn)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	v.add_child(row2)
	_spin_button.text = "SPIN"
	_spin_button.custom_minimum_size = Vector2(200, 48)
	_spin_button.add_theme_font_size_override("font_size", 24)
	_spin_button.pressed.connect(_on_spin)
	row2.add_child(_spin_button)
	_close_button.text = "Leave machine (Esc)"
	_close_button.custom_minimum_size = Vector2(180, 48)
	_close_button.pressed.connect(close)
	row2.add_child(_close_button)
	_pay_box.custom_minimum_size = Vector2(0, 0)
	add_child(_pay_box)
	_pay_box.draw.connect(_draw_paytable)
	_pay_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pay_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


func open(coins: int, pot: float) -> void:
	_coins = coins
	_pot = pot
	_message = "Pick a bet and press SPIN."
	_busy = false
	visible = true
	if _bets.size() > 0 and _bet > int(_bets[_bets.size() - 1]):
		_bet = int(_bets[0])
	_refresh()


func close() -> void:
	if _busy:
		return
	visible = false
	closed.emit()


# Called by the session around a spin.
func set_busy(busy: bool) -> void:
	_busy = busy
	_refresh()


func show_state(coins: int, pot: float, message: String) -> void:
	_coins = coins
	_pot = pot
	_message = message
	_refresh()


func cost() -> int:
	return _bet * _lines


func _on_bet(b: int) -> void:
	if _busy:
		return
	_bet = b
	_refresh()


func _on_spin() -> void:
	if _busy or _coins < cost():
		return
	spin_requested.emit(_bet)


func _refresh() -> void:
	_info.text = "Coins %d     Jackpot pot %d     Cost %d (%d lines x %d)" % [_coins, floori(_pot), cost(), _lines, _bet]
	_result.text = _message
	for i in _bet_buttons.size():
		_bet_buttons[i].button_pressed = int(_bets[i]) == _bet
		_bet_buttons[i].disabled = _busy
	_spin_button.disabled = _busy or _coins < cost()
	_close_button.disabled = _busy
	_pay_box.queue_redraw()


# Small paytable at the top right: icon and multiplier of the bet per line (3 on a line).
func _draw_paytable() -> void:
	if not visible:
		return
	var view := get_viewport_rect().size
	var x0 := view.x - 190.0
	var y0 := 90.0
	_pay_box.draw_rect(Rect2(x0 - 10, y0 - 30, 190, 24 + 40 * 8 + 10), Color(0, 0, 0, 0.55))
	_pay_box.draw_string(_font, Vector2(x0, y0 - 10), "3 on a line pays", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))
	var tex := SymbolArt.atlas()
	var order: Array[String] = ["jackpot", "seven", "wild", "bar", "bell", "plum", "lemon", "cherry"]
	for i in order.size():
		var id := order[i]
		var y := y0 + float(i) * 40.0
		_pay_box.draw_texture_rect_region(tex, Rect2(x0, y, 64, 38), SymbolArt.pixel_rect(id))
		var text := "x%d" % int(_pays[id])
		if id == "jackpot":
			text = "POT (max bet)"
		_pay_box.draw_string(_font, Vector2(x0 + 74, y + 26), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)
