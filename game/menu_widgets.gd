# Purpose: tiny helpers shared by the menus (full-screen backdrop, centered column, title, button).
# Dependencies: none.
extends RefCounted


static func fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func backdrop(parent: Control, color: Color) -> void:
	var rect := ColorRect.new()
	rect.color = color
	parent.add_child(rect)
	fill(rect)


static func centered_column(parent: Control, width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	parent.add_child(center)
	fill(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	return box


static func title(box: Container, text: String, font_size: int = 32) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	box.add_child(label)


static func button(box: Container, text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(on_press)
	box.add_child(b)
