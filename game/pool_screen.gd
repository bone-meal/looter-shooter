# Purpose: (polish1 item 71) the pool screens in the game's skin, like an online pool game: the start menu (opponent,
# chip stake), the players' bar (names, solids / stripes with the balls each still has, whose shot, the shot clock
# ring), a message line (fouls, ball in hand, groups), the SPIN widget (the cue ball with the red dot where the tip
# will strike), the POWER bar, key hints, call-outs and the result (Play again / Join / Leave).
# Shows and collects clicks only: game/pool_game.gd plays.
# Dependencies: game/ui_skin.gd, game/chip_art.gd, game/sharp_text.gd.
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const ChipArt = preload("res://game/chip_art.gd")
const SharpText = preload("res://game/sharp_text.gd")
const BASE_HEIGHT := 648.0
const BALL_COLOURS := [Color(1, 1, 1), Color(0.98, 0.78, 0.05), Color(0.1, 0.25, 0.85), Color(0.85, 0.1, 0.1), Color(0.4, 0.12, 0.6),
	Color(1.0, 0.45, 0.05), Color(0.05, 0.5, 0.2), Color(0.5, 0.12, 0.08), Color(0.05, 0.05, 0.05)]

signal start(opponent: String, stake: int)
signal again
signal join
signal closed

var _menu := CenterContainer.new()
var _result := CenterContainer.new()
var _result_text := Label.new()
var _again_b := Button.new()
var _join_b := Button.new()
var _leave_b := Button.new()
var _chips := Label.new()
var _callout := Label.new()
var _message := Label.new()
var _hint := Label.new()
var _picks := {"opponent": "", "stake": 0}
var _pick_buttons := {}
var _player_choice: Button
var _playing := false
var _callout_t := 0.0
# what the play overlay draws
var names: Array = ["", ""]
var groups: Array = ["", ""]
var left: Array = [[], []]
var current := 0
var clock_share := 1.0  # 0..1 of the shot clock left
var spin := Vector2.ZERO
var power := 0.0
var show_power := false
var font: Font
var _bar_box: StyleBoxFlat


func _ready() -> void:
	visible = false
	theme = UiSkin.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	_fit()
	get_viewport().size_changed.connect(_fit)
	visibility_changed.connect(func() -> void: _fit() if is_visible_in_tree() else SharpText.release(self))


func _fit() -> void:
	var view := get_viewport_rect().size
	var k := clampf(view.y / BASE_HEIGHT, 1.0, 4.0)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	scale = Vector2(k, k)
	size = view / k
	if is_visible_in_tree():
		SharpText.hold(self, k)


func setup(cfg: Dictionary) -> void:
	_build_menu(cfg)
	_build_result()
	for l: Label in [_callout, _message, _hint]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		add_child(l)
	_callout.add_theme_font_size_override("font_size", 46)
	_callout.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.0))
	_callout.add_theme_constant_override("outline_size", 12)
	_callout.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_callout.offset_top = 92
	_message.add_theme_font_size_override("font_size", 18)
	_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_message.add_theme_constant_override("outline_size", 6)
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.offset_top = 62
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -36
	_hint.offset_bottom = -12


func _panel_box() -> StyleBoxFlat:
	var box := (UiSkin.theme().get_stylebox("panel", "Panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	box.set_content_margin_all(18)
	return box


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
	title.text = "POOL  -  8-BALL"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UiSkin.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_chips.add_theme_font_size_override("font_size", 22)
	head.add_child(ChipArt.row(_chips))
	var rules := Label.new()
	rules.text = "Pot all your solids or stripes, then the 8 in the pocket you call. Fouls give ball in hand."
	rules.add_theme_font_size_override("font_size", 14)
	rules.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	v.add_child(rules)
	v.add_child(_section("OPPONENT"))
	var opp: Array = []
	for ai: Dictionary in cfg["ai"]:
		opp.append([String(ai["id"]), String(ai["name"]), String(ai.get("about", ""))])
	_picks["opponent"] = String(opp[0][0])
	opp.append(["player", "Another player", "A person in this lobby: they come to this table and join (you both put in the stake)."])
	v.add_child(_choices("opponent", opp))
	_player_choice = _pick_buttons["opponent"]["player"]
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
	go.text = "  RACK 'EM  "
	go.add_theme_font_size_override("font_size", 22)
	go.pressed.connect(func() -> void: start.emit(String(_picks["opponent"]), int(_picks["stake"])))
	foot.add_child(go)
	_select("opponent", _picks["opponent"])
	_select("stake", 0)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	return l


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


func _build_result() -> void:
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_result)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	_result.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	_result_text.add_theme_font_size_override("font_size", 28)
	_result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_result_text)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	_join_b.text = "  Join  "
	_join_b.pressed.connect(func() -> void: join.emit())
	foot.add_child(_join_b)
	_again_b.text = "Play again"
	_again_b.pressed.connect(func() -> void: again.emit())
	foot.add_child(_again_b)
	_leave_b.text = "Leave"
	_leave_b.pressed.connect(func() -> void: closed.emit())
	foot.add_child(_leave_b)


