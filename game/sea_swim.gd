# Purpose: swimming at sea (sea step 5b): decides when the player is in the water (not aboard, deeper than wading),
# keeps the surface height under him for the swim movement (game/player.gd _swim_step), drains and refills stamina
# (more moving, under water, sprinting and in heavy swell; Agility levels give more), drowns him when it is empty
# (director: health drains until a ladder, a rope or the shore), climbs the rope ladders on both sides of a ship,
# and the thrown rope (director: F at the rail; whoever reaches the float is hauled aboard). The view under water
# (game/swim_hud.gd wash + the sea look's close fog). Runs after the ships, before the player's own movement.
# Dependencies: game/sea_ships.gd, game/sea_rope.gd, game/swim_hud.gd, data/sea/salvage.json "swim"; the sea world
# (waves, swell, look, skills), the player (swimming, water_level, swim, swim_fast_ok, drown, pin, carried).
extends Node3D

const SeaRope = preload("res://game/sea_rope.gd")
const SwimHud = preload("res://game/swim_hud.gd")
const HEAD := 1.6

var cfg: Dictionary  # data/sea/salvage.json "swim"
var stamina := 100.0
var under := false  # head under water
var depth := 0.0  # how deep the head is (m)
var hud := SwimHud.new()
var ropes: Array = []  # SeaRope

var _sea: Node3D
var _player: CharacterBody3D
var _ships: Node3D  # game/sea_ships.gd
var _climb := {}  # {"ship", "path": [ship-space points], "t", "seconds"}
var _layer := CanvasLayer.new()
var _far_above := 0.0  # the camera's view distance before the head went under


func setup(sea_world: Node3D, player: CharacterBody3D, ships: Node3D, swim_cfg: Dictionary) -> void:
	_sea = sea_world
	_player = player
	_ships = ships
	cfg = swim_cfg
	process_priority = -9  # after the ships moved, before the player swims
	_player.set("swim", {"speed": cfg["speed"], "sprint": cfg["sprint"], "float": cfg["float"], "max_depth": cfg["max_depth"]})
	_layer.layer = 4
	_layer.add_child(hud)
	add_child(_layer)
	stamina = max_stamina()


func max_stamina() -> float:
	var skills: Variant = _sea.get("skills")
	var level := int((skills as Node).get("skills").call("level", "agility")) if skills != null else 1
	return float(cfg["stamina"]) + float(cfg["stamina_per_agility"]) * float(level - 1)


# The water's surface (scene height) over a scene position: the waves where they are drawn moving, flat otherwise.
func surface_at(at: Vector3) -> float:
	var ocean: Node3D = _sea.get("ocean")
	if not bool(ocean.call("is_moving")):
		return 0.0
	var here: Vector3 = _sea.call("local_of", at)
	return float((ocean.get("waves") as RefCounted).call("height_at", here.x, here.z, float(_sea.call("seconds")), float(ocean.get("swell"))))


func _process(delta: float) -> void:
	if not bool(_sea.get("inside")) or delta <= 0.0:
		return
	for rope: SeaRope in ropes.duplicate():
		rope.follow(surface_at(rope.float_at()), delta)
		if rope.left <= 0.0 or not is_instance_valid(rope.ship):
			ropes.erase(rope)
			rope.queue_free()
		elif _climb.is_empty() and bool(_player.get("swimming")) and _flat_distance(rope.float_at(), _player.global_position) <= float(cfg["rope_grab"]):
			_haul(rope)
	if not _climb.is_empty():
		_climbing(delta)
		return
	var feet := _player.global_position.y
	var surface := surface_at(_player.global_position)
	_player.set("water_level", surface)
	var was := bool(_player.get("swimming"))
	var wet := false
	if _ships.call("ship_aboard") == null and not bool(_player.get("carried")):
		if was:  # out once standing in the shallows, or clear of the water altogether (a teleport, a wave dropping away)
			wet = feet < surface + 1.0 and not (_player.is_on_floor() and feet > surface - float(cfg["wade"]) + 0.25)
		else:
			wet = feet < surface - float(cfg["wade"])
	_player.set("swimming", wet)
	depth = maxf(surface - (feet + HEAD), 0.0)
	under = wet and depth > 0.05
	_breathe(delta, wet)
	_sea.get("look").set("under_water", under)
	_view_under(under)
	var here: Vector3 = _sea.call("local_of", _player.global_position)
	var region: Dictionary = (_sea.get("map") as RefCounted).call("region_at", here.x, here.z)
	var sea_colour: Array = region.get("sea", [0.05, 0.3, 0.4])
	hud.show_state(stamina / max_stamina(), wet, under, depth, Color(sea_colour[0], sea_colour[1], sea_colour[2]), delta)


