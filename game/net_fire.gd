# Purpose: other players' gunfire online (sea step 12b, LOCKED "bursts of fire events"). The shooter's machine collects
# its shots (sound + where each pellet ended, at most 6 per shot) and slow shots (rockets, grenades, harpoons, flares,
# bolts: where from, how fast) and sends them five times a second as one small message; the host checks it and passes
# it on; every other machine replays it from the shooter's body in the same rhythm: muzzle flash, tracers, sound, and
# harmless copies of the slow shots (no damage anywhere: hits stay the shooter's own, as before).
# Node "Fire" under game/net_session.gd (`fire`). Positions travel as SHARED positions (the sea's floating origin).
# Dependencies: game/net_session.gd (parent `net`: can_send, is_host, roster, player_node, to_shared, from_shared),
# game/fire_copies.gd (the visuals).
extends Node

const FireCopies = preload("res://game/fire_copies.gd")
const SEND_EVERY := 0.2  # s: five bursts a second at most
const MAX_SHOTS := 12  # shots in one burst (more are dropped: a 15-round-a-second SMG makes 3)
const MAX_ENDS := 6  # tracers per shot (a shotgun's pellets are sampled)
const MAX_PROJ := 6
const FAR := 100000.0
const KINDS := ["rocket", "grenade", "harpoon", "flare", "bolt"]

var net: Node3D
var sent := 0  # dev / checks: bursts sent, bursts heard, shots shown, slow shots shown
var heard := 0
var copies := FireCopies.new()
var _shots: Array = []  # this burst: [t, sound, PackedVector3Array of shared ends]
var _proj: Array = []  # this burst: [t, kind, shared from, velocity, gravity, splash radius]
var _burst_t := 0.0  # engine time the burst began
var _send_t := 0.0


func _ready() -> void:
	add_to_group("net_fire")
	add_child(copies)


func active() -> bool:
	return net != null and net.can_send()


func my_id() -> int:
	return int(net.my_id()) if net != null else 1


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _age() -> float:
	if _shots.is_empty() and _proj.is_empty():
		_burst_t = _now()
	return snappedf(_now() - _burst_t, 0.01)


# From our player's shot: its sound and where each pellet ended (scene positions).
func shot(sound: String, ends: PackedVector3Array) -> void:
	if not active() or _shots.size() >= MAX_SHOTS:
		return
	var out := PackedVector3Array()
	var step := maxi(1, ceili(float(ends.size()) / float(MAX_ENDS)))
	for i in range(0, ends.size(), step):
		out.append(net.to_shared(ends[i]))
	_shots.append([_age(), sound.left(24), out])


# From our player's slow shot (scene position, velocity in m/s).
func projectile(kind: String, from: Vector3, vel: Vector3, gravity: float, radius: float) -> void:
	if not active() or _proj.size() >= MAX_PROJ or not KINDS.has(kind):
		return
	_proj.append([_age(), kind, net.to_shared(from), vel, gravity, radius])


func _process(delta: float) -> void:
	_send_t -= delta
	if _send_t > 0.0 or (_shots.is_empty() and _proj.is_empty()):
		return
	_send_t = SEND_EVERY
	if active():
		sent += 1
		if net.is_host():
			_pass_on(my_id(), _shots, _proj)
		else:
			_up.rpc_id(1, _shots, _proj)
	_shots = []
	_proj = []


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _up(shots: Array, proj: Array) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not net.is_host() or not net.roster.has(from) or not _sane(shots, proj):
		return
	_pass_on(from, shots, proj)


# Host: a burst is what it claims to be (sizes, finite, near enough) or it is dropped.
func _sane(shots: Array, proj: Array) -> bool:
	if shots.size() > MAX_SHOTS or proj.size() > MAX_PROJ:
		return false
	for s: Variant in shots:
		if not s is Array or (s as Array).size() != 3 or not (s[2] is PackedVector3Array) or (s[2] as PackedVector3Array).size() > MAX_ENDS:
			return false
		if not is_finite(float(s[0])) or float(s[0]) < 0.0 or float(s[0]) > 1.0 or String(s[1]).length() > 24:
			return false
		for e: Vector3 in s[2]:
			if not e.is_finite() or e.length() > FAR:
				return false
	for p: Variant in proj:
		if not p is Array or (p as Array).size() != 6 or not KINDS.has(String(p[1])) or not (p[2] is Vector3) or not (p[3] is Vector3):
			return false
		if not (p[2] as Vector3).is_finite() or (p[2] as Vector3).length() > FAR or not (p[3] as Vector3).is_finite() or (p[3] as Vector3).length() > 400.0:
			return false
		if not is_finite(float(p[0])) or float(p[0]) < 0.0 or float(p[0]) > 1.0 or absf(float(p[4])) > 50.0 or float(p[5]) < 0.0 or float(p[5]) > 30.0:
			return false
	return true


func _pass_on(from: int, shots: Array, proj: Array) -> void:
	_down.rpc(from, shots, proj)
	_down(from, shots, proj)  # (the host sees a guest's shots too; its own return at once)


@rpc("authority", "call_remote", "unreliable_ordered")
func _down(from: int, shots: Array, proj: Array) -> void:
	if from == my_id():
		return
	var body: Node3D = net.player_node(from)
	if body == null:
		return
	heard += 1
	for s: Array in shots:
		var ends := PackedVector3Array()
		for e: Vector3 in s[2]:
			ends.append(net.from_shared(e))
		copies.queue_shot(float(s[0]), body, String(s[1]), ends)
	for p: Array in proj:
		copies.queue_projectile(float(p[0]), body, String(p[1]), net.from_shared(p[2]), p[3], float(p[4]), float(p[5]))
