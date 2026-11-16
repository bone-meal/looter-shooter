# Purpose: the sea online (director: "fix online for seeing and interacting with this"). HOST-AUTHORITATIVE fleet:
# the host alone steps the world fleet (game/sea_ships.gd) and sends every ship's state, the sea clock and any held
# weather 10 times a second; other machines follow it smoothly. Taking the helm, the helm's rudder and sail stage,
# and the anchor are INTENTS sent to the host, which checks them (the helm is free, the player stands at it, his
# claimed Sailing level meets the ship's, he is at the anchor) and applies them. Each player also tells where he
# stands on a deck (ship + ship-space point, so his body rides the hull on every screen without lagging behind it)
# and whether he swims. Thrown ropes are shown everywhere; the swimmer who reaches one hauls himself up and its end
# is pulled in on every machine. Node "Sea" under game/net_session.gd.
# Dependencies: game/net_session.gd (parent `net`: roster, my_id, is_host, can_send, positions, ghost_deck),
# game/sea_world.gd (group "sea_world": ships, swim, sync_clock, force_weather).
extends Node

const SEND_HZ := 10.0
const INPUT_HZ := 15.0
const HELM_REACH := 4.0  # m: how far from the wheel the host accepts a helm request (positions lag a little)
const MAX_LEVEL := 70
const FAR := 100000.0
const MAX_SHIPS := 24  # the world fleet's cap (a client cannot flood the host with launches)

var net: Node3D
var heard := 0  # fleet packets received (dev)
var sent := 0

var _send_t := 0.0
var _input_t := 0.0
var _rope_n := 0


func _ready() -> void:
	add_to_group("net_sea")


func active() -> bool:
	return net != null and net.can_send()


func is_client() -> bool:
	return active() and not net.is_host()


func my_id() -> int:
	return int(net.my_id()) if net != null else 1


func _sea() -> Node:
	return get_tree().get_first_node_in_group("sea_world")


func _fleet() -> Node:
	var sea := _sea()
	return sea.get("ships") if sea != null else null


func _process(delta: float) -> void:
	if not active():
		return
	var fleet := _fleet()
	if fleet == null:
		return
	_send_t += delta
	if _send_t >= 1.0 / SEND_HZ:
		_send_t = 0.0
		if net.is_host():
			_send_fleet(fleet)
		_send_me(fleet)
	_input_t += delta
	if _input_t >= 1.0 / INPUT_HZ and is_client() and fleet.get("helm_ship") != null:
		_input_t = 0.0
		var ship: Node = fleet.get("helm_ship")
		_helm_input.rpc_id(1, (fleet.get("ships") as Array).find(ship), float(fleet.get("wanted_rudder")), int(fleet.get("wanted_stage")))


# --- the fleet (host -> everyone) ---

func _send_fleet(fleet: Node) -> void:
	var sea := _sea()
	var states: Array = []
	for ship: Node in fleet.get("ships"):
		var s: Dictionary = ship.get("state")
		states.append([float(s["x"]), float(s["z"]), float(s["yaw"]), float(s["speed"]), int(s["stage"]), float(s["rudder"]), bool(s["anchored"]), int(fleet.call("helmsman_of", ship)), String(s["ship"])])
	sent += 1
	_fleet_down.rpc(float(sea.call("seconds")), String(sea.get("_forced")), states)


@rpc("authority", "call_remote", "unreliable_ordered")
func _fleet_down(clock: float, forced: String, states: Array) -> void:
	var sea := _sea()
	var fleet := _fleet()
	if sea == null or fleet == null or not is_finite(clock):
		return
	heard += 1
	sea.call("sync_clock", clock)
	if String(sea.get("_forced")) != forced:
		sea.call("force_weather", forced)
	fleet.call("host_states", states)


# --- the helm and the anchor (client -> host) ---

func request_helm(ship_index: int, level: int) -> void:
	_helm_take.rpc_id(1, ship_index, level)


func leave_helm(ship_index: int) -> void:
	_helm_leave.rpc_id(1, ship_index)


func request_anchor(ship_index: int) -> void:
	_anchor.rpc_id(1, ship_index)


func _ship_for(from: int, ship_index: int) -> Node:
	var fleet := _fleet()
	if not net.is_host() or not net.roster.has(from) or fleet == null:
		return null
	var ships: Array = fleet.get("ships")
	return ships[ship_index] if ship_index >= 0 and ship_index < ships.size() else null


func _near(from: int, ship: Node, spot: Array, reach: float) -> bool:
	var at: Variant = net.positions().get(from)
	if not at is Vector3:
		return false
	var there: Vector3 = ship.call("deck_spot", spot)
	return Vector2((at as Vector3).x - there.x, (at as Vector3).z - there.z).length() <= reach


