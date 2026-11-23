# Purpose: the things to work on in the fantasy world (trees to chop, ore rocks, fishing spots, crops, herbs): where
# they are, which are used up, and when they grow back. game/fantasy_scatter.gd places them with each chunk and draws
# them (many copies in one draw call); a used-up one is hidden by shrinking its copy to nothing. Used-up state is
# remembered while the chunk is away, so walking off and back does not refill a tree.
# (polish1 item 114) Spots: dormant spots, hibernation after heavy use and a sleeper waking nearby, shared online.
# Dependencies: none (game/fantasy_work.gd decides who may gather what; game/fantasy_world.gd gather_use routes a use).
extends Node3D

var _hidden := Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0.0, -50.0, 0.0))

var _nodes := {}  # chunk key -> Array of {"id", "at", "model", "index", "slot", "shown": Transform3D}
var _drawn := {}  # chunk key -> {model id: MultiMesh}
var _spent := {}  # "cx:cz:slot" -> engine time it grows back
var _timer := 0.0
# (polish1 item 114) RuneScape-style spots: the same known spots for everyone (the layout), more spots than awake
# nodes (a share of the spots starts DORMANT: not drawn, not gatherable), a spot gathered `hibernate_after` times
# HIBERNATES for `hibernate_s` and a dormant spot of the same kind nearby WAKES instead. Online the host keeps this
# and tells everyone (game/net_fantasy.gd), so a node used by one player is used up for all.
var cfg := {"hibernate_after": 6, "hibernate_s": 1800.0, "dormant_share": 0.35}  # data/fantasy/skilling.json "spots"
var _uses := {}  # tag -> times gathered since it last woke
var _hib := {}  # tag -> engine time its hibernation ends
var _woken := {}  # tag -> true: a dormant spot that has woken


func add_node(key: Vector2i, slot: int, id: String, at: Vector3, model: String, index: int) -> void:
	if not _nodes.has(key):
		_nodes[key] = []
	(_nodes[key] as Array).append({"id": id, "at": at, "model": model, "index": index, "slot": slot, "key": key})


# Called once a chunk's copies exist: hides the ones that are still used up.
func bind_drawn(key: Vector2i, model: String, many: MultiMesh) -> void:
	if not _drawn.has(key):
		_drawn[key] = {}
	_drawn[key][model] = many
	for node: Dictionary in _nodes.get(key, []):
		if String(node["model"]) == model:
			node["shown"] = many.get_instance_transform(int(node["index"]))
			if is_spent(node):
				many.set_instance_transform(int(node["index"]), _hidden)


func drop_chunk(key: Vector2i) -> void:
	_nodes.erase(key)
	_drawn.erase(key)


func _tag(node: Dictionary) -> String:
	var key: Vector2i = node["key"]
	return "%d:%d:%d" % [key.x, key.y, int(node["slot"])]


func is_spent(node: Dictionary) -> bool:
	var tag := _tag(node)
	return _spent.has(tag) or _hib.has(tag) or (dormant(node) and not _woken.has(tag))


# A spot that starts asleep (the random spread's slots only; patches and fishing spots are always awake).
func dormant(node: Dictionary) -> bool:
	var key: Vector2i = node["key"]
	var slot := int(node["slot"])
	return slot < 8 and _hash(key.x * 31 + slot, key.y * 17 + slot * 7) < float(cfg["dormant_share"])


static func _hash(a: int, b: int) -> float:
	var h := (a * 374761393 + b * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10000) / 10000.0


# (polish1 item 114) A player gathered `node`: it is used up for `seconds`; often enough and it hibernates and another
# spot of its kind nearby wakes. Returns the change to tell everyone: {"tag", "spent", "hib", "wake"} (seconds, "" none).
func use(node: Dictionary, seconds: float) -> Dictionary:
	var tag := _tag(node)
	spend(node, seconds)
	_uses[tag] = int(_uses.get(tag, 0)) + 1
	var change := {"tag": tag, "spent": seconds, "hib": 0.0, "wake": ""}
	if int(_uses[tag]) >= int(cfg["hibernate_after"]):
		_uses.erase(tag)
		_woken.erase(tag)
		_hib[tag] = Time.get_ticks_msec() / 1000.0 + float(cfg["hibernate_s"])
		change["hib"] = float(cfg["hibernate_s"])
		var other := _sleeper_near(node)
		if not other.is_empty():
			_woken[_tag(other)] = true
			_show(other, true)
			change["wake"] = _tag(other)
	return change


