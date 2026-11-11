# Purpose: player-versus-player damage. The shooter reports a hit on another player's body; the host validates it and tells the victim, whose own game applies armor and health.
# Dependencies: game/net_session.gd (parent; `net`), data/net.json (pvp on/off).
extends Node

var net: Node3D


# Local shooter: our shot hit player `victim`.
func report_hit(victim: int, damage: float) -> void:
	if net == null or not net.is_active() or not bool(net.config("pvp")):
		return
	if net.is_host():
		_host_apply(1, victim, damage)
	else:
		_pvp_hit.rpc_id(1, victim, damage)


@rpc("any_peer", "call_remote", "reliable")
func _pvp_hit(victim: int, damage: float) -> void:
	if net.is_host():
		_host_apply(multiplayer.get_remote_sender_id(), victim, damage)


func _host_apply(shooter: int, victim: int, damage: float) -> void:
	if not net.roster.has(shooter) or not net.roster.has(victim) or shooter == victim:
		return
	if not is_finite(damage) or damage <= 0.0:
		return
	if victim == 1:
		net.local_player().take_damage(damage, "physical")
	else:
		_pvp_damage.rpc_id(victim, damage)


@rpc("authority", "call_remote", "reliable")
func _pvp_damage(amount: float) -> void:
	var player: Node3D = net.local_player()
	if player != null:
		player.take_damage(amount, "physical")
