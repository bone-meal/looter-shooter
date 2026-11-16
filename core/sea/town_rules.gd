# Purpose: the HOME PORT TOWN's rules (sea step 7), pure: the plots of data/sea/town.json, the level each building
# stands at (0 = run down, waiting to be repaired; the hamlet's harbour master, dock and shipyard start at 1), what
# the next level costs (materials of the fantasy bag + doubloons), whether a player can pay, and the town as saved in
# the host's world (profile extra "sea_town"). Nothing here touches the scene.
# Dependencies: none (data/sea/town.json is handed in).
extends RefCounted

var cfg: Dictionary
var levels := {}  # plot id -> level


func _init(data: Dictionary) -> void:
	cfg = data
	reset()


func reset() -> void:
	levels.clear()
	for p: Dictionary in cfg["plots"]:
		levels[String(p["id"])] = clampi(int(p.get("start", 0)), 0, (p["levels"] as Array).size())


func plots() -> Array:
	return cfg["plots"]


func ids() -> Array:
	var out: Array = []
	for p: Dictionary in cfg["plots"]:
		out.append(String(p["id"]))
	return out


func plot(id: String) -> Dictionary:
	for p: Dictionary in cfg["plots"]:
		if String(p["id"]) == id:
			return p
	return {}


func index_of(id: String) -> int:
	return ids().find(id)


func level(id: String) -> int:
	return int(levels.get(id, 0))


func top(id: String) -> int:
	var p := plot(id)
	return (p["levels"] as Array).size() if not p.is_empty() else 0


# The level's entry (name, look, cost, adds); level 0 = the run-down plot.
func entry(id: String, at: int) -> Dictionary:
	var p := plot(id)
	if p.is_empty() or at <= 0 or at > top(id):
		return {"name": "Run down", "look": -1, "cost": {}, "adds": "Waiting to be repaired."}
	return (p["levels"] as Array)[at - 1]


func next_entry(id: String) -> Dictionary:
	return entry(id, level(id) + 1) if level(id) < top(id) else {}


# The model the plot shows now: "<building>_<level>".
func model(id: String) -> String:
	return "%s_%d" % [String(plot(id).get("building", id)), level(id)]


func cost(id: String) -> Dictionary:
	var e := next_entry(id)
	return e.get("cost", {}) if not e.is_empty() else {}


# What is still missing for the next level: [[item id or "doubloons", need, have], ...] (empty = can pay).
# `have_item` = Callable(id) -> count in the player's bag.
func missing(id: String, have_item: Callable, doubloons: int) -> Array:
	var out: Array = []
	var c := cost(id)
	if c.is_empty():
		return out
	if doubloons < int(c.get("doubloons", 0)):
		out.append(["doubloons", int(c.get("doubloons", 0)), doubloons])
	var items: Dictionary = c.get("items", {})
	for item: String in items:
		var have := int(have_item.call(item))
		if have < int(items[item]):
			out.append([item, int(items[item]), have])
	return out


func can_upgrade(id: String, have_item: Callable, doubloons: int) -> bool:
	return level(id) < top(id) and missing(id, have_item, doubloons).is_empty()


# Raises the plot one level (the host decides; the payer paid). Returns false if it cannot rise.
func upgrade(id: String) -> bool:
	if plot(id).is_empty() or level(id) >= top(id):
		return false
	levels[id] = level(id) + 1
	return true


# How grown the town is: the sum of all levels over the sum of all tops (0..1).
func growth() -> float:
	var have := 0
	var most := 0
	for id: String in ids():
		have += level(id)
		most += top(id)
	return float(have) / float(maxi(most, 1))


# The town's streets by its growth: 0 dirt tracks, 1 cobbles, 2 flagstones (data "paving_at").
func paving() -> int:
	var at: Array = cfg.get("paving_at", [0.3, 0.65])
	var g := growth()
	return 2 if g >= float(at[1]) else (1 if g >= float(at[0]) else 0)


# Which residents' house stands on lot i at this growth ("" = none yet): more lots fill as the town grows (the first
# few from the start, nearest the plaza first) and each is rebuilt in newer styles, not all at once.
func house_model(i: int, g: float) -> String:
	var lots: Array = cfg.get("houses", [])
	if i < 0 or i >= lots.size():
		return ""
	var first := int(cfg.get("houses_at_start", 3))
	var standing := mini(lots.size(), first + floori(g * float(lots.size() - first) * 1.25))
	if i >= standing:
		return ""
	var style := clampi(floori(g * 5.0 - float(i % 4) * 0.3), 0, 4)
	return "house_%d_%d" % [int((lots[i] as Dictionary).get("variant", 0)), style]


# Levels in plot order (sent online).
func to_list() -> Array:
	var out: Array = []
	for id: String in ids():
		out.append(level(id))
	return out


func from_list(list: Variant) -> bool:
	if not list is Array or (list as Array).size() != ids().size():
		return false
	var changed := false
	var all := ids()
	for i in all.size():
		var v: Variant = (list as Array)[i]
		if not (v is int or v is float):
			continue
		var lv := clampi(int(v), 0, top(String(all[i])))
		if lv != level(String(all[i])):
			levels[String(all[i])] = lv
			changed = true
	return changed


func to_dict() -> Dictionary:
	return {"levels": levels.duplicate()}


# A saved town (unknown plots dropped, levels clamped; a plot missing from the save keeps its start level).
func from_dict(saved: Variant) -> void:
	reset()
	if not saved is Dictionary or not (saved as Dictionary).get("levels") is Dictionary:
		return
	var got: Dictionary = saved["levels"]
	for id: String in ids():
		var v: Variant = got.get(id)
		if v is int or v is float:
			levels[id] = clampi(int(v), 0, top(id))
