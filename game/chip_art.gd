# Purpose: the casino's currency look (Q32: "coins" are shown as CHIPS everywhere; the save key stays "coins"):
# draws a poker chip, and wraps a label with a chip icon in front of it. (polish1 C5) Chips of a value in that value's
# colour with the number on them, and a stack of chips for an amount (the casino tables' bets).
# Dependencies: none.
extends RefCounted

const RIM := Color(0.82, 0.12, 0.16)
const STRIPE := Color(0.97, 0.95, 0.9)
const CENTRE := Color(0.62, 0.07, 0.1)


# A poker chip of radius r at `center` on any CanvasItem.
static func draw(ci: CanvasItem, center: Vector2, r: float) -> void:
	Icon.paint(ci, center, r)


# A little Control that is just a chip.
class Icon extends Control:
	var radius := 11.0

	func _init(r := 11.0) -> void:
		radius = r
		custom_minimum_size = Vector2(r * 2.0 + 4.0, r * 2.0 + 4.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		paint(self, size * 0.5, radius)

	static func paint(ci: CanvasItem, center: Vector2, r: float) -> void:
		ci.draw_circle(center, r, RIM)
		for i in 6:  # the edge stripes
			var a := float(i) * TAU / 6.0
			ci.draw_arc(center, r * 0.82, a - 0.18, a + 0.18, 4, STRIPE, maxf(r * 0.32, 2.0), true)
		ci.draw_circle(center, r * 0.58, STRIPE)
		ci.draw_circle(center, r * 0.48, CENTRE)
		ci.draw_arc(center, r * 0.36, 0.0, TAU, 16, STRIPE, maxf(r * 0.08, 1.0), true)
		ci.draw_arc(center, r, 0.0, TAU, 24, Color(0, 0, 0, 0.45), maxf(r * 0.08, 1.0), true)


# A row: chip icon, then the label (for the casino screens' money lines).
static func row(label: Control, r := 11.0) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(Icon.new(r))
	box.add_child(label)
	return box


# (polish1 C5) The colour of a chip of that value (casino style: 1 white, 5 red, 10 blue, 25 green, 50 orange,
# 100 black, 500 purple, 1000 yellow).
static func value_colour(value: int) -> Color:
	if value >= 1000:
		return Color(0.95, 0.78, 0.15)
	if value >= 500:
		return Color(0.52, 0.22, 0.75)
	if value >= 100:
		return Color(0.12, 0.12, 0.14)
	if value >= 50:
		return Color(0.95, 0.5, 0.12)
	if value >= 20:
		return Color(0.12, 0.6, 0.28)
	if value >= 10:
		return Color(0.15, 0.35, 0.85)
	if value >= 2:
		return Color(0.82, 0.12, 0.16)
	return Color(0.92, 0.92, 0.9)


# A chip of `value` (its colour, the number in the middle); `font` may be null (no number).
static func draw_value(ci: CanvasItem, center: Vector2, r: float, value: int, font: Font = null) -> void:
	var rim := value_colour(value)
	var stripe := Color(0.97, 0.95, 0.9) if rim.get_luminance() < 0.8 else Color(0.2, 0.35, 0.8)
	ci.draw_circle(center + Vector2(0, r * 0.12), r, Color(0, 0, 0, 0.35))
	ci.draw_circle(center, r, rim)
	for i in 6:
		var a := float(i) * TAU / 6.0
		ci.draw_arc(center, r * 0.82, a - 0.18, a + 0.18, 4, stripe, maxf(r * 0.32, 2.0), true)
	ci.draw_circle(center, r * 0.6, rim.lightened(0.12))
	ci.draw_arc(center, r * 0.6, 0.0, TAU, 20, stripe, maxf(r * 0.07, 1.0), true)
	ci.draw_arc(center, r, 0.0, TAU, 24, Color(0, 0, 0, 0.5), maxf(r * 0.08, 1.0), true)
	if font != null:
		var text := str(value) if value < 1000 else "%dk" % floori(value / 1000.0)
		var fs := maxi(int(r * (0.8 if text.length() <= 2 else 0.62)), 8)
		var ink := Color(1, 1, 1) if rim.get_luminance() < 0.6 else Color(0.08, 0.08, 0.1)
		ci.draw_string(font, center + Vector2(-r, fs * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, ink)


# A stack of chips worth `amount` standing on `base` (bottom centre), biggest chips at the bottom, at most `most`
# chips drawn, the amount written beside it when `font` is given.
static func draw_stack(ci: CanvasItem, base: Vector2, r: float, amount: int, values: Array, font: Font = null, most: int = 6) -> void:
	var left := amount
	var chips: Array[int] = []
	var sorted := values.duplicate()
	sorted.sort()
	sorted.reverse()
	for v: Variant in sorted:
		while left >= int(v) and chips.size() < most:
			chips.append(int(v))
			left -= int(v)
	if chips.is_empty():
		chips.append(int(sorted[sorted.size() - 1]))
	for i in chips.size():
		draw_value(ci, base - Vector2(0, float(i) * r * 0.32), r, chips[i], font if i == chips.size() - 1 else null)
	if font != null and chips.size() > 1:
		var label := str(amount)
		var top := base - Vector2(0, float(chips.size() - 1) * r * 0.32)
		ci.draw_string_outline(font, top + Vector2(r * 0.9, -r * 0.6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(r * 0.85), 10), 4, Color(0, 0, 0, 0.85))
		ci.draw_string(font, top + Vector2(r * 0.9, -r * 0.6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(r * 0.85), 10), Color(1.0, 0.85, 0.35))
