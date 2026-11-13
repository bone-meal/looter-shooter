# Purpose: pure rules of a colosseum run: the tickets, how much tougher each wave's enemies are, which tier of gun a
# kill leaves in which wave, what the last boss and the reward chest give, and when armour drops. No nodes; the
# caller brings the random numbers.
# Dependencies: none. Data: data/colosseum.json, passed to the constructor. `luck` (1 = plain) scales every chance:
# the session passes the character's luck times the modifiers' loot_mult().
extends RefCounted

var cfg: Dictionary

var _loot: Dictionary
var _tiers: Array


func _init(config: Dictionary) -> void:
	cfg = config
	_loot = config["loot"]
	_tiers = _loot["tiers"]


# What is wrong with the data, as lines for a check log (empty = fine).
func problems(wave_count: int, known_tiers: Array) -> PackedStringArray:
	var found := PackedStringArray()
	var last := 0
	for entry: Dictionary in cfg["tickets"]:
		if int(entry["waves"]) <= last or int(entry["waves"]) > wave_count or int(entry["price"]) <= 0:
			found.append("ticket %s: waves must grow, fit the %d waves there are, and cost something" % [entry["name"], wave_count])
		last = int(entry["waves"])
	for tier: String in _tiers:
		if not known_tiers.has(tier):
			found.append("loot tier %s is not a gun tier" % tier)
	var reach := 0
	for band: Dictionary in _loot["bands"]:
		if int(band["to_wave"]) <= reach or not _tiers.has(String(band["tier"])):
			found.append("loot band to wave %d: waves must grow and the tier must be on the ladder" % int(band["to_wave"]))
		reach = int(band["to_wave"])
	if reach < wave_count:
		found.append("the loot bands end at wave %d of %d" % [reach, wave_count])
	for tier: String in _loot["final_boss"]["tiers"]:
		if not known_tiers.has(tier):
			found.append("final boss tier %s is not a gun tier" % tier)
	return found


func ticket_count() -> int:
	return (cfg["tickets"] as Array).size()


# {"name", "waves", "price"}
func ticket(index: int) -> Dictionary:
	return cfg["tickets"][index]


# An enemy's numbers in a wave (wave 1 = as written in data/enemies.json), under a run's effects (see `effects`).
# A copy; the input is untouched.
func wave_stats(stats: Dictionary, wave: int, fx: Dictionary = {}) -> Dictionary:
	var grown := stats.duplicate(true)
	var waves_on := float(maxi(wave - 1, 0))
	var per: Dictionary = cfg["per_wave"]
	grown["max_hp"] = float(stats["max_hp"]) * (1.0 + float(per["health"]) * waves_on) * float(fx.get("enemy_health", 1.0))
	grown["damage"] = float(stats["damage"]) * (1.0 + float(per["damage"]) * waves_on) * float(fx.get("enemy_damage", 1.0))
	grown["speed"] = float(stats["speed"]) * (1.0 + float(per["speed"]) * waves_on) * float(fx.get("enemy_speed", 1.0))
	return grown


# What the chosen modifiers change, as one table: numbers under the same key multiply, anything else is taken as
# written. {} = a plain run. The keys are listed in the data's _about.
func effects(chosen: PackedStringArray) -> Dictionary:
	var fx := {}
	for id: String in chosen:
		var changes: Dictionary = modifier(id).get("effects", {})
		for key: String in changes:
			var value: Variant = changes[key]
			if fx.has(key) and (value is float or value is int) and (fx[key] is float or fx[key] is int):
				fx[key] = float(fx[key]) * float(value)
			else:
				fx[key] = value
	return fx


# The waves of a run: the first `count` of the data's, with more heads under the effects (bosses x boss_count, the
# rest x enemy_count, rounded up).
func run_waves(waves: Array, count: int, fx: Dictionary = {}) -> Array:
	var out: Array = []
	for wave: Dictionary in waves.slice(0, count):
		var heads := {}
		for id: String in wave:
			heads[id] = ceili(float(wave[id]) * float(fx.get("boss_count" if id.begins_with("boss") else "enemy_count", 1.0)) - 0.001)
		out.append(heads)
	return out


