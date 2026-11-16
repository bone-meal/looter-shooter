# Purpose: boarding between ships (sea step 5d; director chose "1 and 3": GRAPPLING HOOKS and a BOARDING PLANK).
# HOOKS: a player at his ship's rail throws a grapnel (assets/models/sea/grapnel.gltf) at another ship within reach;
# the line lashes them: the other ship is hauled in until she lies parallel a little off our rail and both are held
# still until somebody cuts the line at either end. PLANK: when two ships lie close and slow (lashed or not), a player
# at the rail lays a gangway (assets/models/sea/boarding_plank.gltf stretched): a ramp up from each deck to the rail
# tops and a bridge between, solid to walk on; taken up at either end, or it falls when the ships part or get under
# way. Rails come from the ship outline (core/sea/ship_rules.gd half_width, deck_height) + the bulwark.
# The host (or a lone player) decides: clients ask (game/net_sea.gd request_board) and get the lines and planks in
# the fleet's states (to_net / from_net); every machine draws them and the plank is solid everywhere.
# Dependencies: data/sea/boarding.json, the fleet (game/sea_ships.gd: ships, rules, ship_aboard, _net), the player.
extends Node3D

const GRAPNEL := "res://assets/models/sea/grapnel.gltf"
const PLANK := "res://assets/models/sea/boarding_plank.gltf"

var cfg: Dictionary
var lashes: Array = []  # {"a": thrower's ship, "b": hauled ship, "pa", "pb": Vector2 rail points (ship-local x, z), "age", "rope", "hook"}
var planks: Array = []  # {"a", "b", "pa", "pb", "body": AnimatableBody3D with 3 shapes, "parts": 3 models}
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _rope_mat: StandardMaterial3D


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/boarding.json"))
	_rope_mat = StandardMaterial3D.new()
	_rope_mat.albedo_color = Color(0.62, 0.52, 0.36)
	_rope_mat.roughness = 0.95


# --- rails ---

func _rules() -> RefCounted:
	return _fleet.get("rules")


# The rail nearest a ship-local point: (x on the side, z along her), clamped to her length.
func rail_point(ship: Node3D, local: Vector3) -> Vector2:
	var id := String(ship.get("state")["ship"])
	var outline: Array = ship.get("spec")["outline"]
	var z := clampf(local.z, float(outline.back()[0]) * 0.8, float(outline[0][0]) * 0.8)
	var hw := float(_rules().call("half_width", id, z))
	return Vector2(hw * (1.0 if local.x >= 0.0 else -1.0), z)


# A rail point's top in the scene (deck + bulwark), up = extra height.
func rail_world(ship: Node3D, p: Vector2, up: float = 0.0) -> Vector3:
	var spec: Dictionary = ship.get("spec")
	var top := float(_rules().call("deck_height", String(ship.get("state")["ship"]), p.y)) + float(spec["bulwark"])
	return ship.global_transform * Vector3(p.x, top + up, p.y)


# The deck spot a ramp of `ramp` m inboard of a rail point starts from.
func ramp_foot(ship: Node3D, p: Vector2) -> Vector3:
	var x := p.x - signf(p.x) * float(cfg["ramp"])
	return ship.global_transform * Vector3(x, float(_rules().call("deck_height", String(ship.get("state")["ship"]), p.y)), p.y)


static func widest(ship: Node3D) -> float:
	var most := 0.0
	for station: Array in ship.get("spec")["outline"]:
		most = maxf(most, float(station[1]))
	return most


