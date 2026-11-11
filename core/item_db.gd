# Purpose: read-only lookup of item definitions (name, flavor text, kind, stack size). Pure data, no nodes.
# Dependencies: none. Data comes from data/items.json (checked by tools/validate_data.gd).
extends RefCounted

var _items: Dictionary


func _init(data: Dictionary) -> void:
	_items = data.get("items", {})


func has_item(id: String) -> bool:
	return _items.has(id)


func item_name(id: String) -> String:
	return String(_items[id]["name"])


func flavor(id: String) -> String:
	return String(_items[id]["flavor"])


func kind(id: String) -> String:
	return String(_items[id]["kind"])


# Equipment slot an armor item goes in ("ring" fits ring_1 and ring_2), or "" for non-armor.
func equip_slot(id: String) -> String:
	return String(_items[id].get("slot", ""))


# Raw stats of an item: defense, block, resist, ability (missing keys mean zero / none).
func stats(id: String) -> Dictionary:
	return _items[id]


# Short readable stat lines for tooltips.
func stat_lines(id: String) -> Array[String]:
	var lines: Array[String] = []
	var it: Dictionary = _items[id]
	if float(it.get("defense", 0)) > 0:
		lines.append("Defense %d" % int(it["defense"]))
	if float(it.get("block", 0)) > 0:
		lines.append("Block %d%%" % roundi(float(it["block"]) * 100.0))
	for e in it.get("resist", {}):
		lines.append("%s resist %d%%" % [String(e).capitalize(), roundi(float(it["resist"][e]) * 100.0)])
	if String(it.get("ability", "")) == "auto_reload":
		lines.append("Left click reloads an empty gun")
	return lines


func stack_max(id: String) -> int:
	return int(_items[id]["stack_max"])


# IDs of every item with kind "weapon" (the ID is also the weapon ID in data/weapons.json).
func weapon_ids() -> Array[String]:
	return ids_of_kind("weapon")


func ids_of_kind(wanted: String) -> Array[String]:
	var ids: Array[String] = []
	for id in _items:
		if kind(id) == wanted:
			ids.append(id)
	return ids
