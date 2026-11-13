# Purpose: the Combat Report page of the player card: the character's portrait on the left, and on the right every
# record in titled sections (combat, kills by enemy and by weapon, the islands, the colosseum, Aurelind, time and
# travel). Draws only: the session hands in {"look": appearance, "sections": [{"title", "rows": [[label, value]]}]}
# (built by game/combat_report.gd).
# Dependencies: game/portrait_view.gd.
extends HBoxContainer

const PortraitView = preload("res://game/portrait_view.gd")

const HEAD := Color(1.0, 0.82, 0.4)
const LABEL := Color(0.78, 0.82, 0.9)
const VALUE := Color(1, 1, 1)


func build(report: Dictionary) -> void:
	add_theme_constant_override("separation", 22)
	var left := VBoxContainer.new()
	add_child(left)
	var picture := PortraitView.new()
	left.add_child(picture)
	picture.show_look(report.get("look", {}))
	for line: String in report.get("under_portrait", []):
		left.add_child(_text(line, 15, HEAD))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)
	for section: Dictionary in report.get("sections", []):
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(262, 0)
		box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(box)
		box.add_child(_text(String(section["title"]).to_upper(), 16, HEAD))
		var rows: Array = section.get("rows", [])
		if rows.is_empty():
			box.add_child(_text("Nothing yet.", 13, LABEL))
		for row: Array in rows:
			var line := HBoxContainer.new()
			box.add_child(line)
			var caption := _text(String(row[0]), 13, LABEL)
			caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(caption)
			line.add_child(_text(String(row[1]), 13, VALUE))


func _text(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label
