# Purpose: draws chalk tally marks (1-5) and chalk numbers on a CanvasItem: the round counter of the HUD.
# Every stroke is drawn three times, slightly apart, so it looks rubbed on instead of ruled.
# Dependencies: none.
extends RefCounted

const DIGIT_W := 0.62  # width of one digit, in heights
const TALLY_GAP := 0.26  # distance between two tally strokes, in heights
const STROKE := 0.085  # stroke width, in heights

# One polyline per digit, in a box 1 wide and 1.6 tall (y down).
const DIGITS := [
	[Vector2(0.5, 0.02), Vector2(0.16, 0.3), Vector2(0.1, 0.9), Vector2(0.3, 1.5), Vector2(0.6, 1.58), Vector2(0.86, 1.2), Vector2(0.9, 0.5), Vector2(0.7, 0.08), Vector2(0.46, 0.04)],
	[Vector2(0.2, 0.42), Vector2(0.55, 0.02), Vector2(0.5, 1.6)],
	[Vector2(0.08, 0.4), Vector2(0.32, 0.06), Vector2(0.72, 0.08), Vector2(0.88, 0.48), Vector2(0.06, 1.58), Vector2(0.95, 1.55)],
	[Vector2(0.1, 0.14), Vector2(0.68, 0.04), Vector2(0.88, 0.4), Vector2(0.44, 0.76), Vector2(0.9, 1.1), Vector2(0.7, 1.52), Vector2(0.1, 1.5)],
	[Vector2(0.74, 1.6), Vector2(0.78, 0.02), Vector2(0.06, 1.06), Vector2(0.98, 1.02)],
	[Vector2(0.9, 0.04), Vector2(0.22, 0.02), Vector2(0.12, 0.7), Vector2(0.6, 0.62), Vector2(0.9, 1.0), Vector2(0.7, 1.52), Vector2(0.1, 1.5)],
	[Vector2(0.8, 0.04), Vector2(0.3, 0.5), Vector2(0.1, 1.1), Vector2(0.35, 1.56), Vector2(0.75, 1.5), Vector2(0.9, 1.1), Vector2(0.6, 0.8), Vector2(0.16, 1.0)],
	[Vector2(0.05, 0.06), Vector2(0.95, 0.02), Vector2(0.36, 1.6)],
	[Vector2(0.5, 0.76), Vector2(0.15, 0.4), Vector2(0.5, 0.02), Vector2(0.85, 0.4), Vector2(0.5, 0.76), Vector2(0.1, 1.2), Vector2(0.5, 1.6), Vector2(0.9, 1.2), Vector2(0.5, 0.76)],
	[Vector2(0.85, 0.6), Vector2(0.5, 0.8), Vector2(0.15, 0.45), Vector2(0.45, 0.03), Vector2(0.85, 0.3), Vector2(0.85, 0.9), Vector2(0.6, 1.6), Vector2(0.2, 1.5)],
]

static var _lines: Array[PackedVector2Array] = []  # the digits at _lines_height pixels, built when that changes
static var _lines_height := 0.0


# Tally marks for `count` (1 to 5; the fifth is the slash through the other four). `origin` is the top left corner,
# `height` the height of a stroke in pixels. Returns the width used.
static func tally(canvas: CanvasItem, origin: Vector2, count: int, height: float, color: Color) -> float:
	var gap := height * TALLY_GAP
	for i in mini(count, 4):
		var lean := height * (0.05 if i % 2 == 0 else -0.03)  # no two strokes quite parallel
		_stroke(canvas, origin + Vector2(gap * (i + 0.5) + lean, height * (0.03 * (i % 3))), origin + Vector2(gap * (i + 0.5) - lean, height), height * STROKE, color)
	if count >= 5:
		_stroke(canvas, origin + Vector2(-gap * 0.2, height * 0.82), origin + Vector2(gap * 4.3, height * 0.18), height * STROKE, color)
	return gap * 4.5


# A whole number in chalk. Returns the width used.
static func number(canvas: CanvasItem, origin: Vector2, value: int, height: float, color: Color) -> float:
	if _lines_height != height:  # (scaling with a draw transform instead would smear the smoothed edges)
		_lines_height = height
		_lines.clear()
		for digit: Array in DIGITS:
			var line := PackedVector2Array()
			for p: Vector2 in digit:
				line.append(Vector2(p.x * DIGIT_W, p.y / 1.6) * height)
			_lines.append(line)
	var x := 0.0
	var text := str(maxi(value, 0))
	for i in text.length():
		var line := _lines[text.unicode_at(i) - 48]
		for pass_index in 3:
			canvas.draw_set_transform(origin + Vector2(x + float(pass_index - 1) * 1.6, float(1 - pass_index) * 1.2))
			canvas.draw_polyline(line, color if pass_index == 1 else Color(color, color.a * 0.4), height * STROKE * (1.0 if pass_index == 1 else 0.6), true)
		x += height * (DIGIT_W + 0.14)
	canvas.draw_set_transform(Vector2.ZERO)
	return x


static func _stroke(canvas: CanvasItem, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	canvas.draw_line(from, to, color, width, true)
	canvas.draw_line(from + Vector2(1.6, -1.2), to + Vector2(1.8, 0.6), Color(color, color.a * 0.4), width * 0.6, true)
	canvas.draw_line(from + Vector2(-1.7, 0.9), to + Vector2(-1.4, -1.0), Color(color, color.a * 0.4), width * 0.6, true)
