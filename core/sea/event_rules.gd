# Purpose: pure rules of the friendly / odd SEA EVENTS (sea step 13d; plan diary/DESIGN_REGION1.md): which event comes
# (kinds by weight from their regions, the weather a kind avoids, castaways only while one is still out there), the
# goods a merchant raft offers, the next castaway, the next riddle a player has not read, the whale pod's path, and
# the writing file's words (data/sea/writing/events_r1.txt). No nodes, no engine state.
# Dependencies: data/sea/events.json (cfg), the writing file's text (given to setup).
extends RefCounted

var cfg: Dictionary
var words := {}  # section -> id -> Array of the line's parts ("|"-separated); notices: key -> [text]


func _init(config: Dictionary, writing: String) -> void:
	cfg = config
	var section := ""
	for raw: String in writing.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("["):
			section = line.trim_prefix("[").trim_suffix("]")
			words[section] = {}
			continue
		var at := line.find(":")
		if at < 0 or section == "":
			continue
		var parts: Array = []
		for p: String in line.substr(at + 1).split("|"):
			parts.append(p.strip_edges())
		words[section][line.substr(0, at).strip_edges()] = parts


static func region_number(region_id: String) -> int:
	return maxi(1, int(region_id.trim_prefix("region_"))) if region_id.begins_with("region_") else 0


# A kind for this region and weather ("" = none); `castaways_left` false drops the castaway; `roll` in 0..1.
func pick(region_id: String, weather: String, castaways_left: bool, roll: float) -> String:
	var n := region_number(region_id)
	var total := 0.0
	var fits: Array = []
	for kind: String in cfg["kinds"]:
		var k: Dictionary = cfg["kinds"][kind]
		if not (k["regions"] as Array).has(float(n)) and not (k["regions"] as Array).has(n):
			continue
		if (k.get("not_weather", []) as Array).has(weather):
			continue
		if kind == "castaway" and not castaways_left:
			continue
		fits.append(kind)
		total += float(k["weight"])
	var left := roll * total
	for kind: String in fits:
		left -= float(cfg["kinds"][kind]["weight"])
		if left < 0.0:
			return kind
	return String(fits.back()) if not fits.is_empty() else ""


# The indexes of a raft's goods in its region's stock (`offers` of them, no repeats).
func offers(rng: RandomNumberGenerator) -> Array:
	var stock: Array = cfg["merchant"]["stock"][String(cfg["merchant"]["region_stock"])]
	var left: Array = range(stock.size())
	var out: Array = []
	for i in mini(int(cfg["merchant"]["offers"]), stock.size()):
		out.append(left.pop_at(rng.randi_range(0, left.size() - 1)))
	out.sort()
	return out


func stock_entry(index: int) -> Dictionary:
	var stock: Array = cfg["merchant"]["stock"][String(cfg["merchant"]["region_stock"])]
	return stock[index] if index >= 0 and index < stock.size() else {}


# The next castaway still out at sea ("" = all of them live in the town).
func next_castaway(home: Array, out_now: Array) -> String:
	for id: String in cfg["castaway"]["who"]:
		if not home.has(id) and not out_now.has(id):
			return id
	return ""


# Where a castaway who moved into town stands (sea x, z), by his place in the list.
func stand_of(id: String) -> Vector2:
	var k := (cfg["castaway"]["who"] as Array).find(id)
	var spots: Array = cfg["castaway"]["stand"]
	var s: Array = spots[clampi(k, 0, spots.size() - 1)]
	return Vector2(float(s[0]), float(s[1]))


# The first riddle of a region this player has not read yet ({} = none left). `read` = has the logbook got
# "riddle:<id>".
func next_riddle(region_id: String, read: Callable) -> Dictionary:
	for r: Dictionary in cfg["bottle"]["riddles"]:
		if String(r["region"]) == region_id and not bool(read.call(String(r["id"]))):
			return r
	return {}


func riddle_text(id: String) -> String:
	var parts: Array = (words.get("riddles", {}) as Dictionary).get(id, [""])
	return String(parts[0]).replace(" / ", "\n")


func name_of(section: String, id: String) -> String:
	var parts: Array = (words.get(section, {}) as Dictionary).get(id, [id])
	return String(parts[0])


# A line of a merchant / castaway (part k of its entry; "" when missing).
func line_of(section: String, id: String, k: int) -> String:
	var parts: Array = (words.get(section, {}) as Dictionary).get(id, [])
	return String(parts[k]) if k < parts.size() else ""


func notice(key: String) -> String:
	var parts: Array = (words.get("notices", {}) as Dictionary).get(key, [key])
	return String(parts[0])


# The whale pod's line past a player at `at` (sea x, z): starts start_back_m behind him along `way` (unit), offset
# `side` metres to one side; returns [start, way].
func pod_line(at: Vector2, way: Vector2, side: float) -> Array:
	var across := Vector2(-way.y, way.x)
	return [at - way * float(cfg["whales"]["start_back_m"]) + across * side, way]
