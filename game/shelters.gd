# Purpose: the shelters on the islands as things in the world: each hut (driftwood walls with a doorway and three
# windows, a thatched roof; solid), the boards on its windows, and the spots enemies walk to. It tells the island's
# rounds where an enemy should go when its prey sits in a hut (`guide`) and shows what core/shelter_rules.gd says
# about the boards.
# Dependencies: core/shelter_rules.gd (`rules`: all decisions), game/surface_library.gd. game/game_session.gd creates
# it with the huts' places; game/island_rounds.gd calls `guide`.
extends Node3D

const ShelterRules = preload("res://core/shelter_rules.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")

signal tore(window: int)  # an enemy tore a board off (the machine that runs the rounds)

const ORIGIN := Vector3(500, 0, 0)  # game/island.gd CENTER: the rules count from here
const WALL := 0.2
const HIGH := 2.6  # wall height
const SILL := 1.05  # a window opens from here ...
const TOP := 2.0  # ... to here: wide enough to shoot through, too low to jump through
const SHOOTERS := 6.0  # an enemy that reaches farther than this shoots: it stays outside and aims at its prey

var rules: ShelterRules

var _spots := {}  # Vector2 (a rules spot) -> Node3D standing there, for enemies to walk to
var _planks: MultiMesh  # every board of every window: one draw call
var _plank_places: Array[Transform3D] = []
var _shown := PackedInt32Array()  # boards drawn per window
var _hops := 0  # enemies that have climbed in so far
var _inside := PackedInt32Array()  # enemies inside each hut at the last look ...
var _counting := PackedInt32Array()  # ... and the count of the look going on


# places = [{"at": Vector2, "yaw": float}] (core/archipelago.gd shelters), windows = data "windows".
func setup(places: Array, windows: Dictionary) -> void:
	rules = ShelterRules.new(windows, places)
	var wood := SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
	var thatch := SurfaceLibrary.material("fx_thatch", Color(0.72, 0.62, 0.36))
	for hut: Dictionary in rules.huts:
		_build_hut(hut, wood, thatch)
	for door: Dictionary in rules.doors:
		_spot(door["in"])
	var plank := BoxMesh.new()
	plank.size = Vector3(ShelterRules.WINDOW + 0.5, 0.15, 0.05)
	_planks = MultiMesh.new()
	_planks.transform_format = MultiMesh.TRANSFORM_3D
	_planks.mesh = plank
	_planks.instance_count = rules.windows.size() * rules.full()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for window: Dictionary in rules.windows:
		_spot(window["out"])
		_spot(window["in"])
		var mid: Vector2 = window["mid"]
		var facing := Basis(Vector3.UP, float(window["yaw"]))
		for n in rules.full():
			var height := SILL + (TOP - SILL) * (float(n) + 0.5) / float(rules.full())
			var skew := Basis(Vector3.BACK, rng.randf_range(-0.09, 0.09))  # nailed on by hand, none quite level
			_plank_places.append(Transform3D(facing * skew, ORIGIN + Vector3(mid.x, height, mid.y) + facing * Vector3(0, 0, WALL * 0.5 + 0.04)))
	var boards := MultiMeshInstance3D.new()
	boards.multimesh = _planks
	boards.material_override = wood
	add_child(boards)
	_shown.resize(rules.windows.size())
	_shown.fill(-1)
	_inside.resize(rules.huts.size())
	_counting.resize(rules.huts.size())
	refresh()


# The rounds are about to ask `guide` for every enemy once more: the count of who is inside starts again.
func look_begins() -> void:
	for hut in _inside.size():
		_inside[hut] = _counting[hut]
		_counting[hut] = 0


# Shows the boards the rules say each window has.
func refresh() -> void:
	for window in rules.windows.size():
		if _shown[window] == rules.boards[window]:
			continue
		_shown[window] = rules.boards[window]
		for n in rules.full():
			var index := window * rules.full() + n
			_planks.set_instance_transform(index, _plank_places[index] if n < rules.boards[window] else Transform3D(Basis.from_scale(Vector3.ZERO), _plank_places[index].origin))


# Where `enemy` should walk to get at `prey` (the prey itself, or a spot at a window or door). An enemy whose turn
# it is to climb through a broken window is put inside here; a board it tears off is announced by `tore`.
func guide(enemy: Node3D, prey: Node3D, now: float) -> Node3D:
	var reach: float = enemy.call("reach")
	if reach > SHOOTERS:
		return prey
	var from := enemy.global_position - ORIGIN
	var to := prey.global_position - ORIGIN
	var mine: int = rules.hut_of(from.x, from.z)
	if mine >= 0:
		_counting[mine] += 1
	var theirs: int = rules.hut_of(to.x, to.z)
	var room: bool = theirs < 0 or maxi(_inside[theirs], _counting[theirs]) < int(rules.cfg["max_inside"])
	var move: Dictionary = rules.guide(from.x, from.z, to.x, to.z, now, maxf(ShelterRules.AT_SPOT, reach + 0.6), room)
	if move.has("tore"):
		refresh()
		tore.emit(int(move["tore"]))
	if move.has("hop"):
		var landing: Vector2 = move["hop"]
		var into: int = rules.hut_of(landing.x, landing.y)  # -1 = it stepped out of a door
		_hops += 1
		var along := Vector2(landing.y - to.y, to.x - landing.x).normalized() * (0.7 if _hops % 2 == 0 else -0.7)  # not all onto the very same spot
		if rules.hut_of(landing.x + along.x, landing.y + along.y) == into:
			landing += along
		enemy.global_position = ORIGIN + Vector3(landing.x, 0.15, landing.y)
		if into >= 0:
			_counting[into] += 1
		return prey
	return _spots[move["goal"]] if move.has("goal") else prey


