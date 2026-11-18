# Purpose: ships' cannons (sea step 5d, LOCKED "cannons manned by players: F to sit, aim, fire, while one steers"):
# a cannon model (assets/models/sea/cannon.gltf, tools/blender/sea_cannon.py) at every data/sea/ships.json cannon
# spot, pointing outboard. A player sits behind one (interact), aims it by looking (it turns arc_deg each way from
# broadside and lifts pitch_min..pitch_max), fires with the shoot key (reload seconds per cannon) and leaves with
# interact or jump. Balls fly under gravity; one that strikes another ship's hull damages it (game/sea_hull.gd, the
# host's word), others splash into the sea or thud into the land. Smoke, flash, recoil, splashes; stand-in sound =
# the game's explosion until the sound pass.
# Online: the shooter fires at once on his own screen and asks the host (game/net_sea.gd request_fire); the host
# checks he sits at that cannon and it is loaded, fires its own ball (the one that does damage) and tells everyone
# else, who fly a harmless copy.
# Dependencies: data/sea/cannons.json, game/fx_kit.gd, game/sea_hull.gd (through the fleet); made by
# game/sea_ships.gd (child of the fleet: its local space = sea coordinates, so balls ride the floating origin).
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")
const MODEL := "res://assets/models/sea/cannon.gltf"
const TRUNNION_UP := 0.62  # the barrel's pivot height (tools/blender/sea_cannon.py TRUNNION)
const TRUNNION_BACK := 0.05

var cfg: Dictionary
var seated := {}  # this player's seat: {"ship": SeaShip, "index": int}
var dev_fire := false  # dev: fire once without the key (tests run without focus)
var dev_target: Node3D = null  # dev: a ship aimed at (with the drop worked out) instead of the look
var fired := 0  # dev / checks: balls this machine fired; hits: hull strikes it saw
var hits := 0
var last_end := ""  # dev / checks: how the last ball ended (what, where in sea metres, flight time)
var _fleet: Node3D  # game/sea_ships.gd
var _sea: Node3D
var _player: CharacterBody3D
var _guns := {}  # SeaShip -> Array of {"holder", "turn", "pivot", "muzzle" (pivot space), "m" (base aim, holder space), "side", "spot", "ready_at", "kick"}
var _balls: Array = []  # {"mesh", "vel": Vector3, "life", "real": bool (does damage), "from": SeaShip}
var _ball_mesh: SphereMesh
var _ball_mat: StandardMaterial3D
var _ray := PhysicsRayQueryParameters3D.new()


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/cannons.json"))
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = float(cfg["ball_radius"])
	_ball_mesh.height = float(cfg["ball_radius"]) * 2.0
	_ball_mesh.radial_segments = 10
	_ball_mesh.rings = 6
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.albedo_color = Color(0.08, 0.08, 0.09)
	_ball_mat.metallic = 0.3
	_ball_mat.roughness = 0.5
	_ray.collision_mask = 1


# A ship joined the fleet: her cannons.
func prepare(ship: Node3D) -> void:
	var list: Array = []
	if not ResourceLoader.exists(MODEL):
		_guns[ship] = list
		return
	var spec: Dictionary = ship.get("spec")
	for spot: Array in spec.get("cannons", []):
		var holder := Node3D.new()
		ship.add_child(holder)
		var side := 1.0 if float(spot[0]) >= 0.0 else -1.0
		holder.position = Vector3(float(spot[0]), float(_fleet.get("rules").call("deck_height", String(ship.get("state")["ship"]), float(spot[1]))), float(spot[1]))
		var turn := Node3D.new()
		holder.add_child(turn)
		var model := (load(MODEL) as PackedScene).instantiate() as Node3D
		turn.add_child(model)
		var barrel := model.find_child("Barrel", true, false) as Node3D
		var muzzle := model.find_child("Muzzle", true, false) as Node3D
		var muzzle_at := _centre(model, muzzle) if muzzle != null else Vector3(0.0, TRUNNION_UP, -1.3)
		var pivot_at := Vector3(0.0, TRUNNION_UP, -TRUNNION_BACK * signf(muzzle_at.z))
		var pivot := Node3D.new()
		pivot.position = pivot_at
		model.add_child(pivot)
		for part: Node3D in [barrel, muzzle]:
			if part != null:
				var keep := part.global_transform
				part.get_parent().remove_child(part)
				pivot.add_child(part)
				part.global_transform = keep
		var m := Vector3(muzzle_at.x - pivot_at.x, 0.0, muzzle_at.z - pivot_at.z).normalized()
		holder.rotation.y = _heading(Vector3(side, 0.0, 0.0)) - _heading(m)  # broadside, outboard
		list.append({"holder": holder, "turn": turn, "pivot": pivot, "muzzle": muzzle_at - pivot_at, "m": m, "side": side, "spot": spot, "ready_at": 0.0, "kick": 0.0, "yaw": 0.0, "pitch": 0.0})
	_guns[ship] = list


