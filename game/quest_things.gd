# Purpose: the main quest's things in the world: the keeper's logbook in the sand, the brine jars that glow fuller
# as they fill, the three old lamps on their posts (game/hidden_target.gd: shoot them), and the bell on Gull Rock.
# Draws and reports lamp hits only: core/quest_state.gd decides.
# Dependencies: game/hidden_target.gd, game/surface_library.gd. `setup(places, on_lamp)`, then `show_state(...)`.
extends Node3D

const HiddenTarget = preload("res://game/hidden_target.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")

var _jar_glow := StandardMaterial3D.new()
var _lamps: Array = []  # MeshInstance3D glass of each lamp
var _lamp_bodies: Array = []
var _lit := StandardMaterial3D.new()
var _out := StandardMaterial3D.new()
var _bell: Node3D


# places: {"log": Vector3, "jars": Vector3, "lamps": Array[Vector3] (the lamp's own height included), "bell": Vector3}
# (any may be missing); on_lamp(index) is called when a lamp is shot.
func setup(places: Dictionary, on_lamp: Callable) -> void:
	var wood := SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.25, 0.26, 0.28)
	iron.metallic = 0.5
	iron.roughness = 0.6
	if places.has("log"):  # a logbook half in the sand
		var book := _box(self, Vector3(0.34, 0.07, 0.26), places["log"] + Vector3(0, 0.03, 0), Color(0.32, 0.18, 0.1))
		book.rotation = Vector3(0.25, 0.6, 0.1)
	if places.has("jars"):  # three jars on a plank
		var jars := Node3D.new()
		jars.position = places["jars"]
		add_child(jars)
		var plank := MeshInstance3D.new()
		var plank_mesh := BoxMesh.new()
		plank_mesh.size = Vector3(1.8, 0.08, 0.5)
		plank.mesh = plank_mesh
		plank.material_override = wood
		plank.position = Vector3(0, 0.45, 0)
		jars.add_child(plank)
		_jar_glow.albedo_color = Color(0.2, 0.55, 0.6, 0.6)
		_jar_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_jar_glow.emission_enabled = true
		_jar_glow.emission = Color(0.1, 0.8, 0.7)
		_jar_glow.emission_energy_multiplier = 0.0
		var jar := CylinderMesh.new()
		jar.top_radius = 0.14
		jar.bottom_radius = 0.17
		jar.height = 0.42
		for i in 3:
			var one := MeshInstance3D.new()
			one.mesh = jar
			one.material_override = _jar_glow
			one.position = Vector3(-0.55 + 0.55 * float(i), 0.7, 0.0)
			jars.add_child(one)
		_box(jars, Vector3(0.12, 0.45, 0.12), Vector3(-0.8, 0.22, 0), Color(0.35, 0.24, 0.13))
		_box(jars, Vector3(0.12, 0.45, 0.12), Vector3(0.8, 0.22, 0), Color(0.35, 0.24, 0.13))
	_lit.albedo_color = Color(1.0, 0.85, 0.45)
	_lit.emission_enabled = true
	_lit.emission = Color(1.0, 0.75, 0.3)
	_lit.emission_energy_multiplier = 2.0
	_out.albedo_color = Color(0.12, 0.12, 0.12)
	var places_of_lamps: Array = places.get("lamps", [])
	for i in places_of_lamps.size():
		var top: Vector3 = places_of_lamps[i]
		var post := MeshInstance3D.new()
		var pole := CylinderMesh.new()
		pole.top_radius = 0.06
		pole.bottom_radius = 0.09
		pole.height = top.y
		post.mesh = pole
		post.material_override = wood
		post.position = Vector3(top.x, top.y * 0.5, top.z)
		add_child(post)
		var body := HiddenTarget.new()
		body.position = top + Vector3(0, 0.22, 0)
		body.hit_by = on_lamp.bind(i)
		var shape := CollisionShape3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.28
		shape.shape = ball
		body.add_child(shape)
		var glass := MeshInstance3D.new()
		var glass_mesh := SphereMesh.new()
		glass_mesh.radius = 0.18
		glass_mesh.height = 0.36
		glass.mesh = glass_mesh
		glass.material_override = _lit
		body.add_child(glass)
		var cap := MeshInstance3D.new()
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = 0.05
		cap_mesh.bottom_radius = 0.22
		cap_mesh.height = 0.14
		cap.mesh = cap_mesh
		cap.material_override = iron
		cap.position = Vector3(0, 0.22, 0)
		body.add_child(cap)
		add_child(body)
		_lamps.append(glass)
		_lamp_bodies.append(body)
	if places.has("bell"):  # a ship's bell under a little frame of driftwood
		_bell = Node3D.new()
		_bell.position = places["bell"]
		add_child(_bell)
		for side: float in [-0.7, 0.7]:
			_box(_bell, Vector3(0.14, 2.0, 0.14), Vector3(side, 1.0, 0), Color(0.42, 0.35, 0.27))
		_box(_bell, Vector3(1.6, 0.14, 0.16), Vector3(0, 2.0, 0), Color(0.42, 0.35, 0.27))
		var bell := MeshInstance3D.new()
		var bell_mesh := CylinderMesh.new()
		bell_mesh.top_radius = 0.16
		bell_mesh.bottom_radius = 0.34
		bell_mesh.height = 0.5
		bell.mesh = bell_mesh
		var bronze := StandardMaterial3D.new()
		bronze.albedo_color = Color(0.62, 0.45, 0.2)
		bronze.metallic = 0.7
		bronze.roughness = 0.4
		bell.material_override = bronze
		bell.position = Vector3(0, 1.62, 0)
		_bell.add_child(bell)


# fill = 0..1 of the jars (kills step), lamps_out[i] = that lamp is out; lamps only take shots while `lamps_armed`.
func show_state(fill: float, lamps_out: Array, lamps_armed: bool) -> void:
	_jar_glow.emission_energy_multiplier = 2.5 * clampf(fill, 0.0, 1.0)
	for i in _lamps.size():
		var out: bool = i < lamps_out.size() and bool(lamps_out[i])
		(_lamps[i] as MeshInstance3D).material_override = _out if out else _lit
		(_lamp_bodies[i] as Node).set("armed", lamps_armed and not out)


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	var look := StandardMaterial3D.new()
	look.albedo_color = color
	piece.material_override = look
	piece.position = at
	parent.add_child(piece)
	return piece
