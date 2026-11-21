# Purpose: the skinned knives a player owns (polish1 D5b, diary/DESIGN_KNIVES.md): each its own item {finish, type,
# pattern, wear, strength, kills} kept in a list, one of them carried (`on`, -1 = the character's own rolled knife),
# saved in the profile ("knives") and checked against the rules on load (unknown or odd rows dropped). Kills made with
# the carried knife are counted on it (its level comes from them). Pure rules.
# Dependencies: core/knife_skins.gd (the rules object passed in).
extends RefCounted

const MOST := 200

var rules: RefCounted
var items: Array = []
var on := -1


func _init(knife_rules: RefCounted) -> void:
	rules = knife_rules


func carried() -> Dictionary:
	return items[on] if on >= 0 and on < items.size() else {}


func add(item: Dictionary) -> bool:
	if items.size() >= MOST or rules.call("check", item) != "":
		return false
	items.append(item)
	return true


# Takes knife `index` out (a trade); the carried one moves with the list.
func remove(index: int) -> Dictionary:
	if index < 0 or index >= items.size():
		return {}
	var out: Dictionary = items[index]
	items.remove_at(index)
	if on == index:
		on = -1
	elif on > index:
		on -= 1
	return out


func equip(index: int) -> void:
	on = index if index >= 0 and index < items.size() else -1


# A kill with the carried knife: returns the new level when it went up, else 0.
func count_kill() -> int:
	var k := carried()
	if k.is_empty():
		return 0
	var before := int(rules.call("level", k))
	k["kills"] = mini(int(k.get("kills", 0)) + 1, 10000000)
	var after := int(rules.call("level", k))
	return after if after > before else 0


func to_dict() -> Dictionary:
	return {"items": items.duplicate(true), "on": on}


func from_dict(d: Variant) -> void:
	items.clear()
	on = -1
	if not d is Dictionary:
		return
	for row: Variant in (d as Dictionary).get("items", []):
		if row is Dictionary and rules.call("check", row) == "" and items.size() < MOST:
			var r: Dictionary = row
			items.append({"finish": String(r["finish"]), "type": String(r["type"]), "pattern": int(r["pattern"]), "wear": float(r["wear"]), "strength": float(r["strength"]), "kills": int(r["kills"])})
	var want := int((d as Dictionary).get("on", -1)) if ((d as Dictionary).get("on", -1) is int or (d as Dictionary).get("on", -1) is float) else -1
	on = want if want >= 0 and want < items.size() else -1


# Order to show them: the carried one first, then by tier (pony first), then by level.
func order() -> Array:
	var tiers := ["pony", "gold", "purple", "blue"]
	var idx: Array = range(items.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		if (a == on) != (b == on):
			return a == on
		var ta := tiers.find(String(rules.call("finish", String(items[a]["finish"])).get("tier", "")))
		var tb := tiers.find(String(rules.call("finish", String(items[b]["finish"])).get("tier", "")))
		if ta != tb:
			return ta < tb
		return int(items[a]["kills"]) > int(items[b]["kills"]))
	return idx
