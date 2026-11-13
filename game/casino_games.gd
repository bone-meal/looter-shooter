# Purpose: runs the blackjack and roulette tables: sitting down (free the mouse, face the table), the overlay screens, dealing animation order, the wallet (stake spent up front, winnings paid at the end) and the result messages. Rules are in core/, drawing in the table nodes.
# Dependencies: core/blackjack_rules.gd, core/roulette_rules.gd, core/wallet.gd, game/blackjack_table.gd, game/roulette_table.gd, game/blackjack_screen.gd, game/roulette_screen.gd, game/staff_crew.gd, game/player.gd (controls_enabled, look_at_point), game/player_hud.gd (notice).
extends Node

const Blackjack = preload("res://core/blackjack_rules.gd")
const Roulette = preload("res://core/roulette_rules.gd")
const Wallet = preload("res://core/wallet.gd")
const BlackjackTable = preload("res://game/blackjack_table.gd")
const RouletteTable = preload("res://game/roulette_table.gd")
const BlackjackScreen = preload("res://game/blackjack_screen.gd")
const RouletteScreen = preload("res://game/roulette_screen.gd")
const StaffCrew = preload("res://game/staff_crew.gd")

signal round_finished  # coins changed: the session saves the profile
signal left

const SIT_RANGE := 2.6

var _wallet: Wallet
var _cfg: Dictionary
var _rng: RandomNumberGenerator
var _player: CharacterBody3D
var _hud: Control
var _crew: StaffCrew
var _bj_table: BlackjackTable
var _rt_table: RouletteTable
var _bj_dealer: Node3D
var _rt_dealer: Node3D
var _bj_screen := BlackjackScreen.new()
var _rt_screen := RouletteScreen.new()


# The two screens join the tree in `setup`, which now only runs when the club is built (round 5): a session that never
# went there would leave them behind as orphans at exit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for screen: Variant in [_bj_screen, _rt_screen]:  # (Variant: at exit they may be freed already)
			if is_instance_valid(screen) and (screen as Node).get_parent() == null:
				(screen as Node).free()
var _bj := Blackjack.new()
var _current := ""  # "", "blackjack" or "roulette"
var _bj_shown: Array[int] = [0, 0]
var _bj_dealer_shown := 0
var _bj_spent := 0
var _bj_hole_hidden := false
var _rt_bets: Dictionary = {}
var _rt_number := 0


# casino = the dictionary returned by game/casino_room.gd; layer = a CanvasLayer for the overlays.
func setup(wallet: Wallet, cfg: Dictionary, casino: Dictionary, layer: CanvasLayer, player: CharacterBody3D, hud: Control, rng: RandomNumberGenerator) -> void:
	_wallet = wallet
	_cfg = cfg
	_rng = rng
	_player = player
	_hud = hud
	_crew = casino["crew"]
	_bj_table = casino["blackjack"]
	_rt_table = casino["roulette"]
	_bj_dealer = casino["bj_dealer"]
	_rt_dealer = casino["rt_dealer"]
	var bj_cfg: Dictionary = cfg["blackjack"]
	_bj = Blackjack.new(int(bj_cfg["decks"]), float(bj_cfg["reshuffle_at"]))
	_bj.rng.randomize()
	layer.add_child(_bj_screen)
	layer.add_child(_rt_screen)
	_bj_screen.setup(bj_cfg)
	_rt_screen.setup(cfg["roulette"])
	_bj_screen.deal_requested.connect(_on_deal)
	_bj_screen.action_requested.connect(_on_action)
	_bj_screen.closed.connect(_leave)
	_rt_screen.spin_requested.connect(_on_spin)
	_rt_screen.closed.connect(_leave)
	_rt_table.finished.connect(_on_roulette_finished)
	_rt_screen.bets_changed.connect(_rt_table.show_bets)
	_bj_screen.bet_changed.connect(_on_bj_bet_chosen)


func is_open() -> bool:
	return _current != ""


# Esc: closes the table if no round is running. Always consumes the key while seated.
func request_close() -> void:
	if _current == "blackjack":
		_bj_screen.close()
	elif _current == "roulette":
		_rt_screen.close()


