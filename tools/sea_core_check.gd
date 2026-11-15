# Purpose: developer check of sea step 4's pure rules: the region grid (core/sea/sea_map.gd), the waves
# (core/sea/sea_waves.gd: height, slope against a finite difference, swell scaling), the day (core/sea/sea_clock.gd:
# noon high, midnight below the horizon, daylight 0..1), the weather (core/sea/sea_weather.gd: the same answer twice,
# every kind turns up, storms swell more than calm). Writes tools/sea_core_check.log ("SEA_CORE problems=n").
# Dependencies: core/sea/*.gd, data/sea/world.json.
extends Node

const SeaMap = preload("res://core/sea/sea_map.gd")
const SeaWaves = preload("res://core/sea/sea_waves.gd")
const SeaClock = preload("res://core/sea/sea_clock.gd")
const SeaWeather = preload("res://core/sea/sea_weather.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/world.json"))
	var map := SeaMap.new(world)
	_check(map.width() == 6000.0 and map.height() == 6000.0, "6 x 6 km grid")
	_check(map.region_id_at(0.0, 0.0) == "region_7", "the Maelstrom in the centre")
	_check(map.region_id_at(0.0, 2500.0) == "region_1", "region 1 bottom middle")
	_check(map.region_id_at(9000.0, 0.0) == "", "beyond the edge: no region")
	_check(map.centre_of("region_1") == Vector2(0.0, 2000.0), "centre of region 1")
	for row: Array in world["grid"]:
		for id: String in row:
			_check((world["regions"] as Dictionary).has(id), "region %s has data" % id)
	var waves := SeaWaves.new(world["waves"])
	var h := waves.height_at(12.0, -40.0, 3.0, 1.0)
	_check(absf(h) <= 1.0001, "a 1 m swell stays within 1 m (%.3f)" % h)
	_check(is_equal_approx(waves.height_at(12.0, -40.0, 3.0, 2.5), h * 2.5), "height scales with the swell")
	var e := 0.01
	var dx := (waves.height_at(12.0 + e, -40.0, 3.0, 1.0) - waves.height_at(12.0 - e, -40.0, 3.0, 1.0)) / (2.0 * e)
	var n := waves.normal_at(12.0, -40.0, 3.0, 1.0)
	_check(absf(-n.x / n.y - dx) < 0.01, "normal matches the slope (%.4f vs %.4f)" % [-n.x / n.y, dx])
	var clock := SeaClock.new(world["clock"])
	_check(clock.sun(0.5).x > 50.0, "noon sun high (%.0f)" % clock.sun(0.5).x)
	_check(clock.sun(0.0).x < 0.0, "midnight sun below the horizon (%.0f)" % clock.sun(0.0).x)
	_check(clock.daylight(0.5) == 1.0 and clock.daylight(0.0) == 0.0, "daylight 1 at noon, 0 at midnight")
	_check(is_equal_approx(clock.day_part(clock.day_seconds), clock.day_part(0.0)), "a full day comes round")
	var rules := SeaWeather.new(world)
	var seen := {}
	var calm_swell := 0.0
	var storm_swell := 0.0
	for slot in 400:
		var t := float(slot) * 360.0 + 200.0
		var w := rules.at("region_5", world["regions"]["region_5"], t)
		seen[w["kind"]] = true
		if String(w["kind"]) == "calm":
			calm_swell = float(w["swell"])
		if String(w["kind"]) == "storm":
			storm_swell = float(w["swell"])
	_check(seen.size() == 4, "all four weathers turn up in region 5 (%s)" % str(seen.keys()))
	_check(storm_swell > calm_swell * 2.0, "storms swell more than calm (%.1f vs %.1f)" % [storm_swell, calm_swell])
	_check(str(rules.at("region_1", world["regions"]["region_1"], 1234.0)) == str(rules.at("region_1", world["regions"]["region_1"], 1234.0)), "the same clock gives the same weather")
	_lines.append("SEA_CORE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/sea_core_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_problems += 1