# The tier ordinary kills leave in a wave.
func band_tier(wave: int) -> String:
	return String(_band(wave)["tier"])


func _band(wave: int) -> Dictionary:
	var bands: Array = _loot["bands"]
	for band: Dictionary in bands:
		if wave <= int(band["to_wave"]):
			return band
	return bands[bands.size() - 1]


# `steps` rungs up the ladder from a tier, never past its top.
func tier_up(tier: String, steps: int) -> String:
	return String(_tiers[clampi(_tiers.find(tier) + steps, 0, _tiers.size() - 1)])


# The tiers of the guns a kill leaves (often none). kind = "trash", "elite" or "boss".
func kill_tiers(rng: RandomNumberGenerator, wave: int, kind: String, luck: float = 1.0) -> Array[String]:
	var out: Array[String] = []
	var last: Dictionary = _loot["final_boss"]
	if kind == "boss" and wave == int(last["wave"]):
		for _gun in int(last["guns"]):
			out.append(_weighted(rng, last["tiers"]))
		return out
	if kind == "trash" and rng.randf() >= float(_loot["trash_chance"]) * luck:
		return out
	var band := _band(wave)
	var tier := String(band["tier"])
	if kind == "boss":
		tier = tier_up(tier, int(_loot["boss_tiers_up"]))
	elif rng.randf() < float(band["better"]) * luck:
		tier = tier_up(tier, 1)
	out.append(tier)
	return out


func _weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for id: String in weights:
		total += float(weights[id])
	var pick := rng.randf() * total
	var chosen := ""
	for id: String in weights:
		chosen = id
		pick -= float(weights[id])
		if pick <= 0.0:
			break
	return chosen


# The modifiers a run can be made harder with ([] until data lists some): {"id", "name", "desc", "loot", ...}.
func modifiers() -> Array:
	return cfg.get("modifiers", [])


func modifier(id: String) -> Dictionary:
	for mod: Dictionary in modifiers():
		if String(mod["id"]) == id:
			return mod
	return {}


# What the chosen modifiers multiply every loot chance by: 1 + the sum of their `loot` shares.
func loot_mult(chosen: PackedStringArray) -> float:
	var bonus := 0.0
	for id: String in chosen:
		bonus += float(modifier(id).get("loot", 0.0))
	return 1.0 + bonus


# The reward chest of a run whose last wave was `last_wave`: its guns' tiers. Modifiers add a gun for every
# `gun_per_loot` of loot bonus they bring.
func chest_tiers(last_wave: int, chosen: PackedStringArray = PackedStringArray()) -> Array[String]:
	var out: Array[String] = []
	var chest: Dictionary = _loot["chest"]
	var extra := floori((loot_mult(chosen) - 1.0) / maxf(float(chest.get("gun_per_loot", 1.0)), 0.01))
	for _gun in int(chest["guns"]) + extra:
		out.append(tier_up(band_tier(last_wave), int(chest["tiers_up"])))
	return out


# Does this kill also leave a piece of armour, and is it the one with a gun slot more?
func armour_drops(rng: RandomNumberGenerator, kind: String, luck: float = 1.0) -> bool:
	return rng.randf() < float(_loot["armour"]["%s_chance" % kind]) * luck


func armour_has_slot(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < float(_loot["armour"]["slot_trait_chance"])


# The last boss's own treasure ("" = not this time, or not that boss).
func treasure(rng: RandomNumberGenerator, wave: int, kind: String, luck: float = 1.0) -> String:
	var last: Dictionary = _loot["final_boss"]
	if kind != "boss" or wave != int(last["wave"]) or rng.randf() >= float(last["treasure_chance"]) * luck:
		return ""
	return String(last["treasure"])
