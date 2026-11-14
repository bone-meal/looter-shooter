# Purpose: buying at the card vending machine of "You got me Lobster?" (data/tcg/packs.json prices and rows, locked):
# single pack 300, bundles of 5 / 10 packs 1 400 / 2 700, a 50-pack box 12 000 (with its guarantee), starter decks
# 2 000 each (their 20 cards and leader). Takes the chips from the wallet and puts the goods in the collection. Pure.
# Dependencies: core/wallet.gd and core/tcg/collection.gd (handed in).
extends RefCounted


# item = a "rows" item id of packs.json ("single", "bundle_5", "bundle_10", "box") or "starter:<id>".
# Returns "" when bought, else why not.
static func buy(item: String, wallet: RefCounted, owned: RefCounted, cfg: Dictionary, starters: Dictionary) -> String:
	var prices: Dictionary = cfg["prices"]
	if item.begins_with("starter:"):
		var sid := item.get_slice(":", 1)
		if not starters.has(sid):
			return "no such deck"
		if not bool(wallet.call("spend", int(prices["starter"]))):
			return "not enough chips"
		owned.call("give_deck_cards", starters[sid])
		return ""
	var found: Dictionary = {}
	for row: Dictionary in cfg["rows"]:
		for it: Dictionary in row["items"]:
			if String(it["id"]) == item:
				found = it
	if found.is_empty() or not prices.has(item):
		return "no such item"
	if not bool(wallet.call("spend", int(prices[item]))):
		return "not enough chips"
	if bool(found.get("box", false)):
		owned.call("add_box", int(found["packs"]), int(cfg["box"]["legendaries"]), int(cfg["box"]["epics"]))
	else:
		owned.call("add_pack", "standard", int(found["packs"]))
	return ""