# The host's (or another machine's) word about a spot.
func apply(change: Dictionary) -> void:
	var tag := String(change.get("tag", ""))
	var now := Time.get_ticks_msec() / 1000.0
	if float(change.get("spent", 0.0)) > 0.0:
		_spent[tag] = now + float(change["spent"])
	if float(change.get("hib", 0.0)) > 0.0:
		_hib[tag] = now + float(change["hib"])
		_woken.erase(tag)
		_uses.erase(tag)
	if String(change.get("wake", "")) != "":
		_woken[String(change["wake"])] = true
	for t: String in [tag, String(change.get("wake", ""))]:
		var node := _by_tag(t)
		if not node.is_empty():
			_show(node, not is_spent(node))


# Everything the host knows, for a player who has just come in.
func state() -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	var out: Array = []
	for tag: String in _spent:
		out.append({"tag": tag, "spent": float(_spent[tag]) - now})
	for tag: String in _hib:
		out.append({"tag": tag, "hib": float(_hib[tag]) - now})
	for tag: String in _woken:
		out.append({"tag": "", "wake": tag})
	return out


func _by_tag(tag: String) -> Dictionary:
	if tag == "":
		return {}
	var parts := tag.split(":")
	if parts.size() != 3:
		return {}
	for node: Dictionary in _nodes.get(Vector2i(int(parts[0]), int(parts[1])), []):
		if int(node["slot"]) == int(parts[2]):
			return node
	return {}


# A dormant spot of the same kind in this chunk or the ones round it (nearest first), {} = none.
func _sleeper_near(node: Dictionary) -> Dictionary:
	var key: Vector2i = node["key"]
	var best := {}
	var best_d := INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for other: Dictionary in _nodes.get(key + Vector2i(dx, dz), []):
				if String(other["id"]) != String(node["id"]) or not dormant(other) or _woken.has(_tag(other)) or _hib.has(_tag(other)):
					continue
				var d: float = (other["at"] as Vector3).distance_to(node["at"])
				if d < best_d:
					best_d = d
					best = other
	return best


# (dev) how many spots of a kind are loaded / awake / dormant / hibernating.
func note(id: String) -> String:
	var n := 0
	var awake := 0
	var asleep := 0
	var hib := 0
	for key: Vector2i in _nodes:
		for node: Dictionary in _nodes[key]:
			if String(node["id"]) != id:
				continue
			n += 1
			if _hib.has(_tag(node)):
				hib += 1
			elif dormant(node) and not _woken.has(_tag(node)):
				asleep += 1
			else:
				awake += 1
	return "%s: %d spots, %d awake, %d dormant, %d hibernating" % [id, n, awake, asleep, hib]


# The closest node within reach that is not used up ({} = none). Positions are in the fantasy world's own space.
func nearest(local: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	var cx := floori(local.x / 50.0)
	var cz := floori(local.z / 50.0)
	for key: Vector2i in _nodes:
		if absi(key.x - cx) > 1 or absi(key.y - cz) > 1:
			continue
		for node: Dictionary in _nodes[key]:
			var d := Vector2(local.x - node["at"].x, local.z - node["at"].z).length()
			if d < best_d and not is_spent(node):
				best_d = d
				best = node
	return best


# (polish1 item 106) The nodes within reach that are not used up, nearest first (at most `most`).
func near_list(local: Vector3, reach: float, most: int) -> Array:
	var out: Array = []
	var cx := floori(local.x / 50.0)
	var cz := floori(local.z / 50.0)
	for key: Vector2i in _nodes:
		if absi(key.x - cx) > 1 or absi(key.y - cz) > 1:
			continue
		for node: Dictionary in _nodes[key]:
			var d := Vector2(local.x - node["at"].x, local.z - node["at"].z).length()
			if d < reach and not is_spent(node):
				out.append([d, node])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var list: Array = []
	for e: Array in out.slice(0, most):
		list.append(e[1])
	return list


# Uses a node up for `seconds`.
func spend(node: Dictionary, seconds: float) -> void:
	_spent[_tag(node)] = Time.get_ticks_msec() / 1000.0 + seconds
	_show(node, false)


func _show(node: Dictionary, on: bool) -> void:
	var many: MultiMesh = _drawn.get(node["key"], {}).get(node["model"])
	if many != null and node.has("shown"):
		many.set_instance_transform(int(node["index"]), node["shown"] if on else _hidden)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 1.0:
		return
	_timer = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	for tag: String in _hib.keys():  # (polish1 item 114) hibernation over: the spot is back (if it was not a sleeper)
		if now >= float(_hib[tag]):
			_hib.erase(tag)
			var back := _by_tag(tag)
			if not back.is_empty():
				_show(back, not is_spent(back))
	for tag: String in _spent.keys():
		if now >= float(_spent[tag]):
			_spent.erase(tag)
			var parts := tag.split(":")
			var key := Vector2i(int(parts[0]), int(parts[1]))
			for node: Dictionary in _nodes.get(key, []):
				if int(node["slot"]) == int(parts[2]):
					_show(node, not is_spent(node))
