# Purpose: the game's shared look for menus drawn in code (locked 2026-11-14: real game UI, not plain text and boxes):
# rounded panels, section headers, item slots with a rarity glow, pill tabs and buttons, key caps. Styles are made once
# and kept (no new objects every frame).
# Dependencies: none.
extends RefCounted

const INK := Color(0.055, 0.06, 0.085, 0.985)  # panel fill
const INK_DEEP := Color(0.03, 0.035, 0.05, 0.96)
const EDGE := Color(1, 1, 1, 0.1)
const TEXT := Color(0.94, 0.95, 0.98)
const TEXT_DIM := Color(0.62, 0.66, 0.74)
const ACCENT := Color(1.0, 0.78, 0.32)  # gold: headers, chosen tabs
const GOOD := Color(0.45, 1.0, 0.55)
const BAD := Color(1.0, 0.45, 0.4)

static var _boxes := {}  # key -> StyleBoxFlat


static func _box(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var key := Vector4i(fill.to_rgba32(), border.to_rgba32(), radius, width)  # numbers, not text: this runs for every box drawn
	if not _boxes.has(key):
		if _boxes.size() > 300:  # animated rarity colours (rainbow, pony) make new keys: start the store over now and then
			_boxes.clear()
		var b := StyleBoxFlat.new()
		b.bg_color = fill
		b.border_color = border
		b.set_border_width_all(width)
		b.set_corner_radius_all(radius)
		b.corner_detail = 6
		b.anti_aliasing = true
		_boxes[key] = b
	return _boxes[key]


# A rounded panel with a soft drop shadow.
static func panel(canvas: CanvasItem, r: Rect2, fill: Color = INK, border: Color = EDGE, radius: int = 12) -> void:
	canvas.draw_style_box(_box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), radius + 4, 0), r.grow(6.0))
	canvas.draw_style_box(_box(fill, border, radius, 1), r)


# A section title with a thin gold line under it running to the right edge; returns the y under it.
static func header(canvas: CanvasItem, font: Font, at: Vector2, width: float, text: String, note: String = "") -> float:
	canvas.draw_string(font, at + Vector2(0, 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ACCENT)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	if note != "":
		canvas.draw_string(font, at + Vector2(tw + 12.0, 19), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)
	canvas.draw_line(at + Vector2(0, 30), at + Vector2(width, 30), Color(ACCENT, 0.35), 1.0)
	return at.y + 40.0


# An outline only (the inventory's hover and chosen marks, drawn on a layer above the slots).
static func outline(canvas: CanvasItem, r: Rect2, colour: Color, radius: int = 8, width: int = 2) -> void:
	canvas.draw_style_box(_box(Color(0, 0, 0, 0), colour, radius, width), r)


# An item slot: dark rounded square, a rarity glow rising from the bottom, a border in the rarity colour.
# state: "" | "hover" | "fits" (what the mouse carries can go here) | "chosen".
static func slot(canvas: CanvasItem, r: Rect2, tint: Color, filled: bool, state: String) -> void:
	canvas.draw_style_box(_box(INK_DEEP, Color(1, 1, 1, 0.08), 8, 1), r)
	if filled and tint.a > 0.0:
		var top := Color(tint, 0.0)
		var low := Color(tint, 0.32)
		var inner := r.grow(-2.0)
		canvas.draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]),
			PackedColorArray([top, top, low, low]))
		canvas.draw_style_box(_box(Color(0, 0, 0, 0), Color(tint, 0.85), 8, 2), r)
	match state:
		"hover":
			canvas.draw_style_box(_box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.9), 8, 2), r)
		"fits":
			canvas.draw_style_box(_box(Color(GOOD, 0.08), Color(GOOD, 0.95), 8, 2), r)
		"chosen":
			canvas.draw_style_box(_box(Color(0, 0, 0, 0), Color(ACCENT, 0.95), 8, 2), r)


# A pill tab or button; returns nothing (the caller keeps the rect for clicks).
static func pill(canvas: CanvasItem, font: Font, r: Rect2, text: String, active: bool, hovered: bool, size_px: int = 15) -> void:
	var fill := Color(ACCENT, 0.9) if active else (Color(1, 1, 1, 0.14) if hovered else Color(1, 1, 1, 0.06))
	canvas.draw_style_box(_box(fill, Color(1, 1, 1, 0.18), int(r.size.y * 0.5), 1), r)
	var colour := Color(0.08, 0.06, 0.02) if active else TEXT
	canvas.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + size_px * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size_px, colour)


