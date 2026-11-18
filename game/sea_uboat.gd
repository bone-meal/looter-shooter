# Purpose: THE G U-BOAT SIGHTINGS (sea step 8e-4; director: an unknown force with an unclear goal, sometimes helping,
# sometimes hurting, NEVER blocking the way, NEVER in direct contact: only glances from a distance, always out of
# reach; LOCKED "sightings with deeds"). Rarely the HOST shows one player at sea a SIGHTING far off (spawn_m): a
# PERISCOPE cutting the water, or the boat SURFACED at the horizon under its checkerboard G flag. Close in to dive_m
# and it dives and is gone; otherwise it slips under after a while. Each sighting may carry one DEED: torpedo a foe
# ship that is fighting the player (help), leave a marked crate afloat ahead of him (help), pin a secret on every
# player's chart (help: the nearest unfound salvage spot), or send a torpedo at his own ship that holes her LIGHTLY
# (hurt: never below keep_hull of her hull). It has no collision: nothing can touch it or be stopped by it.
# Online: the host sends the boat and its torpedoes (game/net_sea.gd _uboat_down, 10 Hz) and the deeds' notices /
# chart pins as events (tell_uboat_event); torpedo damage is the host's (the fleet's hull state goes out as always).
# Dependencies: assets/models/sea/uboat.gltf (tools/blender/sea_uboat.py), data/sea/encounters.json "uboat", the fleet
# (ships, hull_part, rules, _net), the foes node (foes, players, flotsam, rules), the sea world (world_of, local_of,
# water_height, map, salvage, chart, notice), game/fx_kit.gd.
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")
const MODEL := "res://assets/models/sea/uboat.gltf"

var cfg: Dictionary
var paused := false  # dev: no rolls of its own
var sightings := 0  # dev / checks: sightings, dives on approach, deeds done (by kind), torpedo hits
var dived := 0
var deeds := {}
var torpedo_hits := 0
var last := ""
var sub := {}  # {"x", "z", "yaw", "mode" (periscope / surface / dive), "t", "deed", "done", "for" (sea x, z of its player), "lift"}
var torps: Array = []  # [{"x", "z", "yaw", "target" ship, "kind" foe / us, "t"}]
var _fleet: Node3D
var _sea: Node3D
var _foes: Node
var _rng := RandomNumberGenerator.new()
var _check := 0.0
var _last_seen := -1e9
var _model: Node3D
var _wake: CPUParticles3D
var _torp_nodes: Array = []
static var _flag_tex: ImageTexture


func setup(fleet: Node3D, sea: Node3D, foes: Node, encounters: Dictionary) -> void:
	_fleet = fleet
	_sea = sea
	_foes = foes
	cfg = encounters["uboat"]
	_rng.randomize()
	_check = float(cfg["check_s"])


func _host() -> bool:
	var net: Node = _fleet.call("_net")
	return net == null or not bool(net.call("is_client"))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# The checkerboard flag with the letter G (its meaning is the story's: an unknown force).
static func flag_texture() -> ImageTexture:
	if _flag_tex != null:
		return _flag_tex
	var w := 96
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dark := (int(x / 12.0) + int(y / 12.0)) % 2 == 0
			img.set_pixel(x, y, Color(0.08, 0.08, 0.09) if dark else Color(0.92, 0.9, 0.84))
	var c := Vector2(48, 32)  # a G in a gold disc in the middle
	for y in h:
		for x in w:
			var p := Vector2(x, y) - c
			var r := p.length()
			if r < 20.0:
				img.set_pixel(x, y, Color(0.85, 0.66, 0.2))
			var ang := atan2(p.y, p.x)
			var ring := r > 9.0 and r < 14.5 and not (ang > -0.75 and ang < 0.15)
			var bar := p.y > -1.5 and p.y < 3.0 and p.x > 1.0 and p.x < 14.5
			var stem := p.x > 10.0 and p.x < 14.5 and p.y > 0.0 and p.y < 9.0
			if ring or bar or stem:
				img.set_pixel(x, y, Color(0.08, 0.08, 0.09))
	_flag_tex = ImageTexture.create_from_image(img)
	return _flag_tex


# --- every frame ---

func _process(delta: float) -> void:
	if _fleet == null or not bool(_sea.call("running")) or delta <= 0.0:
		return
	if _host():
		_host_step(delta)
	_draw(delta)


