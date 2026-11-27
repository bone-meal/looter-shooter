# Purpose: pure compiler (polish1 F1a): turns a country's SHAPE (data/fantasy/countries/<id>.json "shape", cut from
# the continent by tools/worldgen/export_countries.py, then hand edited) into grids the land is read from: the big
# height (CONTOURS: the coast is the 0 m line, each ring a height; between two lines the land slopes evenly), the
# crater rings, the BORDER WALLS toward the neighbours (open at the crossings), which LOOK (a world.json region) the
# ground wears, the LAKES; and the RIVERS as lines (beds cut where the land is read, water falling toward the sea).
# The same on every machine. The compiled grids are kept in user://country_<id>_<hash>.bin (the hash of the shape and
# of COMPILER), so a country is compiled once per machine and per change. No nodes.
# Dependencies: none.
extends RefCounted

const WALL_HEIGHT := 60.0  # metres: a border wall of rough high ground (director 2026-11-27: a real barrier, was 32) ...
const WALL_HALF := 16.0  # ... this wide either side of the border line
const WALL_LEAST := 0.85  # the wall's height wanders between this share of WALL_HEIGHT and WALL_MOST (was 0.39 - 1.11: low stretches were walked over)
const WALL_MOST := 1.25
const WALL_REACH := 600.0  # metres a wall's loose end is carried on toward the sea when it stops short of it (so the two sides stay apart)
const AWAY_PAST := 24.0  # metres past the border line where the neighbour's land counts as AWAY (game/border_guard.gd turns players back there)
const GAP := 40.0  # metres round a crossing where the wall opens into a pass
const SEA_SLOPE := 0.06  # the sea floor drops this much a metre from the coast ...
const SEA_MOST := 22.0  # ... down to here
const TOP_SLOPE := 0.03  # above the highest line the land keeps rising this much a metre ...
const TOP_MOST := 18.0  # ... at most this much
const BLEND := 3  # cells: how far one look blends into the next
const RIVER_CELL := 60.0  # rivers are looked up through a grid of squares this wide
const COMPILER := 4  # raise when the compiling below changes: kept grids are then made afresh

var cell: float
var n: int
var half: float
var macro := PackedFloat32Array()  # big height at every grid corner
var looks := PackedStringArray()  # look ids, in the order of `look_weight`
var look_weight: Array = []  # PackedFloat32Array per look: its share at every grid corner (they add up to 1)
var lake_index := PackedInt32Array()  # which lake (index into `lakes`) a grid corner lies in, -1 none
var away := PackedByteArray()  # 1 = a neighbour's land beyond the border wall, AWAY_PAST and more past the line (empty: no walls)
var lakes: Array = []  # {"id", "level", "x", "z", "r" (a circle round it), "depth"}
var crossings: Array = []  # the country's crossings as they are in the data
var rivers: Array = []  # {"points": PackedVector2Array, "width": PackedFloat32Array, "level": PackedFloat32Array (water at each point)}
var _rv_a := PackedVector2Array()  # every stretch of river: its two ends, widths and water levels
var _rv_b := PackedVector2Array()
var _rv_w := PackedVector2Array()  # (width at a, width at b)
var _rv_l := PackedVector2Array()  # (level at a, level at b)
var _rv_cells := {}
var _none := PackedInt32Array()


func _init(country: Dictionary, grid: float = 16.0) -> void:
	var shape: Dictionary = country["shape"]
	var size := float(country["size"])
	cell = grid
	half = size * 0.5
	n = int(ceil(size / cell)) + 1
	crossings = country.get("crossings", [])
	var kept := "user://country_%s_%d.bin" % [String(country.get("id", "x")), hash([JSON.stringify(shape), crossings, size, grid, COMPILER])]
	if not _load(kept):
		_heights(shape)
		_craters(shape.get("craters", []))
		_walls(shape.get("walls", []), country.get("spawn", [0.0, 0.0]))
		_zones(shape.get("zones", []))
		_lakes(shape.get("lakes", []))
		_save(kept)
	_rivers(shape.get("rivers", []))


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var got: Variant = f.get_var()
	if not got is Dictionary or int((got as Dictionary).get("n", 0)) != n:
		return false
	macro = got["macro"]
	looks = got["looks"]
	look_weight = got["look_weight"]
	lake_index = got["lake_index"]
	lakes = got["lakes"]
	away = got.get("away", PackedByteArray())
	return macro.size() == n * n


