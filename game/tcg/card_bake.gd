# Purpose: turns a drawn card (game/tcg/card_face.gd) into a texture for the 3D table: one small SubViewport draws the
# face once (256 x 358), the picture is copied into an ImageTexture and kept in a small cache (oldest dropped first),
# so a match holds a few dozen card pictures and nothing is drawn per frame. Also the card back.
# Dependencies: game/tcg/card_face.gd; a card db handed in.
extends Node

const CardFace = preload("res://game/tcg/card_face.gd")

const SIZE := Vector2i(256, 358)
const KEEP := 48  # pictures kept (each about 360 KB)

var db: RefCounted
var _view := SubViewport.new()
var _face: Control
var _cache := {}  # key -> ImageTexture
var _order: Array = []  # keys, oldest first
var _queue: Array = []  # [key, id, finish, callback] waiting for their frame


func _ready() -> void:
	_view.size = SIZE
	_view.transparent_bg = true
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	_face = CardFace.new()
	_face.size = Vector2(SIZE)
	_view.add_child(_face)
	_face.call("show_back")  # nothing to draw yet


# The picture of a card ("" id = the back; live = a creature on the mat, drawn with its current numbers). Ready at
# once when cached, else `done` gets it a frame or two later.
func texture(id: String, finish: String, done: Callable, live: Dictionary = {}) -> void:
	var key := "%s|%s|%s" % [id, finish, _live_key(live)]
	if _cache.has(key):
		done.call(_cache[key])
		return
	for q: Array in _queue:
		if q[0] == key:
			(q[3] as Array).append(done)
			return
	_queue.append([key, id, finish, [done], live])
	if _queue.size() == 1:
		_bake_next()


static func _live_key(live: Dictionary) -> String:
	if live.is_empty():
		return ""
	var kws: Array = (live.get("kw", {}) as Dictionary).keys()
	kws.sort()
	return "%d/%d/%d/%s" % [int(live.get("atk", 0)), int(live.get("hp", 0)), int(live.get("max_hp", 0)), ",".join(kws)]


func _bake_next() -> void:
	if _queue.is_empty():
		return
	var q: Array = _queue[0]
	if String(q[1]) == "":
		_face.call("show_back")
	else:
		_face.call("show_card", db, String(q[1]), q[4])
	_face.call("set_finish", String(q[2]))
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var tex := ImageTexture.create_from_image(_view.get_texture().get_image())
	_cache[q[0]] = tex
	_order.append(q[0])
	while _order.size() > KEEP:
		_cache.erase(_order.pop_front())
	_queue.pop_front()
	for done: Callable in q[3]:
		if done.is_valid():
			done.call(tex)
	_bake_next()
