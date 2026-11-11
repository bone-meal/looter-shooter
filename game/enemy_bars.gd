# Purpose: health bars drawn on screen above each enemy's head (green > yellow > red as health drops).
# Dependencies: game/wave_director.gd (source of the enemy list). Bars shrink with distance but stay readable.
extends Control

const BAR_BACK := Color(0, 0, 0, 0.7)
const GOOD := Color(0.3, 0.85, 0.4)
const WARN := Color(0.95, 0.8, 0.25)
const BAD := Color(0.95, 0.3, 0.3)
const HEIGHT_OFFSET := 0.45

var source: Node3D  # the wave director; set after it exists


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or source == null:
		return
	for e in source.enemy_list():
		if not is_instance_valid(e):
			continue
		var top: Vector3 = e.global_position + Vector3(0, e.head_height() + HEIGHT_OFFSET, 0)
		if cam.is_position_behind(top):
			continue
		var p := cam.unproject_position(top)
		var width := clampf(300.0 / cam.global_position.distance_to(top), 26.0, 80.0)
		var ratio: float = clampf(e.health.hp / e.health.max_hp, 0.0, 1.0)
		var color := GOOD if ratio > 0.6 else (WARN if ratio > 0.3 else BAD)
		draw_rect(Rect2(p.x - width * 0.5 - 1.0, p.y - 4.0, width + 2.0, 8.0), BAR_BACK)
		draw_rect(Rect2(p.x - width * 0.5, p.y - 3.0, width * ratio, 6.0), color)
