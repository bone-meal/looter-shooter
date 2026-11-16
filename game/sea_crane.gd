# Purpose: the ship's salvage crane (sea step 5e, LOCKED: "a crane on the ship (must be BOUGHT as an upgrade); until
# then diving"). A ship whose state has "crane" carries the davit (assets/models/sea/crane.gltf, tools/blender/
# sea_crane.py) at her stern quarter (data/sea/ships.json "crane" or the rule below). Fitted at the shipyard: the
# Carpentry station's build_crane makes item ship_crane (game/fantasy_world.gd ship_part_made) and the fleet fits it
# to the ship nearest the slipway without one (the host decides online). Used from her deck: stand at the post, the
# ship nearly still and a salvage spot not yet taken under the jib's reach: interact lowers a hook on a rope into
# the sea and hauls the find up after a few seconds (game/sea_salvage.gd take: logbook as by diving, no Agility xp).
# Finds are each player's own (his logbook), so working the crane needs no host; the haul is SHOWN on every machine
# (game/net_sea.gd tell_crane: ship + where the hook goes, in sea coordinates): the rope, hook and winch move there too.
# Dependencies: data/sea/crane.json, game/sea_salvage.gd (through the sea world), the fleet (game/sea_ships.gd).
extends Node3D

const MODEL := "res://assets/models/sea/crane.gltf"
const GRAPNEL := "res://assets/models/sea/grapnel.gltf"
const TIP := Vector3(2.13, 3.69, 0.0)  # tools/blender/sea_crane.py TIP (the jib reaches along +x)
const WINCH := Vector3(-0.22, 1.0, 0.0)  # the winch's axle (along z)

var cfg: Dictionary
var dev_use := false  # dev: interact without the key
var hauled := 0  # dev / checks: finds this player brought up with a crane
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _cranes := {}  # SeaShip -> {"holder": Node3D, "side": 1 / -1, "spot": [x, z]}
var _work := {}  # this player's haul: {"ship", "spot": salvage spot, "t", "rope", "hook"}
var _shows: Array = []  # other players' hauls seen here: {"ship", "target": sea position, "t", "rope", "hook"}
var _rope_mat: StandardMaterial3D


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/crane.json"))
	_rope_mat = StandardMaterial3D.new()
	_rope_mat.albedo_color = Color(0.62, 0.52, 0.36)


static func spot_of(spec: Dictionary) -> Array:
	if spec.has("crane"):
		return spec["crane"]
	var outline: Array = spec["outline"]
	var z := float(outline[0][0]) * 0.55
	var hw := 0.0
	for i in range(1, outline.size()):
		if z <= float(outline[i - 1][0]) and z >= float(outline[i][0]):
			hw = lerpf(float(outline[i - 1][1]), float(outline[i][1]), (float(outline[i - 1][0]) - z) / maxf(float(outline[i - 1][0]) - float(outline[i][0]), 0.001))
	return [maxf(hw - 0.45, 0.3), z]


# Every frame for each ship: her crane shown when she has one.
func show_for(ship: Node3D) -> void:
	var has := bool(ship.get("state").get("crane", false))
	if has and not _cranes.has(ship) and ResourceLoader.exists(MODEL):
		var spec: Dictionary = ship.get("spec")
		var spot := spot_of(spec)
		var holder := (load(MODEL) as PackedScene).instantiate() as Node3D
		ship.add_child(holder)
		holder.position = Vector3(float(spot[0]), float(_fleet.get("rules").call("deck_height", String(ship.get("state")["ship"]), float(spot[1]))), float(spot[1]))
		var side := 1.0 if float(spot[0]) >= 0.0 else -1.0
		holder.rotation.y = 0.0 if side > 0.0 else PI  # the jib out over her side
		var winch := holder.find_child("Winch", true, false) as Node3D
		var axle: Node3D = null
		if winch != null:  # turn the winch round its own axle (its node sits at the model's origin)
			axle = Node3D.new()
			holder.add_child(axle)
			axle.position = WINCH
			var keep := winch.global_transform
			winch.get_parent().remove_child(winch)
			axle.add_child(winch)
			winch.global_transform = keep
		_cranes[ship] = {"holder": holder, "side": side, "spot": spot, "axle": axle}
	elif not has and _cranes.has(ship):
		(_cranes[ship]["holder"] as Node).queue_free()
		_cranes.erase(ship)


func forget(ship: Node3D) -> void:
	_cranes.erase(ship)
	if _work.get("ship") == ship:
		_stop()


func tip_of(ship: Node3D) -> Vector3:
	return (_cranes[ship]["holder"] as Node3D).global_transform * TIP


# What the crane could haul from here: the salvage spot, or {} (with why in "why").
func _job() -> Dictionary:
	var ship: Node3D = _fleet.call("ship_aboard")
	if ship == null or not _cranes.has(ship):
		return {}
	var post: Vector3 = (_cranes[ship]["holder"] as Node3D).global_position
	if Vector2(post.x - _player.global_position.x, post.z - _player.global_position.z).length() > float(cfg["use_reach"]):
		return {}
	if absf(float(ship.get("state")["speed"])) > float(cfg["max_speed"]):
		return {"why": "The crane: bring her to a stop first"}
	var spot: Dictionary = _sea.get("salvage").call("spot_within", tip_of(ship), float(cfg["reach"]))
	if spot.is_empty():
		return {"why": "The crane: no salvage under her (look for bubbles)"}
	return {"ship": ship, "spot": spot}


