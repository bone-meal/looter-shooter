# Purpose: the region gates (sea step 13a, LOCKED: a region opens with a ship part from the region before it; the
# hazard hurts, the part protects). Pure rules: which regions a ship with these parts may sail in, and for a sea
# position how strong the hazard is (0 in open water, rising to 1 over ramp_m metres in from the nearest open cell)
# and which way is back to open water. Sea coordinates as core/sea/sea_map.gd.
# Dependencies: core/sea/sea_map.gd (passed in), data/sea/gates.json.
extends RefCounted

var cfg: Dictionary
var _map: RefCounted


func _init(config: Dictionary, map: RefCounted) -> void:
	cfg = config
	_map = map


func gate_of(region_id: String) -> Dictionary:
	return (cfg["regions"] as Dictionary).get(region_id, {"part": "", "kind": "deep_squall", "notice": ""})


func is_open(region_id: String, fitted: Array) -> bool:
	var g := gate_of(region_id)
	if bool(g.get("open", false)):
		return true
	var part := String(g.get("part", ""))
	return part != "" and fitted.has(part)


# Every gate part the data names (what the shipyard may fit besides the crane).
func parts() -> Array:
	var out: Array = []
	for id: String in cfg["regions"]:
		var p := String((cfg["regions"][id] as Dictionary).get("part", ""))
		if p != "" and not out.has(p):
			out.append(p)
	return out


# {"s": 0..1, "back": Vector2 (unit, toward open water), "region": id, "notice": text} for a ship with `parts` at (x, z).
func danger(x: float, z: float, parts_fitted: Array) -> Dictionary:
	var here := String(_map.call("region_id_at", x, z))
	if here == "" or is_open(here, parts_fitted):
		return {"s": 0.0, "back": Vector2.ZERO, "region": here, "notice": ""}
	var cell := float(_map.get("cell"))
	var grid: Array = _map.get("grid")
	var half_w := float(_map.call("width")) * 0.5
	var half_h := float(_map.call("height")) * 0.5
	var p := Vector2(x, z)
	var best := INF
	var best_point := p
	for row in grid.size():
		for col in (grid[row] as Array).size():
			if not is_open(String(grid[row][col]), parts_fitted):
				continue
			var lo := Vector2(float(col) * cell - half_w, float(row) * cell - half_h)
			var near := Vector2(clampf(x, lo.x, lo.x + cell), clampf(z, lo.y, lo.y + cell))
			var d := p.distance_to(near)
			if d < best:
				best = d
				best_point = near
	var g := gate_of(here)
	var s := 1.0 if best == INF else clampf(best / float(cfg["ramp_m"]), 0.0, 1.0)
	var back := (best_point - p).normalized() if best < INF and best > 0.001 else Vector2.ZERO
	return {"s": s, "back": back, "region": here, "notice": String(g.get("notice", ""))}