# A key label in a small key cap ("Q", "F", "Esc").
static func key_cap(canvas: CanvasItem, font: Font, at: Vector2, key: String) -> float:
	var w := maxf(font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0, 22.0)
	canvas.draw_style_box(_box(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.35), 4, 1), Rect2(at, Vector2(w, 20)))
	canvas.draw_string(font, at + Vector2(0, 15), key, HORIZONTAL_ALIGNMENT_CENTER, w, 12, TEXT)
	return w


# A thin bar filled to `share` (0..1).
static func bar(canvas: CanvasItem, r: Rect2, share: float, colour: Color) -> void:
	canvas.draw_style_box(_box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 2, 0), r)
	if share > 0.0:
		canvas.draw_style_box(_box(colour, Color(0, 0, 0, 0), 2, 0), Rect2(r.position, Vector2(r.size.x * clampf(share, 0.0, 1.0), r.size.y)))


static var _theme: Theme


# (polish1 item 81) The skin as a Theme for menus built from controls (the player card's tabs, buttons, lists, text
# fields): rounded dark panels, pill buttons and tabs (gold when chosen), bigger text. Made once.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	for kind: String in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", kind, _pad(_box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.16), 18, 1), 16, 7))
		t.set_stylebox("hover", kind, _pad(_box(Color(1, 1, 1, 0.15), Color(1, 1, 1, 0.45), 18, 1), 16, 7))
		t.set_stylebox("pressed", kind, _pad(_box(Color(ACCENT, 0.9), Color(ACCENT, 1.0), 18, 1), 16, 7))
		t.set_stylebox("hover_pressed", kind, _pad(_box(Color(ACCENT, 1.0), Color(1, 1, 1, 0.6), 18, 1), 16, 7))
		t.set_stylebox("disabled", kind, _pad(_box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06), 18, 1), 16, 7))
		t.set_stylebox("focus", kind, _box(Color(0, 0, 0, 0), Color(ACCENT, 0.6), 18, 1))
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_pressed_color", kind, Color(0.08, 0.06, 0.02))
		t.set_color("font_hover_pressed_color", kind, Color(0.08, 0.06, 0.02))
		t.set_color("font_disabled_color", kind, Color(TEXT_DIM, 0.5))
	t.set_stylebox("tab_selected", "TabContainer", _pad(_box(Color(ACCENT, 0.92), Color(ACCENT, 1.0), 16, 1), 20, 8))
	t.set_stylebox("tab_hovered", "TabContainer", _pad(_box(Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.4), 16, 1), 20, 8))
	t.set_stylebox("tab_unselected", "TabContainer", _pad(_box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12), 16, 1), 20, 8))
	t.set_stylebox("tab_disabled", "TabContainer", _pad(_box(Color(1, 1, 1, 0.02), Color(0, 0, 0, 0), 16, 1), 20, 8))
	t.set_stylebox("panel", "TabContainer", _pad(_box(INK, EDGE, 14, 1), 18, 16))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", Color(0.08, 0.06, 0.02))
	t.set_color("font_unselected_color", "TabContainer", TEXT)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	t.set_constant("side_margin", "TabContainer", 0)
	t.set_font_size("font_size", "TabContainer", 19)
	t.set_stylebox("panel", "PanelContainer", _pad(_box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 12, 1), 14, 10))
	t.set_stylebox("panel", "Panel", _box(INK, EDGE, 12, 1))
	t.set_stylebox("normal", "LineEdit", _pad(_box(INK_DEEP, Color(1, 1, 1, 0.2), 10, 1), 12, 8))
	t.set_stylebox("focus", "LineEdit", _pad(_box(INK_DEEP, Color(ACCENT, 0.9), 10, 2), 12, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PopupMenu", _pad(_box(INK, Color(ACCENT, 0.5), 10, 1), 8, 8))
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.85), Color(0, 0, 0, 0), 6, 0))
	t.set_color("font_hover_color", "PopupMenu", Color(0.08, 0.06, 0.02))
	t.set_stylebox("panel", "TooltipPanel", _pad(_box(INK, Color(ACCENT, 0.6), 8, 1), 10, 6))
	t.set_stylebox("scroll", "VScrollBar", _box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 4, 0))
	t.set_stylebox("grabber", "VScrollBar", _box(Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 4, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(ACCENT, 0.7), Color(0, 0, 0, 0), 4, 0))
	_theme = t
	return t


static func _pad(box: StyleBoxFlat, x: float, y: float) -> StyleBoxFlat:
	var b := box.duplicate() as StyleBoxFlat
	b.content_margin_left = x
	b.content_margin_right = x
	b.content_margin_top = y
	b.content_margin_bottom = y
	return b