# The middle of a node's mesh in the model's own space.
static func _centre(model: Node3D, node: Node3D) -> Vector3:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh == null:
		for found in node.find_children("*", "MeshInstance3D", true, false):
			mesh = found as MeshInstance3D
			break
	var into := model.global_transform.affine_inverse()
	return into * (mesh.global_transform * mesh.get_aabb().get_center()) if mesh != null else into * node.global_position


# Rotation about +y that turns (1, 0, 0) towards v.
static func _heading(v: Vector3) -> float:
	return atan2(-v.z, v.x)


func forget(ship: Node3D) -> void:
	_guns.erase(ship)
	if seated.get("ship") == ship:
		stand_up()


# --- the seat ---

func _seat_spot(gun: Dictionary) -> Array:
	return [float(gun["spot"][0]) - float(gun["side"]) * float(cfg["seat_back"]), float(gun["spot"][1])]


# The cannon this player stands at (its index on the ship he is aboard, -1 = none).
func cannon_here(ship: Node3D) -> int:
	if ship == null:
		return -1
	var local: Vector3 = ship.global_transform.affine_inverse() * _player.global_position
	var list: Array = _guns.get(ship, [])
	for i in list.size():
		var seat := _seat_spot(list[i])
		if Vector2(local.x - float(seat[0]), local.z - float(seat[1])).length() <= float(cfg["seat_reach"]):
			return i
	return -1


func prompt(key: String, ship: Node3D) -> String:
	if not seated.is_empty():
		var gun: Dictionary = (_guns.get(seated["ship"], []) as Array)[int(seated["index"])]
		var wait := float(gun["ready_at"]) - _now()
		return ("Reloading... %.0f s" % ceilf(wait) if wait > 0.0 else "[Left Mouse] Fire") + "   [%s] Leave the cannon" % key
	if cannon_here(ship) >= 0:
		return "[%s] Man the cannon" % key
	return ""


func sit(ship: Node3D, index: int) -> void:
	seated = {"ship": ship, "index": index}
	_player.set("at_helm", true)
	_player.set("manning", true)


func stand_up() -> void:
	if seated.is_empty():
		return
	seated = {}
	dev_target = null
	_player.set("at_helm", false)
	_player.set("manning", false)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- every frame ---

func _process(delta: float) -> void:
	if not bool(_sea.call("running")) or delta <= 0.0:
		return
	if not seated.is_empty():
		_man(delta)
	for ship: Node3D in _guns:
		for gun: Dictionary in _guns[ship]:
			if float(gun["kick"]) > 0.0:
				gun["kick"] = maxf(float(gun["kick"]) - delta / 0.7, 0.0)
				var back := -(gun["m"] as Vector3) * 0.3 * sin(float(gun["kick"]) * PI * 0.5)
				(gun["pivot"] as Node3D).position = Vector3(back.x, TRUNNION_UP, back.z - TRUNNION_BACK * signf((gun["muzzle"] as Vector3).z))
	_fly(delta)


func _man(delta: float) -> void:
	var ship: Node3D = seated["ship"]
	if not is_instance_valid(ship) or bool(ship.get("state").get("sinking", false)):
		stand_up()
		return
	var list: Array = _guns.get(ship, [])
	var gun: Dictionary = list[int(seated["index"])]
	_player.call("pin", ship.call("deck_spot", _seat_spot(gun)))
	if bool(_player.get("controls_enabled")) and Input.is_action_just_pressed("jump"):
		stand_up()
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null or is_instance_valid(dev_target):  # the cannon follows the look, inside its arc
		var world_look := -camera.global_transform.basis.z if camera != null else Vector3.FORWARD
		if is_instance_valid(dev_target):  # dev: at her hull side, lifted for the drop
			var to: Vector3 = dev_target.call("deck_spot", [0.0, 0.0], -0.9) - (gun["pivot"] as Node3D).global_position
			var flat := Vector2(to.x, to.z).length()
			var lift := 0.5 * asin(clampf(float(cfg["gravity"]) * flat / pow(float(cfg["speed"]), 2.0), -1.0, 1.0)) + atan2(to.y, flat)
			world_look = Vector3(to.x, 0.0, to.z).normalized() * cos(lift) + Vector3.UP * sin(lift)
		var look := (gun["holder"] as Node3D).global_transform.basis.inverse() * world_look
		var yaw := clampf(wrapf(_heading(look) - _heading(gun["m"]), -PI, PI), -deg_to_rad(float(cfg["arc_deg"])), deg_to_rad(float(cfg["arc_deg"])))
		var pitch := clampf(asin(clampf(look.normalized().y, -1.0, 1.0)), deg_to_rad(float(cfg["pitch_min"])), deg_to_rad(float(cfg["pitch_max"])))
		_aim(gun, lerp_angle(float(gun["yaw"]), yaw, minf(delta * 8.0, 1.0)), lerpf(float(gun["pitch"]), pitch, minf(delta * 8.0, 1.0)))
	var pressed := dev_fire or (bool(_player.get("controls_enabled")) and Input.is_action_just_pressed("shoot") and bool(_player.call("_mouse_held")))
	dev_fire = false
	if pressed and _now() >= float(gun["ready_at"]):
		var ships: Array = _fleet.get("ships")
		var net: Node = _fleet.call("_net")
		var client := net != null and bool(net.call("is_client"))
		fire(ship, int(seated["index"]), float(gun["yaw"]), float(gun["pitch"]), not client)
		if client:
			net.call("request_fire", ships.find(ship), int(seated["index"]), float(gun["yaw"]), float(gun["pitch"]))
		elif net != null:
			net.call("tell_fire", ships.find(ship), int(seated["index"]), float(gun["yaw"]), float(gun["pitch"]))


