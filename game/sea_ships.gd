# Purpose: the sea's ships (sea step 5a): the WORLD FLEET (director: ships belong to the world and stay where they
# were left), each stepped by core/sea/ship_rules.gd every frame before the player moves, so a player on a deck is
# carried with it exactly (SHIP-LOCAL decks: his place on the deck is kept while the hull rolls and turns; jumping
# keeps it too). Taking the helm (the HELMSMAN'S Sailing level must reach the ship's; his Sailing perks apply),
# W / S through the sail stages, A / D on the rudder, F or jump to let go; the anchor at the bow capstan. Running
# aground stops a ship. Sailing xp for the helmsman per 100 m under sail. The helm panel (game/ship_helm_panel.gd).
# Online the host alone steps the fleet and sends it (game/net_sea.gd); other machines glide after it, and their helm,
# rudder, sails and anchor are requests the host checks.
# Dependencies: core/sea/ship_rules.gd, game/sea_ship.gd, game/ship_helm_panel.gd, data/sea/ships.json; the sea world
# (weather, clock, ocean swell, waves, skills), the player (carry, pin, at_helm).
extends Node3D

const ShipRules = preload("res://core/sea/ship_rules.gd")
const SeaShip = preload("res://game/sea_ship.gd")
const HelmPanel = preload("res://game/ship_helm_panel.gd")
const SkillPerks = preload("res://core/skill_perks.gd")

const HELM_REACH := 1.5
const ANCHOR_REACH := 1.8
const CALM_BOB := 0.2  # m of swell a ship still rides on the flat tiers (Potato / Low draw no waves)

var rules: ShipRules
var ships: Array = []  # SeaShip
var helm_ship: SeaShip = null  # the ship this player steers
var panel := HelmPanel.new()

var _sea: Node3D  # game/sea_world.gd
var _player: CharacterBody3D
var _ray := PhysicsRayQueryParameters3D.new()
var _floor_rid: RID
var _xp_metres := 0.0
var _aground_told := false
var _layer := CanvasLayer.new()
var last_ground := ""  # dev: what the last aground probe hit
var wanted_rudder := 0.0  # the helm's keys: the rudder and sail stage this player asks for (sent to the host online)
var wanted_stage := 1
var _helmsmen := {}  # SeaShip -> {"id": peer, "level": claimed Sailing level} (the host's word online)
var _asked: SeaShip = null  # client: the helm we asked the host for
var _slow := 0.0
var shipyard: Node3D  # game/sea_shipyard.gd: where built ships are launched
var working := false  # this player is trimming sails at a rigging spot (holding interact)
var dev_rudder := NAN  # dev: a rudder held without keys (tests run without focus)


func setup(sea_world: Node3D, player: CharacterBody3D, floor_rid: RID) -> void:
	_sea = sea_world
	_player = player
	process_priority = -10  # before the player's own movement: the deck moves first, then he walks on it
	rules = ShipRules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/ships.json")))
	_ray.collision_mask = 1
	_floor_rid = floor_rid
	_layer.layer = 5
	_layer.add_child(panel)
	panel.visible = false
	add_child(_layer)
	for entry: Dictionary in rules.cfg["fleet"]:
		spawn(String(entry["ship"]), float(entry["at"][0]), float(entry["at"][1]), float(entry["yaw"]))


func spawn(ship_id: String, x: float, z: float, yaw_deg: float) -> SeaShip:
	var ship := SeaShip.new()
	add_child(ship)
	ship.setup(rules, rules.new_state(ship_id, x, z, yaw_deg))
	ships.append(ship)
	return ship


# --- every frame ---

