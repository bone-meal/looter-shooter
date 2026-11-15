# Purpose: the MIXTAPE's red-text behaviour (director's design, diary/DESIGN_UNIQUES.md): while the gun is in hand
# the MP3 player taped to it plays the holder's own Music folder (game/music_library.gd; the game ships no songs),
# shuffled, as 3D sound from the holder (loud near, soft far); its screen scrolls the song's name; the inspect key
# skips to the next song. Other players hear it from us through game/net_mixtape.gd (told each song here).
# Dependencies: game/music_library.gd, core/music_queue.gd (song dictionaries), the gun model's gimmick with its
# "Screen" marker (game/unique_attach.gd).
extends Node3D

const MusicLibrary = preload("res://game/music_library.gd")

const SCREEN_CHARS := 10  # letters the little screen shows at once
const SCROLL_EVERY := 0.22  # seconds per letter of scrolling
const LOUD_UNTIL := 6.0  # metres: full volume this close
const HEARD_TO := 45.0  # metres: silent beyond this
const VOLUME_DB := -4.0
const EMPTY_TEXT := "NO SONGS - PUT MUSIC IN YOUR MUSIC FOLDER"

var _speaker := AudioStreamPlayer3D.new()
var _label: Label3D
var _top: Label3D  # the small "PLAYING n/m" line above the name
var _songs: Array = []  # core/music_queue.gd song dictionaries, shuffled
var _at := -1
var _text := EMPTY_TEXT
var _scroll := 0
var _since := 0.0


func _ready() -> void:
	_speaker.unit_size = LOUD_UNTIL
	_speaker.max_distance = HEARD_TO
	_speaker.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_speaker.volume_db = VOLUME_DB
	_speaker.position = Vector3(0, 1.2, 0)
	_speaker.finished.connect(next_song)
	add_child(_speaker)


# The gun came into hand: `gimmick` = the MP3 model on it (its "Screen" marker gets the song name).
func start(gimmick: Node3D) -> void:
	_label = null
	_top = null
	var screen := gimmick.find_child("Screen", true, false) as Node3D if gimmick != null else null
	if screen != null:
		_backlight(screen)
		_label = _screen_line(screen, 56, 0.000105, -0.003)
		_top = _screen_line(screen, 30, 0.000085, 0.0095)
	_songs = MusicLibrary.scan()
	_songs.shuffle()
	_at = -1
	next_song()


# The screen's soft glow behind the letters (so it reads in shadow too).
func _backlight(screen: Node3D) -> void:
	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.039, 0.031)
	glow.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.07, 0.2, 0.24)
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.rotation_degrees = Vector3(0, -90, 0)
	glow.position = Vector3(0.0004, 0, 0)  # just behind the letters
	glow.set_meta("mixtape_screen", true)
	screen.add_child(glow)


# One line of glowing letters on the screen, `y` above its middle (left edge at the screen's muzzle end).
func _screen_line(screen: Node3D, size: int, pixel: float, y: float) -> Label3D:
	var line := Label3D.new()
	line.font_size = size
	line.pixel_size = pixel
	line.modulate = Color(0.55, 0.95, 1.0)
	line.outline_size = 0
	line.shaded = false
	line.double_sided = false
	line.rotation_degrees = Vector3(0, -90, 0)  # the screen faces out of the gun's left side
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.position = Vector3(0, y, -0.0185)
	screen.add_child(line)
	return line


# The gun left the hand: the music stops.
func stop() -> void:
	_speaker.stop()
	_tell_net("", 0)
	for line: Variant in [_label, _top]:  # (untyped: a label already freed with the gun broke a typed loop)
		if is_instance_valid(line):
			(line as Node).queue_free()
	if _label != null and is_instance_valid(_label):
		for child in _label.get_parent().get_children():
			if child.has_meta("mixtape_screen"):
				child.queue_free()
	_label = null
	_top = null


# The inspect key: the next song.
func on_inspect() -> void:
	next_song()


func next_song() -> void:
	_speaker.stop()
	_text = EMPTY_TEXT
	for _try in _songs.size():  # skip files that will not play
		_at = (_at + 1) % _songs.size()
		var song: Dictionary = _songs[_at]
		var stream := MusicLibrary.stream(String(song["file"]), MusicLibrary.bytes_of(String(song["file"])))
		if stream == null:
			continue
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = false
		_speaker.stream = stream
		_speaker.play()
		_tell_net(String(song["file"]), int(song.get("bytes", 0)))
		var artist := String(song.get("artist", ""))
		_text = ("%s - %s" % [artist, song["title"]] if artist != "" else String(song["title"])).to_upper()
		break
	_scroll = 0
	if _text == EMPTY_TEXT:
		_tell_net("", 0)
	_show()


# Tells the others what plays now (game/net_mixtape.gd; "" = nothing).
func _tell_net(file: String, size: int) -> void:
	var link: Node = get_tree().get_first_node_in_group("net_mixtape") if is_inside_tree() else null
	if link == null:
		return
	if file == "":
		link.call("stopped")
	else:
		link.call("playing", file, size, 0.0)


func playing_text() -> String:
	return _text


func _process(delta: float) -> void:
	_since += delta
	if _since >= SCROLL_EVERY:
		_since = 0.0
		_scroll += 1
		_show()


# The screen's window onto the scrolling name ("  ARTIST - TITLE  " goes round and round).
func _show() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	if _top != null and is_instance_valid(_top):
		_top.text = "PLAYING %d/%d" % [_at + 1, _songs.size()] if _speaker.playing else "MUSIC FOLDER"
	var loop := _text + "   *   "
	if _text.length() <= SCREEN_CHARS:
		_label.text = _text
		return
	var from := _scroll % loop.length()
	_label.text = (loop + loop).substr(from, SCREEN_CHARS)
