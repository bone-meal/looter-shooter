# Purpose: one dungeon's puzzle rules (sea step 9a, LOCKED: hand-made from a room kit): the map of cells, its things
# (doors, plates, levers, push blocks, keys, chests, the way in and out) and its state: which doors are open, how
# many keys the party holds here, where the blocks stand, which levers are pulled, keys and chests taken. Doors open
# by a key (for good), by plates pressed (by a player or a block; `latch` keeps it open) or by a lever. Pure: no nodes.
# The host decides every change; clients only show the state they are sent.
# Dependencies: none (one dungeon's data from data/sea/dungeons.json is passed in).
extends RefCounted

var id: String
var cfg: Dictionary  # this dungeon's entry
var tile := 3.0
var size := Vector2i.ZERO  # cells across (x) and down (z)
var things := {}  # letter -> {"kind", "cell": Vector2i, + its data}
var state := {}  # "doors": {letter: true}, "keys": int, "taken": {letter: true}, "levers": {letter: bool}, "blocks": {letter: [x, z]}, "pressed": {letter: bool}
var _rows: Array = []


func _init(dungeon_id: String, entry: Dictionary, tile_m: float) -> void:
	id = dungeon_id
	cfg = entry
	tile = tile_m
	_rows = entry["map"]
	size = Vector2i((_rows[0] as String).length(), _rows.size())
	var legend: Dictionary = entry.get("legend", {})
	for z in size.y:
		var row := String(_rows[z])
		for x in row.length():
			var ch := row[x]
			if legend.has(ch):
				var t: Dictionary = (legend[ch] as Dictionary).duplicate(true)
				t["cell"] = Vector2i(x, z)
				things[ch] = t
	state = fresh()


func fresh() -> Dictionary:
	var blocks := {}
	for ch: String in things:
		if String(things[ch]["kind"]) == "block":
			var c: Vector2i = things[ch]["cell"]
			blocks[ch] = [c.x, c.y]
	return {"doors": {}, "keys": 0, "taken": {}, "levers": {}, "blocks": blocks, "pressed": {}}


# Saved / sent form (blocks as [x, z]); a loaded state missing keys gets them fresh.
func to_dict() -> Dictionary:
	return state.duplicate(true)


func from_dict(d: Dictionary) -> void:
	var base := fresh()
	for k: String in base:
		if d.has(k) and typeof(d[k]) == typeof(base[k]):
			base[k] = d[k]
	base["keys"] = clampi(int(base["keys"]), 0, 99)
	state = base


# --- the map ---

func char_at(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= size.y or cell.x < 0 or cell.x >= String(_rows[cell.y]).length():
		return " "
	return String(_rows[cell.y])[cell.x]


func is_wall(cell: Vector2i) -> bool:
	return char_at(cell) == "#"


func is_floor(cell: Vector2i) -> bool:
	var ch := char_at(cell)
	return ch != "#" and ch != " "


# Local position (from the dungeon's origin) of a cell's middle, floor level.
func at_of(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * tile, 0.0, float(cell.y) * tile)


func cell_of(local: Vector3) -> Vector2i:
	return Vector2i(roundi(local.x / tile), roundi(local.z / tile))


func of_kind(kind: String) -> Array:
	var out: Array = []
	for ch: String in things:
		if String(things[ch]["kind"]) == kind:
			out.append(ch)
	return out


func cell_of_thing(ch: String) -> Vector2i:
	if things.has(ch) and String(things[ch]["kind"]) == "block":
		var b: Array = state["blocks"].get(ch, [0, 0])
		return Vector2i(int(b[0]), int(b[1]))
	return things[ch]["cell"] if things.has(ch) else Vector2i(-1, -1)


# A door's way through: along z when its left and right are walls, else along x.
func door_along_z(ch: String) -> bool:
	var c: Vector2i = things[ch]["cell"]
	return is_wall(c + Vector2i(-1, 0)) and is_wall(c + Vector2i(1, 0))


# --- doors ---

func door_open(ch: String) -> bool:
	var t: Dictionary = things.get(ch, {})
	if t.is_empty():
		return false
	if bool(state["doors"].get(ch, false)):
		return true
	match String(t.get("open", "key")):
		"plates":
			return _all_pressed(t.get("plates", []))
		"lever":
			return bool(state["levers"].get(String(t.get("lever", "")), false))
	return false


func _all_pressed(list: Array) -> bool:
	if list.is_empty():
		return false
	for p: String in list:
		if not bool(state["pressed"].get(p, false)):
			return false
	return true


# Can a body stand in / a block slide into this cell now?
func passable(cell: Vector2i) -> bool:
	if not is_floor(cell):
		return false
	var ch := char_at(cell)
	if things.has(ch) and String(things[ch]["kind"]) == "door" and not door_open(ch):
		return false
	for b: String in state["blocks"]:
		if cell_of_thing(b) == cell:
			return false
	return true


# --- what changes (the host calls these; each returns true when the state changed) ---

# Plates under the given occupied cells (players) or a block. Latching doors open for good.
func press(occupied: Array) -> bool:
	var changed := false
	for p: String in of_kind("plate"):
		var c: Vector2i = things[p]["cell"]
		var on := occupied.has(c)
		for b: String in state["blocks"]:
			on = on or cell_of_thing(b) == c
		if bool(state["pressed"].get(p, false)) != on:
			state["pressed"][p] = on
			changed = true
	for d: String in of_kind("door"):
		var t: Dictionary = things[d]
		if String(t.get("open", "")) == "plates" and bool(t.get("latch", false)) and not bool(state["doors"].get(d, false)) and _all_pressed(t.get("plates", [])):
			state["doors"][d] = true
			changed = true
	return changed


# Where a push from `from` would move the block (Vector2i(-1, -1) = it does not move).
func push_to(block: String, from: Vector2i) -> Vector2i:
	if not state["blocks"].has(block):
		return Vector2i(-1, -1)
	var at := cell_of_thing(block)
	var way := at - from
	if absi(way.x) + absi(way.y) != 1:
		return Vector2i(-1, -1)
	var to := at + way
	var ch := char_at(to)
	if not passable(to) or (things.has(ch) and String(things[ch]["kind"]) in ["key", "chest", "lever", "exit", "arrive", "door"]):
		return Vector2i(-1, -1)
	return to


func push(block: String, from: Vector2i) -> bool:
	var to := push_to(block, from)
	if to.x < 0:
		return false
	state["blocks"][block] = [to.x, to.y]
	return true


func take_key(ch: String) -> bool:
	if not things.has(ch) or String(things[ch]["kind"]) != "key" or bool(state["taken"].get(ch, false)):
		return false
	state["taken"][ch] = true
	state["keys"] = int(state["keys"]) + 1
	return true


func use_key(door: String) -> bool:
	if not things.has(door) or String(things[door].get("open", "")) != "key" or door_open(door) or int(state["keys"]) <= 0:
		return false
	state["keys"] = int(state["keys"]) - 1
	state["doors"][door] = true
	return true


func pull(lever: String) -> bool:
	if not things.has(lever) or String(things[lever]["kind"]) != "lever":
		return false
	state["levers"][lever] = not bool(state["levers"].get(lever, false))
	return true


# A chest opened: its loot table ("" = already open / not a chest).
func open_chest(ch: String) -> String:
	if not things.has(ch) or String(things[ch]["kind"]) != "chest" or bool(state["taken"].get(ch, false)):
		return ""
	state["taken"][ch] = true
	return String(things[ch].get("loot", ""))