# World position of a window's middle (sounds, tools).
func window_spot(window: int) -> Vector3:
	var mid: Vector2 = rules.windows[window]["mid"]
	return ORIGIN + Vector3(mid.x, 1.5, mid.y)


func _spot(at: Vector2) -> void:
	var marker := Node3D.new()
	marker.position = ORIGIN + Vector3(at.x, 0.0, at.y)
	add_child(marker)
	_spots[at] = marker


# One hut: four walls of pieces around the doorway and the windows (each piece drawn and solid), and a roof.
func _build_hut(hut: Dictionary, wood: Material, thatch: Material) -> void:
	var half := ShelterRules.HALF
	var holder := StaticBody3D.new()
	holder.position = ORIGIN + Vector3((hut["at"] as Vector2).x, 0.0, (hut["at"] as Vector2).y)
	holder.rotation.y = float(hut["yaw"])
	add_child(holder)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var door := ShelterRules.DOOR * 0.5
	var gap := ShelterRules.WINDOW * 0.5
	# the door wall (+z): a piece each side of the doorway and a beam over it
	_piece(holder, walls, Vector3(half.x - door, HIGH, WALL), Vector3(-(half.x + door) * 0.5, HIGH * 0.5, half.y - WALL * 0.5))
	_piece(holder, walls, Vector3(half.x - door, HIGH, WALL), Vector3((half.x + door) * 0.5, HIGH * 0.5, half.y - WALL * 0.5))
	_piece(holder, walls, Vector3(door * 2.0, HIGH - 2.1, WALL), Vector3(0, (HIGH + 2.1) * 0.5, half.y - WALL * 0.5))
	# the sea wall (-z): a window in its middle
	_piece(holder, walls, Vector3(half.x - gap, HIGH, WALL), Vector3(-(half.x + gap) * 0.5, HIGH * 0.5, -half.y + WALL * 0.5))
	_piece(holder, walls, Vector3(half.x - gap, HIGH, WALL), Vector3((half.x + gap) * 0.5, HIGH * 0.5, -half.y + WALL * 0.5))
	_piece(holder, walls, Vector3(gap * 2.0, SILL, WALL), Vector3(0, SILL * 0.5, -half.y + WALL * 0.5))
	_piece(holder, walls, Vector3(gap * 2.0, HIGH - TOP, WALL), Vector3(0, (HIGH + TOP) * 0.5, -half.y + WALL * 0.5))
	# the two side walls (-x, +x): a window in the middle of each
	for side: float in [-1.0, 1.0]:
		var x := side * (half.x - WALL * 0.5)
		var run := half.y - WALL  # between the two long walls
		_piece(holder, walls, Vector3(WALL, HIGH, run - gap), Vector3(x, HIGH * 0.5, -(run + gap) * 0.5))
		_piece(holder, walls, Vector3(WALL, HIGH, run - gap), Vector3(x, HIGH * 0.5, (run + gap) * 0.5))
		_piece(holder, walls, Vector3(WALL, SILL, gap * 2.0), Vector3(x, SILL * 0.5, 0))
		_piece(holder, walls, Vector3(WALL, HIGH - TOP, gap * 2.0), Vector3(x, (HIGH + TOP) * 0.5, 0))
	var mesh := ArrayMesh.new()
	walls.commit(mesh)
	mesh.surface_set_material(0, wood)
	var shell := MeshInstance3D.new()
	shell.mesh = mesh
	holder.add_child(shell)
	var slab := BoxMesh.new()
	slab.size = Vector3(half.x * 2.0 + 0.9, 0.22, half.y * 2.0 + 0.9)
	var roof := MeshInstance3D.new()
	roof.mesh = slab
	roof.material_override = thatch
	roof.position = Vector3(0, HIGH + 0.2, 0)
	roof.rotation.x = 0.1  # it sheds the rain toward the door
	holder.add_child(roof)


# A wall piece: into the hut's one mesh, and solid.
func _piece(holder: StaticBody3D, walls: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	walls.append_from(box_mesh, 0, Transform3D(Basis(), at))
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = at
	holder.add_child(shape)
