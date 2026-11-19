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
const TOWN_EVERY := 2.0  # s between the host's town levels (a joiner's town catches up within this)
const TOWN_REACH := 40.0  # m: how near the town a player must be for the host to take his upgrade

const SeaGhosts = preload("res://game/sea_ghosts.gd")
var net: Node3D
var heard := 0  # fleet packets received (dev)
var sent := 0

var _send_t := 0.0
var _town_t := 0.0
var _input_t := 0.0
var _rope_n := 0


var adopted := 0  # dev / checks: times this machine took the sea over from a host who left


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


func _town() -> Node:
	var sea := _sea()
	return sea.get("town") if sea != null else null


func _fleet() -> Node:
	var sea := _sea()
	return sea.get("ships") if sea != null else null


# --- host migration (sea step 12, LOCKED: carry on and save a copy) ---

# This machine is the new host: the sea it was shown goes on as its own world (game_session saves it from now on, as a
# host's): ships from where they were, pirate crews fight on, flotsam is handed out here; creatures in sight slip away,
# dungeon fights and a boss fight begin again (the offering kept).
func adopt_as_host() -> void:
	var sea := _sea()
	if sea == null:
		return
	var fleet: Node = sea.get("ships")
	fleet.call("adopt_as_host")
	var foes: Node = fleet.get("foes")
	(foes.get("crews") as Node).call("adopt_as_host")
	for ship: Node3D in fleet.get("ships"):
		var st: Dictionary = ship.get("state")
		if st.has("foe") and SeaGhosts.is_ghost(ship, (foes.get("rules") as RefCounted).get("cfg")["kinds"]):
			(foes.get("ghosts") as Node).call("begin", ship)
	var gone := int((foes.get("sharks") as Node).call("adopt_as_host")) + int((foes.get("serpent") as Node).call("adopt_as_host")) + int((foes.get("beasts") as Node).call("adopt_as_host"))
	(foes.get("uboat") as Node).call("adopt_as_host")
	(foes.get("flotsam") as Node).call("adopt_as_host")
	var dungeons: Node = sea.get("dungeons")
	dungeons.call("adopt_as_host")
	var boss_again: bool = (dungeons.get("boss") as Node).call("adopt_as_host")
	adopted += 1
	if gone > 0:
		sea.emit_signal("notice", "The host is gone: you hold the sea now. The creatures about slip away in the confusion.")
	else:
		sea.emit_signal("notice", "The host is gone: you hold the sea now (it is kept in your save from here on).")
	if boss_again:
		sea.emit_signal("notice", "The boss pulls back: it comes again at full strength (your offering is not spent).")
	var session := get_tree().get_first_node_in_group("game_session")
	if session != null:
		session.call("save_profile")  # the copy of the world is ours from now on (LOCKED)


# Every machine, once the session is back: a player lying downed in a boss fight that began again gets up.
func after_migration() -> void:
	var session := get_tree().get_first_node_in_group("game_session")
	if session != null and session.has_method("boss_reset_after_migration"):
		session.call("boss_reset_after_migration")


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
	_town_t += delta
	if _town_t >= TOWN_EVERY and net.is_host():
		_town_t = 0.0
		var town := _town()
		if town != null:
			_town_levels.rpc(town.get("rules").call("to_list"))
			_store_list.rpc((town.get("crew_chest") as RefCounted).call("to_list"))
			_town_extra.rpc(town.call("extra_dict"))
		var fleet_f := _fleet()
		if fleet_f != null:
			_cargo_all.rpc(fleet_f.get("holds").call("all_cargo"))  # (holds: a late joiner sees what is aboard)
		if fleet_f != null and not (fleet_f.get("foes").get("flotsam").get("pieces") as Dictionary).is_empty():
			_flotsam_list.rpc(fleet_f.get("foes").get("flotsam").call("to_net"))  # (a late joiner sees what floats)
	_input_t += delta
	if _input_t >= 1.0 / INPUT_HZ and is_client() and fleet.get("helm_ship") != null:
		_input_t = 0.0
		var ship: Node = fleet.get("helm_ship")
		_helm_input.rpc_id(1, (fleet.get("ships") as Array).find(ship), float(fleet.get("wanted_rudder")), int(fleet.get("wanted_stage")), int(fleet.call("sailing_level")))


