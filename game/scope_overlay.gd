# Purpose: sniper scope view: black outside a circle plus a thin crosshair, faded in as the player finishes aiming.
# Dependencies: none. game/game_session.gd sets `amount` (0..1) every frame.
extends Control

const SHOW_FROM := 0.85   # scope appears once aiming is this far along
const RADIUS_FRACTION := 0.4
const SEGMENTS := 64

var amount := 0.0:
	set(value):
		if is_equal_approx(value, amount):
			return
		amount = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var alpha := clampf((amount - SHOW_FROM) / (1.0 - SHOW_FROM), 0.0, 1.0)
	if alpha <= 0.0:
		return
	var view_size := get_viewport_rect().size
	var center := view_size * 0.5
	var inner := minf(view_size.x, view_size.y) * RADIUS_FRACTION
	var outer := view_size.length() * 0.5 + 10.0
	var black := Color(0, 0, 0, alpha)
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var d0 := Vector2.from_angle(a0)
		var d1 := Vector2.from_angle(a1)
		draw_colored_polygon(PackedVector2Array([center + d0 * inner, center + d1 * inner, center + d1 * outer, center + d0 * outer]), black)
	draw_line(center - Vector2(inner, 0), center + Vector2(inner, 0), black, 1.0)
	draw_line(center - Vector2(0, inner), center + Vector2(0, inner), black, 1.0)
