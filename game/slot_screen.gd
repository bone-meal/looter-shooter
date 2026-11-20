# Purpose: the slot machine's screen (polish1 items 73-74, real game UI: game/ui_skin.gd), styled as the machine's
# own panel: a gold-rimmed cabinet strip with your chips, the JACKPOT pot glittering in big gold, the last result
# (wins lit up), BET PER LINE as a row of big real chips with the spin's cost spelled out, a big SPIN; Leave in the
# corner. The paytable is a card at the left edge (symbol pictures, x pays, the pot at max bet). It stands clear of the
# HUD's bottom bar. Only collects input and shows numbers; game_session runs the spin and the wallet.
# Dependencies: game/symbol_art.gd (paytable icons), game/chip_art.gd, game/ui_skin.gd, data/slots.json passed in via setup().
extends Control

const ChipArt = preload("res://game/chip_art.gd")
const UiSkin = preload("res://game/ui_skin.gd")
const SymbolArt = preload("res://game/symbol_art.gd")

signal spin_requested(bet_per_line: int)
signal closed

const GOLD := Color(1.0, 0.8, 0.25)
const CABINET := Color(0.12, 0.03, 0.1, 0.97)
const PANEL := Vector2(960, 300)
const ORDER: Array[String] = ["jackpot", "seven", "wild", "bar", "bell", "plum", "lemon", "cherry"]

var _bets: Array = []
var _pays: Dictionary = {}
var _lines := 5
var _bet := 1
var _coins := 0
var _pot := 0.0
var _busy := false
var _message := ""
var _won_at := -10.0  # when the last spin paid (the message flashes)
var _hits: Array = []  # [Rect2, Callable, key]
var _mouse := Vector2(-1, -1)
var _t := 0.0
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -PANEL.x * 0.5
	offset_right = PANEL.x * 0.5
	offset_top = -PANEL.y - 110.0  # clear of the HUD's bottom bar
	offset_bottom = -110.0


# data = parsed data/slots.json
func setup(data: Dictionary) -> void:
	_bets = data["bets"]
	_pays = data["pays"]
	_lines = (data["lines"] as Array).size()


func open(coins: int, pot: float) -> void:
	_coins = coins
	_pot = pot
	_message = "Pick a bet and press SPIN."
	_busy = false
	visible = true
	if _bets.size() > 0 and _bet > int(_bets[_bets.size() - 1]):
		_bet = int(_bets[0])
	queue_redraw()


func close() -> void:
	if _busy:
		return
	visible = false
	closed.emit()


# Called by the session around a spin.
func set_busy(busy: bool) -> void:
	_busy = busy
	if busy:
		_message = "Spinning..."
	queue_redraw()


func show_state(coins: int, pot: float, message: String) -> void:
	if coins > _coins and not _busy:
		_won_at = _t
	_coins = coins
	_pot = pot
	_message = message
	queue_redraw()


func cost() -> int:
	return _bet * _lines


# Checks: press a control by key ("spin", "leave", "bet 5").
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
		queue_redraw()  # the pot glitters


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
	var b := event as InputEventMouseButton
	if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
		for hit: Array in _hits:
			if (hit[0] as Rect2).has_point(b.position):
				(hit[1] as Callable).call()
				break
		accept_event()


func _on_bet(b: int) -> void:
	if _busy:
		return
	_bet = b


func _on_spin() -> void:
	if _busy or _coins < cost():
		return
	spin_requested.emit(_bet)


func _button(r: Rect2, label: String, key: String, enabled: bool, act: Callable, big: bool = false) -> void:
	UiSkin.pill(self, _font, r, label, big and enabled, r.has_point(_mouse) and enabled, 30 if big else 17)
	if enabled:
		_hits.append([r, act, key])
	else:
		draw_style_box(UiSkin._box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), int(r.size.y * 0.5), 0), r)