# "blackjack", "roulette" or "" depending on which table the player is standing at.
func spot_near(pos: Vector3) -> String:
	if _bj_table == null:
		return ""  # the club is not built yet (game_session `_build_club`)
	if _is_near(_bj_table, pos):
		return "blackjack"
	if _is_near(_rt_table, pos):
		return "roulette"
	return ""


func _is_near(table: Node3D, pos: Vector3) -> bool:
	return Vector2(pos.x - table.global_position.x, pos.z - table.global_position.z).length() < SIT_RANGE and absf(pos.x - table.global_position.x) < 2.2


func open(which: String) -> void:
	_current = which
	var refill: Dictionary = _cfg["free_refill"]
	if _wallet.balance < int(refill["below"]):
		_wallet.balance = int(refill["to"])
		_hud.call("notice", "The casino tops you up to %d free chips." % _wallet.balance)
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if which == "blackjack":
		_player.look_at_point(_bj_table.global_position + Vector3(0, 0.95, 0))
		_bj_screen.open(_wallet.balance)
		_on_bj_bet_chosen(_bj_screen.current_bet())
	else:
		_player.look_at_point(_rt_table.global_position + Vector3(-0.8, 0.95, 0))
		_rt_screen.open(_wallet.balance)
		_rt_table.show_bets(_rt_screen.current_bets())


func _leave() -> void:
	_current = ""
	_bj_table.show_bets([])
	_rt_table.show_bets({})
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_bj_table.clear_cards()
	left.emit()


# ---------------------------------------------------------------- blackjack

func _on_bj_bet_chosen(amount: int) -> void:
	var shown: Array[int] = [amount]
	_bj_table.show_bets(shown)


func _on_deal(bet: int) -> void:
	if not _wallet.spend(bet):
		return
	_bj_spent = bet
	_bj.start(bet)
	_bj_screen.set_busy(true)
	_bj_table.clear_cards()
	await get_tree().create_timer(0.45).timeout
	_bj_shown = [0, 0]
	_bj_dealer_shown = 0
	_bj_hole_hidden = true
	_crew.deal_flick(_bj_dealer)
	_place_player_card(0)
	await get_tree().create_timer(0.35).timeout
	_place_dealer_card(true)
	await get_tree().create_timer(0.35).timeout
	_place_player_card(0)
	await get_tree().create_timer(0.35).timeout
	_place_dealer_card(false)
	await get_tree().create_timer(0.5).timeout
	if _bj.phase == "done":
		await _bj_finish()
	else:
		_bj_update("Your move.")


func _place_player_card(hand: int) -> void:
	var cards := _bj.hand_cards(hand)
	var idx := _bj_shown[hand]
	_bj_table.place("p%d:%d" % [hand, idx], cards[idx], true)
	_bj_shown[hand] = idx + 1


# A dealer card; face_up false = the hole card, dealt face down.
func _place_dealer_card(face_up: bool) -> void:
	var idx := _bj_dealer_shown
	_bj_table.place("d:%d" % idx, _bj.dealer[idx], face_up)
	_bj_dealer_shown = idx + 1


func _on_action(action: String) -> void:
	_bj_screen.set_busy(true)
	var hands_before := _bj.hands.size()
	var active_before := _bj.active
	var refused := false
	match action:
		"hit":
			_bj.hit()
		"stand":
			_bj.stand()
		"double":
			if _wallet.spend(int(_bj.hands[_bj.active]["bet"])):
				_bj.double_down()
			else:
				refused = true
		"split":
			if _wallet.spend(int(_bj.hands[0]["bet"])):
				_bj.split()
			else:
				refused = true
	if refused:
		_bj_update("Not enough chips for that.")
		return
	if _bj.hands.size() != hands_before:
		# split: re-lay both hands from the shoe
		_bj_table.clear_cards(true)
		var keep_dealer := _bj.dealer.size()
		_bj_shown = [0, 0]
		_bj_dealer_shown = 0
		_place_dealer_card(true)
		_place_dealer_card(false)
		_bj_dealer_shown = keep_dealer
		for h in 2:
			for _i in _bj.hand_cards(h).size():
				_place_player_card(h)
	else:
		while _bj_shown[active_before] < _bj.hand_cards(active_before).size():
			_place_player_card(active_before)
	_crew.deal_flick(_bj_dealer)
	await get_tree().create_timer(0.6).timeout
	if _bj.phase == "player":
		_bj_update("Your move.")
	else:
		await _bj_finish()


