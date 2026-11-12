# Purpose: the rules of what is inside the fantasy world's buildings (data/fantasy/interiors.json): which buildings
# can be entered and what each is inside (a home, a smithy, a bakery ...), where its door is, the furniture of a room,
# and what a search of a container gives. Two ways in: a WALK-IN house (main story; its model is hollow and has
# "walls" and "inner" in props.json) gets its furniture as ordinary things of the open world (`furnish`); every other building
# is entered through its door into a room of its own (`room`). Everything is in a building's own axes: x to the right,
# z towards the back wall; the door is on the -z side (a model's front).
# Dependencies: core/fantasy_terrain.gd (hash01 only). No rendering.
extends RefCounted

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")

var data: Dictionary
var props: Dictionary  # data/fantasy/props.json "props": model -> footprint (and "walls", "inner" for walk-in houses)


func _init(interiors: Dictionary, prop_sizes: Dictionary) -> void:
	data = interiors
	props = prop_sizes


# What a building is inside ("" = it cannot be entered). The same building always answers the same.
func kind_of(model: String, x: float, z: float) -> String:
	var best := ""
	for start: String in data["buildings"]:
		if model.begins_with(start) and start.length() > best.length():
			best = start
	if best == "":
		return ""
	var kinds: Array = data["buildings"][best]
	return String(kinds[int(FantasyTerrain.hash01(int(x), int(z), 77) * 0.999 * float(kinds.size()))])


func walk_in(model: String) -> bool:
	return (props.get(model, {}) as Dictionary).has("inner")  # a gate has "walls" too, but no room inside


# The middle of a building's footprint and its front direction on the map.
func _frame(item: Dictionary) -> Array:
	var size: Dictionary = props.get(String(item["model"]), {})
	var turn := float(item["turn"])
	var right := Vector2(cos(turn), -sin(turn))  # the building's +x on the map (x east, z south)
	var back := Vector2(sin(turn), cos(turn))  # the building's +z
	var middle := Vector2(float(item["x"]), float(item["z"])) + right * float(size.get("x", 0.0)) + back * float(size.get("z", 0.0))
	return [middle, right, back, size]


# The spot on the map just outside a building's door.
func door(item: Dictionary) -> Vector2:
	var f := _frame(item)
	var size: Dictionary = f[3]
	if size.has("walls") and not size.has("inner"):  # roofs and upper floors reach out over the street: the door is in the first solid piece
		var piece: Array = size["walls"][0]
		return Vector2(float(item["x"]), float(item["z"])) + (f[1] as Vector2) * float(piece[0]) + (f[2] as Vector2) * (float(piece[1]) - float(piece[3]) * 0.5 - 0.9)
	return (f[0] as Vector2) - (f[2] as Vector2) * (float(size.get("d", 4.0)) * 0.5 + 0.9)


# How large a building's room is inside (half width, half depth): its footprint without the walls, within limits.
func half_size(model: String) -> Vector2:
	var size: Dictionary = props.get(model, {})
	if size.has("inner"):
		return Vector2(float(size["inner"][0]), float(size["inner"][1]))
	var least: Array = data["smallest"]
	var most: Array = data["largest"]
	return Vector2(clampf(float(size.get("w", 6.0)) - 0.8, float(least[0]), float(most[0])), clampf(float(size.get("d", 6.0)) - 0.8, float(least[1]), float(most[1]))) * 0.5


# The furniture of one kind of room in the building's own axes: [{"model", "x", "z", "turn", "loot", "station"}].
func furniture(kind: String, half: Vector2) -> Array:
	var out: Array = []
	var clear := float(data.get("clear_m", 0.0))
	var may_lie: Array = data.get("clear_skip", [])
	var n := 0
	for rule: Dictionary in data["rooms"][kind]["items"]:
		var x := float(rule["at"][0]) * half.x
		var z := -float(rule["at"][1]) * half.y  # along: -1 is the back wall (+z), 1 the door's wall (-z)
		var size: Dictionary = props.get(String(rule["model"]), {})
		var reach := maxf(float(size.get("w", 1.0)), float(size.get("d", 1.0))) * 0.5
		n += 1
		# The way from the door to the middle stays free (round 5): what stood in it moves aside, as far as the wall allows.
		if clear > 0.0 and z < half.y * 0.25 and absf(x) < clear + reach and not may_lie.has(String(rule["model"])):
			var side := 1.0 if x > 0.01 or (absf(x) <= 0.01 and n % 2 == 0) else -1.0
			x = side * maxf(minf(clear + reach, half.x - reach * 0.7), absf(x))
		out.append({"model": String(rule["model"]), "x": x, "z": z,
			"turn": deg_to_rad(float(rule.get("turn", 0.0))), "loot": String(rule.get("loot", "")), "station": String(rule.get("station", ""))})
	return out


# A walk-in house: its furniture as things of the open world, in map metres (added to the place's own list).
func furnish(item: Dictionary) -> Array:
	var model := String(item["model"])
	var out: Array = []
	if not walk_in(model):
		return out
	var kind := kind_of(model, float(item["x"]), float(item["z"]))
	if kind == "":
		return out
	var f := _frame(item)
	var middle: Vector2 = f[0]
	for piece: Dictionary in furniture(kind, half_size(model)):
		var at: Vector2 = middle + (f[1] as Vector2) * float(piece["x"]) + (f[2] as Vector2) * float(piece["z"])
		out.append({"model": piece["model"], "x": at.x, "z": at.y, "turn": float(item["turn"]) + float(piece["turn"]), "solid": false,
			"station": piece["station"], "loot": piece["loot"], "inside": true})
	return out


# Where somebody stands just after coming in: in a room's own axes (`entry`), and on the map for a walk-in house.
func entry(half: Vector2) -> Vector2:
	return Vector2(0.0, -half.y + 1.0)


func entry_spot(item: Dictionary) -> Vector2:
	var f := _frame(item)
	return (f[0] as Vector2) + (f[2] as Vector2) * entry(half_size(String(item["model"]))).y


# Where to stand and which way to look to see what is really outside a building's side wall (`side`: 1 its right,
# -1 its left): [spot on the map, direction]. For the windows of a room that is entered by a fade.
func window_view(item: Dictionary, side: float) -> Array:
	var f := _frame(item)
	var way: Vector2 = (f[1] as Vector2) * side
	return [(f[0] as Vector2) + way * (float(f[3].get("w", 6.0)) * 0.5 + 0.5), way]


# Where the people who live in a walk-in house stand (map metres), one spot per index.
func standing_spot(item: Dictionary, index: int) -> Vector2:
	var f := _frame(item)
	var half := half_size(String(item["model"]))
	return (f[0] as Vector2) + (f[1] as Vector2) * (half.x * (-0.3 if index % 2 == 0 else 0.35)) - (f[2] as Vector2) * (half.y * 0.45)


# What one search of a container gives: {item id: count}.
func roll(table_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var table: Dictionary = data["loot"].get(table_id, {})
	var out := {}
	if table.is_empty():
		return out
	var items: Dictionary = table["items"]
	var total := 0.0
	for id: String in items:
		total += float(items[id])
	for n in rng.randi_range(int(table["rolls"][0]), int(table["rolls"][1])):
		var pick := rng.randf() * total
		for id: String in items:
			pick -= float(items[id])
			if pick <= 0.0:
				out[id] = int(out.get(id, 0)) + 1
				break
	return out


func refill_seconds(table_id: String) -> float:
	return float((data["loot"].get(table_id, {}) as Dictionary).get("refill_s", 1200.0))
