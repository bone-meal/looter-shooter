# Purpose: a small billboard sprite showing a player-card emblem above another player's head (the emblem is drawn once into a tiny SubViewport texture).
# Dependencies: game/emblem_art.gd. Call show_emblem() with one entry of data/achievements.json "emblems".
extends Sprite3D

const EmblemArt = preload("res://game/emblem_art.gd")


# Draws the emblem into a 64x64 viewport (updated once) and shows it as this sprite's texture.
class Canvas extends Control:
	var def := {}  # one entry of data/achievements.json "emblems"

	func _draw() -> void:
		EmblemArt.draw_def(self, def, Vector2(32, 32), 29.0)


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
	_canvas.def = emblem_def
	_canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
