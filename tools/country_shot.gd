# Purpose: developer-time check (polish1 F1a): builds every country's land (core/country_world.gd, core/fantasy_terrain.gd)
# and paints its map chart (game/chart_painter.gd) into tools/userdata/countries/<id>.png, with how long each took
# and what one height() costs. Run headless: godot --headless --path . --script res://tools/country_shot.gd [-- ids=a,b]
# Dependencies: core/fantasy_data.gd, core/fantasy_terrain.gd, game/chart_painter.gd, data/fantasy/countries/*.json.
extends SceneTree

const FantasyData = preload("res://core/fantasy_data.gd")
const FantasyTerrain = preload("res://core/fantasy_terrain.gd")
const ChartPainter = preload("res://game/chart_painter.gd")

func _init() -> void:
	var ids := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("ids="):
			ids = arg.substr(4).split(",")
	if ids.is_empty():
		for f in DirAccess.get_files_at("res://data/fantasy/countries"):
			if f.ends_with(".json"):
				ids.append(f.get_basename())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/userdata/countries"))
	for id in ids:
		var started := Time.get_ticks_msec()
		var d: Dictionary = FantasyData.load_all(id)
		var terrain: RefCounted = FantasyTerrain.new(d["world"])
		var took := Time.get_ticks_msec() - started
		started = Time.get_ticks_msec()
		var img: Image = ChartPainter.paint(terrain, 512)
		var painted := Time.get_ticks_msec() - started
		started = Time.get_ticks_usec()
		var _probe := 0.0
		for k in 20000:
			_probe += float(terrain.height(float(k % 400) * 9.0 - 1800.0, float(k / 400.0) * 70.0 - 1750.0))
		var micro := float(Time.get_ticks_usec() - started) / 20000.0
		img.save_png("res://tools/userdata/countries/%s.png" % id)
		var shape: RefCounted = terrain.country_shape
		var lo := INF
		var hi := -INF
		for v in shape.macro:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		print("%s: %d m, built in %d ms (shape + terrain), chart %d ms, height() %.1f us, big land %.1f .. %.1f m, looks %s, lakes %d, rivers %d, crossings %d" % [id, int(terrain.size), took, painted, micro, lo, hi, ",".join(shape.looks), shape.lakes.size(), shape.rivers.size(), shape.crossings.size()])
	quit()
