# Purpose: MARSH LIGHTS (sea step 13 R2e, plan diary/DESIGN_REGION2.md): region 2's own sea event, only at night or in
# fog. A few will-o'-wisps appear ahead of a player and drift away along a wandering way (legs of a few hundred
# metres), moving on only while someone keeps within follow_m of them, as if leading him; left behind (nobody within
# lose_m for lose_s) they wink out. At the end of their way they settle: cache_chance a floating cache (game/
# sea_flotsam.gd spill, loot cache_loot), else they gather into one light that is a lure: the region's beast (a
# Fogmaw: game/sea_beasts.gd) rises there. The HOST runs them (game/sea_events.gd hands it the event and sends it
# with the others); every machine draws them (glowing balls bobbing round the event's point, one light for all).
# Dependencies: data/sea/events.json marsh_lights, game/sea_events.gd (parent `events`: rules, tell, _nearest, _water,
# _foes, counts), game/sea_flotsam.gd, game/sea_beasts.gd, core/sea/event_rules.gd (region_number).
extends Node

var events: Node  # game/sea_events.gd
var _mat: StandardMaterial3D


func cfg() -> Dictionary:
	return (events.get("rules").get("cfg") as Dictionary)["marsh_lights"]


# Host: a new marsh lights event `ahead_m` before a player at sea point `at` heading `ahead` (unit), its way laid now.
func make(at: Vector2, ahead: Vector2, region: String, rng: RandomNumberGenerator) -> Dictionary:
	var c := cfg()
	var start := at + ahead * float(c["ahead_m"])
	var total := rng.randf_range(float(c["lead_m"][0]), float(c["lead_m"][1]))
	var legs := maxi(int(c["legs"]), 1)
	var path: Array = []
	var dir := ahead
	var p := start
	for i in legs:
		dir = dir.rotated(deg_to_rad(rng.randf_range(-float(c["turn_deg"]), float(c["turn_deg"]))))
		p += dir * total / float(legs)
		path.append([p.x, p.y])
	return {"kind": "marsh_lights", "x": start.x, "z": start.y, "yaw": 0.0, "t": 0.0, "n": rng.randi_range(int(c["count"][0]), int(c["count"][1])),
		"path": path, "leg": 0, "mode": "lead", "lost_t": 0.0, "region": region, "cache": rng.randf() < float(c["cache_chance"]), "led_m": 0.0}


# Host, each frame: lead on while followed, wink out when left, settle at the end.
func host_step(id: int, e: Dictionary, delta: float) -> void:
	var c := cfg()
	var here := Vector2(float(e["x"]), float(e["z"]))
	if String(e["mode"]) != "lead":
		if float(e["t"]) > 4.0:
			(events.get("events") as Dictionary).erase(id)
		return
	var near: Array = events.call("_nearest", here)
	var d := float(near[0])
	if d > float(c["lose_m"]):
		e["lost_t"] = float(e["lost_t"]) + delta
		if float(e["lost_t"]) > float(c["lose_s"]):
			_count("marsh_lost")
			events.call("tell", "marsh_lights_lost", here.x, here.y, "", -1)
			(events.get("events") as Dictionary).erase(id)
		return
	e["lost_t"] = 0.0
	if d > float(c["follow_m"]):
		return  # (they wait for him, bobbing)
	var path: Array = e["path"]
	var leg := int(e["leg"])
	if leg >= path.size():
		_settle(e, here)
		return
	var goal := Vector2(float(path[leg][0]), float(path[leg][1]))
	var to := goal - here
	var step := float(c["speed"]) * delta
	if to.length() <= step:
		e["x"] = goal.x
		e["z"] = goal.y
		e["leg"] = leg + 1
	else:
		e["x"] = here.x + to.normalized().x * step
		e["z"] = here.y + to.normalized().y * step
		e["yaw"] = atan2(-to.x, -to.y)
	e["led_m"] = float(e["led_m"]) + minf(step, to.length())


# The end of their way: a cache, or the lure of a beast.
func _settle(e: Dictionary, here: Vector2) -> void:
	var c := cfg()
	e["t"] = 0.0
	var foes: Node = events.call("_foes")
	if bool(e["cache"]):
		e["mode"] = "cache"
		(foes.get("flotsam") as Node).call("spill", here.x, here.y, String(c["cache_loot"]), String(e["region"]))
		_count("marsh_cache")
		events.call("tell", "marsh_lights_cache", here.x, here.y, "", -1)
	else:
		e["mode"] = "beast"
		var region_n := maxi(int(String(e["region"]).trim_prefix("region_")), 1)
		(foes.get("beasts") as Node).call("spawn", String(c["beast"]), here.x, here.y, region_n)
		_count("marsh_beast")
		events.call("tell", "marsh_lights_beast", here.x, here.y, "", -1)


func _count(key: String) -> void:
	var counts: Dictionary = events.get("counts")
	counts[key] = int(counts.get(key, 0)) + 1


# --- drawing (every machine) ---

func build(root: Node3D, e: Dictionary, out: Dictionary) -> void:
	if _mat == null:
		var col: Array = cfg().get("color", [0.72, 1.0, 0.55])
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = Color(float(col[0]), float(col[1]), float(col[2]))
	var wisps: Array = []
	var ball := SphereMesh.new()
	ball.radius = 0.55
	ball.height = 1.1
	ball.radial_segments = 10
	ball.rings = 5
	for i in clampi(int(e.get("n", 3)), 1, 8):
		var w := MeshInstance3D.new()
		w.mesh = ball
		w.material_override = _mat
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(w)
		wisps.append(w)
	var light := OmniLight3D.new()
	light.light_color = _mat.albedo_color
	light.omni_range = 16.0
	light.light_energy = 1.6
	light.shadow_enabled = false
	root.add_child(light)
	out["wisps"] = wisps
	out["light"] = light


func place(n: Dictionary, e: Dictionary, delta: float, clock: float) -> void:
	var root: Node3D = n["root"]
	var at := Vector2(float(e["x"]), float(e["z"]))
	var goal := Vector3(at.x, float(events.call("_water", at)) + 2.2, at.y)
	root.position = goal if root.position.distance_to(goal) > 30.0 else root.position.lerp(goal, minf(1.0, delta * 3.0))
	var mode := String(e.get("mode", "lead"))
	var wisps: Array = n.get("wisps", [])
	for i in wisps.size():
		var w: MeshInstance3D = wisps[i]
		var k := float(i)
		var spread := 0.4 if mode == "beast" else (1.0 if mode == "lead" else 0.0)
		w.position = Vector3(sin(clock * 0.7 + k * 2.1) * 4.0 * spread, sin(clock * 1.3 + k) * 0.8 + 0.4, cos(clock * 0.6 + k * 1.7) * 4.0 * spread)
		w.visible = mode != "cache"
		w.scale = Vector3.ONE * (0.8 + 0.25 * sin(clock * 3.0 + k * 1.3))
	(n["light"] as OmniLight3D).visible = mode == "lead" or mode == "beast"