func _process(delta: float) -> void:
	if not bool(_sea.call("running")) or delta <= 0.0:
		return
	var net := _net()
	var client := net != null and bool(net.call("is_client"))
	var t: float = _sea.call("seconds")
	var ocean: Node3D = _sea.get("ocean")
	var swell := float(ocean.get("swell")) if bool(ocean.call("is_moving")) else CALM_BOB
	var waves: RefCounted = ocean.get("waves")
	var here := _player.global_position
	var inside := bool(_sea.get("inside"))
	_slow -= delta
	if _slow <= 0.0:
		_slow = 0.5
		for ship: SeaShip in ships:  # each ship sails in the wind where she is
			ship.set_meta("weather", _sea.call("weather_at", Vector3(float(ship.state["x"]), 0.0, float(ship.state["z"]))))
		if net != null and not client:
			_check_helmsmen()
	for ship: SeaShip in ships:
		var weather: Dictionary = ship.get_meta("weather", {})
		var wind := float(weather.get("wind", 0.3))
		var wind_dir := float(weather.get("wind_dir", 0.0))
		var before: Transform3D = ship.global_transform
		var yaw_before := float(ship.state["yaw"])
		var riding := inside and (ship == helm_ship or rules.aboard(String(ship.state["ship"]), before.affine_inverse() * here))
		if ship == helm_ship:
			_steer(ship, delta, client)
		var was := Vector2(float(ship.state["x"]), float(ship.state["z"]))
		var moved := 0.0
		if client:
			_follow_host(ship, delta)
			moved = was.distance_to(Vector2(float(ship.state["x"]), float(ship.state["z"])))
		else:
			moved = rules.step(ship.state, wind, wind_dir, _speed_pct(ship), delta)
			if moved > 0.0 and _aground(ship):
				ship.state["x"] = was.x
				ship.state["z"] = was.y
				ship.state["speed"] = 0.0
				moved = 0.0
				if ship == helm_ship and not _aground_told:
					_aground_told = true
					_sea.emit_signal("notice", "Run aground: back her off with the oars (S)")
			elif moved > 0.0:
				_aground_told = false
		ship.pose(waves, t, swell, wind, wind_dir, delta)
		if riding:
			_player.call("carry", ship.global_transform * before.affine_inverse(), wrapf(float(ship.state["yaw"]) - yaw_before, -PI, PI))
		if ship == helm_ship:
			_player.call("pin", ship.deck_spot([float(ship.spec["helm"][0]), float(ship.spec["helm"][1]) + 1.0]))
			if float(rules.stage(ship.state)["sail"]) > 0.0:
				_sailing_xp(ship, moved)
	var deck_now := ship_aboard() if inside and helm_ship == null else null
	working = deck_now != null and _rigging_spot(deck_now, deck_now.global_transform.affine_inverse() * here) >= 0 and bool(_player.get("controls_enabled")) and Input.is_action_pressed("interact")
	if helm_ship != null:
		var w: Dictionary = helm_ship.get_meta("weather", {})
		panel.show_ship(helm_ship.state, helm_ship.spec, rules, float(w.get("wind", 0.3)), float(w.get("wind_dir", 0.0)))


func _steer(ship: SeaShip, delta: float, client: bool) -> void:
	var held := Input.get_axis("move_left", "move_right") if bool(_player.get("controls_enabled")) else 0.0
	if not is_nan(dev_rudder):
		held = dev_rudder
	wanted_rudder = move_toward(wanted_rudder, held, delta * (1.6 if held != 0.0 else 2.4))
	if bool(_player.get("controls_enabled")):
		if Input.is_action_just_pressed("move_forward"):
			wanted_stage = mini(wanted_stage + 1, rules.stage_count() - 1)
		elif Input.is_action_just_pressed("move_back"):
			wanted_stage = maxi(wanted_stage - 1, 0)
		elif Input.is_action_just_pressed("jump"):
			let_go()
			return
	if not client:  # online the host takes these from game/net_sea.gd; here they are ours to set
		ship.state["rudder"] = wanted_rudder
		ship.state["stage"] = wanted_stage


# --- online (game/net_sea.gd) ---

func _net() -> Node:
	var net := get_tree().get_first_node_in_group("net_sea")
	return net if net != null and bool(net.call("active")) else null


