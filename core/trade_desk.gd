# Purpose: the host's book of trades between players (pure rules, no nodes, no network). Two players put up to
# MAX_THINGS things each on the table (a rolled gun or one piece of armour); any change clears both "ready" ticks;
# when both are ready each must confirm; then the desk tells each side what to give and what it gets. Asking,
# answering, cancelling, leaving and standing too far apart are handled here too.
# Every call returns the messages to deliver: [[peer id, message name, arguments array], ...]. The caller
# (game/net_trade.gd) sends them; the test (tools/trade_check.gd) plays two players against it.
# A thing: {"ref": int, "gun": {...}} or {"ref": int, "id": "<armour item id>"}. `ref` is the owner's own mark
# (its inventory slot); the desk only hands it back. The desk checks that a thing is LEGAL (`legal`), never that the
# player owns it: saves are local, so that cannot be known (director's decision, round 5).
# Dependencies: none.
extends RefCounted

const MAX_THINGS := 8
const ASK_SECONDS := 20.0
const MAX_APART := 12.0  # metres: a trade ends when the two are farther apart than this

var legal := Callable()  # func(thing: Dictionary) -> bool, set by the owner

var _asks := {}  # asked peer -> {"from": peer, "at": seconds}
var _tables: Array[Dictionary] = []  # {"peers": [a, b], "offers": {a: [], b: []}, "ready": {a: false, b: false}, "confirmed": {a: false, b: false}}


func busy(peer: int) -> bool:
	return _table_of(peer) >= 0


# `from` asks `to` for a trade. names: peer -> shown name.
func ask(from: int, to: int, names: Dictionary, now: float) -> Array:
	if from == to or not names.has(to) or not names.has(from):
		return [[from, "ended", ["Nobody to trade with."]]]
	if busy(from) or busy(to):
		return [[from, "ended", ["%s is already trading." % names[to] if busy(to) else "You are already trading."]]]
	_asks[to] = {"from": from, "at": now}
	return [[to, "asked", [from, String(names[from])]], [from, "waiting", [String(names[to])]]]


func answer(peer: int, yes: bool, names: Dictionary) -> Array:
	if not _asks.has(peer):
		return []
	var from: int = _asks[peer]["from"]
	_asks.erase(peer)
	if not yes or busy(from) or busy(peer) or not names.has(from):
		return [[from, "ended", ["%s declined." % names.get(peer, "They")]], [peer, "ended", [""]]]
	_tables.append({"peers": [from, peer], "offers": {from: [], peer: []}, "ready": {from: false, peer: false}, "confirmed": {from: false, peer: false}})
	return _views(_tables[_tables.size() - 1], names)


func offer(peer: int, thing: Dictionary, names: Dictionary) -> Array:
	var i := _table_of(peer)
	if i < 0:
		return []
	var table := _tables[i]
	var mine: Array = table["offers"][peer]
	var clean := _clean(thing)
	if clean.is_empty() or mine.size() >= MAX_THINGS or not legal.is_valid() or not bool(legal.call(clean)):
		return [[peer, "refused", [int(thing.get("ref", -1))]]]
	for other: Dictionary in mine:
		if int(other["ref"]) == int(clean["ref"]):
			return []  # that slot is already on the table
	mine.append(clean)
	_unready(table)
	return _views(table, names)


func withdraw(peer: int, ref: int, names: Dictionary) -> Array:
	var i := _table_of(peer)
	if i < 0:
		return []
	var mine: Array = _tables[i]["offers"][peer]
	for n in mine.size():
		if int(mine[n]["ref"]) == ref:
			mine.remove_at(n)
			_unready(_tables[i])
			return _views(_tables[i], names)
	return []


func set_ready(peer: int, on: bool, names: Dictionary) -> Array:
	var i := _table_of(peer)
	if i < 0:
		return []
	var table := _tables[i]
	table["ready"][peer] = on
	if not on:
		_unready(table)
	return _views(table, names)


