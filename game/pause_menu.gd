# Purpose: in-game pause overlay (Esc): Resume, Settings, Main Menu, Quit.
# Dependencies: game/menu_widgets.gd.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")

signal resume_pressed
signal settings_pressed
signal main_menu_pressed
signal quit_pressed


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0, 0, 0, 0.6))
	var box := Widgets.centered_column(self, 320)
	Widgets.title(box, "PAUSED")
	Widgets.button(box, "Resume", func() -> void: resume_pressed.emit())
	Widgets.button(box, "Settings", func() -> void: settings_pressed.emit())
	Widgets.button(box, "Main Menu", func() -> void: main_menu_pressed.emit())
	Widgets.button(box, "Quit", func() -> void: quit_pressed.emit())
