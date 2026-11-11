# Purpose: developer check of the casino table flows without clicking: plays blackjack rounds with random actions and roulette spins through game/casino_games.gd on a stub player/HUD, and checks the wallet arithmetic after each round. Writes tools/casino_flow_check.log and quits. Run scene tools/casino_flow_check.tscn.
# Dependencies: game/casino_room.gd, game/casino_games.gd, core/wallet.gd, core/data_store.gd.
extends Node

const CasinoRoom = preload("res://game/casino_room.gd")
const CasinoGames = preload("res://game/casino_games.gd")
const Wallet = preload("res://core/wallet.gd")
const DataStore = preload("res://core/data_store.gd")

class FakePlayer extends CharacterBody3D:
	var controls_enabled := true

	func look_at_point(_p: Vector3) -> void:
		pass


class FakeHud extends Control:
	var notes: PackedStringArray = []

	func notice(text: String) -> void:
		notes.append(text)


var _log := PackedStringArray()


func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	var casino := CasinoRoom.build(world, Vector3.ZERO)
	var wallet := Wallet.new(5000)
	var layer := CanvasLayer.new()
	add_child(layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var games: CasinoGames = CasinoGames.new()
	add_child(games)
	games.setup(wallet, DataStore.load_json("res://data/casino.json"), casino, layer, FakePlayer.new(), FakeHud.new(), rng)
	games.open("blackjack")
	var bad := 0
	for round_index in 8:
		var before := wallet.balance
		await games._on_deal(10)
		var guard := 0
		while games._bj.phase == "player" and guard < 12:
			guard += 1
			var o: Dictionary = games._bj.options(wallet.balance)
			var pick := "stand"
			if o["split"] and rng.randf() < 0.5:
				pick = "split"
			elif o["double"] and rng.randf() < 0.3:
				pick = "double"
			elif o["hit"] and BlackjackTotal.of(games._bj.hand_cards(games._bj.active)) < 15:
				pick = "hit"
			await games._on_action(pick)
		var expected: int = before - games._bj.staked + games._bj.returned
		var ok: bool = wallet.balance == expected and games._bj.phase == "done"
		if not ok:
			bad += 1
		_log.append("bj round %d: phase %s staked %d returned %d balance %d expected %d %s" % [round_index, games._bj.phase, games._bj.staked, games._bj.returned, wallet.balance, expected, "ok" if ok else "MISMATCH"])
	games._leave()
	games.open("roulette")
	for spin_index in 2:
		var before := wallet.balance
		var bets := {"red": 10, "straight:17": 5, "dozen:2": 10}
		games._on_spin(bets)
		await games._rt_table.finished
		await get_tree().process_frame
		var back: int = games._rt_number
		var expected := before - 25 + _settle(bets, back)
		var ok2: bool = wallet.balance == expected
		if not ok2:
			bad += 1
		_log.append("roulette spin %d: number %d balance %d expected %d %s" % [spin_index, back, wallet.balance, expected, "ok" if ok2 else "MISMATCH"])
	_log.append("done, problems: %d" % bad)
	var f := FileAccess.open("res://tools/casino_flow_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _settle(bets: Dictionary, number: int) -> int:
	const Roulette = preload("res://core/roulette_rules.gd")
	return Roulette.settle(bets, number)


class BlackjackTotal:
	static func of(cards: Array[int]) -> int:
		const Blackjack = preload("res://core/blackjack_rules.gd")
		return Blackjack.total_of(cards)
