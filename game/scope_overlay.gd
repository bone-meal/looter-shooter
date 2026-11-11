# Purpose: what the player sees when aiming THROUGH something (the gun model is hidden then): the sniper scope (black
# outside a circle, thin crosshair) or one of the optic parts: red dot (a tube rim and a red dot), holo (a window
# frame, ring and dot), ACOG (a smaller dark tube with a chevron). Faded in as the player finishes aiming.
# Dependencies: none. game/game_session.gd sets `kind` and `amount` (0..1) every frame.
extends Control

const SHOW_FROM := 0.85   # the view appears once aiming is this far along
const RADIUS_FRACTION := 0.4
const SEGMENTS := 64
const RETICLE := Color(1.0, 0.16, 0.1)
const RIM := Color(0.04, 0.04, 0.05)

var kind := "scope":  # "scope", "red_dot", "holo", "acog" (see game/player.gd sight_kind)
	set(value):
		if value != kind and value != "":
			kind = value
			queue_redraw()
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
	var unit := minf(view_size.x, view_size.y)
	match kind:
		"red_dot":
			_outside(center, unit * 0.34, view_size, Color(0, 0, 0, 0.3 * alpha))
			draw_arc(center, unit * 0.34, 0.0, TAU, SEGMENTS, Color(RIM, alpha), unit * 0.03, true)
			draw_circle(center, unit * 0.014, Color(RETICLE, 0.25 * alpha))
			draw_circle(center, unit * 0.006, Color(RETICLE, alpha))
		"holo":
			var half := Vector2(unit * 0.3, unit * 0.23)
			var edge := unit * 0.022
			draw_rect(Rect2(Vector2.ZERO, Vector2(view_size.x, center.y - half.y)), Color(0, 0, 0, 0.3 * alpha))
			draw_rect(Rect2(Vector2(0, center.y + half.y), Vector2(view_size.x, view_size.y)), Color(0, 0, 0, 0.3 * alpha))
			draw_rect(Rect2(Vector2(0, center.y - half.y), Vector2(center.x - half.x, half.y * 2.0)), Color(0, 0, 0, 0.3 * alpha))
			draw_rect(Rect2(Vector2(center.x + half.x, center.y - half.y), Vector2(view_size.x, half.y * 2.0)), Color(0, 0, 0, 0.3 * alpha))
			draw_rect(Rect2(center - half - Vector2(edge, edge) * 0.5, half * 2.0 + Vector2(edge, edge)), Color(RIM, alpha), false, edge)
			draw_rect(Rect2(center - half, half * 2.0), Color(0.5, 0.8, 1.0, 0.05 * alpha))
			draw_arc(center, unit * 0.045, 0.0, TAU, 40, Color(RETICLE, 0.9 * alpha), 1.5, true)
			for k in 4:  # four ticks on the ring
				var way := Vector2.from_angle(float(k) * PI * 0.5)
				draw_line(center + way * unit * 0.045, center + way * unit * 0.06, Color(RETICLE, 0.9 * alpha), 1.5, true)
			draw_circle(center, unit * 0.004, Color(RETICLE, alpha))
		"acog":
			_outside(center, unit * 0.3, view_size, Color(0, 0, 0, 0.82 * alpha))
			draw_arc(center, unit * 0.3, 0.0, TAU, SEGMENTS, Color(RIM, alpha), unit * 0.02, true)
			var tip := unit * 0.022
			draw_polyline(PackedVector2Array([center + Vector2(-tip, tip * 1.3), center, center + Vector2(tip, tip * 1.3)]), Color(RETICLE, alpha), 2.0, true)
			draw_line(center + Vector2(0, tip * 1.6), center + Vector2(0, unit * 0.2), Color(RIM, 0.8 * alpha), 1.0)
			for k in 3:  # range marks under the chevron
				var down := tip * 2.4 + float(k) * tip * 1.5
				draw_line(center + Vector2(-tip * (0.9 - 0.2 * float(k)), down), center + Vector2(tip * (0.9 - 0.2 * float(k)), down), Color(RIM, 0.8 * alpha), 1.0)
		_:
			var inner := unit * RADIUS_FRACTION
			_outside(center, inner, view_size, Color(0, 0, 0, alpha))
			draw_line(center - Vector2(inner, 0), center + Vector2(inner, 0), Color(0, 0, 0, alpha), 1.0)
			draw_line(center - Vector2(0, inner), center + Vector2(0, inner), Color(0, 0, 0, alpha), 1.0)


# Fills everything outside a circle.
func _outside(center: Vector2, inner: float, view_size: Vector2, color: Color) -> void:
	var outer := view_size.length() * 0.5 + 10.0
	for i in SEGMENTS:
		var d0 := Vector2.from_angle(TAU * float(i) / float(SEGMENTS))
		var d1 := Vector2.from_angle(TAU * float(i + 1) / float(SEGMENTS))
		draw_colored_polygon(PackedVector2Array([center + d0 * inner, center + d1 * inner, center + d1 * outer, center + d0 * outer]), color)
