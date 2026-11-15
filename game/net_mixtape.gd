# Purpose: the MIXTAPE online (director's design, diary/DESIGN_UNIQUES.md): everyone hears the song playing on a
# player's Mixtape as 3D sound from that player (game/remote_player.gd `play_song`), loud near and soft far. The
# holder tells the host what plays (song id, file, size, how far in); the host tells everyone. A player who does not
# hold the song asks the host; the host sends it from its own copy, or first asks the holder to send it up (16 KB
# pieces, a few a frame, kept in memory for the session, like the jukebox's: game/net_music.gd). A late starter
# joins the song where it is now. The song only travels: nothing is saved or installed. Node "Mixtape" under
# game/net_session.gd (`mixtape`).
# Dependencies: game/net_session.gd (parent; `net`: roster, my_id, is_host, can_send, player_node),
# game/music_library.gd (bytes and streams), core/music_queue.gd (MAX_BYTES).
extends Node

const MusicLibrary = preload("res://game/music_library.gd")
const MusicQueue = preload("res://core/music_queue.gd")

const PIECE := 16384
const PIECES_A_FRAME := 3

var net: Node3D
var cache := {}  # song id -> bytes held this session (the host's include what holders sent up)
var _playing := {}  # holder peer -> {"id", "file", "size", "pos", "at"}: what plays where (pos seconds at engine time at)
var _sending := {}  # host: peer -> {"id", "file", "bytes", "next"}
var _uploading := {}  # holder: {"id", "file", "bytes", "next"} while sending a song up to the host
var _incoming := {}  # id -> {"file", "count", "parts"}
var _waiting := {}  # host: song id -> peers that asked for it before the host had it
var _mine := ""  # our own song id playing now ("" = none)
var _mine_file := ""


func _ready() -> void:
	add_to_group("net_mixtape")


func active() -> bool:
	return net != null and net.can_send()


# ---- the holder's own Mixtape (game/signatures/mixtape.gd) ----

# Our Mixtape started `file` (its bytes on our disk) at `pos` seconds in.
func playing(file: String, size: int, pos: float) -> void:
	_mine = "%s|%d" % [file, size]
	_mine_file = file
	cache[_mine] = MusicLibrary.bytes_of(file)
	if not active():
		return
	if net.is_host():
		_announce(net.my_id(), _mine, file, size, pos)
	else:
		_tell.rpc_id(1, _mine, file, size, pos)


# Our Mixtape went quiet (put away, no songs).
func stopped() -> void:
	_mine = ""
	if not active():
		return
	if net.is_host():
		_announce(net.my_id(), "", "", 0, 0.0)
	else:
		_tell.rpc_id(1, "", "", 0, 0.0)


