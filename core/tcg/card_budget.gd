# Purpose: prices a card against the stat budget (data/tcg/budget.json): what its cost and rarity allow, and what its
# stats, keywords and effects spend. Pure rules, no nodes. Used by tools/tcg_rules_check to list off-budget cards
# (information for the director; the starter decks are balanced by the simulator, not by this).
# Dependencies: none (the card data and the budget data are handed in).
extends RefCounted


# What a card of this cost and rarity may hold.
static func allowed(card: Dictionary, budget: Dictionary) -> float:
	var n := float(card.get("cost", 0))
	var extra := float((budget["rarity"] as Dictionary).get(String(card.get("rarity", "common")), 0.0))
	if String(card.get("type", "")) == "creature":
		return float(budget["creature_per_cost"]) * n + float(budget["creature_base"]) + extra
	return float(budget["spell_per_cost"]) * n + float(budget["spell_base"]) + extra


# What the card spends: attack + health, its keywords, its effects. `cards` = every card (summoned tokens are priced
# by their own attack + health).
static func spent(card: Dictionary, budget: Dictionary, cards: Dictionary) -> float:
	var out := float(card.get("attack", 0)) + float(card.get("health", 0))
	var kw: Dictionary = budget["keywords"]
	for k: Variant in card.get("keywords", []):
		out += float(kw.get(String(k), 0.0))
	for e: Dictionary in card.get("effects", []):
		out += _effect(e, budget, cards)
	return out


# Spent minus allowed: above 0 = too strong for its cost, below 0 = too weak.
static func gap(card: Dictionary, budget: Dictionary, cards: Dictionary) -> float:
	return spent(card, budget, cards) - allowed(card, budget)


static func _effect(e: Dictionary, budget: Dictionary, cards: Dictionary) -> float:
	var what := String(e.get("do", ""))
	var per: Dictionary = budget["effects"]
	var worth := 0.0
	match what:
		"summon":
			var token: Dictionary = cards.get(String(e.get("card", "")), {})
			worth = (float(token.get("attack", 1)) + float(token.get("health", 1))) * float(e.get("count", 1)) * float(per["summon"])
		"buff":
			worth = (float(e.get("attack", 0)) + float(e.get("health", 0))) * float(per["buff"])
		"give":
			worth = float((budget["keywords"] as Dictionary).get(String(e.get("keyword", "")), 0.0)) + float(per["give_flat"])
		_:
			if per.has(what + "_flat"):
				worth = float(per[what + "_flat"])
			else:
				worth = float(e.get("amount", e.get("count", 1))) * float(per.get(what, 0.0))
	worth *= float((budget["targets"] as Dictionary).get(String(e.get("to", "")), 1.0))
	worth *= float((budget["repeats"] as Dictionary).get(String(e.get("when", "")), 1.0))
	if e.has("per"):
		worth *= 2.0  # "for each ..." effects grow with the board: counted as about two
	return worth
