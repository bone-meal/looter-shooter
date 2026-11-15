# Purpose: pure rule for where the fantasy world's cliff shortcuts are (sea step 3d): in some cells of open country a
# cliff is found (ground rising 5.5-20 m within 2.5-4.5 m, dry and fairly level at its foot and on top, away from
# places and houses) and gets a way up of the kind its region allows (data/fantasy/agility.json shortcuts). The same
# map gives the same spots on every machine.
# Dependencies: core/fantasy_terrain.gd (height, water, normal, regions, places), core/fantasy_layout.gd (blocked).
extends RefCounted

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")


# The shortcut of one cell ({} = none): {"key", "kind", "base": Vector3, "top": Vector3, "dir": Vector2}.
static func spot(terrain: FantasyTerrain, layout: RefCounted, cell: Vector2i, cfg: Dictionary) -> Dictionary:
	var size := float(cfg["cell"])
	if FantasyTerrain.hash01(cell.x, cell.y, 901) > float(cfg["chance"]):
		return {}
	for k in 10:
		var x := (float(cell.x) + FantasyTerrain.hash01(cell.x, cell.y, 910 + k * 2)) * size
		var z := (float(cell.y) + FantasyTerrain.hash01(cell.x, cell.y, 911 + k * 2)) * size
		if terrain.water_at(x, z) != "" or terrain.normal(x, z).y < 0.85 or _near_place(terrain, x, z) or bool(layout.call("blocked", x, z, 1.0)):
			continue
		var turn := FantasyTerrain.hash01(cell.x, cell.y, 940 + k) * TAU
		for d in 8:
			var dir := Vector2.from_angle(turn + float(d) * TAU / 8.0)
			var found := _climb(terrain, x, z, dir)
			if found.is_empty():
				continue
			var kinds: Array = cfg["regions"].get(String(terrain.region_at(x, z)["id"]), [])
			if kinds.is_empty():
				return {}
			found["kind"] = String(kinds[int(FantasyTerrain.hash01(cell.x, cell.y, 960) * float(kinds.size())) % kinds.size()])
			found["key"] = "%d:%d" % [cell.x, cell.y]
			found["dir"] = dir
			return found
	return {}


# Walks from (x, z) along `dir` to the foot of a cliff and up to its top: {"base", "top"} or {} when there is none.
static func _climb(terrain: FantasyTerrain, x: float, z: float, dir: Vector2) -> Dictionary:
	var at := Vector2(x, z)
	var h := terrain.height(x, z)
	for _step in 8:  # up to 4 m of gentle ground to the foot
		var next := at + dir * 0.5
		if terrain.height(next.x, next.y) - terrain.height(at.x, at.y) > 0.35:
			break
		at = next
	var foot := terrain.height(at.x, at.y)
	if absf(foot - h) > 1.0:
		return {}
	for reach in [2.5, 3.5, 4.5]:  # a real cliff: the rise comes within a few steps
		var top := at + dir * float(reach)
		var rise := terrain.height(top.x, top.y) - foot
		if rise < 5.5 or rise > 20.0:
			continue
		var land := top + dir * 1.5  # stepping off onto the top
		if terrain.water_at(land.x, land.y) != "" or terrain.normal(land.x, land.y).y < 0.8:
			continue
		if absf(terrain.height(land.x, land.y) - terrain.height(top.x, top.y)) > 1.2:
			continue
		return {"base": Vector3(at.x, foot, at.y), "top": Vector3(land.x, terrain.height(land.x, land.y), land.y)}
	return {}


static func _near_place(terrain: FantasyTerrain, x: float, z: float) -> bool:
	for place: Dictionary in terrain.places:
		if Vector2(x - float(place["pos"][0]), z - float(place["pos"][1])).length() < float(place["flat"]) + 15.0:
			return true
	return false
