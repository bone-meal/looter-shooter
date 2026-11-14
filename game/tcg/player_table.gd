# Purpose: the three player card tables on the beach, online (locked build step 13): F at one sits you down (offline it
# says a second player is needed), a waiting panel until someone sits across, then each picks one of their own full,
# legal decks, a 5 s countdown, and the match the HOST runs (game/net_tcg.gd + core/tcg/table_book.gd): this machine
# holds a mirror of it for the screen's questions and sends only intents. F at a table where two already play =
# watch it (spectators see everything, locked). The end: the result goes into the collection's record as a match
# against a player (+50 chips for a win, the win-milestone play mats). Esc = "Concede?", Esc again concedes; walking
# away or dropping out mid-match is a loss (the host decides). Uses the same screen and 3D view as the House Dealer's table.
# Dependencies: core/tcg/match_state.gd, core/tcg/event_text.gd, core/tcg/mat_book.gd, core/tcg/card_db.gd,
# game/tcg/table_screen.gd, game/tcg/table_view.gd, game/tcg/card_bake.gd, data/tcg/table.json, data/tcg/mats.json.
extends Node

const MatchState = preload("res://core/tcg/match_state.gd")
const EventText = preload("res://core/tcg/event_text.gd")
const MatBook = preload("res://core/tcg/mat_book.gd")
const CardDb = preload("res://core/tcg/card_db.gd")
const TableScreen = preload("res://game/tcg/table_screen.gd")
const TableView = preload("res://game/tcg/table_view.gd")
const CardBake = preload("res://game/tcg/card_bake.gd")
const DataStore = preload("res://core/data_store.gd")
const TcgStats = preload("res://core/tcg/tcg_stats.gd")

signal finished  # a result came in (record, chips): the session saves

var collection: RefCounted
var net_tcg: Node  # game/net_tcg.gd, or null offline
var graphics := "high"
var stats: RefCounted  # the combat record (core/stat_book.gd): the card game's achievements
var _full_counted := false
var _db: RefCounted
var _cfg: Dictionary
var _wallet: RefCounted
var _player: CharacterBody3D
var _hud: Control
var _tables: Array = []  # beach_table nodes
var _views: Array = []  # a 3D view per table (made when first used)
var _bake: Node
var _screen: Control
var _at := -1  # the table this machine sits at or watches, -1 = none
var _watching := false
var _seats: Array = []  # the host's seats view
var _mirror: RefCounted  # the match as the host last said
var _side := 0  # our side (spectators look from side 0)
var _mats_shown := false  # both players' mats laid for this match
var _who: Array = ["", ""]
var _known := {}
var _deck_name := ""


func setup(wallet: RefCounted, casino: Dictionary, layer: CanvasLayer, player: CharacterBody3D, hud: Control, owned: RefCounted, net: Node) -> void:
	_wallet = wallet
	collection = owned
	_player = player
	_hud = hud
	net_tcg = net
	_tables = casino.get("player_tables", [])
	_cfg = DataStore.load_json("res://data/tcg/table.json")
	_db = CardDb.from_files()
	_screen = TableScreen.new()
	layer.add_child(_screen)
	_screen.set_prize(int(_cfg["prize_vs_player"]))
	_screen.deck_chosen.connect(_on_deck)
	_screen.mulligan_chosen.connect(func(indices: Array) -> void: _send({"do": "mulligan", "indices": indices}))
	_screen.intent.connect(_send)
	_screen.leave.connect(_leave)
	_screen.again.connect(_again)
	_bake = CardBake.new()
	_bake.db = _db
	add_child(_bake)
	for t: Node3D in _tables:
		_views.append(null)
	if net_tcg != null:
		net_tcg.message.connect(_on_message)


# Playing with others right now (playing alone the session's network is idle).
func _online() -> bool:
	return net_tcg != null and bool(net_tcg.get("net").call("can_send")) and (net_tcg.get("net").get("roster") as Dictionary).size() > 1


func is_open() -> bool:
	return _at >= 0


