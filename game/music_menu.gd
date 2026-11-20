# Purpose: the jukebox window (locked hub plan): opened by the music-note icon in the main menu and by the jukeboxes in
# the game. The song list (our Music folder, or the host's online) with Play and Queue on each song, what plays now,
# play / pause, skip, stop, volume, and Open Folder (where songs are added or changed; not shown to a joiner, whose
# list is the host's). Asks game/music_box.gd; closes with Back or Esc (the caller listens to `closed`).
# (polish1 item 5) Room for a big library (~400 of the player's own files): a search box filters the list, songs show as
# striped rows (now playing lit, queued numbered), SHUFFLE, and for a joiner a switch: the host's music or our own.
# Dependencies: game/menu_widgets.gd, game/music_box.gd (`box`), game/music_library.gd.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")
const MusicLibrary = preload("res://game/music_library.gd")

signal closed

var box: Node  # game/music_box.gd
var _list := VBoxContainer.new()
var _hint := Label.new()
var _now := Label.new()
var _pause := Button.new()
var _folder := Button.new()
var _volume := HSlider.new()
var _refresh := 0.0
var _search := LineEdit.new()
var _shuffle := Button.new()
var _source := OptionButton.new()  # online, a joiner: "Host's music" / "My own music"


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.05, 0.03, 0.06, 0.92))
	var column := Widgets.centered_column(self, 620)
	Widgets.title(column, "JUKEBOX")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(620, 0)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	column.add_child(_hint)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	column.add_child(tools)
	_search.placeholder_text = "Search songs or artists"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _fill())
	tools.add_child(_search)
	_source.add_item("Host's music")
	_source.add_item("My own music")
	_source.item_selected.connect(func(index: int) -> void: box.call("set_own", index == 1))
	tools.add_child(_source)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_now.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_now.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	column.add_child(_now)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 8)
	column.add_child(controls)
	_pause.custom_minimum_size = Vector2(110, 40)
	_pause.pressed.connect(func() -> void: box.call("toggle_pause"))
	controls.add_child(_pause)
	_shuffle.custom_minimum_size = Vector2(120, 40)
	_shuffle.toggle_mode = true
	_shuffle.text = "Shuffle"
	_shuffle.pressed.connect(func() -> void: box.call("toggle_shuffle"))
	controls.add_child(_shuffle)
	for pair: Array in [["Skip", func() -> void: box.call("skip")], ["Stop", func() -> void: box.call("stop_all")]]:
		var b := Button.new()
		b.text = String(pair[0])
		b.custom_minimum_size = Vector2(90, 40)
		b.pressed.connect(pair[1])
		controls.add_child(b)
	var vol := Label.new()
	vol.text = "  Volume"
	controls.add_child(vol)
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01
	_volume.custom_minimum_size = Vector2(150, 0)
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.value_changed.connect(func(v: float) -> void: box.call("set_volume", v))
	controls.add_child(_volume)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 8)
	column.add_child(bottom)
	_folder.text = "Open Music Folder"
	_folder.custom_minimum_size = Vector2(200, 44)
	_folder.pressed.connect(MusicLibrary.open_folder)
	bottom.add_child(_folder)
	var again := Button.new()
	again.text = "Look again"
	again.custom_minimum_size = Vector2(130, 44)
	again.pressed.connect(func() -> void: box.call("refresh"))
	bottom.add_child(again)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(110, 44)
	back.pressed.connect(close)
	bottom.add_child(back)


func open() -> void:
	if not box.is_connected("changed", _fill):
		box.connect("changed", _fill)
	_volume.set_value_no_signal(float(box.get("volume")))
	box.call("refresh")
	visible = true
	_fill()


func close() -> void:
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:  # the download line and play / pause move on their own
		_refresh = 0.5
		_status()


func _fill() -> void:
	if not visible:
		return
	for child in _list.get_children():
		child.queue_free()
	var shown: RefCounted = box.call("shown")
	var songs: Array = shown.get("songs")
	var now := String(shown.get("now"))
	var waiting: Array = shown.get("queue")
	var find := _search.text.strip_edges().to_lower()
	var n := 0
	for s: Dictionary in songs:
		if find != "" and not (String(s["title"]).to_lower().contains(find) or String(s["artist"]).to_lower().contains(find)):
			continue
		var stripe := PanelContainer.new()  # striped rows, the one playing lit
		var look := StyleBoxFlat.new()
		look.bg_color = Color(0.32, 0.22, 0.06, 0.85) if String(s["id"]) == now else (Color(1, 1, 1, 0.05) if n % 2 == 0 else Color(0, 0, 0, 0))
		look.set_corner_radius_all(6)
		look.content_margin_left = 8
		look.content_margin_right = 4
		stripe.add_theme_stylebox_override("panel", look)
		n += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		stripe.add_child(row)
		var name_label := Label.new()
		var artist := String(s["artist"])
		var title := String(s["title"]) if artist == "" else "%s  -  %s" % [artist, String(s["title"])]
		var mark := "> " if String(s["id"]) == now else ("(%d) " % (waiting.find(String(s["id"])) + 1) if waiting.has(String(s["id"])) else "")
		name_label.text = mark + title
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		var id := String(s["id"])
		for pair: Array in [["Play", func() -> void: box.call("play", id)], ["Queue", func() -> void: box.call("add", id)]]:
			var b := Button.new()
			b.text = String(pair[0])
			b.custom_minimum_size = Vector2(80, 34)
			b.pressed.connect(pair[1])
			row.add_child(b)
		_list.add_child(stripe)
	_folder.visible = bool(box.call("host_side"))
	_source.visible = bool(box.call("joined_someone"))
	_source.select(1 if bool(box.get("own_music")) else 0)
	_status()


func _status() -> void:
	var shown: RefCounted = box.call("shown")
	var songs: Array = shown.get("songs")
	var online: bool = box.call("online")
	if songs.is_empty():
		_hint.text = "No songs yet. Put mp3, ogg or wav files (up to 30 MB each) into your Music folder, then press Look again." if bool(box.call("host_side")) else "The host has no songs in their Music folder."
	elif online:
		_hint.text = "Songs from the host's Music folder: everyone hears them together." if not bool(box.call("host_side")) else "Your Music folder: everyone here hears these songs together."
	else:
		_hint.text = "Your Music folder (%d songs)." % songs.size()
	var getting: float = box.get("net_music").call("receiving") if online else -1.0
	var now := String(shown.get("now"))
	var song: Dictionary = shown.call("song", now) if now != "" else {}
	if getting >= 0.0:
		_now.text = "Getting the song from the host ... %d %%" % roundi(getting * 100.0)
	elif song.is_empty():
		_now.text = "Nothing playing."
	else:
		_now.text = "Now: %s%s" % [String(song["title"]), "" if String(song["artist"]) == "" else "  -  " + String(song["artist"])]
	_pause.text = "Play" if bool(box.call("is_paused")) or String(box.call("playing_id")) == "" else "Pause"
	_shuffle.set_pressed_no_signal(bool(shown.get("shuffle")))
	_shuffle.text = "Shuffle: on" if bool(shown.get("shuffle")) else "Shuffle: off"
