# Purpose: in-game pause overlay (Esc): the lobby code with a Copy button when online, Resume, Settings, Main Menu, Quit.
# Dependencies: game/menu_widgets.gd.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")

signal resume_pressed
signal settings_pressed
signal main_menu_pressed
signal quit_pressed

var _code := ""
var _code_row := HBoxContainer.new()
var _code_label := Label.new()


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0, 0, 0, 0.6))
	var box := Widgets.centered_column(self, 320)
	Widgets.title(box, "PAUSED")
	_code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_code_row.add_theme_constant_override("separation", 10)
	_code_label.add_theme_font_size_override("font_size", 18)
	_code_row.add_child(_code_label)
	var copy := Button.new()
	copy.text = "Copy"
	copy.custom_minimum_size = Vector2(80, 32)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_code)
		copy.text = "Copied")
	copy.mouse_exited.connect(func() -> void: copy.text = "Copy")
	_code_row.add_child(copy)
	_code_row.visible = false
	box.add_child(_code_row)
	Widgets.button(box, "Resume", func() -> void: resume_pressed.emit())
	Widgets.button(box, "Settings", func() -> void: settings_pressed.emit())
	Widgets.button(box, "Main Menu", func() -> void: main_menu_pressed.emit())
	Widgets.button(box, "Quit", func() -> void: quit_pressed.emit())


# The online session's lobby code, so friends can join a game in progress ("" = not online: the row hides).
func set_code(code: String) -> void:
	_code = code
	_code_label.text = "Lobby code: %s" % code
	_code_row.visible = code != ""
