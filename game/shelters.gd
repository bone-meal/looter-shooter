# Purpose: the shelters on the islands as things in the world: each hut (driftwood walls with a doorway and four
# windows, a thatched pitched roof; solid), the boards on its windows, its DOOR (polish1 D4b: a plank door on a hinge
# that swings open / shut, loses a plank per blow and hangs broken when none are left; its collider is out of the
# islands' navigation mesh, group "nav_skip"), a table and lantern inside, and the spots enemies walk to. It tells the island's
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
const HIGH := 3.0  # wall height
const SILL := 1.05  # a window opens from here ...
const TOP := 2.0  # ... to here: wide enough to shoot through, too low to jump through
const SHOOTERS := 6.0  # an enemy that reaches farther than this shoots: it stays outside and aims at its prey

var rules: ShelterRules

var _spots := {}  # Vector2 (a rules spot) -> Node3D standing there, for enemies to walk to
var _planks: MultiMesh  # every board of every window: one draw call
var _plank_places: Array[Transform3D] = []
var _plank_start := PackedInt32Array()  # per entrance: its first plank in the MultiMesh (-1 = a door: its own planks)
var _door_leaves := {}  # entrance -> [hinge Node3D, MultiMesh of its planks, CollisionShape3D]
var _door_angle := {}  # entrance -> shown opening (radians)
var _shown := PackedInt32Array()  # boards drawn per window
var _hops := 0  # enemies that have climbed in so far
var _inside := PackedInt32Array()  # enemies inside each hut at the last look ...
var _counting := PackedInt32Array()  # ... and the count of the look going on


# places = [{"at": Vector2, "yaw": float}] (core/archipelago.gd shelters), windows = data "windows".
func setup(places: Array, windows: Dictionary) -> void:
	rules = ShelterRules.new(windows, places)
	var wood := SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
	var thatch := SurfaceLibrary.material("fx_thatch", Color(0.72, 0.62, 0.36))
	var door_wood := SurfaceLibrary.material("hut_door", Color(0.3, 0.2, 0.14))  # darker than the walls: the door reads from afar
	for hut: Dictionary in rules.huts:
		_build_hut(hut, wood, thatch)
	for door: Dictionary in rules.doors:
		_spot(door["in"])
	var plank := BoxMesh.new()
	plank.size = Vector3(ShelterRules.WINDOW + 0.5, 0.15, 0.05)
	_planks = MultiMesh.new()
	_planks.transform_format = MultiMesh.TRANSFORM_3D
	_planks.mesh = plank
	var window_count := 0
	for window: Dictionary in rules.windows:
		if String(window["kind"]) == "window":
			window_count += 1
	_planks.instance_count = window_count * rules.full()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for e in rules.windows.size():
		var window: Dictionary = rules.windows[e]
		_spot(window["out"])
		_spot(window["in"])
		if String(window["kind"]) == "door":
			_plank_start.append(-1)
			_build_door(e, door_wood)
			continue
		_plank_start.append(_plank_places.size())
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
	_shown.fill(-1000)
	_inside.resize(rules.huts.size())
	_counting.resize(rules.huts.size())
	refresh()


# The rounds are about to ask `guide` for every enemy once more: the count of who is inside starts again.
func look_begins() -> void:
	for hut in _inside.size():
		_inside[hut] = _counting[hut]
		_counting[hut] = 0


# Shows the boards the rules say each window has, and each door's planks and whether it stands open.
func refresh() -> void:
	for window in rules.windows.size():
		var state: int = rules.encoded(window)
		if _shown[window] == state:
			continue
		_shown[window] = state
		if _plank_start[window] < 0:
			_show_door(window)
			continue
		for n in rules.full():
			var index := _plank_start[window] + n
			_planks.set_instance_transform(index, _plank_places[index] if n < rules.boards[window] else Transform3D(Basis.from_scale(Vector3.ZERO), _plank_places[index].origin))


# ------------------------------------------------------------------ the doors (polish1 D4b)

const DOOR_H := 2.15


