# Purpose: developer check + render of the Omaha map. Tests core/omaha_geo.gd, validates districts/enemies/drops data, builds the streamed world around the
#   spawn and Union Pacific area, spawns a few enemies, writes tools/omaha_check.log and shots tools/shots/omaha_a..c.png, then quits. Run scene tools/omaha_check.tscn.
# Dependencies: game/omaha_world.gd, game/omaha_spawner.gd (not needed), core/omaha_geo.gd, core/data_store.gd, game/wave_director.gd.
extends Node3D

const OmahaWorld = preload("res://game/omaha_world.gd")
const OmahaGeo = preload("res://core/omaha_geo.gd")
const DataStore = preload("res://core/data_store.gd")

var _world: OmahaWorld
var _cam := Camera3D.new()
var _t := 0.0
var _shot := 0
var _log: Array[String] = []
var _spots: Array[Vector3] = []


func _say(s: String) -> void:
	_log.append(s)
	print(s)


func _ready() -> void:
	get_window().size = Vector2i(1152, 648)
	_unit_tests()
	_data_checks()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.78, 0.62, 0.45)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.55, 0.48)
	env.environment.fog_enabled = true
	env.environment.fog_density = 0.0035
	env.environment.fog_light_color = Color(0.74, 0.60, 0.44)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	_world = OmahaWorld.new()
	add_child(_world)
	add_child(_cam)
	_cam.current = true
	_cam.far = 1500.0
	var t0 := Time.get_ticks_msec()
	_world.load_around(_world.spawn_world())
	_say("load_around spawn: %d chunks in %d ms" % [_world.chunk_count(), Time.get_ticks_msec() - t0])
	var s := _world.spawn_world()
	_spots = [s + Vector3(0, 2.0, 0), _world.to_world(Vector2(-60, 40)) + Vector3(0, 40, 0), _world.to_world(Vector2(250, -80)) + Vector3(0, 90, 0)]


func _unit_tests() -> void:
	var sq := [0, 0, 10, 0, 10, 10, 0, 10]
	_say("poly inside %s outside %s" % [OmahaGeo.point_in_poly(Vector2(5, 5), sq), OmahaGeo.point_in_poly(Vector2(15, 5), sq)])
	_say("rect rot ok %s" % [OmahaGeo.in_rect(Vector2(3, 0), 0, 0, 10, 2, 0.0) and not OmahaGeo.in_rect(Vector2(0, 3), 0, 0, 10, 2, 0.0) and OmahaGeo.in_rect(Vector2(0, 3), 0, 0, 10, 2, PI * 0.5)])
	var p := OmahaGeo.to_xz(41.2565, -95.9345, 41.2565, -95.9345, 5.0)
	_say("origin maps to %s" % p)
	_say("Henry Doorly Zoo desert dome maps to %s (expect about x=+1200/5.. south)" % OmahaGeo.to_xz(41.2246, -95.9290, 41.2565, -95.9345, 5.0))


func _data_checks() -> void:
	var ens: Dictionary = DataStore.load_json("res://data/omaha/enemies.json")["enemies"]
	var drops: Dictionary = DataStore.load_json("res://data/drops.json")["enemies"]
	var d := DataStore.load_json("res://data/omaha/districts.json")
	var bad := 0
	for id in ens:
		if not drops.has(id):
			_say("MISSING drop entry for %s" % id)
			bad += 1
		for k in ["model", "max_hp", "speed", "attack_type", "damage", "attack_range", "attack_interval", "size", "color"]:
			if not (ens[id] as Dictionary).has(k):
				_say("enemy %s lacks %s" % [id, k])
				bad += 1
		if ens[id]["attack_type"] == "ranged" and not (ens[id] as Dictionary).has("projectile_speed"):
			_say("ranged enemy %s lacks projectile_speed" % id)
			bad += 1
	for dist: Dictionary in d["districts"]:
		for id in dist["mix"]:
			if not ens.has(id):
				_say("district %s uses unknown enemy %s" % [dist["id"], id])
				bad += 1
		if dist.has("boss") and not ens.has(dist["boss"]["id"]):
			_say("district %s boss unknown" % dist["id"])
			bad += 1
	for id in d["default"]["mix"]:
		if not ens.has(id):
			bad += 1
	_say("data check problems: %d" % bad)


func _process(delta: float) -> void:
	_t += delta
	if _shot < _spots.size() and _t > 1.0 + 1.5 * float(_shot):
		_cam.position = _spots[_shot]
		_cam.rotation_degrees = Vector3(-5.0 if _shot == 0 else -28.0, 20.0 + 60.0 * float(_shot), 0.0)
		if _t > 1.5 + 1.5 * float(_shot):
			var img := get_viewport().get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path("res://tools/shots/omaha_%s.png" % char(97 + _shot)))
			_shot += 1
	elif _shot >= _spots.size() and _t > 8.0:
		var f := FileAccess.open(ProjectSettings.globalize_path("res://tools/omaha_check.log"), FileAccess.WRITE)
		f.store_string("\n".join(_log))
		f.close()
		get_tree().quit()
