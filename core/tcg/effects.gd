# Purpose: runs the card game's effects (data/tcg/cards.json "effects", leaders' powers): who they hit, damage, healing,
# drawing, summoning, buffs, keywords, destroy, mana, bounce, adding cards, dice rolls and coin flips. Pure.
# An effect = {"when", "do", "to", "amount", "card", "count", "attack", "health", "keyword", "per", "sides", "low",
# "high", "heads", "tails"}; see data/tcg/cards.json "_about".
# Dependencies: core/tcg/match_state.gd (the match is handed in).
extends RefCounted


# Every effect of `effects` whose "when" matches, for `side`; `source` = the creature it comes from (-1 none);
# `target` = the picked target (or, for traps, the creature that set it off); spell = gets the side's Empower.
static func run(m: RefCounted, side: int, effects: Array, when: String, source: int, target: int, spell := false) -> void:
	for e: Dictionary in effects:
		if String(e.get("when", "")) != when or m.get("phase") == "over":
			continue
		apply(m, side, e, source, target, spell)


static func apply(m: RefCounted, side: int, e: Dictionary, source: int, target: int, spell: bool) -> void:
	var times := 1
	if e.has("per"):
		times = _count(m, side, String(e["per"]), source)
	var amount := int(e.get("amount", 1)) * (times if e.has("per") and String(e["do"]) in ["damage", "heal", "draw"] else 1)
	var hits := targets(m, side, String(e.get("to", "self")), source, target)
	match String(e["do"]):
		"damage":
			var extra: int = m.empower(side) if spell else 0
			for t: int in hits:
				m.damage(t, amount + extra, source)
		"heal":
			for t: int in hits:
				m.heal(t, amount)
		"draw":
			m.draw(side if String(e.get("to", "self")) != "enemy_hero" else 1 - side, amount)
		"summon":
			var who := 1 - side if String(e.get("to", "")) == "enemy_hero" else side
			for i in int(e.get("count", 1)) * (times if e.has("per") else 1):
				m.summon(who, String(e["card"]))
		"buff":
			var mult := times if e.has("per") else 1
			for t: int in hits:
				if t >= 0:
					m.buff(t, int(e.get("attack", 0)) * mult, int(e.get("health", 0)) * mult)
		"give":
			for t: int in hits:
				if t >= 0:
					m.give_keyword(t, String(e["keyword"]))
		"destroy":
			for t: int in hits:
				if t >= 0:
					m.destroy(t)
		"mana":
			m.gain_mana(side, amount)
		"crystal":
			m.gain_crystal(side, amount)
		"bounce":
			for t: int in hits:
				if t >= 0:
					m.bounce(t)
		"add":
			for i in int(e.get("count", 1)):
				m.add_card(side, String(e["card"]))
		"roll":
			var faces := int(e.get("sides", 6))
			var rolled: int = (m.get("rng") as RandomNumberGenerator).randi_range(1, faces)
			m.log_event({"e": "roll", "side": side, "value": rolled, "sides": faces})
			for sub: Dictionary in (e.get("low", []) if rolled <= floori(float(faces) / 2.0) else e.get("high", [])):
				apply(m, side, sub, source, target, spell)
		"flip":
			var heads: bool = (m.get("rng") as RandomNumberGenerator).randi_range(0, 1) == 1
			m.log_event({"e": "flip", "side": side, "heads": heads})
			for sub: Dictionary in (e.get("heads", []) if heads else e.get("tails", [])):
				apply(m, side, sub, source, target, spell)


# Target codes (match_state: creature uid, or HERO - side for a leader).
static func targets(m: RefCounted, side: int, to: String, source: int, target: int) -> Array:
	var foe := 1 - side
	var hero: int = m.HERO
	var sides: Array = m.get("sides")
	var rng: RandomNumberGenerator = m.get("rng")
	match to:
		"pick_any", "pick_creature", "pick_enemy", "pick_enemy_creature", "pick_friendly_creature", "attacker", "played":
			return [target] if target != -1 and m.hp_of(target) > 0 else []
		"self":
			return [source] if source >= 0 else [hero - side]
		"own_hero":
			return [hero - side]
		"enemy_hero":
			return [hero - foe]
		"both_heroes":
			return [hero - side, hero - foe]
		"all_enemy_creatures":
			return _uids(sides[foe]["board"], -1)
		"all_friendly_creatures":
			return _uids(sides[side]["board"], -1)
		"all_other_friendly":
			return _uids(sides[side]["board"], source)
		"all_creatures":
			return _uids(sides[side]["board"], -1) + _uids(sides[foe]["board"], -1)
		"all_enemies":
			return [hero - foe] + _uids(sides[foe]["board"], -1)
		"random_enemy_creature":
			return _one(_uids(sides[foe]["board"], -1), rng)
		"random_enemy":
			return _one([hero - foe] + _uids(sides[foe]["board"], -1), rng)
		"random_friendly_creature":
			return _one(_uids(sides[side]["board"], source), rng)
	return []


# How many of something there are, for "per" (e.g. "friendly_tribe:drowned").
static func _count(m: RefCounted, side: int, per: String, source: int) -> int:
	var sides: Array = m.get("sides")
	var db: RefCounted = m.get("db")
	match per.get_slice(":", 0):
		"friendly_creatures":
			return _uids(sides[side]["board"], source).size()
		"enemy_creatures":
			return (sides[1 - side]["board"] as Array).size()
		"friendly_tribe":
			var n := 0
			for c: Dictionary in sides[side]["board"]:
				if int(c["uid"]) != source and String(db.card(String(c["card"])).get("tribe", "")) == per.get_slice(":", 1):
					n += 1
			return n
		"cards_in_hand":
			return (sides[side]["hand"] as Array).size()
	return 0


static func _uids(board: Array, leave_out: int) -> Array:
	var out: Array = []
	for c: Dictionary in board:
		if int(c["uid"]) != leave_out:
			out.append(int(c["uid"]))
	return out


static func _one(list: Array, rng: RandomNumberGenerator) -> Array:
	return [] if list.is_empty() else [list[rng.randi_range(0, list.size() - 1)]]