# Client: the host's states (one array per ship: x, z, yaw, speed, stage, rudder, anchored, helmsman).
func host_states(states: Array) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_match_fleet(states)
	for i in mini(states.size(), ships.size()):
		var got: Array = states[i]
		if got.size() < 9:
			continue
		var ship: SeaShip = ships[i]
		ship.set_meta("host", {"x": float(got[0]), "z": float(got[1]), "yaw": float(got[2]), "at": now})
		ship.state["speed"] = float(got[3])
		ship.state["stage"] = clampi(int(got[4]), 0, rules.stage_count() - 1)
		ship.state["rudder"] = clampf(float(got[5]), -1.0, 1.0)
		ship.state["anchored"] = bool(got[6])
		_helmsmen[ship] = {"id": int(got[7]), "level": 0}
		var mine := int(got[7]) == int(_net().call("my_id"))
		if mine and helm_ship == null and _asked == ship:
			_asked = null
			_enter_helm(ship)
		elif not mine and helm_ship == ship:
			_leave_helm_here()


# Client: the host's fleet decides which ships exist (its ship ids, in order): ours is rebuilt when it differs.
func _match_fleet(states: Array) -> void:
	var same := states.size() == ships.size()
	for i in mini(states.size(), ships.size()):
		if (states[i] as Array).size() < 9 or String(states[i][8]) != String(ships[i].state["ship"]):
			same = false
	if same:
		return
	_leave_helm_here()
	for ship: SeaShip in ships:
		ship.queue_free()
	ships.clear()
	_helmsmen.clear()
	for got: Array in states:
		if got.size() >= 9 and (rules.cfg["ships"] as Dictionary).has(String(got[8])):
			spawn(String(got[8]), float(got[0]), float(got[1]), rad_to_deg(float(got[2])))


# Client: glide towards where the host says the ship is (moving on at her speed since that word was sent).
func _follow_host(ship: SeaShip, delta: float) -> void:
	if not ship.has_meta("host"):
		return
	var h: Dictionary = ship.get_meta("host")
	var age := minf(Time.get_ticks_msec() / 1000.0 - float(h["at"]), 0.5)
	var speed := float(ship.state["speed"])
	var tx := float(h["x"]) - sin(float(h["yaw"])) * speed * age
	var tz := float(h["z"]) - cos(float(h["yaw"])) * speed * age
	var yaw := float(ship.state["yaw"])
	var x := float(ship.state["x"]) - sin(yaw) * speed * delta
	var z := float(ship.state["z"]) - cos(yaw) * speed * delta
	var k := 1.0 - exp(-3.0 * delta)
	if Vector2(tx - x, tz - z).length() > 30.0:
		k = 1.0  # too far apart: jump
	ship.state["x"] = lerpf(x, tx, k)
	ship.state["z"] = lerpf(z, tz, k)
	ship.state["yaw"] = lerp_angle(yaw, float(h["yaw"]), k)


# Host: who steers which ship (0 = nobody).
func helmsman_of(ship: SeaShip) -> int:
	return int((_helmsmen.get(ship, {}) as Dictionary).get("id", 0))


# Host: gives the helm to a player who claimed `level` in Sailing (refused when taken or not enough).
func give_helm(ship: SeaShip, id: int, level: int) -> bool:
	if helmsman_of(ship) != 0 or not rules.can_steer(String(ship.state["ship"]), level):
		return false
	_helmsmen[ship] = {"id": id, "level": level}
	return true


func free_helm(ship: SeaShip) -> void:
	_helmsmen.erase(ship)
	ship.state["rudder"] = 0.0


# Host: a helmsman who left the game or the wheel lets go of it.
func _check_helmsmen() -> void:
	var net := _net()
	var at: Dictionary = net.get("net").call("positions")
	for ship: SeaShip in _helmsmen.keys():
		var id := helmsman_of(ship)
		if id == int(net.call("my_id")):
			continue
		var spot: Vector3 = ship.deck_spot([float(ship.spec["helm"][0]), float(ship.spec["helm"][1]) + 1.0])
		if not at.has(id) or Vector2((at[id] as Vector3).x - spot.x, (at[id] as Vector3).z - spot.z).length() > 6.0:
			free_helm(ship)


