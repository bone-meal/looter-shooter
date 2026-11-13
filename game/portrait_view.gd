# Purpose: a portrait of the character as he looks now (rigged body, or the code-built one when the packs are
# missing), standing in its idle pose under studio light in its own little world: the Combat Report's picture.
# Dependencies: game/rigged_body.gd, game/body_builder.gd.
extends SubViewportContainer

const RiggedBody = preload("res://game/rigged_body.gd")
const BodyBuilder = preload("res://game/body_builder.gd")

var _port := SubViewport.new()
var _model: Node3D


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(300, 420)
	_port.own_world_3d = true
	_port.size = Vector2i(300, 420)
	_port.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_port)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.11, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	var world := WorldEnvironment.new()
	world.environment = env
	_port.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, -35.0, 0.0)
	key.light_energy = 1.3
	_port.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.6, 0.75, 1.0)
	_port.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 1.25, 3.1)
	cam.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	_port.add_child(cam)


# The character with this look, turned a little toward the light.
func show_look(look: Dictionary) -> void:
	if _model != null:
		_model.queue_free()
	_model = RiggedBody.build(look)
	if _model == null:
		_model = BodyBuilder.build(look)
	_model.rotation.y = PI - deg_to_rad(18.0)  # facing the camera, turned a little toward the light
	_port.add_child(_model)


func _process(_delta: float) -> void:
	if _model != null and is_visible_in_tree() and _model.has_method("animate"):
		_model.call("animate", 0.0, false)  # the idle pose, breathing
