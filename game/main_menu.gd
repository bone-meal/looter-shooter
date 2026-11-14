# Purpose: start screen shown at launch: Start Game, Multiplayer, Settings, Quit, and a music-note icon in the top
# right corner that opens the jukebox (locked hub plan: the player's own Music folder).
# Dependencies: game/menu_widgets.gd.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")

signal start_pressed
signal multiplayer_pressed
signal settings_pressed
signal quit_pressed
signal music_pressed


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.09, 0.08, 0.07))
	var box := Widgets.centered_column(self, 320)
	Widgets.title(box, "LOOTER SHOOTER", 44)
	Widgets.button(box, "Start Game", func() -> void: start_pressed.emit())
	Widgets.button(box, "Multiplayer", func() -> void: multiplayer_pressed.emit())
	Widgets.button(box, "Settings", func() -> void: settings_pressed.emit())
	Widgets.button(box, "Quit", func() -> void: quit_pressed.emit())
	var note := NoteButton.new()
	note.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	note.offset_left = -84
	note.offset_top = 20
	note.offset_right = -20
	note.offset_bottom = 84
	note.tooltip_text = "Jukebox: your Music folder"
	note.pressed.connect(func() -> void: music_pressed.emit())
	add_child(note)


# A round button with a drawn pair of eighth notes.
class NoteButton:
	extends Button

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var c := size * 0.5
		var hot := is_hovered()
		draw_circle(c, 30.0, Color(0.25, 0.18, 0.12) if hot else Color(0.16, 0.12, 0.09))
		draw_arc(c, 30.0, 0, TAU, 40, Color(1.0, 0.8, 0.4), 2.0, true)
		var ink := Color(1.0, 0.85, 0.5) if hot else Color(0.95, 0.78, 0.45)
		var a := c + Vector2(-10, 10)
		var b := c + Vector2(10, 6)
		draw_set_transform(a, -0.35, Vector2(1.3, 1.0))
		draw_circle(Vector2.ZERO, 5.5, ink)
		draw_set_transform(b, -0.35, Vector2(1.3, 1.0))
		draw_circle(Vector2.ZERO, 5.5, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(a + Vector2(6, 0), a + Vector2(6, -22), ink, 3.0)
		draw_line(b + Vector2(6, 0), b + Vector2(6, -22), ink, 3.0)
		draw_line(a + Vector2(6, -22), b + Vector2(6, -22), ink, 5.0)