# Under water nothing far is drawn (the fog alone does not hide it on every renderer): the camera's view distance
# shrinks to UNDER_VIEW while the head is under and comes back when it surfaces.
const UNDER_VIEW := 70.0


func _view_under(now_under: bool) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if now_under and _far_above <= 0.0:
		_far_above = camera.far
		camera.far = UNDER_VIEW
	elif not now_under and _far_above > 0.0:
		camera.far = _far_above
		_far_above = 0.0


func _breathe(delta: float, wet: bool) -> void:
	var most := max_stamina()
	if not wet:
		stamina = minf(stamina + float(cfg["regen"]) * delta, most)
		_player.set("swim_fast_ok", true)
		return
	var moving := Vector2(_player.velocity.x, _player.velocity.z).length() > 0.6 or absf(_player.velocity.y) > 0.6
	var drain := float(cfg["move"]) if moving else float(cfg["tread"])
	if under:
		drain = maxf(drain, float(cfg["under"]))
	if moving and Input.is_action_pressed("sprint") and bool(_player.get("controls_enabled")):
		drain *= float(cfg["sprint_drain"])
	drain += float(cfg["storm_drain"]) * maxf(float((_sea.get("ocean") as Node3D).get("swell")) - 1.0, 0.0)
	stamina = maxf(stamina - drain * delta, 0.0)
	_player.set("swim_fast_ok", stamina > 5.0)
	if stamina <= 0.0:
		var health: Variant = _player.get("health")
		_player.call("drown", float((health as RefCounted).get("max_hp")) * float(cfg["drown"]) * delta)


# --- the rope ladders ---

# The ladder foot (scene position at the waterline) a swimmer is near, as {"ship", "side"}; {} when none.
func ladder_near() -> Dictionary:
	if not bool(_player.get("swimming")) or not _climb.is_empty():
		return {}
	for ship: Node3D in _ships.get("ships"):
		var z := float(ship.get("spec")["ladder_z"])
		var hw := float(_ships.get("rules").call("half_width", String(ship.get("state")["ship"]), z))
		for side: float in [1.0, -1.0]:
			var foot: Vector3 = ship.global_transform * Vector3(side * (hw + 0.35), 0.0, z)
			if _flat_distance(foot, _player.global_position) <= float(cfg["ladder_reach"]) and _player.global_position.y > foot.y - 3.5:
				return {"ship": ship, "side": side}
	return {}


func climb_ladder(spot: Dictionary) -> void:
	var ship: Node3D = spot["ship"]
	var side := float(spot["side"])
	var spec: Dictionary = ship.get("spec")
	var z := float(spec["ladder_z"])
	var hw := float(_ships.get("rules").call("half_width", String(ship.get("state")["ship"]), z))
	var deck := float(spec["deck"])
	var start: Vector3 = ship.global_transform.affine_inverse() * _player.global_position
	_start_climb(ship, [start, Vector3(side * (hw + 0.3), deck + float(spec["bulwark"]) + 0.35, z), Vector3(side * (hw - 0.8), deck + 0.05, z)], float(cfg["climb_seconds"]))


# --- the thrown rope ---

# Throws a rope from `ship`'s rail (ship-space point) to land at a scene position (on the water there).
func throw_rope(ship: Node3D, rail: Vector3, lands_at: Vector3) -> void:
	var key := ""
	var net := get_tree().get_first_node_in_group("net_sea")
	if net != null and bool(net.call("active")):  # everyone sees it; the swimmer who reaches it hauls himself up
		var session_net: Node = net.get("net")
		key = String(net.call("send_rope", (_ships.get("ships") as Array).find(ship), rail, session_net.call("to_shared", lands_at)))
	show_rope(key, ship, rail, lands_at)


# A rope out from a ship's rail (ours, or another player's sent by game/net_sea.gd under `key`).
func show_rope(key: String, ship: Node3D, rail: Vector3, lands_at: Vector3) -> void:
	var rope := SeaRope.new()
	(_sea.call("sea_root") as Node3D).add_child(rope)  # under the sea's root: shifts with the floating origin
	rope.setup(ship, rail, lands_at, float(cfg["rope_seconds"]))
	rope.set_meta("key", key)
	ropes.append(rope)


