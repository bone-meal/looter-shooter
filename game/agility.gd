# Purpose: Agility in the fantasy world (sea step 3d): crossing the obstacles of the courses (stations of kind
# "agility" in places of kind course: the body is carried over each one along its own path, may slip, pays Agility
# experience and a bonus for a lap in order) and the cliff shortcuts (core/shortcut_spots.gd): knotted ropes that
# need an Agility level, and ladders that Carpentry must mend first (mended ones are saved). While the body is
# carried the player's own controls rest.
# Dependencies: game/fantasy_world.gd (terrain, layout, skills, perks, work, player, world_of, gain_xp, notice),
# game/fantasy_models.gd, core/shortcut_spots.gd, data/fantasy/agility.json.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")
const ShortcutSpots = preload("res://core/shortcut_spots.gd")

const REACH := 3.0

var world: Node3D  # game/fantasy_world.gd

var _cfg: Dictionary
var _spots := {}  # cell key -> spot dictionary with "node" (the model standing there)
var _repaired := {}  # spot key -> true: ladders this player has mended
var _laps := {}  # course place id -> the obstacle expected next
var _move := {}  # the crossing under way ({} = none): from, to, lift, profile, seconds, t, yaw, done (Callable)


func setup(fantasy_world: Node3D) -> void:
	world = fantasy_world
	_cfg = world.data["agility"]


func busy() -> bool:
	return not _move.is_empty()


# --- cliff shortcuts ---

# Keeps the shortcut models of the cells round the player (call every half second).
func follow(local: Vector3) -> void:
	var size := float(_cfg["shortcuts"]["cell"])
	var here := Vector2i(floori(local.x / size), floori(local.z / size))
	var wanted := {}
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			wanted["%d:%d" % [here.x + dx, here.y + dz]] = Vector2i(here.x + dx, here.y + dz)
	for key: String in _spots.keys():
		if not wanted.has(key):
			if is_instance_valid(_spots[key].get("node")):
				(_spots[key]["node"] as Node3D).queue_free()
			_spots.erase(key)
	for key: String in wanted:
		if not _spots.has(key):
			var spot := ShortcutSpots.spot(world.terrain, world.layout, wanted[key], _cfg["shortcuts"])
			_spots[key] = spot
			if not spot.is_empty():
				_dress(spot)


func _dress(spot: Dictionary) -> void:
	if is_instance_valid(spot.get("node")):
		(spot["node"] as Node3D).queue_free()
	var kind: Dictionary = _cfg["shortcuts"]["kinds"][String(spot["kind"])]
	var broken := kind.has("repair") and not _repaired.has(String(spot["key"]))
	var made := FantasyModels.scene(String(kind["broken"] if broken else kind["model"]))
	if made == null:
		return
	add_child(made)
	var base: Vector3 = spot["base"]
	var top: Vector3 = spot["top"]
	var dir: Vector2 = spot["dir"]
	var flat := maxf(Vector2(top.x - base.x, top.z - base.z).length() - 1.5, 0.9)
	made.global_position = world.world_of(base)
	made.rotation.y = atan2(dir.x, dir.y)  # the model leans along its +z: towards the cliff
	made.scale = Vector3(1.0, maxf((top.y - base.y) / 6.0, 0.6), clampf(flat / 0.9, 1.0, 5.0))
	spot["node"] = made


# The nearest shortcut end within reach: {"spot", "up": true at its foot} ({} = none).
func shortcut_near(local: Vector3) -> Dictionary:
	for key: String in _spots:
		var spot: Dictionary = _spots[key]
		if spot.is_empty():
			continue
		for up: bool in [true, false]:
			var end: Vector3 = spot["base"] if up else spot["top"]
			if Vector2(local.x - end.x, local.z - end.z).length() < REACH and absf(local.y - end.y) < 3.0:
				return {"spot": spot, "up": up}
	return {}


func shortcut_prompt(found: Dictionary, key: String) -> String:
	var spot: Dictionary = found["spot"]
	var kind: Dictionary = _cfg["shortcuts"]["kinds"][String(spot["kind"])]
	var skill := String(kind["skill"])
	if kind.has("repair") and not _repaired.has(String(spot["key"])):
		var recipe := _recipe(String(kind["repair"]))
		var why: String = world.work.cannot_make(recipe)
		return "Broken ladder: %s" % why.trim_suffix(".") if why != "" else "[%s] Mend the ladder (%s)" % [key, _needs(recipe)]
	if skill == "agility" and int(world.skills.level("agility")) < int(kind["level"]):
		return "Knotted rope: needs Agility %d" % int(kind["level"])
	return "[%s] Climb %s" % [key, "up" if bool(found["up"]) else "down"]


func use_shortcut(found: Dictionary) -> void:
	var spot: Dictionary = found["spot"]
	var kind: Dictionary = _cfg["shortcuts"]["kinds"][String(spot["kind"])]
	if kind.has("repair") and not _repaired.has(String(spot["key"])):
		if world.work.make(_recipe(String(kind["repair"]))) == "":
			_repaired[String(spot["key"])] = true
			_dress(spot)
			world.notice.emit("The ladder holds again: a way up for good.")
		return
	if String(kind["skill"]) == "agility" and int(world.skills.level("agility")) < int(kind["level"]):
		return
	var from: Vector3 = spot["base"] if bool(found["up"]) else spot["top"]
	var to: Vector3 = spot["top"] if bool(found["up"]) else spot["base"]
	var xp := int(_cfg["shortcuts"]["xp"].get(String(spot["kind"]), 0))
	_start(from, to, 0.0, "climb", float(_cfg["shortcuts"]["climb_seconds"]), func(_ok: bool) -> void: world.gain_xp("agility", xp), true)


