# Purpose: Hunting's things on the ground: snares set from the bag (each catches the region's best small game the
# player may hunt after a while, shows sprung, and is checked with the interact key) and the trail of prints that
# following tracks lays from the tracks to where the animal is met. Snares are the player's own (not shared online).
# Dependencies: game/fantasy_world.gd (terrain, spawner stats, perks, give, gain_xp, world_of), game/fantasy_models.gd
# (snare, snare_sprung, tracks_hoof / tracks_paw models), data/fantasy/skilling.json gather.snare, data/fantasy/world.json small_game.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")

const TRAIL_STEP := 2.6  # metres between two patches of prints
const TRAIL_SECONDS := 45.0

var world: Node3D  # game/fantasy_world.gd

var _snares: Array = []  # {"at": Vector3 local, "ready_at": engine time, "catch": animal id or "", "node": Node3D}
var _trails: Array = []  # [Node3D, engine time it fades]
var _cfg: Dictionary


func setup(fantasy_world: Node3D) -> void:
	world = fantasy_world
	_cfg = world.skilling["gather"]["snare"]


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# Sets a snare at `local` (the player's feet). Returns what to tell the player ("" = set).
func place(local: Vector3, item: String = "snare") -> String:
	if _snares.size() >= int(_cfg["max"]):
		return "You already have %d snares out." % int(_cfg["max"])
	var game: Array = world.terrain.region_at(local.x, local.z).get("small_game", [])
	if game.is_empty():
		return "Nothing small lives here to snare."
	if not world.bag.remove(item, 1):
		return "You have no snare."
	var quick: float = world.perk("hunting", "snare_speed") + float(world.bag.def(item).get("speed", 0.0))  # perks and a sturdier snare
	var seconds := float(_cfg["seconds"]) * maxf(1.0 - quick, 0.2)
	var snare := {"at": local, "ready_at": _now() + seconds * randf_range(0.8, 1.2), "catch": _pick(game), "node": null, "item": item}
	snare["node"] = _model("snare", local)
	_snares.append(snare)
	world.sound("craft_workbench", world.world_of(local))
	return ""


# The best small game of the region the player's Hunting level allows.
func _pick(game: Array) -> String:
	var best := ""
	for id: String in game:
		var level := int(world.spawner.stats_of(id).get("level", 1))
		if level <= int(world.skills.level("hunting")) and (best == "" or level > int(world.spawner.stats_of(best).get("level", 1))):
			best = id
	return best


# The nearest snare within reach ({} = none).
func near(local: Vector3) -> Dictionary:
	var best := {}
	var best_d := float(_cfg["reach"])
	for snare: Dictionary in _snares:
		var d := Vector2(local.x - snare["at"].x, local.z - snare["at"].z).length()
		if d < best_d:
			best_d = d
			best = snare
	return best


func caught(snare: Dictionary) -> bool:
	return _now() >= float(snare["ready_at"]) and String(snare["catch"]) != ""


func prompt(snare: Dictionary, key: String) -> String:
	if caught(snare):
		return "[%s] Take the %s from the snare" % [key, String(world.spawner.stats_of(String(snare["catch"])).get("name", "catch")).to_lower()]
	return "[%s] Take up the snare (nothing yet)" % key


# Checks a snare: the catch's meat and pelt and Hunting experience, and most of the time the snare back.
func collect(snare: Dictionary) -> void:
	if caught(snare):
		var stats: Dictionary = world.spawner.stats_of(String(snare["catch"]))
		var extra := 1 if randf() < world.perk("hunting", "double") else 0
		for item: String in stats.get("drops", {}):
			if randf() < float(stats["drops"][item]):
				world.give(item, 1 + extra)
		world.gain_xp("hunting", roundi(float(stats.get("xp", 0)) * float(_cfg["catch_xp_mult"])))
		world.report({"type": "kill", "enemy": String(snare["catch"])})
		if randf() < float(_cfg["keep_snare"]):
			world.give(String(snare["item"]), 1)
	else:
		world.give(String(snare["item"]), 1)
	(snare["node"] as Node3D).queue_free()
	_snares.erase(snare)


# Prints from the tracks to where the animal is met, fading after a while.
func show_trail(from: Vector3, to: Vector3, paw: bool) -> void:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var steps := int(flat.length() / TRAIL_STEP)
	for k in range(1, steps):
		var at := from.lerp(to, float(k) / float(steps))
		var patch := _model("tracks_paw" if paw else "tracks_hoof", Vector3(at.x, world.terrain.height(at.x, at.z), at.z))
		if patch != null:
			patch.rotation.y = atan2(-flat.x, -flat.y)
			patch.scale = Vector3.ONE * 1.3
			_trails.append([patch, _now() + TRAIL_SECONDS])


func _model(id: String, local: Vector3) -> Node3D:
	var made := FantasyModels.scene(id)
	if made == null:
		made = Node3D.new()
	add_child(made)
	made.global_position = world.world_of(Vector3(local.x, world.terrain.height(local.x, local.z), local.z))
	return made


func _process(_delta: float) -> void:
	var now := _now()
	for snare: Dictionary in _snares:
		if caught(snare) and not bool(snare.get("sprung", false)):
			snare["sprung"] = true
			(snare["node"] as Node3D).queue_free()
			snare["node"] = _model("snare_sprung", snare["at"])
	for i in range(_trails.size() - 1, -1, -1):
		if now >= float(_trails[i][1]):
			(_trails[i][0] as Node3D).queue_free()
			_trails.remove_at(i)


# Leaving the world takes the snares back into the bag (they are not saved).
func clear() -> void:
	for snare: Dictionary in _snares:
		(snare["node"] as Node3D).queue_free()
		world.bag.add(String(snare["item"]), 1)
	_snares.clear()
	for trail: Array in _trails:
		(trail[0] as Node3D).queue_free()
	_trails.clear()