# Another machine's swimmer took the rope `key`: it is pulled in here too.
func drop_rope(key: String) -> void:
	for rope: SeaRope in ropes.duplicate():
		if String(rope.get_meta("key", "")) == key:
			ropes.erase(rope)
			rope.queue_free()


func _haul(rope: SeaRope) -> void:
	var ship := rope.ship
	var spec: Dictionary = ship.get("spec")
	var side := signf(rope.rail_local.x) if rope.rail_local.x != 0.0 else 1.0
	var start: Vector3 = ship.global_transform.affine_inverse() * _player.global_position
	var over := Vector3(rope.rail_local.x + side * 0.3, float(spec["deck"]) + float(spec["bulwark"]) + 0.35, rope.rail_local.z)
	var on_deck := Vector3(rope.rail_local.x - side * 0.8, float(spec["deck"]) + 0.05, rope.rail_local.z)
	var key := String(rope.get_meta("key", ""))
	var net := get_tree().get_first_node_in_group("net_sea")
	if key != "" and net != null and bool(net.call("active")):
		net.call("rope_used", key)
	ropes.erase(rope)
	rope.queue_free()
	_start_climb(ship, [start, over, on_deck], float(cfg["haul_seconds"]))
	_sea.emit_signal("notice", "Hauled aboard")


# The rail spot nearest the player on the ship he stands on (ship space), when he is at the rail; INF when not.
func rail_spot() -> Vector3:
	var ship: Node3D = _ships.call("ship_aboard")
	if ship == null or _ships.get("helm_ship") != null:
		return Vector3.INF
	var local: Vector3 = ship.global_transform.affine_inverse() * _player.global_position
	var hw := float(_ships.get("rules").call("half_width", String(ship.get("state")["ship"]), local.z))
	if absf(local.x) < hw - 1.0:
		return Vector3.INF
	return Vector3(signf(local.x) * hw, float(ship.get("spec")["deck"]) + float(ship.get("spec")["bulwark"]), local.z)


# --- climbing (ladder or rope): the body follows a path in the ship's space ---

func _start_climb(ship: Node3D, path: Array, seconds: float) -> void:
	_climb = {"ship": ship, "path": path, "t": 0.0, "seconds": seconds}
	_player.set("carried", true)
	_player.set("swimming", false)


func _climbing(delta: float) -> void:
	var ship: Node3D = _climb["ship"]
	var path: Array = _climb["path"]
	_climb["t"] = minf(float(_climb["t"]) + delta / float(_climb["seconds"]), 1.0)
	var t := float(_climb["t"])
	var local: Vector3 = (path[0] as Vector3).lerp(path[1], t / 0.75) if t < 0.75 else (path[1] as Vector3).lerp(path[2], (t - 0.75) / 0.25)
	_player.call("pin", ship.global_transform * local)
	if t >= 1.0:
		_climb = {}
		_player.set("carried", false)
		_sea.get("look").set("under_water", false)
		under = false
		_view_under(false)
		hud.show_state(stamina / max_stamina(), false, false, 0.0, Color.BLACK, delta)


func climbing() -> bool:
	return not _climb.is_empty()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- the interact key ---

# Other players (scene positions) swimming within the rope's reach of the player's rail spot.
func _swimmer_near() -> Vector3:
	var others: Variant = _sea.get("others")
	if not others is Callable or not (others as Callable).is_valid():
		return Vector3.INF
	var best := Vector3.INF
	for at: Vector3 in (others as Callable).call():
		if at.y < surface_at(at) - float(cfg["wade"]) and _flat_distance(at, _player.global_position) <= float(cfg["rope_reach"]):
			if not best.is_finite() or _flat_distance(at, _player.global_position) < _flat_distance(best, _player.global_position):
				best = at
	return best


func prompt(key: String) -> String:
	if not ladder_near().is_empty():
		return "[%s] Climb the rope ladder" % key
	if rail_spot().is_finite() and _swimmer_near().is_finite():
		return "[%s] Throw a rope to the swimmer" % key
	return ""


func interact() -> bool:
	var spot := ladder_near()
	if not spot.is_empty():
		climb_ladder(spot)
		return true
	var rail := rail_spot()
	var swimmer := _swimmer_near()
	if rail.is_finite() and swimmer.is_finite():
		throw_rope(_ships.call("ship_aboard"), rail, swimmer + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)))
		return true
	return false
