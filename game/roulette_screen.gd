# Purpose: roulette overlay panel: chip picker, the number grid (0-36), dozens, columns, red/black, odd/even, low/high, CLEAR / UNDO / SPIN, total staked and the result text. Collects input only; game/casino_games.gd spins and pays.
# Dependencies: core/roulette_rules.gd (colours and bet keys).
extends Control

const ChipArt = preload("res://game/chip_art.gd")

const Roulette = preload("res://core/roulette_rules.gd")

signal spin_requested(bets: Dictionary)
signal bets_changed(bets: Dictionary)  # the chips now on the table (for the 3D felt)
signal closed

const GOLD := Color(1.0, 0.8, 0.25)

var _chips: Array = []
var _chip := 1
var _table_max := 500
var _coins := 0
var _busy := false
var _bets: Dictionary = {}  # bet key -> coins
var _order: Array = []  # [key, amount] in the order chips were placed (for UNDO)
var _buttons: Dictionary = {}  # key -> Button
var _captions: Dictionary = {}  # key -> base caption
var _chip_buttons: Array[Button] = []
var _info := Label.new()
var _result := Label.new()
var _spin := Button.new()
var _clear := Button.new()
var _undo := Button.new()
var _close := Button.new()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# cfg = the "roulette" section of data/casino.json
func setup(cfg: Dictionary) -> void:
	_chips = cfg["chips"]
	_chip = int(_chips[0])
	_table_max = int(cfg["table_max"])
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -330
	panel.offset_bottom = -12
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	panel.add_child(v)
	_info.add_theme_font_size_override("font_size", 18)
	v.add_child(ChipArt.row(_info))
	_result.add_theme_font_size_override("font_size", 22)
	_result.add_theme_color_override("font_color", GOLD)
	v.add_child(_result)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 6)
	v.add_child(chip_row)
	var cl := Label.new()
	cl.text = "Chip:"
	chip_row.add_child(cl)
	for c in _chips:
		var btn := Button.new()
		btn.text = str(int(c))
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(52, 32)
		btn.pressed.connect(_on_chip.bind(int(c)))
		chip_row.add_child(btn)
		_chip_buttons.append(btn)
	# number grid: a zero button, then three rows of twelve (top row 3,6,..,36)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 3)
	v.add_child(grid)
	grid.add_child(_bet_button("straight:0", "0", Color(0.1, 0.55, 0.2), Vector2(40, 100)))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	grid.add_child(rows)
	for r in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		rows.add_child(row)
		for c in 12:
			var n := c * 3 + (3 - r)
			var color := Color(0.75, 0.08, 0.1) if Roulette.is_red(n) else Color(0.1, 0.1, 0.13)
			row.add_child(_bet_button("straight:%d" % n, str(n), color, Vector2(44, 32)))
		row.add_child(_bet_button("column:%d" % (3 - r), "2:1", Color(0.2, 0.3, 0.4), Vector2(44, 32)))
	var dozens := HBoxContainer.new()
	dozens.add_theme_constant_override("separation", 3)
	v.add_child(dozens)
	for i in 3:
		dozens.add_child(_bet_button("dozen:%d" % (i + 1), ["1st 12", "2nd 12", "3rd 12"][i], Color(0.2, 0.3, 0.4), Vector2(150, 30)))
	var outside := HBoxContainer.new()
	outside.add_theme_constant_override("separation", 3)
	v.add_child(outside)
	outside.add_child(_bet_button("low", "1-18", Color(0.2, 0.3, 0.4), Vector2(98, 30)))
	outside.add_child(_bet_button("even", "EVEN", Color(0.2, 0.3, 0.4), Vector2(98, 30)))
	outside.add_child(_bet_button("red", "RED", Color(0.75, 0.08, 0.1), Vector2(98, 30)))
	outside.add_child(_bet_button("black", "BLACK", Color(0.1, 0.1, 0.13), Vector2(98, 30)))
	outside.add_child(_bet_button("odd", "ODD", Color(0.2, 0.3, 0.4), Vector2(98, 30)))
	outside.add_child(_bet_button("high", "19-36", Color(0.2, 0.3, 0.4), Vector2(98, 30)))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	_spin.text = "SPIN"
	_spin.custom_minimum_size = Vector2(140, 38)
	_spin.add_theme_font_size_override("font_size", 20)
	_spin.pressed.connect(_on_spin)
	actions.add_child(_spin)
	_undo.text = "Undo"
	_undo.pressed.connect(_on_undo)
	actions.add_child(_undo)
	_clear.text = "Clear bets"
	_clear.pressed.connect(_on_clear)
	actions.add_child(_clear)
	_close.text = "Leave table (Esc)"
	_close.pressed.connect(close)
	actions.add_child(_close)
	_refresh()


func _bet_button(key: String, caption: String, color: Color, box: Vector2) -> Button:
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size = box
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.5)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.25)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(_on_bet.bind(key))
	_buttons[key] = b
	_captions[key] = caption
	return b


func open(coins: int) -> void:
	_coins = coins
	_busy = false
	_result.text = "Pick a chip, click the layout to bet, then SPIN."
	visible = true
	_refresh()


func close() -> void:
	if _busy:
		return
	visible = false
	closed.emit()


func set_busy(busy: bool) -> void:
	_busy = busy
	_refresh()


func show_state(coins: int, message: String) -> void:
	_coins = coins
	_result.text = message
	_refresh()


func current_bets() -> Dictionary:
	return _bets


func total_bet() -> int:
	var t := 0
	for k: String in _bets:
		t += int(_bets[k])
	return t


func _on_chip(c: int) -> void:
	_chip = c
	_refresh()


func _on_bet(key: String) -> void:
	if _busy:
		return
	if total_bet() + _chip > mini(_coins, _table_max):
		_result.text = "Not enough chips or table limit (%d) reached." % _table_max
		return
	_bets[key] = int(_bets.get(key, 0)) + _chip
	_order.append([key, _chip])
	bets_changed.emit(_bets)
	_refresh()


func _on_undo() -> void:
	if _busy or _order.is_empty():
		return
	var last: Array = _order.pop_back()
	var key := String(last[0])
	_bets[key] = int(_bets[key]) - int(last[1])
	if int(_bets[key]) <= 0:
		_bets.erase(key)
	bets_changed.emit(_bets)
	_refresh()


func _on_clear() -> void:
	if _busy:
		return
	_bets.clear()
	_order.clear()
	bets_changed.emit(_bets)
	_refresh()


func _on_spin() -> void:
	if _busy or _bets.is_empty() or total_bet() > _coins:
		return
	spin_requested.emit(_bets.duplicate())


func _refresh() -> void:
	_info.text = "Chips %d     On the table %d (max %d)" % [_coins, total_bet(), _table_max]
	for i in _chip_buttons.size():
		_chip_buttons[i].button_pressed = int(_chips[i]) == _chip
		_chip_buttons[i].disabled = _busy
	for key: String in _buttons:
		var b: Button = _buttons[key]
		var amount := int(_bets.get(key, 0))
		b.text = String(_captions[key]) if amount == 0 else "%s\n[%d]" % [_captions[key], amount]
		b.disabled = _busy
	_spin.disabled = _busy or _bets.is_empty() or total_bet() > _coins
	_undo.disabled = _busy or _order.is_empty()
	_clear.disabled = _busy or _bets.is_empty()
	_close.disabled = _busy