# What this player could do from where he stands: {"kind": hook | plank | cut | unplank, "a", "b", "pa", "pb", "text"}.
func _job() -> Dictionary:
	var ship: Node3D = _fleet.call("ship_aboard")
	if ship == null or bool(ship.get("state").get("sinking", false)):
		return {}
	var here := _player.global_position
	for plank: Dictionary in planks:  # at either end of a plank: take it up
		for end: Array in [[plank["a"], plank["pa"]], [plank["b"], plank["pb"]]]:
			if end[0] == ship and ramp_foot(ship, end[1]).distance_to(here) <= 1.6:
				return {"kind": "unplank", "a": plank["a"], "b": plank["b"], "pa": plank["pa"], "pb": plank["pb"], "text": "Take up the boarding plank"}
	for lash: Dictionary in lashes:  # right at either end of a line: cut it (a step along the rail lays a plank)
		for end: Array in [[lash["a"], lash["pa"]], [lash["b"], lash["pb"]]]:
			var foot: Vector3 = ship.global_transform * Vector3((end[1] as Vector2).x, 0.0, (end[1] as Vector2).y)
			if end[0] == ship and Vector2(foot.x - here.x, foot.z - here.z).length() <= float(cfg["cut_reach"]):
				return {"kind": "cut", "a": lash["a"], "b": lash["b"], "pa": lash["pa"], "pb": lash["pb"], "text": "Cut the grappling line"}
	var local: Vector3 = ship.global_transform.affine_inverse() * here
	var mine := rail_point(ship, local)
	if absf(local.x) < absf(mine.x) - float(cfg["rail_reach"]):
		return {}
	var mine_world := rail_world(ship, mine)
	var best: Node3D = null
	var best_d := INF
	var best_p := Vector2.ZERO
	for other: Node3D in _fleet.get("ships"):
		if other == ship or bool(other.get("state").get("sinking", false)):
			continue
		var theirs := rail_point(other, other.global_transform.affine_inverse() * mine_world)
		var d := rail_world(other, theirs).distance_to(mine_world)
		var outward: Vector3 = ship.global_transform.basis * Vector3(signf(mine.x), 0.0, 0.0)
		if d < best_d and outward.dot(rail_world(other, theirs) - mine_world) > 0.0:  # only ships off this side
			best = other
			best_d = d
			best_p = theirs
	if best == null:
		return {}
	var job := {"a": ship, "b": best, "pa": mine, "pb": best_p}
	var name_b := String(best.get("spec")["name"])
	if best_d <= float(cfg["plank_range"]) and _slow(ship) and _slow(best) and _plank_between(ship, best).is_empty():
		job["kind"] = "plank"
		job["text"] = "Lay the boarding plank across to the %s" % name_b
		return job
	if best_d <= float(cfg["hook_range"]) and _lash_between(ship, best).is_empty():
		job["kind"] = "hook"
		job["text"] = "Throw a grappling hook at the %s" % name_b
		return job
	return {}


func _slow(ship: Node3D) -> bool:
	return absf(float(ship.get("state")["speed"])) <= float(cfg["plank_speed"])


func _lash_between(a: Node3D, b: Node3D) -> Dictionary:
	for lash: Dictionary in lashes:
		if (lash["a"] == a and lash["b"] == b) or (lash["a"] == b and lash["b"] == a):
			return lash
	return {}


func _plank_between(a: Node3D, b: Node3D) -> Dictionary:
	for plank: Dictionary in planks:
		if (plank["a"] == a and plank["b"] == b) or (plank["a"] == b and plank["b"] == a):
			return plank
	return {}


func prompt(key: String) -> String:
	var job := _job()
	return "[%s] %s" % [key, String(job["text"])] if not job.is_empty() else ""


# The interact key: true when boarding used it. A client asks the host.
func interact() -> bool:
	var job := _job()
	if job.is_empty():
		return false
	var net: Node = _fleet.call("_net")
	if net != null and bool(net.call("is_client")):
		var ships: Array = _fleet.get("ships")
		net.call("request_board", String(job["kind"]), ships.find(job["a"]), ships.find(job["b"]), job["pa"], job["pb"])
		return true
	apply(String(job["kind"]), job["a"], job["b"], job["pa"], job["pb"])
	return true


