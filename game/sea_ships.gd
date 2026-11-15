# Purpose: the sea's ships (sea step 5a): the WORLD FLEET (director: ships belong to the world and stay where they
# were left), each stepped by core/sea/ship_rules.gd every frame before the player moves, so a player on a deck is
# carried with it exactly (SHIP-LOCAL decks: his place on the deck is kept while the hull rolls and turns; jumping
# keeps it too). Taking the helm (the HELMSMAN'S Sailing level must reach the ship's; his Sailing perks apply),
# W / S through the sail stages, A / D on the rudder, F or jump to let go; the anchor at the bow capstan. Running
# aground stops a ship. Sailing xp for the helmsman per 100 m under sail. The helm panel (game/ship_helm_panel.gd).
# All of it runs on this machine; the host runs the fleet and sends it in sea step 12.
# Dependencies: core/sea/ship_rules.gd, game/sea_ship.gd, game/ship_helm_panel.gd, data/sea/ships.json; the sea world
# (weather, clock, ocean swell, waves, skills), the player (carry, pin, at_helm).
extends Node3D

const ShipRules = preload("res://core/sea/ship_rules.gd")
const SeaShip = preload("res://game/sea_ship.gd")
const HelmPanel = preload("res://game/ship_helm_panel.gd")

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
	if not bool(_sea.get("inside")) or delta <= 0.0:
		return
	var weather: Dictionary = _sea.get("weather")
	var wind := float(weather.get("wind", 0.3))
	var wind_dir := float(weather.get("wind_dir", 0.0))
	var t: float = _sea.call("seconds")
	var ocean: Node3D = _sea.get("ocean")
	var swell := float(ocean.get("swell")) if bool(ocean.call("is_moving")) else CALM_BOB
	var waves: RefCounted = ocean.get("waves")
	var here := _player.global_position
	for ship: SeaShip in ships:
		var before: Transform3D = ship.global_transform
		var yaw_before := float(ship.state["yaw"])
		var riding := ship == helm_ship or rules.aboard(String(ship.state["ship"]), before.affine_inverse() * here)
		if ship == helm_ship:
			_steer(ship, delta)
		var was := Vector2(float(ship.state["x"]), float(ship.state["z"]))
		var moved := rules.step(ship.state, wind, wind_dir, _speed_pct(ship), delta)
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
	if helm_ship != null:
		panel.show_ship(helm_ship.state, helm_ship.spec, rules, wind, wind_dir)


func _steer(ship: SeaShip, delta: float) -> void:
	var held := Input.get_axis("move_left", "move_right") if bool(_player.get("controls_enabled")) else 0.0
	if not is_nan(dev_rudder):
		held = dev_rudder
	ship.state["rudder"] = move_toward(float(ship.state["rudder"]), held, delta * (1.6 if held != 0.0 else 2.4))
	if not bool(_player.get("controls_enabled")):
		return
	if Input.is_action_just_pressed("move_forward"):
		rules.step_stage(ship.state, true)
	elif Input.is_action_just_pressed("move_back"):
		rules.step_stage(ship.state, false)
	elif Input.is_action_just_pressed("jump"):
		let_go()


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
	var skills: Variant = _sea.get("skills")
	if ship != helm_ship or skills == null:
		return 0.0
	return float((skills as Node).call("perk", "sailing", "ship_speed"))


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
			take_helm(ship)
		return true
	if _near_spot(ship, ship.spec["anchor"], ANCHOR_REACH):
		toggle_anchor(ship)
		return true
	return false


func take_helm(ship: SeaShip) -> void:
	helm_ship = ship
	_player.set("at_helm", true)
	_player.call("look_at_point", ship.deck_spot([0.0, float(ship.spec["outline"].back()[0])], 1.6))  # face the bow
	_xp_metres = 0.0
	panel.visible = true


func let_go() -> void:
	if helm_ship != null:
		helm_ship.state["rudder"] = 0.0
	helm_ship = null
	_player.set("at_helm", false)
	panel.visible = false


func toggle_anchor(ship: SeaShip) -> void:
	ship.state["anchored"] = not bool(ship.state["anchored"])
	_sea.emit_signal("notice", "Anchor weighed" if not bool(ship.state["anchored"]) else "Anchor let go")


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
