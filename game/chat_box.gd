# Purpose: the text chat on the HUD: the last lines in the bottom-left corner (they fade after a while) and a one-line
# input opened with the chat key (Enter) or the command key (/). Emits `submitted` with what was typed; it does not
# know about the network or commands (game/game_session.gd routes the text).
# Dependencies: none. Sits on a CanvasLayer.
extends Control

signal submitted(text: String)
signal opened
signal closed

const SHOWN := 8  # lines visible at once
const KEPT := 60  # lines remembered while the input is open
const FADE_AFTER := 9.0
const MAX_CHARS := 160

var _lines: Array = []  # [text, colour, age in seconds]
var _entry := LineEdit.new()
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry.visible = false
	_entry.max_length = MAX_CHARS
	_entry.placeholder_text = "Say something, or / for commands"
	_entry.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_entry.position = Vector2(14, -196)
	_entry.custom_minimum_size = Vector2(520, 30)
	_entry.text_submitted.connect(_on_submitted)
	add_child(_entry)


func is_open() -> bool:
	return _entry.visible


func open(start_text: String = "") -> void:
	_entry.visible = true
	_entry.text = start_text
	_entry.grab_focus()
	_entry.caret_column = start_text.length()
	opened.emit()
	queue_redraw()


func close() -> void:
	if not _entry.visible:
		return
	_entry.release_focus()
	_entry.visible = false
	closed.emit()
	queue_redraw()


func add_line(text: String, color: Color = Color.WHITE) -> void:
	_lines.append([text, color, 0.0])
	if _lines.size() > KEPT:
		_lines.pop_front()
	queue_redraw()


func _on_submitted(text: String) -> void:
	close()
	if text.strip_edges() != "":
		submitted.emit(text)


func _input_event_closes(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE


func _input(event: InputEvent) -> void:
	if _entry.visible and _input_event_closes(event):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var fading := false
	for line: Array in _lines:
		line[2] = float(line[2]) + delta
		fading = fading or float(line[2]) < FADE_AFTER + 1.0
	if fading or _entry.visible:
		queue_redraw()


func _draw() -> void:
	var base := Vector2(16, size.y - 205.0)  # above the health ring and its text
	var shown: Array = []  # [line, alpha], newest first
	for i in range(_lines.size() - 1, -1, -1):
		var line: Array = _lines[i]
		var alpha := 1.0 if _entry.visible else clampf(FADE_AFTER + 1.0 - float(line[2]), 0.0, 1.0)
		if alpha <= 0.0:
			continue
		shown.append([line, alpha])
		if shown.size() >= SHOWN:
			break
	if shown.is_empty():
		return
	var widest := 0.0
	var brightest := 0.0
	for pair: Array in shown:
		widest = maxf(widest, _font.get_string_size(String(pair[0][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
		brightest = maxf(brightest, float(pair[1]))
	var top := base.y - 20.0 * float(shown.size() - 1) - 16.0
	draw_rect(Rect2(base.x - 8.0, top - 4.0, widest + 16.0, base.y - top + 10.0), Color(0.12, 0.12, 0.13, 0.42 * brightest))  # a faint box so the lines stay readable on bright sand and sky
	for n in shown.size():
		var line: Array = shown[n][0]
		var alpha := float(shown[n][1])
		var at := base - Vector2(0, 20.0 * float(n))
		var color: Color = line[1]
		draw_string(_font, at + Vector2(1, 1), String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.7 * alpha))
		draw_string(_font, at, String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(color.r, color.g, color.b, alpha))