func _host_step(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = float(cfg["check_s"])
		if not paused and sub.is_empty() and _now() - _last_seen > float(cfg["min_gap_s"]) and _rng.randf() < float(cfg["chance"]):
			sight("", "")
	_torps_step(delta)
	if sub.is_empty():
		return
	sub["t"] = float(sub["t"]) + delta
	var mode := String(sub["mode"])
	var way := Vector2(-sin(float(sub["yaw"])), -cos(float(sub["yaw"])))
	sub["x"] = float(sub["x"]) + way.x * float(cfg["speed"]) * delta
	sub["z"] = float(sub["z"]) + way.y * float(cfg["speed"]) * delta
	if mode == "dive":
		if float(sub["t"]) >= float(cfg["dive_s"]):
			sub = {}
		return
	var here := Vector2(float(sub["x"]), float(sub["z"]))
	for who: Dictionary in _foes.call("players"):  # close in and it is gone
		if (who["at"] as Vector2).distance_to(here) < float(cfg["dive_m"]):
			dived += 1
			_dive("approach")
			return
	if not bool(sub["done"]) and float(sub["t"]) >= float(cfg["deed_at_s"]):
		sub["done"] = true
		_deed(String(sub["deed"]))
	if float(sub["t"]) >= float(sub["stay"]):
		_dive("time")


# Host / dev: a sighting for a player at sea (empty `how` / `deed` = rolled).
func sight(how: String, deed: String) -> void:
	var list: Array = _foes.call("players")
	if list.is_empty():
		return
	var who: Dictionary = list[_rng.randi() % list.size()]
	var at: Vector2 = who["at"]
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(float(cfg["spawn_m"][0]), float(cfg["spawn_m"][1]))
	if how == "":
		how = "surface" if _rng.randf() < float(cfg["surface_share"]) else "periscope"
	if deed == "":
		deed = _pick_deed(at)
	var stay: Array = cfg["surface_s"] if how == "surface" else cfg["periscope_s"]
	sub = {"x": at.x + cos(a) * d, "z": at.y + sin(a) * d, "yaw": a + PI * 0.5 + _rng.randf_range(-0.4, 0.4), "mode": how, "t": 0.0, "deed": deed, "done": false,
		"for": at, "stay": _rng.randf_range(float(stay[0]), float(stay[1]))}
	sightings += 1
	_last_seen = _now()
	last = "%s %.0f m off, deed %s" % [how, d, deed]
	_event(how)


func _pick_deed(at: Vector2) -> String:
	var weights: Dictionary = (cfg["deeds"] as Dictionary).duplicate()
	if _foe_near(at) == null:
		weights.erase("torpedo_foe")  # (it only helps against a foe that is there)
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	var left := _rng.randf() * total
	for k: String in weights:
		left -= float(weights[k])
		if left < 0.0:
			return k
	return "none"


func _foe_near(at: Vector2) -> Node3D:
	for ship: Node3D in _foes.call("foes"):
		var st: Dictionary = ship.get("state")
		if Vector2(float(st["x"]), float(st["z"])).distance_to(at) < float(cfg["help_m"]) and not bool(st.get("sinking", false)):
			return ship
	return null


func _player_ship(at: Vector2) -> Node3D:
	for who: Dictionary in _foes.call("players"):
		if (who["at"] as Vector2).distance_to(at) < 60.0 and who["ship"] != null:
			return who["ship"]
	return null


func _dive(why: String) -> void:
	sub["mode"] = "dive"
	sub["t"] = 0.0
	last = "dived (%s)" % why
	_event("dive")


# --- deeds ---

func _deed(deed: String) -> void:
	var at: Vector2 = sub["for"]
	match deed:
		"torpedo_foe":
			var foe := _foe_near(at)
			if foe != null:
				_fire(foe, "foe")
		"torpedo_us":
			var mine := _player_ship(at)
			if mine != null:
				_fire(mine, "us")
		"crate":
			var mine2 := _player_ship(at)
			var spot := at
			if mine2 != null:
				var st: Dictionary = mine2.get("state")
				spot = Vector2(float(st["x"]), float(st["z"])) + Vector2(-sin(float(st["yaw"])), -cos(float(st["yaw"]))) * float(cfg["crate_ahead_m"])
			var region := String((_sea.get("map") as RefCounted).call("region_id_at", spot.x, spot.y))
			(_foes.get("flotsam") as Node).call("spill", spot.x, spot.y, String(cfg["crate_loot"]), region)
			_event("crate")
		"chart":
			_event("chart")
	if deed != "none":
		deeds[deed] = int(deeds.get(deed, 0)) + 1


func _fire(target: Node3D, kind: String) -> void:
	torps.append({"x": float(sub["x"]), "z": float(sub["z"]), "yaw": float(sub["yaw"]), "target": target, "kind": kind, "t": 0.0})
	_event("torpedo_" + kind)


func _torps_step(delta: float) -> void:
	for tp: Dictionary in torps.duplicate():
		var target: Node3D = tp["target"]
		tp["t"] = float(tp["t"]) + delta
		if not is_instance_valid(target) or float(tp["t"]) > float(cfg["torpedo_life_s"]):
			torps.erase(tp)
			continue
		var st: Dictionary = target.get("state")
		var goal := Vector2(float(st["x"]), float(st["z"]))
		var here := Vector2(float(tp["x"]), float(tp["z"]))
		var way := goal - here
		var step := float(cfg["torpedo_speed"]) * delta
		if way.length() <= maxf(step, 3.0):
			_torp_hit(target, String(tp["kind"]))
			torps.erase(tp)
			continue
		here += way.normalized() * step
		tp["x"] = here.x
		tp["z"] = here.y
		tp["yaw"] = atan2(-way.x, -way.y)


func _torp_hit(ship: Node3D, kind: String) -> void:
	torpedo_hits += 1
	var st: Dictionary = ship.get("state")
	var amount := float(cfg["foe_damage"]) if kind == "foe" else minf(float(cfg["us_damage"]), float(st["hull"]) - float(st.get("hull_max", st["hull"])) * float(cfg["keep_hull"]))
	var at: Vector3 = ship.global_transform * Vector3(0.0, 0.0, 0.0)
	FxKit.burst(self, Vector3(at.x, float(_sea.call("water_height", at)), at.z), Color(0.92, 0.97, 1.0), 60, 1.4, 0.45, 12.0, -10.0)
	if amount > 0.0:
		_fleet.get("hull_part").call("damage", ship, Vector3(0.0, 0.0, 0.0), amount)
	_event("hit_" + kind)


# --- events: a notice (and for "chart", a pin) on every machine ---

func _event(kind: String) -> void:
	var net: Node = _fleet.call("_net")
	if net != null:
		net.call("tell_uboat_event", kind)
	event(kind)


func event(kind: String) -> void:
	var notices: Dictionary = cfg["notices"]
	if kind == "chart":
		_pin_secret()
	if notices.has(kind) and bool(_sea.get("inside")):
		_sea.emit_signal("notice", String(notices[kind]))


# The nearest unfound salvage spot, pinned on this player's own chart.
func _pin_secret() -> void:
	var salvage: Node = _sea.get("salvage")
	var chart: RefCounted = _sea.get("chart")
	if salvage == null or chart == null:
		return
	var player: Node3D = get_parent().get("_player")
	var here: Vector3 = _sea.call("local_of", player.global_position)
	var best := Vector2.INF
	var best_d := INF
	for spot: Dictionary in salvage.get("cfg")["spots"]:
		if bool(salvage.call("_taken", spot)):
			continue
		var at := Vector2(float(spot["at"][0]), float(spot["at"][1]))
		var pinned := false
		for pin: Vector2 in chart.get("pins"):
			pinned = pinned or pin.distance_to(at) < 30.0
		var d := at.distance_to(Vector2(here.x, here.z))
		if not pinned and d < best_d:
			best_d = d
			best = at
	if best.is_finite():
		chart.call("toggle_pin", best)


# --- drawing (every machine) ---

func _draw(delta: float) -> void:
	if sub.is_empty():
		if _model != null:
			_model.visible = false
		if _wake != null:
			_wake.emitting = false
	else:
		if _model == null:
			_make_model()
		_model.visible = true
		var pos: Vector3 = _sea.call("world_of", Vector3(float(sub["x"]), 0.0, float(sub["z"])))
		var water := float(_sea.call("water_height", pos))
		var mode := String(sub["mode"])
		var want := -float(cfg["periscope_depth"]) if mode == "periscope" else (float(cfg["surface_lift"]) if mode == "surface" else -14.0)
		var lift := move_toward(float(sub.get("lift", -14.0)), want, delta * (3.0 if mode == "dive" else 2.0))
		sub["lift"] = lift
		_model.global_position = Vector3(pos.x, water + lift, pos.z)
		_model.rotation.y = float(sub["yaw"])  # (the model's bow is -z, like the ships')
		_wake.global_position = Vector3(pos.x, water + 0.1, pos.z) + (_model.global_transform.basis * Vector3(0.3, 0.0, 0.6) if mode == "periscope" else Vector3.ZERO)
		_wake.emitting = mode != "dive"
	while _torp_nodes.size() < torps.size():
		var torp := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 2.6
		cap.radial_segments = 8
		cap.rings = 2
		torp.mesh = cap
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.13, 0.13)
		torp.material_override = mat
		torp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var foam := FxKit.particles(Color(0.95, 0.98, 1.0, 0.9), 30, 1.6, 0.5, 0.6, 15.0, -1.0, false, false)
		torp.add_child(foam)
		add_child(torp)
		_torp_nodes.append(torp)
	for i in _torp_nodes.size():
		var node: MeshInstance3D = _torp_nodes[i]
		node.visible = i < torps.size()
		if i < torps.size():
			var tp: Dictionary = torps[i]
			var at: Vector3 = _sea.call("world_of", Vector3(float(tp["x"]), 0.0, float(tp["z"])))
			node.global_position = Vector3(at.x, float(_sea.call("water_height", at)) - 0.4, at.z)
			node.rotation = Vector3(PI * 0.5, float(tp["yaw"]), 0.0)


