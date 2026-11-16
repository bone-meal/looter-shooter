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
		states.append([float(s["x"]), float(s["z"]), float(s["yaw"]), float(s["speed"]), int(s["stage"]), float(s["rudder"]), bool(s["anchored"]), int(fleet.call("helmsman_of", ship)), String(s["ship"]),
			float(s["hull"]), float(s["water"]), float(s["leaks"][0]), float(s["leaks"][1]), float(s["leaks"][2]), bool(s.get("sinking", false))])
	sent += 1
	_fleet_down.rpc(float(sea.call("seconds")), String(sea.get("_forced")), states)
	_board_down.rpc(fleet.get("boarding").call("to_net"))


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
	var deck: Array = net.call("deck_of", from)  # riding a deck: his ship-space spot is exact (no lag, no origin shift)
	if not deck.is_empty() and deck[0] == ship:
		return Vector2((deck[1] as Vector3).x - float(spot[0]), (deck[1] as Vector3).z - float(spot[1])).length() <= reach
	var at: Variant = net.positions().get(from)
	if not at is Vector3:
		return false
	var there: Vector3 = ship.call("deck_spot", spot)
	return Vector2((at as Vector3).x - there.x, (at as Vector3).z - there.z).length() <= reach


func _how_far(from: int, ship: Node, spot: Array) -> String:
	var deck: Array = net.call("deck_of", from)
	if not deck.is_empty():
		return "deck %s of ship %d, %.1f m" % [str(deck[1]), (_fleet().get("ships") as Array).find(deck[0]), Vector2((deck[1] as Vector3).x - float(spot[0]), (deck[1] as Vector3).z - float(spot[1])).length()]
	var at: Variant = net.positions().get(from)
	return "%.1f m (no deck)" % ((at as Vector3).distance_to(ship.call("deck_spot", spot)) if at is Vector3 else -1.0)


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


# A plank nailed on at a leak zone (sea step 5d): the plank is the client's own claim (his bag); the host checks he
# stands at that zone of that ship and applies it.
func request_plank(ship_index: int, zone: int) -> void:
	_plank.rpc_id(1, ship_index, zone)


@rpc("any_peer", "call_remote", "reliable")
func _plank(ship_index: int, zone: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var ship := _ship_for(from, ship_index)
	if ship == null or zone < 0 or zone > 2:
		return
	var hulls: Node = _fleet().get("hull_part")
	var spot: Array = load("res://core/sea/hull_rules.gd").zones(ship.get("spec"))[zone]
	if _near(from, ship, [float(spot[0]) * 0.8, float(spot[1])], float(hulls.get("hull").cfg["patch_reach"]) + 1.5):
		hulls.call("use_plank", ship, zone)


# Cannons (sea step 5d-2): a client fired on his screen and asks the host, which checks he sits at that cannon and
# fires the real ball (game/sea_cannons.gd host_fire); the host tells everyone else about every real shot.
func request_fire(ship_index: int, cannon: int, yaw: float, pitch: float) -> void:
	_fire_up.rpc_id(1, ship_index, cannon, yaw, pitch)


func tell_fire(ship_index: int, cannon: int, yaw: float, pitch: float) -> void:
	_fire_down.rpc(ship_index, cannon, yaw, pitch, my_id())


@rpc("any_peer", "call_remote", "reliable")
func _fire_up(ship_index: int, cannon: int, yaw: float, pitch: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	var ship := _ship_for(from, ship_index)
	if ship == null or not is_finite(yaw) or not is_finite(pitch):
		return
	var guns: Node = _fleet().get("cannons")
	var spots: Array = ship.get("spec").get("cannons", [])
	if cannon < 0 or cannon >= spots.size():
		return
	var side := 1.0 if float(spots[cannon][0]) >= 0.0 else -1.0
	var seat := [float(spots[cannon][0]) - side * float(guns.get("cfg")["seat_back"]), float(spots[cannon][1])]
	if _near(from, ship, seat, float(guns.get("cfg")["seat_reach"]) + 1.5) and bool(guns.call("host_fire", ship, cannon, yaw, pitch)):
		_fire_down.rpc(ship_index, cannon, yaw, pitch, from)


@rpc("authority", "call_remote", "reliable")
func _fire_down(ship_index: int, cannon: int, yaw: float, pitch: float, shooter: int) -> void:
	var fleet := _fleet()
	if fleet == null or shooter == my_id():
		return
	var ships: Array = fleet.get("ships")
	if ship_index >= 0 and ship_index < ships.size():
		fleet.get("cannons").call("fire", ships[ship_index], cannon, yaw, pitch, false)


# Boarding (sea step 5d-3): a client asks to throw a hook / cut / lay or take up a plank from where he stands; the
# host checks he stands at that rail point of that ship and does it (game/sea_boarding.gd apply). The lines and
# planks go out with every fleet send.
func request_board(kind: String, ship_a: int, ship_b: int, pa: Vector2, pb: Vector2) -> void:
	_board_up.rpc_id(1, kind, ship_a, ship_b, pa, pb)


var board_log := PackedStringArray()  # dev: what the host did with boarding asks (newest last, 6 kept)


@rpc("any_peer", "call_remote", "reliable")
func _board_up(kind: String, ship_a: int, ship_b: int, pa: Vector2, pb: Vector2) -> void:
	var from := multiplayer.get_remote_sender_id()
	var a := _ship_for(from, ship_a)
	var b := _ship_for(from, ship_b)
	var said := "?"
	if a == null or b == null or not pa.is_finite() or not pb.is_finite() or not kind in ["hook", "cut", "plank", "unplank"]:
		said = "bad ask (ships %d %d)" % [ship_a, ship_b]
	else:
		var board: Node = _fleet().get("boarding")
		var reach := float(board.get("cfg")["rail_reach"]) + 2.5
		if _near(from, a, [pa.x, pa.y], reach) or _near(from, b, [pb.x, pb.y], reach):
			said = "done" if bool(board.call("apply", kind, a, b, pa, pb)) else "refused by the rules"
		else:
			said = "not standing there (%s from it)" % _how_far(from, a, [pa.x, pa.y])
	board_log.append("%s %s" % [kind, said])
	if board_log.size() > 6:
		board_log.remove_at(0)


@rpc("authority", "call_remote", "unreliable_ordered")
func _board_down(items: Array) -> void:
	var fleet := _fleet()
	if fleet != null:
		fleet.get("boarding").call("from_net", items)


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
