# Purpose: the chase guns' effects for the other players (director 2026-11-15: "effects should be seen by online
# players too"). The holder's machine plays an effect and tells the host; the host passes it to everyone else, who
# show it. CROAK: where the holder's frog is (leaping, riding an enemy's head) or that it is back on the gun.
# SWAMP GAS: the holder's clouds (made, gone off); a copy of a cloud near fire on another machine (a teammate's
# inferno, his burning enemy) tells the owner, whose cloud goes off for real (his blast, his damage).
# Node "Chase" under game/net_session.gd (`chase`). (The Mixtape and the beach balls have their own: net_mixtape.gd,
# net_beachballs.gd.)
# Dependencies: game/net_session.gd (parent `net`), game/swamp_gas.gd (copies), the croak_frog model.
extends Node

const SwampGas = preload("res://game/swamp_gas.gd")
const FROG := "res://assets/models/weapons/uniques/croak_frog.gltf"
const KINDS := ["frog", "frog_off", "gas", "gas_pop", "gas_lit"]
const FAR := 100000.0

var net: Node3D
var sent := 0
var heard := 0
var _frogs := {}  # peer -> the copy of his frog
var _frog_goal := {}  # peer -> where his frog is now (the copy glides there)


func _ready() -> void:
	add_to_group("net_chase")


func active() -> bool:
	return net != null and net.can_send()


func my_id() -> int:
	return int(net.my_id()) if net != null else 1


# From an effect on this machine. slot = which of our things (a cloud's number), target = whose thing it is (gas_lit).
func send(kind: String, slot: int, at: Vector3, target: int = 0) -> void:
	if not active():
		return
	sent += 1
	if net.is_host():
		_pass_on(my_id(), kind, slot, at, target)
	else:
		_up.rpc_id(1, kind, slot, at, target)


@rpc("any_peer", "call_remote", "reliable")
func _up(kind: String, slot: int, at: Vector3, target: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not net.is_host() or not net.roster.has(from) or not KINDS.has(kind) or slot < -1 or slot > 64:
		return
	if not at.is_finite() or at.length() > FAR:
		return
	_pass_on(from, kind, slot, at, target)


func _pass_on(from: int, kind: String, slot: int, at: Vector3, target: int) -> void:
	_down.rpc(from, kind, slot, at, target)
	_down(from, kind, slot, at, target)


@rpc("authority", "call_remote", "reliable")
func _down(from: int, kind: String, slot: int, at: Vector3, target: int) -> void:
	if from == my_id():
		return
	heard += 1
	match kind:
		"frog":
			_frog_goal[from] = at
			var frog := _frog_of(from)
			if frog != null and not frog.visible:
				frog.global_position = at
				frog.visible = true
		"frog_off":
			_frog_goal.erase(from)
			if _frogs.has(from) and is_instance_valid(_frogs[from]):
				(_frogs[from] as Node3D).visible = false
		"gas":
			var gas := gas_pool()
			if gas != null:
				gas.remote_puff(from, slot, at)
		"gas_pop":
			var gas_p := gas_pool()
			if gas_p != null:
				gas_p.remote_pop(from, slot, at)
		"gas_lit":
			if target == my_id():
				var gas_l := gas_pool()
				if gas_l != null:
					gas_l.friend_lit(slot)


func _process(delta: float) -> void:
	for peer: int in _frog_goal:
		var frog: Node3D = _frogs.get(peer)
		if frog != null and is_instance_valid(frog) and frog.visible:
			frog.global_position = frog.global_position.lerp(_frog_goal[peer], minf(1.0, delta * 10.0))


func _frog_of(peer: int) -> Node3D:
	if _frogs.has(peer) and is_instance_valid(_frogs[peer]):
		return _frogs[peer]
	var me: Node3D = net.local_player() if net != null else null
	if me == null or me.get_parent() == null or not ResourceLoader.exists(FROG):
		return null
	var frog := (load(FROG) as PackedScene).instantiate() as Node3D
	frog.scale = Vector3.ONE * 1.6
	frog.visible = false
	me.get_parent().add_child(frog)
	_frogs[peer] = frog
	return frog


# This machine's gas clouds (made on first use next to our player).
func gas_pool() -> SwampGas:
	var found := get_tree().get_first_node_in_group("swamp_gas") as SwampGas
	var me: Node3D = net.local_player() if net != null else null
	if found == null and me != null and me.get_parent() != null:
		found = SwampGas.new()
		found.name = "SwampGas"
		me.get_parent().add_child(found)
	if found != null and found.explosives == null and me != null:
		found.explosives = me.get("explosives")
	return found