@rpc("any_peer", "call_remote", "reliable")
func _helm_take(ship_index: int, level: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var ship := _ship_for(from, ship_index)
	if ship == null or level < 1 or level > MAX_LEVEL:
		return
	var spec: Dictionary = ship.get("spec")
	if not _near(from, ship, [float(spec["helm"][0]), float(spec["helm"][1]) + 1.0], HELM_REACH):
		return
	_fleet().call("give_helm", ship, from, level)  # refused inside when taken or the level is too low


@rpc("any_peer", "call_remote", "reliable")
func _helm_leave(ship_index: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var ship := _ship_for(from, ship_index)
	if ship != null and int(_fleet().call("helmsman_of", ship)) == from:
		_fleet().call("free_helm", ship)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _helm_input(ship_index: int, rudder: float, stage: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var ship := _ship_for(from, ship_index)
	if ship == null or int(_fleet().call("helmsman_of", ship)) != from or not is_finite(rudder):
		return
	var s: Dictionary = ship.get("state")
	s["rudder"] = clampf(rudder, -1.0, 1.0)
	s["stage"] = clampi(stage, 0, int(_fleet().get("rules").call("stage_count")) - 1)


@rpc("any_peer", "call_remote", "reliable")
func _anchor(ship_index: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var ship := _ship_for(from, ship_index)
	if ship != null and _near(from, ship, ship.get("spec")["anchor"], 3.5):
		_fleet().call("toggle_anchor", ship)


# --- the shipyard (client -> host): the client's own Carpentry and materials built it (his bag is his own claim);
# the host launches her into its world fleet ---

func request_build(ship_id: String) -> void:
	_build.rpc_id(1, ship_id)


@rpc("any_peer", "call_remote", "reliable")
func _build(ship_id: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	var fleet := _fleet()
	if not net.is_host() or not net.roster.has(from) or fleet == null or ship_id.length() > 24 or (fleet.get("ships") as Array).size() >= MAX_SHIPS:
		return
	fleet.call("launch", ship_id)


# --- where each player stands on a deck, and whether he swims (everyone -> host -> everyone) ---

func _send_me(fleet: Node) -> void:
	var me: Node3D = net.local_player()
	if me == null or not is_instance_valid(me):
		return
	var ship: Node = fleet.call("ship_aboard")
	var index := (fleet.get("ships") as Array).find(ship) if ship != null else -1
	var local := (ship as Node3D).global_transform.affine_inverse() * me.global_position if ship != null else Vector3.ZERO
	var swimming := bool(me.get("swimming"))
	var working := bool(fleet.get("working"))
	if net.is_host():
		_me_down.rpc(1, index, local, swimming, working)
	else:
		_me_up.rpc_id(1, index, local, swimming, working)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _me_up(index: int, local: Vector3, swimming: bool, working: bool) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not net.is_host() or not net.roster.has(from) or not local.is_finite() or local.length() > 40.0 or index < -1 or index > 64:
		return
	_apply_me(from, index, local, swimming, working)
	_me_down.rpc(from, index, local, swimming, working)


@rpc("authority", "call_remote", "unreliable_ordered")
func _me_down(id: int, index: int, local: Vector3, swimming: bool, working: bool) -> void:
	_apply_me(id, index, local, swimming, working)


func _apply_me(id: int, index: int, local: Vector3, swimming: bool, working: bool) -> void:
	if id == my_id():
		return
	var fleet := _fleet()
	var ship: Node3D = null
	if fleet != null and index >= 0 and index < (fleet.get("ships") as Array).size():
		ship = (fleet.get("ships") as Array)[index]
	net.call("ghost_deck", id, ship, local, swimming, working)


# --- thrown ropes ---

func send_rope(ship_index: int, rail: Vector3, lands_at: Vector3) -> String:
	_rope_n += 1
	var key := "%d:%d" % [my_id(), _rope_n]
	if net.is_host():
		_rope_down.rpc(key, ship_index, rail, lands_at)
	else:
		_rope_up.rpc_id(1, key, ship_index, rail, lands_at)
	return key


@rpc("any_peer", "call_remote", "reliable")
func _rope_up(key: String, ship_index: int, rail: Vector3, lands_at: Vector3) -> void:
	var from := multiplayer.get_remote_sender_id()
	if _ship_for(from, ship_index) == null or not key.begins_with("%d:" % from) or key.length() > 24 or not rail.is_finite() or rail.length() > 30.0 or not lands_at.is_finite() or lands_at.length() > FAR:
		return
	_rope_here(key, ship_index, rail, lands_at)
	_rope_down.rpc(key, ship_index, rail, lands_at)


@rpc("authority", "call_remote", "reliable")
func _rope_down(key: String, ship_index: int, rail: Vector3, lands_at: Vector3) -> void:
	_rope_here(key, ship_index, rail, lands_at)


func _rope_here(key: String, ship_index: int, rail: Vector3, lands_at: Vector3) -> void:
	if key.begins_with("%d:" % my_id()):
		return  # our own rope is already out
	var sea := _sea()
	var fleet := _fleet()
	if sea == null or fleet == null or ship_index < 0 or ship_index >= (fleet.get("ships") as Array).size():
		return
	sea.get("swim").call("show_rope", key, (fleet.get("ships") as Array)[ship_index], rail, net.call("from_shared", lands_at))


func rope_used(key: String) -> void:
	if net.is_host():
		_rope_gone_down.rpc(key)
	else:
		_rope_gone_up.rpc_id(1, key)


@rpc("any_peer", "call_remote", "reliable")
func _rope_gone_up(key: String) -> void:
	if net.is_host() and net.roster.has(multiplayer.get_remote_sender_id()) and key.length() <= 24:
		_rope_gone_here(key)
		_rope_gone_down.rpc(key)


@rpc("authority", "call_remote", "reliable")
func _rope_gone_down(key: String) -> void:
	_rope_gone_here(key)


func _rope_gone_here(key: String) -> void:
	var sea := _sea()
	if sea != null:
		sea.get("swim").call("drop_rope", key)
