# Purpose: (polish1 item 71) checks core/pool_sim.gd, core/pool_rules.gd and core/pool_ai.gd without a screen: the
# rack, follow / draw, a pot into a chosen pocket, side english off a cushion, breaks (spread, time, nothing off the
# table) and whole AI-against-AI games per house skill (shots per game, fouls, how games end).
# Run: godot --headless --path . --script res://tools/pool_check.gd  (prints POOL_CHECK lines, "problems n").
# Dependencies: core/pool_sim.gd, core/pool_rules.gd, core/pool_ai.gd, core/data_store.gd, data/pool.json.
extends SceneTree

const Sim = preload("res://core/pool_sim.gd")
const Rules = preload("res://core/pool_rules.gd")
const AI = preload("res://core/pool_ai.gd")
const DataStore = preload("res://core/data_store.gd")

var _problems := 0


func _init() -> void:
	var data: Dictionary = DataStore.load_json("res://data/pool.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sim := Sim.new(data)
	sim.rack(rng)
	var min_gap := 9.0
	for i in 16:
		for j in range(i + 1, 16):
			min_gap = minf(min_gap, sim.pos[i].distance_to(sim.pos[j]))
	_expect(min_gap >= 2.0 * sim.r - 0.0001, "rack overlaps (%.4f)" % min_gap)
	# follow and draw: cue 0.3 m behind a ball, straight
	for spin_y: float in [1.0, -1.0, 0.0]:
		_only(sim, {0: Vector2(-0.3, 0), 1: Vector2(0, 0)})
		sim.shoot(0.0, 0.25, Vector2(0, spin_y))
		sim.run_to_rest()
		print("POOL_CHECK spin %.0f: cue ends at x %.2f, object at x %.2f" % [spin_y, sim.pos[0].x, sim.pos[1].x])
		if spin_y > 0.0:
			_expect(sim.pos[0].x > 0.05, "follow should run on")
		elif spin_y < 0.0:
			_expect(sim.pos[0].x < -0.1, "draw should come back")
	# a pot into the corner pocket 5 (+x, +y)
	var target := Vector2(0.9, 0.4)
	var pocket: Vector2 = sim.pockets[5]
	var dir := (pocket - target).normalized()
	var ghost := target - dir * 2.0 * sim.r
	var cue := ghost - dir * 0.5
	_only(sim, {0: cue, 1: target})
	sim.shoot((ghost - cue).angle(), 0.2, Vector2.ZERO)
	sim.run_to_rest()
	_expect(sim.pocketed.size() > 0 and int(sim.pocketed[0][0]) == 1 and int(sim.pocketed[0][1]) == 5, "pot into pocket 5: %s" % str(sim.pocketed))
	# english: straight into the foot rail
	var ys: Array = []
	for sx: float in [1.0, -1.0]:
		_only(sim, {0: Vector2(0.6, 0)})
		sim.shoot(0.0, 0.12, Vector2(sx, 0))
		sim.run_to_rest()
		ys.append(sim.pos[0].y)
	print("POOL_CHECK english: right ends y %.2f, left ends y %.2f" % [ys[0], ys[1]])
	_expect(float(ys[0]) * float(ys[1]) < 0.0, "left / right english should bounce to different sides")
	# breaks
	var down := 0
	var t0 := Time.get_ticks_msec()
	for k in 10:
		sim.rack(rng)
		sim.shoot(rng.randf_range(-0.03, 0.03), 1.0, Vector2.ZERO)
		sim.run_to_rest()
		down += sim.pocketed.size()
		for e: Array in sim.pocketed:
			_expect(int(e[1]) >= 0, "a ball left the table on a break")
	print("POOL_CHECK 10 breaks: %.1f balls down a break, %d ms" % [float(down) / 10.0, Time.get_ticks_msec() - t0])
	# AI vs AI
	for ai: Dictionary in data["ai"]:
		var shots := 0
		var fouls := 0
		var games := 6
		var finished := 0
		var t1 := Time.get_ticks_msec()
		for g in games:
			sim.rack(rng)
			var rules := Rules.new()
			rules.start()
			var n := 0
			while rules.winner < 0 and n < 150:
				if rules.ball_in_hand:
					sim.place(0, AI.place_cue(sim, rules, rules.current))
				var shot: Dictionary = AI.choose(sim, rules, rules.current, ai, rng) if not rules.break_shot else {"angle": rng.randf_range(-0.03, 0.03), "power": 1.0, "spin": Vector2.ZERO, "called": -1}
				sim.shoot(float(shot["angle"]), float(shot["power"]), shot["spin"])
				sim.run_to_rest()
				var res := rules.judge(sim.first_hit, sim.pocketed, sim.rail_after_contact, sim.on_table, int(shot["called"]))
				if res["foul"] != "":
					fouls += 1
				if sim.on_table[0] == 0:
					sim.place(0, sim.head_spot()) or sim.place(0, sim.head_spot() + Vector2(0, 0.2))
				if bool(res["eight_respot"]):
					sim.place(8, sim.foot_spot()) or sim.place(8, sim.foot_spot() + Vector2(0.1, 0))
				n += 1
			shots += n
			if rules.winner >= 0:
				finished += 1
		print("POOL_CHECK ai %s: %d of %d games finished, %.1f shots a game, %.1f fouls a game, %d ms" % [ai["id"], finished, games, float(shots) / games, float(fouls) / games, Time.get_ticks_msec() - t1])
	print("POOL_CHECK problems %d" % _problems)
	quit()


func _only(sim: RefCounted, balls: Dictionary) -> void:
	for i in 16:
		sim.on_table[i] = 0
	for b: int in balls:
		sim.place(b, balls[b])


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_problems += 1
		print("POOL_CHECK PROBLEM " + what)
