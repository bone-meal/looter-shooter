# Purpose: start screen shown at launch: Start Game, Multiplayer, Settings, Quit.
# Dependencies: game/menu_widgets.gd.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")

signal start_pressed
signal multiplayer_pressed
signal settings_pressed
signal quit_pressed


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.09, 0.08, 0.07))
	var box := Widgets.centered_column(self, 320)
	Widgets.title(box, "LOOTER SHOOTER", 44)
	Widgets.button(box, "Start Game", func() -> void: start_pressed.emit())
	Widgets.button(box, "Multiplayer", func() -> void: multiplayer_pressed.emit())
	Widgets.button(box, "Settings", func() -> void: settings_pressed.emit())
	Widgets.button(box, "Quit", func() -> void: quit_pressed.emit())