func near(pos: Vector3) -> int:
	for i in _tables.size():
		var t: Node3D = _tables[i]
		if Vector2(pos.x - t.global_position.x, pos.z - t.global_position.z).length() < float(_cfg["sit_range"]):
			return i
	return -1


# What F does here, for the prompt.
func prompt(i: int) -> String:
	if not _online():
		return "Card table for two players (play online)"
	if i < _seats.size() and bool((_seats[i] as Dictionary).get("busy", false)):
		return "Watch the match at this card table"
	return "Sit at the card table and play another player (a win pays chips)"


func open(i: int) -> void:
	if not _online():
		_hud.call("notice", "These card tables are for two players online. The House Dealer plays you any time.")
		return
	_at = i
	_watching = i < _seats.size() and bool((_seats[i] as Dictionary).get("busy", false))
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player.look_at_point(_tables[i].call("look_point"))
	_hud.visible = false
	var mats: Dictionary = DataStore.load_json("res://data/tcg/mats.json")  # your half shows your mat
	(_tables[i] as Node3D).call("set_mats", MatBook.current(collection, mats), String(mats.get("default", "")))
	if _watching:
		_screen.open_pick("Watching", "The match shows when its next move is made.", [])
	else:
		net_tcg.call("sit", i)
		_screen.open_pick("Waiting for a second player", "Someone sits across from you and you both pick a deck.", [])


# Esc: watching or waiting = leave; in a match = "Concede?", again = concede.
func request_close() -> void:
	if _mirror != null and String(_mirror.get("phase")) != "over" and not _watching:
		if _screen.asking_concede():
			_screen.ask_concede(false)
			_send({"do": "concede"})
		else:
			_screen.ask_concede(true)
		return
	_leave()


func _leave() -> void:
	if _at < 0:
		return
	if not _watching and net_tcg != null:
		net_tcg.call("leave")
	if _views[_at] != null:
		(_views[_at] as Node3D).call("leave")
	_at = -1
	_watching = false
	_mirror = null
	_mats_shown = false
	_screen.close()
	_hud.visible = true
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# "Play again": sit down at the same table for the next match.
func _again() -> void:
	if _at < 0 or net_tcg == null:
		return
	_watching = false
	_mirror = null
	_mats_shown = false
	net_tcg.call("sit", _at)
	_screen.open_pick("Waiting for a second player", "Someone sits across from you and you both pick a deck.", [])


func _send(move: Dictionary) -> void:
	if net_tcg != null and not _watching:
		net_tcg.call("intent", move)


func _on_deck(key: String) -> void:
	if collection == null or net_tcg == null or _at < 0:
		return
	var slot := int(key.get_slice(":", 1))
	var deck: Dictionary = ((collection.get("decks") as Array)[slot] as Dictionary).duplicate()
	deck["mat"] = MatBook.current(collection, DataStore.load_json("res://data/tcg/mats.json"))  # the other player sees it on their far half
	deck["finishes"] = collection.call("best_finishes", deck.get("cards", []))  # and our foils as foils
	_deck_name = String(deck.get("name", ""))
	net_tcg.call("deck", deck)
	_screen.open_pick("Deck in: %s" % _deck_name, "Waiting for the other player's deck.", [])


func _view_for(i: int) -> Node3D:
	if _views[i] == null:
		var v := TableView.new()
		v.visible = false
		v.bake = _bake
		(_tables[i] as Node3D).add_child(v)
		_views[i] = v
	var view: Node3D = _views[i]
	view.set("graphics", graphics)
	return view