func _build_door(entry: int, wood: Material) -> void:
	var w: Dictionary = rules.windows[entry]
	var hut: Dictionary = rules.huts[int(w["hut"])]
	var yaw := float(hut["yaw"])
	var width := ShelterRules.DOOR
	var hinge_local := Vector2(-width * 0.5, ShelterRules.HALF.y - WALL * 0.5)  # in the hut's frame
	var hinge_at := (hut["at"] as Vector2) + ShelterRules._turn(hinge_local, yaw)
	var hinge := Node3D.new()
	hinge.position = ORIGIN + Vector3(hinge_at.x, 0.0, hinge_at.y)
	hinge.rotation.y = yaw
	add_child(hinge)
	var n_planks := rules.full_of(entry)
	var plank := BoxMesh.new()
	plank.size = Vector3(width / float(n_planks) - 0.02, DOOR_H, 0.07)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plank
	mm.instance_count = n_planks
	var rng := RandomNumberGenerator.new()
	rng.seed = 90 + entry
	for i in n_planks:
		var h := DOOR_H - rng.randf_range(0.0, 0.08)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.01, 0.01)), Vector3(width / float(n_planks) * (float(i) + 0.5), h * 0.5, 0)))
	var leaf := MultiMeshInstance3D.new()
	leaf.multimesh = mm
	leaf.material_override = wood
	hinge.add_child(leaf)
	for y: float in [0.45, DOOR_H - 0.45]:  # two cross battens hold the planks
		var batten := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width - 0.1, 0.14, 0.05)
		batten.mesh = bm
		batten.material_override = wood
		batten.position = Vector3(width * 0.5, y, -0.06)
		hinge.add_child(batten)
	var iron := StandardMaterial3D.new()  # two black iron straps and a ring pull on the outside
	iron.albedo_color = Color(0.09, 0.09, 0.1)
	iron.metallic = 0.5
	iron.roughness = 0.6
	for y: float in [0.45, DOOR_H - 0.45]:
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(width * 0.8, 0.07, 0.02)
		strap.mesh = sm
		strap.material_override = iron
		strap.position = Vector3(width * 0.4, y, 0.045)
		hinge.add_child(strap)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.06
	rm.outer_radius = 0.09
	rm.rings = 12
	rm.ring_segments = 6
	ring.mesh = rm
	ring.material_override = iron
	ring.rotation.x = PI * 0.5
	ring.position = Vector3(width - 0.22, 1.05, 0.07)
	hinge.add_child(ring)
	var body := StaticBody3D.new()
	body.add_to_group(&"nav_skip")
	hinge.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, DOOR_H, 0.12)
	shape.shape = box
	shape.position = Vector3(width * 0.5, DOOR_H * 0.5, 0)
	body.add_child(shape)
	_door_leaves[entry] = [hinge, mm, shape, leaf]
	_door_angle[entry] = 0.0


func _show_door(entry: int) -> void:
	var parts: Array = _door_leaves[entry]
	var mm: MultiMesh = parts[1]
	var n_planks := rules.full_of(entry)
	var left: int = rules.boards[entry]
	var rng := RandomNumberGenerator.new()
	rng.seed = 90 + entry
	var width := ShelterRules.DOOR
	for i in n_planks:
		var h := DOOR_H - rng.randf_range(0.0, 0.08)
		var keep := i < left
		var xf := Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.01, 0.01)), Vector3(width / float(n_planks) * (float(i) + 0.5), h * 0.5, 0))
		mm.set_instance_transform(i, xf if keep else Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))
	for child in (parts[0] as Node3D).get_children():
		if child is MeshInstance3D and not (child is MultiMeshInstance3D):
			(child as Node3D).visible = left > 0  # the battens go with the last plank
	var broken := left <= 0
	var is_open: bool = rules.open[entry] == 1
	(parts[2] as CollisionShape3D).set_deferred("disabled", broken or is_open)
	var target := 1.75 if is_open else 0.0  # swings inward, flat against the front wall
	if not is_inside_tree():
		(parts[0] as Node3D).rotation.y = float((rules.huts[int(rules.windows[entry]["hut"])] as Dictionary)["yaw"]) + target
		return
	var hinge: Node3D = parts[0]
	var base := float((rules.huts[int(rules.windows[entry]["hut"])] as Dictionary)["yaw"])
	var tw := create_tween()
	tw.tween_property(hinge, "rotation:y", base + target, 0.35).set_trans(Tween.TRANS_SINE)


# The door entrance a world spot is at (within reach), -1 = none.
func door_near(world: Vector3) -> int:
	var e: int = rules.window_near(world.x - ORIGIN.x, world.z - ORIGIN.z)
	return e if rules.is_door(e) else -1


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


