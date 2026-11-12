# Purpose: the bank on the spawn island: slots for guns and items that are safe when their owner goes down, and the
# upgrades that add slots (first for points, then for casino coins). Things move in and out through the inventory's
# mouse stack. Pure rules: no nodes, no rendering.
# Dependencies: core/inventory_state.gd (its mouse stack, and how a stack is saved and checked). Numbers come from
# data/bank.json, passed to the constructor.
extends RefCounted

var level := 0  # upgrades bought

var _cfg: Dictionary
var _slots: Array[Dictionary] = []


func _init(cfg: Dictionary) -> void:
	_cfg = cfg
	_fit()


func capacity() -> int:
	return int(_cfg["slots"]) + int(_cfg["per_upgrade"]) * level


func most_slots() -> int:
	return int(_cfg["slots"]) + int(_cfg["per_upgrade"]) * (_cfg["upgrades"] as Array).size()


func stack(slot: int) -> Dictionary:
	return _slots[slot]


func used() -> int:
	var n := 0
	for s in _slots:
		n += 0 if s.is_empty() else 1
	return n


# Click on a bank slot: what is there and what the mouse holds change places (either may be nothing).
func click(slot: int, inventory: RefCounted) -> void:
	if slot < 0 or slot >= capacity():
		return
	var here := _slots[slot]
	_slots[slot] = inventory.cursor
	inventory.cursor = here


# What the next upgrade costs: {"points": n} or {"coins": n}; {} when the bank is as big as it gets.
func next_upgrade() -> Dictionary:
	var list: Array = _cfg["upgrades"]
	return list[level] if level < list.size() else {}


# Call once the price has been paid.
func upgrade() -> void:
	if not next_upgrade().is_empty():
		level += 1
		_fit()


func _fit() -> void:
	while _slots.size() < capacity():
		_slots.append({})


func to_dict(inventory: RefCounted) -> Dictionary:
	var out: Array = []
	for s in _slots:
		out.append(inventory.stack_to_saved(s))
	return {"level": level, "slots": out}


# Anything that is not a known item or a valid gun is left out; a level beyond the last upgrade is cut back.
func from_dict(d: Variant, inventory: RefCounted) -> void:
	level = 0
	_slots.clear()
	if d is Dictionary and (d.get("level") is int or d.get("level") is float):
		level = clampi(int(d["level"]), 0, (_cfg["upgrades"] as Array).size())
	_fit()
	if d is Dictionary and d.get("slots") is Array:
		var saved: Array = d["slots"]
		for i in mini(saved.size(), capacity()):
			_slots[i] = inventory.stack_from_saved(saved[i])
