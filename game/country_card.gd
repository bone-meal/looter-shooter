# Purpose: the BORDER CROSSING card (polish1 F1a): while the party goes over a border and the next country is built,
# the whole screen is a night-ink card: the country's name in Grenze Gotisch, its level band, its painted map
# (assets/ui/countries/<id>.png, cut from the continent by tools/worldgen/export_countries.py) in a gold frame and a
# line about it. It stays at least SHOW_S seconds and until the session says the land is ready.
# Dependencies: game/fantasy_style.gd (fonts, colours).
extends Control

const Style = preload("res://game/fantasy_style.gd")
const SHOW_S := 2.5
const FADE_S := 0.5

var _name := ""
var _levels := ""
var _about := ""
var _map: Texture2D = null
var _age := -1.0
var _ready_to_go := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_for(id: String, country_name: String, levels: String, about: String) -> void:
	_name = country_name
	_levels = levels
	_about = about
	var path := "res://assets/ui/countries/%s.png" % id
	_map = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_age = 0.0
	_ready_to_go = false
	visible = true
	queue_redraw()


# The next country is built: the card fades once it has shown long enough.
func done() -> void:
	_ready_to_go = true


func _process(delta: float) -> void:
	if _age < 0.0:
		return
	_age += minf(delta, 0.1)  # building the land holds frames for seconds: the card still shows its time after
	if _ready_to_go and _age >= SHOW_S + FADE_S:
		_age = -1.0
		visible = false
	queue_redraw()


func _draw() -> void:
	if _age < 0.0:
		return
	var view := size
	var a := 1.0 if not _ready_to_go or _age < SHOW_S else clampf((SHOW_S + FADE_S - _age) / FADE_S, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.05, 0.04, 0.03, a))
	var mid := view * 0.5
	draw_string(Style.gothic(), Vector2(0.0, mid.y - 250.0), _name, HORIZONTAL_ALIGNMENT_CENTER, view.x, 54, Color(Style.PARCHMENT, a))
	if _levels != "":
		draw_string(Style.font_italic(), Vector2(0.0, mid.y - 212.0), "levels %s" % _levels, HORIZONTAL_ALIGNMENT_CENTER, view.x, 20, Color(Style.FADED, a))
	var box := Rect2(mid + Vector2(-170.0, -190.0), Vector2(340.0, 340.0))
	if _map != null:
		draw_texture_rect(_map, box, false, Color(1, 1, 1, a))
	draw_rect(box.grow(4.0), Color(Style.GOLD, a), false, 3.0)
	draw_rect(box.grow(9.0), Color(Style.GOLD_DIM, a), false, 1.5)
	if _about != "":
		draw_multiline_string(Style.font_italic(), Vector2(mid.x - 330.0, box.end.y + 46.0), _about, HORIZONTAL_ALIGNMENT_CENTER, 660.0, 18, 3, Color(Style.FADED, a))
	var dots := ".".repeat(1 + int(_age * 2.0) % 3)
	draw_string(Style.font_italic(), Vector2(0.0, view.y - 60.0), "Crossing the border" + dots, HORIZONTAL_ALIGNMENT_CENTER, view.x, 18, Color(Style.FADED, a * 0.8))
