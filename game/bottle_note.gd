# Purpose: the note from a message in a bottle (sea step 13d), real game UI (game/ui_skin.gd): a title, the riddle in
# lines, a footer line (the chart mark or the coins). F / Esc puts it away.
# Dependencies: game/ui_skin.gd, game/sea_events.gd (set as `events`).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const SIZE := Vector2(700, 380)

var events: Node3D  # game/sea_events.gd
var title := ""
var text := ""
var footer := ""
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func show_note(head: String, body: String, foot: String) -> void:
	title = head
	text = body
	footer = foot
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		events.call("close_window")
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.45))
	var r := Rect2((view - SIZE) * 0.5, SIZE)
	UiSkin.panel(self, r)
	var paper := Rect2(r.position + Vector2(24, 64), r.size - Vector2(48, 128))
	draw_rect(paper, Color(0.88, 0.82, 0.66))
	draw_rect(paper, Color(0.55, 0.43, 0.28), false, 2.0)
	draw_string(_font, r.position + Vector2(28, 44), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiSkin.TEXT)
	var y := paper.position.y + 44.0
	for line: String in text.split("\n"):
		draw_string(_font, Vector2(paper.position.x + 22.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, paper.size.x - 44.0, 18, Color(0.24, 0.16, 0.09))
		y += 32.0
	draw_string(_font, Vector2(r.position.x + 28.0, r.end.y - 30.0), footer, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 220.0, 15, UiSkin.ACCENT)
	var kx := r.end.x - 170.0
	kx += UiSkin.key_cap(self, _font, Vector2(kx, r.end.y - 46.0), "F / Esc") + 6.0
	draw_string(_font, Vector2(kx, r.end.y - 31.0), "Put away", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
