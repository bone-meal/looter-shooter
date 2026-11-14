# Purpose: what music plays on this machine (locked hub plan, jukebox rework). Made once by game/main.gd and kept for
# the whole run (main menu and game, also while paused). Alone or in the main menu it plays our own Music folder
# (game/music_library.gd) with its own queue; online it follows the host (game/net_music.gd): menus send intents
# there and the host says what starts. Volume is ours alone (user://music.cfg). Hidden songs (core/song_book.gd) play
# our own file at once, here only.
# Dependencies: core/music_queue.gd, game/music_library.gd, game/net_music.gd (`net_music`, set when online exists).
extends Node

const MusicQueue = preload("res://core/music_queue.gd")
const MusicLibrary = preload("res://game/music_library.gd")
const SETTINGS := "user://music.cfg"

signal changed

var net_music: Node  # game/net_music.gd under the online session
var local := MusicQueue.new()  # our own folder's list and queue
var player := AudioStreamPlayer.new()
var volume := 0.8
var _playing := ""  # id of what plays here ("secret:<file>" for a hidden song)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.finished.connect(_ended)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		volume = clampf(float(cfg.get_value("music", "volume", 0.8)), 0.0, 1.0)
	player.volume_db = linear_to_db(maxf(volume, 0.0001))
	local.set_songs(MusicLibrary.scan())
	if net_music != null:
		net_music.connect("state_changed", func() -> void: changed.emit())


func online() -> bool:
	return net_music != null and bool(net_music.call("active"))


# The list and queue the menus show: the host's online, ours otherwise.
func shown() -> RefCounted:
	return net_music.get("queue") if online() else local


func host_side() -> bool:
	return not online() or bool(net_music.get("net").call("is_host"))


# ---- what a menu asks ----

func refresh() -> void:
	if online():
		net_music.call("ask", "list")
	else:
		local.set_songs(MusicLibrary.scan())
	changed.emit()


func add(id: String) -> void:
	if online():
		net_music.call("ask", "add", id)
	elif local.add(id) and local.now == id and _playing != id:
		_play_local(id)
	changed.emit()


func play(id: String) -> void:
	if online():
		net_music.call("ask", "play", id)
	elif local.play_now(id):
		_play_local(id)
	changed.emit()


func skip() -> void:
	if online():
		net_music.call("ask", "skip")
	else:
		_play_local(local.skip())


func toggle_pause() -> void:
	if online():
		net_music.call("ask", "pause")
	elif _playing == "" and not local.songs.is_empty():  # Play with nothing playing: the first song
		play(String(local.songs[0]["id"]))
	else:
		local.paused = not player.stream_paused
		pause(local.paused)


func stop_all() -> void:
	if online():
		net_music.call("ask", "stop")
	else:
		local.stop()
		stop()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	player.volume_db = linear_to_db(maxf(volume, 0.0001))
	var cfg := ConfigFile.new()
	cfg.set_value("music", "volume", volume)
	cfg.save(SETTINGS)


# ---- what plays here ----

func play_bytes(id: String, file: String, bytes: PackedByteArray) -> void:
	var s := MusicLibrary.stream(file, bytes)
	if s == null:
		return
	player.stream = s
	player.stream_paused = false
	player.play()
	_playing = id
	changed.emit()


func pause(on: bool) -> void:
	player.stream_paused = on
	changed.emit()


func stop() -> void:
	player.stop()
	_playing = ""
	changed.emit()


# A hidden song found on the islands: our own file, at once, here only. False when the file cannot be played.
func play_file(file: String) -> bool:
	var bytes := MusicLibrary.bytes_of(file)
	if MusicLibrary.stream(file, bytes) == null:
		return false
	play_bytes("secret:" + file, file, bytes)
	return true


func playing_id() -> String:
	return _playing if player.playing or player.stream_paused else ""


func is_paused() -> bool:
	return player.stream_paused


func _play_local(id: String) -> void:
	var s := local.song(id)
	if s.is_empty():
		stop()
		return
	play_bytes(id, String(s["file"]), MusicLibrary.bytes_of(String(s["file"])))


func _ended() -> void:
	var was := _playing
	_playing = ""
	if online():
		if host_side():
			net_music.call("song_ended")
	elif was != "" and was == local.now:  # our own queue goes on (a hidden song or a host's song just ends)
		_play_local(local.skip())
	changed.emit()
