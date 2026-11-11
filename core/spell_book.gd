# Purpose: pure rules of staff magic. Turns the elements a player put in the box (a string such as "WFA") into one
# spell: a secret when the exact sequence is known, otherwise form (first element) + substance (set of elements) +
# size (amount). Also mana cost, how many elements a staff can hold and damage scaling. No nodes.
# Dependencies: none. Data: data/fantasy/spells.json.
extends RefCounted

var data: Dictionary


func _init(spell_data: Dictionary) -> void:
	data = spell_data


func is_element(letter: String) -> bool:
	return (data["elements"] as Dictionary).has(letter)


func mana_cost(sequence: String) -> float:
	var total := 0.0
	for letter in sequence:
		total += float(data["elements"][letter]["mana"])
	return total


# How many elements fit in one cast: the base, plus what the staff, the story and the caster's Magic level have
# added (one more for every "slot_every_levels" levels), never above the cap.
func slots(staff_bonus: int, story_bonus: int, magic_level: int = 1) -> int:
	var every := int(data.get("slot_every_levels", 0))
	var from_level := floori(float(magic_level) / float(every)) if every > 0 else 0
	return clampi(int(data["base_slots"]) + staff_bonus + story_bonus + from_level, 1, int(data["max_slots"]))


# The sorted set of different elements in a sequence, e.g. "WFWA" -> "AFW" (the key into "substances").
static func substance_key(sequence: String) -> String:
	var letters: Array[String] = []
	for letter in sequence:
		if not letters.has(letter):
			letters.append(letter)
	letters.sort()
	return "".join(letters)


func secret_for(sequence: String) -> Dictionary:
	for secret: Dictionary in data["secrets"]:
		if String(secret["sequence"]) == sequence:
			return secret
	return {}


func secret_for_id(id: String) -> Dictionary:
	for secret: Dictionary in data["secrets"]:
		if String(secret["id"]) == id:
			return secret
	return {}


# "AWA" -> "Air, Water, Air" (how a long spell is taught).
func spell_out(sequence: String) -> String:
	var words := PackedStringArray()
	for letter in sequence:
		words.append(String(data["elements"][letter]["name"]))
	return ", ".join(words)


# The spell a sequence makes, or {} for an empty or invalid one. Keys: name, kind (jet / bolt / ground / wave, or a
# secret's kind), color, damage (before the caster's power), heal, effects, count (elements used), mana, secret (id or
# ""), and the form's own numbers (range, radius, seconds, speed, angle, width) already grown by the amount.
func resolve(sequence: String) -> Dictionary:
	if sequence == "":
		return {}
	for letter in sequence:
		if not is_element(letter):
			return {}
	var count := sequence.length()
	var secret := secret_for(sequence)
	if not secret.is_empty():
		var out: Dictionary = secret.duplicate(true)
		out["secret"] = String(secret["id"])
		out["count"] = count
		out["mana"] = mana_cost(sequence)
		out["heal"] = float(secret.get("heal", 0.0))
		return out
	var form: Dictionary = data["forms"][sequence[0]]
	var key := substance_key(sequence)
	var substance: Dictionary = data["substances"][key]
	var grow := pow(float(count), float(data["damage_power"]))
	var spell := {"secret": "", "kind": String(form["id"]), "count": count, "mana": mana_cost(sequence), "color": substance["color"],
		"damage": float(substance["damage"]) * grow * float(form["damage_mult"]), "heal": float(substance.get("heal", 0.0)) * grow,
		"effects": (substance["effects"] as Dictionary).duplicate(), "substance": key, "look": substance.get("look", {}),
		"pull": float(form.get("pull", 0.0)), "range": float(form.get("range", 0.0)), "speed": float(form.get("speed", 0.0)), "angle": float(form.get("angle", 0.0)), "width": float(form.get("width", 0.0)),
		"radius": float(form.get("radius", 0.0)) + float(form.get("radius_per_element", 0.0)) * float(count - 1),
		"seconds": float(form.get("seconds", 0.0)) + float(form.get("seconds_per_element", 0.0)) * float(count - 1)}
	spell["name"] = _name(String(form["id"]), String(form["name"]), key, String(substance["name"]), count)
	return spell


func _name(form_id: String, form_name: String, key: String, substance_name: String, count: int) -> String:
	var names: Dictionary = data["names"]
	var exact := "%s:%s:%d" % [form_id, key, count]
	if names.has(exact):
		return String(names[exact])
	var tier := ""
	for entry: Dictionary in data["tiers"]:
		if count >= int(entry["count"]):
			tier = String(entry["name"])
	return ("%s %s %s" % [tier, substance_name, form_name]).strip_edges()


# Damage or healing after the caster's strength: staff power (1 = starter staff) and Magic level (each level adds
# `per_level`).
static func scaled(amount: float, staff_power: float, magic_level: int, per_level: float = 0.06) -> float:
	return amount * staff_power * (1.0 + per_level * float(maxi(magic_level - 1, 0)))


# Problems in the data, for tools/fantasy_check: unknown letters, secrets longer than the cap, two secrets alike.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for secret: Dictionary in data["secrets"]:
		var sequence := String(secret["sequence"])
		for letter in sequence:
			if not is_element(letter):
				out.append("secret %s uses unknown element %s" % [secret["id"], letter])
		if sequence.length() > int(data["max_slots"]):
			out.append("secret %s is longer than max_slots" % secret["id"])
		if seen.has(sequence):
			out.append("secrets %s and %s share a sequence" % [secret["id"], seen[sequence]])
		seen[sequence] = secret["id"]
	for key: String in data["substances"]:
		if substance_key(key) != key:
			out.append("substance key %s is not sorted" % key)
	for name_key: String in data["names"]:
		var parts := name_key.split(":")
		if parts.size() != 3 or not (data["substances"] as Dictionary).has(parts[1]):
			out.append("name %s points at nothing" % name_key)
	return out
