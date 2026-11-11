# Purpose: pure rules for gun drops from enemies: drop chance, tier floor, wave luck, elite affix choice and stat scaling. The host/each machine rolls with its own RNG; no nodes.
# Dependencies: core/gun_gen.gd, core/gun_db.gd. Data: data/drops.json.
extends RefCounted

const GunGen = preload("res://core/gun_gen.gd")


# Luck for a wave number (1-based): grows by cfg.luck_per_wave per wave after the first.
static func wave_luck(cfg: Dictionary, wave: int) -> float:
	return float(cfg["luck_per_wave"]) * float(maxi(wave - 1, 0))


# Returns the guns an enemy drops: its own entry (chance, floor, count) plus the elite bonus drop. May be empty.
static func roll_drops(db: RefCounted, cfg: Dictionary, rng: RandomNumberGenerator, enemy_id: String, elite: bool, wave: int, luck_mult: float = 1.0) -> Array:
	var guns: Array = []
	var luck := wave_luck(cfg, wave) * luck_mult
	var entries: Array = []
	if cfg["enemies"].has(enemy_id):
		entries.append(cfg["enemies"][enemy_id])
	if elite:
		entries.append(cfg["elite"]["drop"])
	for e: Dictionary in entries:
		if rng.randf() > float(e["chance"]):
			continue
		for _i in int(e["count"]):
			guns.append(GunGen.generate(db, rng, luck, "", "", String(e["min_tier"])))
	return guns


# Picks an affix for a new enemy, or {} for a normal one. Elites never appear before cfg.elite.min_wave and never for a boss.
static func roll_elite(cfg: Dictionary, rng: RandomNumberGenerator, enemy_id: String, wave: int) -> Dictionary:
	var e: Dictionary = cfg["elite"]
	if enemy_id.begins_with("boss") or wave < int(e["min_wave"]) or rng.randf() > float(e["chance"]):
		return {}
	var affixes: Array = e["affixes"]
	return affixes[rng.randi_range(0, affixes.size() - 1)]


# Enemy stats with an affix applied (a copy; the input is untouched).
static func apply_affix(stats: Dictionary, affix: Dictionary) -> Dictionary:
	var out: Dictionary = stats.duplicate(true)
	out["max_hp"] = float(stats["max_hp"]) * float(affix["hp_mult"])
	out["speed"] = float(stats["speed"]) * float(affix["speed_mult"])
	out["damage"] = float(stats["damage"]) * float(affix["damage_mult"])
	var size: Array = stats["size"]
	var m := float(affix["size_mult"])
	out["size"] = [float(size[0]) * m, float(size[1]) * m, float(size[2]) * m]
	return out
