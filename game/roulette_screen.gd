# Purpose: the roulette table's screen (polish1 items 73-74, real game UI: game/ui_skin.gd): a felt betting layout
# (0, the 3 x 12 numbers, columns 2:1, dozens, 1-18 / even / red / black / odd / 19-36) where every bet shows its chip
# stack, the cell under the mouse lights up with every number it covers, a chip picker of real chips, the last numbers,
# SPIN / Undo / Clear / Leave inside the panel (it grows up from the bottom edge). Collects input only;
# game/casino_games.gd spins and pays.
# Dependencies: core/roulette_rules.gd (colours and bet keys), game/chip_art.gd, game/ui_skin.gd.
extends Control

const ChipArt = preload("res://game/chip_art.gd")
const UiSkin = preload("res://game/ui_skin.gd")
const Roulette = preload("res://core/roulette_rules.gd")

signal spin_requested(bets: Dictionary)
signal bets_changed(bets: Dictionary)  # the chips now on the table (for the 3D felt)
signal closed

const GOLD := Color(1.0, 0.8, 0.25)
const FELT := Color(0.05, 0.32, 0.16)
const RED := Color(0.72, 0.08, 0.1)
const BLACK := Color(0.08, 0.08, 0.1)
const ZERO := Color(0.1, 0.55, 0.2)
const PANEL := Vector2(1180, 470)
const CELL := Vector2(66, 54)

var _chips: Array = []
var _chip := 1
var _table_max := 500
var _coins := 0
var _busy := false
var _bets: Dictionary = {}  # bet key -> coins
var _order: Array = []  # [key, amount] in the order chips were placed (for UNDO)
var _message := ""
var _history: Array[int] = []  # last numbers, newest first
var _cells: Array = []  # [Rect2, key, caption, colour] of the layout, in local coordinates
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


# cfg = the "roulette" section of data/casino.json
func setup(cfg: Dictionary) -> void:
	_chips = cfg["chips"]
	_chip = int(_chips[0])
	_table_max = int(cfg["table_max"])
	_layout()


# The layout's cells: zero on the left, three rows of twelve (top row 3, 6 .. 36), the columns' 2:1 on the right,
# the dozens and the even-money bets under them.
func _layout() -> void:
	_cells.clear()
	var o := Vector2(44, 128)
	_cells.append([Rect2(o, Vector2(CELL.x, CELL.y * 3.0)), "straight:0", "0", ZERO])
	for r in 3:
		for c in 12:
			var n := c * 3 + (3 - r)
			_cells.append([Rect2(o + Vector2(CELL.x * float(c + 1), CELL.y * float(r)), CELL), "straight:%d" % n, str(n), RED if Roulette.is_red(n) else BLACK])
		_cells.append([Rect2(o + Vector2(CELL.x * 13.0, CELL.y * float(r)), CELL), "column:%d" % (3 - r), "2:1", FELT])
	var y := o.y + CELL.y * 3.0
	for i in 3:
		_cells.append([Rect2(Vector2(o.x + CELL.x * (1.0 + 4.0 * float(i)), y), Vector2(CELL.x * 4.0, 46)), "dozen:%d" % (i + 1), ["1st 12", "2nd 12", "3rd 12"][i], FELT])
	var outs := [["low", "1-18", FELT], ["even", "EVEN", FELT], ["red", "RED", RED], ["black", "BLACK", BLACK], ["odd", "ODD", FELT], ["high", "19-36", FELT]]
	for i in outs.size():
		_cells.append([Rect2(Vector2(o.x + CELL.x * (1.0 + 2.0 * float(i)), y + 46.0), Vector2(CELL.x * 2.0, 46)), outs[i][0], outs[i][1], outs[i][2]])


func open(coins: int) -> void:
	_coins = coins
	_busy = false
	_message = "Pick a chip, click the layout to bet, then SPIN."
	visible = true
	queue_redraw()


func close() -> void:
	if _busy:
		return
	visible = false
	closed.emit()


func set_busy(busy: bool) -> void:
	_busy = busy
	queue_redraw()