func _make_model() -> void:
	if ResourceLoader.exists(MODEL):
		_model = (load(MODEL) as PackedScene).instantiate() as Node3D
	else:
		_model = MeshInstance3D.new()
		(_model as MeshInstance3D).mesh = CapsuleMesh.new()
	add_child(_model)
	var panel := _model.find_child("Flag", true, false) as Node3D
	if panel != null:  # the checkerboard G on its flag
		if panel is MeshInstance3D:  # (the white panel only marks the spot)
			(panel as MeshInstance3D).mesh = null
		var flag := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.7, 1.1)
		quad.center_offset = Vector3(-0.85, 0.0, 0.0)
		flag.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = flag_texture()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		flag.material_override = mat
		flag.rotation.y = PI * 0.5  # (flies aft of the staff: +z)
		panel.add_child(flag)
	_wake = FxKit.particles(Color(0.95, 0.98, 1.0, 0.9), 40, 2.2, 0.8, 1.6, 25.0, -2.0, false, false)  # (not additive: white on bright water)
	add_child(_wake)


# --- online ---

func to_net() -> Array:
	var out: Array = []
	if not sub.is_empty():
		out = [snappedf(float(sub["x"]), 0.1), snappedf(float(sub["z"]), 0.1), snappedf(float(sub["yaw"]), 0.01), String(sub["mode"])]
	var tl: Array = []
	for tp: Dictionary in torps:
		tl.append([snappedf(float(tp["x"]), 0.1), snappedf(float(tp["z"]), 0.1), snappedf(float(tp["yaw"]), 0.01)])
	return [out, tl]


