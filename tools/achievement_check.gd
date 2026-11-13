# Purpose: developer check of achievements, titles and emblems (data/achievements.json): every reward exists, every
# emblem's frame / symbol / picture is real, every stat key reads, stat achievements unlock from the record, survive a
# save, and a joiner's card is checked against its readings. Log tools/achievement_check.log (ACHIEVEMENT_CHECK_DONE problems=n).
# Dependencies: core/progress_state.gd, core/achievement_reader.gd, core/stat_book.gd, game/emblem_art.gd, core/data_store.gd.
extends Node

const ProgressState = preload("res://core/progress_state.gd")
const AchievementReader = preload("res://core/achievement_reader.gd")
const StatBook = preload("res://core/stat_book.gd")
const EmblemArt = preload("res://game/emblem_art.gd")
const DataStore = preload("res://core/data_store.gd")
const KINDS := ["total", "group", "sum", "count", "prefix", "countprefix", "every", "ctx", "below"]

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var ach := DataStore.load_json("res://data/achievements.json")
	var cfg := DataStore.load_json("res://data/progression.json")
	var all: Dictionary = ach["achievements"]
	var wrong: Array[String] = []
	var stat_count := 0
	for id: String in all:
		var a: Dictionary = all[id]
		if String(a["emblem"]) != "" and not ach["emblems"].has(String(a["emblem"])):
			wrong.append("%s: no emblem %s" % [id, a["emblem"]])
		if not ach["titles"].has(String(a["title"])):
			wrong.append("%s: no title %s" % [id, a["title"]])
		if a.has("stat"):
			stat_count += 1
			if not KINDS.has(String(a["stat"]).split(":")[0]):
				wrong.append("%s: unknown stat key %s" % [id, a["stat"]])
		elif not a.has("counter"):
			wrong.append("%s: neither counter nor stat" % id)
	_say("%d achievements (%d read from the record), every reward and key known%s" % [all.size(), stat_count, "" if wrong.is_empty() else ": " + "; ".join(wrong)], wrong.is_empty() and all.size() >= 114)
	var pictures := 0
	var layered := 0
	wrong.clear()
	for id: String in ach["emblems"]:
		var e: Dictionary = ach["emblems"][id]
		if e.has("picture"):
			pictures += 1
			if not ResourceLoader.exists(String(e["picture"])):
				wrong.append("%s: picture missing" % id)
		elif e.has("frame"):
			layered += 1
			if not EmblemArt.FRAMES.has(String(e["frame"])) or not EmblemArt.SYMBOLS.has(String(e["symbol"])):
				wrong.append("%s: unknown frame or symbol" % id)
	_say("%d emblems: %d layered, %d painted, all drawable%s" % [ach["emblems"].size(), layered, pictures, "" if wrong.is_empty() else ": " + "; ".join(wrong)], wrong.is_empty() and layered == 90 and pictures == 10)
	var seen := {}
	var titles_used := 0
	for id: String in all:
		var t := String(all[id]["title"])
		if not seen.has(t):
			seen[t] = true
			titles_used += 1
	_say("%d titles, %d different ones given by achievements" % [ach["titles"].size(), titles_used], titles_used >= 114)
	# readings
	var book := StatBook.new()
	book.add("kills", 60.0)
	book.add_to("kills_by_weapon", "knife:karambit", 70.0)
	book.add_to("kills_by_weapon", "knife:flip", 40.0)
	book.add_to("kills_by_weapon", "gun:ak47", 5.0)
	book.add_to("kills_by_enemy", "harvest_king", 1.0)
	book.add_to("kills_by_enemy", "rootmother", 2.0)
	book.add_to("powerups", "nuke", 3.0)
	var extra := {"course_best": 23.4, "best_round": 12, "skill:magic": 7}
	var reads := {
		"total:kills": 60, "group:kills_by_weapon:gun:ak47": 5, "prefix:kills_by_weapon:knife:": 110, "countprefix:kills_by_weapon:knife:": 2,
		"every:kills_by_enemy:harvest_king,rootmother,pallid_king": 2, "count:powerups": 1, "sum:kills_by_weapon": 115, "ctx:best_round": 12,
		"ctx:skill:magic": 7, "below:ctx:course_best:25": 1, "below:ctx:course_best:20": 0, "group:kills_by_enemy:nobody": 0}
	var off: Array[String] = []
	for key: String in reads:
		var got := AchievementReader.read(key, book, extra)
		if got != int(reads[key]):
			off.append("%s = %d (want %d)" % [key, got, reads[key]])
	_say("every kind of stat key reads right%s" % ("" if off.is_empty() else ": " + "; ".join(off)), off.is_empty())
	# unlocking, saving, host check
	var p := ProgressState.new(cfg, ach)
	var values := {}
	for key: String in p.stat_keys():
		values[key] = AchievementReader.read(key, book, extra)
	p.read_stats(values)
	var fresh: Array = p.take_unlocked()
	var want: Array = ["kills_50", "knife_100", "best_10", "course_40", "course_25", "f_harvest", "f_root"]
	var missing: Array = want.filter(func(id: String) -> bool: return not fresh.has(id))
	_say("the record unlocks %s%s" % [", ".join(fresh), "" if missing.is_empty() else " (missing %s)" % ", ".join(missing)], missing.is_empty() and not fresh.has("kills_500"))
	p.read_stats({"total:kills": 3})
	_say("a lower reading never takes a reading back (kills still %d)" % int(p.stat_values["total:kills"]), int(p.stat_values["total:kills"]) == 60)
	p.set_card("Tester", "e_knife_100", "knife_fighter")
	var saved: Variant = JSON.parse_string(JSON.stringify(p.to_dict()))
	var back := ProgressState.new(cfg, ach)
	back.from_dict(saved)
	_say("stat unlocks and the card survive a save (%d unlocked, emblem %s, title %s)" % [back.unlocked.size(), back.emblem, back.title], back.unlocked.size() == p.unlocked.size() and back.emblem == "e_knife_100" and back.title == "knife_fighter")
	_say("the host accepts that card", p.check(saved) == "")
	var faked: Dictionary = (saved as Dictionary).duplicate(true)
	faked["stats"]["prefix:kills_by_weapon:knife:"] = 20
	var why := p.check(faked)
	_say("the host refuses a card whose reading does not reach the goal (%s)" % why, why != "")
	var forged: Dictionary = (saved as Dictionary).duplicate(true)
	forged["stats"]["total:kills"] = 60
	(forged["unlocked"] as Array).append("kills_500")
	why = p.check(forged)
	_say("the host refuses an unlock with no reading behind it (%s)" % why, why != "")
	var edited: Dictionary = (saved as Dictionary).duplicate(true)
	edited["stats"]["total:kills"] = 2
	var loaded := ProgressState.new(cfg, ach)
	loaded.from_dict(edited)
	_say("loading an edited save drops the unlock its reading no longer reaches", not loaded.unlocked.has("kills_50") and loaded.unlocked.has("knife_100"))
	_finish()


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("ACHIEVEMENT_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/achievement_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
