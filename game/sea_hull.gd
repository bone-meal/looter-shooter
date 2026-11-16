# Purpose: ships' hulls in the world (sea step 5d, LOCKED "hull bar + 3 leak zones", "sunk = back to port, repairs
# cost materials"): the host (or a lone player) steps every ship's hull rules (core/sea/hull_rules.gd: flooding,
# pumps, sinking), turns running aground hard into hull damage, sinks a foundered ship (she goes down over a few
# seconds, the crew ends up swimming) and refloats her at the shipyard needing planks before she may weigh anchor.
# On every machine it shows the leaks (water spouting up through the deck at a holed zone) and the sinking, and lets
# a player patch a hole or mend the hull with a plank from the shared fantasy bag (hold interact at a leak zone;
# online the host decides the patch, the plank comes from the player's own bag = his claim).
# Dependencies: core/sea/hull_rules.gd, data/sea/hull.json, used by
# game/sea_ships.gd (fleet, shipyard lanes), game/net_sea.gd (repair intent), game/sea_world.gd (notice, skills).
extends Node

const HullRules = preload("res://core/sea/hull_rules.gd")

var hull: HullRules
var _fleet: Node  # game/sea_ships.gd
var _sea: Node3D
var _player: CharacterBody3D
var _spouts := {}  # ship -> Array of 3 MeshInstance3D
var _patching := {}  # {"ship", "zone", "left"} while this player holds interact at a leak
var patch_shown := 0.0  # 0..1 progress of the current patch (prompt)


func setup(fleet: Node, sea: Node3D, player: CharacterBody3D) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	hull = HullRules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/hull.json")))


# A ship joined the fleet: hull keys in her state and her three spouts.
func prepare(ship: Node3D) -> void:
	var state: Dictionary = ship.get("state")
	hull.fill(state)
	state["hull_max"] = hull.max_hull(String(state["ship"]))
	var list: Array = []
	for i in 3:
		var spout := MeshInstance3D.new()
		var tube := CylinderMesh.new()
		tube.top_radius = 0.12
		tube.bottom_radius = 0.32
		tube.height = 1.0
		tube.radial_segments = 8
		tube.rings = 1
		spout.mesh = tube
		spout.material_override = _foam()
		spout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spout.visible = false
		ship.add_child(spout)
		list.append(spout)
	_spouts[ship] = list


# Host / alone: one step of a ship's hull. Returns true when she founders now (the fleet then sinks her).
func step(ship: Node3D, delta: float) -> bool:
	var state: Dictionary = ship.get("state")
	if bool(state.get("sinking", false)):
		return false
	return hull.step(state, delta)


# The fleet's speed bonus for a ship turned into one that also carries the water in her hold.
func speed_pct(ship: Node3D, pct: float) -> float:
	return (1.0 + pct) * hull.speed_mult(ship.get("state")) - 1.0


# Host / alone: she ran aground at this speed (m/s): the bow (or the stern going astern) takes the blow.
func aground(ship: Node3D, speed: float) -> void:
	var amount := hull.aground_damage(speed)
	if amount <= 0.0:
		return
	var spec: Dictionary = ship.get("spec")
	var outline: Array = spec["outline"]
	var end_z := float(outline.back()[0]) if speed >= 0.0 else float(outline[0][0])
	damage(ship, Vector3(0.0, 0.0, end_z), amount)


# Host / alone: a blow at a ship-space point (aground, later cannonballs and enemies). Tells the crew of a new hole.
func damage(ship: Node3D, local: Vector3, amount: float) -> void:
	var state: Dictionary = ship.get("state")
	if bool(state.get("sinking", false)):
		return
	var before: Array = (state["leaks"] as Array).duplicate()
	var zone := hull.hit(state, ship.get("spec"), local.x, local.z, amount)
	if zone >= 0 and float(before[zone]) <= 0.0 and _fleet.call("ship_aboard") == ship:
		_sea.emit_signal("notice", "Holed at the %s! Patch it with a plank" % ["bow", "waist", "stern"][zone])


