# Purpose: on-screen 8-slot emote wheel shown while H is held; highlights the slot picked by digits, scroll or (first person) mouse direction.
# Dependencies: game/dance_poses.gd (names).
extends CanvasLayer

const DancePoses = preload("res://game/dance_poses.gd")

var selected := -1
var _labels: Array[Label] = []
var _root := Control.new()


func _ready() -> void:
	layer = 7
	visible = false
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	for i in DancePoses.DANCES.size():
		var l := Label.new()
		l.text = "%d  %s" % [i + 1, DancePoses.DANCES[i]["name"]]
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(l)
		_labels.append(l)
	_layout()
	get_viewport().size_changed.connect(_layout)


func show_wheel() -> void:
	select(-1)
	visible = true


func hide_wheel() -> void:
	visible = false


# Highlights slot `index` (-1 = none).
func select(index: int) -> void:
	selected = index
	for i in _labels.size():
		_labels[i].add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if i == index else Color(0.85, 0.85, 0.9))


# Picks the slot a mouse direction points at (0 = up, clockwise).
func select_by_direction(dir: Vector2) -> void:
	if dir.length() < 30.0:
		return
	var angle := fposmod(atan2(dir.x, -dir.y), TAU)
	select(int(roundf(angle / (TAU / float(_labels.size())))) % _labels.size())


func _layout() -> void:
	var center := get_viewport().get_visible_rect().size * 0.5
	for i in _labels.size():
		var a := TAU * float(i) / float(_labels.size())
		var size := _labels[i].get_minimum_size()
		_labels[i].position = center + Vector2(sin(a), -cos(a)) * 190.0 - size * 0.5