func _save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_var({"n": n, "macro": macro, "looks": looks, "look_weight": look_weight, "lake_index": lake_index, "lakes": lakes, "away": away})


# ---------- reading ----------

# Whether a point lies on a neighbour's land beyond the border wall (well past the line: not on the crest or in a pass).
func away_at(x: float, z: float) -> bool:
	if away.is_empty():
		return false
	var ix := clampi(roundi((x + half) / cell), 0, n - 1)
	var iz := clampi(roundi((z + half) / cell), 0, n - 1)
	return away[iz * n + ix] == 1


func _sample(grid: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + half) / cell, 0.0, float(n - 1) - 0.001)
	var fz := clampf((z + half) / cell, 0.0, float(n - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var k := iz * n + ix
	return lerpf(lerpf(grid[k], grid[k + 1], tx), lerpf(grid[k + n], grid[k + n + 1], tx), tz)


# The big height, read smoothly between the grid corners (Catmull-Rom across 4 x 4 corners: no flat facets).
func height(x: float, z: float) -> float:
	var fx := clampf((x + half) / cell, 1.0, float(n - 2) - 0.001)
	var fz := clampf((z + half) / cell, 1.0, float(n - 2) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var rows := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for r in 4:
		var k := (iz - 1 + r) * n + ix - 1
		rows[r] = _cubic(macro[k], macro[k + 1], macro[k + 2], macro[k + 3], tx)
	return _cubic(rows[0], rows[1], rows[2], rows[3], tz)


static func _cubic(a: float, b: float, c: float, d: float, t: float) -> float:
	return b + 0.5 * t * (c - a + t * (2.0 * a - 5.0 * b + 4.0 * c - d + t * (3.0 * (b - c) + d - a)))


# Shares of each look at a point (same order as `looks`).
func weights(x: float, z: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(looks.size())
	for i in looks.size():
		out[i] = _sample(look_weight[i], x, z)
	return out


func lake_at(x: float, z: float) -> int:
	var ix := clampi(roundi((x + half) / cell), 0, n - 1)
	var iz := clampi(roundi((z + half) / cell), 0, n - 1)
	return lake_index[iz * n + ix]


# The river nearest a point within its reach: Vector3(distance to its middle line, its half width there, its water
# level there); x = INF when no river is near.
func river_near(x: float, z: float) -> Vector3:
	var here := Vector2(x, z)
	var best := Vector3(INF, 0.0, 0.0)
	var list: PackedInt32Array = _rv_cells.get(Vector2i(floori(x / RIVER_CELL), floori(z / RIVER_CELL)), _none)
	for s in list:
		var a := _rv_a[s]
		var b := _rv_b[s]
		var t := clampf((here - a).dot(b - a) / maxf((b - a).length_squared(), 0.001), 0.0, 1.0)
		var d := here.distance_to(a + (b - a) * t)
		if d < best.x:
			best = Vector3(d, lerpf(_rv_w[s].x, _rv_w[s].y, t) * 0.5, lerpf(_rv_l[s].x, _rv_l[s].y, t))
	return best


# ---------- building ----------

# Cells inside any of the rings (even-odd: a ring inside a ring cuts a hole), one byte a grid corner.
func _fill(ring_list: Array) -> PackedByteArray:
	var rows: Array = []
	rows.resize(n)
	for j in n:
		rows[j] = PackedFloat32Array()
	for ring: Array in ring_list:
		var count := ring.size()
		for i in count:
			var a: Array = ring[i]
			var b: Array = ring[(i + 1) % count]
			var az := (float(a[1]) + half) / cell
			var bz := (float(b[1]) + half) / cell
			if is_equal_approx(az, bz):
				continue
			var ax := (float(a[0]) + half) / cell
			var bx := (float(b[0]) + half) / cell
			var lo := maxi(int(ceil(minf(az, bz))), 0)
			var hi := mini(int(ceil(maxf(az, bz))) - 1, n - 1)
			for j in range(lo, hi + 1):
				var row: PackedFloat32Array = rows[j]  # (a packed array taken from an Array is a copy: put it back)
				row.append(ax + (bx - ax) * (float(j) - az) / (bz - az))
				rows[j] = row
	var mask := PackedByteArray()
	mask.resize(n * n)
	for j in n:
		var xs: PackedFloat32Array = rows[j]
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			for i in range(maxi(int(ceil(xs[k])), 0), mini(int(ceil(xs[k + 1])) - 1, n - 1) + 1):
				mask[j * n + i] = 1
			k += 2
	return mask


# Exact distance (in cells) from every grid corner to the nearest corner where mask == want (Felzenszwalb).
func _distance(mask: PackedByteArray, want: int) -> PackedFloat32Array:
	const FAR := 1.0e12
	var g := PackedFloat32Array()
	g.resize(n * n)
	for k in n * n:
		g[k] = 0.0 if mask[k] == want else FAR
	var f := PackedFloat32Array()
	f.resize(n)
	for pass_index in 2:  # columns, then rows
		for line in n:
			for q in n:
				f[q] = g[q * n + line] if pass_index == 0 else g[line * n + q]
			var d := _edt_1d(f)
			for q in n:
				if pass_index == 0:
					g[q * n + line] = d[q]
				else:
					g[line * n + q] = d[q]
	for k in n * n:
		g[k] = sqrt(g[k])
	return g


func _edt_1d(f: PackedFloat32Array) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(n)
	var v := PackedInt32Array()
	v.resize(n)
	var zb := PackedFloat32Array()
	zb.resize(n + 1)
	var k := 0
	v[0] = 0
	zb[0] = -INF
	zb[1] = INF
	for q in range(1, n):
		var s := ((f[q] + float(q * q)) - (f[v[k]] + float(v[k] * v[k]))) / float(2 * q - 2 * v[k])
		while s <= zb[k]:
			k -= 1
			s = ((f[q] + float(q * q)) - (f[v[k]] + float(v[k] * v[k]))) / float(2 * q - 2 * v[k])
		k += 1
		v[k] = q
		zb[k] = s
		zb[k + 1] = INF
	k = 0
	for q in n:
		while zb[k + 1] < float(q):
			k += 1
		d[q] = float((q - v[k]) * (q - v[k])) + f[v[k]]
	return d


# The big height from the contour lines: the land between two lines slopes evenly from one to the next.
func _heights(shape: Dictionary) -> void:
	var lines: Array = shape.get("contours", [])
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["height"]) < float(b["height"]))
	var level := PackedFloat32Array()
	var inside: Array = []  # per line: distance from inside corners out to the line's outside
	var outside: Array = []  # per line: distance from outside corners in to the line
	var index := PackedInt32Array()  # how many lines a corner lies inside
	index.resize(n * n)
	for line: Dictionary in lines:
		var mask := _fill(line["rings"])
		level.append(float(line["height"]))
		inside.append(_distance(mask, 0))
		outside.append(_distance(mask, 1))
		for k in n * n:
			index[k] += mask[k]
	macro.resize(n * n)
	var top := level.size()
	for k in n * n:
		var at := index[k]
		if at == 0:
			macro[k] = -minf(0.5 + maxf((outside[0] as PackedFloat32Array)[k] - 0.5, 0.0) * cell * SEA_SLOPE, SEA_MOST) if top > 0 else -SEA_MOST
		elif at >= top:
			macro[k] = level[top - 1] + minf(maxf((inside[top - 1] as PackedFloat32Array)[k] - 0.5, 0.0) * cell * TOP_SLOPE, TOP_MOST)
		else:
			var a := maxf((inside[at - 1] as PackedFloat32Array)[k] - 0.5, 0.0)
			var b := maxf((outside[at] as PackedFloat32Array)[k] - 0.5, 0.0)
			macro[k] = lerpf(level[at - 1], level[at], a / maxf(a + b, 0.001))
	macro = _blur(macro)  # the straight ramps between the lines are rounded off
	for k in n * n:
		macro[k] = maxf(macro[k], 0.6) if index[k] > 0 else minf(macro[k], -0.3)  # the coast stays where its line is


func _craters(list: Array) -> void:
	for c: Dictionary in list:
		var cx := float(c["pos"][0])
		var cz := float(c["pos"][1])
		var r := float(c["radius"])
		var rim := float(c.get("rim", 20.0))
		var floor_drop := float(c.get("floor", -8.0))
		for j in n:
			for i in n:
				var d := Vector2(-half + i * cell - cx, -half + j * cell - cz).length() / r
				if d > 2.2:
					continue
				var k := j * n + i
				macro[k] += rim * exp(-pow((d - 1.0) / 0.14, 2.0)) + floor_drop * pow(clampf(1.0 - d, 0.0, 1.0), 0.6)


# Rough high ground along the borders with the neighbours, open round each crossing.
func _walls(list: Array, spawn: Array) -> void:
	if list.is_empty():
		return
	var seeds := PackedByteArray()
	seeds.resize(n * n)
	var line := PackedByteArray()  # the border as the two sides see it: the walls, carried on to the sea at their loose ends
	line.resize(n * n)
	for wall: Array in list:
		for i in wall.size() - 1:
			var a := Vector2(float(wall[i][0]), float(wall[i][1]))
			var b := Vector2(float(wall[i + 1][0]), float(wall[i + 1][1]))
			var steps := maxi(int(a.distance_to(b) / (cell * 0.5)), 1)
			for s in steps + 1:
				var p := a.lerp(b, float(s) / float(steps))
				var ix := roundi((p.x + half) / cell)
				var iz := roundi((p.y + half) / cell)
				if ix >= 0 and ix < n and iz >= 0 and iz < n:
					seeds[iz * n + ix] = 1
		for tip: Array in [[0, mini(3, wall.size() - 1)], [wall.size() - 1, maxi(wall.size() - 4, 0)]]:
			var end := Vector2(float(wall[tip[0]][0]), float(wall[tip[0]][1]))
			var before := Vector2(float(wall[tip[1]][0]), float(wall[tip[1]][1]))
			var on := (end - before).normalized()
			for s in int(WALL_REACH / (cell * 0.5)):
				var p := end + on * (float(s) * cell * 0.5)
				var ix := roundi((p.x + half) / cell)
				var iz := roundi((p.y + half) / cell)
				if ix < 0 or ix >= n or iz < 0 or iz >= n:
					break
				line[iz * n + ix] = 1
	for k in n * n:  # ... and thick enough that a flood cannot slip through it cornerwise
		if seeds[k] == 1:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var ix := k % n + dx
					var iz := floori(float(k) / float(n)) + dz
					if ix >= 0 and ix < n and iz >= 0 and iz < n:
						line[iz * n + ix] = 1
	var d := _distance(seeds, 1)
	# HOME is the land reached from the spawn without crossing the border; AWAY is the land on its other side, well
	# past the line. Sea and islands are neither.
	var side := PackedByteArray()  # 1 = home land, 2 = the neighbours' land
	side.resize(n * n)
	_flood(side, line, [Vector2i(roundi((float(spawn[0]) + half) / cell), roundi((float(spawn[1]) + half) / cell))], 1)
	var far: Array[Vector2i] = []
	for k in n * n:
		if line[k] == 1 and seeds[k] == 0:
			continue
		if seeds[k] == 1:
			for step: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
				far.append(Vector2i(k % n, floori(float(k) / float(n))) + step)
	_flood(side, line, far, 2)
	away.resize(n * n)
	away.fill(0)
	for k in n * n:
		if side[k] == 2 and d[k] * cell > AWAY_PAST:
			away[k] = 1
	# each crossing cuts a pass through the wall: from the crossing to the nearest point of the wall and past it
	var cuts: Array = []
	for c: Dictionary in crossings:
		var from := Vector2(float(c["pos"][0]), float(c["pos"][1]))
		var best := from
		var best_d := INF
		for wall: Array in list:
			for p: Array in wall:
				var q := Vector2(float(p[0]), float(p[1]))
				if q.distance_to(from) < best_d:
					best_d = q.distance_to(from)
					best = q
		var out := (best - from).normalized() if best_d < INF and best_d > 0.1 else Vector2.ZERO
		cuts.append([from, best + out * 70.0])
	var crags := FastNoiseLite.new()  # the wall is broken high ground, not a bank: its height and width wander
	crags.seed = 77
	crags.fractal_octaves = 3
	crags.frequency = 1.0 / 260.0
	for j in n:
		for i in n:
			var k := j * n + i
			var m := d[k] * cell
			if m > WALL_HALF * 2.5 or macro[k] <= 0.0:
				continue
			var open := 1.0
			var here := Vector2(-half + i * cell, -half + j * cell)
			for cut: Array in cuts:
				var a: Vector2 = cut[0]
				var b: Vector2 = cut[1]
				var t := clampf((here - a).dot(b - a) / maxf((b - a).length_squared(), 0.01), 0.0, 1.0)
				open = minf(open, smoothstep(GAP * 0.5, GAP * 1.5, here.distance_to(a + (b - a) * t)))
			var vary := crags.get_noise_2d(here.x, here.y)
			var wide := WALL_HALF * (1.0 + 0.6 * vary)
			macro[k] += WALL_HEIGHT * clampf(1.05 + 0.6 * vary, WALL_LEAST, WALL_MOST) * exp(-pow(m / wide, 2.0)) * open


# Marks with `mark` every land cell reached from `from` by steps up, down, left and right that is not on the border
# `line` and not marked yet.
func _flood(side: PackedByteArray, line: PackedByteArray, from: Array, mark: int) -> void:
	var todo: Array[Vector2i] = []
	for start: Vector2i in from:
		todo.append(start)
	while not todo.is_empty():
		var at: Vector2i = todo.pop_back()
		if at.x < 0 or at.x >= n or at.y < 0 or at.y >= n:
			continue
		var k := at.y * n + at.x
		if side[k] != 0 or line[k] == 1 or macro[k] <= 0.0:
			continue
		side[k] = mark
		todo.append(at + Vector2i(1, 0))
		todo.append(at + Vector2i(-1, 0))
		todo.append(at + Vector2i(0, 1))
		todo.append(at + Vector2i(0, -1))


func _zones(list: Array) -> void:
	var total := PackedFloat32Array()
	total.resize(n * n)
	for zone: Dictionary in list:
		var look := String(zone["look"])
		var at := looks.find(look)
		var mask := _fill(zone["rings"])
		var w := PackedFloat32Array()
		w.resize(n * n)
		for k in n * n:
			w[k] = float(mask[k])
		w = _blur(_blur(w))
		if at < 0:
			looks.append(look)
			look_weight.append(w)
		else:
			var old: PackedFloat32Array = look_weight[at]
			for k in n * n:
				old[k] += w[k]
			look_weight[at] = old
	if looks.is_empty():
		return
	for w: PackedFloat32Array in look_weight:
		for k in n * n:
			total[k] += w[k]
	for i in looks.size():
		var w: PackedFloat32Array = look_weight[i]
		for k in n * n:
			w[k] = w[k] / total[k] if total[k] > 0.0001 else (1.0 if i == 0 else 0.0)
		look_weight[i] = w


# A box blur BLEND cells each way, across and then down.
func _blur(src: PackedFloat32Array) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(n * n)
	var out := PackedFloat32Array()
	out.resize(n * n)
	var span := float(BLEND * 2 + 1)
	for j in n:
		for i in n:
			var s := 0.0
			for q in range(i - BLEND, i + BLEND + 1):
				s += src[j * n + clampi(q, 0, n - 1)]
			tmp[j * n + i] = s / span
	for j in n:
		for i in n:
			var s := 0.0
			for q in range(j - BLEND, j + BLEND + 1):
				s += tmp[clampi(q, 0, n - 1) * n + i]
			out[j * n + i] = s / span
	return out


func _lakes(list: Array) -> void:
	lake_index.resize(n * n)
	lake_index.fill(-1)
	for entry: Dictionary in list:
		var ring: Array = entry["ring"]
		var mask := _fill([ring])
		var at := lakes.size()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p: Array in ring:
			lo = Vector2(minf(lo.x, float(p[0])), minf(lo.y, float(p[1])))
			hi = Vector2(maxf(hi.x, float(p[0])), maxf(hi.y, float(p[1])))
		var mid := (lo + hi) * 0.5
		var inside := _distance(mask, 0)
		var level := float(entry["level"])
		for k in n * n:
			if mask[k] == 1:
				lake_index[k] = at
				macro[k] = minf(macro[k], level - minf(0.3 + inside[k] * cell * 0.12, float(entry.get("depth", 4.0))))
		lakes.append({"id": String(entry["id"]), "level": level, "x": mid.x, "z": mid.y, "r": (hi - lo).length() * 0.5, "depth": float(entry.get("depth", 4.0)), "water": String(entry.get("water", "fresh"))})


# Rivers: each point's water level runs downhill from the source (never up), the bed below it.
func _rivers(list: Array) -> void:
	for entry: Dictionary in list:
		var pts := PackedVector2Array()
		var wid := PackedFloat32Array()
		var lev := PackedFloat32Array()
		var lowest := INF
		for i in (entry["points"] as Array).size():
			var p: Array = entry["points"][i]
			var v := Vector2(float(p[0]), float(p[1]))
			pts.append(v)
			wid.append(float(entry["width"][i]))
			lowest = minf(lowest, height(v.x, v.y) - 0.5)
			lev.append(maxf(lowest, 0.05))
		rivers.append({"points": pts, "width": wid, "level": lev})
		for i in pts.size() - 1:
			var s := _rv_a.size()
			_rv_a.append(pts[i])
			_rv_b.append(pts[i + 1])
			_rv_w.append(Vector2(wid[i], wid[i + 1]))
			_rv_l.append(Vector2(lev[i], lev[i + 1]))
			var reach := maxf(wid[i], wid[i + 1]) * 3.0 + 50.0  # the river's valley reaches this far (core/fantasy_terrain.gd)
			for cz in range(floori((minf(pts[i].y, pts[i + 1].y) - reach) / RIVER_CELL), floori((maxf(pts[i].y, pts[i + 1].y) + reach) / RIVER_CELL) + 1):
				for cx in range(floori((minf(pts[i].x, pts[i + 1].x) - reach) / RIVER_CELL), floori((maxf(pts[i].x, pts[i + 1].x) + reach) / RIVER_CELL) + 1):
					var key := Vector2i(cx, cz)
					var bucket: PackedInt32Array = _rv_cells.get(key, PackedInt32Array())
					bucket.append(s)
					_rv_cells[key] = bucket
