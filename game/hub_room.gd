# Purpose: builds the safe hub at game start (locked: diary/DECISIONS_HUB.md) at data/hub.json "center": the
# library hall, the checkerboard stage with its pillars, the sandstone pedestal and its big red button (pushed in once
# for good), candle chandeliers, the cold moon window, the endless spiral stair turning slowly behind the arch, the
# Aurelind painting's place, and solid floor and walls to walk in. Its own light only: warm candles and one cold moon
# beam, no shadows (the session darkens the sky light while the player stands inside: game/game_session.gd hub_dark).
# Dependencies: game/fantasy_models.gd (models made by tools/blender/hub_room.py), data/hub.json (set `cfg` before
# add_child).
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")

const CANDLE := Color(1.0, 0.7, 0.4)
const MOON := Color(0.55, 0.68, 1.0)
const CHANDELIERS := [Vector3(-12.0, 10.6, -5.0), Vector3(12.0, 10.6, -5.0), Vector3(-12.0, 10.6, 7.0), Vector3(12.0, 10.6, 7.0)]
const STAIR_AT := Vector3(0.0, 0.0, -21.0)  # the spiral's middle, behind the arch in the back wall
const STAIR_RISE := 4.2  # one turn of tools/blender/hub_room.py stair
const STAIR_TURNS := 22
const STAIR_SPIN := 0.06  # radians a second
const BUTTON_TOP := 1.45  # the pedestal's gold top
const BUTTON_DOWN := 0.15

var cfg: Dictionary
var _button: Node3D
var _spiral: Node3D
var _pressed := false
var _push := 0.0


func _ready() -> void:
	var c: Array = cfg["center"]
	position = Vector3(float(c[0]), float(c[1]), float(c[2]))
	for id: String in ["hub_hall", "hub_stage"]:
		_model(id, Vector3.ZERO)
	var p: Array = cfg["pedestal"]
	var at := Vector3(float(p[0]), 0.0, float(p[1]))
	_model("hub_pedestal", at)
	_button = _model("hub_button", at + Vector3(0.0, BUTTON_TOP, 0.0))
	for spot: Vector3 in CHANDELIERS:
		_model("hub_chandelier", spot)
		_light(spot + Vector3(0.0, 0.2, 0.0), CANDLE, 2.2, 20.0)
	_light(Vector3(0.0, 4.0, -11.0), CANDLE, 0.8, 10.0)  # over the stage
	_light(Vector3(0.0, 5.5, 1.5), CANDLE, 0.7, 9.0)  # over the pedestal
	_moon()
	_stair()
	_solids()


func _model(id: String, at: Vector3) -> Node3D:
	var made := FantasyModels.scene(id)
	if made == null:
		push_warning("hub model missing: " + id)
		made = Node3D.new()
	made.position = at
	add_child(made)
	return made


func _light(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	add_child(lamp)


# The high round window in the right wall: cold glass and one beam of moonlight across the hall.
func _moon() -> void:
	var hw := float(cfg["size"][0]) * 0.5
	var glass := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.5
	disc.bottom_radius = 1.5
	disc.height = 0.05
	disc.radial_segments = 20
	var cold := StandardMaterial3D.new()
	cold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cold.albedo_color = MOON
	disc.material = cold
	glass.mesh = disc
	glass.position = Vector3(hw - 0.08, 9.5, -8.0)
	glass.rotation.z = PI * 0.5
	add_child(glass)
	var beam := SpotLight3D.new()
	beam.position = Vector3(hw - 0.6, 9.5, -8.0)
	beam.light_color = MOON
	beam.light_energy = 2.2
	beam.spot_range = 40.0
	beam.spot_angle = 22.0
	beam.shadow_enabled = false
	add_child(beam)
	beam.look_at(global_position + Vector3(4.0, 0.0, -3.0), Vector3.UP)


# One turn of the stair, many times over, up and down into the dark; the whole column turns slowly. One draw for all
# turns of each material (a MultiMesh).
func _stair() -> void:
	var turn := FantasyModels.mesh("hub_stair")
	if turn == null:
		return
	_spiral = Node3D.new()
	_spiral.position = STAIR_AT
	add_child(_spiral)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = turn
	many.instance_count = STAIR_TURNS
	for i in STAIR_TURNS:
		many.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, (float(i) - STAIR_TURNS * 0.5) * STAIR_RISE, 0.0)))
	var shown := MultiMeshInstance3D.new()
	shown.multimesh = many
	shown.custom_aabb = AABB(Vector3(-3.0, -STAIR_TURNS * STAIR_RISE * 0.5, -3.0), Vector3(6.0, STAIR_TURNS * STAIR_RISE, 6.0))
	_spiral.add_child(shown)
	var lamp := OmniLight3D.new()  # a faint glow down the shaft so the turning stair reads through the arch
	lamp.light_color = MOON
	lamp.light_energy = 0.6
	lamp.omni_range = 14.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(0.0, 4.0, 0.0)
	_spiral.add_child(lamp)


