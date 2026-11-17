# Purpose: the people of the home port (sea step 7b-3; locked: residents run the port's services). Each building that
# stands (level 1+) has its resident at the door (data/sea/town.json "residents": name, trade, clothes, lines); talking
# to one opens that building's page of the town window with one of their lines. Townsfolk walk the town's streets
# (data "townsfolk"), more of them as the town grows; far from the player they stand still and hidden.
# Dependencies: game/npc_body.gd, game/body_motion.gd, data/sea/town.json, data/sea/isles/isle_start.json (the streets);
# game/sea_town.gd (parent: plots, markers, rules, the sea world).
extends Node3D

const NpcBody = preload("res://game/npc_body.gd")
const BodyMotion = preload("res://game/body_motion.gd")
const TALK := 2.6
const STREETS := "res://data/sea/isles/isle_start.json"

var town: Node3D  # game/sea_town.gd
var _residents := {}  # plot id -> {"node": Node3D, "shown_for": String (the model it stands at)}
var _folk: Array = []  # [{"node", "path", "i", "dir", "pos" (sea xz), "y", "ray_t"}]
var _streets: Array = []  # the town's street lines (sea coordinates)
var _rng := RandomNumberGenerator.new()
var _clock := 0.0


func _ready() -> void:
	_rng.seed = 7
	var isle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STREETS))
	var cx := -520.0
	var cz := 6570.0  # the start island's centre in the sea (data/sea/islands.json)
	for line: Array in isle.get("paths", []):
		var pts: Array = []
		for q: Array in line:
			var x := float(q[0])
			var z := float(q[1])
			if ((x - 430.0) / 175.0) ** 2 + ((z - 60.0) / 230.0) ** 2 < 0.8:  # inside the town site only
				pts.append(Vector2(x + cx, z + cz))
		if pts.size() > 6:
			_streets.append(pts)


func _look(entry: Dictionary) -> Dictionary:
	return {"gender": String(entry.get("gender", "female")), "height": 1.0, "weight": 1.0, "bust": 0.3, "glutes": 0.3, "skin": _rng.randi_range(0, 5),
		"hair": String(entry.get("hair", "bob")), "hair_color": ["#2b1d14", "#553322", "#8a5a2b", "#c9a26b", "#1a1a1a"][_rng.randi_range(0, 4)], "face": "gentle_smile", "outfit": String(entry.get("outfit", "farmer"))}


func _plate(body: Node3D, words: String) -> void:
	var plate := Label3D.new()
	plate.text = words
	plate.font_size = 30
	plate.pixel_size = 0.005
	plate.outline_size = 8
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.position.y = 2.05
	body.add_child(plate)


# Called by the town when anything changed (a level, the growth).
func refresh() -> void:
	var rules: RefCounted = town.get("rules")
	var who: Dictionary = rules.get("cfg").get("residents", {})
	for id: String in who:
		var model := String(rules.call("model", id))
		var up := int(rules.call("level", id)) > 0
		var have: Dictionary = _residents.get(id, {})
		if not up:
			if not have.is_empty():
				(have["node"] as Node).queue_free()
				_residents.erase(id)
			continue
		if not have.is_empty() and String(have["shown_for"]) == model:
			continue
		var door: Node3D = town.call("marker", id, "Door")
		if door == null:
			continue
		var node: Node3D = have["node"] if not have.is_empty() else null
		if node == null:
			node = NpcBody.build(_look(who[id]))
			add_child(node)
			BodyMotion.animate(node, 0.0, 0.0, 0.0, false)
			_plate(node, "%s\n%s" % [String(who[id]["name"]), String(who[id]["trade"])])
		var holder: Node3D = town.get("_plots")[id]["holder"]
		var out := door.global_position - holder.global_position
		out.y = 0.0
		var side := out.normalized().cross(Vector3.UP) if out.length() > 0.1 else Vector3.RIGHT
		node.global_position = door.global_position + side * 1.6 + (out.normalized() * 0.6 if out.length() > 0.1 else Vector3.ZERO)
		if bool(rules.call("plot", id).get("sea_level", false)):
			node.global_position = holder.global_position + holder.global_basis * Vector3(2.5, 1.9, 1.5)
		node.look_at(node.global_position + (out.normalized() if out.length() > 0.1 else Vector3.FORWARD) + Vector3(0.001, 0, 0), Vector3.UP)  # bodies face -z: out into the street
		_residents[id] = {"node": node, "shown_for": model}
	var want := int(rules.get("cfg").get("townsfolk", {}).get("start", 2)) + floori(float(rules.call("growth")) * float(rules.get("cfg").get("townsfolk", {}).get("per_growth", 10)))
	while _folk.size() < want and not _streets.is_empty():
		_add_walker()


