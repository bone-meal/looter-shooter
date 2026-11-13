# Purpose: developer check of the main quest (core/quest_state.gd with data/zombies/quest.json and the writers'
# data/zombies/writing/quest.txt) and the hidden songs (core/song_book.gd with data/zombies/songs.json): every step
# has its texts and its things on dry land, the steps finish on the right events in order, the state travels as
# plain data, song files and names, floats and unlocks. Log tools/quest_check.log (ends QUEST_CHECK_DONE problems=n).
# Dependencies: core/quest_state.gd, core/song_book.gd, core/text_book.gd, core/archipelago.gd, core/data_store.gd.
extends Node

const QuestState = preload("res://core/quest_state.gd")
const SongBook = preload("res://core/song_book.gd")
const TextBook = preload("res://core/text_book.gd")
const Archipelago = preload("res://core/archipelago.gd")
const DataStore = preload("res://core/data_store.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var land := Archipelago.new(DataStore.load_json("res://data/archipelago.json"))
	var cfg: Dictionary = DataStore.load_json("res://data/zombies/quest.json")
	var quest := QuestState.new()
	quest.setup(cfg, TextBook.read_files(PackedStringArray(["res://data/zombies/writing/quest.txt"])))
	var missing := quest.text_problems()
	_say("the writers' file has every step's lines%s" % ("" if missing.is_empty() else ": " + "; ".join(missing)), missing.is_empty())
	var dry := true
	var where := PackedStringArray()
	for entry: Dictionary in quest.steps():
		var places: Array = entry.get("spots", []).duplicate()
		if entry.has("at"):
			places.append(entry)
		for place: Dictionary in places:
			var spot := land.on_island(String(place["island"]), place["at"])
			if land.index_of(String(place["island"])) < 0 or land.height_at(spot.x, spot.y) < -0.05:
				dry = false
				where.append(String(entry["id"]))
	_say("every step's thing stands on dry land of an island that exists%s" % ("" if dry else ": NOT " + ", ".join(where)), dry)
	var builds: Array = []
	for thing: Dictionary in DataStore.load_json("res://data/buildables.json")["things"]:
		builds.append(String(thing["id"]))
	var known := true
	for entry: Dictionary in quest.steps():
		if String(entry["kind"]) == "build":
			known = known and builds.has(String(entry["thing"]))
		if String(entry["kind"]) == "boss":
			known = known and (DataStore.load_json("res://data/enemies.json")["enemies"] as Dictionary).has(String(entry["enemy"]))
	_say("its buildable and its boss exist", known)

	_say("it starts at the first step, nothing done", quest.step == 0 and quest.kind() == "use" and not quest.done())
	_say("the wrong things do not finish a step", not quest.power_is_on(true) and not quest.built("boat") and not quest.killed_near() and not quest.lamp_out(0) and not quest.boss_killed() and not quest.used("bell"))
	var walked := PackedStringArray()
	var guard := 0
	while not quest.done() and guard < 20:
		guard += 1
		var entry := quest.current()
		var finished := false
		match quest.kind():
			"use":
				finished = quest.used(String(entry["id"]))
			"power":
				finished = quest.power_is_on(true)
			"build":
				finished = quest.built(String(entry["thing"]))
			"kills":
				for _kill in int(entry["count"]) - 1:
					finished = finished or quest.killed_near()
				finished = not finished and quest.killed_near()
			"shoot":
				for i in (entry["spots"] as Array).size() - 1:
					finished = finished or quest.lamp_out(i)
				finished = not finished and not quest.lamp_out(0) and quest.lamp_out((entry["spots"] as Array).size() - 1)
			"boss":
				var early := quest.boss_killed()
				quest.boss_out = true
				finished = not early and quest.boss_killed()
		walked.append("%s %s" % [String(entry["id"]), "ok" if finished else "STUCK"])
		if not finished:
			break
		var copy := QuestState.new()
		copy.setup(cfg, {})
		copy.from_dict(quest.to_dict())
		quest.advance()
	_say("played through in order, each step finished only by its own event: %s" % ", ".join(walked), quest.done() and not walked.has("STUCK"))
	quest.reset()
	quest.advance()
	quest.advance()
	quest.killed_near()
	quest.killed_near()
	var copy := QuestState.new()
	copy.setup(cfg, {})
	copy.from_dict(quest.to_dict())
	_say("the state travels as plain data (step %d, %d kills)" % [copy.step, copy.count], copy.step == 2 and copy.count == 2 and copy.kind() == "kills")
	quest.reset()
	_say("game over: back to the first step", quest.step == 0)

	var songs_cfg: Dictionary = DataStore.load_json("res://data/zombies/songs.json")
	var book := SongBook.new()
	book.setup(songs_cfg)
	var floats_dry := book.secret_count() == 10
	var spots: Array[Vector2] = []
	for secret: Dictionary in songs_cfg["secrets"]:
		floats_dry = floats_dry and (secret["things"] as Array).size() == 3
		for thing: Dictionary in secret["things"]:
			var spot := land.on_island(String(thing["island"]), thing["at"])
			floats_dry = floats_dry and land.height_at(spot.x, spot.y) > -0.05
			for other: Vector2 in spots:
				floats_dry = floats_dry and spot.distance_to(other) > 3.0
			spots.append(spot)
	_say("ten secrets of three floats, all on dry land and apart", floats_dry)
	book.set_files(PackedStringArray(["b - Two.mp3", "readme.txt", "A Band - One Song.mp3", "plain.ogg"]))
	_say("song files: only music counts, sorted by name (%s)" % str(book.files), book.files == PackedStringArray(["A Band - One Song.mp3", "b - Two.mp3", "plain.ogg"]))
	_say("names: the artist is before the dash, the rest is the title; no dash = all title", book.song(0)["artist"] == "A Band" and book.song(0)["title"] == "One Song" and book.song(2)["artist"] == "" and book.song(2)["title"] == "plain" and book.song(3).is_empty())
	_say("two floats of a secret do not unlock it; the third does, once", not book.shoot(4, 0) and not book.shoot(4, 0) and not book.shoot(4, 2) and book.shoot(4, 1) and book.unlocked == ([4] as Array[int]) and not book.is_shot(4, 0))
	var saved := book.to_list()
	var again := SongBook.new()
	again.setup(songs_cfg)
	again.from_list(saved + [99, -1, "x"])
	_say("unlocks are saved and read back (nonsense dropped)", again.unlocked == ([4] as Array[int]))

	_lines.append("QUEST_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/quest_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
