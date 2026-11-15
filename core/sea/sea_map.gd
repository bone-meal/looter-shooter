# Purpose: pure rules for the sea world's map (sea step 4): the open grid of regions (data/sea/world.json grid), which
# region a sea position lies in, the sea's edges. Sea coordinates = metres from the sea's centre, x east, z south.
# Dependencies: none (data/sea/world.json passed in).
extends RefCounted

var cell := 2000.0
var grid: Array = []  # rows north to south of region ids
var regions: Dictionary = {}


func _init(world: Dictionary) -> void:
	cell = float(world["cell"])
	grid = world["grid"]
	regions = world["regions"]


func width() -> float:
	return cell * float((grid[0] as Array).size())


func height() -> float:
	return cell * float(grid.size())


# The region id at a sea position ("" outside the grid: open water at the world's edge).
func region_id_at(x: float, z: float) -> String:
	var col := floori((x + width() * 0.5) / cell)
	var row := floori((z + height() * 0.5) / cell)
	if row < 0 or row >= grid.size() or col < 0 or col >= (grid[row] as Array).size():
		return ""
	return String(grid[row][col])


func region_at(x: float, z: float) -> Dictionary:
	return regions.get(region_id_at(x, z), regions[String(grid[grid.size() - 1][(grid[0] as Array).size() >> 1])])


# The centre of a region's cell (sea coordinates); Vector2.INF when the id is not on the grid.
func centre_of(id: String) -> Vector2:
	for row in grid.size():
		for col in (grid[row] as Array).size():
			if String(grid[row][col]) == id:
				return Vector2((float(col) + 0.5) * cell - width() * 0.5, (float(row) + 0.5) * cell - height() * 0.5)
	return Vector2.INF


# How far a sea position is inside the map (negative = beyond its edge), for the edge of the world.
func inside_by(x: float, z: float) -> float:
	return minf(width() * 0.5 - absf(x), height() * 0.5 - absf(z))
