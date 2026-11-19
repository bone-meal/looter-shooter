# Purpose: pure rules of the salvage logbook (sea step 5b): which hand-placed finds a character has logged (each
# fills its region's set; a full set pays once), the random trinkets found on dives (counted; every kind found once
# pays once), the roll for a random find, and the words from data/sea/writing/salvage.txt. Saved with the character
# (to_dict / from_dict keeps only known ids and sane counts).
# Dependencies: none (data/sea/salvage.json and the writing file's text passed in).
extends RefCounted

const TRINKETS := "trinkets"

var cfg: Dictionary  # data/sea/salvage.json
var found := {}  # set find id -> true
var trinkets := {}  # trinket id -> how many
var paid := {}  # set id ("region_1" .. or "trinkets") -> true once its reward was paid
var names := {}  # id -> name
var lines := {}  # id -> line
var titles := {}  # set id -> title
var done_lines := {}  # set id -> line when full

var _set_of := {}  # find id -> set id
var _trinket_ids: Array = []


func _init(salvage_cfg: Dictionary, writing: String) -> void:
	cfg = salvage_cfg
	for set_id: String in cfg["sets"]:
		for find: String in cfg["sets"][set_id]["finds"]:
			_set_of[find] = set_id
	for t: Dictionary in cfg["trinkets"]["finds"]:
		_trinket_ids.append(String(t["id"]))
	_read(writing)


func _read(text: String) -> void:
	var section := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("["):
			section = line.trim_prefix("[").trim_suffix("]")
			continue
		var colon := line.find(":")
		if colon < 0:
			continue
		var key := line.substr(0, colon).strip_edges()
		var value := line.substr(colon + 1).strip_edges()
		if section.begins_with("set "):
			var set_id := section.substr(4)
			if key == "title":
				titles[set_id] = value
			elif key == "done":
				done_lines[set_id] = value
		elif section == "finds":
			var bar := value.find("|")
			names[key] = value.substr(0, bar).strip_edges() if bar >= 0 else value
			lines[key] = value.substr(bar + 1).strip_edges() if bar >= 0 else ""


func name_of(id: String) -> String:
	return String(names.get(id, id.capitalize()))


func set_ids() -> Array:
	return (cfg["sets"] as Dictionary).keys()


func set_of(find: String) -> String:
	return String(_set_of.get(find, ""))


func set_finds(set_id: String) -> Array:
	return _trinket_ids if set_id == TRINKETS else cfg["sets"][set_id]["finds"]


func have(set_id: String) -> int:
	var n := 0
	for id: String in set_finds(set_id):
		if (trinkets.get(id, 0) > 0) if set_id == TRINKETS else found.has(id):
			n += 1
	return n


func reward(set_id: String) -> Dictionary:
	return cfg["trinkets"]["reward"] if set_id == TRINKETS else cfg["sets"][set_id]["reward"]


# Logs a hand-placed find. Returns {"new", "set", "have", "of", "complete"} (complete = the set just filled up:
# pay its reward now; it is marked paid here).
func record(find: String) -> Dictionary:
	var set_id := set_of(find)
	if set_id == "":
		return {}
	var fresh := not found.has(find)
	found[find] = true
	return _result(set_id, fresh)


# A random trinket brought up from a dive (same answer as record).
func add_trinket(id: String) -> Dictionary:
	if not _trinket_ids.has(id):
		return {}
	var fresh := int(trinkets.get(id, 0)) == 0
	trinkets[id] = int(trinkets.get(id, 0)) + 1
	return _result(TRINKETS, fresh)


func _result(set_id: String, fresh: bool) -> Dictionary:
	var of := set_finds(set_id).size()
	var now := have(set_id)
	var complete := now >= of and not paid.has(set_id)
	if complete:
		paid[set_id] = true
	return {"new": fresh, "set": set_id, "have": now, "of": of, "complete": complete}


# A random trinket by weight (rng = RandomNumberGenerator).
func roll_trinket(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for t: Dictionary in cfg["trinkets"]["finds"]:
		total += float(t["weight"])
	var pick := rng.randf() * total
	for t: Dictionary in cfg["trinkets"]["finds"]:
		pick -= float(t["weight"])
		if pick <= 0.0:
			return String(t["id"])
	return String(_trinket_ids.back())


func icon_of(id: String) -> String:
	for t: Dictionary in cfg["trinkets"]["finds"]:
		if String(t["id"]) == id:
			return String(t["icon"])
	return String(cfg.get("icons", {}).get(id, "relic"))


func to_dict() -> Dictionary:
	return {"found": found.keys(), "trinkets": trinkets.duplicate(), "paid": paid.keys()}


func from_dict(saved: Variant) -> void:
	found.clear()
	trinkets.clear()
	paid.clear()
	if not saved is Dictionary:
		return
	if saved.get("found") is Array:
		for id: Variant in saved["found"]:
			if _set_of.has(str(id)) or ((str(id).begins_with("hoard:") or str(id).begins_with("riddle:")) and str(id).length() <= 40):  # (hoards taken, riddles read: sea steps 9d / 13d)
				found[str(id)] = true
	if saved.get("trinkets") is Dictionary:
		for id: Variant in saved["trinkets"]:
			if _trinket_ids.has(str(id)):
				trinkets[str(id)] = clampi(int(saved["trinkets"][id]), 0, 99999)
	if saved.get("paid") is Array:
		for id: Variant in saved["paid"]:
			var set_id := str(id)
			if (set_id == TRINKETS or (cfg["sets"] as Dictionary).has(set_id)) and have(set_id) >= set_finds(set_id).size():
				paid[set_id] = true  # only a set that is really full can have been paid
