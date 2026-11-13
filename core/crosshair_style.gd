# Purpose: pure crosshair rules: the fields of a crosshair with their limits (data/crosshairs.json), the 30 ready-made
# designs, cleaning a saved or typed style into legal values, and the share code (text a player copies to a friend).
# A style is a Dictionary field id -> number, plus "name". No nodes, no drawing.
# Share code = code_prefix + url-safe base64 of [version, one byte per field = its step number from the minimum].
# Dependencies: data/crosshairs.json (handed in through setup).
extends RefCounted

const VERSION := 1

var fields: Array = []  # [{id, label, min, max, step, default}]
var presets: Array = []  # [{name, <field>: value ...}] only what differs from the defaults
var prefix := "XH1-"


func setup(cfg: Dictionary) -> void:
	fields = cfg.get("fields", [])
	presets = cfg.get("presets", [])
	prefix = String(cfg.get("code_prefix", prefix))


func defaults() -> Dictionary:
	var out := {"name": "Custom"}
	for f: Dictionary in fields:
		out[String(f["id"])] = float(f["default"])
	return out


# Preset n (0-based) as a full style. Out of range = the defaults.
func preset(n: int) -> Dictionary:
	var out := defaults()
	if n < 0 or n >= presets.size():
		return out
	for key: String in (presets[n] as Dictionary):
		out[key] = presets[n][key]
	return clean(out)


# Any dictionary (a saved one, an old one, one from a code) into a legal style: missing fields take the default,
# numbers are held to the limits and snapped to the step.
func clean(style: Dictionary) -> Dictionary:
	var out := {"name": String(style.get("name", "Custom"))}
	for f: Dictionary in fields:
		var id := String(f["id"])
		var value: Variant = style.get(id, f["default"])
		var number := float(value) if (value is float or value is int) else float(f["default"])
		out[id] = _snap(f, number)
	return out


# The preset this style matches exactly (-1 = none: an edited one).
func preset_of(style: Dictionary) -> int:
	for n in presets.size():
		if same(preset(n), style):
			return n
	return -1


func same(a: Dictionary, b: Dictionary) -> bool:
	for f: Dictionary in fields:
		var id := String(f["id"])
		if not is_equal_approx(float(a.get(id, f["default"])), float(b.get(id, f["default"]))):
			return false
	return true


func code_of(style: Dictionary) -> String:
	var clear := clean(style)
	var bytes := PackedByteArray([VERSION])
	for f: Dictionary in fields:
		bytes.append(_step_number(f, float(clear[String(f["id"])])))
	return prefix + Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


# A share code back into a style; {} when it is not one (wrong start, broken text, other version, wrong length).
func from_code(code: String) -> Dictionary:
	var text := code.strip_edges()
	if not text.begins_with(prefix):
		return {}
	var body := text.substr(prefix.length()).replace("-", "+").replace("_", "/")
	while body.length() % 4 != 0:
		body += "="
	var bytes := Marshalls.base64_to_raw(body)
	if bytes.size() != fields.size() + 1 or bytes[0] != VERSION:
		return {}
	var out := {"name": "Shared"}
	for i in fields.size():
		var f: Dictionary = fields[i]
		out[String(f["id"])] = float(f["min"]) + float(bytes[i + 1]) * float(f["step"])
	return clean(out)


func color_of(style: Dictionary) -> Color:
	return Color(float(style.get("red", 255)) / 255.0, float(style.get("green", 255)) / 255.0, float(style.get("blue", 255)) / 255.0, float(style.get("alpha", 1.0)))


# Data mistakes for the checks: steps that do not fit in a byte, defaults or preset values outside the limits.
func problems() -> Array:
	var out: Array = []
	var ids := {}
	for f: Dictionary in fields:
		ids[String(f["id"])] = f
		if (float(f["max"]) - float(f["min"])) / float(f["step"]) > 255.0:
			out.append("field %s has more than 255 steps" % f["id"])
		if float(f["default"]) < float(f["min"]) or float(f["default"]) > float(f["max"]):
			out.append("field %s default outside its limits" % f["id"])
	for p: Dictionary in presets:
		for key: String in p:
			if key == "name":
				continue
			if not ids.has(key):
				out.append("preset %s: unknown field %s" % [p.get("name", "?"), key])
			elif not is_equal_approx(_snap(ids[key], float(p[key])), float(p[key])):
				out.append("preset %s: %s = %s is off the step or limits" % [p.get("name", "?"), key, str(p[key])])
	return out


func _snap(f: Dictionary, number: float) -> float:
	return float(f["min"]) + float(_step_number(f, number)) * float(f["step"])


func _step_number(f: Dictionary, number: float) -> int:
	var lo := float(f["min"])
	var steps := roundi((float(f["max"]) - lo) / float(f["step"]))
	return clampi(roundi((number - lo) / float(f["step"])), 0, steps)