var _sent_empty := true


func should_send() -> bool:
	if not sub.is_empty() or not torps.is_empty():
		_sent_empty = false
		return true
	if not _sent_empty:
		_sent_empty = true
		return true
	return false


func from_net(got: Array) -> void:
	if got.size() < 2:
		return
	var s: Array = got[0]
	if s.size() >= 4 and is_finite(float(s[0])) and is_finite(float(s[1])):
		var mode := String(s[3]).left(12)
		if sub.is_empty():
			sub = {"lift": -14.0}
		sub["x"] = float(s[0])
		sub["z"] = float(s[1])
		sub["yaw"] = float(s[2])
		sub["mode"] = mode
	else:
		sub = {}
	torps.clear()
	for t: Variant in got[1]:
		if t is Array and (t as Array).size() >= 3:
			torps.append({"x": float(t[0]), "z": float(t[1]), "yaw": float(t[2])})


func status() -> String:
	var where := ""
	if not sub.is_empty():
		var nearest := INF
		for who: Dictionary in _foes.call("players"):
			nearest = minf(nearest, (who["at"] as Vector2).distance_to(Vector2(float(sub["x"]), float(sub["z"]))))
		where = "%s %.0f m off" % [String(sub["mode"]), nearest]
	return "uboat [%s], sightings %d, dived on approach %d, deeds %s, torpedoes %d running %d hits, last '%s'" % [where, sightings, dived, str(deeds), torps.size(), torpedo_hits, last]
