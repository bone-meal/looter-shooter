# Purpose: the COACH RIDE card (polish1 E5, item 126; "for now a teleport + loading screen"): when a coach leaves, the
# whole screen goes to a night-ink card for data/fantasy/coaches.json ride_s seconds: "The coach to <town>" in
# Grenze Gotisch, a spoked wheel turning, a road of dashes running under it; the world moves the player behind it and
# the land loads. Pure drawing over any CanvasItem (game/fantasy_hud.gd).
# Dependencies: game/fantasy_style.gd (fonts, colours).
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")

var seconds := 3.0
var _to := ""
var _age := -1.0


func start(town: String, ride_s: float) -> void:
	_to = town
	seconds = ride_s
	_age = 0.0


func update(delta: float) -> void:
	if _age >= 0.0:
		_age += minf(delta, 0.1)  # the land loading behind it can hold one frame for seconds: the card still shows after
		if _age >= seconds:
			_age = -1.0


func busy() -> bool:
	return _age >= 0.0


func draw(c: CanvasItem, view: Vector2) -> void:
	if _age < 0.0:
		return
	var a := clampf(_age / 0.35, 0.0, 1.0) * clampf((seconds - _age) / 0.5, 0.0, 1.0)
	c.draw_rect(Rect2(Vector2.ZERO, view), Color(0.05, 0.04, 0.03, a))
	var mid := view * 0.5
	c.draw_string(Style.gothic(), Vector2(0.0, mid.y - 90.0), "The coach to %s" % _to, HORIZONTAL_ALIGNMENT_CENTER, view.x, 40, Color(Style.PARCHMENT, a))
	var hub := mid + Vector2(0.0, 10.0)
	var turn := _age * 4.0
	c.draw_arc(hub, 46.0, 0.0, TAU, 40, Color(Style.GOLD, a), 6.0, true)
	for k in 8:  # spokes
		var d := Vector2.from_angle(turn + float(k) * TAU / 8.0)
		c.draw_line(hub + d * 8.0, hub + d * 44.0, Color(Style.GOLD, a), 3.0)
	c.draw_circle(hub, 8.0, Color(Style.GOLD, a))
	for k in 12:  # the road running past
		var x := fposmod(float(k) * 90.0 - _age * 260.0, view.x + 90.0) - 45.0
		c.draw_line(Vector2(x, hub.y + 62.0), Vector2(x + 44.0, hub.y + 62.0), Color(Style.GOLD_DIM, a * 0.8), 3.0)
	c.draw_string(Style.font_italic(), Vector2(0.0, hub.y + 110.0), "The road rolls by...", HORIZONTAL_ALIGNMENT_CENTER, view.x, 18, Color(Style.FADED, a))
