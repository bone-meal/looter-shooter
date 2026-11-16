# Purpose: pure rules of sailing (sea step 5a): Valheim-style wind (how much of the wind's push a heading gets, the
# sail stages stepped through at the helm, oars without wind), speed and turning of a ship, the lean the wind gives
# her, and the helmsman's Sailing-level gate. A ship's state is a plain dictionary in SEA COORDINATES (x, z metres,
# yaw radians with 0 = bow to the north / -z) so the host can run it and send it (sea step 12).
# Dependencies: none (data/sea/ships.json passed in).
extends RefCounted

var cfg: Dictionary  # data/sea/ships.json


func _init(ships_cfg: Dictionary) -> void:
	cfg = ships_cfg


func spec(ship_id: String) -> Dictionary:
	return cfg["ships"][ship_id]


func new_state(ship_id: String, x: float, z: float, yaw_deg: float) -> Dictionary:
	return {"ship": ship_id, "x": x, "z": z, "yaw": deg_to_rad(yaw_deg), "speed": 0.0, "stage": int(cfg["start_stage"]),
		"rudder": 0.0, "anchored": true}


func stage_count() -> int:
	return (cfg["stages"] as Array).size()


func stage(state: Dictionary) -> Dictionary:
	return cfg["stages"][int(state["stage"])]


# W / S at the helm: one stage up (more sail) or down (less, then oars back).
func step_stage(state: Dictionary, up: bool) -> void:
	state["stage"] = clampi(int(state["stage"]) + (1 if up else -1), 0, stage_count() - 1)


func can_steer(ship_id: String, sailing_level: int) -> bool:
	return sailing_level >= int(spec(ship_id)["sailing_level"])


# Degrees between where the bow points and where the wind blows to: 0 = the wind straight from behind, 180 = into it.
static func off_wind(yaw: float, wind_dir: float) -> float:
	var bow := Vector2(-sin(yaw), -cos(yaw))
	return rad_to_deg(absf(bow.angle_to(Vector2.from_angle(wind_dir))))


