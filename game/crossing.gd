# Purpose: THE CROSSING on the islands (sea step 11, LOCKED: fog-bank handoff, every winning run). When the island
# quest is done (the Warden beaten, the boat built) the G U-boat surfaces beyond Gull Rock and sails slowly into a fog
# bank, where it dives. The fog thickens round the bank as the camera comes near (game/island_weather.gd set_bank).
# The boat's middle in the bank long enough = the crossing: the host (or a lone player) emits `cross` and the session
# ends the run as won for everyone and takes whoever is aboard out into the sea world.
# Dependencies: data/crossing.json, game/fog_bank.gd, game/sea_uboat.gd (model_with_flag), the island weather (set_bank).
# Positions in data are metres from the archipelago's middle; `center` = that middle in the world (Island.CENTER).
extends Node3D

const FogBank = preload("res://game/fog_bank.gd")
const SeaUboat = preload("res://game/sea_uboat.gd")

signal cross  # the boat stayed in the bank: cross now (decided where the boat is sailed: host or alone)

var cfg: Dictionary
var active := false
var in_bank := 0.0  # seconds the boat's middle has been in the bank
var bank_amount := 0.0  # how deep in the fog the camera is (0..1), for checks
var _center := Vector3.ZERO
var _sea_level := 0.0
var _bank: Node3D
var _sub: Node3D
var _sub_at := Vector2.ZERO
var _sub_lift := 0.4
var _said := false


func setup(center: Vector3, sea_level: float) -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/crossing.json"))
	_center = center
	_sea_level = sea_level
	_bank = FogBank.new()
	add_child(_bank)
	_bank.call("build", float(cfg["fog_radius"]) * 2.2, 9, 22.0, Color(0.86, 0.9, 0.93, 1.0))
	_bank.position = _world(_v2(cfg["fog_at"]))
	_bank.visible = false


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _world(at: Vector2) -> Vector3:
	return _center + Vector3(at.x, _sea_level, at.y)


# The quest is done: the U-boat comes up and the bank stands (every machine shows it).
func start() -> void:
	if active:
		return
	active = true
	in_bank = 0.0
	_sub_at = _v2(cfg["uboat_from"])
	_sub_lift = -6.0
	if _sub == null:
		_sub = SeaUboat.model_with_flag()
		add_child(_sub)
	_sub.visible = true
	_bank.visible = true
	_said = false


func stop() -> void:
	active = false
	in_bank = 0.0
	if _sub != null:
		_sub.visible = false
	_bank.visible = false


# Every frame from the session: the boat's middle (archipelago metres), whether this machine decides (host / alone),
# the camera (world) and the island weather (fog).
func step(delta: float, boat: Vector2, deciding: bool, camera: Vector3, weather: Node) -> void:
	if not active:
		if weather != null and bank_amount > 0.0:
			bank_amount = 0.0
			weather.call("set_bank", 0.0)
		return
	var fog := _v2(cfg["fog_at"])
	var to := fog - _sub_at
	if to.length() > 6.0:  # it sails slowly to the bank, surfaced, then dives inside it
		_sub_at += to.normalized() * float(cfg["uboat_speed"]) * delta
		_sub_lift = move_toward(_sub_lift, 0.4, delta * 1.5)
	else:
		_sub_lift = move_toward(_sub_lift, -12.0, delta * 1.2)
	_sub.position = _world(_sub_at) + Vector3(0.0, _sub_lift, 0.0)
	_sub.rotation.y = atan2(-to.x, -to.y)  # (its bow is -z)
	_sub.visible = _sub_lift > -11.0
	var cam := Vector2(camera.x - _center.x, camera.z - _center.z)
	bank_amount = clampf(1.0 - (cam.distance_to(fog) - float(cfg["fog_radius"])) / float(cfg["fog_reach"]), 0.0, 1.0)
	if weather != null:
		weather.call("set_bank", bank_amount)
	if deciding:
		if boat.distance_to(fog) <= float(cfg["fog_radius"]):
			in_bank += delta
			if in_bank >= float(cfg["cross_after_s"]):
				in_bank = 0.0
				active = false
				cross.emit()
		else:
			in_bank = 0.0


func status() -> String:
	return "crossing active %s, uboat at %s lift %.1f, bank %.2f, boat in bank %.1f s" % [str(active), str(_sub_at.snapped(Vector2(0.1, 0.1))), _sub_lift, bank_amount, in_bank]
