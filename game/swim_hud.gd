# Purpose: what swimming shows on screen (sea step 5b), real game UI (game/ui_skin.gd): the stamina bar above the
# health ring while in the water or getting breath back, "DROWNING" pulsing when it is empty, the depth while under,
# and a blue-green wash over the view under water.
# Dependencies: game/ui_skin.gd.
extends Control

const UiSkin = preload("res://game/ui_skin.gd")

var _font: Font = ThemeDB.fallback_font
var _stamina := 1.0  # share 0..1
var _swimming := false
var _under := false
var _depth := 0.0
var _tint := Color(0.05, 0.3, 0.38)
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_state(share: float, swimming: bool, under: bool, depth: float, water: Color, delta: float) -> void:
	var changed := absf(share - _stamina) > 0.002 or swimming != _swimming or under != _under or absf(depth - _depth) > 0.05 or (share <= 0.0 and swimming)
	_stamina = share
	_swimming = swimming
	_under = under
	_depth = depth
	_tint = water
	_t += delta
	if changed:
		queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	if _under:
		draw_rect(Rect2(Vector2.ZERO, view), Color(_tint.darkened(0.2), 0.42))
	if not _swimming and _stamina >= 0.999:
		return
	var r := Rect2(Vector2(150.0, view.y - 112.0), Vector2(260.0, 40.0))
	UiSkin.panel(self, r, UiSkin.INK, UiSkin.EDGE, 8)
	var empty := _stamina <= 0.0
	var colour := UiSkin.BAD if _stamina < 0.25 else Color(0.45, 0.85, 1.0)
	draw_string(_font, r.position + Vector2(12, 16), "DROWNING" if empty else "STAMINA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(UiSkin.BAD, 0.55 + 0.45 * sin(_t * 9.0)) if empty else UiSkin.TEXT_DIM)
	if _under:
		var text := "%.1f m deep" % _depth
		draw_string(_font, Vector2(r.end.x - 12.0 - _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, r.position.y + 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiSkin.TEXT_DIM)
	UiSkin.bar(self, Rect2(r.position + Vector2(12, 24), Vector2(r.size.x - 24.0, 7)), _stamina, colour)
