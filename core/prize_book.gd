# Purpose: (polish1 item 75) the pachinko prize counter's rules: prize tickets buy what data/pachinko.json "prizes"
# lists. A prize gives "tcg:<unopened item>" (card packs into the collection) or "crate:<crate id>" (a gun crate onto
# the case shelf). Pure: no rendering, no saving.
# Dependencies: core/tcg/collection.gd (add_pack / add_item, like core/tcg/pack_shop.gd), core/case_shelf.gd (add),
# data/pachinko.json, data/tcg/packs.json (how many packs each unopened item holds).
extends RefCounted


static func find(prizes: Array, id: String) -> Dictionary:
	for p: Dictionary in prizes:
		if String(p["id"]) == id:
			return p
	return {}


# Spends the prize's tickets and hands it over. Returns the tickets left, or -1 when it is unknown or too dear.
static func redeem(prizes: Array, id: String, tickets: int, cards: RefCounted, cases: RefCounted, packs_cfg: Dictionary) -> int:
	var prize := find(prizes, id)
	if prize.is_empty() or tickets < int(prize["tickets"]):
		return -1
	var gives := String(prize["gives"])
	var what := gives.get_slice(":", 1)
	if gives.begins_with("tcg:"):
		var packs := 0
		for row: Dictionary in packs_cfg["rows"]:
			for it: Dictionary in row["items"]:
				if String(it["id"]) == what and not bool(it.get("box", false)):
					packs = int(it["packs"])
		if packs <= 0:
			return -1
		cards.call("add_pack", "standard", packs)
		cards.call("add_item", what)
	elif gives.begins_with("crate:"):
		cases.call("add", what)
	else:
		return -1
	return tickets - int(prize["tickets"])
