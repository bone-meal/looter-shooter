# Purpose: turns a Weathervane's rooster (node "Rooster" of its gimmick model) into the wind on every machine: the
# island weather's wind_yaw, wobbling more as the wind grows. Child of the gimmick (game/unique_attach.gd adds it for
# data "vane": true), so the gun in hand, another player's copy and the gun on the ground all turn alike.
# Dependencies: game/island_weather.gd (group "island_weather": wind, wind_yaw); a "Rooster" node above it.
extends Node3D

var _rooster: Node3D
var _weather: Node
var _yaw := 0.0


func _ready() -> void:
	_rooster = (get_parent() as Node3D).find_child("Rooster", true, false) as Node3D if get_parent() is Node3D else null


func _process(delta: float) -> void:
	if _rooster == null or not _rooster.is_visible_in_tree():
		return
	if _weather == null or not is_instance_valid(_weather):
		_weather = get_tree().get_first_node_in_group("island_weather")
	var wind := float(_weather.call("wind")) if _weather != null else 0.25
	var toward := float(_weather.call("wind_yaw")) if _weather != null else 0.0
	toward += sin(Time.get_ticks_msec() * 0.006) * 0.25 * wind  # it swings in the gusts
	_yaw = lerp_angle(_yaw, toward, minf(1.0, delta * (1.0 + wind * 3.0)))
	var parent_yaw := (_rooster.get_parent() as Node3D).global_transform.basis.get_euler().y if _rooster.get_parent() is Node3D else 0.0
	_rooster.rotation.y = _yaw - parent_yaw  # the arrow head (+f) points where the wind blows to
