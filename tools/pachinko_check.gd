# Purpose: (polish1 item 75) measures the pachinko wall's return with the real core/pachinko_sim.gd and the rules of
# game/game_session.gd + game/pachinko_wall.gd (pocket payouts, fever gold balls, jackpot lamps and pot, tickets):
# chips back per chip staked, prize tickets per ball, how often the jackpot falls. Aim follows the sweeping marker.
# The jackpot is rare (~1 in 600-3000 balls): its rate is worked out from these landing shares in diary/DECISIONS_CASINO.md,
# this run shows the pocket return and tickets. Run: godot --headless --path . --script res://tools/pachinko_check.gd  (prints PACHINKO_CHECK lines).
# Dependencies: core/pachinko_sim.gd, core/data_store.gd, data/pachinko.json.
extends SceneTree

const Sim = preload("res://core/pachinko_sim.gd")
const DataStore = preload("res://core/data_store.gd")


func _init() -> void:
	var d: Dictionary = DataStore.load_json("res://data/pachinko.json")
	for aim_mode: String in ["sweep", "middle", "edge"]:
		_run(d, aim_mode, 3000)
	quit()


func _run(d: Dictionary, aim_mode: String, paid: int) -> void:
	var sim := Sim.new(d, 4242)
	var kinds: Array = d["pocket_kinds"]
	var fever: Dictionary = d["fever"]
	var jack: Dictionary = d["jackpot"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var staked := 0.0
	var back := 0.0
	var tickets := 0
	var jackpots := 0
	var pot := float(jack["seed"])
	var pot_paid := 0.0
	var launched := 0
	var lamps := 0
	var batch := 0
	while launched < paid or sim.count > 0:
		if launched < paid and sim.count < 4:
			var aim := 0.5
			if aim_mode == "sweep":
				aim = 0.5 + 0.5 * sin(rng.randf() * TAU)
			elif aim_mode == "edge":
				aim = 0.0
			sim.launch(aim)
			launched += 1
			staked += float(sim.ball_cost)
			pot += float(sim.ball_cost) * float(jack["share"])
		var landed := sim.step(0.05)
		for n in landed.size():
			var pocket := landed[n]
			back += float(sim.payout(pocket))
			var kind := String(kinds[pocket])
			if sim.landed_bonus[n] == batch and batch > 0:
				if kind == "jackpot" and lamps < int(jack["lamps"]):
					lamps += 1
					if lamps >= int(jack["lamps"]):
						jackpots += 1
						back += floorf(pot)
						pot_paid += floorf(pot)
						tickets += int(jack["tickets"])
						pot = float(jack["seed"])
			if kind == "ticket":
				tickets += int(d["tickets_per_pocket"])
			elif kind == "fever":
				batch = batch % 255 + 1
				lamps = 0
				var aim2 := 0.5 + 0.5 * sin(rng.randf() * TAU) if aim_mode == "sweep" else (0.5 if aim_mode == "middle" else 0.0)
				for i in int(fever["free_balls"]):
					sim.launch(clampf(aim2 + (float(i) - float(int(fever["free_balls"]) - 1) * 0.5) * 0.08, 0.0, 1.0), batch)
	print("PACHINKO_CHECK %s: %d balls  return %.3f (pot share of it %.3f)  tickets/ball %.3f  jackpot 1 in %s balls  avg pot %d" % [
		aim_mode, paid, back / staked, pot_paid / staked, float(tickets) / float(paid),
		str(roundi(float(paid) / float(jackpots))) if jackpots > 0 else "-", int(pot_paid / maxf(float(jackpots), 1.0))])