func _draw() -> void:
	_hits.clear()
	var r := Rect2(Vector2.ZERO, PANEL)
	UiSkin.panel(self, r, CABINET, Color(GOLD, 0.9), 18)
	draw_style_box(UiSkin._box(Color(0, 0, 0, 0), Color(GOLD, 0.35), 14, 1), r.grow(-6.0))
	# the pot, big, in the middle of the top
	var pot := "JACKPOT  %d" % floori(_pot)
	var shine := Color(1.0, 0.8 + 0.15 * sin(_t * 4.0), 0.25 + 0.1 * sin(_t * 7.0))
	draw_string_outline(_font, Vector2(0, 62), pot, HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 46, 8, Color(0.35, 0.12, 0.0))
	draw_string(_font, Vector2(0, 62), pot, HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 46, shine)
	ChipArt.draw_value(self, Vector2(44, 44), 17.0, 25)
	draw_string(_font, Vector2(70, 54), "%d" % _coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UiSkin.TEXT)
	_button(Rect2(Vector2(PANEL.x - 240.0, 24), Vector2(216, 40)), "Leave (Esc)", "leave", not _busy, close)
	# the result line: a win flashes gold
	var flash := _t - _won_at < 2.5 and int(_t * 6.0) % 2 == 0
	var msg_box := Rect2(Vector2(24, 86), Vector2(PANEL.x - 48.0, 52))
	draw_style_box(UiSkin._box(Color(0, 0, 0, 0.45), Color(GOLD, 0.8) if flash else Color(1, 1, 1, 0.08), 10, 2 if flash else 1), msg_box)
	draw_string(_font, Vector2(msg_box.position.x, msg_box.position.y + 35.0), _message, HORIZONTAL_ALIGNMENT_CENTER, msg_box.size.x, 26, GOLD if flash else UiSkin.TEXT)
	# bet per line + SPIN
	var by := 160.0
	draw_string(_font, Vector2(28, by + 4.0), "BET PER LINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.ACCENT)
	draw_string(_font, Vector2(170, by + 4.0), "%d lines x %d = %d chips a spin" % [_lines, _bet, cost()], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiSkin.TEXT)
	for i in _bets.size():
		var v := int(_bets[i])
		var at := Vector2(60.0 + float(i) * 80.0, by + 66.0)
		var on := v == _bet
		if on:
			draw_circle(at, 35.0, Color(GOLD, 0.45))
			draw_arc(at, 35.0, 0.0, TAU, 32, GOLD, 3.0, true)
		ChipArt.draw_value(self, at - Vector2(0, 5.0 if on else 0.0), 29.0 if on else 27.0, v, _font)
		if _busy or v * _lines > _coins:
			draw_circle(at, 28.0, Color(0, 0, 0, 0.55))
		if not _busy:
			_hits.append([Rect2(at - Vector2(31, 31), Vector2(62, 62)), _on_bet.bind(v), "bet %d" % v])
	_button(Rect2(Vector2(PANEL.x - 330.0, by + 32.0), Vector2(306, 72)), "SPIN", "spin", not _busy and _coins >= cost(), _on_spin, true)
	_paytable()


# The paytable card at the left edge of the screen, mid height (drawn outside the panel, in screen place).
func _paytable() -> void:
	var view := get_viewport_rect().size
	var box := Vector2(270, 66.0 + 50.0 * float(ORDER.size()))
	var r := Rect2(Vector2(24.0, (view.y - box.y) * 0.5 - 60.0) - global_position, box)
	UiSkin.panel(self, r, CABINET, Color(GOLD, 0.6), 14)
	draw_string(_font, r.position + Vector2(18, 38), "3 ON A LINE PAYS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiSkin.ACCENT)
	var tex := SymbolArt.atlas()
	for i in ORDER.size():
		var id := ORDER[i]
		var y := r.position.y + 56.0 + float(i) * 50.0
		draw_style_box(UiSkin._box(UiSkin.INK_DEEP, Color(1, 1, 1, 0.1), 6, 1), Rect2(Vector2(r.position.x + 14.0, y), Vector2(82, 44)))
		draw_texture_rect_region(tex, Rect2(Vector2(r.position.x + 19.0, y + 2.0), Vector2(72, 40)), SymbolArt.pixel_rect(id))
		var text := "POT (max bet)" if id == "jackpot" else "x%d" % int(_pays[id])
		draw_string(_font, Vector2(r.position.x + 108.0, y + 30.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GOLD if id == "jackpot" else UiSkin.TEXT)
