# Purpose: the jukebox's rules (locked hub plan, jukebox rework): the songs on offer (the host's Music folder online,
# our own alone), what plays now, what comes next, and, for the host, who already holds the song so every player can
# start it at the same moment. Anyone may queue, play now or skip. Pure rules, no nodes, no files, no network.
# A song = {"id", "file", "artist", "title", "bytes"}; id = file name + size (the same file on two machines has one id).
# Dependencies: none.
extends RefCounted

const MAX_BYTES := 30 * 1024 * 1024  # locked: 30 MB a song
const KINDS := ["mp3", "ogg", "wav"]

var songs: Array = []  # in list order (by file name)
var queue: Array = []  # ids waiting, first plays next
var now := ""  # id playing (or waiting for every player to hold it); "" = nothing
var paused := false
var holders := {}  # host: id -> {peer: true} who holds that song's bytes


# The songs of a folder listing: [[file name, size in bytes]]; only mp3 / ogg / wav up to 30 MB, by name.
static func from_listing(listing: Array) -> Array:
	var out: Array = []
	for pair: Array in listing:
		var file := String(pair[0])
		var size := int(pair[1])
		if not (file.get_extension().to_lower() in KINDS) or size <= 0 or size > MAX_BYTES:
			continue
		var named := split_name(file)
		out.append({"id": "%s|%d" % [file, size], "file": file, "artist": named["artist"], "title": named["title"], "bytes": size})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["file"]).naturalnocasecmp_to(String(b["file"])) < 0)
	return out


# "Artist - Title.mp3" -> {"artist": "Artist", "title": "Title"}; a name without " - " is all title.
static func split_name(file_name: String) -> Dictionary:
	var stem := file_name.get_basename()
	var cut := stem.find(" - ")
	if cut < 0:
		return {"artist": "", "title": stem.strip_edges()}
	return {"artist": stem.substr(0, cut).strip_edges(), "title": stem.substr(cut + 3).strip_edges()}


func set_songs(list: Array) -> void:
	songs = list
	var known := ids()
	queue = queue.filter(func(id: Variant) -> bool: return known.has(id))
	if now != "" and not known.has(now):
		now = ""


func ids() -> Array:
	return songs.map(func(s: Dictionary) -> String: return String(s["id"]))


func song(id: String) -> Dictionary:
	for s: Dictionary in songs:
		if String(s["id"]) == id:
			return s
	return {}


# Puts a song at the end of the queue (nothing playing: it starts). Returns false for an unknown id.
func add(id: String) -> bool:
	if song(id).is_empty():
		return false
	if now == "":
		now = id
		paused = false
	else:
		queue.append(id)
	return true


# Plays a song right away (what played is dropped, the queue stays).
func play_now(id: String) -> bool:
	if song(id).is_empty():
		return false
	now = id
	paused = false
	return true


# The next one in the queue, or the next song of the list when the queue is empty (the jukebox keeps playing). "" = none.
func skip() -> String:
	if not queue.is_empty():
		now = String(queue.pop_front())
	elif songs.is_empty():
		now = ""
	else:
		var at := ids().find(now)
		now = String(songs[(at + 1) % songs.size()]["id"])
	paused = false
	return now


func stop() -> void:
	now = ""
	paused = false
	queue.clear()


# Host: a peer holds this song now.
func hold(id: String, peer: int) -> void:
	if not holders.has(id):
		holders[id] = {}
	holders[id][peer] = true


# Host: may `id` start (every peer in `peers` holds it)?
func everyone_has(id: String, peers: Array) -> bool:
	var got: Dictionary = holders.get(id, {})
	for peer: Variant in peers:
		if not got.has(int(peer)):
			return false
	return true


# Host: forget a peer that left.
func forget(peer: int) -> void:
	for id: String in holders:
		(holders[id] as Dictionary).erase(peer)
