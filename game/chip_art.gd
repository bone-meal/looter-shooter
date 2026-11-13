# Purpose: the casino's currency look (Q32: "coins" are shown as CHIPS everywhere; the save key stays "coins"):
# draws a poker chip, and wraps a label with a chip icon in front of it.
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
