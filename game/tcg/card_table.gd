# Purpose: the House Dealer's card table on the club beach (build step 5, first playable): F to sit (mouse freed, face
# the table), pick a starter deck (the dealer plays another one), coin toss, mulligan, the match against the House
# Dealer (core/tcg/ai_player.gd, one move every `dealer_pause` seconds), the turn timer (75 s, fuse at 15 s; time out =
# end turn), Esc = "Concede?" then concede, the log, and 20 chips for a win. The first sit-down gives the chosen
# starter deck + 3 packs (core/tcg/collection.gd); later the player picks one of their own deck slots. The House
# Dealer's record is kept apart. One local match; online is step 13.
# Dependencies: core/tcg/card_db.gd, core/tcg/match_state.gd, core/tcg/ai_player.gd, core/tcg/event_text.gd,
# core/wallet.gd, core/tcg/collection.gd, game/tcg/table_screen.gd, game/tcg/beach_table.gd, game/staff_crew.gd (deal_flick),
# game/player.gd (controls_enabled, look_at_point), game/player_hud.gd (notice), data/tcg/table.json, starters.json.
extends Node

const CardDb = preload("res://core/tcg/card_db.gd")
const MatchState = preload("res://core/tcg/match_state.gd")
const AiPlayer = preload("res://core/tcg/ai_player.gd")
const EventText = preload("res://core/tcg/event_text.gd")
const Wallet = preload("res://core/wallet.gd")
const TableScreen = preload("res://game/tcg/table_screen.gd")
const TableView = preload("res://game/tcg/table_view.gd")
const CardBake = preload("res://game/tcg/card_bake.gd")
const DataStore = preload("res://core/data_store.gd")
const Collection = preload("res://core/tcg/collection.gd")
const MatBook = preload("res://core/tcg/mat_book.gd")
const TcgStats = preload("res://core/tcg/tcg_stats.gd")

signal finished  # a match ended (chips may have changed): the session saves
signal left

const ME := 0
const DEALER := 1

var autopilot := false  # dev runs: the AI plays our side too
var graphics := "high"  # graphics tier id, set by the session: how many 3D figures stand on the table
var stats: RefCounted  # the combat record (core/stat_book.gd), set by the session: the card game's achievements
var _full_counted := false  # the full-mat reading is taken once a match
var match_state: RefCounted  # MatchState, or null between matches
var collection: RefCounted  # core/tcg/collection.gd (the session owns it and saves it)
var _db: RefCounted
var _view: Node3D  # game/tcg/table_view.gd
var _cfg: Dictionary
var _starters: Dictionary
var _wallet: Wallet
var _player: CharacterBody3D
var _hud: Control
var _table: Node3D
var _dealer: Node3D
var _crew: Node
var _screen: Control  # game/tcg/table_screen.gd, made in setup (a session that never visits the club makes none)
var _seated := false
var _deck := ""
var _known: Dictionary = {}  # uid -> card id, for the log
var _wait := 0.0
var _turn_left := 0.0
var _who: Array = ["You", "Dealer"]
var _played_cards: Array = []  # the deck list of the match in progress (for the House Dealer record)
var _rng := RandomNumberGenerator.new()  # which deck the dealer plays, the match seed


# Called when the club is built. casino = game/casino_room.gd's dictionary ("card_table", "card_dealer", "crew").
func setup(wallet: Wallet, casino: Dictionary, layer: CanvasLayer, player: CharacterBody3D, hud: Control, owned: RefCounted) -> void:
	_wallet = wallet
	collection = owned
	_player = player
	_hud = hud
	_table = casino["card_table"]
	_dealer = casino["card_dealer"]
	_crew = casino["crew"]
	_cfg = DataStore.load_json("res://data/tcg/table.json")
	_starters = DataStore.load_json("res://data/tcg/starters.json")["starters"]
	_db = CardDb.from_files()
	_rng.randomize()
	var npc: Dictionary = (DataStore.load_json("res://data/npcs.json")["npcs"] as Dictionary).get(String(_cfg["house"]["dealer_npc"]), {})
	_who = ["You", String(npc.get("name", "Dealer"))]
	_screen = TableScreen.new()
	layer.add_child(_screen)
	_screen.set_prize(int(_cfg["prize_vs_ai"]))
	_screen.deck_chosen.connect(_start)
	_screen.mulligan_chosen.connect(_on_mulligan)
	_screen.intent.connect(_on_intent)
	_screen.again.connect(_open_pick)
	_screen.leave.connect(_leave)
	var view := TableView.new()  # the 3D cards on the table (step 12); the screen keeps the rules of clicking
	view.visible = false
	var bake := CardBake.new()
	bake.db = _db
	view.add_child(bake)
	view.bake = bake
	_table.add_child(view)
	_screen.set("view3d", view)
	_view = view


