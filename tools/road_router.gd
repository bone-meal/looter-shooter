extends SceneTree
# Purpose: developer tool (polish1 F3). Suggests where each road of a country should BEND so that it runs round hills
# and lakes instead of through them: for every road of data/fantasy/places/<country>.json it tries bend points on a
# grid beside the straight line and scores each by the deepest cutting its graded bed would need, the water it would
# have to cross and its extra length. Prints one line per road; copy a suggested bend into the road in the places
# file as its third entry ([from, to, [x, z]]). Nothing is written.
# Run: godot --headless --path . --script res://tools/road_router.gd -- country=amberfield
# Dependencies: core/fantasy_data.gd, core/fantasy_terrain.gd (its land without road beds).
const FantasyData = preload("res://core/fantasy_data.gd")
const FantasyTerrain = preload("res://core/fantasy_terrain.gd")

const STEP := 6.0  # metres between the points a road is measured at
const MOST := 0.26  # the steepest a road climbs (core/fantasy_terrain.gd GRADE_MOST)
const BRIDGE := 32.0  # metres of water a bridge can carry it over


func _init() -> void:
	var country := "amberfield"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("country="):
			country = arg.trim_prefix("country=")
	var d: Dictionary = FantasyData.load_all(country)
	var t: FantasyTerrain = FantasyTerrain.new(d["world"])
	t.set("_graded", false)  # measure the land itself
	for r in t.roads.size():
		var road: PackedVector2Array = t.roads[r]
		var now := _score(t, road[0], road[1], road[2])
		var best := now
		var best_at := road[1]
		var line := road[2] - road[0]
		var side := line.orthogonal().normalized()
		for along: float in [0.3, 0.4, 0.5, 0.6, 0.7]:
			for off: float in [-0.5, -0.4, -0.3, -0.2, -0.1, 0.0, 0.1, 0.2, 0.3, 0.4, 0.5]:
				var mid := road[0] + line * along + side * off * line.length()
				var s := _score(t, road[0], mid, road[2])
				if s[0] < best[0]:
					best = s
					best_at = mid
		print("%s -> %s: now cut %.0f m, wet %.0f m, score %.0f | best bend [%d, %d]: cut %.0f m, wet %.0f m, bridges %d, length %.0f (straight %.0f), score %.0f%s" % [
			t.road_ends[r][0], t.road_ends[r][1], now[1], now[2], now[0], best_at.x, best_at.y, best[1], best[2], best[3], best[4], line.length(), best[0],
			"   <- USE" if best[0] < now[0] - 6.0 else ""])
	quit()


# [score (low is good), deepest cutting m, metres of water no bridge can cross, bridges, length]
func _score(t: FantasyTerrain, a: Vector2, mid: Vector2, b: Vector2) -> Array:
	var first := a.distance_to(mid)
	var length := first + mid.distance_to(b)
	var count := maxi(ceili(length / STEP) + 1, 2)
	var raw := PackedFloat32Array()
	var wet := PackedByteArray()
	for i in count:
		var along := float(i) * STEP
		var p := a.lerp(mid, along / maxf(first, 0.001)) if along <= first else mid.lerp(b, minf((along - first) / maxf(length - first, 0.001), 1.0))
		raw.append(t.call("_placed_height", p.x, p.y))
		wet.append(1 if t.water_at(p.x, p.y) != "" else 0)
	var bed := raw.duplicate()
	for i in range(1, count):
		bed[i] = minf(bed[i], bed[i - 1] + MOST * STEP)
	for i in range(count - 2, -1, -1):
		bed[i] = minf(bed[i], bed[i + 1] + MOST * STEP)
	var deepest := 0.0
	var total := 0.0
	for i in count:
		if wet[i] == 0:
			deepest = maxf(deepest, raw[i] - bed[i])
			total += raw[i] - bed[i]
	var drowned := 0.0
	var bridges := 0
	var run := 0
	for i in count:
		if wet[i] == 1:
			run += 1
		if (wet[i] == 0 or i == count - 1) and run > 0:
			if float(run + 1) * STEP > BRIDGE:
				drowned += float(run) * STEP
			else:
				bridges += 1
			run = 0
	return [deepest * 3.0 + total / float(count) * 4.0 + drowned * 2.0 + float(bridges) * 4.0 + (length - a.distance_to(b)) * 0.08, deepest, drowned, bridges, length]
