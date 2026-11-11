# Purpose: the one look shared by everything the fantasy world puts on screen (HUD, spell box, panels, map): dark ink
# panels with a thin gold line and small corner marks, a book typeface taken from the system, parchment-coloured text
# with a soft shadow, slim framed bars, and one drawn sign per element (a drop, a flame, a stone, a gust) so elements
# are told apart by shape as well as colour.
# Dependencies: none (drawing helpers for any CanvasItem, and a Theme for Control-built panels).
extends RefCounted

const INK := Color(0.075, 0.06, 0.045, 0.86)
const INK_SOFT := Color(0.075, 0.06, 0.045, 0.55)
const PARCHMENT := Color(0.94, 0.89, 0.77)
const FADED := Color(0.94, 0.89, 0.77, 0.6)
const GOLD := Color(0.86, 0.71, 0.38)
const GOLD_DIM := Color(0.86, 0.71, 0.38, 0.4)
const SHADOW := Color(0, 0, 0, 0.6)

static var _font: Font
static var _theme: Theme


# A book face from the machine's own fonts (none is shipped); falls back to the engine's font.
static func font() -> Font:
	if _font == null:
		var face := SystemFont.new()
		face.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia", "Constantia", "Baskerville", "Liberation Serif", "DejaVu Serif", "Times New Roman", "serif"])
		face.allow_system_fallback = true
		_font = face
	return _font


# A dark panel with a gold hairline and a small mark in each corner.
static func frame(canvas: CanvasItem, rect: Rect2, fill: Color = INK) -> void:
	canvas.draw_rect(rect, fill)
	canvas.draw_rect(rect.grow(-2.0), GOLD_DIM, false, 1.0)
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		canvas.draw_rect(Rect2(corner - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), GOLD)


# Text with a soft shadow. `width` > 0 aligns inside that width starting at pos.x.
static func text(canvas: CanvasItem, pos: Vector2, words: String, points: int, color: Color = PARCHMENT, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	canvas.draw_string(font(), pos + Vector2(1.0, 1.0), words, align, width, points, Color(SHADOW, SHADOW.a * color.a))
	canvas.draw_string(font(), pos, words, align, width, points, color)


# Text that wraps inside `width` over at most `lines` lines.
static func paragraph(canvas: CanvasItem, pos: Vector2, words: String, points: int, color: Color, width: float, lines: int = 2) -> void:
	canvas.draw_multiline_string(font(), pos + Vector2(1.0, 1.0), words, HORIZONTAL_ALIGNMENT_LEFT, width, points, lines, Color(SHADOW, SHADOW.a * color.a))
	canvas.draw_multiline_string(font(), pos, words, HORIZONTAL_ALIGNMENT_LEFT, width, points, lines, color)


# A slim framed bar filled to `share` (0..1).
static func bar(canvas: CanvasItem, rect: Rect2, share: float, color: Color) -> void:
	canvas.draw_rect(rect, INK)
	canvas.draw_rect(Rect2(rect.position + Vector2(2.0, 2.0), Vector2((rect.size.x - 4.0) * clampf(share, 0.0, 1.0), rect.size.y - 4.0)), color)
	canvas.draw_rect(rect, GOLD_DIM, false, 1.0)


# A thin gold line with a small diamond in the middle.
static func rule(canvas: CanvasItem, from: Vector2, to: Vector2) -> void:
	canvas.draw_line(from, to, GOLD_DIM, 1.0)
	var mid := (from + to) * 0.5
	canvas.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -3), mid + Vector2(3, 0), mid + Vector2(0, 3), mid + Vector2(-3, 0)]), GOLD)


# The sign of one element inside a round stone: W a drop, F a flame, E a faceted rock, A two curling gusts.
static func element_sign(canvas: CanvasItem, letter: String, center: Vector2, radius: float, color: Color) -> void:
	canvas.draw_circle(center, radius, Color(color.r * 0.28, color.g * 0.28, color.b * 0.28, 0.95))
	canvas.draw_arc(center, radius, 0.0, TAU, 28, color, 2.0, true)
	var r := radius * 0.56
	match letter:
		"W":
			canvas.draw_circle(center + Vector2(0, r * 0.3), r * 0.62, color)
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.56, r * 0.1), center + Vector2(-r * 0.56, r * 0.1)]), color)
		"F":
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.75, r * 0.35), center + Vector2(r * 0.3, r), center + Vector2(-r * 0.3, r), center + Vector2(-r * 0.75, r * 0.35), center + Vector2(-r * 0.25, -r * 0.2)]), color)
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0.05 * r, -r * 0.2), center + Vector2(r * 0.35, r * 0.55), center + Vector2(0, r * 0.9), center + Vector2(-r * 0.35, r * 0.55)]), color.lerp(Color(1, 1, 0.8), 0.7))
		"E":
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(-r * 0.2, -r * 0.9), center + Vector2(r * 0.7, -r * 0.35), center + Vector2(r * 0.9, r * 0.5), center + Vector2(r * 0.1, r * 0.9), center + Vector2(-r * 0.85, r * 0.45), center + Vector2(-r * 0.75, -r * 0.3)]), color)
			canvas.draw_line(center + Vector2(-r * 0.2, -r * 0.9), center + Vector2(r * 0.1, r * 0.9), Color(0, 0, 0, 0.35), 1.5)
		"G":  # gravity: a dark heart with a ring falling into it
			canvas.draw_arc(center, r * 0.95, PI * 0.15, PI * 1.75, 16, color, 2.0, true)
			canvas.draw_arc(center, r * 0.55, PI * 1.1, PI * 2.6, 12, color.lerp(Color.WHITE, 0.35), 1.5, true)
			canvas.draw_circle(center, r * 0.26, color.lerp(Color.WHITE, 0.6))
		_:
			canvas.draw_arc(center + Vector2(-r * 0.15, -r * 0.3), r * 0.55, PI * 0.9, PI * 2.3, 12, color, 2.5, true)
			canvas.draw_arc(center + Vector2(r * 0.15, r * 0.4), r * 0.5, -PI * 0.1, PI * 1.3, 12, color, 2.5, true)


# The same look for panels built from Controls (game/fantasy_panel.gd).
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(INK, 0.94)
	panel.border_color = GOLD_DIM
	panel.set_border_width_all(1)
	panel.set_content_margin_all(18.0)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 12
	t.set_stylebox("panel", "PanelContainer", panel)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.16, 0.13, 0.09, 0.95) if state == "normal" else (Color(0.3, 0.24, 0.13, 0.95) if state in ["hover", "focus"] else (Color(0.4, 0.31, 0.15) if state == "pressed" else Color(0.12, 0.1, 0.08, 0.6)))
		box.border_color = GOLD if state in ["hover", "pressed", "focus"] else GOLD_DIM
		box.set_border_width_all(1)
		box.set_content_margin_all(7.0)
		box.content_margin_left = 14.0
		box.content_margin_right = 14.0
		t.set_stylebox(state, "Button", box)
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", FADED)
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	t.set_color("font_color", "ItemList", PARCHMENT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	var list := StyleBoxFlat.new()
	list.bg_color = Color(0.05, 0.04, 0.03, 0.6)
	list.border_color = GOLD_DIM
	list.set_border_width_all(1)
	list.set_content_margin_all(6.0)
	t.set_stylebox("panel", "ItemList", list)
	var chosen := StyleBoxFlat.new()
	chosen.bg_color = Color(0.4, 0.31, 0.15, 0.9)
	t.set_stylebox("selected", "ItemList", chosen)
	t.set_stylebox("selected_focus", "ItemList", chosen)
	_theme = t
	return t