# What stops a player: the floor, the walls (the bookcases' fronts), the arch closed (the stair is only seen), the
# stage, the pedestal, the pillars, the reading tables and globes.
func _solids() -> void:
	var hw := float(cfg["size"][0]) * 0.5
	var hd := float(cfg["size"][1]) * 0.5
	var h := float(cfg["height"])
	var shelf := 0.45
	var door: Array = cfg["door"]
	var dz0 := float(door[1]) - 1.5
	var dz1 := float(door[1]) + 1.5
	_solid(Vector3(hw * 2.0 + 2.0, 1.0, hd * 2.0 + 2.0), Vector3(0.0, -0.5, 0.0))
	_solid(Vector3(1.0, h, hd * 2.0), Vector3(hw - shelf + 0.5, h * 0.5, 0.0))
	_solid(Vector3(hw * 2.0, h, 1.0), Vector3(0.0, h * 0.5, hd - shelf + 0.5))
	_solid(Vector3(hw * 2.0, h, 1.0), Vector3(0.0, h * 0.5, -hd + shelf - 0.5))
	_solid(Vector3(1.0, h, dz0 + hd), Vector3(-hw + shelf - 0.5, h * 0.5, (dz0 - hd) * 0.5))  # left wall, both sides of the doorway
	_solid(Vector3(1.0, h, hd - dz1), Vector3(-hw + shelf - 0.5, h * 0.5, (dz1 + hd) * 0.5))
	_solid(Vector3(1.0, h - 4.0, 3.0), Vector3(-hw + shelf - 0.5, 4.0 + (h - 4.0) * 0.5, float(door[1])))
	var s: Array = cfg["stage"]
	var top := float(cfg["stage_height"])
	_solid(Vector3(float(s[2]) - float(s[0]), top, float(s[3]) - float(s[1])), Vector3((float(s[0]) + float(s[2])) * 0.5, top * 0.5, (float(s[1]) + float(s[3])) * 0.5))
	_solid(Vector3(10.0, 0.3, 0.35), Vector3(0.0, 0.15, float(s[3]) + 0.17))
	_solid(Vector3(10.0, 0.15, 0.35), Vector3(0.0, 0.075, float(s[3]) + 0.52))
	var p: Array = cfg["pedestal"]
	_solid(Vector3(1.9, BUTTON_TOP, 1.9), Vector3(float(p[0]), BUTTON_TOP * 0.5, float(p[1])))
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(1.6, 11.0, 1.6), Vector3(side * 8.9, 5.5, -11.5))
	for t: Vector2 in [Vector2(-8.0, 6.0), Vector2(8.0, 6.0), Vector2(10.0, -2.0)]:  # reading tables (tools/blender/hub_room.py)
		_solid(Vector3(3.2, 0.86, 1.2), Vector3(t.x, 0.43, t.y))
	for g: Vector2 in [Vector2(-6.0, 9.0), Vector2(14.0, -6.0)]:
		_solid(Vector3(0.8, 1.9, 0.8), Vector3(g.x, 0.95, g.y))


func _solid(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


# The big red button goes down with a clunk and stays down (the session plays the sound).
func press() -> void:
	_pressed = true


func is_pressed() -> bool:
	return _pressed


# The Aurelind painting on the right wall, facing into the hall (world position and turn, for Island.build_painting).
func painting_spot() -> Array:
	var at: Array = cfg["painting"]
	return [position + Vector3(float(at[0]), 0.0, float(at[1])), -PI * 0.5]


func spawn(index: int) -> Vector3:
	var list: Array = cfg["spawns"]
	var at: Array = list[index % list.size()]
	return position + Vector3(float(at[0]), 0.1, float(at[1]))


func _process(delta: float) -> void:
	if _spiral != null:
		_spiral.rotation.y = wrapf(_spiral.rotation.y + STAIR_SPIN * delta, 0.0, TAU)
	if _pressed and _push < 1.0 and _button != null:
		_push = minf(_push + delta * 8.0, 1.0)
		_button.position.y = BUTTON_TOP - BUTTON_DOWN * _push
