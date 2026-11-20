# Purpose: party effects that help teammates (sea step 12d; locked earlier as party roles: Rally Cry, War Banner and the
# pony traits Hearthfire and Bloom). The caster's machine tells the host what it cast and where; the host passes it on;
# every other machine applies it to its OWN player when he is near: Rally Cry and Hearthfire within data/party.json
# reach_m of the caster, a War Banner while he stands within its radius (refreshed while inside), a Bloom flower that
# heals him while he stands by it. (Soft Wing works through the host's enemies: game/net_rounds.gd effect "soothe".)
# Node "Party" under game/net_session.gd (`party`). Positions travel as SHARED positions.
# Dependencies: game/net_session.gd (parent `net`), game/player.gd party_effect / self_fx / skill_fx, data/party.json.
extends Node

const DataStore = preload("res://core/data_store.gd")
const KINDS := ["rally", "banner", "hearth", "bloom"]
const FAR := 100000.0

var net: Node3D
var cfg: Dictionary
var sent := 0  # dev / checks
var heard := 0
var applied := {}  # kind -> times it reached our player
var _banners: Array = []  # [shared-free scene position, radius, until, damage, guard]


func _ready() -> void:
	add_to_group("net_party")
	cfg = DataStore.load_json("res://data/party.json")


func active() -> bool:
	return net != null and net.can_send()


func my_id() -> int:
	return int(net.my_id()) if net != null else 1


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# From our player: kind, where (scene position), values a and b (meaning by kind; see party_effect in game/player.gd).
func send(kind: String, at: Vector3, a: Vector3, b: Vector3 = Vector3.ZERO) -> void:
	if not active() or not KINDS.has(kind):
		return
	sent += 1
	var shared: Vector3 = net.to_shared(at)
	if net.is_host():
		_down.rpc(my_id(), kind, shared, a, b)
	else:
		_up.rpc_id(1, kind, shared, a, b)


@rpc("any_peer", "call_remote", "reliable")
func _up(kind: String, at: Vector3, a: Vector3, b: Vector3) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not net.is_host() or not net.roster.has(from) or not KINDS.has(kind):
		return
	if not at.is_finite() or at.length() > FAR or not a.is_finite() or not b.is_finite() or a.length() > 1000.0 or b.length() > 1000.0:
		return
	_down.rpc(from, kind, at, a, b)
	_down(from, kind, at, a, b)


@rpc("authority", "call_remote", "reliable")
func _down(from: int, kind: String, at: Vector3, a: Vector3, b: Vector3) -> void:
	if from == my_id():
		return
	heard += 1
	var here: Vector3 = net.from_shared(at)
	if kind == "banner":  # a: seconds, damage, guard; b.x: radius
		_banners.append([here, clampf(b.x, 0.0, 30.0), _now() + clampf(a.x, 0.0, 60.0), clampf(a.y, 0.0, 200.0), clampf(a.z, 0.0, 90.0)])
		var mine: Node3D = net.local_player()  # (polish1 B4) its pole, disc and ring are seen here too
		var fx: Variant = mine.get("skill_fx") if mine != null and is_instance_valid(mine) else null
		if fx != null:
			var c: Array = (mine.get("gun_db") as RefCounted).call("skill_def", "war_banner").get("color", [1.0, 0.8, 0.3])
			(fx as Node).get("zones").call("ally_banner", here, clampf(b.x, 0.0, 30.0), clampf(a.x, 0.0, 60.0), Color(float(c[0]), float(c[1]), float(c[2])))
		return
	var me: Node3D = net.local_player()
	if me == null or not is_instance_valid(me) or not me.has_method("party_effect"):
		return
	if bool(me.call("party_effect", kind, here, a, float(cfg["reach_m"]))):
		applied[kind] = int(applied.get(kind, 0)) + 1


# Banners of teammates: our player inside one keeps its bonus.
func _process(_delta: float) -> void:
	if _banners.is_empty():
		return
	var now := _now()
	var me: Node3D = net.local_player() if net != null else null
	var i := 0
	while i < _banners.size():
		var bn: Array = _banners[i]
		if now >= float(bn[2]):
			_banners.remove_at(i)
			continue
		if me != null and is_instance_valid(me) and me.has_method("party_effect") and me.global_position.distance_to(bn[0]) <= float(bn[1]):
			if bool(me.call("party_effect", "banner", bn[0], Vector3(0.5, float(bn[3]), float(bn[4])), float(bn[1]))):
				applied["banner"] = int(applied.get("banner", 0)) + 1
		i += 1
