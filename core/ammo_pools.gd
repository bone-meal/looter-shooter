# Purpose: spare ammunition. One pool per gun body (pistol, AK, M16 ...), shared by every gun of that body the player
# owns; a reload moves rounds from the pool into the gun. Pure rules: no nodes, no rendering.
# Dependencies: none. Pool sizes come from data/weapons.json ("ammo_pool" of each weapon), passed to the constructor.
extends RefCounted

var bonus_pct := 0.0  # makes every pool this much bigger (a perk)

var _size := {}  # body -> pool size without the bonus
var _left := {}  # body -> rounds in the pool


func _init(weapons: Dictionary) -> void:
	for body: String in weapons:
		_size[body] = int(weapons[body]["ammo_pool"])
	fill_all()


func bodies() -> Array:
	return _size.keys()


func size_of(body: String) -> int:
	return roundi(float(_size.get(body, 0)) * (1.0 + bonus_pct / 100.0))


func left(body: String) -> int:
	return int(_left.get(body, 0))


# Takes up to `wanted` rounds out (a reload). Returns how many there were to take.
func take(body: String, wanted: int) -> int:
	var taken := clampi(wanted, 0, left(body))
	_left[body] = left(body) - taken
	return taken


# Puts rounds in, up to the pool's size. `over` = no limit: rounds coming back out of the player's own gun are
# never thrown away. Returns how many went in.
func give(body: String, amount: int, over: bool = false) -> int:
	if not _size.has(body) or amount <= 0:
		return 0
	var room := amount if over else clampi(size_of(body) - left(body), 0, amount)
	_left[body] = left(body) + room
	return room


func is_full(body: String) -> bool:
	return left(body) >= size_of(body)


func fill(body: String) -> void:
	if _size.has(body):
		_left[body] = maxi(left(body), size_of(body))


func fill_all() -> void:
	for body: String in _size:
		fill(body)


func to_dict() -> Dictionary:
	return _left.duplicate()


# A missing or broken entry gives a full pool; nothing is ever more than twice the pool's size.
func from_dict(d: Variant) -> void:
	fill_all()
	if not d is Dictionary:
		return
	for body: String in _size:
		var saved: Variant = (d as Dictionary).get(body)
		if saved is int or saved is float:
			_left[body] = clampi(int(saved), 0, size_of(body) * 2)
