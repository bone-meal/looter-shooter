# Purpose: developer check of the jukebox (locked hub plan, jukebox rework): the queue rules (core/music_queue.gd:
# which files count, add / play now / skip / stop, who holds a song before it may start) and the Music folder
# (game/music_library.gd: a song written there is listed and plays from its bytes). It writes one short test tone
# "Zz Check - Tone.wav" into user://Music and takes it away again. Log tools/music_check.log (MUSIC_CHECK_DONE problems=n).
# Dependencies: core/music_queue.gd, game/music_library.gd.
extends Node

const MusicQueue = preload("res://core/music_queue.gd")
const MusicLibrary = preload("res://game/music_library.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var songs := MusicQueue.from_listing([["b.mp3", 100], ["A - Song.ogg", 50], ["notes.txt", 10], ["huge.wav", MusicQueue.MAX_BYTES + 1], ["empty.mp3", 0], ["c.WAV", 20]])
	var names: Array = songs.map(func(s: Dictionary) -> String: return String(s["file"]))
	_say("only mp3 / ogg / wav up to 30 MB count, by name (%s)" % ", ".join(PackedStringArray(names)), names == ["A - Song.ogg", "b.mp3", "c.WAV"])
	_say("\"Artist - Title\" names split (%s / %s)" % [songs[0]["artist"], songs[0]["title"]], String(songs[0]["artist"]) == "A" and String(songs[0]["title"]) == "Song")
	var q := MusicQueue.new()
	q.set_songs(songs)
	var a := String(songs[0]["id"])
	var b := String(songs[1]["id"])
	var c := String(songs[2]["id"])
	_say("adding with nothing playing starts it", q.add(b) and q.now == b and q.queue.is_empty())
	_say("adding while one plays queues it", q.add(c) and q.add(a) and q.queue == [c, a])
	_say("an unknown song is refused", not q.add("nope|1") and not q.play_now("nope|1"))
	_say("skip takes the queue first", q.skip() == c and q.queue == [a])
	_say("play now jumps in, the queue stays", q.play_now(b) and q.now == b and q.queue == [a])
	q.skip()
	_say("with an empty queue skip goes on down the list (%s)" % q.skip(), q.now == b)
	q.stop()
	_say("stop clears it all", q.now == "" and q.queue.is_empty())
	q.hold(a, 1)
	_say("a song waits until every player holds it", not q.everyone_has(a, [1, 7]))
	q.hold(a, 7)
	_say("and may start when all do", q.everyone_has(a, [1, 7]))
	q.set_songs([songs[1]])
	_say("a song gone from the folder leaves the queue", q.song(a).is_empty())
	# the folder
	var tone := AudioStreamWAV.new()
	tone.format = AudioStreamWAV.FORMAT_16_BITS
	tone.mix_rate = 22050
	var pcm := PackedByteArray()
	pcm.resize(22050 * 2)
	for i in 22050:
		pcm.encode_s16(i * 2, int(sin(float(i) * TAU * 440.0 / 22050.0) * 8000.0))
	tone.data = pcm
	MusicLibrary.ensure()
	var path := MusicLibrary.FOLDER.path_join("Zz Check - Tone.wav")
	tone.save_to_wav(path)
	var listed: Array = MusicLibrary.scan().filter(func(s: Dictionary) -> bool: return String(s["file"]) == "Zz Check - Tone.wav")
	_say("a song put into the Music folder is listed (%s)" % ProjectSettings.globalize_path(MusicLibrary.FOLDER), listed.size() == 1)
	var bytes := MusicLibrary.bytes_of("Zz Check - Tone.wav")
	var played := MusicLibrary.stream("Zz Check - Tone.wav", bytes)
	_say("its bytes become something to play (%d bytes, %.2f s)" % [bytes.size(), played.get_length() if played != null else 0.0], played != null and played.get_length() > 0.9)
	_say("a path out of the folder is not read", MusicLibrary.bytes_of("../override.cfg").is_empty())
	DirAccess.remove_absolute(path)
	_finish()


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("MUSIC_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/music_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