func _add_walker() -> void:
	var cfg: Dictionary = town.get("rules").get("cfg")["townsfolk"]
	var looks: Array = cfg["looks"]
	var pick: Array = looks[_folk.size() % looks.size()]
	var node := NpcBody.build(_look({"outfit": pick[0], "gender": pick[1], "hair": pick[2]}))
	add_child(node)
	var path: Array = _streets[_rng.randi_range(0, _streets.size() - 1)]
	var i := _rng.randi_range(0, path.size() - 2)
	_folk.append({"node": node, "path": path, "i": i, "dir": 1 if _rng.randf() < 0.5 else -1, "pos": path[i], "y": 0.0, "ray_t": 0.0, "pause": 0.0})


func _process(delta: float) -> void:
	_clock += delta
	var sea: Node3D = town.get("_sea")
	var me: Vector3 = sea.call("local_of", (town.get("_player") as Node3D).global_position)
	var cfg: Dictionary = town.get("rules").get("cfg").get("townsfolk", {})
	var speed := float(cfg.get("walk_speed", 1.25))
	var seen_within := float(cfg.get("show_within", 160.0))
	for k in _folk.size():
		var f: Dictionary = _folk[k]
		var node: Node3D = f["node"]
		var near := Vector2(me.x, me.z).distance_to(f["pos"]) < seen_within
		node.visible = near
		if not near:
			continue
		var path: Array = f["path"]
		var moving := 0.0
		if float(f["pause"]) > 0.0:
			f["pause"] = float(f["pause"]) - delta
		else:
			var j := clampi(int(f["i"]) + int(f["dir"]), 0, path.size() - 1)
			var goal: Vector2 = path[j]
			var at: Vector2 = f["pos"]
			var step := speed * delta
			if at.distance_to(goal) <= step:
				f["pos"] = goal
				f["i"] = j
				if j == 0 or j == path.size() - 1:  # the end of the street: stop a while, then walk back
					f["dir"] = -int(f["dir"])
					f["pause"] = _rng.randf_range(2.0, 6.0)
			else:
				f["pos"] = at + (goal - at).normalized() * step
				moving = 1.0
				node.rotation.y = atan2(goal.x - at.x, goal.y - at.y) + PI  # bodies face -z
		f["ray_t"] = float(f["ray_t"]) - delta
		if float(f["ray_t"]) <= 0.0:  # the ground under them, now and then
			f["ray_t"] = 0.3
			var top: Vector3 = sea.call("world_of", Vector3(f["pos"].x, 120.0, f["pos"].y))
			var ray := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -200.0, 0))
			ray.collision_mask = 1
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty():
				f["y"] = (sea.call("local_of", hit["position"]) as Vector3).y
		node.global_position = sea.call("world_of", Vector3(f["pos"].x, float(f["y"]), f["pos"].y))
		BodyMotion.animate(node, moving, _clock * 6.0, _clock + float(k), false)


# The resident the player stands by ("" = none).
func resident_near(at: Vector3) -> String:
	for id: String in _residents:
		var node: Node3D = _residents[id]["node"]
		if is_instance_valid(node) and node.global_position.distance_to(at) <= TALK:
			return id
	return ""


func line_of(id: String) -> String:
	var who: Dictionary = town.get("rules").get("cfg").get("residents", {}).get(id, {})
	var lines: Array = who.get("say", [""])
	return "%s: %s" % [String(who.get("name", "")), String(lines[_rng.randi_range(0, lines.size() - 1)])]


func counts() -> Vector2i:
	return Vector2i(_residents.size(), _folk.size())