# Does the water ahead (behind when going astern) have ground higher than the keel?
func _aground(ship: SeaShip) -> bool:
	var going := 1.0 if float(ship.state["speed"]) >= 0.0 else -1.0
	var outline: Array = ship.spec["outline"]
	var ahead := (float(outline.back()[0]) - 1.0) if going > 0.0 else (float(outline[0][0]) + 1.0)
	var spot: Vector3 = ship.global_transform * Vector3(0.0, 0.0, ahead)
	_ray.from = Vector3(spot.x, global_position.y + 40.0, spot.z)
	_ray.to = Vector3(spot.x, global_position.y - float(ship.spec["draft"]), spot.z)
	var skip: Array[RID] = [_floor_rid, ship.get_rid()]
	_ray.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		last_ground = "%s at %s" % [str(hit["collider"]), str(hit["position"])]
	return not hit.is_empty()


# --- the helmsman's Sailing ---

func sailing_level() -> int:
	var skills: Variant = _sea.get("skills")
	if skills == null:
		return 1
	return int((skills as Node).get("skills").call("level", "sailing"))


func _speed_pct(ship: SeaShip) -> float:
	return _helm_pct(ship) + float(rules.cfg["rigging_bonus"]) * float(_crew_at_rigging(ship))


# How many players trim this ship's sails right now: this player, and (online, the host) others whose deck spot lies
# at one of her rigging spots and who say they are working it.
func _crew_at_rigging(ship: SeaShip) -> int:
	var n := 0
	if working and ship_aboard() == ship:
		n += 1
	var net := _net()
	if net != null:
		for local: Vector3 in net.get("net").call("workers_on", ship):
			if _rigging_spot(ship, local) >= 0:
				n += 1
	return mini(n, (ship.spec["rigging"] as Array).size())


# The index of the rigging spot a ship-space point stands at (-1 = none).
func _rigging_spot(ship: SeaShip, local: Vector3) -> int:
	var spots: Array = ship.spec["rigging"]
	for i in spots.size():
		if Vector2(local.x - float(spots[i][0]), local.z - float(spots[i][1])).length() <= float(rules.cfg["rigging_reach"]):
			return i
	return -1


func _helm_pct(ship: SeaShip) -> float:
	var skills: Variant = _sea.get("skills")
	if skills == null:
		return 0.0
	if ship == helm_ship:
		return float((skills as Node).call("perk", "sailing", "ship_speed"))
	var level := int((_helmsmen.get(ship, {}) as Dictionary).get("level", 0))  # another player steers: his claimed level's perks
	if level <= 0:
		return 0.0
	return SkillPerks.total((skills as Node).get("skilling").get("unlocks", {}), "sailing", level, "ship_speed")


func _sailing_xp(ship: SeaShip, moved: float) -> void:
	_xp_metres += moved
	if _xp_metres < 100.0:
		return
	_xp_metres -= 100.0
	var skills: Variant = _sea.get("skills")
	if skills != null:
		(skills as Node).call("gain_xp", "sailing", int(ship.spec["xp_per_100m"]))


# --- the helm and the anchor ---

# The ship this player stands on (null when none).
func ship_aboard() -> SeaShip:
	for ship: SeaShip in ships:
		if rules.aboard(String(ship.state["ship"]), ship.global_transform.affine_inverse() * _player.global_position):
			return ship
	return null


func _near_spot(ship: SeaShip, spot: Array, reach: float) -> bool:
	var at: Vector3 = ship.deck_spot(spot)
	return Vector2(at.x - _player.global_position.x, at.z - _player.global_position.z).length() <= reach


