# Purpose: (polish1 item 71) the darts screens in the game's skin: the start menu (game: 501 / Around the Clock,
# opponent, chip stake), the scoreboard while playing (each player's score or number, this turn's darts, the
# checkout to aim for), the aim reticle with its steady bar, big call-outs (T20, BUST, ONE HUNDRED AND EIGHTY) and
# the result (Play again / Leave). Shows and collects clicks only: game/darts_game.gd plays.
# Dependencies: game/ui_skin.gd, game/chip_art.gd.
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const BASE_HEIGHT := 648.0
const ChipArt = preload("res://game/chip_art.gd")
const SharpText = preload("res://game/sharp_text.gd")

signal start(mode: String, opponent: String, stake: int)
signal again
signal closed

var _menu := CenterContainer.new()
var _board := PanelContainer.new()
var _result := CenterContainer.new()
var _rows: Array = []  # per player: [name label, need label, turn label]
var _checkout := Label.new()
var _hint := Label.new()
var _callout := Label.new()
var _result_text := Label.new()
var _chips := Label.new()
var _picks := {"mode": "501", "opponent": "", "stake": 0}
var _pick_buttons := {}  # group -> {value -> Button}
var _reticle := Vector2.ZERO
var _reticle_on := false
var _steady := 1.0  # 0..1 left
var _steadying := false
var _callout_t := 0.0


func _ready() -> void:
	visible = false
	theme = UiSkin.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)
	visibility_changed.connect(func() -> void: _fit() if is_visible_in_tree() else SharpText.release(self))


# Laid out for a 648-pixel-high window and scaled up (like the card machine and the prize counter).
func _fit() -> void:
	var view := get_viewport_rect().size
	var k := clampf(view.y / BASE_HEIGHT, 1.0, 4.0)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	scale = Vector2(k, k)
	size = view / k
	if is_visible_in_tree():
		SharpText.hold(self, k)


# A screen point (the camera's) in this scaled layout.
func to_local_point(screen: Vector2) -> Vector2:
	return screen / scale.x


func setup(cfg: Dictionary) -> void:
	_build_menu(cfg)
	_build_board()
	_build_result()
	_callout.add_theme_font_size_override("font_size", 54)
	_callout.add_theme_color_override("font_color", UiSkin.ACCENT)
	_callout.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.0))
	_callout.add_theme_constant_override("outline_size", 14)
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_callout.offset_top = 60
	_callout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_callout)
	_hint.text = "Mouse: aim    Hold right mouse: steady your hand    Left mouse: throw    Esc: leave"
	_hint.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -40
	_hint.offset_bottom = -14
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_hint)


func _build_menu(cfg: Dictionary) -> void:
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	_menu.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "DARTS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UiSkin.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_chips.add_theme_font_size_override("font_size", 22)
	head.add_child(ChipArt.row(_chips))
	v.add_child(_section("GAME"))
	v.add_child(_choices("mode", [["501", "501", "From 501 down to exactly 0, finishing on a double (or the bull)."], ["clock", "Around the Clock", "Hit 1 to 20 in order, then the bull. A double moves you on two, a treble three."]]))
	v.add_child(_section("OPPONENT"))
	var opp: Array = []
	for ai: Dictionary in cfg["ai"]:
		opp.append([String(ai["id"]), String(ai["name"]), String(ai.get("about", ""))])
	_picks["opponent"] = String(opp[0][0])
	v.add_child(_choices("opponent", opp))
	v.add_child(_section("STAKE (win = the stake again)"))
	var st: Array = []
	for s: Variant in cfg["stakes"]:
		st.append([int(s), "Free" if int(s) == 0 else "%d chips" % int(s), ""])
	v.add_child(_choices("stake", st))
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func() -> void: closed.emit())
	foot.add_child(leave)
	var go := Button.new()
	go.text = "  START  "
	go.add_theme_font_size_override("font_size", 22)
	go.pressed.connect(func() -> void: start.emit(String(_picks["mode"]), String(_picks["opponent"]), int(_picks["stake"])))
	foot.add_child(go)
	_select("mode", "501")
	_select("opponent", _picks["opponent"])
	_select("stake", 0)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	return l


# A row of toggle buttons; each item = [value, label, tooltip].
func _choices(group: String, items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_pick_buttons[group] = {}
	for it: Array in items:
		var b := Button.new()
		b.text = String(it[1])
		b.tooltip_text = String(it[2])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, 40)
		var value: Variant = it[0]
		b.pressed.connect(func() -> void: _select(group, value))
		row.add_child(b)
		_pick_buttons[group][value] = b
	return row


