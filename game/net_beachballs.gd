# Purpose: the BEACH BALL BOMBARDIER online (diary/DESIGN_UNIQUES.md: "any player can shoot or bump a ball to set it
# off, so the party can volley them"). The thrower's machine OWNS each of its balls: it alone deals their damage and
# decides when they pop. It tells the host when a ball is launched, changes course (a head bounce, a kick) or pops;
# the host passes that on to everyone, who fly a COPY of the ball (game/beach_balls.gd). A player who kicks or shoots
# someone else's ball moves / hides his copy at once and the host passes the kick or shot to the owner, who applies it
# (a kick is a volley: the pop grows) and tells everyone the new course. Node "BeachBalls" under game/net_session.gd.
# Dependencies: game/net_session.gd (parent `net`: roster, my_id, is_host, can_send, local_player), game/beach_balls.gd.
extends Node

const BeachBalls = preload("res://game/beach_balls.gd")

const KINDS := ["launch", "move", "pop", "kick", "shoot"]
const FAR := 100000.0  # positions and speeds beyond this are refused

var net: Node3D
var sent := 0  # events sent from here (dev: !balls)
var heard := 0  # events received here


func _ready() -> void:
	add_to_group("net_beachballs")


func active() -> bool:
	return net != null and net.can_send()


func my_id() -> int:
	return int(net.my_id()) if net != null else 1


# From game/beach_balls.gd: something happened to a ball. owner = whose ball, slot = its number on the owner's machine.
func send(kind: String, holder: int, slot: int, a: Vector3, b: Vector3) -> void:
	if not active():
		return
	sent += 1
	if net.is_host():
		_pass_on(my_id(), kind, holder, slot, a, b)
	else:
		_up.rpc_id(1, kind, holder, slot, a, b)


@rpc("any_peer", "call_remote", "reliable")
func _up(kind: String, holder: int, slot: int, a: Vector3, b: Vector3) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not net.is_host() or not net.roster.has(from) or not KINDS.has(kind) or slot < 0 or slot >= BeachBalls.POOL_SIZE:
		return
	if (kind == "launch" or kind == "move" or kind == "pop") and holder != from:
		return  # only the owner says where his ball is
	if not a.is_finite() or not b.is_finite() or a.length() > FAR or b.length() > FAR:
		return
	_pass_on(from, kind, holder, slot, a, b)


# Host: to everyone else, and to itself.
func _pass_on(from: int, kind: String, holder: int, slot: int, a: Vector3, b: Vector3) -> void:
	_down.rpc(from, kind, holder, slot, a, b)
	_down(from, kind, holder, slot, a, b)


@rpc("authority", "call_remote", "reliable")
func _down(from: int, kind: String, holder: int, slot: int, a: Vector3, b: Vector3) -> void:
	if from == my_id():
		return  # our own news, already done here
	var balls := pool()
	if balls == null:
		return
	heard += 1
	match kind:
		"launch":
			balls.remote_launch(holder, slot, a, b)
		"move":
			balls.remote_move(holder, slot, a, b)
		"pop":
			balls.remote_pop(holder, slot, a)
		"kick":
			if holder == my_id():
				balls.friend_kick(slot, b)
		"shoot":
			if holder == my_id():
				balls.friend_shot(slot)


# The world's ball pool on this machine (made on first use next to our player).
func pool() -> BeachBalls:
	var found := get_tree().get_first_node_in_group("beach_balls") as BeachBalls
	var me: Node3D = net.local_player() if net != null else null
	if found == null and me != null and me.get_parent() != null:
		found = BeachBalls.new()
		found.name = "BeachBalls"
		me.get_parent().add_child(found)
	if found != null and me != null:
		found.explosives = me.get("explosives")
		found.kicker = me
	return found
