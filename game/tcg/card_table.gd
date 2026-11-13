# Purpose: the House Dealer's card table on the club beach (build step 5, first playable): F to sit (mouse freed, face
# the table), pick a starter deck (the dealer plays another one), coin toss, mulligan, the match against the House
# Dealer (core/tcg/ai_player.gd, one move every `dealer_pause` seconds), the turn timer (75 s, fuse at 15 s; time out =
# end turn), Esc = "Concede?" then concede, the log, and 20 chips for a win. One local match; online is step 13.
# Dependencies: core/tcg/card_db.gd, core/tcg/match_state.gd, core/tcg/ai_player.gd, core/tcg/event_text.gd,
# core/wallet.gd, game/tcg/table_screen.gd, game/tcg/beach_table.gd, game/staff_crew.gd (deal_flick),
# game/player.gd (controls_enabled, look_at_point), game/player_hud.gd (notice), data/tcg/table.json, starters.json.
extends Node

const CardDb = preload("res://core/tcg/card_db.gd")
const MatchState = preload("res://core/tcg/match_state.gd")
const AiPlayer = preload("res://core/tcg/ai_player.gd")
const EventText = preload("res://core/tcg/event_text.gd")
const Wallet = preload("res://core/wallet.gd")
const TableScreen = preload("res://game/tcg/table_screen.gd")
const DataStore = preload("res://core/data_store.gd")

signal finished  # a match ended (chips may have changed): the session saves
signal left

const ME := 0
const DEALER := 1

var autopilot := false  # dev runs: the AI plays our side too
var match_state: RefCounted  # MatchState, or null between matches
var _db: RefCounted
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


# Called when the club is built. casino = game/casino_room.gd's dictionary ("card_table", "card_dealer", "crew").
func setup(wallet: Wallet, casino: Dictionary, layer: CanvasLayer, player: CharacterBody3D, hud: Control) -> void:
	_wallet = wallet
	_player = player
	_hud = hud
	_table = casino["card_table"]
	_dealer = casino["card_dealer"]
	_crew = casino["crew"]
	_cfg = DataStore.load_json("res://data/tcg/table.json")
	_starters = DataStore.load_json("res://data/tcg/starters.json")["starters"]
	_db = CardDb.from_files()
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
	_screen.open_pick(_starters, _db.get("leaders"))


func _start(deck_id: String) -> void:
	_deck = deck_id
	var others: Array = _starters.keys()
	others.erase(deck_id)
	var theirs: Dictionary = _starters[others[randi() % others.size()]]
	var mine: Dictionary = _starters[deck_id]
	match_state = MatchState.new(_db, [{"leader": mine["leader"], "cards": mine["cards"]}, {"leader": theirs["leader"], "cards": theirs["cards"]}], randi())
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
	for e: Dictionary in match_state.call("take_log"):
		if String(e["e"]) == "summon":
			_known[int(e["uid"])] = String(e["card"])
		if String(e["e"]) == "turn":
			_turn_left = float(_db.get("rules")["turn_seconds"])
			_wait = float(_cfg["dealer_pause"])
		lines.append(EventText.line(_db, e, ME, _known, _who))
	_screen.add_log(lines)
	_screen.show_match(match_state, ME, _who)
	if match_state.get("phase") == "over":
		_finish(int(match_state.get("winner")))


func _finish(winner: int) -> void:
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
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	left.emit()
