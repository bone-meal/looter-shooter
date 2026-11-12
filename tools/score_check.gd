# Purpose: developer check of the points rules (core/score_card.gd with data/points.json): what hits and kills pay,
# spending, the cap, the pause in Aurelind, saving, cleaning a row another machine sent, and the chalk digits of the
# round counter. Log tools/score_check.log (ends SCORE_CHECK_DONE problems=n).
# Dependencies: core/score_card.gd, core/data_store.gd, core/wave_state.gd, game/chalk_marks.gd.
extends Node

const ScoreCard = preload("res://core/score_card.gd")
const DataStore = preload("res://core/data_store.gd")
const WaveState = preload("res://core/wave_state.gd")
const ChalkMarks = preload("res://game/chalk_marks.gd")

var _lines := PackedStringArray()
var _problems := 0
var _pops: Array[int] = []


func _ready() -> void:
	var cfg: Dictionary = DataStore.load_json("res://data/points.json")
	var awards: Dictionary = cfg["awards"]
	var data_fine := int(cfg["max"]) > 0 and float(cfg["headshot"]["damage_mult"]) >= 1.0 and float(cfg["headshot"]["head_share"]) > 0.0 and float(cfg["headshot"]["head_share"]) < 0.5
	for key: String in ["hit", "kill", "headshot_kill", "melee_kill"]:
		data_fine = data_fine and awards.has(key) and int(awards[key]) > 0
	_say("data/points.json: hit %d, kill %d, headshot kill %d, melee kill %d, head = top %d %%, head damage x%.2f" % [int(awards["hit"]), int(awards["kill"]), int(awards["headshot_kill"]), int(awards["melee_kill"]), roundi(float(cfg["headshot"]["head_share"]) * 100.0), float(cfg["headshot"]["damage_mult"])], data_fine)

	var card := ScoreCard.new(cfg)
	card.earned.connect(func(amount: int) -> void: _pops.append(amount))
	card.spent.connect(func(amount: int) -> void: _pops.append(-amount))
	card.hit()
	card.hit()
	_say("two hits pay 20", card.points == 20 and card.kills == 0)
	card.kill()
	_say("a plain kill pays 60 more", card.points == 80 and card.kills == 1 and card.headshots == 0)
	card.blow = "headshot"
	card.kill()
	card.blow = ""
	_say("a headshot kill pays 100 and counts as a headshot", card.points == 180 and card.kills == 2 and card.headshots == 1)
	card.blow = "melee"
	card.kill()
	card.blow = ""
	_say("a melee kill pays 130", card.points == 310 and card.kills == 3 and card.headshots == 1)
	_say("the HUD heard every gain: %s" % str(_pops), _pops == [10, 10, 60, 100, 130])
	_say("500 cannot be paid from 310, and nothing changes", not card.spend(500) and card.points == 310)
	_say("250 can: 60 left", card.spend(250) and card.points == 60 and _pops[-1] == -250)
	_say("a price below zero is refused", not card.spend(-5) and card.points == 60)
	card.paused = true
	card.hit()
	card.kill()
	card.paused = false
	_say("paused (Aurelind): hits and kills pay and count nothing", card.points == 60 and card.kills == 3)
	card.give(int(cfg["max"]) * 2)
	_say("the cap holds: %d" % card.points, card.points == int(cfg["max"]))

	var again := ScoreCard.new(cfg)
	again.from_dict(JSON.parse_string(JSON.stringify(card.to_dict())))
	_say("saved and loaded: the points come back, the session numbers start at 0", again.points == card.points and again.kills == 0)
	again.from_dict({"points": -50})
	var low := again.points
	again.from_dict({"points": "lots"})
	var odd := again.points
	again.from_dict(null)
	_say("a save with nonsense in it gives 0 points", low == 0 and odd == 0 and again.points == 0)
	var row := ScoreCard.clean_row({"points": 1e12, "kills": -4, "headshots": "x", "downs": 2.0, "extra": 1}, int(cfg["max"]))
	_say("a row from another machine is cleaned: %s" % str(row), row == {"points": int(cfg["max"]), "kills": 0, "headshots": 0, "downs": 2, "revives": 0})
	_say("something that is no row at all gives zeros", ScoreCard.clean_row("hello", 100) == {"points": 0, "kills": 0, "headshots": 0, "downs": 0, "revives": 0})

	var waves := WaveState.new({"waves": [{"chaser": 3}, {"chaser": 2, "shooter": 1}], "max_alive": 2, "spawn_interval": 1.0, "wave_delay": 2.0})
	var first := waves.status()
	waves.update(0.0, 0)
	var waiting := waves.status()
	var sent := waves.update(5.0, 0)
	_say("waves: \"%s\" before the first, then %d left of wave %d / %d" % [waiting, waves.left(1), waves.wave_number(), waves.wave_count()], first == "" and waiting == "Wave 1 / 2 incoming" and sent == "chaser" and waves.left(1) == 3 and waves.wave_count() == 2 and waves.status() == "")

	var digits_fine := ChalkMarks.DIGITS.size() == 10
	for digit: Array in ChalkMarks.DIGITS:
		digits_fine = digits_fine and digit.size() >= 3
		for p: Vector2 in digit:
			digits_fine = digits_fine and p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.601
	_say("the ten chalk digits stay inside their box", digits_fine)

	_lines.append("SCORE_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/score_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