# The share of the wind's push a sail gets at `off` degrees off the wind (data wind_efficiency, straight lines between).
func wind_share(off: float) -> float:
	var table: Array = cfg["wind_efficiency"]
	off = clampf(absf(off), 0.0, 180.0)
	for i in range(1, table.size()):
		var a: Array = table[i - 1]
		var b: Array = table[i]
		if off <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (off - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
	return float((table.back() as Array)[1])


# Words for the point of sail (for the helm panel).
static func point_of_sail(off: float) -> String:
	if off < 30.0:
		return "Running"
	if off < 75.0:
		return "Broad reach"
	if off < 105.0:
		return "Beam reach"
	if off < 155.0:
		return "Close hauled"
	return "In irons"


# The speed the ship works towards (m/s, negative = backwards). speed_pct: the helmsman's Sailing perk (0.05 = +5 %).
func target_speed(state: Dictionary, wind: float, wind_dir: float, speed_pct: float) -> float:
	if bool(state["anchored"]):
		return 0.0
	var s := stage(state)
	var sail := float(s["sail"])
	if sail <= 0.0:
		return float(s["oars"]) * float(spec(String(state["ship"])).get("oar_mult", 1.0))
	if bool(s.get("swift", false)):  # the swift sail (sea step 5e): the wind always from astern, never weak, faster
		var best := 0.0
		for row: Array in cfg["wind_efficiency"]:
			best = maxf(best, float(row[1]))
		var strong := lerpf(float(cfg["wind_floor"]), 1.0, clampf(maxf(wind, float(s.get("wind_at_least", 0.0))), 0.0, 1.0))
		return float(spec(String(state["ship"]))["top_speed"]) * sail * best * strong * float(s.get("speed_mult", 1.0)) * (1.0 + speed_pct)
	var push := lerpf(float(cfg["wind_floor"]), 1.0, clampf(wind, 0.0, 1.0))
	return float(spec(String(state["ship"]))["top_speed"]) * sail * wind_share(off_wind(float(state["yaw"]), wind_dir)) * push * (1.0 + speed_pct)


# The highest sail stage a helmsman of this Sailing level may set (the swift sail needs its level).
func top_stage(sailing_level: int) -> int:
	var stages: Array = cfg["stages"]
	var top := stages.size() - 1
	while top > 0 and sailing_level < int((stages[top] as Dictionary).get("sailing_level", 0)):
		top -= 1
	return top


# One step of `dt` seconds. The rudder (-1 .. 1, + = to starboard) is set by the helm before. Returns the metres
# moved (for Sailing xp). The new position is in state x / z; the caller may undo it when the ship runs aground.
func step(state: Dictionary, wind: float, wind_dir: float, speed_pct: float, dt: float) -> float:
	var sp := spec(String(state["ship"]))
	var want := target_speed(state, wind, wind_dir, speed_pct)
	var speed := float(state["speed"])
	var rate := float(sp["accel"]) * (3.0 if bool(state["anchored"]) else (1.5 if absf(want) < absf(speed) else 1.0))
	speed = move_toward(speed, want, rate * dt)
	state["speed"] = speed
	var way := clampf(absf(speed) / float(sp["top_speed"]), 0.0, 1.0)
	if not bool(state["anchored"]):
		var turn := deg_to_rad(float(sp["turn_deg"])) * lerpf(float(sp["turn_slow"]), 1.0, way) * float(state["rudder"])
		state["yaw"] = wrapf(float(state["yaw"]) - turn * (1.0 if speed >= -0.01 else -1.0) * dt, -PI, PI)
	var yaw := float(state["yaw"])
	state["x"] = float(state["x"]) - sin(yaw) * speed * dt
	state["z"] = float(state["z"]) - cos(yaw) * speed * dt
	return absf(speed * dt)


# Degrees the wind leans her (+ = starboard side down): the side-push on the sail.
func heel(state: Dictionary, wind: float, wind_dir: float) -> float:
	var sp := spec(String(state["ship"]))
	var yaw := float(state["yaw"])
	var starboard := Vector2(cos(yaw), -sin(yaw))
	var side := starboard.dot(Vector2.from_angle(wind_dir))
	return float(sp["tilt"]["heel"]) * float(stage(state)["sail"]) * clampf(wind, 0.0, 1.0) * side


# Half the deck's width at ship-space z (data outline, straight lines between; 0 beyond the ends).
func half_width(ship_id: String, z: float) -> float:
	var outline: Array = spec(ship_id)["outline"]
	for i in range(1, outline.size()):
		var a: Array = outline[i - 1]
		var b: Array = outline[i]
		if z <= float(a[0]) and z >= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (float(a[0]) - z) / maxf(float(a[0]) - float(b[0]), 0.001))
	return 0.0


# The walking height above the waterline at ship-space z: the main deck, or a raised deck (quarterdeck, forecastle,
# stern castle) over it.
func deck_height(ship_id: String, z: float) -> float:
	var sp := spec(ship_id)
	var top := float(sp["deck"])
	for level: Dictionary in sp.get("levels", []):
		if z >= float(level["from"]) and z <= float(level["to"]):
			top = maxf(top, float(sp["deck"]) + float(level["height"]))
	return top


func tallest_mast(ship_id: String) -> float:
	var top := 4.0
	for mast: Array in spec(ship_id)["masts"]:
		top = maxf(top, float(mast[1]))
	return top


# Is a ship-space point on board (over the deck, or up in the air above it)?
func aboard(ship_id: String, local: Vector3) -> bool:
	var sp := spec(ship_id)
	if local.y < float(sp["deck"]) - 0.6 or local.y > float(sp["deck"]) + tallest_mast(ship_id):
		return false
	return absf(local.x) <= half_width(ship_id, local.z) + 0.35
