# Purpose: what the safe hub shows on screen (locked: diary/DECISIONS_HUB.md): the big countdown in the middle of the
# screen (red in its last seconds; gone once the button was pressed), the ready list with ticks and "n/m ready", and
# on the stage the ring filling while F is held and the stage prompt. Fed by the session from game/net_hub.gd's view.
# Dependencies: none (a Control the session puts on its HUD layer).
extends Control

const RED := Color(1.0, 0.25, 0.2)
const GOLD := Color(1.0, 0.85, 0.4)

var view := {}  # game/net_hub.gd view (left, button, ready, total, players {peer: {ready, hold, stage}})
var red_last := 10.0
var me := 1
var names := Callable()  # func(peer) -> String
var key := "F"  # the interact key's label
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_view(v: Dictionary) -> void:
	view = v
	queue_redraw()


func _mine() -> Dictionary:
	return (view.get("players", {}) as Dictionary).get(me, {})


func _draw() -> void:
	if view.is_empty() or not bool(view.get("open", true)):
		return
	var mid := size * 0.5
	if not bool(view.get("button", false)) and int(view.get("total", 0)) > 0:
		var left := float(view.get("left", 0.0))
		var text := str(ceili(left))
		var big := 96
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		var color := RED if left <= red_last else Color.WHITE
		_font.draw_string_outline(get_canvas_item(), Vector2(mid.x - w * 0.5, mid.y - 110.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 10, Color(0, 0, 0, 0.8))
		draw_string(_font, Vector2(mid.x - w * 0.5, mid.y - 110.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, big, color)
	# the ready list, right side
	var players: Dictionary = view.get("players", {})
	var x := size.x - 260.0
	var y := size.y * 0.32
	draw_rect(Rect2(x - 14.0, y - 30.0, 254.0, 40.0 + 26.0 * players.size()), Color(0, 0, 0, 0.45))
	draw_string(_font, Vector2(x, y), "%d/%d ready" % [int(view.get("ready", 0)), int(view.get("total", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD)
	for peer: int in players:
		y += 26.0
		var ready := bool((players[peer] as Dictionary).get("ready", false))
		_tick(Vector2(x + 8.0, y - 6.0), ready)
		var name := String(names.call(peer)) if names.is_valid() else "Player"
		draw_string(_font, Vector2(x + 26.0, y), name, HORIZONTAL_ALIGNMENT_LEFT, 200.0, 18, Color.WHITE if ready else Color(0.75, 0.75, 0.75))
	# my ring and prompt, only on the stage
	var mine := _mine()
	if not bool(mine.get("stage", false)):
		return
	var hold := float(mine.get("hold", 0.0))
	if hold > 0.0:
		draw_arc(mid, 34.0, -PI * 0.5, -PI * 0.5 + TAU * hold, 48, GOLD, 6.0, true)
	var prompt := ("Ready.  Press [%s] to cancel" % key) if bool(mine.get("ready", false)) else ("Hold [%s] to get ready" % key)
	var pw := _font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_font.draw_string_outline(get_canvas_item(), Vector2(mid.x - pw * 0.5, mid.y + 80.0), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.8))
	draw_string(_font, Vector2(mid.x - pw * 0.5, mid.y + 80.0), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GOLD)


func _tick(at: Vector2, on: bool) -> void:
	draw_rect(Rect2(at - Vector2(7, 7), Vector2(14, 14)), Color(1, 1, 1, 0.6), false, 2.0)
	if on:
		draw_polyline(PackedVector2Array([at + Vector2(-5, 0), at + Vector2(-1, 5), at + Vector2(6, -6)]), Color(0.4, 1.0, 0.45), 3.0)
