# Purpose: the screen shown when a run on the islands ends: the round reached, the character's best round, and what
# the run brought (kills, headshots, points). It fades in over the game, which goes on underneath, and leaves by
# itself after a few seconds or at a click or key press.
# Dependencies: game/chalk_marks.gd (the round in chalk). game/game_session.gd calls show_run().
extends Control

const ChalkMarks = preload("res://game/chalk_marks.gd")

const STAY := 8.0  # seconds it stays without input
const MIN_STAY := 1.2  # no input closes it before this

var _font: Font = ThemeDB.fallback_font
var _age := 0.0
var _round := 0
var _best := 0
var _record := false
var _lines := PackedStringArray()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


# `lines` = what the run brought, one per line (already worded).
func show_run(round_reached: int, best_round: int, new_record: bool, lines: PackedStringArray) -> void:
	_round = round_reached
	_best = best_round
	_record = new_record
	_lines = lines
	_age = 0.0
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta
	if _age >= STAY:
		visible = false
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and _age >= MIN_STAY and ((event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		visible = false


func _draw() -> void:
	var view := get_viewport_rect().size
	var fade := clampf(_age / 0.6, 0.0, 1.0) * clampf((STAY - _age) / 0.8, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.05, 0.0, 0.0, 0.72 * fade))
	var red := Color(0.78, 0.07, 0.05, fade)
	var white := Color(1, 1, 1, 0.95 * fade)
	draw_string(_font, Vector2(0, view.y * 0.26), "GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, view.x, 64, red)
	draw_string(_font, Vector2(0, view.y * 0.26 + 44.0), "You made it to round", HORIZONTAL_ALIGNMENT_CENTER, view.x, 22, white)
	var digits := str(maxi(_round, 0)).length()
	var height := 120.0
	var width := height * (ChalkMarks.DIGIT_W + 0.14) * digits
	ChalkMarks.number(self, Vector2((view.x - width) * 0.5, view.y * 0.26 + 70.0), _round, height, red)
	var y := view.y * 0.26 + 70.0 + height + 48.0
	draw_string(_font, Vector2(0, y), ("A new best for this character!" if _record else "Best round of this character: %d" % _best), HORIZONTAL_ALIGNMENT_CENTER, view.x, 22, Color(1.0, 0.85, 0.3, fade) if _record else white)
	for i in _lines.size():
		draw_string(_font, Vector2(0, y + 40.0 + 28.0 * i), _lines[i], HORIZONTAL_ALIGNMENT_CENTER, view.x, 18, white)
