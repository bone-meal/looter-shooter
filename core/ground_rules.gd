# Purpose: the rules of what spells leave on the ground, as plain sums (no nodes, no rendering): which marks a
# spell makes, how puddles grow into floods, how fire and water cancel. Numbers: data/fantasy/ground.json.
# Played by game/ground_marks.gd.
# Dependencies: none.
extends RefCounted


# Which marks a spell that touches the ground leaves: any of "spikes", "fire", "water" (things that stay) and
# "shock" (lightning: it stays nowhere, but water carries it).
static func leaves(cfg: Dictionary, spell: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var effects: Dictionary = spell.get("effects", {})
	var shape := String((spell.get("look", {}) as Dictionary).get("shape", ""))
	if shape in cfg["spikes"]["shapes"] and String(spell.get("kind", "")) in cfg["spikes"]["forms"]:
		out.append("spikes")
	var burns := effects.has("burn")
	var wets := effects.has("wet")
	if burns and not wets:  # both at once is steam: nothing stays
		out.append("fire")
	if wets and not burns:
		out.append("water")
	if effects.has("chain") or effects.has("shock"):
		out.append("shock")
	return out


# How wide the mark of a spell of radius `spell_radius` is.
static func radius(part: Dictionary, spell_radius: float) -> float:
	return clampf(spell_radius * float(part["radius_share"]), float(part.get("min_radius", 0.5)), float(part.get("max_radius", 99.0)))


# A puddle of radius `had` takes more water of radius `added`: the areas add up, to the cap.
static func pooled(water: Dictionary, had: float, added: float) -> float:
	return minf(sqrt(had * had + added * added), float(water["max_radius"]))


# Fire of radius `fire` boils part of a puddle of radius `had` away: what is left (below min_radius = gone, 0).
static func boiled(water: Dictionary, had: float, fire: float) -> float:
	var left := sqrt(maxf(had * had - fire * fire, 0.0))
	return left if left >= float(water["min_radius"]) else 0.0


static func flooded(water: Dictionary, size: float) -> bool:
	return size >= float(water["flood_radius"])


# How long a puddle of this size lies before it has dried.
static func dries_in(water: Dictionary, size: float) -> float:
	return float(water["seconds"]) + float(water["seconds_per_m"]) * size
