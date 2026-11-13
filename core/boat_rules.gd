# Purpose: pure rules of the steered boat: where it is, where its bow points and how fast it goes; how throttle and
# rudder change that; where it cannot go (water shallower than its draught, unless it is backing off toward deeper
# water); and who sits in which seat (seat 0 is the helm). No nodes: the caller says how deep the water is.
# Dependencies: none. Data: data/boat.json, passed to the constructor. Positions are metres on the land's own map
# (x, z from the spawn island's middle, as core/archipelago.gd); yaw as a player's look yaw (0 = toward -z, a turn to
# the right makes it smaller).
extends RefCounted

var cfg: Dictionary
var x := 0.0
var z := 0.0
var yaw := 0.0
var speed := 0.0  # along the bow, metres a second (negative = astern)
var aground := false  # the last step was stopped by shallow water or something solid
var seats: Array[int] = []  # a player's id per seat, 0 = free; seat 0 steers


func _init(config: Dictionary) -> void:
	cfg = config
	seats.resize((config["seats"] as Array).size())
	seats.fill(0)


func place(at: Vector2, heading: float) -> void:
	x = at.x
	z = at.y
	yaw = heading
	speed = 0.0
	aground = false


func forward() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


# One step of sailing. throttle and rudder are -1..1 (rudder above 0 = to the right). depth = func(x, z) -> float:
# metres of water there (0 or less where there is land or something solid).
func step(throttle: float, rudder: float, delta: float, depth: Callable) -> void:
	throttle = clampf(throttle, -1.0, 1.0)
	rudder = clampf(rudder, -1.0, 1.0)
	if absf(throttle) > 0.01:
		var wanted := throttle * float(cfg["max_speed"] if throttle > 0.0 else cfg["reverse_speed"])
		var against := signf(wanted) != signf(speed) and absf(speed) > 0.05
		speed = move_toward(speed, wanted, float(cfg["brake"] if against else cfg["accel"]) * delta)
	else:
		speed = move_toward(speed, 0.0, float(cfg["drag"]) * delta)
	var way := clampf(absf(speed) / float(cfg["turn_full_at"]), 0.0, 1.0)  # no way on = no steering
	yaw = wrapf(yaw - rudder * deg_to_rad(float(cfg["turn_rate_deg"])) * way * signf(speed) * delta, -PI, PI)
	var ahead := forward()
	var to_x := x + ahead.x * speed * delta
	var to_z := z + ahead.y * speed * delta
	var need := float(cfg["draught"])
	var now := _least_depth(x, z, depth)
	var then := _least_depth(to_x, to_z, depth)
	aground = then < need and then <= now  # too shallow there, and not a way off: it stops
	if aground:
		speed = 0.0
		return
	x = to_x
	z = to_z


# The shallowest water under bow, middle and stern with the boat's middle at (at_x, at_z).
func _least_depth(at_x: float, at_z: float, depth: Callable) -> float:
	var ahead := forward() * float(cfg["half_length"])
	return minf(float(depth.call(at_x, at_z)), minf(float(depth.call(at_x + ahead.x, at_z + ahead.y)), float(depth.call(at_x - ahead.x, at_z - ahead.y))))


# A seat's place on the map: Vector3(x, metres above the waterline, z).
func seat_place(seat: int) -> Vector3:
	var at: Array = cfg["seats"][seat]
	var ahead := forward()
	var right := Vector2(-ahead.y, ahead.x)
	var spot := Vector2(x, z) + right * float(at[0]) - ahead * float(at[2])
	return Vector3(spot.x, float(at[1]), spot.y)


func seat_of(id: int) -> int:
	return seats.find(id) if id != 0 else -1


func helm() -> int:
	return seats[0]


func aboard() -> int:
	return seats.size() - seats.count(0)


# Takes the first free seat (the helm first). Returns the seat, the one already held, or -1 when the boat is full.
func sit(id: int) -> int:
	if seat_of(id) >= 0:
		return seat_of(id)
	var free := seats.find(0)
	if free >= 0 and id != 0:
		seats[free] = id
	return free if id != 0 else -1


# Gets up. When that leaves the helm empty with people aboard, the one in the lowest seat moves to it.
func leave(id: int) -> bool:
	var seat := seat_of(id)
	if seat < 0:
		return false
	seats[seat] = 0
	if seat == 0:
		for other in range(1, seats.size()):
			if seats[other] != 0:
				seats[0] = seats[other]
				seats[other] = 0
				break
	return true


# Game over or the boat is gone: nobody aboard, standing still.
func empty() -> void:
	seats.fill(0)
	speed = 0.0
	aground = false
