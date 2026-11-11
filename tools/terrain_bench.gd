# Purpose: developer-time check: how long the terrain rules take per point (run headless:
# godot --headless --path . --script res://tools/terrain_bench.gd).
# Dependencies: core/fantasy_terrain.gd, data/fantasy/world.json.
extends SceneTree

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")


func _init() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/fantasy/world.json"))
	var terrain := FantasyTerrain.new(world)
	var n := 40000
	for what: String in ["weights", "wildness", "_raw_height(0)", "_raw_height(1)", "height", "trodden", "color"]:
		var started := Time.get_ticks_usec()
		var sum := 0.0
		for i in n:
			var x := -900.0 + 1800.0 * FantasyTerrain.hash01(i, 3, 1)
			var z := -900.0 + 1800.0 * FantasyTerrain.hash01(i, 5, 2)
			match what:
				"weights":
					sum += terrain.weights(x, z)[0]
				"wildness":
					sum += terrain.wildness(x, z)
				"_raw_height(0)":
					sum += terrain.call("_raw_height", x, z, 0.0)
				"_raw_height(1)":
					sum += terrain.call("_raw_height", x, z, 1.0)
				"height":
					sum += terrain.height(x, z)
				"trodden":
					sum += terrain.trodden(x, z)
				"color":
					sum += terrain.color(x, z, 5.0, 0.1).r
		print("%-16s %.1f microseconds a point" % [what, float(Time.get_ticks_usec() - started) / float(n)])
	quit()