func _select(group: String, value: Variant) -> void:
	_picks[group] = value
	for v: Variant in _pick_buttons[group]:
		(_pick_buttons[group][v] as Button).button_pressed = v == value


func _build_board() -> void:
	_board.add_theme_stylebox_override("panel", _panel_box())
	_board.position = Vector2(18, 18)
	add_child(_board)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_board.add_child(v)
	for i in 2:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		v.add_child(row)
		var name_l := Label.new()
		name_l.custom_minimum_size = Vector2(170, 0)
		name_l.add_theme_font_size_override("font_size", 20)
		row.add_child(name_l)
		var need := Label.new()
		need.custom_minimum_size = Vector2(110, 0)
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		need.add_theme_font_size_override("font_size", 30)
		row.add_child(need)
		var turn := Label.new()
		turn.custom_minimum_size = Vector2(150, 0)
		turn.add_theme_font_size_override("font_size", 16)
		turn.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
		row.add_child(turn)
		_rows.append([name_l, need, turn])
	_checkout.add_theme_font_size_override("font_size", 17)
	_checkout.add_theme_color_override("font_color", UiSkin.GOOD)
	v.add_child(_checkout)


func _build_result() -> void:
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_result)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	_result.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	_result_text.add_theme_font_size_override("font_size", 30)
	_result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_result_text)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	var again_b := Button.new()
	again_b.text = "Play again"
	again_b.pressed.connect(func() -> void: again.emit())
	foot.add_child(again_b)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func() -> void: closed.emit())
	foot.add_child(leave)


func _panel_box() -> StyleBoxFlat:
	var box := (UiSkin.theme().get_stylebox("panel", "Panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	box.set_content_margin_all(18)
	return box


func show_menu(chips: int) -> void:
	visible = true
	_chips.text = str(chips)
	_menu.visible = true
	_board.visible = false
	_result.visible = false
	_hint.visible = false
	_callout.text = ""
	_reticle_on = false


func show_play() -> void:
	_menu.visible = false
	_result.visible = false
	_board.visible = true
	_hint.visible = true


func show_result(text: String, good: bool) -> void:
	_result_text.text = text
	_result_text.add_theme_color_override("font_color", UiSkin.GOOD if good else UiSkin.TEXT)
	_result.visible = true
	_hint.visible = false
	_reticle_on = false


# names, needs (text), turn texts, whose turn, the checkout line.
func show_scores(names: Array, needs: Array, turns: Array, current: int, checkout: String) -> void:
	for i in _rows.size():
		var row: Array = _rows[i]
		var on := i == current
		(row[0] as Label).text = ("> " if on else "   ") + String(names[i])
		(row[0] as Label).add_theme_color_override("font_color", UiSkin.ACCENT if on else UiSkin.TEXT)
		(row[1] as Label).text = String(needs[i])
		(row[2] as Label).text = String(turns[i])
	_checkout.text = checkout
	_checkout.visible = checkout != ""


func callout(text: String, colour: Color = UiSkin.ACCENT) -> void:
	_callout.text = text
	_callout.add_theme_color_override("font_color", colour)
	_callout_t = 1.6
	_callout.modulate.a = 1.0


func set_reticle(on: bool, at: Vector2, steady_left: float, steadying: bool) -> void:
	_reticle_on = on
	_reticle = to_local_point(at)
	_steady = steady_left
	_steadying = steadying
	queue_redraw()


func _process(delta: float) -> void:
	if _callout_t > 0.0:
		_callout_t -= delta
		_callout.modulate.a = clampf(_callout_t / 0.4, 0.0, 1.0)


func _draw() -> void:
	if not _reticle_on:
		return
	var col := UiSkin.ACCENT if not _steadying else UiSkin.GOOD
	draw_arc(_reticle, 9.0, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 4.0, true)
	draw_arc(_reticle, 9.0, 0.0, TAU, 24, col, 2.0, true)
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(_reticle + d * 13.0, _reticle + d * 22.0, col, 2.0, true)
	draw_circle(_reticle, 1.6, col)
	var bar := Rect2(_reticle + Vector2(-24, 30), Vector2(48, 6))  # the steady meter under the reticle
	draw_rect(bar, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * _steady, bar.size.y)), UiSkin.GOOD if _steady > 0.25 else UiSkin.BAD)
