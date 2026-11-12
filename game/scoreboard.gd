# Purpose: the scoreboard shown while its key (Tab) is held: one row per player with points, kills, headshots, downs
# and revives, best points first, our own row lit.
# Dependencies: core/score_card.gd (our own row, read-only). game/game_session.gd sets `card`, `my_name`, `title` and
# `others` (a function giving the other players' rows with their names).
extends Control

const COLUMNS := [["Points", "points"], ["Kills", "kills"], ["Headshots", "headshots"], ["Downs", "downs"], ["Revives", "revives"]]
const WIDTH := 760.0
const ROW_H := 34.0
const NAME_W := 250.0

const REFRESH := 0.25  # seconds between two looks at the numbers while it is open

var card: RefCounted
var my_name := ""
var others := Callable()  # func() -> Array of {"name", "points", "kills", "headshots", "downs", "revives"}
var title := ""  # what is being played, e.g. "Round 7"
var rows: Array = []  # what is drawn: the rows above plus ours, each with "me"

var _font: Font = ThemeDB.fallback_font
var _wait := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


# Open while the key is held during play (not over a menu, where the mouse is free).
func _process(delta: float) -> void:
	var want := card != null and Input.is_action_pressed("scoreboard") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if want != visible:
		visible = want
		_wait = 0.0
	if not visible:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH
		refresh()


# Reads the numbers again: ours and everybody else's, best points first.
func refresh() -> void:
	rows.clear()
	if others.is_valid():
		for other: Dictionary in others.call():
			other["me"] = false
			rows.append(other)
	var mine: Dictionary = card.row()
	mine["name"] = my_name
	mine["me"] = true
	rows.append(mine)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["points"]) > int(b["points"]))
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	var height := 86.0 + ROW_H * maxf(rows.size(), 1.0)
	var o := Vector2((view.x - WIDTH) * 0.5, maxf((view.y - height) * 0.4, 20.0))
	draw_rect(Rect2(o, Vector2(WIDTH, height)), Color(0, 0, 0, 0.72))
	draw_rect(Rect2(o, Vector2(WIDTH, height)), Color(1, 1, 1, 0.25), false, 2.0)
	draw_string(_font, o + Vector2(20, 30), title, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 40.0, 20, Color(0.78, 0.07, 0.05))
	var col_w := (WIDTH - NAME_W - 40.0) / COLUMNS.size()
	draw_string(_font, o + Vector2(20, 62), "Player", HORIZONTAL_ALIGNMENT_LEFT, NAME_W, 14, Color(1, 1, 1, 0.6))
	for c in COLUMNS.size():
		draw_string(_font, o + Vector2(20.0 + NAME_W + col_w * c, 62), COLUMNS[c][0], HORIZONTAL_ALIGNMENT_RIGHT, col_w, 14, Color(1, 1, 1, 0.6))
	draw_line(o + Vector2(16, 70), o + Vector2(WIDTH - 16.0, 70), Color(1, 1, 1, 0.25), 1.0)
	for r in rows.size():
		var row: Dictionary = rows[r]
		var y := o.y + 78.0 + ROW_H * r
		var tint := Color(1.0, 0.93, 0.7) if bool(row["me"]) else Color(1, 1, 1, 0.9)
		if bool(row["me"]):
			draw_rect(Rect2(o.x + 8.0, y, WIDTH - 16.0, ROW_H - 4.0), Color(1, 1, 1, 0.08))
		draw_string(_font, Vector2(o.x + 20.0, y + 22.0), String(row["name"]), HORIZONTAL_ALIGNMENT_LEFT, NAME_W, 18, tint)
		for c in COLUMNS.size():
			draw_string(_font, Vector2(o.x + 20.0 + NAME_W + col_w * c, y + 22.0), str(int(row[COLUMNS[c][1]])), HORIZONTAL_ALIGNMENT_RIGHT, col_w, 18, tint)