@rpc("any_peer", "call_remote", "reliable")
func _tell(id: String, file: String, size: int, pos: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(peer) and size >= 0 and size <= MusicQueue.MAX_BYTES and id.length() < 300:
		_announce(peer, id, file, size, pos)


# Host: what plays on `holder`'s Mixtape now, to everyone (and here).
func _announce(holder: int, id: String, file: String, size: int, pos: float) -> void:
	_now.rpc(holder, id, file, size, pos)
	_now(holder, id, file, size, pos)


# ---- everyone ----

@rpc("authority", "call_remote", "reliable")
func _now(holder: int, id: String, file: String, size: int, pos: float) -> void:
	if id == "":
		_playing.erase(holder)
		_sound(holder)
		return
	_playing[holder] = {"id": id, "file": file, "size": size, "pos": pos, "at": _clock()}
	if holder == net.my_id():
		return  # our own plays from our own player
	if cache.has(id):
		_sound(holder)
	elif not _incoming.has(id):
		_incoming[id] = {"file": file, "count": ceili(float(size) / PIECE), "parts": {}}
		if net.is_host():
			_want_from(net.my_id(), holder, id)
		else:
			_want.rpc_id(1, holder, id)


# Starts (or stops) `holder`'s song on their body here, where it is now.
func _sound(holder: int) -> void:
	var body: Node = net.player_node(holder)
	if body == null or holder == net.my_id() or not body.has_method("play_song"):
		return
	if not _playing.has(holder) or not cache.has(String(_playing[holder]["id"])):
		body.call("stop_song")
		return
	var p: Dictionary = _playing[holder]
	var stream := MusicLibrary.stream(String(p["file"]), cache[String(p["id"])])
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	body.call("play_song", stream, float(p["pos"]) + _clock() - float(p["at"]))


@rpc("any_peer", "call_remote", "reliable")
func _want(holder: int, id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(peer):
		_want_from(peer, holder, id)


# Host: `peer` needs song `id` (it plays on `holder`): send our copy, or have the holder send it up first.
func _want_from(peer: int, holder: int, id: String) -> void:
	if cache.has(id):
		if peer != net.my_id():
			_sending[peer] = {"id": id, "file": String(_playing.get(holder, {}).get("file", "")), "bytes": cache[id], "next": 0}
		return
	if not _waiting.has(id):
		_waiting[id] = []
		if holder != net.my_id() and net.roster.has(holder):
			_send_up.rpc_id(holder, id)
	if peer != net.my_id() and not (_waiting[id] as Array).has(peer):
		(_waiting[id] as Array).append(peer)


# Holder: the host wants our song.
@rpc("authority", "call_remote", "reliable")
func _send_up(id: String) -> void:
	if id == _mine and cache.has(id):
		_uploading = {"id": id, "file": _mine_file, "bytes": cache[id], "next": 0}


# Host: a piece of a holder's song.
@rpc("any_peer", "call_remote", "reliable")
func _up_piece(id: String, file: String, index: int, count: int, data: PackedByteArray) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(peer) and count > 0 and count <= ceili(float(MusicQueue.MAX_BYTES) / PIECE):
		_take_piece(id, file, index, count, data)


@rpc("authority", "call_remote", "reliable")
func _piece(id: String, file: String, index: int, count: int, data: PackedByteArray) -> void:
	_take_piece(id, file, index, count, data)


func _take_piece(id: String, file: String, index: int, count: int, data: PackedByteArray) -> void:
	if cache.has(id):
		return
	if not _incoming.has(id):
		_incoming[id] = {"file": file, "count": count, "parts": {}}
	var job: Dictionary = _incoming[id]
	(job["parts"] as Dictionary)[index] = data
	if (job["parts"] as Dictionary).size() < count:
		return
	var whole := PackedByteArray()
	for i in count:
		whole.append_array((job["parts"] as Dictionary).get(i, PackedByteArray()))
	_incoming.erase(id)
	cache[id] = whole
	if net.is_host():  # everyone who asked before we had it gets it now
		for peer: int in _waiting.get(id, []):
			if net.roster.has(peer):
				_sending[peer] = {"id": id, "file": file, "bytes": whole, "next": 0}
		_waiting.erase(id)
	for holder: int in _playing:  # start it on whoever plays it now
		if String(_playing[holder]["id"]) == id:
			_sound(holder)


func _process(_delta: float) -> void:
	if not active():
		if not _playing.is_empty():
			_playing.clear()
			_sending.clear()
			_uploading.clear()
			_incoming.clear()
			_waiting.clear()
		return
	for holder: int in _playing.keys():  # a holder who left
		if not net.roster.has(holder):
			_playing.erase(holder)
	if not _uploading.is_empty():
		_uploading = _pump(_uploading, 1, true)
	if net.is_host():
		for peer: int in _sending.keys():
			if not net.roster.has(peer):
				_sending.erase(peer)
				continue
			var job := _pump(_sending[peer], peer, false)
			if job.is_empty():
				_sending.erase(peer)
			else:
				_sending[peer] = job


# Sends a few pieces of `job` to `peer` (up to the host or down from it); {} when all are sent.
func _pump(job: Dictionary, peer: int, up: bool) -> Dictionary:
	var bytes: PackedByteArray = job["bytes"]
	var count := ceili(float(bytes.size()) / PIECE)
	for _i in PIECES_A_FRAME:
		var at := int(job["next"])
		if at >= count:
			return {}
		var part := bytes.slice(at * PIECE, mini((at + 1) * PIECE, bytes.size()))
		if up:
			_up_piece.rpc_id(peer, String(job["id"]), String(job["file"]), at, count, part)
		else:
			_piece.rpc_id(peer, String(job["id"]), String(job["file"]), at, count, part)
		job["next"] = at + 1
	return job


# A player joined: they hear every Mixtape playing now.
func joined(_peer: int) -> void:
	if active() and net.is_host():
		for holder: int in _playing:
			var p: Dictionary = _playing[holder]
			_now.rpc(holder, String(p["id"]), String(p["file"]), int(p["size"]), float(p["pos"]) + _clock() - float(p["at"]))


func _clock() -> float:
	return Time.get_ticks_msec() / 1000.0
