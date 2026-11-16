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
const SeaShips = preload("res://game/sea_ships.gd")
const SeaSwim = preload("res://game/sea_swim.gd")
const SeaSalvage = preload("res://game/sea_salvage.gd")
const SeaShipyard = preload("res://game/sea_shipyard.gd")

signal origin_shifted(delta: Vector3)  # the scene moved by -delta under everything at sea (ships, enemies: move with it)
signal notice(text: String)


var world: Dictionary  # data/sea/world.json
var map: SeaMap
var weather_rules: SeaWeather
var look := SeaLook.new()
var ocean := SeaOcean.new()
var islands := SeaIslands.new()
var rain := SeaRain.new()
var ships := SeaShips.new()  # the world fleet (sea step 5a)
var swim := SeaSwim.new()  # swimming, stamina, ladders, the rope (sea step 5b)
var shipyard := SeaShipyard.new()  # the slipway on the test island (sea step 5c)
var salvage := SeaSalvage.new()  # diving finds and the logbook (sea step 5b)
var others := Callable()  # the session: other players' scene positions (the rope looks for swimmers)
var someone_else_here := false  # the host: another player is at sea, so the fleet runs here (set by the session)
var skills: Node = null  # the shared skills (game/fantasy_world.gd: Sailing level, perks, xp), set by the session
var inside := false
var weather := {}  # the weather where the player is (core/sea/sea_weather.gd at())
var region_id := ""

var _player: CharacterBody3D
var _root := Node3D.new()  # everything placed in sea coordinates hangs here (it carries the floating origin)
var _anchor := Vector3.ZERO
var _shift := Vector3.ZERO  # the sea position that sits at the anchor
var _clock_start := 0.0
var _slow := 0.0
var _island_cfg: Dictionary
var _clock_extra := 0.0  # dev / admin: seconds added to the shared clock (set_day_part)
var _forced := ""  # dev / admin: a weather kind held everywhere ("" = the sea's own)


func setup(player: CharacterBody3D, style: Node) -> void:
	_player = player
	add_to_group("sea_world")
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
	_root.add_child(ships)
	ships.setup(self, _player, RID())
	_root.add_child(shipyard)
	shipyard.setup(self, _player, ships.rules.cfg["shipyard"])
	ships.shipyard = shipyard
	_root.add_child(swim)
	swim.setup(self, _player, ships, JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/salvage.json"))["swim"])
	_root.add_child(salvage)
	salvage.setup(self, _player, swim)
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


# The weather over a sea position (core/sea/sea_weather.gd, or the kind a dev / admin holds everywhere).
func weather_at(here: Vector3) -> Dictionary:
	var id := map.region_id_at(here.x, here.z)
	var reg: Dictionary = map.region_at(here.x, here.z)
	var out: Dictionary = weather_rules.at(id if id != "" else region_id, reg, seconds())
	if _forced != "":
		var held: Dictionary = world["weather"]["kinds"][_forced]
		out.merge({"kind": _forced, "fog": held["fog"], "rain": held["rain"], "light": held["light"], "swell": float(reg["swell"]) * float(held["swell"]),
			"wind": clampf(float(reg["wind"]) + float(held["wind"]), 0.05, 1.0)}, true)
	return out


# Online: the host's sea clock (game/net_sea.gd) - this machine's clock follows it.
func sync_clock(host_seconds: float) -> void:
	var off := host_seconds - seconds()
	if absf(off) > 0.5:
		_clock_extra += off


# Does the sea run on this machine: the player is in it, or (the host) another player is.
func running() -> bool:
	return inside or someone_else_here


# --- going in and out ---

# Where a new arrival stands (the home-port town): a scene position. slot = the player's place in the party (0 = the
# centre), so players arriving together stand apart on a ring of "spawn_spread" metres instead of inside each other.
func spawn_world(slot: int = 0) -> Vector3:
	var at: Array = _island_cfg["spawn"]
	var spot := Vector3(float(at[0]), 30.0, float(at[1]))
	if slot > 0:
		var turn := TAU * float(slot - 1) / 6.0
		spot += Vector3(cos(turn), 0.0, sin(turn)) * float(_island_cfg.get("spawn_spread", 3.0))
	return world_of(spot)


func enter(graphics: String) -> void:
	inside = true
	_player.platform_floor_layers = 0  # decks carry the body themselves (game/sea_ships.gd): no engine platform push on top
	visible = true
	ocean.set_detail(graphics, world["waves"])
	rain.set_tier(graphics)
	islands.graphics = graphics
	look.take_over()
	islands.follow(local_of(_player.global_position))
	_tick(0.0, true)


func leave() -> void:
	inside = false
	ships.let_go()
	salvage.window.visible = false
	_player.set("swimming", false)
	look.under_water = false
	swim.call("_view_under", false)
	_player.platform_floor_layers = 0xFFFFFFFF
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
		weather = weather_at(here)
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
	return "sea %s at (%.0f, %.0f) day %.2f %s wind %.2f to %.0f deg swell %.1f m, islands %s props %d, shift %s, under water %s fog %.4f" % [region_id, here.x, here.z, part,
		String(weather.get("kind", "?")), float(weather.get("wind", 0.0)), fposmod(rad_to_deg(float(weather.get("wind_dir", 0.0))), 360.0), ocean.swell, str(islands.shown_count()), int(islands.props_shown()), str(_shift),
		str(look.under_water), float(look.call("fog_density"))]


# --- the interact key at sea (ships for now) ---

func prompt(key: String) -> String:
	if swim.climbing():
		return ""
	for part: Node in [swim, salvage, shipyard]:
		var said := String(part.call("prompt", key))
		if said != "":
			return said
	return ships.prompt(key)


func interact() -> bool:
	if swim.climbing():
		return true
	return swim.interact() or salvage.interact() or shipyard.interact() or ships.interact()


func toggle_logbook() -> void:
	salvage.toggle_window()


# The sea's root (things placed in sea coordinates hang here and shift with the floating origin).
func sea_root() -> Node3D:
	return _root


# For game/net_session.gd: where the sea's anchor lies along x, and how far the scene has shifted.
func anchor_x() -> float:
	return _anchor.x


func shift() -> Vector3:
	return _shift
