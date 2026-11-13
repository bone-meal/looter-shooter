# Purpose: developer check of the crosshairs (core/crosshair_style.gd with data/crosshairs.json): the data has no
# mistakes, there are 30 different designs, every one survives its share code, broken codes are refused, and a saved
# style with nonsense in it is cleaned. Log tools/crosshair_check.log (ends CROSSHAIR_CHECK_DONE problems=n).
# Dependencies: core/crosshair_style.gd, core/data_store.gd.
extends Node

const CrosshairStyle = preload("res://core/crosshair_style.gd")
const DataStore = preload("res://core/data_store.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var styles := CrosshairStyle.new()
	styles.setup(DataStore.load_json("res://data/crosshairs.json"))
	var wrong := styles.problems()
	_say("the data has no mistakes%s" % ("" if wrong.is_empty() else ": " + "; ".join(wrong)), wrong.is_empty())
	_say("30 ready-made crosshairs (%d)" % styles.presets.size(), styles.presets.size() == 30)
	var alike := PackedStringArray()
	for a in styles.presets.size():
		for b in range(a + 1, styles.presets.size()):
			if styles.same(styles.preset(a), styles.preset(b)):
				alike.append("%d=%d" % [a, b])
	_say("no two of them are the same%s" % ("" if alike.is_empty() else ": " + ", ".join(alike)), alike.is_empty())
	var lost := PackedStringArray()
	var longest := 0
	for n in styles.presets.size():
		var code := styles.code_of(styles.preset(n))
		longest = maxi(longest, code.length())
		if not styles.same(styles.from_code(code), styles.preset(n)) or styles.preset_of(styles.from_code(code)) != n:
			lost.append(str(n))
	_say("every design comes back from its share code (longest code %d characters)%s" % [longest, "" if lost.is_empty() else ": NOT " + ", ".join(lost)], lost.is_empty())
	var odd := styles.preset(3)
	odd["gap"] = 7.3
	odd["red"] = 17.0
	var back := styles.from_code(styles.code_of(odd))
	_say("an edited style survives its code too (gap snapped to 7.5)", is_equal_approx(float(back["gap"]), 7.5) and is_equal_approx(float(back["red"]), 17.0) and styles.preset_of(back) == -1)
	var code := styles.code_of(styles.preset(5))
	var refused := styles.from_code("hello").is_empty() and styles.from_code("").is_empty() and styles.from_code(code.left(code.length() - 3)).is_empty() and styles.from_code("XH9-" + code.substr(4)).is_empty() and styles.from_code(code + "AA").is_empty()
	_say("broken codes are refused", refused)
	_say("a code with spaces round it still works", styles.same(styles.from_code("  " + code + " \n"), styles.preset(5)))
	var cleaned := styles.clean({"length": 900, "gap": -50, "dot": "big", "alpha": 0.0, "nonsense": 4})
	_say("a saved style is held to the limits (length 40, gap -10, dot default, opacity 0.05)", is_equal_approx(float(cleaned["length"]), 40.0) and is_equal_approx(float(cleaned["gap"]), -10.0) and is_equal_approx(float(cleaned["dot"]), 0.0) and is_equal_approx(float(cleaned["alpha"]), 0.05) and not cleaned.has("nonsense"))
	_say("the first design is the default crosshair", styles.preset_of(styles.preset(0)) == 0 and String(styles.preset(0)["name"]) == "Classic")

	_lines.append("CROSSHAIR_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/crosshair_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