func show_menu(chips: int, online := false) -> void:
	visible = true
	_playing = false
	_chips.text = str(chips)
	_player_choice.visible = online
	if not online and String(_picks["opponent"]) == "player":
		_select("opponent", (_pick_buttons["opponent"] as Dictionary).keys()[0])
	_menu.visible = true
	_result.visible = false
	_message.text = ""
	_hint.text = ""
	_callout.text = ""
	queue_redraw()


func show_play() -> void:
	_menu.visible = false
	_result.visible = false
	_playing = true
	queue_redraw()


func show_result(text: String, good: bool, can_again := true) -> void:
	visible = true
	_menu.visible = false
	_join_b.visible = false
	_again_b.visible = can_again
	_leave_b.text = "Leave"
	_result_text.text = text
	_result_text.add_theme_color_override("font_color", UiSkin.GOOD if good else UiSkin.TEXT)
	_result.visible = true
	_hint.text = ""


func show_waiting(text: String) -> void:
	show_result(text, false, false)
	_leave_b.text = "Cancel"
	_playing = false
	queue_redraw()


func show_offer(text: String) -> void:
	show_result(text, false, false)
	_join_b.visible = true
	_playing = false
	queue_redraw()


func message(text: String) -> void:
	_message.text = text


func hint(text: String) -> void:
	_hint.text = text


func callout(text: String, colour: Color = UiSkin.ACCENT) -> void:
	_callout.text = text
	_callout.add_theme_color_override("font_color", colour)
	_callout_t = 1.8
	_callout.modulate.a = 1.0


func _process(delta: float) -> void:
	if _callout_t > 0.0:
		_callout_t -= delta
		_callout.modulate.a = clampf(_callout_t / 0.4, 0.0, 1.0)
	if _playing:
		queue_redraw()


func _draw() -> void:
	if not _playing:
		return
	# the players' bar across the top
	var bar := Rect2(size.x * 0.5 - 330, 10, 660, 46)
	if _bar_box == null:
		_bar_box = _panel_box()
	draw_style_box(_bar_box, bar)
	for i in 2:
		var x0 := bar.position.x + (14.0 if i == 0 else 342.0)
		var on := i == current
		var name_col := UiSkin.ACCENT if on else UiSkin.TEXT
		draw_string(font, Vector2(x0, bar.position.y + 20), String(names[i]).substr(0, 16), HORIZONTAL_ALIGNMENT_LEFT, 150, 16, name_col)
		var g := String(groups[i])
		draw_string(font, Vector2(x0, bar.position.y + 38), g.to_upper() if g != "" else "open table", HORIZONTAL_ALIGNMENT_LEFT, 150, 12, UiSkin.TEXT_DIM)
		var balls: Array = left[i]
		for k in balls.size():
			_ball_icon(Vector2(x0 + 158 + float(k) * 19.0, bar.position.y + 23), int(balls[k]), 8.0)
		if on:  # the shot clock round the active name
			var c := Vector2(x0 - 2 + 312, bar.position.y + 23)
			draw_arc(c, 11.0, 0, TAU, 24, Color(1, 1, 1, 0.15), 3.0, true)
			draw_arc(c, 11.0, -PI * 0.5, -PI * 0.5 + TAU * clock_share, 24, UiSkin.GOOD if clock_share > 0.3 else UiSkin.BAD, 3.0, true)
	# spin widget, bottom right
	var sc := Vector2(size.x - 70, size.y - 84)
	draw_circle(sc, 40.0, Color(0, 0, 0, 0.5))
	draw_circle(sc, 36.0, Color(0.96, 0.96, 0.93))
	draw_arc(sc, 36.0, 0, TAU, 40, Color(0, 0, 0, 0.6), 1.5, true)
	draw_line(sc - Vector2(36, 0), sc + Vector2(36, 0), Color(0, 0, 0, 0.12), 1.0)
	draw_line(sc - Vector2(0, 36), sc + Vector2(0, 36), Color(0, 0, 0, 0.12), 1.0)
	draw_circle(sc + Vector2(spin.x, -spin.y) * 30.0, 6.0, Color(0.85, 0.1, 0.1))
	draw_string(font, sc + Vector2(-26, 56), "SPIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
	# power bar, right edge
	if show_power:
		var pr := Rect2(size.x - 34, size.y * 0.5 - 110, 16, 220)
		draw_rect(pr.grow(3), Color(0, 0, 0, 0.55))
		var fill := pr.size.y * power
		var col := UiSkin.GOOD.lerp(UiSkin.BAD, power)
		draw_rect(Rect2(pr.position + Vector2(0, pr.size.y - fill), Vector2(pr.size.x, fill)), col)
		draw_string(font, pr.position + Vector2(-8, -8), "%d%%" % roundi(power * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT)


func _ball_icon(c: Vector2, b: int, rad: float) -> void:
	var base: Color = BALL_COLOURS[b if b <= 8 else b - 8]
	if b >= 9:
		draw_circle(c, rad, Color(0.97, 0.96, 0.92))
		draw_rect(Rect2(c - Vector2(rad, rad * 0.45), Vector2(rad * 2.0, rad * 0.9)), base)
	else:
		draw_circle(c, rad, base)
	draw_circle(c, rad * 0.45, Color(0.98, 0.98, 0.95))
	var t := str(b)
	var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
	draw_string(font, c + Vector2(-ts.x * 0.5, 3), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.05, 0.05, 0.05))
