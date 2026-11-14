# Purpose: the hub's travel effect (locked: diary/DECISIONS_HUB.md "black ink splotches spread and black out the
# screen"): blots of black ink with little splashes around them spread over the screen until it is black, the
# callback runs (the player is moved), then the black fades away. Drawn circles only (cheap on every machine).
# Dependencies: none (a Control the session puts on its HUD layer).
extends Control

const SPREAD := 0.85  # seconds until the screen is black
const HOLD := 0.35
const FADE := 0.6

var _t := -1.0
var _blots: Array = []  # [centre, full radius, start delay, splashes [[offset, radius]]]
var _dark := Callable()
var _fired := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func playing() -> bool:
	return _t >= 0.0


# Starts the blots; `dark` runs once the screen is fully black.
func play(dark: Callable) -> void:
	_dark = dark
	_fired = false
	_t = 0.0
	visible = true
	modulate.a = 1.0
	_blots.clear()
	var rnd := RandomNumberGenerator.new()
	rnd.randomize()
	var span := maxf(size.x, size.y)
	for i in 16:
		var splashes: Array = []
		for k in rnd.randi_range(3, 7):
			var a := rnd.randf() * TAU
			splashes.append([Vector2(cos(a), sin(a)) * rnd.randf_range(1.05, 1.5), rnd.randf_range(0.04, 0.14)])
		_blots.append([Vector2(rnd.randf() * size.x, rnd.randf() * size.y), span * rnd.randf_range(0.18, 0.42), rnd.randf_range(0.0, 0.35), splashes])


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if _t >= SPREAD and not _fired:
		_fired = true
		if _dark.is_valid():
			_dark.call()
	if _t > SPREAD + HOLD:
		modulate.a = clampf(1.0 - (_t - SPREAD - HOLD) / FADE, 0.0, 1.0)
	if _t > SPREAD + HOLD + FADE:
		_t = -1.0
		visible = false
	queue_redraw()


func _draw() -> void:
	if _t < 0.0:
		return
	if _t >= SPREAD:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		return
	for blot: Array in _blots:
		var grow := clampf((_t - float(blot[2])) / (SPREAD - float(blot[2])), 0.0, 1.0)
		if grow <= 0.0:
			continue
		var r := float(blot[1]) * (1.0 - pow(1.0 - grow, 3.0))  # fast at first, then soaking out slowly
		r *= 1.0 + 2.0 * maxf(_t / SPREAD - 0.75, 0.0)  # the last moments: the blots run together into black
		var at: Vector2 = blot[0]
		draw_circle(at, r, Color.BLACK)
		for splash: Array in blot[3]:
			draw_circle(at + (splash[0] as Vector2) * r, r * float(splash[1]) * 2.0, Color.BLACK)
