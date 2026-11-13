# Purpose: pure rules of the islands' perks: which ones a player carries, the limit, buying, losing them all on going
# down, the random one a boss's power-up hands out, and the numbers the rest of the game asks for. No nodes.
# Dependencies: none. Data: data/perks.json, passed to the constructor.
extends RefCounted

var cfg: Dictionary
var owned: Array[String] = []
var stamp := 0  # goes up with every change (things built from the perks' numbers know when to rebuild)

var _perks: Dictionary


func _init(config: Dictionary) -> void:
	cfg = config
	_perks = config["perks"]


func limit() -> int:
	return int(cfg["limit"])


func ids() -> Array:
	return _perks.keys()


func has(id: String) -> bool:
	return owned.has(id)


func known(id: String) -> bool:
	return _perks.has(id)


func name_of(id: String) -> String:
	return String(_perks[id]["name"]) if _perks.has(id) else id


func price(id: String) -> int:
	return int(_perks[id]["price"])


func desc(id: String) -> String:
	return String(_perks[id]["desc"])


func color_of(id: String) -> Color:
	return Color(String(_perks[id]["color"]))


# "" when the perk can be bought now, else why not: "owned" or "limit".
func refusal(id: String) -> String:
	if owned.has(id):
		return "owned"
	return "limit" if owned.size() >= limit() else ""


# Takes a perk (the caller has paid). `over` = the limit does not count (the boss's power-up). False when it is
# already carried, unknown, or there is no room.
func add(id: String, over: bool = false) -> bool:
	if not _perks.has(id) or owned.has(id) or (not over and owned.size() >= limit()):
		return false
	owned.append(id)
	stamp += 1
	return true


# The boss's power-up: one perk not carried yet, whatever the limit says. "" when every perk is carried.
func give_random(rng: RandomNumberGenerator) -> String:
	var open: Array[String] = []
	for id: String in _perks:
		if not owned.has(id):
			open.append(id)
	if open.is_empty():
		return ""
	var id := open[rng.randi() % open.size()]
	add(id, true)
	return id


# Going down, game over: every perk is gone.
func clear() -> void:
	if not owned.is_empty():
		owned.clear()
		stamp += 1


# A number of the carried perks (each key belongs to one perk), `fallback` when no carried perk has it.
func num(key: String, fallback: float) -> float:
	for id in owned:
		if (_perks[id] as Dictionary).has(key):
			return float(_perks[id][key])
	return fallback