# --- the fleet (host -> everyone) ---

func _send_fleet(fleet: Node) -> void:
	var sea := _sea()
	var states: Array = []
	for ship: Node in fleet.get("ships"):
		var s: Dictionary = ship.get("state")
		states.append([float(s["x"]), float(s["z"]), float(s["yaw"]), float(s["speed"]), int(s["stage"]), float(s["rudder"]), bool(s["anchored"]), int(fleet.call("helmsman_of", ship)), String(s["ship"]),
			float(s["hull"]), float(s["water"]), float(s["leaks"][0]), float(s["leaks"][1]), float(s["leaks"][2]), bool(s.get("sinking", false)), bool(s.get("crane", false)), String(s.get("foe", "")), bool(s.get("struck", false)), snappedf(float(s.get("phase", 1.0)), 0.01), ",".join(PackedStringArray(s.get("parts", [])))])
	sent += 1
	_fleet_down.rpc(float(sea.call("seconds")), String(sea.get("_forced")), states)
	_board_down.rpc(fleet.get("boarding").call("to_net"))
	var crews: Node = fleet.get("foes").get("crews")
	if bool(crews.call("should_send")):
		_crew_down.rpc(crews.call("to_net"))
	var sharks: Node = fleet.get("foes").get("sharks")
	if bool(sharks.call("should_send")):
		_shark_down.rpc(sharks.call("to_net"))
	var wyrm: Node = fleet.get("foes").get("serpent")
	if bool(wyrm.call("should_send")):
		_serpent_down.rpc(wyrm.call("to_net"))
	var beasts: Node = fleet.get("foes").get("beasts")
	if bool(beasts.call("should_send")):
		_beast_down.rpc(beasts.call("to_net"), beasts.call("fires_to_net"))
	var uboat: Node = fleet.get("foes").get("uboat")
	if bool(uboat.call("should_send")):
		_uboat_down.rpc(uboat.call("to_net"))


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
	if ship == null or level < 1 or level > MAX_LEVEL or not net.claim_level_ok(from, "sailing", level):  # (12c: an impossible Sailing level is refused)
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
func _helm_input(ship_index: int, rudder: float, stage: int, level: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var ship := _ship_for(from, ship_index)
	if ship == null or int(_fleet().call("helmsman_of", ship)) != from or not is_finite(rudder):
		return
	_fleet().call("helmsman_level", ship, net.claim_level_cap(from, "sailing", clampi(level, 1, MAX_LEVEL)))  # his Sailing level as it grows while he steers (12c: never past what he can have reached)
	var s: Dictionary = ship.get("state")
	s["rudder"] = clampf(rudder, -1.0, 1.0)
	s["stage"] = clampi(stage, 0, int(_fleet().call("top_stage_of", ship)))  # the swift sail only at its Sailing level


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


# A crane haul started here (game/sea_crane.gd): everybody else sees the hook go down at that ship (sea coordinates).
func tell_crane(ship_index: int, target_sea: Vector3) -> void:
	if net.is_host():
		_crane_down.rpc(ship_index, target_sea, my_id())
	else:
		_crane_up.rpc_id(1, ship_index, target_sea)


@rpc("any_peer", "call_remote", "reliable")
func _crane_up(ship_index: int, target_sea: Vector3) -> void:
	var from := multiplayer.get_remote_sender_id()
	if _ship_for(from, ship_index) == null or not target_sea.is_finite():
		return
	_crane_here(ship_index, target_sea)
	_crane_down.rpc(ship_index, target_sea, from)


@rpc("authority", "call_remote", "reliable")
func _crane_down(ship_index: int, target_sea: Vector3, who: int) -> void:
	if who != my_id():
		_crane_here(ship_index, target_sea)


func _crane_here(ship_index: int, target_sea: Vector3) -> void:
	var fleet := _fleet()
	if fleet == null:
		return
	var ships: Array = fleet.get("ships")
	if ship_index >= 0 and ship_index < ships.size():
		fleet.get("crane").call("show_haul", ships[ship_index], target_sea)
		crane_seen += 1


var crane_seen := 0  # dev: other players' crane hauls shown here


# A ship's part made at the shipyard by a client (his Carpentry and materials: his claim): the host fits it.
func request_part(part: String) -> void:
	_part_up.rpc_id(1, part)


@rpc("any_peer", "call_remote", "reliable")
func _part_up(part: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if net.is_host() and net.roster.has(from) and _fleet() != null and (part == "crane" or ((_fleet().get("gates") as RefCounted).call("parts") as Array).has(part)) and net.claim_can_make(from, "ship_crane" if part == "crane" else part):
		_fleet().call("fit_part", part)


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
	if not net.claim_can_make(from, "ship_" + ship_id):  # (12c: a ship his Carpentry cannot have built yet)
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


# --- the home port town (sea step 7): its levels belong to the host's world. A player pays from his own bag and
# purse (his own claim), but only after the host has raised the level; the host checks the level is the next one and
# that the player is in the town ---

func request_town(plot_index: int, level: int) -> void:
	_town_up.rpc_id(1, plot_index, level)


# The host (or a lone player) raised a plot itself: everyone else follows.
func tell_town(plot_index: int, level: int) -> void:
	if active() and net.is_host():
		_town_done.rpc(plot_index, level, my_id())


@rpc("any_peer", "call_remote", "reliable")
func _town_up(plot_index: int, level: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var town := _town()
	if not net.is_host() or not net.roster.has(from) or town == null:
		return
	var rules: RefCounted = town.get("rules")
	var all: Array = rules.call("ids")
	if plot_index < 0 or plot_index >= all.size() or level != int(rules.call("level", String(all[plot_index]))) + 1 or not _in_town(from):
		_town_no.rpc_id(from, plot_index)
		return
	rules.call("upgrade", String(all[plot_index]))
	_town_done.rpc(plot_index, level, from)


@rpc("authority", "call_remote", "reliable")
func _town_done(plot_index: int, level: int, asker: int) -> void:
	var town := _town()
	if town != null and plot_index >= 0 and level > 0:
		town.call("host_done", plot_index, level, asker, my_id())


@rpc("authority", "call_remote", "reliable")
func _town_no(plot_index: int) -> void:
	var town := _town()
	if town != null:
		town.call("host_refused", plot_index)


@rpc("authority", "call_remote", "unreliable_ordered")
func _town_levels(list: Array) -> void:
	var town := _town()
	if town != null and list.size() <= 64:
		town.call("host_levels", list)


# Is this player standing in the town (near any plot)? By his last shared position in sea coordinates.
func _in_town(from: int) -> bool:
	var sea := _sea()
	var town := _town()
	var at: Variant = net.positions().get(from)
	if sea == null or town == null or not at is Vector3:
		return true  # no position yet: trust the claim (his payment is his own anyway)
	var here: Vector3 = sea.call("local_of", at)
	for p: Dictionary in town.get("rules").call("plots"):
		if Vector2(here.x, here.z).distance_to(Vector2(float(p["at"][0]), float(p["at"][1]))) < TOWN_REACH:
			return true
	return false


# --- the crew's chest at the storehouse (its top level): the host's world keeps it; a player asks to put in or take
# out, the host does it and tells him how many (his bag follows only then) and everyone the chest ---

func request_store(op: String, item: String, n: int) -> void:
	_store_up.rpc_id(1, op, item, n)


func tell_store(list: Array) -> void:
	if active() and net.is_host():
		_store_list.rpc(list)


@rpc("any_peer", "call_remote", "reliable")
func _store_up(op: String, item: String, n: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var town := _town()
	if not net.is_host() or not net.roster.has(from) or town == null or not op in ["put", "take"] or item.length() > 48 or n <= 0 or n > 9999:
		return
	if not bool(town.call("chest_shared")) or not _in_town(from) or (op == "put" and not net.claim_put_ok(from, item, n)):
		_store_done.rpc_id(from, op, item, 0)
		return
	var chest: RefCounted = town.call("chest")
	var did := int(chest.call("put" if op == "put" else "take", item, n))
	_store_done.rpc_id(from, op, item, did)
	_store_list.rpc(chest.call("to_list"))


@rpc("authority", "call_remote", "reliable")
func _store_done(op: String, item: String, n: int) -> void:
	var town := _town()
	if town != null:
		town.call("store_done", op, item, n)


@rpc("authority", "call_remote", "unreliable_ordered")
func _store_list(list: Array) -> void:
	var town := _town()
	if town != null and list.size() <= 200:
		(town.get("crew_chest") as RefCounted).call("from_list", list)


# --- a feast at the tavern (sea step 7b-3): the one who ordered it paid; every player near the tavern eats ---

func tell_feast() -> void:
	if net.is_host():
		_feast_down.rpc()
	else:
		_feast_up.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _feast_up() -> void:
	var from := multiplayer.get_remote_sender_id()
	var town := _town()
	if not net.is_host() or not net.roster.has(from) or town == null:
		return
	town.call("feast_here")
	_feast_down.rpc()


@rpc("authority", "call_remote", "reliable")
func _feast_down() -> void:
	var town := _town()
	if town != null:
		town.call("feast_here")


# --- the trophy hall's cases and the gallery's paintings (sea step 7b-4): the host's world. A player asks; the host
# checks (the case still empty / the painting not yet bought and its wall built, the player in the town) and tells
# everyone; the one who asked then pays (his trophy, his doubloons) ---

func request_act(kind: String, arg: String) -> void:
	_act_up.rpc_id(1, kind, arg)


# The host (or a lone player) did it itself: everyone else follows.
func tell_act(kind: String, arg: String, who: String) -> void:
	if active() and net.is_host():
		_act_done.rpc(kind, arg, my_id(), who)


@rpc("any_peer", "call_remote", "reliable")
func _act_up(kind: String, arg: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	var town := _town()
	if not net.is_host() or not net.roster.has(from) or town == null or kind.length() > 8 or arg.length() > 24:
		return
	if not bool(town.call("can_act", kind, arg)) or not _in_town(from):
		_act_no.rpc_id(from, kind)
		return
	var who := String(net.roster[from]).left(24)
	town.call("act_done", kind, arg, from, who, my_id())
	_act_done.rpc(kind, arg, from, who)


@rpc("authority", "call_remote", "reliable")
func _act_done(kind: String, arg: String, asker: int, who: String) -> void:
	var town := _town()
	if town != null:
		town.call("act_done", kind, arg, asker, who, my_id())


@rpc("authority", "call_remote", "reliable")
func _act_no(_kind: String) -> void:
	var town := _town()
	if town != null:
		town.set("said", "The harbour master said no")
		(town.get("window") as CanvasItem).queue_redraw()


@rpc("authority", "call_remote", "unreliable_ordered")
func _town_extra(got: Dictionary) -> void:
	var town := _town()
	if town != null:
		town.call("load_extra", got)


# --- floating cargo (sea step 8): the host's pieces; a player who reaches one asks for it, the host gives it to the
# first who asked (and is near it) and tells everyone it is gone; the taker rolls its loot himself ---

func tell_flotsam(list: Array) -> void:
	if active() and net.is_host():
		_flotsam_list.rpc(list)


func request_flotsam(id: int) -> void:
	_flotsam_ask.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _flotsam_ask(id: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var fleet := _fleet()
	var sea := _sea()
	if not net.is_host() or not net.roster.has(from) or fleet == null or sea == null:
		return
	var at: Variant = net.positions().get(from)
	var flot: Node = fleet.get("foes").get("flotsam")
	var p: Dictionary = flot.get("pieces").get(id, {})
	if p.is_empty() or not at is Vector3:
		return
	if not bool(flot.call("host_give", id, sea.call("local_of", at))):
		return
	_flotsam_yes.rpc_id(from, String(p["loot"]), String(p["region"]))
	_flotsam_list.rpc(flot.call("to_net"))


@rpc("authority", "call_remote", "reliable")
func _flotsam_yes(loot_id: String, region_id: String) -> void:
	var fleet := _fleet()
	if fleet != null:
		fleet.get("foes").get("flotsam").call("grant", loot_id.left(24), region_id.left(16))


@rpc("authority", "call_remote", "reliable")
func _flotsam_list(list: Array) -> void:
	var fleet := _fleet()
	if fleet != null and list.size() <= 64:
		fleet.get("foes").get("flotsam").call("from_net", list)


# --- pirate crews (sea step 8b): the host runs them and sends where each stands (ship + ship space); a client's hits
# on its puppets are intents the host applies (capped); the host says who fell and whose blow it was ---

func _crews() -> Node:
	var fleet := _fleet()
	return fleet.get("foes").get("crews") if fleet != null else null


@rpc("authority", "call_remote", "unreliable_ordered")
func _crew_down(list: Array) -> void:
	var crews := _crews()
	if crews != null and list.size() <= 64:
		crews.call("from_net", list)


func tell_crew_fire(id: int, ship_index: int, origin: Vector3, aim: Vector3) -> void:
	if active() and net.is_host():
		_crew_fire.rpc(id, ship_index, origin, aim)


@rpc("authority", "call_remote", "reliable")
func _crew_fire(id: int, ship_index: int, origin: Vector3, aim: Vector3) -> void:
	var crews := _crews()
	if crews != null and origin.is_finite() and aim.is_finite() and aim.length() > 0.01:
		crews.call("show_fire", id, ship_index, origin, aim)


func tell_crew_died(id: int, killer: int) -> void:
	if active() and net.is_host():
		_crew_died.rpc(id, killer)


@rpc("authority", "call_remote", "reliable")
func _crew_died(id: int, killer: int) -> void:
	var crews := _crews()
	if crews != null:
		crews.call("fell", id, killer, my_id())


func request_crew_hit(id: int, damage: float) -> void:
	if is_client():
		_crew_hit.rpc_id(1, id, damage)


@rpc("any_peer", "call_remote", "reliable")
func _crew_hit(id: int, damage: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	var crews := _crews()
	if net.is_host() and net.roster.has(from) and crews != null:
		crews.call("host_hit", id, damage, from)


# --- ship's holds (sea step 8b-2): cargo is the host's world fleet; a player in that hold asks to stow or take, the host
# does it and tells him how many (his bag follows only then) and everyone the hold ---

const CARGO_REACH := 2.5


func request_cargo(ship_index: int, op: String, item: String, n: int) -> void:
	_cargo_up.rpc_id(1, ship_index, op, item, n)


func tell_cargo(ship_index: int, list: Array) -> void:
	if active() and net.is_host():
		_cargo_list.rpc(ship_index, list)


@rpc("any_peer", "call_remote", "reliable")
func _cargo_up(ship_index: int, op: String, item: String, n: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var ship: Node = _ship_for(from, ship_index)
	if not net.is_host() or ship == null or not op in ["put", "take"] or item.length() > 48 or n <= 0 or n > 9999:
		return
	var spec: Dictionary = ship.get("spec")
	if spec.get("hold", {}).is_empty() or (ship.get("state") as Dictionary).has("foe") or not _near(from, ship, spec["hold"]["chest"], CARGO_REACH) or (op == "put" and not net.claim_put_ok(from, item, n)):
		_cargo_done.rpc_id(from, op, item, 0)
		return
	var did := int(_fleet().get("holds").call("host_cargo", ship, op, item, n))
	_cargo_done.rpc_id(from, op, item, did)


@rpc("authority", "call_remote", "reliable")
func _cargo_done(op: String, item: String, n: int) -> void:
	var fleet := _fleet()
	if fleet != null:
		fleet.get("holds").call("cargo_done", op, item.left(48), n)


@rpc("authority", "call_remote", "reliable")
func _cargo_list(ship_index: int, list: Array) -> void:
	var fleet := _fleet()
	if fleet == null or list.size() > 200:
		return
	var ships: Array = fleet.get("ships")
	if ship_index >= 0 and ship_index < ships.size():
		(ships[ship_index].get("state") as Dictionary)["cargo"] = list


@rpc("authority", "call_remote", "unreliable_ordered")
func _cargo_all(list: Array) -> void:
	for got: Variant in list.slice(0, 32):
		if got is Array and (got as Array).size() == 2 and got[1] is Array:
			_cargo_list(int(got[0]), got[1])


# --- sharks and the Tide Wyrm (sea step 8c): the host runs them and sends where they are; a client's hits go to the
# host (capped), the host says who killed them ---

func _foe_part(part: String) -> Node:
	var fleet := _fleet()
	return fleet.get("foes").get(part) if fleet != null else null


@rpc("authority", "call_remote", "unreliable_ordered")
func _shark_down(list: Array) -> void:
	var sharks := _foe_part("sharks")
	if sharks != null and list.size() <= 16:
		sharks.call("from_net", list)


func request_shark_hit(id: int, damage: float) -> void:
	if is_client():
		_shark_hit.rpc_id(1, id, damage)


@rpc("any_peer", "call_remote", "reliable")
func _shark_hit(id: int, damage: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	var sharks := _foe_part("sharks")
	if net.is_host() and net.roster.has(from) and sharks != null:
		sharks.call("host_hit", id, damage, from)


func tell_shark_died(id: int, killer: int) -> void:
	if active() and net.is_host():
		_shark_died.rpc(id, killer)


@rpc("authority", "call_remote", "reliable")
func _shark_died(id: int, killer: int) -> void:
	var sharks := _foe_part("sharks")
	if sharks != null:
		sharks.call("fell", id, killer, my_id())


@rpc("authority", "call_remote", "unreliable_ordered")
func _serpent_down(got: Array) -> void:
	var wyrm := _foe_part("serpent")
	if wyrm != null and got.size() <= 8:
		wyrm.call("from_net", got)


func request_serpent_hit(damage: float) -> void:
	if is_client():
		_serpent_hit.rpc_id(1, damage)


@rpc("any_peer", "call_remote", "reliable")
func _serpent_hit(damage: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	var wyrm := _foe_part("serpent")
	if net.is_host() and net.roster.has(from) and wyrm != null:
		wyrm.call("host_hit", damage, from)


func tell_serpent_died(killer: int) -> void:
	if active() and net.is_host():
		_serpent_died.rpc(killer)


@rpc("authority", "call_remote", "reliable")
func _serpent_died(killer: int) -> void:
	var wyrm := _foe_part("serpent")
	if wyrm != null:
		wyrm.call("fell", killer, my_id())


# --- the drowned (sea step 8d): a held swimmer is pulled under on his own machine ---

func tell_drag(peer: int, seconds: float) -> void:
	if active() and net.is_host() and net.roster.has(peer) and peer != my_id():
		_drag.rpc_id(peer, seconds)


@rpc("authority", "call_remote", "unreliable")
func _drag(seconds: float) -> void:
	var drowned := _foe_part("drowned")
	if drowned != null and is_finite(seconds):
		drowned.call("pulled", seconds)


# --- the regions' own creatures (sea step 8e): host -> everyone, hits to the host, what they do to a player ---

@rpc("authority", "call_remote", "unreliable_ordered")
func _beast_down(list: Array, fire_list: Array) -> void:
	var beasts := _foe_part("beasts")
	if beasts != null and list.size() <= 24 and fire_list.size() <= 32:
		beasts.call("from_net", list, fire_list)


func request_beast_hit(id: int, damage: float) -> void:
	if active() and not net.is_host():
		_beast_hit.rpc_id(1, id, damage)


@rpc("any_peer", "call_remote", "reliable")
func _beast_hit(id: int, damage: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	var beasts := _foe_part("beasts")
	if net.is_host() and net.roster.has(from) and beasts != null and is_finite(damage):
		beasts.call("host_hit", id, damage, from)


func tell_beast_died(id: int, killer: int) -> void:
	if active() and net.is_host():
		_beast_died.rpc(id, killer)


@rpc("authority", "call_remote", "reliable")
func _beast_died(id: int, killer: int) -> void:
	var beasts := _foe_part("beasts")
	if beasts != null:
		beasts.call("fell", id, killer, my_id())


# --- the dungeons (sea step 9): [F] asks to the host, the states to everyone, a chest's loot to its opener ---

func request_dungeon(id: String, ch: String, at: Vector3) -> void:
	if active() and not net.is_host():
		_dun_act.rpc_id(1, id, ch, at)


# A player's [F] in a dungeon: he says where he stands (local to the dungeon); the host takes it when that agrees
# with where it sees him (within a few metres: his last position update may lag a teleport or a step).
@rpc("any_peer", "call_remote", "reliable")
func _dun_act(id: String, ch: String, at: Vector3) -> void:
	var from := multiplayer.get_remote_sender_id()
	var sea := _sea()
	if not net.is_host() or not net.roster.has(from) or sea == null or id.length() > 32 or ch.length() != 1 or not at.is_finite():
		return
	var dungeons: Node = sea.get("dungeons")
	if not (dungeons.get("spaces") as Dictionary).has(id):
		return
	var space: Vector3 = dungeons.call("space_of", id)
	var seen: Variant = net.positions().get(from)
	if seen is Vector3:
		var local: Vector3 = (sea.call("local_of", seen) as Vector3) - space
		if local.distance_to(at) > 6.0:
			dungeons.set("last", "refused %s %s: seen %s, says %s" % [id, ch, str(local.snapped(Vector3.ONE * 0.1)), str(at.snapped(Vector3.ONE * 0.1))])
			return
	dungeons.call("host_act", from, id, ch, at)


func tell_dungeons(states: Dictionary) -> void:
	if active() and net.is_host():
		_dun_states.rpc(states)


@rpc("authority", "call_remote", "reliable")
func _dun_states(states: Dictionary) -> void:
	var sea := _sea()
	if sea != null and states.size() <= 16:
		sea.get("dungeons").call("from_net", states)


func tell_dungeon_loot(peer: int, loot: String, region_n: int) -> void:
	if active() and net.is_host() and net.roster.has(peer):
		_dun_loot.rpc_id(peer, loot, region_n)


@rpc("authority", "call_remote", "reliable")
func _dun_loot(loot: String, region_n: int) -> void:
	var sea := _sea()
	if sea != null and loot.begins_with("dungeon") and loot.length() <= 32:
		sea.get("dungeons").call("grant", loot, clampi(region_n, 1, 7))


# --- the sea tools (sea step 9b): an ice slab told to everyone (through the host), a tool from a dungeon chest ---

func tell_tool_fx(kind: String, a: Vector3, b: Vector3 = Vector3.ZERO) -> void:
	if not active():
		return
	if net.is_host():
		_tool_fx.rpc(kind, a, b, my_id())
	else:
		_tool_fx_up.rpc_id(1, kind, a, b)


@rpc("any_peer", "call_remote", "reliable")
func _tool_fx_up(kind: String, a: Vector3, b: Vector3) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not net.is_host() or not net.roster.has(from) or not kind in ["ice", "hook", "bolt"] or not a.is_finite() or not b.is_finite() or a.length() > 60000.0 or b.length() > 60000.0:
		return
	_tool_fx(kind, a, b, from)
	for peer: int in net.roster:
		if peer != from and peer != my_id():
			_tool_fx.rpc_id(peer, kind, a, b, from)


# What another player's tool did here (sea coordinates): an ice slab, his hook's line to a ring, an ember bolt.
@rpc("authority", "call_remote", "reliable")
func _tool_fx(kind: String, a: Vector3, b: Vector3, who: int) -> void:
	var sea := _sea()
	if sea != null and a.is_finite() and b.is_finite():
		sea.get("tools").call("fx_from_net", kind, a, b, who)


func tell_dungeon_gift(peer: int, piece: String) -> void:  # (sea step 9d) a chart piece from a puzzle chest
	if active() and net.is_host() and net.roster.has(peer):
		_dungeon_gift.rpc_id(peer, piece)


@rpc("authority", "call_remote", "reliable")
func _dungeon_gift(piece: String) -> void:
	var sea := _sea()
	if sea != null and piece.length() <= 32:
		sea.get("dungeons").call("receive_piece", piece)


func tell_tool_gift(peer: int, tool: String) -> void:
	if active() and net.is_host() and net.roster.has(peer):
		_tool_gift.rpc_id(peer, tool)


@rpc("authority", "call_remote", "reliable")
func _tool_gift(tool: String) -> void:
	var sea := _sea()
	if sea != null and tool.length() <= 16:
		sea.get("tools").call("give", tool)


# --- the G U-boat (sea step 8e-4): host -> everyone (the boat and its torpedoes; its deeds' notices and chart pins) ---

@rpc("authority", "call_remote", "unreliable_ordered")
func _uboat_down(got: Array) -> void:
	var uboat := _foe_part("uboat")
	if uboat != null and got.size() == 2 and got[0] is Array and got[1] is Array and (got[1] as Array).size() <= 8:
		uboat.call("from_net", got)


func tell_uboat_event(kind: String) -> void:
	if active() and net.is_host():
		_uboat_event.rpc(kind)


@rpc("authority", "call_remote", "reliable")
func _uboat_event(kind: String) -> void:
	var uboat := _foe_part("uboat")
	if uboat != null and kind.length() <= 16:
		uboat.call("event", kind)


func tell_player_fx(peer: int, kind: String, v: Vector3, damage: float) -> void:
	if active() and net.is_host() and net.roster.has(peer) and peer != my_id():
		_player_fx.rpc_id(peer, kind, v, damage)


@rpc("authority", "call_remote", "reliable")
func _player_fx(kind: String, v: Vector3, damage: float) -> void:
	var beasts := _foe_part("beasts")
	if beasts != null and kind in ["knock", "snatch", "slide"]:
		beasts.call("player_fx", kind, v, damage)


# --- the super bosses (sea step 10): the host's boss at 10 Hz, clients' hits / downs / revives as asks ---

func _boss() -> Node:
	var sea := _sea()
	return (sea.get("dungeons") as Node).get("boss") if sea != null else null


func tell_boss(got: Array) -> void:
	if active() and net.is_host():
		_boss_down.rpc(got)


@rpc("authority", "call_remote", "unreliable_ordered")
func _boss_down(got: Array) -> void:
	var boss := _boss()
	if boss != null and got.size() <= 24:
		boss.call("from_net", got)


func request_boss_hit(damage: float) -> void:
	if is_client():
		_boss_hit.rpc_id(1, damage)


@rpc("any_peer", "call_remote", "reliable")
func _boss_hit(damage: float) -> void:
	var boss := _boss()
	if net.is_host() and net.roster.has(multiplayer.get_remote_sender_id()) and boss != null and is_finite(damage):
		boss.call("host_hit", damage, multiplayer.get_remote_sender_id())


func request_boss_part(id: String, damage: float) -> void:
	if is_client():
		_boss_part.rpc_id(1, id, damage)


@rpc("any_peer", "call_remote", "reliable")
func _boss_part(id: String, damage: float) -> void:
	var boss := _boss()
	if net.is_host() and net.roster.has(multiplayer.get_remote_sender_id()) and boss != null and id.length() <= 24 and is_finite(damage) and damage > 0.0:
		boss.call("host_part", id, damage)


func request_boss_down(state: String) -> void:
	if is_client():
		_boss_state.rpc_id(1, state)


@rpc("any_peer", "call_remote", "reliable")
func _boss_state(state: String) -> void:
	var boss := _boss()
	if net.is_host() and net.roster.has(multiplayer.get_remote_sender_id()) and boss != null and state in ["up", "down", "out"]:
		boss.call("host_down", multiplayer.get_remote_sender_id(), state)


func request_boss_revive(target: int) -> void:
	if is_client():
		_boss_revive.rpc_id(1, target)


@rpc("any_peer", "call_remote", "reliable")
func _boss_revive(target: int) -> void:
	var boss := _boss()
	if net.is_host() and net.roster.has(multiplayer.get_remote_sender_id()) and boss != null:
		boss.call("host_revive", multiplayer.get_remote_sender_id(), target)


func tell_boss_revived(peer: int, share: float) -> void:
	if active() and net.is_host() and net.roster.has(peer):
		_boss_revived.rpc_id(peer, share)


@rpc("authority", "call_remote", "reliable")
func _boss_revived(share: float) -> void:
	var s := get_tree().get_first_node_in_group("game_session")
	if s != null and is_finite(share):
		s.call("_on_revived", clampf(share, 0.05, 1.0))


func tell_boss_offered(peer: int) -> void:
	if active() and net.is_host() and net.roster.has(peer):
		_boss_offered.rpc_id(peer)


@rpc("authority", "call_remote", "reliable")
func _boss_offered() -> void:
	var boss := _boss()
	if boss != null:
		boss.call("offered")


func tell_boss_end(id: String, how: String) -> void:
	if active() and net.is_host():
		_boss_end.rpc(id, how)


@rpc("authority", "call_remote", "reliable")
func _boss_end(id: String, how: String) -> void:
	var boss := _boss()
	if boss != null and id.length() <= 32 and how in ["won", "wipe"]:
		boss.call("ended", id, how)


func tell_boss_notice(text: String) -> void:
	if active() and net.is_host():
		_boss_notice.rpc(text.left(120))


@rpc("authority", "call_remote", "reliable")
func _boss_notice(text: String) -> void:
	var sea := _sea()
	if sea != null:
		sea.emit_signal("notice", text.left(120))
