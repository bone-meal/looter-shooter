# Purpose: opening the player's own packs of "You got me Lobster?": which pack is next (standard packs first, then box
# packs), a roll that can still be taken back (the pack is rolled when the tear starts, so a god pack can tear gold, but
# it only counts once the tear is finished: until then the pity and box counters can be put back), committing it (the
# pack leaves, the cards join the collection, each marked "new" when it was not owned before) and "Open all". Pure.
# Dependencies: core/tcg/pack_roll.gd; core/tcg/card_db.gd and core/tcg/collection.gd handed in.
extends RefCounted

const PackRoll = preload("res://core/tcg/pack_roll.gd")

const KINDS := ["standard", "box"]


static func next_kind(owned: RefCounted) -> String:
	var packs: Dictionary = owned.get("packs")
	for k: String in KINDS:
		if int(packs.get(k, 0)) > 0:
			return k
	return ""


# Rolls the next pack without taking it: {"kind", "cards", "god", "undo"} or {} when there is none.
static func roll(db: RefCounted, owned: RefCounted, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var kind := next_kind(owned)
	if kind == "":
		return {}
	var before := {"pity": (owned.get("pity") as Dictionary).duplicate(), "box": (owned.get("box") as Dictionary).duplicate()}
	var out: Dictionary = PackRoll.open(db, owned, cfg, rng, kind)
	out["kind"] = kind
	out["undo"] = before
	return out


# The roll was never torn open: the counters go back to how they were.
static func undo(owned: RefCounted, rolled: Dictionary) -> void:
	if rolled.is_empty():
		return
	(owned.get("pity") as Dictionary).merge(rolled["undo"]["pity"], true)
	(owned.get("box") as Dictionary).merge(rolled["undo"]["box"], true)


# The tear is done: the pack goes, its cards come in. Returns the cards, each with "new".
static func commit(owned: RefCounted, rolled: Dictionary) -> Array:
	if rolled.is_empty() or not owned.take_pack(String(rolled["kind"])):
		return []
	var out: Array = []
	for c: Dictionary in rolled["cards"]:
		var card := c.duplicate()
		card["new"] = owned.count(String(c["id"]), "*", bool(c["leader"])) == 0
		owned.add(String(c["id"]), String(c["finish"]), 1, bool(c["leader"]))
		out.append(card)
	return out


# Every pack left, at once: {"packs": n, "cards": [...], "gods": n}.
static func open_all(db: RefCounted, owned: RefCounted, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"packs": 0, "cards": [], "gods": 0}
	while next_kind(owned) != "":
		var rolled := roll(db, owned, cfg, rng)
		(out["cards"] as Array).append_array(commit(owned, rolled))
		out["packs"] = int(out["packs"]) + 1
		if bool(rolled["god"]):
			out["gods"] = int(out["gods"]) + 1
	return out