func _bj_finish() -> void:
	# reveal the hole card, then the dealer draws until the rules stop him
	_bj_table.reveal("d:1")
	_bj_hole_hidden = false
	await get_tree().create_timer(0.6).timeout
	while _bj.phase == "dealer":
		var more := _bj.dealer_step()
		while _bj_dealer_shown < _bj.dealer.size():
			_place_dealer_card(true)
			await get_tree().create_timer(0.6).timeout
		if not more:
			break
	var lines: PackedStringArray = []
	for r in _bj.results:
		lines.append(_outcome_text(String(r["outcome"]), int(r["returned"])))
	_wallet.add(_bj.returned)
	var net := _bj.returned - _bj.staked
	var message := "  |  ".join(lines)
	message += "     (%s%d chips)" % ["+" if net >= 0 else "", net]
	_bj_update(message, false)
	_on_bj_bet_chosen(_bj_screen.current_bet())
	round_finished.emit()


func _outcome_text(outcome: String, returned: int) -> String:
	match outcome:
		Blackjack.OUTCOME_BLACKJACK:
			return "BLACKJACK +%d" % returned
		Blackjack.OUTCOME_WIN:
			return "Win +%d" % returned
		Blackjack.OUTCOME_PUSH:
			return "Push"
		Blackjack.OUTCOME_BUST:
			return "Bust"
	return "Lose"


func _bj_update(message: String, in_round: bool = true) -> void:
	var totals := ""
	for i in _bj.hands.size():
		var cards := _bj.hand_cards(i)
		if _bj.hands.size() > 1:
			totals += "Hand %d: %d   " % [i + 1, Blackjack.total_of(cards)]
		else:
			totals += "You: %d   " % Blackjack.total_of(cards)
	if _bj_hole_hidden:
		var up: Array[int] = [_bj.dealer[0]]
		totals += "Dealer shows: %d" % Blackjack.total_of(up)
	else:
		totals += "Dealer: %d" % Blackjack.total_of(_bj.dealer)
	var stakes: Array[int] = []
	if in_round:
		for h in _bj.hands:
			stakes.append(int(h["bet"]))
	_bj_table.show_bets(stakes)
	_bj_screen.set_busy(false)
	_bj_screen.show_state(_wallet.balance, in_round and _bj.phase == "player", totals, message, _bj.options(_wallet.balance) if in_round else {})


# ---------------------------------------------------------------- roulette

func _on_spin(bets: Dictionary) -> void:
	var total := 0
	for k: String in bets:
		total += int(bets[k])
	if total <= 0 or not _wallet.spend(total):
		return
	_rt_bets = bets
	_rt_screen.set_busy(true)
	_rt_screen.show_state(_wallet.balance, "No more bets... the wheel is spinning.")
	_crew.deal_flick(_rt_dealer)
	_rt_number = Roulette.spin(_rng)
	_rt_table.spin_to(_rt_number)


func _on_roulette_finished() -> void:
	var number := _rt_number
	var back := Roulette.settle(_rt_bets, number)
	var total := 0
	for k: String in _rt_bets:
		total += int(_rt_bets[k])
	_wallet.add(back)
	var net := back - total
	var verdict := "No win this time."
	if back > 0:
		verdict = "You win %d (net %s%d)" % [back, "+" if net >= 0 else "", net]
	var message := "%d %s.  %s" % [number, Roulette.color_of(number), verdict]
	_rt_screen.set_busy(false)
	_rt_screen.show_state(_wallet.balance, message)
	round_finished.emit()

