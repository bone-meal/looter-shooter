# Purpose: the party's scoreboard online. Every machine tells the host its own row (points, kills, headshots, downs,
# revives) when it changes; the host cleans it and passes the whole table on. These numbers are only SHOWN (Tab, and
# the points list on the HUD): nothing is bought or decided from them.
# Dependencies: game/net_session.gd (parent; `net`), core/score_card.gd. Node name must be "Scores" on every machine.
extends Node

const ScoreCard = preload("res://core/score_card.gd")

const SEND_GAP := 0.5  # seconds between two sends, at most
const MIN_GAP := 0.2  # host: a client's rows closer together than this are dropped

var net: Node3D
var card: ScoreCard  # our own score, set by game/game_session.gd (null until a session is running)
var table := {}  # peer id -> {points, kills, headshots, downs, revives}, as the host cleaned it

var _wait := 0.0
var _sent_hash := 0  # hash of the last row we sent
var _dirty := false  # host: the table changed and has to go out
var _last := {}  # host: peer id -> engine time of that client's last row


func _ready() -> void:
	net.roster_changed.connect(_on_roster)


# Somebody joined or left (or the host changed): send ours again and drop rows of people who are gone.
func _on_roster(_roster: Dictionary) -> void:
	_sent_hash = 0
	_dirty = true
	for id: int in table.keys():
		if not net.roster.has(id):
			table.erase(id)
			_last.erase(id)


# The other players' rows with their names on them: for the HUD's points list and the scoreboard.
func others() -> Array:
	var out: Array = []
	for id: int in table:
		if id != net.my_id() and net.roster.has(id):
			var row: Dictionary = (table[id] as Dictionary).duplicate()
			row["name"] = String(net.roster[id])
			out.append(row)
	return out


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or card == null or not net.can_send():
		return
	_wait = SEND_GAP
	var row := card.row()
	if row.hash() != _sent_hash:
		_sent_hash = row.hash()
		if net.is_host():
			table[1] = row
			_dirty = true
		else:
			_row_to_host.rpc_id(1, row)
	if _dirty and net.is_host():
		_dirty = false
		_set_table.rpc(table)


@rpc("any_peer", "call_remote", "reliable")
func _row_to_host(row: Dictionary) -> void:
	if not net.is_host() or card == null:
		return
	var id := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec() / 1000.0
	if not net.roster.has(id) or now - float(_last.get(id, -10.0)) < MIN_GAP:
		return
	_last[id] = now
	table[id] = ScoreCard.clean_row(row, card.most_points())
	_dirty = true


@rpc("authority", "call_remote", "reliable")
func _set_table(new_table: Dictionary) -> void:
	table.clear()
	if card == null:
		return
	for id: Variant in new_table:
		if id is int and net.roster.has(id):
			table[id] = ScoreCard.clean_row(new_table[id], card.most_points())
