# Purpose: graphical debug HUD: frame-time graph plus colored meter bars with icons (green = fine, yellow = watch, red = problem).
# Dependencies: none. game/game_session.gd feeds it every frame (push_frame) and every HUD refresh (the metric vars).
extends Control

enum Icon { CLOCK, MONITOR, STACK, CHIP, BALL, GEAR, TREE, SKULL, BULLET, FOOT, BOLT }

const HISTORY := 120
const WIDTH := 268.0
const GRAPH_H := 80.0
const GRAPH_MAX_MS := 40.0
const ROW_H := 26.0
const BAR_X := 34.0
const BAR_W := WIDTH - BAR_X
const BAR_H := 14.0
const SPIKE_MS := 25.0
const PIPS := 10

# Budgets: a meter is yellow above 60% of its budget and red above 85%.
const DRAW_BUDGET := 400.0
const MEM_BUDGET_MB := 512.0
const TIME_BUDGET_MS := 8.0
const NODE_BUDGET := 1000.0
const ENEMY_BUDGET := 12.0
const PROJECTILE_BUDGET := 48.0

const GOOD := Color(0.3, 0.85, 0.4)
const WARN := Color(0.95, 0.8, 0.25)
const BAD := Color(0.95, 0.3, 0.3)
const BACK := Color(0, 0, 0, 0.55)
const DIM := Color(1, 1, 1, 0.2)

var fps := 0.0
var draws := 0.0
var mem_mb := 0.0
var process_ms := 0.0
var physics_ms := 0.0
var nodes := 0.0
var enemies := 0.0
var projectiles := 0.0
var on_floor := true

var _frames := PackedFloat32Array()
var _next := 0
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -WIDTH - 12.0
	offset_right = -12.0
	offset_top = 12.0
	offset_bottom = 12.0 + GRAPH_H + 12.0 + ROW_H * 10.0
	_frames.resize(HISTORY)


# Call every rendered frame while visible.
func push_frame(delta: float) -> void:
	_frames[_next] = delta * 1000.0
	_next = (_next + 1) % HISTORY
	_timer += delta
	if _timer >= 0.1:
		_timer = 0.0
		queue_redraw()


func _draw() -> void:
	_draw_graph()
	var spikes := 0
	for ms in _frames:
		if ms > SPIKE_MS:
			spikes += 1
	var fps_color := GOOD if fps >= 55.0 else (WARN if fps >= 30.0 else BAD)
	_row(0, Icon.MONITOR, fps / 60.0, fps_color)
	_row(1, Icon.STACK, draws / DRAW_BUDGET, _budget_color(draws / DRAW_BUDGET))
	_row(2, Icon.CHIP, mem_mb / MEM_BUDGET_MB, _budget_color(mem_mb / MEM_BUDGET_MB))
	_row(3, Icon.GEAR, process_ms / TIME_BUDGET_MS, _budget_color(process_ms / TIME_BUDGET_MS))
	_row(4, Icon.BALL, physics_ms / TIME_BUDGET_MS, _budget_color(physics_ms / TIME_BUDGET_MS))
	_row(5, Icon.TREE, nodes / NODE_BUDGET, _budget_color(nodes / NODE_BUDGET))
	_row(6, Icon.SKULL, enemies / ENEMY_BUDGET, _budget_color(enemies / ENEMY_BUDGET))
	_row(7, Icon.BULLET, projectiles / PROJECTILE_BUDGET, _budget_color(projectiles / PROJECTILE_BUDGET))
	_row(8, Icon.FOOT, 1.0 if on_floor else 0.15, GOOD if on_floor else WARN)
	_spike_row(9, spikes)


func _draw_graph() -> void:
	draw_rect(Rect2(0, 0, WIDTH, GRAPH_H), BACK)
	var bar_w := WIDTH / HISTORY
	for i in HISTORY:
		var ms := _frames[(_next + i) % HISTORY]
		var h := clampf(ms / GRAPH_MAX_MS, 0.0, 1.0) * GRAPH_H
		var color := GOOD if ms < 18.0 else (WARN if ms < SPIKE_MS else BAD)
		draw_rect(Rect2(i * bar_w, GRAPH_H - h, bar_w - 0.5, h), color)
	draw_line(Vector2(0, GRAPH_H * (1.0 - 16.7 / GRAPH_MAX_MS)), Vector2(WIDTH, GRAPH_H * (1.0 - 16.7 / GRAPH_MAX_MS)), Color(GOOD, 0.5), 1.0)
	draw_line(Vector2(0, GRAPH_H * (1.0 - 33.3 / GRAPH_MAX_MS)), Vector2(WIDTH, GRAPH_H * (1.0 - 33.3 / GRAPH_MAX_MS)), Color(BAD, 0.5), 1.0)
	draw_rect(Rect2(0, 0, WIDTH, GRAPH_H), DIM, false, 1.0)
	_icon(Icon.CLOCK, Vector2(14, 14), Color(1, 1, 1, 0.8))