# Every machine, every frame: spouts at the holes, the hold's water and the sinking in her pose.
func display(ship: Node3D, delta: float) -> void:
	var state: Dictionary = ship.get("state")
	var spec: Dictionary = ship.get("spec")
	var zones := HullRules.zones(spec)
	var list: Array = _spouts.get(ship, [])
	for i in list.size():
		var spout := list[i] as MeshInstance3D
		var hole := float((state["leaks"] as Array)[i])
		spout.visible = hole > 0.0 and not bool(state.get("sinking", false))
		if spout.visible:
			var high := 0.7 + 1.6 * hole
			var deck := float(_fleet.get("rules").call("deck_height", String(state["ship"]), float(zones[i][1])))
			var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.013 + i * 2.0)
			spout.scale = Vector3((0.7 + hole) * pulse, high, (0.7 + hole) * pulse)
			spout.position = Vector3(float(zones[i][0]) * 0.8, deck + high * 0.5 + sin(Time.get_ticks_msec() * 0.02 + i) * 0.05, float(zones[i][1]))
	var sink_t := float(state.get("sink_t", 0.0))
	if bool(state.get("sinking", false)):
		state["sink_t"] = sink_t + delta
	ship.set("lower", hull.sit_lower(state, spec) + (pow(sink_t / float(hull.cfg["sink_seconds"]), 2.0) * (float(spec["deck"]) + float(spec["draft"]) + 6.0) if bool(state.get("sinking", false)) else 0.0))
	ship.set("list_deg", 14.0 * clampf(sink_t / float(hull.cfg["sink_seconds"]), 0.0, 1.0) if bool(state.get("sinking", false)) else 6.0 * float(state["water"]))


# Host / alone: she foundered. Goes down; the helmsman lets go; after sink_seconds she is back at the shipyard.
func sink(ship: Node3D) -> void:
	var state: Dictionary = ship.get("state")
	state["sinking"] = true
	state["sink_t"] = 0.0
	state["speed"] = 0.0
	state["anchored"] = true
	var aboard: bool = _fleet.call("ship_aboard") == ship or _fleet.get("helm_ship") == ship
	if _fleet.get("helm_ship") == ship:
		_fleet.call("let_go")
	_fleet.call("free_helm", ship)
	if aboard:
		_sea.emit_signal("notice", "The %s is going down! Swim for it" % String(ship.get("spec")["name"]))


# Host / alone: the sinking is over: refloated at the first free shipyard lane, little hull, mend before sailing.
func sunk_done(ship: Node3D) -> bool:
	var state: Dictionary = ship.get("state")
	if not bool(state.get("sinking", false)) or float(state.get("sink_t", 0.0)) < float(hull.cfg["sink_seconds"]):
		return false
	state["sinking"] = false
	state["sink_t"] = 0.0
	hull.refloat(state)
	var spot: Vector3 = _fleet.call("free_lane", String(state["ship"]), ship)
	state["x"] = spot.x
	state["z"] = spot.y
	state["yaw"] = deg_to_rad(spot.z)
	state["anchored"] = true
	_sea.emit_signal("notice", "The %s was raised at the shipyard: mend her hull with planks before she sails" % String(ship.get("spec")["name"]))
	return true


static var _foam_mat: StandardMaterial3D


# The spout's look: white foamy water that reads against the sea behind it (the river material vanished there).
static func _foam() -> StandardMaterial3D:
	if _foam_mat == null:
		_foam_mat = StandardMaterial3D.new()
		_foam_mat.albedo_color = Color(0.9, 0.97, 1.0, 0.85)
		_foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_foam_mat.emission_enabled = true
		_foam_mat.emission = Color(0.35, 0.42, 0.45)
		_foam_mat.roughness = 0.3
	return _foam_mat


# --- patching (the interact key) ---

