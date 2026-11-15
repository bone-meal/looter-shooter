# Purpose: rain at sea (sea step 4): the island weather's rain shader (one MultiMesh of drops that fall and wrap round
# the camera inside the shader, nothing moved from script), its drops slanted by the sea's wind and as many shown as
# the weather's rain asks for.
# Dependencies: game/island_weather.gd (RAIN_CODE), data/island_weather.json rain (box, streak, colour).
extends MultiMeshInstance3D

const IslandWeather = preload("res://game/island_weather.gd")

const MOST := 1800  # drops made; the graphics tier shows at most data/island_weather.json rain.drops x 1.5

var _material := ShaderMaterial.new()
var _tiers: Dictionary
var _most := 0


func setup() -> void:
	var rain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/island_weather.json"))["rain"]
	_tiers = rain["drops"]
	var shader := Shader.new()
	shader.code = IslandWeather.RAIN_CODE
	_material.shader = shader
	var box := Vector3(float(rain["box"][0]), float(rain["box"][1]), float(rain["box"][2]))
	_material.set_shader_parameter("box", box)
	_material.set_shader_parameter("streak", float(rain["streak"]))
	_material.set_shader_parameter("width", float(rain["width"]))
	_material.set_shader_parameter("near_cut", float(rain["near_cut"]))
	var color := Color.html(String(rain["color"]))
	color.a = float(rain["alpha"])
	_material.set_shader_parameter("tint", color)
	var drops := MultiMesh.new()
	drops.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.material = _material
	drops.mesh = quad
	drops.instance_count = MOST
	for i in MOST:
		drops.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(randf() * box.x, randf() * box.y, randf() * box.z)))
	drops.visible_instance_count = 0
	multimesh = drops
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1.0e6, -2000.0, -1.0e6), Vector3(2.0e6, 4000.0, 2.0e6))  # the drops are wherever the camera is


func set_tier(graphics: String) -> void:
	_most = mini(roundi(float(_tiers.get(graphics, 500)) * 1.5), MOST)


# rain 0..1 from the weather, wind 0..1 and the direction it blows to (radians).
func show_rain(rain: float, wind: float, wind_dir: float) -> void:
	multimesh.visible_instance_count = roundi(clampf(rain, 0.0, 1.0) * float(_most))
	visible = multimesh.visible_instance_count > 0
	var push := Vector2.from_angle(wind_dir) * wind * 9.0
	_material.set_shader_parameter("fall", Vector3(push.x, -24.0, push.y))