# Host / alone: does it (conditions checked again here; game/net_sea.gd checked where the asker stands).
func apply(kind: String, a: Node3D, b: Node3D, pa: Vector2, pb: Vector2) -> bool:
	if a == null or b == null or a == b or not pa.is_finite() or not pb.is_finite():
		return false
	var apart := rail_world(a, pa).distance_to(rail_world(b, pb))
	match kind:
		"hook":
			if not _lash_between(a, b).is_empty() or apart > float(cfg["hook_range"]) + 2.0:
				return false
			lashes.append({"a": a, "b": b, "pa": pa, "pb": pb, "age": 0.0})
			_tell("Grappling hook thrown: hauling the %s in" % String(b.get("spec")["name"]), a, b)
		"cut":
			var lash := _lash_between(a, b)
			if lash.is_empty():
				return false
			_drop_lash(lash)
			_tell("Grappling line cut", a, b)
		"plank":
			if not _plank_between(a, b).is_empty() or apart > float(cfg["plank_range"]) + 1.0 or not _slow(a) or not _slow(b):
				return false
			_add_plank(a, b, pa, pb)
			_tell("Boarding plank laid", a, b)
		"unplank":
			var plank := _plank_between(a, b)
			if plank.is_empty():
				return false
			_drop_plank(plank)
			_tell("Boarding plank taken up", a, b)
		_:
			return false
	return true


func _tell(text: String, a: Node3D, b: Node3D) -> void:
	var aboard: Node3D = _fleet.call("ship_aboard")
	if aboard == a or aboard == b:
		_sea.emit_signal("notice", text)


# --- the host's hold on lashed ships (called by the fleet after a ship's step) ---

func hold(ship: Node3D, delta: float) -> void:
	for lash: Dictionary in lashes:
		if lash["a"] != ship and lash["b"] != ship:
			continue
		var s: Dictionary = ship.get("state")
		s["speed"] = 0.0
		if lash["b"] != ship:
			continue
		var a: Node3D = lash["a"]
		var sa: Dictionary = a.get("state")
		var yaw_a := float(sa["yaw"])
		var star := Vector2(cos(yaw_a), -sin(yaw_a))
		var bow := Vector2(-sin(yaw_a), -cos(yaw_a))
		var at_a := Vector2(float(sa["x"]), float(sa["z"]))
		var at_b := Vector2(float(s["x"]), float(s["z"]))
		var side := signf((at_b - at_a).dot(star))
		var outline: Array = a.get("spec")["outline"]
		var half_len := absf(float(outline[0][0]) - float(outline.back()[0])) * 0.5
		var along := clampf((at_b - at_a).dot(bow), -half_len, half_len)
		var target := at_a + star * side * (widest(a) + widest(ship) + float(cfg["gap"])) + bow * along
		var moved := at_b.move_toward(target, float(cfg["pull_speed"]) * delta)
		s["x"] = moved.x
		s["z"] = moved.y
		var yaw_b := float(s["yaw"])
		var want := yaw_a if absf(wrapf(yaw_a - yaw_b, -PI, PI)) <= PI * 0.5 else yaw_a + PI  # parallel, whichever way she lies
		s["yaw"] = yaw_b + clampf(wrapf(want - yaw_b, -PI, PI), -deg_to_rad(float(cfg["turn_deg_s"])) * delta, deg_to_rad(float(cfg["turn_deg_s"])) * delta)


# Host: lines and planks that can no longer hold (a ship gone down or gone, ships parted, a plank on a moving ship).
func check() -> void:
	for lash: Dictionary in lashes.duplicate():
		if not _alive(lash["a"]) or not _alive(lash["b"]):
			_drop_lash(lash)
	for plank: Dictionary in planks.duplicate():
		if not _alive(plank["a"]) or not _alive(plank["b"]):
			_drop_plank(plank)
			continue
		var apart := rail_world(plank["a"], plank["pa"]).distance_to(rail_world(plank["b"], plank["pb"]))
		var fast := absf(float(plank["a"].get("state")["speed"])) > float(cfg["plank_speed"]) * 2.0 or absf(float(plank["b"].get("state")["speed"])) > float(cfg["plank_speed"]) * 2.0
		if apart > float(cfg["plank_range"]) + 1.0 or fast:
			_drop_plank(plank)
			_tell("The boarding plank fell into the sea", plank["a"], plank["b"])


