# Purpose: the debris that blocks a way between two islands until somebody pays to clear it: a pile of wreckage across
# the bridge plus an unseen wall wide enough that nobody jumps round it. Cleared = it sinks away and the wall is
# gone; closing puts it back (game over).
# Dependencies: game/surface_library.gd (wood). Built by game/island.gd, which turns it across its bridge; the session
# opens and closes it.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")

const WALL := Vector3(12.0, 7.0, 0.8)  # across the way (x), up, along the way
const SINK := 3.5  # metres it drops while it is being cleared
const SINK_TIME := 1.2

var width := 3.2  # of the way it lies across

var _pile := MeshInstance3D.new()  # all the wreckage as one mesh of two surfaces (wood, tarred wood)
var _wall := StaticBody3D.new()
var _shape := CollisionShape3D.new()
var _open := false
var _sinking := 0.0  # seconds left of the sinking


func _ready() -> void:
	var tools: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new()]
	for tool in tools:
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	# an upturned boat hull, crates and beams thrown across
	_piece(tools[1], Vector3(width + 1.4, 0.9, 1.5), Vector3(0, 0.55, 0), Vector3(0.0, 0.15, 0.12))
	_piece(tools[0], Vector3(width + 0.8, 0.5, 1.0), Vector3(0, 1.15, 0), Vector3(0.0, 0.15, 0.12))
	for n in 3:
		_piece(tools[0], Vector3(0.9, 0.9, 0.9), Vector3(-1.1 + 1.1 * float(n), 0.5 + 0.35 * float(n % 2), 1.0 - 0.3 * float(n)), Vector3(0.0, rng.randf_range(-0.6, 0.6), 0.0))
	for n in 5:
		_piece(tools[n % 2], Vector3(0.18, rng.randf_range(2.6, 4.2), 0.18), Vector3(rng.randf_range(-width * 0.5, width * 0.5), 1.3, rng.randf_range(-0.7, 0.7)),
			Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.0, TAU), rng.randf_range(-0.7, 0.7)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.16, 0.12)
	dark.roughness = 0.9
	var mesh := ArrayMesh.new()
	tools[0].commit(mesh)
	tools[1].commit(mesh)
	mesh.surface_set_material(0, SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15)))
	mesh.surface_set_material(1, dark)
	_pile.mesh = mesh
	add_child(_pile)
	var box := BoxShape3D.new()
	box.size = WALL
	_shape.shape = box
	_shape.position = Vector3(0, WALL.y * 0.5 - 1.0, 0)
	_wall.add_child(_shape)
	add_child(_wall)
	set_process(false)


func is_open() -> bool:
	return _open


# Cleared (open) or put back. `show_it` = let it sink away instead of just vanishing.
func set_open(open: bool, show_it: bool = false) -> void:
	_open = open
	_shape.set_deferred("disabled", open)
	if open and show_it and _pile.visible:
		_sinking = SINK_TIME
		set_process(true)
		return
	_sinking = 0.0
	set_process(false)
	_pile.position.y = 0.0
	_pile.visible = not open


func _process(delta: float) -> void:
	_sinking -= delta
	_pile.position.y = -SINK * (1.0 - maxf(_sinking, 0.0) / SINK_TIME)
	if _sinking <= 0.0:
		_pile.visible = false
		_pile.position.y = 0.0
		set_process(false)


func _piece(tool: SurfaceTool, size: Vector3, at: Vector3, turn: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	tool.append_from(mesh, 0, Transform3D(Basis.from_euler(turn), at))
