# Purpose: the slot machine's screen (polish1 item 74, real game UI: game/ui_skin.gd): chips, the jackpot pot in big
# gold, the bet per line as a row of real chips with the spin's cost (lines x bet), a big SPIN, the last result and
# Leave inside the panel; the paytable as a skinned card at the right edge (symbol pictures, x pays, the pot at max
# bet). Only collects input and shows numbers; game_session runs the spin and the wallet.
# Dependencies: game/symbol_art.gd (paytable icons), game/chip_art.gd, game/ui_skin.gd, data/slots.json passed in via setup().
extends Control

const ChipArt = preload("res://game/chip_art.gd")
const UiSkin = preload("res://game/ui_skin.gd")
const SymbolArt = preload("res://game/symbol_art.gd")

signal spin_requested(bet_per_line: int)
signal closed

const GOLD := Color(1.0, 0.8, 0.25)
const PANEL := Vector2(860, 230)
const ORDER: Array[String] = ["jackpot", "seven", "wild", "bar", "bell", "plum", "lemon", "cherry"]

var _bets: Array = []
var _pays: Dictionary = {}
var _lines := 5
var _bet := 1
var _coins := 0
var _pot := 0.0
var _busy := false
var _message := ""
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
	offset_top = -PANEL.y - 14.0
	offset_bottom = -14.0


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
	queue_redraw()


func show_state(coins: int, pot: float, message: String) -> void:
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
	UiSkin.pill(self, _font, r, label, big and enabled, r.has_point(_mouse) and enabled, 26 if big else 15)
	if enabled:
		_hits.append([r, act, key])
	else:
		draw_style_box(UiSkin._box(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), int(r.size.y * 0.5), 0), r)


func _draw() -> void:
	_hits.clear()
	UiSkin.panel(self, Rect2(Vector2.ZERO, PANEL))
	ChipArt.draw_value(self, Vector2(40, 38), 15.0, 25)
	draw_string(_font, Vector2(64, 46), "%d" % _coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiSkin.TEXT)
	var pot := "JACKPOT  %d" % floori(_pot)
	var shine := Color(1.0, 0.82 + 0.12 * sin(_t * 4.0), 0.3)
	draw_string_outline(_font, Vector2(0, 50), pot, HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 34, 6, Color(0.35, 0.15, 0.0))
	draw_string(_font, Vector2(0, 50), pot, HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 34, shine)
	draw_string(_font, Vector2(24, 96), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 48.0, 21, GOLD)
	var by := PANEL.y - 100.0
	draw_string(_font, Vector2(24, by + 4.0), "BET PER LINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.ACCENT)
	draw_string(_font, Vector2(150, by + 4.0), "%d lines x %d = %d chips a spin" % [_lines, _bet, cost()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
	for i in _bets.size():
		var v := int(_bets[i])
		var at := Vector2(52.0 + float(i) * 70.0, by + 46.0)
		var on := v == _bet
		if on:
			draw_circle(at, 31.0, Color(GOLD, 0.35))
		ChipArt.draw_value(self, at - Vector2(0, 4.0 if on else 0.0), 26.0 if on else 24.0, v, _font)
		if _busy:
			draw_circle(at, 25.0, Color(0, 0, 0, 0.5))
		else:
			_hits.append([Rect2(at - Vector2(28, 28), Vector2(56, 56)), _on_bet.bind(v), "bet %d" % v])
	_button(Rect2(Vector2(PANEL.x - 300.0, by + 16.0), Vector2(270, 60)), "SPIN", "spin", not _busy and _coins >= cost(), _on_spin, true)
	_button(Rect2(Vector2(PANEL.x - 230.0, 70), Vector2(206, 36)), "Leave machine (Esc)", "leave", not _busy, close)
	_paytable()


# The paytable card at the right edge of the screen (drawn outside the panel, in screen place).
func _paytable() -> void:
	var view := get_viewport_rect().size
	var box := Vector2(250, 60.0 + 46.0 * float(ORDER.size()))
	var r := Rect2(Vector2(view.x - box.x - 24.0, 110.0) - global_position, box)
	UiSkin.panel(self, r)
	draw_string(_font, r.position + Vector2(18, 34), "3 ON A LINE PAYS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.ACCENT)
	var tex := SymbolArt.atlas()
	for i in ORDER.size():
		var id := ORDER[i]
		var y := r.position.y + 52.0 + float(i) * 46.0
		draw_style_box(UiSkin._box(UiSkin.INK_DEEP, Color(1, 1, 1, 0.08), 6, 1), Rect2(Vector2(r.position.x + 14.0, y), Vector2(74, 40)))
		draw_texture_rect_region(tex, Rect2(Vector2(r.position.x + 19.0, y + 2.0), Vector2(64, 36)), SymbolArt.pixel_rect(id))
		var text := "POT  (max bet)" if id == "jackpot" else "x%d" % int(_pays[id])
		draw_string(_font, Vector2(r.position.x + 100.0, y + 28.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD if id == "jackpot" else UiSkin.TEXT)
