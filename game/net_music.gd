# Purpose: the jukebox online (locked hub plan, jukebox rework): the HOST's Music folder is the song list; anyone may
# queue, play now, skip, pause or stop (intents); the host decides. A song that is to play is sent from the host's
# file to every player who does not hold it yet (16 KB pieces, a few a frame, kept in memory for the session; nothing
# to download or install), and starts on every machine at the same moment once all hold it (after 45 s it starts
# anyway for those who have it). Node "Music" under game/net_session.gd (`music`).
# Dependencies: game/net_session.gd (parent; `net`), core/music_queue.gd, game/music_library.gd, game/music_box.gd
# (`box`: what plays here).
extends Node

const MusicQueue = preload("res://core/music_queue.gd")
const MusicLibrary = preload("res://game/music_library.gd")

const PIECE := 16384
const PIECES_A_FRAME := 3
const WAIT_LIMIT := 45.0
const START_DELAY := 0.15  # the host starts this much after telling the others (the message's way to them)

signal state_changed

var net: Node3D
var box: Node  # game/music_box.gd
var queue := MusicQueue.new()  # host: the real one; client: what the host last said
var cache := {}  # client: song id -> bytes received this session
var _sending := {}  # host: peer -> {"id", "file", "bytes", "next"}
var _incoming := {}  # client: id -> {"file", "count", "parts": {index: bytes}}
var _waiting := ""  # host: id waiting until every player holds it
var _waited := 0.0
var _was_up := false


func active() -> bool:
	return net != null and net.can_send()


# ---- intents (anyone) ----

func ask(what: String, id := "") -> void:
	if not active():
		return
	if net.is_host():
		_intent(net.my_id(), what, id)
	else:
		_ask.rpc_id(1, what, id)


@rpc("any_peer", "call_remote", "reliable")
func _ask(what: String, id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(peer):
		_intent(peer, what, id)


func _intent(_peer: int, what: String, id: String) -> void:
	var before := queue.now
	match what:
		"list":
			queue.set_songs(MusicLibrary.scan())
		"add":
			queue.add(id)
		"play":
			queue.play_now(id)
		"skip":
			queue.skip()
		"pause":
			if queue.now == "" and not queue.songs.is_empty():  # Play with nothing playing: the first song
				queue.add(String(queue.songs[0]["id"]))
				_prepare(queue.now)
				_send_state()
				return
			queue.paused = not queue.paused
			_pause.rpc(queue.paused)
			box.call("pause", queue.paused)
		"stop":
			queue.stop()
			_waiting = ""
			_stop.rpc()
			box.call("stop")
	if queue.now != before and queue.now != "":
		_prepare(queue.now)
	_send_state()


# The host's own song ended: the next one.
func song_ended() -> void:
	if active() and net.is_host():
		_intent(net.my_id(), "skip", "")


# ---- the host: list, sending, starting ----

func _send_state() -> void:
	_state.rpc(queue.songs, queue.queue, queue.now, queue.paused)
	state_changed.emit()


func _prepare(id: String) -> void:
	var s := queue.song(id)
	if s.is_empty():
		return
	_waiting = id
	_waited = 0.0
	queue.hold(id, net.my_id())
	_offer.rpc(id, String(s["file"]), int(s["bytes"]))


@rpc("any_peer", "call_remote", "reliable")
func _want(id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not net.is_host() or not net.roster.has(peer):
		return
	var s := queue.song(id)
	if s.is_empty():
		return
	var bytes := MusicLibrary.bytes_of(String(s["file"]))
	if bytes.is_empty():
		return
	_sending[peer] = {"id": id, "file": String(s["file"]), "bytes": bytes, "next": 0}


@rpc("any_peer", "call_remote", "reliable")
func _have(id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(peer):
		queue.hold(id, peer)


func _process(delta: float) -> void:
	var up := active()
	if _was_up and not up:  # left, or the host is gone: back to our own folder
		queue = MusicQueue.new()
		cache.clear()
		_sending.clear()
		_incoming.clear()
		_waiting = ""
		state_changed.emit()
	if up and not _was_up and net.is_host():
		queue.set_songs(MusicLibrary.scan())
	_was_up = up
	if not up or not net.is_host():
		return
	for peer: int in _sending.keys():
		if not net.roster.has(peer):
			_sending.erase(peer)
			continue
		var job: Dictionary = _sending[peer]
		var bytes: PackedByteArray = job["bytes"]
		var count := ceili(float(bytes.size()) / PIECE)
		for _i in PIECES_A_FRAME:
			var at := int(job["next"])
			if at >= count:
				_sending.erase(peer)
				break
			_piece.rpc_id(peer, String(job["id"]), String(job["file"]), at, count, bytes.slice(at * PIECE, mini((at + 1) * PIECE, bytes.size())))
			job["next"] = at + 1
	if _waiting != "":
		_waited += delta
		var peers: Array = net.roster.keys()
		if queue.everyone_has(_waiting, peers) or _waited > WAIT_LIMIT:
			var id := _waiting
			_waiting = ""
			var s := queue.song(id)
			_start.rpc(id, String(s.get("file", "")))
			get_tree().create_timer(START_DELAY).timeout.connect(func() -> void:
				box.call("play_bytes", id, String(s.get("file", "")), MusicLibrary.bytes_of(String(s.get("file", "")))))


# A player joined: it hears the list; whatever plays now it gets from the next song on.
func joined(_peer: int) -> void:
	if active() and net.is_host():
		_send_state()


# ---- every client ----

@rpc("authority", "call_remote", "reliable")
func _state(songs: Array, waiting: Array, now: String, paused: bool) -> void:
	queue.set_songs(songs)
	queue.queue = waiting
	queue.now = now
	queue.paused = paused
	state_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _offer(id: String, file: String, size: int) -> void:
	if size <= 0 or size > MusicQueue.MAX_BYTES:
		return
	if cache.has(id):
		_have.rpc_id(1, id)
	else:
		_incoming[id] = {"file": file, "count": ceili(float(size) / PIECE), "parts": {}}
		_want.rpc_id(1, id)


@rpc("authority", "call_remote", "reliable")
func _piece(id: String, file: String, index: int, count: int, data: PackedByteArray) -> void:
	if not _incoming.has(id):
		_incoming[id] = {"file": file, "count": count, "parts": {}}
	var job: Dictionary = _incoming[id]
	(job["parts"] as Dictionary)[index] = data
	if (job["parts"] as Dictionary).size() < int(job["count"]):
		return
	var whole := PackedByteArray()
	for i in int(job["count"]):
		whole.append_array((job["parts"] as Dictionary).get(i, PackedByteArray()))
	_incoming.erase(id)
	cache[id] = whole
	_have.rpc_id(1, id)
	state_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _start(id: String, file: String) -> void:
	if cache.has(id):
		box.call("play_bytes", id, file, cache[id])


@rpc("authority", "call_remote", "reliable")
func _pause(on: bool) -> void:
	box.call("pause", on)


@rpc("authority", "call_remote", "reliable")
func _stop() -> void:
	box.call("stop")


# How far the song now being sent to us has come (0..1), or -1 when nothing comes.
func receiving() -> float:
	for id: String in _incoming:
		var job: Dictionary = _incoming[id]
		return float((job["parts"] as Dictionary).size()) / maxf(float(job["count"]), 1.0)
	return -1.0
