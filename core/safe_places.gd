# Purpose: the safe places of the fantasy world (towns, villages, the starting farm): creatures do not enter them and
# drop the chase when their prey is inside one. Pure rules: where the borders are and where a creature that must
# turn back should walk to. Flat map metres; no nodes.
# Dependencies: none. Numbers: data/fantasy/squad.json "safe". Used by game/squad_command.gd (and tools/fantasy_check.gd).
extends RefCounted

var _at := PackedVector2Array()  # the middle of each safe place
var _border := PackedFloat32Array()  # how far from its middle creatures are kept
var _retreat := 25.0  # how far beyond the border a creature that gave up walks


# places: the world's places ({"pos": [x, z], "kind", "flat"}); rule: {"kinds": [...], "margin": m, "retreat": m}.
func setup(places: Array, rule: Dictionary) -> void:
	_at.clear()
	_border.clear()
	_retreat = float(rule["retreat"])
	var kinds: Array = rule["kinds"]
	for place: Dictionary in places:
		if kinds.has(String(place["kind"])):
			_at.append(Vector2(float(place["pos"][0]), float(place["pos"][1])))
			_border.append(float(place["flat"]) + float(rule["margin"]))


func count() -> int:
	return _at.size()


# The index of the safe place this spot lies in, or -1.
func place_at(spot: Vector2) -> int:
	for i in _at.size():
		if spot.distance_squared_to(_at[i]) < _border[i] * _border[i]:
			return i
	return -1


# Where a creature at `creature` hunting somebody at `prey` must walk instead, or Vector2.INF when no safe place is
# in its way. Inside a border it leaves by the shortest way; when its prey is inside one it backs off to `retreat`
# metres beyond that border and stays there.
func turn_back(creature: Vector2, prey: Vector2) -> Vector2:
	var zone := place_at(creature)
	if zone < 0:
		zone = place_at(prey)
	if zone < 0:
		return Vector2.INF
	var out := creature - _at[zone]
	if out.length() < 0.01:
		out = Vector2.RIGHT
	var keep := _border[zone] + _retreat
	return creature if out.length() >= keep else _at[zone] + out.normalized() * keep
