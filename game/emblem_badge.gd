# Purpose: a small billboard sprite showing a player-card emblem above another player's head (the emblem is drawn once into a tiny SubViewport texture).
# Dependencies: game/emblem_art.gd. Call show_emblem() with one entry of data/achievements.json "emblems".
extends Sprite3D

const EmblemArt = preload("res://game/emblem_art.gd")


# Draws the emblem into a 64x64 viewport (updated once) and shows it as this sprite's texture.
class Canvas extends Control:
	var shape := "chevron"
	var c1 := Color.WHITE
	var c2 := Color.GRAY

	func _draw() -> void:
		EmblemArt.draw(self, shape, Vector2(32, 32), 27.0, c1, c2)


var _viewport: SubViewport
var _canvas: Canvas


func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	pixel_size = 0.0055
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(64, 64)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_canvas = Canvas.new()
	_canvas.size = Vector2(64, 64)
	_viewport.add_child(_canvas)
	add_child(_viewport)
	texture = _viewport.get_texture()


func show_emblem(emblem_def: Dictionary) -> void:
	_canvas.shape = String(emblem_def["shape"])
	_canvas.c1 = Color.html(String(emblem_def["c1"]))
	_canvas.c2 = Color.html(String(emblem_def["c2"]))
	_canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
