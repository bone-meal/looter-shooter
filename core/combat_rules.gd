# Purpose: the rules of the fantasy world's combat tools, as plain sums (no nodes, no rendering): what a ward does to
# a hit, what a spell's elements do against a creature's weak and strong element, whether a point lies inside an
# arc in front of somebody. Numbers: data/fantasy/combat.json. Played by game/combat_tools.gd and
# game/spell_effects.gd.
# Dependencies: none.
extends RefCounted


# True when `to_target` (flat direction from the one facing `facing`) lies within `arc_deg` in front of them.
static func in_front(facing: Vector2, to_target: Vector2, arc_deg: float) -> bool:
	if to_target.length_squared() < 0.0001 or facing.length_squared() < 0.0001:
		return true
	return facing.normalized().dot(to_target.normalized()) >= cos(deg_to_rad(arc_deg * 0.5))


# A hit of `amount` against a raised ward. `raised_for` = seconds since the ward went up, `frontal` = it comes from
# inside the ward's arc, `mana` = what the caster has. Returns {"taken", "mana", "perfect", "stopped"}:
# damage that still gets through, mana it costs, whether it was a just-in-time ward, damage stopped.
static func ward(cfg: Dictionary, amount: float, raised_for: float, frontal: bool, mana: float) -> Dictionary:
	if not frontal:
		return {"taken": amount, "mana": 0.0, "perfect": false, "stopped": 0.0}
	if raised_for <= float(cfg["perfect_seconds"]):
		return {"taken": 0.0, "mana": 0.0, "perfect": true, "stopped": amount}
	var price := float(cfg["mana_per_damage"])
	var stopped := amount * float(cfg["block"])
	if price > 0.0:
		stopped = minf(stopped, mana / price)  # the ward holds only as long as there is mana to feed it
	return {"taken": amount - stopped, "mana": stopped * price, "perfect": false, "stopped": stopped}


# What a spell made of the element `letters` does to a creature weak to `weak` and strong against `strong`
# (element letters, "" = none): {"mult": damage multiplier, "kind": "weak" | "strong" | ""}.
static func elements(cfg: Dictionary, letters: String, weak: String, strong: String) -> Dictionary:
	if weak != "" and letters.contains(weak):
		return {"mult": float(cfg["weak_mult"]), "kind": "weak"}
	if strong != "" and letters.contains(strong):
		return {"mult": float(cfg["strong_mult"]), "kind": "strong"}
	return {"mult": 1.0, "kind": ""}