func _recipe(id: String) -> Dictionary:
	for recipe: Dictionary in world.skilling["recipes"]:
		if String(recipe["id"]) == id:
			return recipe
	return {}


func _needs(recipe: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: String in recipe["in"]:
		parts.append("%d %s" % [int(recipe["in"][item]), world.bag.item_name(item)])
	return ", ".join(parts)


func repaired_keys() -> Array:
	return _repaired.keys()


func set_repaired(keys: Variant) -> void:
	_repaired = {}
	if keys is Array:
		for key: Variant in keys:
			_repaired[String(key)] = true
	for cell: String in _spots:
		if not (_spots[cell] as Dictionary).is_empty():
			_dress(_spots[cell])


# --- course obstacles ---

func _obstacle(station: Dictionary) -> Dictionary:
	for id: String in _cfg["obstacles"]:
		if String(_cfg["obstacles"][id]["model"]) == String(station.get("model", "")):
			return _cfg["obstacles"][id]
	return {}


func obstacle_prompt(station: Dictionary, key: String) -> String:
	var course: Dictionary = _cfg["courses"].get(String(station["place"]), {})
	var def := _obstacle(station)
	if course.is_empty() or def.is_empty():
		return ""
	if int(world.skills.level("agility")) < int(course["level"]):
		return "This course needs Agility %d" % int(course["level"])
	return "[%s] Cross (obstacle %d of %d)" % [key, int(station.get("n", 0)) + 1, _course_size(String(station["place"]))]


func cross(station: Dictionary) -> void:
	var course: Dictionary = _cfg["courses"].get(String(station["place"]), {})
	var def := _obstacle(station)
	if course.is_empty() or def.is_empty() or busy() or int(world.skills.level("agility")) < int(course["level"]):
		return
	var start: Vector3 = station["at"]
	var yaw := float(station.get("yaw", 0.0))
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var end := start + ahead * float(def["length"])
	var odds := minf(float(_cfg["fail"]["base"]) + float(_cfg["fail"]["per_level"]) * float(int(world.skills.level("agility")) - int(course["level"])), 1.0)
	var slips := randf() < (1.0 - odds) * (1.0 - clampf(world.perk("agility", "sure_foot"), 0.0, 1.0))
	if slips:
		end = start.lerp(end, randf_range(0.35, 0.65))
	var place := String(station["place"])
	var n := int(station.get("n", 0))
	_start(start, end, float(def["lift"]), String(def["profile"]), float(def["seconds"]) * (0.55 if slips else 1.0), func(_ok: bool) -> void:
		if slips:
			world.notice.emit("You slip and fall!")
			world._player.call("take_damage", float(world._player.get("health").max_hp) * float(_cfg["fail"]["damage"]))
			_laps[place] = 0
			return
		world.gain_xp("agility", int(course["xp"]))
		if n == int(_laps.get(place, 0)):
			_laps[place] = n + 1
			if n + 1 >= _course_size(place):
				_laps[place] = 0
				world.notice.emit("Lap complete!")
				world.gain_xp("agility", int(course["lap"]))
		else:
			_laps[place] = 1 if n == 0 else 0, not slips)


func _course_size(place: String) -> int:
	var count := 0
	for station: Dictionary in world.places.stations:
		if String(station["place"]) == place and String(station["kind"]) == "agility":
			count += 1
	return count


# --- carrying the body ---

func _start(from: Vector3, to: Vector3, lift: float, profile: String, seconds: float, done: Callable, ok: bool) -> void:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	_move = {"from": from, "to": to, "lift": lift, "profile": profile, "seconds": maxf(seconds, 0.3), "t": 0.0,
		"yaw": atan2(-flat.x, -flat.y) if flat.length() > 0.05 else 0.0, "done": done, "ok": ok}
	world._player.set("controls_enabled", false)


func _physics_process(delta: float) -> void:
	if _move.is_empty():
		return
	_move["t"] = minf(float(_move["t"]) + delta / float(_move["seconds"]), 1.0)
	var t := float(_move["t"])
	var from: Vector3 = _move["from"]
	var to: Vector3 = _move["to"]
	var lift := float(_move["lift"])
	var at := from.lerp(to, t)
	match String(_move["profile"]):
		"climb":  # up (or down) the cliff face, then a step onto the ground
			var rise := clampf(t / 0.8, 0.0, 1.0)
			at = Vector3(lerpf(from.x, to.x, smoothstep(0.0, 1.0, t)), lerpf(from.y, to.y, rise), lerpf(from.z, to.z, smoothstep(0.0, 1.0, t)))
		"hops":
			at.y = world.terrain.height(at.x, at.z) + lift * absf(sin(t * PI * 3.0))
		"over", "swing":
			at.y = world.terrain.height(at.x, at.z) + lift * sin(t * PI)
		_:  # flat: up onto it, along, and down at the end
			at.y = world.terrain.height(at.x, at.z) + lift * minf(minf(t * 6.0, (1.0 - t) * 6.0), 1.0)
	world._player.call("teleport", world.world_of(at) + Vector3(0.0, 0.05, 0.0), float(_move["yaw"]))
	if t >= 1.0:
		var done: Callable = _move["done"]
		var ok := bool(_move["ok"])
		_move = {}
		world._player.set("controls_enabled", true)
		done.call(ok)