func _aim(gun: Dictionary, yaw: float, pitch: float) -> void:
	gun["yaw"] = yaw
	gun["pitch"] = pitch
	(gun["turn"] as Node3D).rotation.y = yaw
	var axis := (gun["m"] as Vector3).cross(Vector3.UP).normalized()
	(gun["pivot"] as Node3D).basis = Basis(axis, pitch)


# Fires a cannon at that aim. real = this machine's ball does the damage (the host, or alone).
func fire(ship: Node3D, index: int, yaw: float, pitch: float, real: bool) -> bool:
	var list: Array = _guns.get(ship, [])
	if index < 0 or index >= list.size() or not is_finite(yaw) or not is_finite(pitch):
		return false
	var gun: Dictionary = list[index]
	gun["ready_at"] = _now() + float(cfg["reload"]) * (1.0 - _perk("cannon_reload"))
	_aim(gun, clampf(yaw, -deg_to_rad(float(cfg["arc_deg"])), deg_to_rad(float(cfg["arc_deg"]))), clampf(pitch, deg_to_rad(float(cfg["pitch_min"])), deg_to_rad(float(cfg["pitch_max"]))))
	gun["kick"] = 1.0
	var pivot := gun["pivot"] as Node3D
	var mouth: Vector3 = pivot.global_transform * (gun["muzzle"] as Vector3)
	var way: Vector3 = (pivot.global_transform.basis * (gun["muzzle"] as Vector3)).normalized()
	var ball := MeshInstance3D.new()
	ball.mesh = _ball_mesh
	ball.material_override = _ball_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = mouth
	_balls.append({"mesh": ball, "vel": way * float(cfg["speed"]), "life": float(cfg["life"]), "real": real, "from": ship, "start": mouth})
	FxKit.burst(self, mouth + way * 0.3, Color(1.0, 0.6, 0.2), 10, 0.15, 0.25, 6.0, 0.0)
	FxKit.burst(self, mouth + way * 0.6, Color(0.75, 0.75, 0.75, 0.8), 26, 1.6, 0.6, 2.5, 0.3)
	_sound(mouth)
	fired += 1
	return true


# A ship's cannons for the pirates (game/sea_encounters.gd): [{index, side}] .
func guns_of(ship: Node3D) -> Array:
	var out: Array = []
	var list: Array = _guns.get(ship, [])
	for i in list.size():
		out.append({"index": i, "side": float(list[i]["side"])})
	return out


func loaded(ship: Node3D, index: int) -> bool:
	var list: Array = _guns.get(ship, [])
	return index >= 0 and index < list.size() and _now() >= float(list[index]["ready_at"])


# The aim (yaw, pitch) that lays this cannon on a world point (lifted for the drop), or NAN yaw when the point lies
# outside its arc or beyond its reach.
func aim_at(ship: Node3D, index: int, point: Vector3) -> Vector2:
	var list: Array = _guns.get(ship, [])
	if index < 0 or index >= list.size():
		return Vector2(NAN, NAN)
	var gun: Dictionary = list[index]
	var to: Vector3 = point - (gun["pivot"] as Node3D).global_position
	var flat := Vector2(to.x, to.z).length()
	var reach := float(cfg["gravity"]) * flat / pow(float(cfg["speed"]), 2.0)
	if reach > 1.0:
		return Vector2(NAN, NAN)
	var lift := 0.5 * asin(reach) + atan2(to.y, flat)
	var world_look := Vector3(to.x, 0.0, to.z).normalized() * cos(lift) + Vector3.UP * sin(lift)
	var look := (gun["holder"] as Node3D).global_transform.basis.inverse() * world_look
	var yaw := wrapf(_heading(look) - _heading(gun["m"]), -PI, PI)
	if absf(yaw) > deg_to_rad(float(cfg["arc_deg"])):
		return Vector2(NAN, NAN)
	return Vector2(yaw, clampf(asin(clampf(look.normalized().y, -1.0, 1.0)), deg_to_rad(float(cfg["pitch_min"])), deg_to_rad(float(cfg["pitch_max"]))))