func _on_message(what: String, args: Array) -> void:
	var me: int = net_tcg.get("net").call("my_id")
	match what:
		"seats":
			_seats = args[0]
		"refused":
			if _at >= 0:
				_screen.flash(String(args[0]))
			if _at >= 0 and String(args[0]).begins_with("Both seats"):  # someone was quicker: watch instead
				_watching = true
		"pick":
			if int(args[0]) == _at and not _watching:
				var leaders: Dictionary = _db.get("leaders")
				var choices: Array = []
				var ready: Dictionary = collection.call("playable", _db)
				for slot: int in ready:
					var d: Dictionary = ready[slot]
					choices.append({"key": "slot:%d" % slot, "label": String(d["name"]), "leader": d["leader"], "name": d["name"],
						"sub": (leaders[String(d["leader"])] as Dictionary)["name"]})
				_screen.open_pick("Pick your deck", "" if not choices.is_empty() else "None of your deck slots is a full, legal deck you own. Build one in the binder (P).", choices)
		"countdown":
			if int(args[0]) == _at:
				_screen.open_pick("The match starts in %d seconds" % int(args[1]), "Coin toss, then the mulligan.", [])
		"match":
			if int(args[0]) == _at:
				_show(args)
		"result":
			if int(args[0]) == _at:
				_result(int(args[1]), args[2], args[3], me)
		"void":  # the host left (or we did): no win, no loss
			_seats = []
			if _at >= 0:
				var playing := _mirror != null
				_leave()
				_hud.call("notice", "The host left: the card match is void (no win, no loss)." if playing else "The host left: the card table was cleared.")


func _show(args: Array) -> void:
	var me: int = net_tcg.get("net").call("my_id")
	if _mirror == null:
		_full_counted = false
		_mirror = MatchState.new(_db, [{"leader": "tide_brute", "cards": []}, {"leader": "tide_brute", "cards": []}], 1)
		_known = {}
		_screen.set("view3d", _view_for(_at))
	_mirror.call("restore", args[1])
	var seats: Array = (_seats[_at] as Dictionary).get("peers", [0, 0]) if _at < _seats.size() else [0, 0]
	_side = maxi(seats.find(me), 0)
	if not _mats_shown and args.size() > 5:  # each half shows its player's mat (a watcher sees side 0's near)
		var mats: Dictionary = DataStore.load_json("res://data/tcg/mats.json")
		var by_side: Array = args[5]
		var pick := func(id: String) -> String: return id if (mats["mats"] as Dictionary).has(id) else String(mats.get("default", ""))
		(_tables[_at] as Node3D).call("set_mats", pick.call(String(by_side[_side])), pick.call(String(by_side[1 - _side])))
		_mats_shown = true
	if args.size() > 6 and args[6] is Array and (args[6] as Array).size() == 2 and args[6][0] is Dictionary and args[6][1] is Dictionary:
		_screen.finishes = args[6]
	_who = args[3]
	var names := (_who as Array).duplicate()
	if not _watching:
		names[_side] = "You"
	var lines: PackedStringArray = []
	for e: Dictionary in args[2]:
		if String(e.get("e", "")) == "summon":
			_known[int(e["uid"])] = String(e["card"])
		lines.append(EventText.line(_db, e, _side, _known, names))
	_screen.add_log(lines)
	_screen.add_events(args[2])
	_screen.show_match(_mirror, _side, names)
	if not _watching and not _full_counted:
		_full_counted = TcgStats.full_board(stats, _mirror, _side)
	_screen.set_timer(float(args[4]), float(_db.get("rules")["fuse_seconds"]), int(_mirror.get("current")) == _side and not _watching)


func _result(winner: int, peers: Array, names: Array, me: int) -> void:
	var side := peers.find(me)
	var text := "A draw - both leaders fell."
	if side >= 0 and winner != 2:
		collection.call("record_result", winner == side, String(names[1 - side]), _deck_name, false)
		if _mirror != null:
			TcgStats.match_end(stats, _mirror, side, false, "", int((collection.get("record") as Dictionary)["best_streak"]))
		var mats: Dictionary = DataStore.load_json("res://data/tcg/mats.json")
		var earned: Array = MatBook.milestones(collection, mats)
		if winner == side:
			var prize := int(_cfg["prize_vs_player"])
			_wallet.call("add", prize)
			text = "You win!  +%d chips" % prize
		else:
			text = "%s wins this one." % names[winner]
		for m: Variant in earned:
			text += "\nNew play mat: %s!" % mats["mats"][String(m)]["name"]
		finished.emit()
	elif winner != 2:
		text = "%s wins." % names[winner]
	_screen.show_result(text)
	_mirror = null
	_mats_shown = false
	_watching = side < 0
