# Purpose: the jukebox's list: every song this character has unlocked, by artist and title; pick one to play it,
# or stop. Asks only: the session plays the files.
# Dependencies: game/menu_widgets.gd. `open(songs, playing)`: songs = [{"secret", "artist", "title"}]; signals.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")

signal picked(secret: int)
signal stopped
signal closed

var _list: VBoxContainer
var _hint := Label.new()


func _ready() -> void:
	visible = false
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.06, 0.03, 0.05, 0.9))
	var box := Widgets.centered_column(self, 560)
	Widgets.title(box, "JUKEBOX")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(560, 0)
	box.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	Widgets.button(box, "Stop the music", func() -> void: stopped.emit())
	Widgets.button(box, "Back", func() -> void: closed.emit())


func open(songs: Array, playing: int, found: int, total: int) -> void:
	for child in _list.get_children():
		child.queue_free()
	_hint.text = "%d of %d songs found. They are hidden on the islands: three of something to shoot for each." % [found, total] if not songs.is_empty() else "No songs found yet. They are hidden on the islands: three of something to shoot for each."
	for song: Dictionary in songs:
		var pick := Button.new()
		var artist := String(song["artist"])
		pick.text = ("> " if int(song["secret"]) == playing else "") + (String(song["title"]) if artist == "" else "%s  -  %s" % [artist, String(song["title"])])
		pick.custom_minimum_size = Vector2(0, 40)
		pick.pressed.connect(func() -> void: picked.emit(int(song["secret"])))
		_list.add_child(pick)
	visible = true


func close() -> void:
	visible = false
