# Purpose: developer check of the pachinko board: simulates many balls per aim, logs pocket distribution and return to player, and checks balls never get stuck. Writes tools/pachinko_check.log and quits. Run scene tools/pachinko_check.tscn.
# Dependencies: core/pachinko_sim.gd, core/data_store.gd, data/pachinko.json.
extends Node

const Sim = preload("res://core/pachinko_sim.gd")
const DataStore = preload("res://core/data_store.gd")

var _log := PackedStringArray()


func _ready() -> void:
	var data: Dictionary = DataStore.load_json("res://data/pachinko.json")
	for aim in [0.0, 0.5, 1.0]:
		_run(data, aim, 1500)
	var f := FileAccess.open("res://tools/pachinko_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _run(data: Dictionary, aim: float, balls: int) -> void:
	var sim := Sim.new(data, 777)
	var hist: Array[int] = []
	hist.resize(sim.bins)
	hist.fill(0)
	var launched := 0
	var landed_total := 0
	var paid := 0
	var steps := 0
	while landed_total < balls and steps < 2000000:
		steps += 1
		if launched < balls and sim.count < 30 and steps % 6 == 0:
			if sim.launch(aim):
				launched += 1
		for p in sim.step(1.0 / 120.0):
			hist[p] += 1
			landed_total += 1
			paid += sim.payout(p)
	var spent := balls * sim.ball_cost
	_log.append("aim %.2f: landed %d of %d, paid %d on %d staked = return %.4f, pockets %s, sim seconds %.0f" % [aim, landed_total, balls, paid, spent, float(paid) / float(spent), str(hist), float(steps) / 120.0])
