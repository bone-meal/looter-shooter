# Purpose: the player card banner (MW2-style): emblem on the left, callsign, title, level badge and XP bar on a coloured strip. Pure drawing; the owner calls show_card() with the values.
# Dependencies: game/emblem_art.gd.
extends Control

const EmblemArt = preload("res://game/emblem_art.gd")

const SIZE := Vector2(580.0, 116.0)

var _callsign := ""
var _title := ""
var _level := 1
var _ratio := 0.0
var _emblem := {}  # one entry of data/achievements.json "emblems"
var _c1 := Color.WHITE  # the card's colours, from the emblem
var _c2 := Color.GRAY
var _line := ""
var _font: Font = ThemeDB.fallback_font


func _init() -> void:
	custom_minimum_size = SIZE


# emblem_def is one entry of data/achievements.json "emblems". `line` is a small stats line (e.g. "Kills 120").
func show_card(callsign: String, title_text: String, level: int, xp_ratio: float, emblem_def: Dictionary, line: String) -> void:
	_callsign = callsign
	_title = title_text
	_level = level
	_ratio = clampf(xp_ratio, 0.0, 1.0)
	_emblem = emblem_def
	_c1 = Color.html(String(emblem_def.get("c1", emblem_def.get("c4", "#ffffff"))))
	_c2 = Color.html(String(emblem_def.get("c2", emblem_def.get("c3", "#888888"))))
	_line = line
	queue_redraw()


func _draw() -> void:
	var accent := _c1.lerp(Color.WHITE, 0.15)
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.07, 0.08, 0.11))
	draw_rect(Rect2(Vector2(0, 0), Vector2(SIZE.x, 6)), accent)
	draw_rect(Rect2(Vector2(0, SIZE.y - 6), Vector2(SIZE.x, 6)), _c2)
	var frame := Rect2(Vector2(10, 12), Vector2(92, 92))
	draw_rect(frame, Color(0.14, 0.16, 0.22))
	draw_rect(frame, accent, false, 2.0)
	EmblemArt.draw_def(self, _emblem, frame.get_center(), 40.0)
	var name_text := _callsign if _callsign != "" else "Unnamed"
	draw_string(_font, Vector2(116, 46), name_text, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 200.0, 32, Color(1, 1, 1, 0.95))
	draw_string(_font, Vector2(116, 70), _title, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 130.0, 18, accent)
	draw_string(_font, Vector2(116, 92), _line, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 130.0, 14, Color(1, 1, 1, 0.55))
	var badge := Rect2(Vector2(SIZE.x - 76, 14), Vector2(64, 30))
	draw_rect(badge, accent)
	draw_string(_font, badge.position + Vector2(0, 22), "LV %d" % _level, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 20, Color(0.05, 0.05, 0.08))
	draw_rect(Rect2(Vector2(116, 98), Vector2(SIZE.x - 130.0, 5)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(Vector2(116, 98), Vector2((SIZE.x - 130.0) * _ratio, 5)), accent)