func prompt(key: String) -> String:
	if helm_ship != null:
		return ""
	var ship := ship_aboard()
	if ship == null:
		return ""
	var ship_name := String(ship.spec["name"])
	if _near_spot(ship, ship.spec["helm"], HELM_REACH):
		var need := int(ship.spec["sailing_level"])
		if not rules.can_steer(String(ship.state["ship"]), sailing_level()):
			return "The %s needs Sailing %d at the helm (you have %d)" % [ship_name, need, sailing_level()]
		return "[%s] Take the helm of the %s" % [key, ship_name]
	if _near_spot(ship, ship.spec["anchor"], ANCHOR_REACH):
		return "[%s] %s" % [key, "Weigh the anchor" if bool(ship.state["anchored"]) else "Let the anchor go"]
	if _rigging_spot(ship, ship.global_transform.affine_inverse() * _player.global_position) >= 0:
		return "Trimming the sails: +%d%% speed" % roundi(float(rules.cfg["rigging_bonus"]) * 100.0) if working else "[hold %s] Trim the sails (+%d%% speed while held)" % [key, roundi(float(rules.cfg["rigging_bonus"]) * 100.0)]
	return ""


# The interact key at sea; true when a ship used it.
func interact() -> bool:
	if helm_ship != null:
		let_go()
		return true
	var ship := ship_aboard()
	if ship == null:
		return false
	if _near_spot(ship, ship.spec["helm"], HELM_REACH):
		if rules.can_steer(String(ship.state["ship"]), sailing_level()):
			if helmsman_of(ship) != 0 and helmsman_of(ship) != _my_id():
				_sea.emit_signal("notice", "Somebody else has the helm")
			else:
				take_helm(ship)
		return true
	if _near_spot(ship, ship.spec["anchor"], ANCHOR_REACH):
		toggle_anchor(ship)
		return true
	return false


func take_helm(ship: SeaShip) -> void:
	var net := _net()
	if net != null and bool(net.call("is_client")):
		_asked = ship  # the host decides; the fleet's next word gives us the wheel
		net.call("request_helm", ships.find(ship), sailing_level())
		return
	if not give_helm(ship, _my_id(), sailing_level()):
		return
	_enter_helm(ship)


func _my_id() -> int:
	var net := _net()
	return int(net.call("my_id")) if net != null else 1


func _enter_helm(ship: SeaShip) -> void:
	helm_ship = ship
	wanted_rudder = float(ship.state["rudder"])
	wanted_stage = int(ship.state["stage"])
	_player.set("at_helm", true)
	_player.call("look_at_point", ship.deck_spot([0.0, float(ship.spec["outline"].back()[0])], 1.6))  # face the bow
	_xp_metres = 0.0
	panel.visible = true


func let_go() -> void:
	if helm_ship != null:
		var net := _net()
		if net != null and bool(net.call("is_client")):
			net.call("leave_helm", ships.find(helm_ship))
		else:
			free_helm(helm_ship)
	_leave_helm_here()


func _leave_helm_here() -> void:
	helm_ship = null
	_asked = null
	_player.set("at_helm", false)
	panel.visible = false


func toggle_anchor(ship: SeaShip) -> void:
	var net := _net()
	if net != null and bool(net.call("is_client")):
		net.call("request_anchor", ships.find(ship))
		_sea.emit_signal("notice", "Anchor weighed" if bool(ship.state["anchored"]) else "Anchor let go")
		return
	ship.state["anchored"] = not bool(ship.state["anchored"])
	_sea.emit_signal("notice", "Anchor weighed" if not bool(ship.state["anchored"]) else "Anchor let go")


# --- the shipyard and the saved fleet ---

# The shipyard launched a ship (game/fantasy_world.gd ship_built): the host (or alone) puts her in the water off the
# slipway; a client asks the host.
func build(ship_id: String) -> void:
	if not (rules.cfg["ships"] as Dictionary).has(ship_id):
		return
	var net := _net()
	if net != null and bool(net.call("is_client")):
		net.call("request_build", ship_id)
		_sea.emit_signal("notice", "The %s slides down the slipway" % String(rules.spec(ship_id)["name"]))
		return
	launch(ship_id)


