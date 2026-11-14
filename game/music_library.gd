# Purpose: the player's own Music folder (locked: "Music" inside the game's save folder; the game ships no songs):
# where it is, opening it in the computer's file browser, what lies in it, a song's bytes, and turning bytes (from
# the folder or sent by the host) into something to play (mp3 / ogg / wav).
# Dependencies: core/music_queue.gd (the listing rules).
extends RefCounted

const MusicQueue = preload("res://core/music_queue.gd")
const FOLDER := "user://Music"


static func ensure() -> void:
	if not DirAccess.dir_exists_absolute(FOLDER):
		DirAccess.make_dir_recursive_absolute(FOLDER)


# Opens the folder in Explorer / Finder / the file manager so songs can be added or changed.
static func open_folder() -> void:
	ensure()
	OS.shell_open(ProjectSettings.globalize_path(FOLDER))


# The songs lying in the folder now (core/music_queue.gd song dictionaries, by name).
static func scan() -> Array:
	ensure()
	var listing: Array = []
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		return []
	for file: String in dir.get_files():
		var f := FileAccess.open(FOLDER.path_join(file), FileAccess.READ)
		if f != null:
			listing.append([file, f.get_length()])
	return MusicQueue.from_listing(listing)


static func bytes_of(file: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(FOLDER.path_join(file.get_file()))  # get_file: never a path out of the folder


# Something to play from a song's bytes; null when they are not a song this game can read.
static func stream(file: String, bytes: PackedByteArray) -> AudioStream:
	if bytes.is_empty():
		return null
	match file.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_buffer(bytes)
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	return null
