# Purpose: the play mats of "You got me Lobster?" (data/tcg/mats.json): which a player owns (the start mat always),
# the one in use, a rare pull from an opened pack (one the player does not own yet), buying at the card machine with
# chips, and the win-milestone mats (wins against players only, locked). Pure.
# Dependencies: core/tcg/collection.gd handed in (its `mats`, `mat`, `record`); a chip wallet with balance / spend.
extends RefCounted


static func owns(owned: RefCounted, cfg: Dictionary, id: String) -> bool:
	var m: Dictionary = (cfg.get("mats", {}) as Dictionary).get(id, {})
	return not m.is_empty() and (bool(m.get("start", false)) or (owned.get("mats") as Array).has(id))


# The mat on the player's half of the table.
static func current(owned: RefCounted, cfg: Dictionary) -> String:
	var id := String(owned.get("mat"))
	return id if owns(owned, cfg, id) else String(cfg.get("default", ""))


static func choose(owned: RefCounted, cfg: Dictionary, id: String) -> bool:
	if not owns(owned, cfg, id):
		return false
	owned.set("mat", id)
	return true


static func give(owned: RefCounted, id: String) -> void:
	var list: Array = owned.get("mats")
	if not list.has(id):
		list.append(id)


# A pack's rare mat pull: "" most of the time, else a pack mat the player does not own (never a doubled one).
static func pull(owned: RefCounted, cfg: Dictionary, rng: RandomNumberGenerator) -> String:
	var one_in := int(cfg.get("pack_one_in", 0))
	if one_in <= 0 or rng.randi_range(1, one_in) != 1:
		return ""
	var left: Array = []
	for id: String in cfg.get("mats", {}):
		if bool(cfg["mats"][id].get("pack", false)) and not owns(owned, cfg, id):
			left.append(id)
	return "" if left.is_empty() else String(left[rng.randi_range(0, left.size() - 1)])


# Buys a machine mat: "" when done, else why not.
static func buy(owned: RefCounted, cfg: Dictionary, wallet: RefCounted, id: String) -> String:
	var m: Dictionary = (cfg.get("mats", {}) as Dictionary).get(id, {})
	if not m.has("buy"):
		return "That mat is not sold"
	if owns(owned, cfg, id):
		return "You own it already"
	if not bool(wallet.call("spend", int(m["buy"]))):
		return "Not enough chips"
	give(owned, id)
	return ""


# Gives every win-milestone mat the player's wins against players have reached. Returns the new ones.
static func milestones(owned: RefCounted, cfg: Dictionary) -> Array:
	var wins := int((owned.get("record") as Dictionary).get("wins", 0))
	var out: Array = []
	for id: String in cfg.get("mats", {}):
		var need := int(cfg["mats"][id].get("wins", 0))
		if need > 0 and wins >= need and not owns(owned, cfg, id):
			give(owned, id)
			out.append(id)
	return out


# How a mat comes, in a few words (for the binder's mat list).
static func how(cfg: Dictionary, id: String) -> String:
	var m: Dictionary = (cfg.get("mats", {}) as Dictionary).get(id, {})
	if bool(m.get("start", false)):
		return "Everyone has it"
	if bool(m.get("pack", false)):
		return "Rare pull from packs"
	if m.has("buy"):
		return "%d chips at the card machine" % int(m["buy"])
	if m.has("wins"):
		return "%d wins against players" % int(m["wins"])
	return ""
