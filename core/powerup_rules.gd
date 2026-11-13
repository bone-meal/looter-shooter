# Purpose: pure rules of the islands' power-ups: which one a dying enemy leaves (chance, cap per round, a boss
# always), and the clocks of the ones that last (insta-kill, double points). No nodes, no rendering.
# Dependencies: none. Data: data/powerups.json, passed to the constructor. Time is the caller's clock in seconds.
extends RefCounted

var cfg: Dictionary

var _kinds: Dictionary
var _timed: Array[String] = []  # the kinds that last, in data order (the HUD walks this list)
var _dropped := 0  # left by chance this round (a boss's and a special round's are not counted)
var _until := {}  # kind -> when it ends
var _colors := {}  # kind -> Color (read from the data once)


func _init(config: Dictionary) -> void:
	cfg = config
	_kinds = config["kinds"]
	for kind: String in _kinds:
		_colors[kind] = Color(String(_kinds[kind]["color"]))
		if float(_kinds[kind].get("seconds", 0.0)) > 0.0:
			_timed.append(kind)
			_until[kind] = -1.0


func has(kind: String) -> bool:
	return _kinds.has(kind)


func kinds() -> Array:
	return _kinds.keys()


func timed() -> Array[String]:
	return _timed


func name_of(kind: String) -> String:
	return String(_kinds[kind]["name"]) if _kinds.has(kind) else kind


func color_of(kind: String) -> Color:
	return _colors[kind] if _colors.has(kind) else Color.WHITE


# How long this kind lasts once taken; 0 = it happens at once.
func seconds_of(kind: String) -> float:
	return float(_kinds[kind].get("seconds", 0.0)) if _kinds.has(kind) else 0.0


# A new round: the cap on chance drops starts again.
func new_round() -> void:
	_dropped = 0


# The run is over: nothing is running, nothing was dropped.
func reset() -> void:
	_dropped = 0
	for kind: String in _timed:
		_until[kind] = -1.0


# What a dying island enemy leaves: mostly "" (nothing). A boss always leaves one, sometimes the perk one.
# `chance_mult` = a perk that makes ordinary drops more likely.
func roll_drop(rng: RandomNumberGenerator, boss: bool, chance_mult: float = 1.0) -> String:
	if boss:
		return "perk" if (_kinds.has("perk") and rng.randf() < float(cfg.get("boss_perk_chance", 0.0))) else pick(rng)
	if _dropped >= int(cfg["max_per_round"]) or rng.randf() >= float(cfg["drop_chance"]) * chance_mult:
		return ""
	_dropped += 1
	return pick(rng)


# One kind by weight.
func pick(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for kind: String in _kinds:
		total += float(_kinds[kind]["weight"])
	var roll := rng.randf() * total
	var last := ""
	for kind: String in _kinds:
		if float(_kinds[kind]["weight"]) <= 0.0:
			continue  # never by chance (the boss's perk power-up)
		last = kind
		roll -= float(_kinds[kind]["weight"])
		if roll <= 0.0:
			return kind
	return last


# Somebody took `kind`: one that lasts starts its clock (again from full when it was still running). `time_mult` = a
# perk that makes it last longer.
func start(kind: String, now: float, time_mult: float = 1.0) -> void:
	if _until.has(kind):
		_until[kind] = now + seconds_of(kind) * time_mult


func is_on(kind: String, now: float) -> bool:
	return _until.has(kind) and now < float(_until[kind])


func left(kind: String, now: float) -> float:
	return maxf(float(_until[kind]) - now, 0.0) if _until.has(kind) else 0.0


# What every point award is multiplied by right now.
func points_mult(now: float) -> int:
	return int(_kinds["double_points"]["mult"]) if is_on("double_points", now) else 1