func is_open() -> bool:
	return _seated


func spot_near(pos: Vector3) -> bool:
	if _table == null:
		return false
	return Vector2(pos.x - _table.global_position.x, pos.z - _table.global_position.z).length() < float(_cfg["sit_range"])


func open() -> void:
	_seated = true
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player.look_at_point(_table.call("look_point"))
	_hud.visible = false  # the gun HUD under the card table is clutter
	_open_pick()


# Esc while seated: no match = leave; a match = "Concede?", and Esc again concedes (locked). Always consumes the key.
func request_close() -> void:
	if match_state == null or match_state.get("phase") == "over":
		_leave()
	elif _screen.asking_concede():
		_screen.ask_concede(false)
		match_state.call("concede", ME)
		_after_move()
	else:
		_screen.ask_concede(true)


# Developer runs (tools/dev_boot.gd "!tcg"): sit down and pick a deck at once.
func dev_start(deck_id: String, auto: bool) -> void:
	autopilot = auto
	if not _seated:
		open()
	_screen.visible = true
	_start(deck_id)


# Developer runs: our side makes the move the AI would pick, through the same path as a click ("!tcg move"), or keeps
# the opening hand ("!tcg keep").
func dev_move() -> void:
	if match_state != null and match_state.get("phase") == "mulligan":
		_on_mulligan([])
	elif match_state != null and match_state.get("phase") == "play" and int(match_state.get("current")) == ME:
		_on_intent(AiPlayer.next_move(match_state, ME))


func _open_pick() -> void:
	match_state = null
	var leaders: Dictionary = _db.get("leaders")
	var choices: Array = []
	if String(collection.get("starter")) == "":  # the very first sit-down: pick a starter deck to keep
		for deck_id: String in _starters:
			var d: Dictionary = _starters[deck_id]
			choices.append({"key": "starter:" + deck_id, "label": "%s  -  %s (%s)" % [d["name"], (leaders[String(d["leader"])] as Dictionary)["name"], d["style"]],
				"leader": d["leader"], "name": d["name"], "sub": String(d["style"]).capitalize()})
		_screen.open_pick("You got me Lobster?  -  pick your starter deck", "It is yours to keep, with %d packs to open." % Collection.START_PACKS, choices)
		return
	var ready: Dictionary = collection.call("playable", _db)
	for slot: int in ready:
		var d: Dictionary = ready[slot]
		choices.append({"key": "slot:%d" % slot, "label": "%s  -  %s" % [d["name"], (leaders[String(d["leader"])] as Dictionary)["name"]],
			"leader": d["leader"], "name": d["name"], "sub": (leaders[String(d["leader"])] as Dictionary)["name"]})
	_screen.open_pick("You got me Lobster?  -  pick your deck", "" if not choices.is_empty() else "None of your deck slots is a full, legal deck you own. Build one in the binder (P).", choices)


# key = "starter:<id>" (first sit-down) or "slot:<n>" (one of the player's deck slots), or a starter id (dev runs).
func _start(key: String) -> void:
	var mine: Dictionary = {}
	if key.begins_with("starter:"):
		var sid := key.get_slice(":", 1)
		collection.call("give_starter", sid, _starters[sid], "standard")
		finished.emit()  # save the gift at once
		mine = _starters[sid]
	elif key.begins_with("slot:"):
		mine = (collection.get("decks") as Array)[int(key.get_slice(":", 1))]
	else:
		mine = _starters[key]
	_deck = String(mine.get("name", ""))
	var others: Array = _starters.keys()
	others.erase(_starter_of(mine))
	var theirs: Dictionary = _starters[others[_rng.randi_range(0, others.size() - 1)]]
	_played_cards = (mine["cards"] as Array).duplicate()
	match_state = MatchState.new(_db, [{"leader": mine["leader"], "cards": mine["cards"]}, {"leader": theirs["leader"], "cards": theirs["cards"]}], _rng.randi())
	_screen.finishes = [collection.call("best_finishes", mine["cards"]), {}]  # ME = side 0; the dealer plays plain cards
	_view.set("graphics", graphics)
	_full_counted = false
	if collection != null:  # each half of the table shows its player's mat (the House Dealer's from data/tcg/table.json)
		var mats: Dictionary = DataStore.load_json("res://data/tcg/mats.json")
		_table.call("set_mats", MatBook.current(collection, mats), String((_cfg["house"] as Dictionary).get("mat", mats.get("default", ""))))
	_known = {}
	_turn_left = float(_db.get("rules")["turn_seconds"])
	match_state.call("mulligan", DEALER, AiPlayer.mulligan(match_state, DEALER))
	_crew.call("deal_flick", _dealer)
	if autopilot:
		match_state.call("mulligan", ME, AiPlayer.mulligan(match_state, ME))
	_after_move()


