# Purpose: developer picture of every emblem in data/achievements.json with its name, 12 to a row. Saves
# tools/shots/emblems.png and quits. Needs a display (not headless); the painted ones need their pictures imported.
# Dependencies: game/emblem_art.gd.
extends Control

const EmblemArt = preload("res://game/emblem_art.gd")
const CELL := 104.0

var _defs: Array = []


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))
	for id: String in data["emblems"]:
		_defs.append(data["emblems"][id])
	var rows := ceili(float(_defs.size()) / 12.0)
	get_window().size = Vector2i(int(CELL * 12.0), int(CELL * float(rows)))
	size = Vector2(get_window().size)
	queue_redraw()
	for _f in 6:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/shots/emblems.png"))
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.11, 0.14))
	var font := ThemeDB.fallback_font
	for i in _defs.size():
		var at := Vector2(float(i % 12), float(floori(float(i) / 12.0))) * CELL
		EmblemArt.draw_def(self, _defs[i], at + Vector2(CELL * 0.5, 44), 38.0)
		draw_string(font, at + Vector2(2, CELL - 8), String(_defs[i]["name"]), HORIZONTAL_ALIGNMENT_CENTER, CELL - 4, 11, Color(1, 1, 1, 0.8))
