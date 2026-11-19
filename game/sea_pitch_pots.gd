# Purpose: region 2's PITCH POTS (sea step 13 R2g, plan diary/DESIGN_REGION2.md): clay pots catching Mangrove Pitch
# under spouts in mangrove roots on the islands (data/sea/pitch_pots.json). [F] at a full pot gives a little pitch (for
# the Marsh Beacon offering and Gloomscale Sheathing); it fills again after regrow_s. Each player taps his own pots on
# his own machine (nothing sent, nothing saved). Pots are built when a player first comes within show_m and stand on
# the island's ground found by a ray (the island is solid only near players).
# Dependencies: data/sea/pitch_pots.json, assets/models/sea/pitch_pot.gltf (tools/blender/sea_pitch_pot.py),
# game/fantasy_models.gd (dress); the sea world (skills: give, bag item_name; world_of, local_of, notice).
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")
const MODEL := "res://assets/models/sea/pitch_pot.gltf"

var cfg: Dictionary
var tapped := 0  # dev / checks
var _sea: Node3D
var _player: CharacterBody3D
var _pots := {}  # id -> {"node": Node3D, "y": float, "found": bool, "full_at": seconds when full again}
var _rng := RandomNumberGenerator.new()


func setup(sea_world: Node3D, player: CharacterBody3D) -> void:
	_sea = sea_world
	_player = player
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/pitch_pots.json"))
	_rng.randomize()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	if _sea == null or not bool(_sea.call("running")):
		return
	var me: Vector3 = _sea.call("local_of", _player.global_position)
	for p: Dictionary in cfg["pots"]:
		var id := String(p["id"])
		var at := Vector2(float(p["at"][0]), float(p["at"][1]))
		var near := at.distance_to(Vector2(me.x, me.z)) < float(cfg["show_m"])
		var pot: Dictionary = _pots.get(id, {})
		if pot.is_empty():
			if not near:
				continue
			pot = {"node": _make(float(p.get("yaw", 0.0))), "y": 0.0, "found": false, "full_at": 0.0, "ray_t": 0.0}
			_pots[id] = pot
		var node: Node3D = pot["node"]
		node.visible = near and bool(pot["found"])
		if not near:
			continue
		pot["ray_t"] = float(pot["ray_t"]) - delta
		if float(pot["ray_t"]) <= 0.0:  # the ground under it, again each second: the island turns solid in full detail only near players
			pot["ray_t"] = 1.0
			var top: Vector3 = _sea.call("world_of", Vector3(at.x, 40.0, at.y))
			var ray := PhysicsRayQueryParameters3D.create(top, top + Vector3(0.0, -80.0, 0.0))
			ray.collision_mask = 1
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty():
				pot["y"] = (_sea.call("local_of", hit["position"]) as Vector3).y
				pot["found"] = true
		node.global_position = _sea.call("world_of", Vector3(at.x, float(pot["y"]), at.y))
		var pitch := node.find_child("Pitch", true, false) as Node3D
		if pitch != null:
			pitch.visible = _now() >= float(pot["full_at"])


func _make(yaw_deg: float) -> Node3D:
	var made: Node3D
	if ResourceLoader.exists(MODEL):
		made = (load(MODEL) as PackedScene).instantiate() as Node3D
		for found in made.find_children("*", "MeshInstance3D", true, false):
			FantasyModels.dress((found as MeshInstance3D).mesh)
	else:
		made = MeshInstance3D.new()
		(made as MeshInstance3D).mesh = CylinderMesh.new()
	made.rotation.y = deg_to_rad(yaw_deg)
	made.visible = false
	add_child(made)
	return made


# The pot this player stands at ("" = none).
func pot_near() -> String:
	for id: String in _pots:
		var pot: Dictionary = _pots[id]
		var node: Node3D = pot["node"]
		if node.visible and node.global_position.distance_to(_player.global_position) <= float(cfg["reach_m"]):
			return id
	return ""


func prompt(key: String) -> String:
	var id := pot_near()
	if id == "":
		return ""
	var left := float(_pots[id]["full_at"]) - _now()
	if left > 0.0:
		return "The pitch pot is dry (full again in %d min)" % ceili(left / 60.0)
	return "[%s] Tap the pitch pot" % key


func interact() -> bool:
	var id := pot_near()
	if id == "":
		return false
	var pot: Dictionary = _pots[id]
	if _now() < float(pot["full_at"]):
		_sea.emit_signal("notice", "The pot is dry. The roots will fill it again")
		return true
	var skills: Variant = _sea.get("skills")
	if skills == null:
		return true
	var n := _rng.randi_range(int(cfg["give"][0]), int(cfg["give"][1]))
	(skills as Node).call("give", String(cfg["item"]), n)
	pot["full_at"] = _now() + float(cfg["regrow_s"])
	tapped += 1
	_sea.emit_signal("notice", "+%d %s" % [n, String(((skills as Node).get("bag") as RefCounted).call("item_name", String(cfg["item"])))])
	return true


func status() -> String:
	var shown: PackedStringArray = []
	for id: String in _pots:
		var pot: Dictionary = _pots[id]
		shown.append("%s%s y %.1f%s" % [id, "" if (pot["node"] as Node3D).visible else " (hidden)", float(pot["y"]), " dry" if _now() < float(pot["full_at"]) else ""])
	return "pitch pots: %s; tapped %d; near '%s'" % [", ".join(shown), tapped, pot_near()]
