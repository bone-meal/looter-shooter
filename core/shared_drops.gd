# Purpose: the host's list of guns that PLAYERS dropped for others (pure rules). Only these are shared online:
# the first player to ask for one gets it; what enemies and chests drop stays each player's own (director, round 5).
# Dependencies: none. Used by game/net_drops.gd and tools/trade_check.gd.
extends RefCounted

var seconds := 300.0  # a shared drop lies this long
var limit := 40  # the oldest goes when more lie around

var _next := 1
var _drops := {}  # id -> {"gun": Dictionary, "pos": Vector3, "until": float}


func add(gun: Dictionary, pos: Vector3, now: float) -> Dictionary:
	var gone: Array = []
	while _drops.size() >= limit:
		var oldest: int = _drops.keys()[0]
		_drops.erase(oldest)
		gone.append(oldest)
	var id := _next
	_next += 1
	_drops[id] = {"gun": gun.duplicate(true), "pos": pos, "until": now + seconds}
	return {"id": id, "gone": gone}


# The gun, taken off the list, or {} when somebody else was first.
func take(id: int) -> Dictionary:
	if not _drops.has(id):
		return {}
	var gun: Dictionary = _drops[id]["gun"]
	_drops.erase(id)
	return gun


# Ids whose time is up (taken off the list).
func expired(now: float) -> Array:
	var out: Array = []
	for id: int in _drops.keys():
		if now >= float(_drops[id]["until"]):
			_drops.erase(id)
			out.append(id)
	return out


# Everything that lies around, for a player who just joined: [[id, gun, pos], ...].
func all() -> Array:
	var out: Array = []
	for id: int in _drops:
		out.append([id, _drops[id]["gun"], _drops[id]["pos"]])
	return out
