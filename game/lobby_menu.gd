# Purpose: multiplayer lobby screen: host a session (shows the session ID to share), or join one by ID; shows who is in the lobby; host presses Start.
# Dependencies: game/menu_widgets.gd, game/net_session.gd (set `net` before add_child).
extends Control

const Widgets = preload("res://game/menu_widgets.gd")

signal back_pressed

var net: Node3D

var _name_edit: LineEdit
var _id_edit: LineEdit
var _status: Label
var _roster_label: Label
var _host_button: Button
var _join_button: Button
var _start_button: Button
var _copy_button: Button
var _leave_button: Button


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.09, 0.08, 0.07))
	var box := Widgets.centered_column(self, 420)
	Widgets.title(box, "MULTIPLAYER", 36)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.max_length = 20
	box.add_child(_name_edit)
	_host_button = _make_button(box, "Host a session", _on_host)
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "Session ID from the host"
	box.add_child(_id_edit)
	_join_button = _make_button(box, "Join session", _on_join)
	_copy_button = _make_button(box, "Copy session ID", func() -> void: DisplayServer.clipboard_set(net.session_id))
	_start_button = _make_button(box, "Start", func() -> void: net.start_for_all())
	_leave_button = _make_button(box, "Leave lobby", _on_leave)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_roster_label = Label.new()
	_roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_roster_label)
	_make_button(box, "Back", func() -> void:
		if net.is_active():
			net.leave()
		back_pressed.emit())
	net.hosted.connect(_on_hosted)
	net.joined.connect(_on_joined)
	net.failed.connect(_on_failed)
	net.left.connect(_on_left)
	net.roster_changed.connect(_on_roster)
	_refresh()


func _make_button(box: Container, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(on_press)
	box.add_child(b)
	return b


func _on_host() -> void:
	_status.text = "Creating session..."
	_host_button.disabled = true
	net.host(_name_edit.text)


func _on_join() -> void:
	_status.text = "Connecting..."
	_join_button.disabled = true
	net.join(_id_edit.text, _name_edit.text)


func _on_leave() -> void:
	net.leave()


func _on_hosted(id: String) -> void:
	_status.text = "Session ID: %s\nShare it with friends (Discord etc.), then press Start." % id
	_refresh()


func _on_joined() -> void:
	_status.text = "Connected. Waiting for the host to start..."
	_refresh()


func _on_failed(message: String) -> void:
	_status.text = message
	_refresh()


func _on_left(reason: String) -> void:
	if reason != "":
		_status.text = reason
	_roster_label.text = ""
	_refresh()


func _on_roster(roster: Dictionary) -> void:
	var names: Array[String] = []
	for id in roster:
		names.append(String(roster[id]) + (" (host)" if id == 1 else ""))
	_roster_label.text = "In lobby: " + ", ".join(names)


# The chosen save slot's character (game/main.gd): the name the lobby starts with.
func set_player_name(character: String) -> void:
	_name_edit.text = character


func _refresh() -> void:
	var active: bool = net.is_active()
	var hosting: bool = net.is_host()
	_host_button.disabled = active
	_join_button.disabled = active
	_name_edit.editable = not active
	_id_edit.editable = not active
	_copy_button.visible = hosting
	_start_button.visible = hosting
	_leave_button.visible = active