func _plank() -> String:
	var skills: Variant = _sea.get("skills")
	if skills == null:
		return ""
	var bag: Object = (skills as Node).get("bag")
	for id: String in hull.cfg["planks"]:
		if int(bag.call("count", id)) > 0:
			return id
	return ""


# The leak zone a ship-space point stands at (-1 = none).
func zone_at(ship: Node3D, local: Vector3) -> int:
	var zones := HullRules.zones(ship.get("spec"))
	for i in zones.size():
		if Vector2(local.x - float(zones[i][0]) * 0.8, local.z - float(zones[i][1])).length() <= float(hull.cfg["patch_reach"]):
			return i
	return -1


# What this player could do here with a plank: [zone, "patch" | "mend"] or [] (nothing).
func _job(ship: Node3D) -> Array:
	var state: Dictionary = ship.get("state")
	if bool(state.get("sinking", false)):
		return []
	var zone := zone_at(ship, ship.global_transform.affine_inverse() * _player.global_position)
	if zone < 0:
		return []
	if float((state["leaks"] as Array)[zone]) > 0.0:
		return [zone, "patch"]
	if hull.holes(state) <= 0.0 and float(state["hull"]) < hull.max_hull(String(state["ship"])):
		return [zone, "mend"]
	return []


func prompt(key: String) -> String:
	var ship: Node3D = _fleet.call("ship_aboard")
	if ship == null:
		return ""
	var job := _job(ship)
	if job.is_empty():
		return ""
	var state: Dictionary = ship.get("state")
	var pct := roundi(float(state["hull"]) / hull.max_hull(String(state["ship"])) * 100.0)
	if not _patching.is_empty():
		return "%s ... %d%%" % ["Patching the leak" if job[1] == "patch" else "Mending the hull", roundi(patch_shown * 100.0)]
	if _plank() == "":
		return "%s: you need a plank (Carpentry)  -  hull %d%%" % ["A leak!" if job[1] == "patch" else "Hull damaged", pct]
	return "[hold %s] %s with a plank  -  hull %d%%" % [key, "Patch the leak" if job[1] == "patch" else "Mend the hull", pct]


# Called every frame by the fleet: holding interact at a job works it; done = one plank used.
func work(delta: float, holding: bool) -> void:
	var ship: Node3D = _fleet.call("ship_aboard")
	var job := _job(ship) if ship != null else []
	if job.is_empty() or not holding or _plank() == "":
		_patching = {}
		patch_shown = 0.0
		return
	if _patching.is_empty() or _patching["ship"] != ship or int(_patching["zone"]) != int(job[0]):
		_patching = {"ship": ship, "zone": int(job[0]), "left": float(hull.cfg["patch_seconds"])}
	_patching["left"] = float(_patching["left"]) - delta
	patch_shown = 1.0 - float(_patching["left"]) / float(hull.cfg["patch_seconds"])
	if float(_patching["left"]) > 0.0:
		return
	var plank := _plank()
	(_sea.get("skills") as Node).get("bag").call("remove", plank, 1)
	_patching = {}
	patch_shown = 0.0
	var net: Node = _fleet.call("_net")
	if net != null and bool(net.call("is_client")):
		net.call("request_plank", (_fleet.get("ships") as Array).find(ship), int(job[0]))
		_sea.emit_signal("notice", "Plank nailed on")
		return
	use_plank(ship, int(job[0]))


# Host / alone: a plank used at a zone of a ship.
func use_plank(ship: Node3D, zone: int) -> String:
	var did := hull.use_plank(ship.get("state"), zone)
	if did != "" and _fleet.call("ship_aboard") == ship:
		var state: Dictionary = ship.get("state")
		_sea.emit_signal("notice", "%s  -  hull %d%%" % ["Leak patched" if did == "patched" else "Hull mended", roundi(float(state["hull"]) / hull.max_hull(String(state["ship"])) * 100.0)])
	return did
