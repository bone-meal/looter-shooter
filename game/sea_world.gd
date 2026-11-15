# Purpose: the sea world (sea step 4): the open sea of seven regions on a grid (core/sea/sea_map.gd), its ocean, the
# islands streamed in by distance, the day, the weather and wind, and its own look. It lives in the same scene as the
# rest of the game with a FLOATING ORIGIN (director's choice): its root sits so that the player stays near `anchor`,
# and when the player has sailed `shift_every` metres the root and the player shift back together (signal
# origin_shifted). Everything saved or sent online uses SEA COORDINATES (local_of / world_of), never scene positions.
# The shared clock is this machine's for now (the host's comes with sea step 12).
# Dependencies: core/sea/*.gd, game/sea_ocean.gd, game/sea_islands.gd, game/sea_look.gd, data/sea/world.json,
# game/sea_rain.gd, data/sea/islands.json, game/render_style.gd (env, sun), the player (teleport, camera).
extends Node3D

const SeaMap = preload("res://core/sea/sea_map.gd")
const SeaWeather = preload("res://core/sea/sea_weather.gd")
const SeaOcean = preload("res://game/sea_ocean.gd")
const SeaIslands = preload("res://game/sea_islands.gd")
const SeaLook = preload("res://game/sea_look.gd")
const SeaRain = preload("res://game/sea_rain.gd")

signal origin_shifted(delta: Vector3)  # the scene moved by -delta under everything at sea (ships, enemies: move with it)
signal notice(text: String)

const WATER_FLOOR := -1.4  # until swimming arrives (sea step 5) the sea can be waded: a floor this far down

var world: Dictionary  # data/sea/world.json
var map: SeaMap
var weather_rules: SeaWeather
var look := SeaLook.new()
var ocean := SeaOcean.new()
var islands := SeaIslands.new()
var rain := SeaRain.new()
var inside := false
var weather := {}  # the weather where the player is (core/sea/sea_weather.gd at())
var region_id := ""

var _player: CharacterBody3D
var _root := Node3D.new()  # everything placed in sea coordinates hangs here (it carries the floating origin)
var _anchor := Vector3.ZERO
var _shift := Vector3.ZERO  # the sea position that sits at the anchor
var _floor := StaticBody3D.new()
var _clock_start := 0.0
var _slow := 0.0
var _island_cfg: Dictionary
var _clock_extra := 0.0  # dev / admin: seconds added to the shared clock (set_day_part)
var _forced := ""  # dev / admin: a weather kind held everywhere ("" = the sea's own)


func setup(player: CharacterBody3D, style: Node) -> void:
	_player = player
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/world.json"))
	_island_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/islands.json"))
	map = SeaMap.new(world)
	weather_rules = SeaWeather.new(world)
	_anchor = Vector3(float(world["anchor"][0]), float(world["anchor"][1]), float(world["anchor"][2]))
	look.setup(world, style.get("env"), style.get("sun"))
	add_child(_root)
	_root.position = _anchor
	ocean.setup(world["waves"])
	add_child(ocean)
	islands.setup(_island_cfg)
	_root.add_child(islands)
	rain.setup()
	add_child(rain)
	var shape := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	shape.shape = plane
	_floor.add_child(shape)
	add_child(_floor)
	_floor.position = Vector3(_anchor.x, WATER_FLOOR, _anchor.z)
	_clock_start = Time.get_ticks_msec() / 1000.0


# --- sea coordinates ---

func world_of(local: Vector3) -> Vector3:
	return _anchor + local - _shift


func local_of(at: Vector3) -> Vector3:
	return at - _anchor + _shift


# The shared clock in seconds (this machine's until sea step 12 sends the host's).
func seconds() -> float:
	return Time.get_ticks_msec() / 1000.0 - _clock_start + _clock_extra


# Dev / admin: jump the clock to a time of day (0 midnight .. 0.5 noon).
func set_day_part(part: float) -> void:
	_clock_extra += fposmod(part - look.clock.day_part(seconds()), 1.0) * look.clock.day_seconds
	_slow = 0.0


