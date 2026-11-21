# Purpose: skinned knives (polish1 D5b, diary/DESIGN_KNIVES.md): rolling one (tier by the odds, a finish of that tier,
# a knife type at its weight, pattern 0-999, wear, power strength), its level from the kills made with it, how strong
# its power and its damage are at that level, the chase / phase / gem name its pattern gives, the power's text, and a
# shape check of an item (saves, trades). A skinned knife item = {"finish", "type", "pattern", "wear", "strength",
# "kills"}. Pure rules.
# Dependencies: none (data/knife_skins.json and the knife types' weights passed in).
extends RefCounted

const KILLS_MAX := 10000000

var cfg: Dictionary
var types: Dictionary  # knife type id -> weight (data/knives.json)
var _by_id := {}


func _init(config: Dictionary, type_weights: Dictionary) -> void:
	cfg = config
	types = type_weights
	for row: Dictionary in cfg.get("finishes", []):
		_by_id[String(row["id"])] = row


func finish(id: String) -> Dictionary:
	return _by_id.get(id, {})


func family(item: Dictionary) -> Dictionary:
	return (cfg.get("families", {}) as Dictionary).get(String(finish(String(item.get("finish", ""))).get("family", "")), {})


func power(item: Dictionary) -> Dictionary:
	return (cfg.get("powers", {}) as Dictionary).get(String(finish(String(item.get("finish", ""))).get("power", "")), {})


# A fresh skinned knife: tier by the odds, a finish of that tier, a type at its weight, pattern, wear, strength.
func roll(rng: RandomNumberGenerator) -> Dictionary:
	var tier := String(_pick(rng, cfg.get("tiers", {"blue": 1.0})))
	var pool: Array = []
	for row: Dictionary in cfg.get("finishes", []):
		if String(row["tier"]) == tier:
			pool.append(String(row["id"]))
	if pool.is_empty():
		pool = _by_id.keys()
	var spread: Array = cfg.get("strength", [0.9, 1.1])
	return {"finish": String(pool[rng.randi() % pool.size()]), "type": String(_pick(rng, types)), "pattern": rng.randi() % 1000,
		"wear": snappedf(rng.randf_range(0.0, 1.0) * rng.randf_range(0.3, 1.0), 0.0001), "strength": snappedf(rng.randf_range(float(spread[0]), float(spread[1])), 0.001), "kills": 0}


static func _pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	var at := rng.randf() * total
	for k: String in weights:
		at -= float(weights[k])
		if at <= 0.0:
			return k
	return String(weights.keys()[weights.size() - 1]) if not weights.is_empty() else ""


# Kills needed to go from level n to n + 1.
func kills_for(n: int) -> int:
	var lv: Dictionary = cfg.get("levels", {})
	return int(lv.get("base", 5)) + int(lv.get("step", 3)) * n


func max_level() -> int:
	return int((cfg.get("levels", {}) as Dictionary).get("max", 30))


func level(item: Dictionary) -> int:
	var left := int(item.get("kills", 0))
	var n := 1
	while n < max_level() and left >= kills_for(n):
		left -= kills_for(n)
		n += 1
	return n


# [kills into this level, kills this level needs] (the needs is 0 at the top level).
func level_progress(item: Dictionary) -> Array:
	var left := int(item.get("kills", 0))
	var n := 1
	while n < max_level() and left >= kills_for(n):
		left -= kills_for(n)
		n += 1
	return [left, 0 if n >= max_level() else kills_for(n)]


# 0..1 of the way from level 1 to the top.
func climb(item: Dictionary) -> float:
	return float(level(item) - 1) / float(maxi(max_level() - 1, 1))


# How strong the power is now: power_min at level 1 up to 1 at the top, times the knife's own roll.
func power_scale(item: Dictionary) -> float:
	var lo := float((cfg.get("levels", {}) as Dictionary).get("power_min", 0.4))
	return lerpf(lo, 1.0, climb(item)) * float(item.get("strength", 1.0))


func damage_mult(item: Dictionary) -> float:
	return lerpf(1.0, float((cfg.get("levels", {}) as Dictionary).get("damage_max", 3.0)), climb(item))


# The power's text with its numbers at this knife's level and roll ("{30}" -> "17").
func power_text(item: Dictionary) -> String:
	var text := String(power(item).get("text", ""))
	var k := power_scale(item)
	var out := ""
	var at := 0
	while true:
		var open := text.find("{", at)
		if open < 0:
			break
		var shut := text.find("}", open)
		if shut < 0:
			break
		out += text.substr(at, open - at) + str(roundi(float(text.substr(open + 1, shut - open - 1)) * k))
		at = shut + 1
	return out + text.substr(at)


# Where a pattern number lands in its family: a chase name ("Bluegem", "Bloodmoon" ...), else a phase, else "".
# `variant` = 1 + the chase's place in the list for the shader, 0 for none; `phase` = 1-4 or 0.
func pattern_look(item: Dictionary) -> Dictionary:
	var fam := family(item)
	var p := int(item.get("pattern", 0))
	var h := float((p * 7919 + absi(hash(String(finish(String(item.get("finish", ""))).get("family", "")))) % 1000) % 1000) / 1000.0  # spread the numbers (per family) so chase patterns are not just the lowest ones
	var share := 0.0
	var chase: Array = fam.get("chase", [])
	var own_names: Array = finish(String(item.get("finish", ""))).get("chase_names", [])
	for i in chase.size():
		share += float(chase[i][1])
		if h < share:
			var shown := String(own_names[i]) if i < own_names.size() else String(chase[i][0])
			return {"name": shown, "variant": i + 1, "phase": 0}
	var phases: Array = fam.get("phases", [])
	if not phases.is_empty():
		var ph := p % phases.size()
		return {"name": String(phases[ph]), "variant": 0, "phase": ph + 1}
	return {"name": "", "variant": 0, "phase": 0}


# "" when the item is a legal skinned knife, else a short reason (saves and trades).
func check(item: Variant) -> String:
	if not item is Dictionary:
		return "not a knife"
	var d: Dictionary = item
	if d.size() > 6 or finish(String(d.get("finish", ""))).is_empty() or not types.has(String(d.get("type", ""))):
		return "unknown knife"
	for key: String in ["pattern", "wear", "strength", "kills"]:
		if not (d.get(key) is int or d.get(key) is float):
			return "bad " + key
	var spread: Array = cfg.get("strength", [0.9, 1.1])
	if int(d["pattern"]) < 0 or int(d["pattern"]) > 999 or float(d["wear"]) < 0.0 or float(d["wear"]) > 1.0 \
			or float(d["strength"]) < float(spread[0]) - 0.0005 or float(d["strength"]) > float(spread[1]) + 0.0005 or int(d["kills"]) < 0 or int(d["kills"]) > KILLS_MAX:
		return "knife numbers out of range"
	return ""
