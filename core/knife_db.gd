# Purpose: the knives. Which types exist, the weighted roll that gives a new character its type, and what a slash and
# a stab do (the same for every type: the type is looks only). Pure: no nodes, no rendering.
# Dependencies: none. Data: data/knives.json, passed to the constructor.
extends RefCounted

const DEFAULT := "combat"

var _knives: Dictionary
var _attacks: Dictionary
var _materials: Dictionary
var _view: Dictionary


func _init(data: Dictionary) -> void:
	_knives = data["knives"]
	_attacks = data["attacks"]
	_materials = data["materials"]
	_view = data["view"]


# How the knife sits in first person: {position, rotation, scale, aim_spread_deg}.
func view() -> Dictionary:
	return _view


func ids() -> Array:
	return _knives.keys()


func has(id: String) -> bool:
	return _knives.has(id)


# The id itself when it is a knife, else the plain combat knife (an old save, a made-up id from another machine).
func known(id: Variant) -> String:
	return String(id) if id is String and _knives.has(id) else DEFAULT


func name_of(id: String) -> String:
	return String(_knives[known(id)]["name"])


# How likely a new character is to get this type, in percent.
func chance_pct(id: String) -> float:
	var total := 0.0
	for other: String in _knives:
		total += float(_knives[other]["weight"])
	return float(_knives[known(id)]["weight"]) / total * 100.0


# One type by weight: the roll at character creation.
func roll(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id: String in _knives:
		total += float(_knives[id]["weight"])
	var pick := rng.randf() * total
	for id: String in _knives:
		pick -= float(_knives[id]["weight"])
		if pick < 0.0:
			return id
	return DEFAULT


# "slash" or "stab": {damage, reach_m, interval, hit_at, sound, hit_sound}.
func attack(kind: String) -> Dictionary:
	return _attacks[kind]


# What the model is built from (game/knife_models.gd).
func parts(id: String) -> Array:
	return _knives[known(id)]["parts"]


# Where the hand grips this type, [x, y] in the model's metres; [] when it does not say (the middle of the handle).
func hold(id: String) -> Array:
	return _knives[known(id)].get("hold", [])


# True for a type held one in each hand.
func twin(id: String) -> bool:
	return bool(_knives[known(id)].get("twin", false))


func material(id: String) -> Dictionary:
	return _materials[id]


func material_ids() -> Array:
	return _materials.keys()