# `number` >= 0 = the wheel just stopped there (added to the last numbers).
func show_state(coins: int, message: String, number: int = -1) -> void:
	_coins = coins
	_message = message
	if number >= 0:
		_history.push_front(number)
		_history.resize(mini(_history.size(), 12))
	queue_redraw()


func current_bets() -> Dictionary:
	return _bets


func total_bet() -> int:
	var t := 0
	for k: String in _bets:
		t += int(_bets[k])
	return t


# Checks: press a control by key ("spin", "undo", "clear", "leave", "chip 25", "bet red", "bet straight:17").
func press(key: String) -> bool:
	queue_redraw()
	if key.begins_with("bet "):
		_on_bet(key.trim_prefix("bet "))
		return true
	for hit: Array in _hits:
		if String(hit[2]) == key:
			(hit[1] as Callable).call()
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		queue_redraw()
	var b := event as InputEventMouseButton
	if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
		var done := false
		for hit: Array in _hits:
			if (hit[0] as Rect2).has_point(b.position):
				(hit[1] as Callable).call()
				done = true
				break
		if not done:
			for cell: Array in _cells:
				if (cell[0] as Rect2).has_point(b.position):
					_on_bet(String(cell[1]))
					break
		accept_event()
		queue_redraw()
	elif b != null and b.pressed and b.button_index == MOUSE_BUTTON_RIGHT:  # right click takes the last chip back
		_on_undo()
		accept_event()


func _on_chip(c: int) -> void:
	_chip = c


func _on_bet(key: String) -> void:
	if _busy:
		return
	if total_bet() + _chip > mini(_coins, _table_max):
		_message = "Not enough chips or table limit (%d) reached." % _table_max
		return
	_bets[key] = int(_bets.get(key, 0)) + _chip
	_order.append([key, _chip])
	bets_changed.emit(_bets)


func _on_undo() -> void:
	if _busy or _order.is_empty():
		return
	var last: Array = _order.pop_back()
	var key := String(last[0])
	_bets[key] = int(_bets[key]) - int(last[1])
	if int(_bets[key]) <= 0:
		_bets.erase(key)
	bets_changed.emit(_bets)


func _on_clear() -> void:
	if _busy:
		return
	_bets.clear()
	_order.clear()
	bets_changed.emit(_bets)


func _on_spin() -> void:
	if _busy or _bets.is_empty() or total_bet() > _coins:
		return
	spin_requested.emit(_bets.duplicate())


func _button(r: Rect2, label: String, key: String, enabled: bool, act: Callable, big: bool = false) -> void:
	var over := r.has_point(_mouse)
	UiSkin.pill(self, _font, r, label, big and enabled, over and enabled, 22 if big else 15)
	if not enabled:
		draw_style_box(_dim(), r)
	else:
		_hits.append([r, act, key])


static var _dim_box: StyleBoxFlat
func _dim() -> StyleBoxFlat:
	if _dim_box == null:
		_dim_box = StyleBoxFlat.new()
		_dim_box.bg_color = Color(0, 0, 0, 0.45)
		_dim_box.set_corner_radius_all(20)
	return _dim_box


