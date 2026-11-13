# Purpose: a plain card face for the first playable (build step 5; real frames, rarity gems, art and the logo come in
# step 7): a rounded panel in the faction's colour with cost, name, type / tribe line, rules text and attack / health,
# all drawn in one _draw. Shows a card in the hand, a creature on the mat (its live numbers: green when raised above the
# card, red when hurt; its current keywords) or a card back. An outline marks what can be used or picked.
# Dependencies: core/tcg/card_db.gd (handed in), core/tcg/card_text.gd.
extends Control

const CardText = preload("res://core/tcg/card_text.gd")

signal pressed(face: Control, right: bool)
signal hovered(face: Control, on: bool)

const FACTION_COLORS := {
	"tide": Color(0.18, 0.42, 0.72), "waste": Color(0.66, 0.4, 0.18), "crypt": Color(0.42, 0.4, 0.5),
	"aurelind": Color(0.3, 0.58, 0.28), "club": Color(0.74, 0.22, 0.52), "neutral": Color(0.55, 0.5, 0.42),
}
const GREEN := Color(0.35, 1.0, 0.4)
const RED := Color(1.0, 0.35, 0.3)

var db: RefCounted
var id := ""
var creature: Dictionary = {}  # a match_state creature when on the mat, {} for a card in the hand
var back := false  # face down
var outline := Color(0, 0, 0, 0)  # green = can be used, yellow = can be picked, white = chosen, red = marked to redraw
var slot := -1  # hand position or creature uid, for whoever listens
var _style := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered.emit(self, true))
	mouse_exited.connect(func() -> void: hovered.emit(self, false))
	_style.set_corner_radius_all(8)


func show_card(card_db: RefCounted, card_id: String, live: Dictionary = {}) -> void:
	db = card_db
	id = card_id
	creature = live
	back = false
	queue_redraw()


func show_back() -> void:
	back = true
	queue_redraw()


func mark(color: Color) -> void:
	if color != outline:
		outline = color
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		pressed.emit(self, click.button_index == MOUSE_BUTTON_RIGHT)
		accept_event()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var font := get_theme_default_font()
	_style.border_color = outline if outline.a > 0.0 else Color(0.05, 0.05, 0.07)
	_style.set_border_width_all(4 if outline.a > 0.0 else 2)
	if back:
		_style.bg_color = Color(0.32, 0.08, 0.22)
		draw_style_box(_style, Rect2(Vector2.ZERO, size))
		draw_string(font, Vector2(0, h * 0.5), "LOBSTER?", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.09), Color(1, 0.8, 0.3))
		return
	var c: Dictionary = db.card(id)
	_style.bg_color = FACTION_COLORS.get(String(c.get("faction", "neutral")), Color.GRAY)
	if not creature.is_empty() and bool((creature["kw"] as Dictionary).get("hidden", false)):
		_style.bg_color = _style.bg_color.darkened(0.45)
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	if not creature.is_empty() and (creature["kw"] as Dictionary).has("guard"):  # a Guard wears a grey band
		draw_rect(Rect2(3, h * 0.2, w - 6, h * 0.05), Color(0.85, 0.85, 0.85, 0.7))
	var big := int(h * 0.085)
	var small := int(h * 0.062)
	# cost gem
	draw_circle(Vector2(w * 0.14, h * 0.09), w * 0.11, Color(0.15, 0.35, 0.95))
	draw_string(font, Vector2(w * 0.03, h * 0.09 + big * 0.36), str(int(c["cost"])), HORIZONTAL_ALIGNMENT_CENTER, w * 0.22, big, Color.WHITE)
	draw_string(font, Vector2(w * 0.26, h * 0.115), String(c["name"]), HORIZONTAL_ALIGNMENT_LEFT, w * 0.72, small, Color.WHITE)
	var kind := String(c["type"]).capitalize() + (" - " + String(c["tribe"]).capitalize() if c.has("tribe") else "")
	draw_string(font, Vector2(w * 0.06, h * 0.19), kind, HORIZONTAL_ALIGNMENT_LEFT, w * 0.9, int(small * 0.85), Color(1, 1, 1, 0.75))
	# text box
	draw_rect(Rect2(w * 0.05, h * 0.27, w * 0.9, h * 0.52), Color(0.95, 0.92, 0.84))
	var shown := c
	if not creature.is_empty():  # live keywords (given ones too, lost ones gone)
		shown = c.duplicate()
		shown["keywords"] = (creature["kw"] as Dictionary).keys()
	draw_multiline_string(font, Vector2(w * 0.08, h * 0.27 + small * 1.05), CardText.of(db, shown), HORIZONTAL_ALIGNMENT_LEFT, w * 0.84, small, 6, Color(0.1, 0.08, 0.06))
	if String(c["type"]) == "creature":
		var atk := int(c["attack"])
		var hp := int(c["health"])
		var atk_col := Color.WHITE
		var hp_col := Color.WHITE
		if not creature.is_empty():
			atk_col = GREEN if int(creature["atk"]) > atk else (RED if int(creature["atk"]) < atk else Color.WHITE)
			hp_col = RED if int(creature["hp"]) < int(creature["max_hp"]) else (GREEN if int(creature["max_hp"]) > hp else Color.WHITE)
			atk = int(creature["atk"])
			hp = int(creature["hp"])
		draw_circle(Vector2(w * 0.15, h * 0.9), w * 0.12, Color(0.85, 0.6, 0.1))
		draw_string(font, Vector2(w * 0.03, h * 0.9 + big * 0.36), str(atk), HORIZONTAL_ALIGNMENT_CENTER, w * 0.24, big, atk_col)
		draw_circle(Vector2(w * 0.85, h * 0.9), w * 0.12, Color(0.75, 0.12, 0.12))
		draw_string(font, Vector2(w * 0.73, h * 0.9 + big * 0.36), str(hp), HORIZONTAL_ALIGNMENT_CENTER, w * 0.24, big, hp_col)
	else:
		draw_string(font, Vector2(0, h * 0.92), String(c["type"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, small, Color(1, 1, 1, 0.8))
