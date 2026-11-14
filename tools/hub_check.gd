# Purpose: developer check of the safe hub's rules (core/hub_rules.gd, locked diary/DECISIONS_HUB.md): the countdown
# sends the group, the button stops it for good, ready = 5 s of F on the stage, F again or stepping off un-readies,
# everyone in the hub counts, leaving the hub stops counting, the stage and hub areas. Log tools/hub_check.log
# (HUB_CHECK_DONE problems=n).
# Dependencies: core/hub_rules.gd, data/hub.json.
extends Node

const HubRules = preload("res://core/hub_rules.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hub.json"))
	var r := HubRules.new(cfg)
	r.join(1)
	var gone := false
	for i in 59:
		gone = gone or r.tick(1.0, {})
	_say("59 s in, nobody has gone yet (%.0f s left)" % r.left, not gone and is_equal_approx(r.left, 1.0))
	_say("at 60 s the group goes", r.tick(1.0, {}) and r.launched)
	r = HubRules.new(cfg)
	r.join(1)
	r.join(2)
	r.tick(10.0, {})
	r.press_button()
	for i in 100:
		r.tick(1.0, {})
	_say("after the button the countdown stops for good (%.0f s left after 100 s)" % r.left, not r.launched and is_equal_approx(r.left, 50.0))
	r.tick(6.0, {1: true})
	_say("holding F off the stage does nothing", not bool(r.players[1]["ready"]))
	r.set_stage(1, true)
	r.tick(4.0, {1: true})
	_say("4 s on the stage is not enough", not bool(r.players[1]["ready"]))
	r.tick(1.0, {1: true})
	_say("5 s on the stage = ready (1/2)", bool(r.players[1]["ready"]) and r.ready_count() == 1)
	r.tick(1.0, {})
	r.tick(0.1, {1: true})
	_say("pressing F again un-readies", not bool(r.players[1]["ready"]))
	r.tick(6.0, {1: true})
	_say("and holding on does not ready again until F is let go", not bool(r.players[1]["ready"]))
	r.tick(0.1, {})
	r.tick(5.0, {1: true})
	r.set_stage(1, false)
	_say("stepping off the stage un-readies", not bool(r.players[1]["ready"]))
	r.set_stage(1, true)
	r.tick(0.1, {})
	r.tick(5.0, {1: true})
	_say("one ready, one idle: the group waits (AFK players hold it)", not r.launched and r.ready_count() == 1)
	r.set_stage(2, true)
	var went := r.tick(5.0, {1: true, 2: true})
	_say("both ready: the group goes", went and r.launched)
	r = HubRules.new(cfg)
	r.join(1)
	r.join(2)
	r.press_button()
	r.set_stage(1, true)
	r.tick(5.0, {1: true})
	r.leave(2)
	_say("a player who leaves the hub (painting, island) no longer counts", r.tick(0.1, {1: true}) and r.launched)
	_say("the stage area: on it at (0, -11), not at (0, 0)", r.on_stage(0.0, -11.0) and not r.on_stage(0.0, 0.0))
	_say("the hub area: hall and trophy room, not outside", r.inside(0.0, 0.0) and r.inside(-30.0, 5.0) and not r.inside(40.0, 0.0))
	var v := r.view()
	_say("the view has what the HUD shows", v.has("left") and v.has("button") and v.has("ready") and v.has("total") and v.has("players"))
	_finish()


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("HUB_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/hub_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