func _alive(ship: Variant) -> bool:
	return is_instance_valid(ship) and (_fleet.get("ships") as Array).has(ship) and not bool((ship as Node).get("state").get("sinking", false))


# --- drawing (every machine, every frame) ---

func _process(delta: float) -> void:
	if not bool(_sea.call("running")):
		return
	for lash: Dictionary in lashes:
		if not is_instance_valid(lash["a"]) or not is_instance_valid(lash["b"]):
			continue
		lash["age"] = float(lash["age"]) + delta
		if not lash.has("rope"):
			_dress_lash(lash)
		var from := rail_world(lash["a"], lash["pa"], 0.1)
		var to := rail_world(lash["b"], lash["pb"], 0.05)
		var k := clampf(float(lash["age"]) / 0.6, 0.0, 1.0)  # the throw: the grapnel flies over in an arc
		var hook_at := from.lerp(to, k) + Vector3.UP * sin(k * PI) * 2.0
		var hook := lash["hook"] as Node3D
		if hook != null:
			hook.global_position = hook_at
			var out := (to - from).normalized()
			hook.global_transform.basis = Basis.looking_at(Vector3.DOWN if k >= 1.0 else out, out if k >= 1.0 else Vector3.UP)  # landed: hanging over her rail
		_stretch(lash["rope"] as MeshInstance3D, from, hook_at)
	for plank: Dictionary in planks:
		if is_instance_valid(plank["a"]) and is_instance_valid(plank["b"]):
			_lay(plank)


func _dress_lash(lash: Dictionary) -> void:
	var rope := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.022
	tube.bottom_radius = 0.022
	tube.height = 1.0
	tube.radial_segments = 6
	tube.rings = 1
	rope.mesh = tube
	rope.material_override = _rope_mat
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rope)
	lash["rope"] = rope
	lash["hook"] = null
	if ResourceLoader.exists(GRAPNEL):
		var hook := (load(GRAPNEL) as PackedScene).instantiate() as Node3D
		add_child(hook)
		lash["hook"] = hook