# Host: a client's shot (game/net_sea.gd checked his seat). Fires when that cannon is loaded.
func host_fire(ship: Node3D, index: int, yaw: float, pitch: float) -> bool:
	var list: Array = _guns.get(ship, [])
	if index < 0 or index >= list.size() or _now() < float(list[index]["ready_at"]) - 0.5:
		return false
	return fire(ship, index, yaw, pitch, true)


func _fly(delta: float) -> void:
	var gravity := float(cfg["gravity"])
	for i in range(_balls.size() - 1, -1, -1):
		var b: Dictionary = _balls[i]
		var ball := b["mesh"] as MeshInstance3D
		b["life"] = float(b["life"]) - delta
		var before := ball.global_position
		var vel: Vector3 = b["vel"]
		vel.y -= gravity * delta
		b["vel"] = vel
		var after := before + vel * delta
		_ray.from = before
		_ray.to = after
		var skip: Array[RID] = []
		if is_instance_valid(b["from"]):
			skip.append((b["from"] as CollisionObject3D).get_rid())
		skip.append(_player.get_rid())
		_ray.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		var done := float(b["life"]) <= 0.0
		if not hit.is_empty():
			var at: Vector3 = hit["position"]
			var target: Object = hit["collider"]
			if target != null and (_fleet.get("ships") as Array).has(target):
				hits += 1
				FxKit.burst(self, at, Color(0.45, 0.32, 0.2), 24, 0.9, 0.25, 7.0, -9.0)  # splinters
				FxKit.burst(self, at, Color(0.7, 0.7, 0.7, 0.8), 14, 1.2, 0.5, 2.0, 0.2)
				if bool(b["real"]) and bool(cfg["friendly_fire"]):
					var ship := target as Node3D
					_fleet.get("hull_part").call("damage", ship, ship.global_transform.affine_inverse() * at, float(cfg["damage"]))
			else:
				FxKit.burst(self, at, Color(0.5, 0.42, 0.3), 20, 0.8, 0.3, 5.0, -9.0)  # earth, rock
			_sound(at)
			done = true
		elif after.y < float(_sea.call("water_height", after)):
			FxKit.burst(self, Vector3(after.x, float(_sea.call("water_height", after)), after.z), Color(0.92, 0.97, 1.0), 40, 1.1, 0.35, 8.0, -12.0)  # splash
			done = true
		if done:
			var end_at: Vector3 = hit["position"] if not hit.is_empty() else after
			# a ball (any machine's copy: they fly alike) that lands by this player hurts him (sea step 8: the pirates' fire)
			var by := end_at.distance_to(_player.global_position + Vector3(0.0, 0.9, 0.0))
			if by < float(cfg.get("splash_m", 3.0)) and b["from"] != _fleet.call("ship_aboard"):
				_player.call("take_damage", float(cfg.get("splash_damage", 35.0)) * (1.0 - by / float(cfg.get("splash_m", 3.0))))
			last_end = "%s %.0f m from the muzzle, %.1f m up, after %.1f s" % ["ship" if not hit.is_empty() and (_fleet.get("ships") as Array).has(hit["collider"]) else ("land" if not hit.is_empty() else ("sea" if float(b["life"]) > 0.0 else "time")), end_at.distance_to(b["start"]), end_at.y - (b["start"] as Vector3).y, float(cfg["life"]) - float(b["life"])]
			ball.queue_free()
			_balls.remove_at(i)
		else:
			ball.global_position = after


# A Sailing perk of this player (data/fantasy/skilling.json unlocks: cannon_reload ...), 0 without skills.
func _perk(key: String) -> float:
	var skills: Variant = _sea.get("skills")
	return clampf(float((skills as Node).call("perk", "sailing", key)), 0.0, 0.9) if skills != null else 0.0


func _sound(at: Vector3) -> void:
	var explosives: Variant = _player.get("explosives")
	if explosives != null and (explosives as Node).get("sounds") != null:
		(explosives as Node).get("sounds").call("play", "explosion", at)


func status() -> String:
	var aims := PackedStringArray()
	if not seated.is_empty():
		var gun: Dictionary = (_guns[seated["ship"]] as Array)[int(seated["index"])]
		aims.append("seated at %d yaw %.0f pitch %.0f" % [int(seated["index"]), rad_to_deg(float(gun["yaw"])), rad_to_deg(float(gun["pitch"]))])
	return "cannons fired %d hits %d balls flying %d %s, last ball: %s" % [fired, hits, _balls.size(), " ".join(aims), last_end]
