# Purpose: pure geometry for the Omaha map: lat/lon to game metres, point-in-polygon, oriented-rect test, district lookup.
# Dependencies: none (no Node, no rendering). Same projection as tools/omaha_bake.py.
extends RefCounted


# Game-space position (x east, z south) of a lat/lon, given the map origin and scale from data/omaha/map.json.
static func to_xz(lat: float, lon: float, origin_lat: float, origin_lon: float, scale: float) -> Vector2:
	var kx := 111320.0 * cos(deg_to_rad(origin_lat))
	return Vector2((lon - origin_lon) * kx / scale, -(lat - origin_lat) * 110574.0 / scale)


# `flat` is [x0, z0, x1, z1, ...].
static func point_in_poly(p: Vector2, flat: Array) -> bool:
	var inside := false
	var n := flat.size() >> 1
	var j := n - 1
	for i in n:
		var xi := float(flat[i * 2])
		var zi := float(flat[i * 2 + 1])
		var xj := float(flat[j * 2])
		var zj := float(flat[j * 2 + 1])
		if (zi > p.y) != (zj > p.y) and p.x < (xj - xi) * (p.y - zi) / (zj - zi) + xi:
			inside = not inside
		j = i
	return inside


# Is p inside the box centred (cx, cz) of size (w, d) rotated by ang radians? `pad` grows the box.
static func in_rect(p: Vector2, cx: float, cz: float, w: float, d: float, ang: float, pad: float = 0.0) -> bool:
	var c := cos(-ang)
	var s := sin(-ang)
	var dx := p.x - cx
	var dz := p.y - cz
	var lx := dx * c - dz * s
	var lz := dx * s + dz * c
	return absf(lx) <= w * 0.5 + pad and absf(lz) <= d * 0.5 + pad


# Districts: [{"id", "pos": Vector2, "radius": float, ...}]. Returns the one whose centre p is closest to relative
# to its radius, or {} when p is further than 1.5 radii from all of them.
static func district_at(p: Vector2, districts: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_ratio := 1.5
	for d: Dictionary in districts:
		var ratio := p.distance_to(d["pos"]) / float(d["radius"])
		if ratio < best_ratio:
			best_ratio = ratio
			best = d
	return best
