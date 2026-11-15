# Purpose: the sea world's sky and light (sea step 4): its own painted sky (a gradient sky whose colours follow the
# region, the time of day and the weather), the sun moving across the day (dark blue nights with a faint moonlight),
# golden dawns and dusks, and horizon fog that thickens with fog banks and storms. It writes onto the environment
# and sun game/render_style.gd made; leaving the sea re-applies the settings, which gives the look back.
# Dependencies: core/sea/sea_clock.gd, data/sea/world.json (regions, fog), game/render_style.gd (env, sun).
extends RefCounted

const SeaClock = preload("res://core/sea/sea_clock.gd")

const NIGHT_SKY := Color(0.03, 0.05, 0.12)
const NIGHT_HORIZON := Color(0.08, 0.11, 0.2)
const GOLD := Color(1.0, 0.62, 0.32)

var clock: SeaClock

var _env: Environment
var _sun: DirectionalLight3D
var _sky := Sky.new()
var _colors := ProceduralSkyMaterial.new()
var _fog_cfg: Dictionary
var _sky_c := Color.SKY_BLUE  # eased towards what the moment asks for
var _fog_c := Color.WHITE
var _fog_far := 2600.0
var _first := true


func setup(world: Dictionary, env: Environment, sun: DirectionalLight3D) -> void:
	clock = SeaClock.new(world["clock"])
	_fog_cfg = world["fog"]
	_env = env
	_sun = sun
	_colors.sun_angle_max = 8.0
	_colors.sun_curve = 0.08
	_sky.sky_material = _colors


# Takes the environment over for the sea (call on entering, and after the settings re-applied the look).
func take_over() -> void:
	_env.background_mode = Environment.BG_SKY
	_env.sky = _sky
	_env.sky_rotation = Vector3.ZERO
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.fog_enabled = true
	_env.fog_sky_affect = 0.35
	_first = true


# Every frame or so: the sky, sun, ambient light and fog for this moment. `weather` from core/sea/sea_weather.gd.
func apply(seconds: float, region: Dictionary, weather: Dictionary, delta: float) -> void:
	var part := clock.day_part(seconds)
	var day := clock.daylight(part)
	var gold := clock.golden(part)
	var light := float(weather.get("light", 1.0))
	var sky := Color(region["sky"][0], region["sky"][1], region["sky"][2])
	var grey := Color(0.5, 0.53, 0.58)
	sky = sky.lerp(grey, 1.0 - light)  # rain and storms grey the sky
	var top := NIGHT_SKY.lerp(sky.darkened(0.15), day)
	var horizon := NIGHT_HORIZON.lerp(sky.lightened(0.35), day).lerp(GOLD, gold * 0.6 * light)
	var fog := Color(region["fog"][0], region["fog"][1], region["fog"][2]).lerp(grey, (1.0 - light) * 0.7)
	fog = NIGHT_HORIZON.lerp(fog, maxf(day, 0.08)).lerp(GOLD.darkened(0.2), gold * 0.35 * light)
	var far := lerpf(float(_fog_cfg["far"]), float(_fog_cfg["heavy_far"]), clampf(float(weather.get("fog", 0.0)), 0.0, 1.0))
	var k := 1.0 if _first else 1.0 - exp(-1.5 * delta)
	_first = false
	_sky_c = _sky_c.lerp(top, k)
	_fog_c = _fog_c.lerp(fog, k)
	_fog_far = lerpf(_fog_far, far, k)
	_colors.sky_top_color = _sky_c
	_colors.sky_horizon_color = _sky_c.lerp(horizon, 0.8)
	_colors.ground_horizon_color = _colors.sky_horizon_color
	_colors.ground_bottom_color = _colors.sky_horizon_color.darkened(0.4)
	_env.fog_light_color = _fog_c
	_env.fog_density = 1.6 / maxf(_fog_far, 50.0)  # exponential fog: about four fifths of the view gone at `far` metres
	_env.ambient_light_color = _sky_c.lerp(Color.WHITE, 0.35) * lerpf(0.18, 0.62, day) * lerpf(0.75, 1.0, light)
	var sun := clock.sun(part)
	var height := maxf(sun.x, 6.0) if day > 0.0 else 35.0  # at night the light is the moon's, high and pale
	_sun.rotation_degrees = Vector3(-height, sun.y, 0.0)
	_sun.light_color = Color(0.55, 0.62, 0.85).lerp(Color.WHITE.lerp(GOLD, gold), day)
	_sun.light_energy = lerpf(0.12, 1.15, day) * lerpf(0.45, 1.0, light)
