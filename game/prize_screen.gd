# Purpose: (polish1 item 75) the pachinko prize counter's window: your prize tickets at the top, one big picture button
# per prize (data/pachinko.json "prizes": picture, name, ticket price; greyed when you have too few), Close. Collects
# clicks only; game/game_session.gd redeems through core/prize_book.gd and calls refresh().
# Dependencies: game/ui_skin.gd, game/sharp_text.gd, the prize pictures named in data/pachinko.json.
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const SharpText = preload("res://game/sharp_text.gd")

signal redeem(id: String)
signal closed

const BASE_HEIGHT := 648.0
const TICKET := Color(0.35, 0.95, 0.9)

var _tickets := Label.new()
var _toast := Label.new()
var _buttons: Dictionary = {}  # prize id -> Button
var _prizes: Array = []


func _ready() -> void:
	visible = false
	theme = UiSkin.theme()
	_fit()
	get_viewport().size_changed.connect(_fit)
	visibility_changed.connect(func() -> void: _fit() if is_visible_in_tree() else SharpText.release(self))


# Laid out for a 648-pixel-high window and scaled up (like the card machine).
func _fit() -> void:
	var view := get_viewport_rect().size
	var k := clampf(view.y / BASE_HEIGHT, 1.0, 4.0)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	scale = Vector2(k, k)
	size = view / k
	if is_visible_in_tree():
		SharpText.hold(self, k)


func setup(prizes: Array) -> void:
	_prizes = prizes
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var box := (UiSkin.theme().get_stylebox("panel", "Panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	box.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "PRIZE COUNTER"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiSkin.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_tickets.add_theme_font_size_override("font_size", 24)
	_tickets.add_theme_color_override("font_color", TICKET)
	head.add_child(_tickets)
	var note := Label.new()
	note.text = "Win prize tickets in the TICKET pockets and the JACKPOT of the pachinko wall."
	note.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	note.add_theme_font_size_override("font_size", 15)
	v.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	for p: Dictionary in prizes:
		var b := Button.new()
		b.custom_minimum_size = Vector2(210, 118)
		b.text = "%s\n%d tickets" % [String(p["name"]), int(p["tickets"])]
		var icon := String(p.get("icon", ""))
		b.icon = load(icon) if icon != "" and ResourceLoader.exists(icon) else null
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("icon_max_width", 74)
		b.add_theme_font_size_override("font_size", 17)
		var id := String(p["id"])
		b.pressed.connect(func() -> void: redeem.emit(id))
		grid.add_child(b)
		_buttons[id] = b
	var foot := HBoxContainer.new()
	v.add_child(foot)
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_toast)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func() -> void: closed.emit())
	foot.add_child(close_btn)


func open(tickets: int) -> void:
	_toast.text = ""
	refresh(tickets)
	visible = true


func refresh(tickets: int) -> void:
	_tickets.text = "%d tickets" % tickets
	for p: Dictionary in _prizes:
		(_buttons[String(p["id"])] as Button).disabled = tickets < int(p["tickets"])


func show_result(text: String, good: bool) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", UiSkin.GOOD if good else UiSkin.BAD)

