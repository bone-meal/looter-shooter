# Purpose: the things to work on in the fantasy world (trees to chop, ore rocks, fishing spots, crops, herbs): where
# they are, which are used up, and when they grow back. game/fantasy_scatter.gd places them with each chunk and draws
# them (many copies in one draw call); a used-up one is hidden by shrinking its copy to nothing. Used-up state is
# remembered while the chunk is away, so walking off and back does not refill a tree.
# Dependencies: none (game/fantasy_work.gd decides who may gather what).
extends Node3D

var _hidden := Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0.0, -50.0, 0.0))

var _nodes := {}  # chunk key -> Array of {"id", "at", "model", "index", "slot", "shown": Transform3D}
var _drawn := {}  # chunk key -> {model id: MultiMesh}
var _spent := {}  # "cx:cz:slot" -> engine time it grows back
var _timer := 0.0


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
	return _spent.has(_tag(node))


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
	for tag: String in _spent.keys():
		if now >= float(_spent[tag]):
			_spent.erase(tag)
			var parts := tag.split(":")
			var key := Vector2i(int(parts[0]), int(parts[1]))
			for node: Dictionary in _nodes.get(key, []):
				if int(node["slot"]) == int(parts[2]):
					_show(node, true)
