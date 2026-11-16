# Purpose: the ship's salvage crane (sea step 5e, LOCKED: "a crane on the ship (must be BOUGHT as an upgrade); until
# then diving"). A ship whose state has "crane" carries the davit (assets/models/sea/crane.gltf, tools/blender/
# sea_crane.py) at her stern quarter (data/sea/ships.json "crane" or the rule below). Fitted at the shipyard: the
# Carpentry station's build_crane makes item ship_crane (game/fantasy_world.gd ship_part_made) and the fleet fits it
# to the ship nearest the slipway without one (the host decides online). Used from her deck: stand at the post, the
# ship nearly still and a salvage spot not yet taken under the jib's reach: interact lowers a hook on a rope into
# the sea and hauls the find up after a few seconds (game/sea_salvage.gd take: logbook as by diving, no Agility xp).
# Finds are each player's own (his logbook), so working the crane needs no host.
# Dependencies: data/sea/crane.json, game/sea_salvage.gd (through the sea world), the fleet (game/sea_ships.gd).
extends Node3D

const MODEL := "res://assets/models/sea/crane.gltf"
const GRAPNEL := "res://assets/models/sea/grapnel.gltf"
const TIP := Vector3(2.13, 3.69, 0.0)  # tools/blender/sea_crane.py TIP (the jib reaches along +x)

var cfg: Dictionary
var dev_use := false  # dev: interact without the key
var hauled := 0  # dev / checks: finds this player brought up with a crane
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _cranes := {}  # SeaShip -> {"holder": Node3D, "side": 1 / -1, "spot": [x, z]}
var _work := {}  # this player's haul: {"ship", "spot": salvage spot, "t", "rope", "hook"}
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
		_cranes[ship] = {"holder": holder, "side": side, "spot": spot}
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
	return true


func _process(delta: float) -> void:
	if dev_use:
		dev_use = false
		interact()
	if _work.is_empty():
		return
	var ship: Node3D = _work["ship"]
	if not is_instance_valid(ship) or not _cranes.has(ship) or _fleet.call("ship_aboard") != ship or absf(float(ship.get("state")["speed"])) > float(cfg["max_speed"]) * 2.0:
		_sea.emit_signal("notice", "The crane's line came up empty")
		_stop()
		return
	_work["t"] = float(_work["t"]) + delta
	var k := float(_work["t"]) / float(cfg["seconds"])
	var tip := tip_of(ship)
	var target: Vector3 = (_work["spot"]["node"] as Node3D).global_position
	var low := Vector3(lerpf(tip.x, target.x, 0.6), target.y, lerpf(tip.z, target.z, 0.6))  # the hook goes down to the find and back
	var down := sin(clampf(k, 0.0, 1.0) * PI)
	var hook_at := tip.lerp(low, down)
	(_work["hook"] as Node3D).global_position = hook_at
	_stretch(_work["rope"] as MeshInstance3D, tip, hook_at + Vector3(0, 0.47, 0))
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
