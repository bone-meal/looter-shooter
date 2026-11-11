# Purpose: pure lookup + validation of character appearance (gender, body sliders, skin, hair, face expression, outfit). `sanitize` turns ANY input into a valid appearance, so saves and other players' data can never carry unknown IDs or out-of-range numbers.
# Rigged bodies (data/characters.json, optional 4th argument) add `rig_outfit` and `rig_hair`.
# Dependencies: none. Built from data/appearance.json, data/outfits.json, data/expressions.json, data/characters.json (parsed Dictionaries passed in).
extends RefCounted

const HEX := "^#[0-9a-fA-F]{6}$"

var skin_tones: Array = []
var hair_styles: Array = []  # [{id, name}]
var outfits: Array = []  # [{id, name, top, bottom, head, back, feet, neck, hands, colors}]
var expressions: Array = []  # [{id, name, eyes, brows, mouth, extra}]
var rig_outfits: Array = []  # [{id, name}] outfits of the rigged bodies (empty when no rig data was given)
var rig_hair: Array = []  # [{id, name}]

var _main: Dictionary
var _outfit_index := {}
var _face_index := {}
var _hair_ids := {}
var _hex := RegEx.new()
var _rig_defaults := {}  # gender -> {rig_outfit, rig_hair}


func _init(main: Dictionary, outfit_data: Dictionary, face_data: Dictionary, rig_data: Dictionary = {}) -> void:
	_main = main
	skin_tones = main["skin_tones"]
	hair_styles = main["hair_styles"]
	outfits = outfit_data["outfits"]
	expressions = face_data["expressions"]
	for i in outfits.size():
		_outfit_index[String(outfits[i]["id"])] = i
	for i in expressions.size():
		_face_index[String(expressions[i]["id"])] = i
	for h in hair_styles:
		_hair_ids[String(h["id"])] = true
	_hex.compile(HEX)
	_rig_defaults = rig_data.get("defaults", {})
	rig_outfits = _id_names(rig_data.get("outfits", {}))
	rig_hair = _id_names(rig_data.get("hair", {}))


static func _id_names(entries: Dictionary) -> Array:
	var out: Array = []
	for id: String in entries:
		out.append({"id": id, "name": String((entries[id] as Dictionary).get("name", id))})
	return out


func outfit(id: String) -> Dictionary:
	return outfits[_outfit_index.get(id, 0)]


func expression(id: String) -> Dictionary:
	return expressions[_face_index.get(id, 0)]


func range_of(key: String) -> Array:
	return _main["ranges"][key]


func default_for(gender: String) -> Dictionary:
	return _main["defaults"].get(gender, _main["defaults"]["female"]).duplicate()


# Always returns a complete, valid appearance. Unknown or malformed fields fall back to the defaults of the chosen gender.
func sanitize(raw: Variant) -> Dictionary:
	var src: Dictionary = raw if raw is Dictionary else {}
	var gender := String(src.get("gender", "female"))
	if gender != "female" and gender != "male":
		gender = "female"
	var out := default_for(gender)
	for key in ["height", "weight", "bust", "glutes"]:
		var v: Variant = src.get(key)
		if (v is float or v is int) and is_finite(float(v)):
			var r := range_of(key)
			out[key] = clampf(float(v), float(r[0]), float(r[1]))
	var skin: Variant = src.get("skin")
	if (skin is int or skin is float) and int(skin) >= 0 and int(skin) < skin_tones.size():
		out["skin"] = int(skin)
	var hair: Variant = src.get("hair")
	if hair is String and _hair_ids.has(hair):
		out["hair"] = hair
	var color: Variant = src.get("hair_color")
	if color is String and _hex.search(color) != null:
		out["hair_color"] = String(color).to_lower()
	var face: Variant = src.get("face")
	if face is String and _face_index.has(face):
		out["face"] = face
	var outfit_id: Variant = src.get("outfit")
	if outfit_id is String and _outfit_index.has(outfit_id):
		out["outfit"] = outfit_id
	if _rig_defaults.has(gender):
		for key: String in ["rig_outfit", "rig_hair"]:
			var picked: Variant = src.get(key)
			var allowed: Array = rig_outfits if key == "rig_outfit" else rig_hair
			out[key] = String((_rig_defaults[gender] as Dictionary)[key])
			for entry: Dictionary in allowed:
				if picked is String and entry["id"] == picked:
					out[key] = picked
	return out
