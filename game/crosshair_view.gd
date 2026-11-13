# Purpose: draws one crosshair style in the middle of its rectangle: the HUD crosshair (full screen) and the pictures
# in Settings > Crosshair (small boxes). Lines, centre dot and ring, each under a dark outline.
# Dependencies: core/crosshair_style.gd (the style dictionary and its colour).
extends Control

const CrosshairStyle = preload("res://core/crosshair_style.gd")

const DIRECTIONS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]  # arms bits 1, 2, 4, 8
const OUTLINE := Color(0, 0, 0)

var style := {}
var zoom := 0.0  # 0 = scale with the window height (1080 lines = 1); else a fixed scale (menu pictures)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_style(new_style: Dictionary) -> void:
	style = new_style
	queue_redraw()


func _draw() -> void:
	if style.is_empty():
		return
	var k := zoom if zoom > 0.0 else get_viewport_rect().size.y / 1080.0
	var c := (size * 0.5).floor()
	var col := CrosshairStyle.new().color_of(style)
	var edge := float(style.get("outline", 0.0)) * k
	var dark := Color(OUTLINE, col.a * 0.85)
	var thick := maxf(float(style.get("thickness", 2.0)) * k, 1.0)
	var length := float(style.get("length", 0.0)) * k
	var gap := float(style.get("gap", 0.0)) * k
	var turn := deg_to_rad(float(style.get("angle", 0.0)))
	var arms := int(style.get("arms", 15))
	var ring := float(style.get("ring", 0.0)) * k
	var ring_width := maxf(float(style.get("ring_width", 1.0)) * k, 1.0)
	var dot := float(style.get("dot", 0.0)) * k
	for layer in 2:  # outlines first, then the colour over them
		var paint := dark if layer == 0 else col
		var grow := edge if layer == 0 else 0.0
		if layer == 0 and edge <= 0.0:
			continue
		if ring > 0.0:
			draw_arc(c, ring, 0.0, TAU, maxi(24, int(ring * 1.5)), paint, ring_width + grow * 2.0, true)
		if length > 0.0:
			for bit in 4:
				if arms & (1 << bit) == 0:
					continue
				var way: Vector2 = (DIRECTIONS[bit] as Vector2).rotated(turn)
				_bar(c + way * (gap - grow), c + way * (gap + length + grow), thick + grow * 2.0, paint)
		if dot > 0.0:
			var half := dot * 0.5 + grow
			draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), paint)


# A straight bar of the given width between two points (a rectangle, so the ends are square like the classic lines).
func _bar(from: Vector2, to: Vector2, width: float, paint: Color) -> void:
	var along := (to - from)
	if along.length() < 0.01:
		return
	var side := along.normalized().orthogonal() * width * 0.5
	draw_colored_polygon(PackedVector2Array([from + side, to + side, to - side, from - side]), paint)