func _budget_color(ratio: float) -> Color:
	if ratio < 0.6:
		return GOOD
	return WARN if ratio < 0.85 else BAD


func _row_y(index: int) -> float:
	return GRAPH_H + 12.0 + index * ROW_H


func _row(index: int, icon: Icon, ratio: float, color: Color) -> void:
	var y := _row_y(index)
	_icon(icon, Vector2(16, y + BAR_H * 0.5), color)
	draw_rect(Rect2(BAR_X, y, BAR_W, BAR_H), BACK)
	draw_rect(Rect2(BAR_X, y, BAR_W * clampf(ratio, 0.0, 1.0), BAR_H), color)
	draw_line(Vector2(BAR_X + BAR_W * 0.6, y), Vector2(BAR_X + BAR_W * 0.6, y + BAR_H), DIM, 1.0)
	draw_line(Vector2(BAR_X + BAR_W * 0.85, y), Vector2(BAR_X + BAR_W * 0.85, y + BAR_H), DIM, 1.0)
	draw_rect(Rect2(BAR_X, y, BAR_W, BAR_H), DIM, false, 1.0)


# Row of pips: one lit red pip per slow frame in the recent history.
func _spike_row(index: int, spikes: int) -> void:
	var y := _row_y(index)
	_icon(Icon.BOLT, Vector2(16, y + BAR_H * 0.5), BAD if spikes > 0 else GOOD)
	var pip_w := BAR_W / PIPS
	for i in PIPS:
		var lit := i < spikes
		draw_rect(Rect2(BAR_X + i * pip_w + 1.0, y, pip_w - 2.0, BAR_H), BAD if lit else BACK)
		draw_rect(Rect2(BAR_X + i * pip_w + 1.0, y, pip_w - 2.0, BAR_H), DIM, false, 1.0)


func _icon(kind: Icon, c: Vector2, col: Color) -> void:
	match kind:
		Icon.CLOCK:
			draw_arc(c, 8.0, 0.0, TAU, 20, col, 2.0)
			draw_line(c, c + Vector2(0, -6), col, 2.0)
			draw_line(c, c + Vector2(4, 2), col, 2.0)
		Icon.MONITOR:
			draw_rect(Rect2(c + Vector2(-9, -8), Vector2(18, 12)), col, false, 2.0)
			draw_line(c + Vector2(0, 4), c + Vector2(0, 8), col, 2.0)
			draw_line(c + Vector2(-5, 8), c + Vector2(5, 8), col, 2.0)
		Icon.STACK:
			for i in 3:
				draw_rect(Rect2(c + Vector2(-9 + i * 4, -9 + i * 4), Vector2(11, 9)), col, false, 1.5)
		Icon.CHIP:
			draw_rect(Rect2(c + Vector2(-6, -6), Vector2(12, 12)), col, false, 2.0)
			for i in 3:
				draw_line(c + Vector2(-9, -4 + i * 4), c + Vector2(-6, -4 + i * 4), col, 1.5)
				draw_line(c + Vector2(6, -4 + i * 4), c + Vector2(9, -4 + i * 4), col, 1.5)
		Icon.BALL:
			draw_circle(c + Vector2(0, 3), 4.0, col)
			draw_arc(c + Vector2(0, 3), 9.0, PI * 1.15, PI * 1.85, 8, col, 1.5)
		Icon.GEAR:
			draw_circle(c, 5.0, col)
			for i in 8:
				var dir := Vector2.RIGHT.rotated(i * TAU / 8.0)
				draw_line(c + dir * 5.0, c + dir * 9.0, col, 2.5)
			draw_circle(c, 2.0, BACK)
		Icon.TREE:
			draw_line(c + Vector2(0, -6), c + Vector2(-6, 6), col, 1.5)
			draw_line(c + Vector2(0, -6), c + Vector2(6, 6), col, 1.5)
			draw_circle(c + Vector2(0, -6), 3.0, col)
			draw_circle(c + Vector2(-6, 6), 3.0, col)
			draw_circle(c + Vector2(6, 6), 3.0, col)
		Icon.SKULL:
			draw_circle(c + Vector2(0, -2), 7.0, col)
			draw_rect(Rect2(c + Vector2(-4, 3), Vector2(8, 5)), col)
			draw_circle(c + Vector2(-3, -2), 2.0, BACK)
			draw_circle(c + Vector2(3, -2), 2.0, BACK)
		Icon.BULLET:
			draw_rect(Rect2(c + Vector2(-9, -3), Vector2(10, 6)), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(1, -3), c + Vector2(9, 0), c + Vector2(1, 3)]), col)
		Icon.FOOT:
			draw_line(c + Vector2(-9, 7), c + Vector2(9, 7), col, 2.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 4), c + Vector2(0, -7), c + Vector2(6, 4)]), col)
		Icon.BOLT:
			draw_colored_polygon(PackedVector2Array([c + Vector2(2, -9), c + Vector2(-5, 1), c + Vector2(0, 1), c + Vector2(-2, 9), c + Vector2(6, -2), c + Vector2(1, -2)]), col)