# A unit cylinder (along y) stretched between two scene points.
func _stretch(rope: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var span := to - from
	if span.length() < 0.01:
		rope.visible = false
		return
	rope.visible = true
	var up := span.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	rope.global_transform = Transform3D(Basis(side, up * span.length(), side.cross(up)), (from + to) * 0.5)


func _add_plank(a: Node3D, b: Node3D, pa: Vector2, pb: Vector2) -> void:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var parts: Array = []
	for i in 3:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		shape.shape = box
		body.add_child(shape)
		var model: Node3D = (load(PLANK) as PackedScene).instantiate() as Node3D if ResourceLoader.exists(PLANK) else Node3D.new()
		add_child(model)
		parts.append([shape, model])
	var plank := {"a": a, "b": b, "pa": pa, "pb": pb, "body": body, "parts": parts}
	planks.append(plank)
	_lay(plank)


# The gangway between its two ships now: ramp up on A, bridge, ramp down on B.
func _lay(plank: Dictionary) -> void:
	var points := [ramp_foot(plank["a"], plank["pa"]), rail_world(plank["a"], plank["pa"]), rail_world(plank["b"], plank["pb"]), ramp_foot(plank["b"], plank["pb"])]
	var width := float(cfg["plank_width"])
	for i in 3:
		var from: Vector3 = points[i]
		var to: Vector3 = points[i + 1]
		var span := to - from
		var length := maxf(span.length(), 0.05)
		var turn := Basis.looking_at(span / length if span.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		var mid := (from + to) * 0.5
		var shape: CollisionShape3D = plank["parts"][i][0]
		(shape.shape as BoxShape3D).size = Vector3(width, 0.1, length + 0.1)
		shape.global_transform = Transform3D(turn, mid + turn.y * -0.02)
		var model: Node3D = plank["parts"][i][1]
		model.global_transform = Transform3D(turn.scaled_local(Vector3(1.0, 1.0, length + 0.1)), mid)


func _drop_lash(lash: Dictionary) -> void:
	for key: String in ["rope", "hook"]:
		if lash.get(key) != null and is_instance_valid(lash[key]):
			(lash[key] as Node).queue_free()
	lashes.erase(lash)


func _drop_plank(plank: Dictionary) -> void:
	(plank["body"] as Node).queue_free()
	for part: Array in plank["parts"]:
		(part[1] as Node).queue_free()
	planks.erase(plank)


func clear() -> void:
	for lash: Dictionary in lashes.duplicate():
		_drop_lash(lash)
	for plank: Dictionary in planks.duplicate():
		_drop_plank(plank)


# --- online ---

# Host: the lines and planks for the fleet states: [kind (0 line, 1 plank), ship a, ship b, pa.x, pa.y, pb.x, pb.y].
func to_net() -> Array:
	var ships: Array = _fleet.get("ships")
	var out: Array = []
	for list: Array in [lashes, planks]:
		for item: Dictionary in list:
			out.append([0 if list == lashes else 1, ships.find(item["a"]), ships.find(item["b"]), item["pa"].x, item["pa"].y, item["pb"].x, item["pb"].y])
	return out


# Client: the host's lines and planks (kept where they match, so a thrown hook keeps flying).
func from_net(items: Array) -> void:
	var ships: Array = _fleet.get("ships")
	var want_lashes: Array = []
	var want_planks: Array = []
	for got: Variant in items:
		if not got is Array or (got as Array).size() < 7:
			continue
		var ia := int(got[1])
		var ib := int(got[2])
		if ia < 0 or ib < 0 or ia >= ships.size() or ib >= ships.size() or ia == ib:
			continue
		var item := {"a": ships[ia], "b": ships[ib], "pa": Vector2(float(got[3]), float(got[4])), "pb": Vector2(float(got[5]), float(got[6]))}
		if not (item["pa"] as Vector2).is_finite() or not (item["pb"] as Vector2).is_finite():
			continue
		(want_lashes if int(got[0]) == 0 else want_planks).append(item)
	for lash: Dictionary in lashes.duplicate():
		if not want_lashes.any(func(w: Dictionary) -> bool: return w["a"] == lash["a"] and w["b"] == lash["b"]):
			_drop_lash(lash)
	for w: Dictionary in want_lashes:
		if _lash_between(w["a"], w["b"]).is_empty():
			w["age"] = 0.0
			lashes.append(w)
	for plank: Dictionary in planks.duplicate():
		if not want_planks.any(func(w: Dictionary) -> bool: return w["a"] == plank["a"] and w["b"] == plank["b"]):
			_drop_plank(plank)
	for w: Dictionary in want_planks:
		if _plank_between(w["a"], w["b"]).is_empty():
			_add_plank(w["a"], w["b"], w["pa"], w["pb"])


func status() -> String:
	var ships: Array = _fleet.get("ships")
	var parts := PackedStringArray()
	for lash: Dictionary in lashes:
		parts.append("line %d->%d rails %.1f m apart" % [ships.find(lash["a"]), ships.find(lash["b"]), rail_world(lash["a"], lash["pa"]).distance_to(rail_world(lash["b"], lash["pb"]))])
	for plank: Dictionary in planks:
		parts.append("plank %d-%d" % [ships.find(plank["a"]), ships.find(plank["b"])])
	return "boarding: %s; prompt '%s'" % [", ".join(parts) if not parts.is_empty() else "none", prompt("F")]
