# Purpose: the player card banner (MW2-style): emblem on the left, callsign, title, level badge and XP bar on a coloured strip. Pure drawing; the owner calls show_card() with the values.
# Dependencies: game/emblem_art.gd, game/ui_skin.gd (polish1 item 81: medallion, shield, sweep).
extends Control

const EmblemArt = preload("res://game/emblem_art.gd")
const UiSkin = preload("res://game/ui_skin.gd")

const SIZE := Vector2(780.0, 140.0)

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
	# (polish1 item 81) a richer banner: the emblem's colours as a sweep, the emblem in a ringed medallion, the callsign
	# large and outlined, the level as a shield, the XP bar rounded with its share
	var accent := _c1.lerp(Color.WHITE, 0.15)
	var r := Rect2(Vector2.ZERO, SIZE)
	UiSkin.panel(self, r, Color(0.05, 0.06, 0.09, 0.98), Color(accent, 0.6), 14)
	var sweep := PackedColorArray([Color(_c1, 0.45), Color(_c2, 0.08), Color(_c2, 0.08), Color(_c1, 0.45)])
	draw_polygon(PackedVector2Array([Vector2(2, 2), Vector2(SIZE.x * 0.75, 2), Vector2(SIZE.x * 0.55, SIZE.y - 2), Vector2(2, SIZE.y - 2)]), sweep)
	draw_rect(Rect2(Vector2(14, SIZE.y - 5), Vector2(SIZE.x - 28.0, 3)), Color(_c2, 0.9))
	var mid := Vector2(70, SIZE.y * 0.5)
	draw_circle(mid, 52.0, Color(0, 0, 0, 0.5))
	draw_circle(mid, 48.0, Color(0.12, 0.13, 0.18))
	draw_arc(mid, 49.0, 0.0, TAU, 48, accent, 3.0, true)
	draw_arc(mid, 54.0, 0.0, TAU, 48, Color(accent, 0.35), 1.5, true)
	EmblemArt.draw_def(self, _emblem, mid, 36.0)
	var name_text := _callsign if _callsign != "" else "Unnamed"
	draw_string_outline(_font, Vector2(140, 58), name_text, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 260.0, 38, 6, Color(0, 0, 0, 0.7))
	draw_string(_font, Vector2(140, 58), name_text, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 260.0, 38, Color.WHITE)
	draw_string(_font, Vector2(140, 86), _title, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 260.0, 21, accent)
	draw_string(_font, Vector2(140, 110), _line, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 160.0, 15, Color(1, 1, 1, 0.6))
	var shield := PackedVector2Array([Vector2(SIZE.x - 92, 14), Vector2(SIZE.x - 24, 14), Vector2(SIZE.x - 24, 54), Vector2(SIZE.x - 58, 74), Vector2(SIZE.x - 92, 54)])
	draw_colored_polygon(shield, accent)
	draw_polyline(shield + PackedVector2Array([shield[0]]), Color(1, 1, 1, 0.6), 2.0, true)
	draw_string(_font, Vector2(SIZE.x - 92, 32), "LEVEL", HORIZONTAL_ALIGNMENT_CENTER, 68, 12, Color(0.05, 0.05, 0.08))
	draw_string(_font, Vector2(SIZE.x - 92, 58), str(_level), HORIZONTAL_ALIGNMENT_CENTER, 68, 26, Color(0.05, 0.05, 0.08))
	var bar := Rect2(Vector2(140, SIZE.y - 26), Vector2(SIZE.x - 260.0, 10))
	UiSkin.bar(self, bar, _ratio, accent)
	draw_string(_font, Vector2(bar.end.x + 10.0, bar.end.y + 2.0), "XP %d%%" % roundi(_ratio * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