func prompt(key: String) -> String:
	if not _work.is_empty():
		return "Hauling up... %d%%" % roundi(float(_work["t"]) / float(cfg["seconds"]) * 100.0)
	var job := _job()
	if job.is_empty():
		return ""
	if job.has("why"):
		return String(job["why"])
	return "[%s] Lower the crane: %s" % [key, String(_sea.get("salvage").call("spot_name", job["spot"]))]


func interact() -> bool:
	if not _work.is_empty():
		return true
	var job := _job()
	if job.is_empty() or job.has("why"):
		return not job.is_empty()
	var rope := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.02
	tube.bottom_radius = 0.02
	tube.height = 1.0
	tube.radial_segments = 6
	tube.rings = 1
	rope.mesh = tube
	rope.material_override = _rope_mat
	add_child(rope)
	var hook: Node3D = (load(GRAPNEL) as PackedScene).instantiate() as Node3D if ResourceLoader.exists(GRAPNEL) else Node3D.new()
	add_child(hook)
	_work = {"ship": job["ship"], "spot": job["spot"], "t": 0.0, "rope": rope, "hook": hook}
	var net: Node = _fleet.call("_net")
	if net != null:
		net.call("tell_crane", (_fleet.get("ships") as Array).find(job["ship"]), _sea.call("local_of", (job["spot"]["node"] as Node3D).global_position))
	return true


# Another player lowers the crane of a ship (game/net_sea.gd): the same rope and hook here, nothing taken.
func show_haul(ship: Node3D, target_sea: Vector3) -> void:
	if not _cranes.has(ship) or not target_sea.is_finite():
		return
	var rope := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.02
	tube.bottom_radius = 0.02
	tube.height = 1.0
	tube.radial_segments = 6
	tube.rings = 1
	rope.mesh = tube
	rope.material_override = _rope_mat
	add_child(rope)
	var hook: Node3D = (load(GRAPNEL) as PackedScene).instantiate() as Node3D if ResourceLoader.exists(GRAPNEL) else Node3D.new()
	add_child(hook)
	_shows.append({"ship": ship, "target": target_sea, "t": 0.0, "rope": rope, "hook": hook})


# The rope and hook of a haul k (0..1) of the way through: down to the find and back up.
func _draw_haul(ship: Node3D, target: Vector3, k: float, rope: MeshInstance3D, hook: Node3D) -> void:
	var tip := tip_of(ship)
	var low := Vector3(lerpf(tip.x, target.x, 0.6), target.y, lerpf(tip.z, target.z, 0.6))
	var hook_at := tip.lerp(low, sin(clampf(k, 0.0, 1.0) * PI))
	hook.global_position = hook_at
	_stretch(rope, tip, hook_at + Vector3(0, 0.47, 0))
	var axle: Node3D = _cranes[ship].get("axle")
	if axle != null:  # paying out going down, winding in coming up
		axle.rotation.z += (0.12 if k < 0.5 else -0.12)


func _process(delta: float) -> void:
	if dev_use:
		dev_use = false
		interact()
	for seen: Dictionary in _shows.duplicate():
		seen["t"] = float(seen["t"]) + delta
		var k := float(seen["t"]) / float(cfg["seconds"])
		if k >= 1.0 or not is_instance_valid(seen["ship"]) or not _cranes.has(seen["ship"]):
			(seen["rope"] as Node).queue_free()
			(seen["hook"] as Node).queue_free()
			_shows.erase(seen)
			continue
		_draw_haul(seen["ship"], _sea.call("world_of", seen["target"]), k, seen["rope"], seen["hook"])
	if _work.is_empty():
		return
	var ship: Node3D = _work["ship"]
	if not is_instance_valid(ship) or not _cranes.has(ship) or _fleet.call("ship_aboard") != ship or absf(float(ship.get("state")["speed"])) > float(cfg["max_speed"]) * 2.0:
		_sea.emit_signal("notice", "The crane's line came up empty")
		_stop()
		return
	_work["t"] = float(_work["t"]) + delta
	var k := float(_work["t"]) / float(cfg["seconds"])
	_draw_haul(ship, (_work["spot"]["node"] as Node3D).global_position, k, _work["rope"], _work["hook"])
	if k >= 1.0:
		var spot: Dictionary = _work["spot"]
		_stop()
		if bool(_sea.get("salvage").call("take", spot, false)):
			hauled += 1


func _stop() -> void:
	for key: String in ["rope", "hook"]:
		if _work.get(key) != null and is_instance_valid(_work[key]):
			(_work[key] as Node).queue_free()
	_work = {}


func _stretch(rope: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var span := to - from
	if span.length() < 0.01:
		rope.visible = false
		return
	rope.visible = true
	var up := span.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	rope.global_transform = Transform3D(Basis(side, up * span.length(), side.cross(up)), (from + to) * 0.5)


# The shipyard made a crane (host / alone): fitted to the ship nearest the slipway that has none. Returns her name.
func fit(at: Vector3) -> String:
	var best: Node3D = null
	var best_d := float(cfg["fit_range"])
	for ship: Node3D in _fleet.get("ships"):
		var s: Dictionary = ship.get("state")
		var d := Vector2(float(s["x"]) - at.x, float(s["z"]) - at.z).length()
		if not bool(s.get("crane", false)) and d < best_d and not bool(s.get("sinking", false)):
			best = ship
			best_d = d
	if best == null:
		return ""
	best.get("state")["crane"] = true
	return String(best.get("spec")["name"])


func status() -> String:
	return "cranes on %d ships, hauled %d, working %s, prompt '%s'" % [_cranes.size(), hauled, str(not _work.is_empty()), prompt("F")]