# Dev / admin: hold one weather kind ("" = back to the sea's own).
func force_weather(kind: String) -> void:
	_forced = kind if (world["weather"]["kinds"] as Dictionary).has(kind) else ""
	_slow = 0.0


# --- going in and out ---

# Where a new arrival stands (on the test island for now): a scene position.
func spawn_world() -> Vector3:
	var at: Array = _island_cfg["spawn"]
	return world_of(Vector3(float(at[0]), 30.0, float(at[1])))


func enter(graphics: String) -> void:
	inside = true
	visible = true
	ocean.set_detail(graphics, world["waves"])
	rain.set_tier(graphics)
	look.take_over()
	islands.follow(local_of(_player.global_position))
	_tick(0.0, true)


func leave() -> void:
	inside = false
	visible = false


# --- the floating origin ---

func _recentre() -> void:
	var here := local_of(_player.global_position)
	if Vector2(here.x - _shift.x, here.z - _shift.z).length() < float(world["shift_every"]):
		return
	var new_shift := Vector3(snappedf(here.x, 100.0), 0.0, snappedf(here.z, 100.0))
	var delta := new_shift - _shift
	_shift = new_shift
	_root.position = _anchor - _shift
	_player.global_position -= delta  # keeps its speed: sailing carries on through a shift
	origin_shifted.emit(delta)


# --- every frame ---

func _process(delta: float) -> void:
	if not inside:
		return
	_tick(delta, false)


func _tick(delta: float, now: bool) -> void:
	_recentre()
	var here := local_of(_player.global_position)
	var t := seconds()
	_slow -= delta
	if now or _slow <= 0.0:
		_slow = 0.5
		var id := map.region_id_at(here.x, here.z)
		if id != region_id and id != "" and region_id != "":
			notice.emit(String(map.regions[id]["name"]))
		region_id = id if id != "" else region_id
		weather = weather_rules.at(region_id, map.region_at(here.x, here.z), t)
		if _forced != "":
			var held: Dictionary = world["weather"]["kinds"][_forced]
			var reg: Dictionary = map.region_at(here.x, here.z)
			weather.merge({"kind": _forced, "fog": held["fog"], "rain": held["rain"], "light": held["light"], "swell": float(reg["swell"]) * float(held["swell"]),
				"wind": clampf(float(reg["wind"]) + float(held["wind"]), 0.05, 1.0)}, true)
		islands.follow(here)
		rain.show_rain(float(weather.get("rain", 0.0)), float(weather.get("wind", 0.0)), float(weather.get("wind_dir", 0.0)))
	var region: Dictionary = map.region_at(here.x, here.z)
	ocean.swell = lerpf(ocean.swell, float(weather.get("swell", 0.5)), 1.0 if now else 1.0 - exp(-0.5 * delta))
	var gloom := clampf((1.0 - float(weather.get("light", 1.0))) / 0.55, 0.0, 1.0)
	ocean.gloom = lerpf(ocean.gloom, gloom, 1.0 if now else 1.0 - exp(-0.5 * delta))
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera != null else _player.global_position
	var offset := Vector2(_shift.x - _anchor.x, _shift.z - _anchor.z)
	ocean.follow(eye, offset, t, region)
	look.apply(t, region, weather, 1.0 if now else delta)


# The water's height at a scene position now (ships and swimmers ride this; it is the drawn surface).
func water_height(at: Vector3) -> float:
	var sea := local_of(at)
	return ocean.waves.height_at(sea.x, sea.z, seconds(), ocean.swell)


# A line for the debug log: where in the sea, the day and the weather.
func status() -> String:
	var here := local_of(_player.global_position)
	var part := look.clock.day_part(seconds())
	return "sea %s at (%.0f, %.0f) day %.2f %s wind %.2f to %.0f deg swell %.1f m, islands %s, shift %s" % [region_id, here.x, here.z, part,
		String(weather.get("kind", "?")), float(weather.get("wind", 0.0)), fposmod(rad_to_deg(float(weather.get("wind_dir", 0.0))), 360.0), ocean.swell, str(islands.shown_count()), str(_shift)]
