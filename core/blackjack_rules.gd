# Purpose: blackjack rules for one player vs the dealer: 6-deck shoe, dealer stands on all 17, blackjack pays 3:2, double on any two cards, split once (split aces get one card), no insurance. Pure; the caller deducts/credits coins using `staked` and `returned`.
# Dependencies: none. Cards are ints 0..51: rank = card % 13 (0 = ace, 10..12 = J Q K), suit = card / 13.
extends RefCounted

const OUTCOME_BLACKJACK := "blackjack"
const OUTCOME_WIN := "win"
const OUTCOME_PUSH := "push"
const OUTCOME_LOSE := "lose"
const OUTCOME_BUST := "bust"

var shoe: Array[int] = []
var decks := 6
var reshuffle_at := 0.25
var rng := RandomNumberGenerator.new()

var hands: Array[Dictionary] = []  # {"cards": Array[int], "bet": int, "done": bool, "from_split": bool, "split_aces": bool, "doubled": bool}
var dealer: Array[int] = []
var active := 0  # index into hands
var phase := "idle"  # "idle", "player", "dealer", "done"
var staked := 0  # total coins the player put in this round
var results: Array[Dictionary] = []  # per hand once done: {"outcome", "returned"}
var returned := 0  # total coins handed back


func _init(deck_count: int = 6, reshuffle_fraction: float = 0.25) -> void:
	decks = deck_count
	reshuffle_at = reshuffle_fraction
	rng.randomize()
	_shuffle()


static func rank_of(card: int) -> int:
	return card % 13


static func suit_of(card: int) -> int:
	return floori(float(card) / 13.0)


# {"total": best total, "soft": an ace is counted as 11}
static func evaluate(cards: Array[int]) -> Dictionary:
	var total := 0
	var aces := 0
	for c in cards:
		var r := rank_of(c)
		if r == 0:
			aces += 1
			total += 1
		else:
			total += mini(r + 1, 10)
	var soft := false
	if aces > 0 and total + 10 <= 21:
		total += 10
		soft = true
	return {"total": total, "soft": soft}


static func total_of(cards: Array[int]) -> int:
	return int(evaluate(cards)["total"])


static func is_blackjack(cards: Array[int]) -> bool:
	return cards.size() == 2 and total_of(cards) == 21


func _shuffle() -> void:
	shoe.clear()
	for d in decks:
		for c in 52:
			shoe.append(c)
	for i in range(shoe.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := shoe[i]
		shoe[i] = shoe[j]
		shoe[j] = t


func _draw() -> int:
	if shoe.is_empty():
		_shuffle()
	return shoe.pop_back()


# Begins a round with `bet` coins staked. Deals two cards each; settles at once on a natural.
func start(bet: int) -> void:
	if float(shoe.size()) < float(decks * 52) * reshuffle_at:
		_shuffle()
	hands.clear()
	dealer.clear()
	results.clear()
	returned = 0
	staked = bet
	active = 0
	var p: Array[int] = []
	hands.append({"cards": p, "bet": bet, "done": false, "from_split": false, "split_aces": false, "doubled": false})
	p.append(_draw())
	dealer.append(_draw())
	p.append(_draw())
	dealer.append(_draw())
	phase = "player"
	if is_blackjack(p) or is_blackjack(dealer):
		hands[0]["done"] = true
		_settle()


func hand_cards(i: int) -> Array[int]:
	var c: Array[int] = []
	c.assign(hands[i]["cards"])
	return c


# Which actions are allowed on the active hand given the coins the player still has.
func options(coins_left: int) -> Dictionary:
	var o := {"hit": false, "stand": false, "double": false, "split": false}
	if phase != "player":
		return o
	var h: Dictionary = hands[active]
	if h["done"]:
		return o
	var cards := hand_cards(active)
	o["stand"] = true
	o["hit"] = not bool(h["split_aces"])
	o["double"] = cards.size() == 2 and coins_left >= int(h["bet"]) and not bool(h["split_aces"])
	o["split"] = cards.size() == 2 and hands.size() == 1 and _same_value(cards[0], cards[1]) and coins_left >= int(h["bet"])
	return o


func _same_value(a: int, b: int) -> bool:
	return mini(rank_of(a) + 1, 10) == mini(rank_of(b) + 1, 10)  # any two ten-value cards may split


func hit() -> void:
	if not options(1_000_000)["hit"]:
		return
	hands[active]["cards"].append(_draw())
	if total_of(hand_cards(active)) >= 21:
		_finish_hand()


func stand() -> void:
	if phase == "player" and not hands[active]["done"]:
		_finish_hand()


# Doubles the bet (caller deducts `hands[active].bet` more coins already counted in `staked`), takes one card, stands.
func double_down() -> void:
	if not options(1_000_000)["double"]:
		return
	var h: Dictionary = hands[active]
	staked += int(h["bet"])
	h["bet"] = int(h["bet"]) * 2
	h["doubled"] = true
	h["cards"].append(_draw())
	_finish_hand()


func split() -> void:
	if not options(1_000_000)["split"]:
		return
	var first: Dictionary = hands[0]
	var cards := hand_cards(0)
	var aces := rank_of(cards[0]) == 0
	var a: Array[int] = [cards[0], _draw()]
	var b: Array[int] = [cards[1], _draw()]
	staked += int(first["bet"])
	hands.clear()
	hands.append({"cards": a, "bet": first["bet"], "done": false, "from_split": true, "split_aces": aces, "doubled": false})
	hands.append({"cards": b, "bet": first["bet"], "done": false, "from_split": true, "split_aces": aces, "doubled": false})
	active = 0
	if aces or total_of(a) >= 21:
		_finish_hand()


func _finish_hand() -> void:
	hands[active]["done"] = true
	while active < hands.size() and hands[active]["done"]:
		active += 1
		if active < hands.size() and (bool(hands[active]["split_aces"]) or total_of(hand_cards(active)) >= 21):
			hands[active]["done"] = true
	if active >= hands.size():
		active = hands.size() - 1
		phase = "dealer"
		var any_live := false
		for i in hands.size():
			if total_of(hand_cards(i)) <= 21:
				any_live = true
		if not any_live:
			_settle()


# Dealer draws one card if the rules say so. Returns true if a card was drawn (call again), false when the dealer is finished and the round is settled.
func dealer_step() -> bool:
	if phase != "dealer":
		return false
	if total_of(dealer) < 17:
		dealer.append(_draw())
		return true
	_settle()
	return false


func _settle() -> void:
	phase = "done"
	results.clear()
	returned = 0
	var dealer_total := total_of(dealer)
	var dealer_bj := is_blackjack(dealer)
	for h in hands:
		var cards: Array[int] = []
		cards.assign(h["cards"])
		var bet := int(h["bet"])
		var total := total_of(cards)
		var outcome := OUTCOME_LOSE
		var back := 0
		if total > 21:
			outcome = OUTCOME_BUST
		elif is_blackjack(cards) and not bool(h["from_split"]):
			if dealer_bj:
				outcome = OUTCOME_PUSH
				back = bet
			else:
				outcome = OUTCOME_BLACKJACK
				back = bet + floori(float(bet) * 1.5)
		elif dealer_bj:
			outcome = OUTCOME_LOSE
		elif dealer_total > 21 or total > dealer_total:
			outcome = OUTCOME_WIN
			back = bet * 2
		elif total == dealer_total:
			outcome = OUTCOME_PUSH
			back = bet
		results.append({"outcome": outcome, "returned": back})
		returned += back