func launch(ship_id: String) -> void:
	var outline: Array = rules.spec(ship_id)["outline"]
	var half_length := absf(float(outline[0][0]) - float(outline.back()[0])) * 0.5
	var spot: Vector3 = shipyard.call("launch_spot", 0, half_length)
	for k in 12:  # the first lane off the slipway with no ship lying in it
		spot = shipyard.call("launch_spot", k, half_length)
		var free := true
		for other: SeaShip in ships:
			if Vector2(float(other.state["x"]) - spot.x, float(other.state["z"]) - spot.y).length() < 16.0 + half_length:
				free = false
		if free:
			break
	spawn(ship_id, spot.x, spot.y, spot.z)
	_sea.emit_signal("notice", "The %s slides down the slipway" % String(rules.spec(ship_id)["name"]))


# The fleet for the host's save: every ship's kind, place, heading and anchor.
func to_list() -> Array:
	var out: Array = []
	for ship: SeaShip in ships:
		out.append({"ship": ship.state["ship"], "x": snappedf(float(ship.state["x"]), 0.1), "z": snappedf(float(ship.state["z"]), 0.1), "yaw": snappedf(float(ship.state["yaw"]), 0.001), "anchored": ship.state["anchored"], "cell": _sea.get("map").get("cell")})
	return out


# A saved fleet replaces the starting one (unknown kinds and places off the map are dropped; anchored as left).
func from_list(saved: Variant) -> void:
	if not saved is Array or (saved as Array).is_empty():
		return
	var keep: Array = []
	var map: Object = _sea.get("map")
	for entry: Variant in saved:
		if not entry is Dictionary or not (rules.cfg["ships"] as Dictionary).has(str(entry.get("ship"))):
			continue
		var fixed: Dictionary = (entry as Dictionary).duplicate()
		var old_cell := float(fixed.get("cell", 2000.0))  # fleets saved before the 6 km regions carry no cell
		if old_cell != float(map.get("cell")) and old_cell > 0.0:
			var moved: Vector2 = map.call("moved_from", float(fixed.get("x", 0.0)), float(fixed.get("z", 0.0)), old_cell)
			fixed["x"] = moved.x
			fixed["z"] = moved.y
		if float(map.call("inside_by", float(fixed.get("x", 0.0)), float(fixed.get("z", 0.0)))) > 0.0:
			keep.append(fixed)
	if keep.is_empty():
		return
	for ship: SeaShip in ships:
		ship.queue_free()
	ships.clear()
	_helmsmen.clear()
	for entry: Dictionary in keep:
		var ship := spawn(String(entry["ship"]), float(entry["x"]), float(entry["z"]), rad_to_deg(float(entry.get("yaw", 0.0))))
		ship.state["anchored"] = bool(entry.get("anchored", true))


# --- dev ---

# Turns a ship so the wind comes `off` degrees off its stern (0 = running, 90 = beam reach).
func dev_face_wind(ship: SeaShip, off: float) -> void:
	var to := Vector2.from_angle(float((_sea.get("weather") as Dictionary).get("wind_dir", 0.0))).rotated(deg_to_rad(off))
	ship.state["yaw"] = atan2(-to.x, -to.y)

func status() -> String:
	var lines := PackedStringArray()
	var weather: Dictionary = _sea.get("weather")
	for ship: SeaShip in ships:
		var s: Dictionary = ship.state
		var off := ShipRules.off_wind(float(s["yaw"]), float(weather.get("wind_dir", 0.0)))
		lines.append("ship %s at (%.0f, %.0f) heading %.0f deg, %.1f m/s, %s, %s, %s %.0f deg off the wind (%.0f %%), rudder %.2f, deck y %.2f%s" % [s["ship"], s["x"], s["z"],
			fposmod(-rad_to_deg(float(s["yaw"])), 360.0), s["speed"], String(rules.stage(s)["name"]), "anchored" if bool(s["anchored"]) else "under way",
			ShipRules.point_of_sail(off), off, rules.wind_share(off) * 100.0, s["rudder"], (ship.global_transform * Vector3(0, float(ship.spec["deck"]), 0)).y,
			", player aboard" if ship == ship_aboard() else ""])
	return "\n".join(lines) + ("\nlast ground: " + last_ground if last_ground != "" else "")
