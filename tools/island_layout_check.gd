# Purpose: (polish1 D4a) checks the islands' layout: every thing that stands on an island (data files with "island" +
# "at": perks, wall buys, shelters, the box, power parts, buildables, quest spots, the boat, the bank, spots ...)
# is on dry, flat ground: not on a hill, not in or against a ridge, ruin or boulder; the bridges' ends are clear too.
# Run: godot --headless --path . --script res://tools/island_layout_check.gd  (ISLAND_LAYOUT lines, "problems n").
# Dependencies: core/archipelago.gd, core/data_store.gd, the data files listed below.
extends SceneTree

const Archipelago = preload("res://core/archipelago.gd")
const DataStore = preload("res://core/data_store.gd")
const FILES := ["perks", "traps", "upgrade_machine", "power", "buildables", "mystery_box", "zombies/quest", "archipelago"]

var _problems := 0
var _land: Archipelago


func _init() -> void:
	_land = Archipelago.new(DataStore.load_json("res://data/archipelago.json"))
	var n := 0
	for f: String in FILES:
		n += _walk(DataStore.load_json("res://data/%s.json" % f), f)
	var bank: Array = DataStore.load_json("res://data/bank.json")["place"]
	_check(Vector2(float(bank[0]), float(bank[1])), "bank", 1.5)
	n += 1
	for i in _land.bridges.size():
		for end: String in ["a", "b"]:
			var p: Vector2 = _land.bridges[i][end]
			if _land.blocked(p.x, p.y, 4.0, true):
				_problem("bridge %d end %s is blocked" % [i, end])
	print("ISLAND_LAYOUT %d spots checked, %d blocks, problems %d" % [n, _land.blocks.size(), _problems])
	quit()


func _walk(v: Variant, where: String) -> int:
	var n := 0
	if v is Dictionary:
		var d: Dictionary = v
		if d.get("island") is String and d.get("at") is Array and _land.index_of(String(d["island"])) >= 0:
			var p := _land.on_island(String(d["island"]), d["at"])
			_check(p, "%s %s" % [where, String(d["island"])], 11.0 if where.contains("shelters") else 2.5)  # (a 12 x 9 m hut: 7.5 m to a corner + room to walk round it)
			n += 1
		for k: Variant in d:
			n += _walk(d[k], "%s.%s" % [where, str(k)])
	elif v is Array:
		for i in (v as Array).size():
			n += _walk(v[i], "%s[%d]" % [where, i])
	return n


func _check(p: Vector2, what: String, margin: float) -> void:
	if where_sea(p):
		return
	if _land.blocked(p.x, p.y, margin, true):
		_problem("%s at (%.1f, %.1f) is on a hill or against a ridge / ruin / boulder" % [what, p.x, p.y])


func where_sea(p: Vector2) -> bool:  # a spot meant for the water (the boat) is fine anywhere off the land
	return _land.height_at(p.x, p.y) < _land.sea_level


func _problem(text: String) -> void:
	_problems += 1
	print("ISLAND_LAYOUT PROBLEM " + text)
