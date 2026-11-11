# Purpose: draws one icon of the game's icon sheet into any CanvasItem. A shape has two layers: one takes the colour
# it is asked for (an item's own colour, a tier colour ...), the other keeps its own colours (wooden handles, glass,
# eyes). The sheet and the list of shapes are made by tools/make_icons.py.
# Dependencies: assets/ui/icons_tint.png, assets/ui/icons_ink.png, data/icons.json.
extends RefCounted

static var _cells := {}
static var _columns := 12
static var _cell := 64.0
static var _tint: Texture2D
static var _ink: Texture2D


static func _load() -> void:
	if _tint != null:
		return
	var sheet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/icons.json"))
	_cells = sheet["shapes"]
	_columns = int(sheet["columns"])
	_cell = float(sheet["cell"])
	_tint = load("res://assets/ui/icons_tint.png")
	_ink = load("res://assets/ui/icons_ink.png")


static func has(shape: String) -> bool:
	_load()
	return _cells.has(shape)


# Draws `shape` as large as fits in `rect`, centred. `alpha` below 1 fades it (something locked or missing).
static func draw(canvas: CanvasItem, shape: String, rect: Rect2, color: Color = Color.WHITE, alpha: float = 1.0) -> void:
	_load()
	if not _cells.has(shape):
		return
	var index := int(_cells[shape])
	var from := Rect2(float(index % _columns) * _cell, floorf(float(index) / float(_columns)) * _cell, _cell, _cell)
	var side := minf(rect.size.x, rect.size.y)
	var box := Rect2(rect.position + (rect.size - Vector2(side, side)) * 0.5, Vector2(side, side))
	canvas.draw_texture_rect_region(_tint, box, from, Color(color.r, color.g, color.b, alpha))
	canvas.draw_texture_rect_region(_ink, box, from, Color(1, 1, 1, alpha))
