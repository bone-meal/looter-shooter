# Purpose: THE DROWNED AT SEA (sea step 8d; director 2026-11-17: CLIMB ABOARD: at night a pack swims to the ship
# and climbs the ladders and hull onto the deck in waves, fought on deck; they also drag swimmers under). The HOST
# starts a rising (encounter kind with "creature": "drowned", night only): `waves` waves, wave_gap_s apart, of
# drowned coming up out of the water ring_m round the ship the chosen player is on (round him if he swims). Their
# bodies are game/sea_crews.gd men (kinds sea_drowned / sea_drowned_brute, swimming = undead: they never drown,
# climb her hull anywhere (not only the ladder) and on deck fight like boarders). In the water a drowned within
# grab_notice_m of a swimming player goes for him instead and, within grab_m, HOLDS him: hold_damage every second
# and pulls him under (his own machine: game/net_sea.gd tell_drag) until hold_s is over, the drowned is hurt, or he
# is out of the water. Then it swims on for the ship.
# Dependencies: game/sea_crews.gd (rise, men), game/sea_sharks.gd (swimmers), data/sea/encounters.json "drowned";
# the fleet (ships, _net), the sea world (notice, map).
extends Node

var cfg: Dictionary  # encounters.json "drowned"
var risings := 0  # dev / checks: risings begun, drowned risen, holds, holds on a remote player
var risen := 0
var holds := 0
var holds_remote := 0
var paused_waves := false  # dev
var nearest := ""  # dev: what the last undead swimmer saw
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _crews: Node
var _sharks: Node
var _waves: Array = []  # host: [{"ship": ship or null, "at": Vector2, "left": n, "next": time, "region": n}]
var _dragged_until := 0.0  # this machine: our player is held under until then
var _rng := RandomNumberGenerator.new()


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D, crews: Node, sharks: Node, encounters: Dictionary) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	_crews = crews
	_sharks = sharks
	cfg = encounters["drowned"]
	_rng.randomize()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _host() -> bool:
	var net: Node = _fleet.call("_net")
	return net == null or not bool(net.call("is_client"))


# Host / dev: the drowned rise round this ship (or round the swimmer at `at` when ship is null).
func begin(ship: Node3D, at: Vector2, region_n: int) -> void:
	_waves.append({"ship": ship, "at": at, "left": int(cfg["waves"]), "next": _now(), "region": maxi(region_n, 1)})
	risings += 1
	_sea.emit_signal("notice", String(cfg["notice"]))


func rising() -> bool:
	return not _waves.is_empty()


func _process(delta: float) -> void:
	if _fleet == null or not bool(_sea.call("running")):
		return
	if _now() < _dragged_until and bool(_player.get("swimming")):  # held: pulled down
		_player.global_position.y -= float(cfg["pull_speed"]) * delta
	if not _host() or paused_waves:
		return
	for w: Dictionary in _waves.duplicate():
		if _now() < float(w["next"]):
			continue
		_wave(w)
		w["left"] = int(w["left"]) - 1
		w["next"] = _now() + float(cfg["wave_gap_s"])
		if int(w["left"]) <= 0:
			_waves.erase(w)


# One wave: n drowned (and a brute from brute_from_region) come up round her, spread round the ring.
func _wave(w: Dictionary) -> void:
	var ship: Node3D = w["ship"]
	var centre: Vector2 = w["at"]
	if ship != null:
		if not is_instance_valid(ship) or bool(ship.get("state").get("sinking", false)):
			return
		centre = Vector2(float(ship.get("state")["x"]), float(ship.get("state")["z"]))
	var region_n := int(w["region"])
	var kinds: Array = []
	for i in int(cfg["per_wave"]) + int(float(cfg["per_wave_per_region"]) * float(region_n - 1)):
		kinds.append("sea_drowned")
	if region_n >= int(cfg["brute_from_region"]):
		kinds.append("sea_drowned_brute")
	var ring: Array = cfg["ring_m"]
	var turn := _rng.randf() * TAU
	for i in kinds.size():
		var a := turn + TAU * float(i) / float(kinds.size()) + _rng.randf_range(-0.3, 0.3)
		var d := _rng.randf_range(float(ring[0]), float(ring[1]))
		var spot := centre + Vector2(cos(a), sin(a)) * d
		if _crews.call("rise", String(kinds[i]), spot.x, spot.y, ship, region_n) >= 0:
			risen += 1


# Host, from game/sea_crews.gd for each undead swimmer: true = handled here (chasing / holding a swimmer).
func swim(_id: int, enemy: Node3D, sw: Dictionary, delta: float) -> bool:
	var swimmers: Dictionary = _sharks.call("swimmers")
	var held: String = sw.get("holding", "")
	if held != "":
		var body: Node3D = swimmers.get(held)
		var hp := float(enemy.get("health").get("hp"))
		if body == null or _now() > float(sw["hold_until"]) or hp < float(sw["hp_at_grab"]):
			sw.erase("holding")
			sw["no_grab_until"] = _now() + float(cfg["regrab_s"])
			return false
		enemy.global_position = body.global_position + (enemy.global_position - body.global_position).normalized() * 0.7
		if _now() >= float(sw["next_hurt"]):
			sw["next_hurt"] = _now() + 1.0
			body.call("take_damage", float(cfg["hold_damage"]), "physical")  # (another player's: his machine takes it)
			_pull(held)
		return true
	if _now() < float(sw.get("no_grab_until", 0.0)):
		return false
	var best := ""
	var best_d := float(cfg["grab_notice_m"])
	var raw := INF
	for key: String in swimmers:
		if not key.begins_with("c"):
			var p := (swimmers[key] as Node3D).global_position
			var d := Vector2(p.x, p.z).distance_to(Vector2(enemy.global_position.x, enemy.global_position.z))  # (flat: he may be a little under)
			raw = minf(raw, d)
			if d < best_d:
				best_d = d
				best = key
	nearest = "%d swimmers, nearest %.1f m" % [swimmers.size(), raw]
	if best == "":
		return false
	var target: Node3D = swimmers[best]
	if best_d <= float(cfg["grab_m"]):
		sw["holding"] = best
		sw["hold_until"] = _now() + float(cfg["hold_s"])
		sw["hp_at_grab"] = float(enemy.get("health").get("hp"))
		sw["next_hurt"] = _now() + 0.3
		holds += 1
		if best != "me":
			holds_remote += 1
		if best == "me":
			_sea.emit_signal("notice", String(cfg["grab_notice"]))
		return true
	var way := target.global_position - enemy.global_position
	way.y = 0.0
	enemy.global_position += way.normalized() * minf(float(cfg["chase_speed"]) * delta, way.length())
	enemy.rotation.y = atan2(-way.x, -way.z)
	return true


# Host: the held swimmer is pulled down for a moment (ours here, another player's on his machine).
func _pull(key: String) -> void:
	if key == "me":
		pulled(1.2)
		return
	var net: Node = _fleet.call("_net")
	if net != null and key.begins_with("g"):
		net.call("tell_drag", int(key.trim_prefix("g")), 1.2)


# This machine: our player is held under for `seconds`.
func pulled(seconds: float) -> void:
	_dragged_until = maxf(_dragged_until, _now() + clampf(seconds, 0.0, 3.0))


# This machine's player is held under right now.
func held_here() -> bool:
	return _now() < _dragged_until


func status() -> String:
	return "drowned risings %d (waves left %d), risen %d, holds %d (remote %d), dragged %s, saw '%s'" % [risings, _waves.size(), risen, holds, holds_remote, str(_now() < _dragged_until), nearest]