# The second step: only counts once both are ready. When both have confirmed the trade is done.
func confirm(peer: int, names: Dictionary) -> Array:
	var i := _table_of(peer)
	if i < 0:
		return []
	var table := _tables[i]
	var a: int = table["peers"][0]
	var b: int = table["peers"][1]
	if not (bool(table["ready"][a]) and bool(table["ready"][b])):
		return []
	table["confirmed"][peer] = true
	if not (bool(table["confirmed"][a]) and bool(table["confirmed"][b])):
		return _views(table, names)
	_tables.remove_at(i)
	return [[a, "done", [_refs(table["offers"][a]), _bare(table["offers"][b])]], [b, "done", [_refs(table["offers"][b]), _bare(table["offers"][a])]]]


func cancel(peer: int, names: Dictionary, why := "") -> Array:
	var out: Array = []
	if _asks.has(peer):
		out.append([int(_asks[peer]["from"]), "ended", ["%s declined." % names.get(peer, "They")]])
		_asks.erase(peer)
	var i := _table_of(peer)
	if i >= 0:
		var table := _tables[i]
		_tables.remove_at(i)
		for who: int in table["peers"]:
			out.append([who, "ended", [why if why != "" else ("You cancelled the trade." if who == peer else "%s cancelled the trade." % names.get(peer, "They"))]])
	return out


# Call now and then: asks run out, players who left or walked apart end their trade.
# where: peer -> Vector3 (missing = unknown, not judged).
func tick(names: Dictionary, where: Dictionary, now: float) -> Array:
	var out: Array = []
	for asked: int in _asks.keys():
		if now - float(_asks[asked]["at"]) > ASK_SECONDS or not names.has(asked) or not names.has(_asks[asked]["from"]):
			out.append([int(_asks[asked]["from"]), "ended", ["No answer."]])
			out.append([asked, "ended", [""]])
			_asks.erase(asked)
	for i in range(_tables.size() - 1, -1, -1):
		var a: int = _tables[i]["peers"][0]
		var b: int = _tables[i]["peers"][1]
		var why := ""
		if not names.has(a) or not names.has(b):
			why = "The other player left."
		elif where.has(a) and where.has(b) and (where[a] as Vector3).distance_to(where[b]) > MAX_APART:
			why = "Too far apart: the trade is off."
		if why != "":
			_tables.remove_at(i)
			for who: int in [a, b]:
				if names.has(who):
					out.append([who, "ended", [why]])
	return out


func _table_of(peer: int) -> int:
	for i in _tables.size():
		if (_tables[i]["peers"] as Array).has(peer):
			return i
	return -1


func _unready(table: Dictionary) -> void:
	for who: int in table["peers"]:
		table["ready"][who] = false
		table["confirmed"][who] = false


# Only the fields a thing may have, so nothing else rides along.
func _clean(thing: Dictionary) -> Dictionary:
	if not thing.has("ref"):
		return {}
	if thing.get("gun") is Dictionary:
		return {"ref": int(thing["ref"]), "gun": (thing["gun"] as Dictionary).duplicate(true)}
	if thing.get("id") is String:
		return {"ref": int(thing["ref"]), "id": String(thing["id"])}
	return {}


func _refs(things: Array) -> Array:
	var out: Array = []
	for thing: Dictionary in things:
		out.append(int(thing["ref"]))
	return out


func _bare(things: Array) -> Array:
	var out: Array = []
	for thing: Dictionary in things:
		var copy := thing.duplicate(true)
		copy.erase("ref")
		out.append(copy)
	return out


# What each of the two sees: {"with", "mine", "theirs", "ready_mine", "ready_theirs", "confirm", "confirmed_mine"}.
func _views(table: Dictionary, names: Dictionary) -> Array:
	var out: Array = []
	var a: int = table["peers"][0]
	var b: int = table["peers"][1]
	for pair: Array in [[a, b], [b, a]]:
		var me: int = pair[0]
		var them: int = pair[1]
		out.append([me, "table", [{"with": String(names.get(them, "?")), "mine": (table["offers"][me] as Array).duplicate(true), "theirs": _bare(table["offers"][them]),
			"ready_mine": bool(table["ready"][me]), "ready_theirs": bool(table["ready"][them]),
			"confirm": bool(table["ready"][a]) and bool(table["ready"][b]), "confirmed_mine": bool(table["confirmed"][me])}]])
	return out