func _draw() -> void:
	_hits.clear()
	UiSkin.panel(self, Rect2(Vector2.ZERO, PANEL))
	# money and message
	ChipArt.draw_value(self, Vector2(40, 36), 15.0, 25)
	draw_string(_font, Vector2(64, 44), "%d" % _coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiSkin.TEXT)
	draw_string(_font, Vector2(170, 44), "on the table %d / %d" % [total_bet(), _table_max], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT_DIM)
	draw_string(_font, Vector2(24, 86), _message, HORIZONTAL_ALIGNMENT_LEFT, 700, 22, GOLD)
	# last numbers, newest left
	draw_string(_font, Vector2(760, 30), "LAST NUMBERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiSkin.TEXT_DIM)
	for i in _history.size():
		var n := _history[i]
		var c := ZERO if n == 0 else (RED if Roulette.is_red(n) else BLACK)
		var dot := Vector2(774.0 + float(i) * 32.0, 56.0)
		draw_circle(dot, 14.0 if i == 0 else 12.0, c)
		draw_arc(dot, 14.0 if i == 0 else 12.0, 0.0, TAU, 20, GOLD if i == 0 else Color(1, 1, 1, 0.3), 2.0, true)
		draw_string(_font, dot + Vector2(-14, 5), str(n), HORIZONTAL_ALIGNMENT_CENTER, 28, 13, Color.WHITE)
	# the felt and its cells
	var felt := Rect2(Vector2(30, 116), Vector2(CELL.x * 14.0 + 28.0, CELL.y * 3.0 + 92.0 + 24.0))
	draw_style_box(UiSkin._box(FELT, Color(GOLD, 0.6), 14, 2), felt)
	var hovered := ""
	for cell: Array in _cells:
		if (cell[0] as Rect2).has_point(_mouse) and not _busy:
			hovered = String(cell[1])
	var covered: Array[int] = []
	if hovered != "":
		covered = Roulette.numbers_of(hovered)
	for cell: Array in _cells:
		var r: Rect2 = (cell[0] as Rect2).grow(-2.0)
		var key := String(cell[1])
		var lit := key == hovered or (key.begins_with("straight:") and covered.has(int(key.trim_prefix("straight:"))))
		var fill: Color = cell[3]
		draw_style_box(UiSkin._box(fill.lightened(0.28) if lit else fill, Color(1, 1, 1, 0.85) if lit else Color(1, 1, 1, 0.35), 6, 2 if lit else 1), r)
		draw_string(_font, Vector2(r.position.x, r.get_center().y + 7.0), String(cell[2]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20 if key.begins_with("straight") else 16, Color.WHITE)
	for cell: Array in _cells:  # chips on top of every cell
		var amount := int(_bets.get(String(cell[1]), 0))
		if amount > 0:
			var r2: Rect2 = cell[0]
			ChipArt.draw_stack(self, r2.get_center() + Vector2(0, 8), 15.0, amount, _chips, _font)
	if hovered != "":
		var odds := Roulette.odds(hovered)
		var tip := "pays %d to 1" % odds
		draw_string(_font, Vector2(760, 104), "%s: %s" % [_caption_of(hovered), tip], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT)
	# the chip picker
	var px := felt.end.x + 26.0
	draw_string(_font, Vector2(px, 134), "CHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.ACCENT)
	for i in _chips.size():
		var v := int(_chips[i])
		var at := Vector2(px + 30.0 + float(i % 2) * 70.0, 182.0 + float(floori(i / 2.0)) * 62.0)
		var on := v == _chip
		var spot := Rect2(at - Vector2(28, 28), Vector2(56, 56))
		if on:
			draw_circle(at, 30.0, Color(GOLD, 0.35))
		ChipArt.draw_value(self, at - Vector2(0, 4.0 if on else 0.0), 25.0 if on else 23.0, v, _font)
		if not _busy:
			_hits.append([spot, _on_chip.bind(v), "chip %d" % v])
	# actions
	var by := PANEL.y - 64.0
	_button(Rect2(Vector2(PANEL.x - 300.0, by), Vector2(270, 48)), "SPIN", "spin", not _busy and not _bets.is_empty() and total_bet() <= _coins, _on_spin, true)
	_button(Rect2(Vector2(30, by + 4.0), Vector2(150, 40)), "Undo", "undo", not _busy and not _order.is_empty(), _on_undo)
	_button(Rect2(Vector2(196, by + 4.0), Vector2(170, 40)), "Clear bets", "clear", not _busy and not _bets.is_empty(), _on_clear)
	_button(Rect2(Vector2(382, by + 4.0), Vector2(220, 40)), "Leave table (Esc)", "leave", not _busy, close)
	draw_string(_font, Vector2(620, by + 30.0), "right click: take the last chip back", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)


func _caption_of(key: String) -> String:
	for cell: Array in _cells:
		if String(cell[1]) == key:
			return String(cell[2]) if not key.begins_with("straight") else "Number %s" % cell[2]
	return key
