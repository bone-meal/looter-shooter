# Purpose: pure rules of the islands' buildables (the shield, the boat): which parts of each the party has found and
# which things are built. No nodes. Things are named by their place in the data's list.
# Dependencies: none. Data: data/buildables.json, passed to the constructor.
extends RefCounted

const BENCH := 99  # the "part" number that means a thing's bench (see code_of)

var ids: Array[String] = []
var names: Array[String] = []

var _found: Array = []  # per thing: Array[bool], one per part
var _built: Array[bool] = []


func _init(config: Dictionary) -> void:
	for thing: Dictionary in config["things"]:
		ids.append(String(thing["id"]))
		names.append(String(thing["name"]))
		var parts: Array[bool] = []
		parts.resize((thing["parts"] as Array).size())
		parts.fill(false)
		_found.append(parts)
		_built.append(false)


func index_of(id: String) -> int:
	return ids.find(id)


# One number for "part p of thing t" (or its bench), to ask the host with; and back.
static func code_of(thing: int, part: int) -> int:
	return thing * 100 + part


static func thing_of(code: int) -> int:
	return floori(float(code) / 100.0) if code >= 0 else -1


static func part_of(code: int) -> int:
	return code % 100


func part_count(thing: int) -> int:
	return (_found[thing] as Array).size()


func found(thing: int) -> Array[bool]:
	return _found[thing]


func found_count(thing: int) -> int:
	return (_found[thing] as Array).count(true)


func all_found(thing: int) -> bool:
	return not (_found[thing] as Array).has(false)


func built(thing: int) -> bool:
	return thing >= 0 and thing < _built.size() and _built[thing]


# A part is picked up; false when it already was (or there is no such part).
func take(thing: int, part: int) -> bool:
	if thing < 0 or thing >= _found.size() or part < 0 or part >= part_count(thing) or bool(_found[thing][part]):
		return false
	_found[thing][part] = true
	return true


# The thing is put together at its bench; false while a part is missing or it is built already.
func build(thing: int) -> bool:
	if thing < 0 or thing >= _built.size() or _built[thing] or not all_found(thing):
		return false
	_built[thing] = true
	return true


# What `code` asks for is done (a part taken or the thing built). Returns whether anything changed.
func apply(code: int) -> bool:
	return build(thing_of(code)) if part_of(code) == BENCH else take(thing_of(code), part_of(code))


# Game over: nothing found, nothing built.
func reset() -> void:
	for thing in _found.size():
		(_found[thing] as Array).fill(false)
		_built[thing] = false


# The whole state as one number (thing after thing: a bit per part, then one for "built"), to send and to set.
func to_bits() -> int:
	var bits := 0
	var at := 0
	for thing in _found.size():
		for part in part_count(thing):
			if bool(_found[thing][part]):
				bits |= 1 << at
			at += 1
		if _built[thing]:
			bits |= 1 << at
		at += 1
	return bits


func set_bits(bits: int) -> void:
	var at := 0
	for thing in _found.size():
		for part in part_count(thing):
			_found[thing][part] = (bits >> at) & 1 == 1
			at += 1
		_built[thing] = (bits >> at) & 1 == 1
		at += 1