func _on_mulligan(indices: Array) -> void:
	if match_state != null:
		match_state.call("mulligan", ME, indices)
		_after_move()


func _on_intent(move: Dictionary) -> void:
	if match_state == null or autopilot:
		return
	var why := AiPlayer.do_move(match_state, ME, move)
	if why != "":
		_screen.flash(why)
	_after_move()


# Turns what happened into log lines, redraws, and settles the end of the match.
func _after_move() -> void:
	var lines: PackedStringArray = []
	var events: Array = match_state.call("take_log")
	for e: Dictionary in events:
		if String(e["e"]) == "summon":
			_known[int(e["uid"])] = String(e["card"])
		if String(e["e"]) == "turn":
			_turn_left = float(_db.get("rules")["turn_seconds"])
			_wait = float(_cfg["dealer_pause"])
		lines.append(EventText.line(_db, e, ME, _known, _who))
	_screen.add_log(lines)
	_screen.add_events(events)
	_screen.show_match(match_state, ME, _who)
	if not _full_counted:
		_full_counted = TcgStats.full_board(stats, match_state, ME)
	if match_state.get("phase") == "over":
		_finish(int(match_state.get("winner")))


# The starter id whose 20 cards and leader this deck is exactly ("" for a deck of the player's own making).
func _starter_of(deck: Dictionary) -> String:
	for sid: String in _starters:
		var s: Dictionary = _starters[sid]
		var a: Array = (s["cards"] as Array).duplicate()
		var b: Array = (deck.get("cards", []) as Array).duplicate()
		a.sort()
		b.sort()
		if String(s["leader"]) == String(deck.get("leader", "")) and a == b:
			return sid
	return ""


func _finish(winner: int) -> void:
	if winner != 2:
		var mine: Dictionary = {"leader": (match_state.get("sides") as Array)[ME]["leader"], "cards": _played_cards}
		collection.call("record_result", winner == ME, String(_who[DEALER]), _deck, true, _starter_of(mine))
		TcgStats.match_end(stats, match_state, ME, true, _starter_of(mine), 0)
	var text := "A draw - both leaders fell."
	if winner == ME:
		var prize := int(_cfg["prize_vs_ai"])
		_wallet.add(prize)
		text = "You win!  +%d chips" % prize
	elif winner == DEALER:
		text = "%s wins this one." % _who[DEALER]
	_screen.show_result(text)
	finished.emit()


func _process(delta: float) -> void:
	if not _seated or match_state == null or match_state.get("phase") != "play":
		return
	var side := int(match_state.get("current"))
	if side == DEALER or autopilot:
		_wait -= delta
		if _wait > 0.0:
			return
		_wait = float(_cfg["dealer_pause"])
		var move := AiPlayer.next_move(match_state, side)
		if AiPlayer.do_move(match_state, side, move) != "":
			match_state.call("end_turn", side)  # a move it thought legal was refused: end rather than loop
		if side == DEALER and String(move["do"]) in ["play", "power"]:
			_crew.call("deal_flick", _dealer)
		_after_move()
		return
	_turn_left -= delta
	_screen.set_timer(_turn_left, float(_db.get("rules")["fuse_seconds"]), true)
	if _turn_left <= 0.0:
		match_state.call("end_turn", ME)
		_after_move()


func _leave() -> void:
	if match_state != null and match_state.get("phase") == "play":  # walking away mid-match = a loss (locked)
		match_state.call("concede", ME)
		_after_move()
	match_state = null
	_seated = false
	autopilot = false
	_screen.close()
	_hud.visible = true
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	left.emit()
