# Purpose: developer check of the inspect moves (core/inspect_moves.gd with data/inspect.json): every gun body, every
# knife type and the staff has its own move, no two are alike, each starts and ends at the hold and moves smoothly.
# Log tools/inspect_check.log (ends INSPECT_CHECK_DONE problems=n).
# Dependencies: core/inspect_moves.gd, core/data_store.gd, data/weapons.json, data/knives.json.
extends Node

const InspectMoves = preload("res://core/inspect_moves.gd")
const DataStore = preload("res://core/data_store.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var moves := InspectMoves.new()
	moves.setup(DataStore.load_json("res://data/inspect.json"))
	var wrong := moves.problems()
	_say("the data has no mistakes%s" % ("" if wrong.is_empty() else ": " + "; ".join(wrong)), wrong.is_empty())
	var wanted: Array = ["staff"]
	var weapons: Dictionary = DataStore.load_json("res://data/weapons.json")
	for body: String in (weapons["weapons"] if weapons.has("weapons") else weapons):
		wanted.append("gun:" + body)
	for kind: String in DataStore.load_json("res://data/knives.json")["knives"]:
		wanted.append("knife:" + kind)
	var missing := PackedStringArray()
	for id: String in wanted:
		if not moves.has(id):
			missing.append(id)
	_say("every gun body, knife type and the staff has a move (%d)%s" % [wanted.size(), "" if missing.is_empty() else ": NOT " + ", ".join(missing)], missing.is_empty())
	var alike := PackedStringArray()
	var ids: Array = moves.moves.keys()
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			if JSON.stringify(moves.moves[ids[a]]["keys"]) == JSON.stringify(moves.moves[ids[b]]["keys"]):
				alike.append("%s=%s" % [ids[a], ids[b]])
	_say("each one is different%s" % ("" if alike.is_empty() else ": " + ", ".join(alike)), alike.is_empty())
	var jumps := PackedStringArray()
	var longest := 0.0
	for id: String in ids:
		var end := moves.length(id)
		longest = maxf(longest, end)
		var before: Array = moves.pose(id, 0.0)
		var t := 0.0
		while t <= end + 0.02:
			var now: Array = moves.pose(id, t)
			var spin := (now[1] as Vector3) - (before[1] as Vector3)
			if t >= end - 0.02:  # the last frame drops whole turns: compare without them
				spin = Vector3(wrapf(spin.x, -180.0, 180.0), wrapf(spin.y, -180.0, 180.0), wrapf(spin.z, -180.0, 180.0))
			if ((now[0] as Vector3) - (before[0] as Vector3)).length() > 0.05 or absf(spin.x) > 40.0 or absf(spin.y) > 40.0 or absf(spin.z) > 40.0:
				jumps.append("%s at %.2f s" % [id, t])
				break
			before = now
			t += 1.0 / 60.0
	_say("no jumps between two frames at 60 fps (at most 5 cm and 40 degrees)%s" % ("" if jumps.is_empty() else ": " + ", ".join(jumps)), jumps.is_empty())
	var held: Array = moves.pose("gun:ak47", 0.0)
	var after: Array = moves.pose("gun:ak47", 99.0)
	_say("before it starts and after it ends the thing is at its hold (longest move %.1f s)" % longest, (held[0] as Vector3) == Vector3.ZERO and (after[1] as Vector3) == Vector3.ZERO and moves.pose("nothing", 1.0)[0] == Vector3.ZERO)

	_lines.append("INSPECT_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/inspect_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