# One hut: four walls of pieces around the doorway and the windows (each piece drawn and solid), a pitched thatch
# roof on a ridge beam, and inside a table with a lantern (polish1 D4b: 12 x 9 m, a door, two windows at the back).
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
	_piece(holder, walls, Vector3(door * 2.0, HIGH - DOOR_H - 0.05, WALL), Vector3(0, (HIGH + DOOR_H + 0.05) * 0.5, half.y - WALL * 0.5))
	# the back wall (-z): two windows, at x -3 and +3
	var z := -half.y + WALL * 0.5
	var xs := [-half.x, -3.0 - gap, -3.0 + gap, 3.0 - gap, 3.0 + gap, half.x]
	for k in 3:
		var x0: float = xs[k * 2]
		var x1: float = xs[k * 2 + 1]
		_piece(holder, walls, Vector3(x1 - x0, HIGH, WALL), Vector3((x0 + x1) * 0.5, HIGH * 0.5, z))
	for wx: float in [-3.0, 3.0]:
		_piece(holder, walls, Vector3(gap * 2.0, SILL, WALL), Vector3(wx, SILL * 0.5, z))
		_piece(holder, walls, Vector3(gap * 2.0, HIGH - TOP, WALL), Vector3(wx, (HIGH + TOP) * 0.5, z))
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
	# pitched roof: two thatch slopes from a ridge beam along x (the gables over the side walls)
	var rise := 1.6
	var slope := Vector2(half.y + 0.5, rise).length()
	for side: float in [-1.0, 1.0]:
		var slab := BoxMesh.new()
		slab.size = Vector3(half.x * 2.0 + 0.9, 0.22, slope)
		var roof := MeshInstance3D.new()
		roof.mesh = slab
		roof.material_override = thatch
		roof.position = Vector3(0, HIGH + rise * 0.5, side * (half.y + 0.5) * 0.5)
		roof.rotation.x = side * atan2(rise, half.y + 0.5)
		holder.add_child(roof)
	# gable ends: one flat five-sided board each side, up under the thatch (both faces drawn; no collider: out of reach)
	var gable := SurfaceTool.new()
	gable.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eave := rise * 0.5 / (half.y + 0.5) - 0.09  # the thatch's underside above the wall's end
	for side: float in [-1.0, 1.0]:
		var gx := side * (half.x - WALL * 0.5)
		var outline: Array[Vector3] = [Vector3(gx, HIGH, -half.y), Vector3(gx, HIGH + eave, -half.y), Vector3(gx, HIGH + rise - 0.1, 0.0), Vector3(gx, HIGH + eave, half.y), Vector3(gx, HIGH, half.y)]
		for k in range(1, 4):
			for tri: Array in [[0, k, k + 1], [0, k + 1, k]]:  # the two windings: one faces out, one in
				var ta: Vector3 = outline[tri[0]]
				gable.set_normal((outline[tri[2]] - ta).cross(outline[tri[1]] - ta).normalized())  # clockwise = the front: this way out
				for v: int in tri:
					gable.add_vertex(outline[v])
	var gables := MeshInstance3D.new()
	gables.mesh = gable.commit()
	gables.material_override = wood
	holder.add_child(gables)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(half.x * 2.0 + 0.6, 0.25, 0.25)
	beam.mesh = bm
	beam.material_override = wood
	beam.position = Vector3(0, HIGH + rise, 0)
	holder.add_child(beam)
	# inside: a plank table with a lantern (it glows; no real light)
	var table := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(2.0, 0.08, 1.0)
	table.mesh = tm
	table.material_override = wood
	table.position = Vector3(-2.6, 0.82, -1.6)
	holder.add_child(table)
	for lx: float in [-0.85, 0.85]:
		for lz: float in [-0.4, 0.4]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.08, 0.8, 0.08)
			leg.mesh = lm
			leg.material_override = wood
			leg.position = Vector3(-2.6 + lx, 0.4, -1.6 + lz)
			holder.add_child(leg)
	var box := BoxShape3D.new()  # the table is solid (a smooth box: nothing to catch on)
	box.size = Vector3(2.0, 0.86, 1.0)
	var tshape := CollisionShape3D.new()
	tshape.shape = box
	tshape.position = Vector3(-2.6, 0.43, -1.6)
	holder.add_child(tshape)
	var lamp := MeshInstance3D.new()
	var lmesh := CylinderMesh.new()
	lmesh.top_radius = 0.09
	lmesh.bottom_radius = 0.11
	lmesh.height = 0.26
	lamp.mesh = lmesh
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.8, 0.45)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.material_override = glow
	lamp.position = Vector3(-2.6, 0.99, -1.6)
	holder.add_child(lamp)


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
