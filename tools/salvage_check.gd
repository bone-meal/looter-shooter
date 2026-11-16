# Purpose: developer check of sea step 5b's salvage logbook rules (core/sea/salvage_book.gd): the words are read,
# a set fills and pays exactly once, trinkets count and pay once every kind is found, a roll gives a known trinket,
# and a saved book keeps only known ids and cannot claim a paid set it does not hold. Writes tools/salvage_check.log
# ("SALVAGE_CHECK problems=n").
# Dependencies: core/sea/salvage_book.gd, data/sea/salvage.json, data/sea/writing/salvage.txt.
extends Node

const SalvageBook = preload("res://core/sea/salvage_book.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/salvage.json"))
	var words := FileAccess.get_file_as_string("res://data/sea/writing/salvage.txt")
	var book := SalvageBook.new(cfg, words)
	_check(book.name_of("brass_spyglass") == "Brass Spyglass" and String(book.titles.get("region_1", "")) == "Sunlit Shallows", "names and titles read from the writing file")
	for set_id: String in book.set_ids():
		for id: String in book.set_finds(set_id):
			_check(book.names.has(id), "%s has a name" % id)
	for spot: Dictionary in cfg["spots"]:
		if spot.has("plan"):
			_check(String(spot["plan"]).ends_with("_plan"), "spot holds the %s" % spot["plan"])
		else:
			_check(book.set_of(String(spot["find"])) != "", "spot %s belongs to a set" % spot["find"])
	var finds: Array = book.set_finds("region_1")
	var paid := 0
	for id: String in finds:
		if bool(book.record(id).get("complete", false)):
			paid += 1
	_check(paid == 1 and book.have("region_1") == finds.size(), "the set fills and pays once")
	_check(not bool(book.record(String(finds[0]))["complete"]), "logging again pays nothing")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tpaid := 0
	for i in 2000:
		if bool(book.add_trinket(book.roll_trinket(rng)).get("complete", false)):
			tpaid += 1
	_check(tpaid == 1 and book.have("trinkets") == book.set_finds("trinkets").size(), "every trinket kind turns up and pays once (%s)" % str(book.trinkets))
	var copy := SalvageBook.new(cfg, words)
	copy.from_dict(book.to_dict())
	_check(copy.found.size() == book.found.size() and copy.paid.size() == 2, "a saved book loads back")
	var bad := SalvageBook.new(cfg, words)
	bad.from_dict({"found": ["brass_spyglass", "nonsense"], "trinkets": {"old_coin": 3, "gold_bar": 9}, "paid": ["region_1", "trinkets"]})
	_check(bad.found.size() == 1 and not bad.trinkets.has("gold_bar") and bad.paid.is_empty(), "unknown ids and unearned rewards are dropped")
	_lines.append("SALVAGE_CHECK problems=%d" % _problems)
	var f := FileAccess.open("res://tools/salvage_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_problems += 1
