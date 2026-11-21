# Purpose: draws the Re-forge quest's pieces on the islands (polish1 D4e, item 38): the lighthouse (its lamp lights and
# its beam sweeps once the lens is fitted), the cliff foghorn (its crank turns while held, its lamp glows once done), the
# tide wheel (turns while its ritual runs and for good once done) and the brass lens lying where it was dropped this run.
# Each piece gets one smooth collider (no snagging: a cylinder for the tower, a box for the rest). Draws only.
# Dependencies: game/fantasy_models.gd. `setup(places, lens_spots)` before add_child; `show_state` when anything changes.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")

const LIT := {"lighthouse": Color(1.0, 0.9, 0.55), "foghorn": Color(1.0, 0.3, 0.15), "tide_wheel": Color(0.4, 0.9, 1.0)}

var _pieces := {}  # id -> {"root": Node3D, "glow": StandardMaterial3D, "spin": Node3D}
var _lens_nodes: Array[Node3D] = []
var _lens_glow := StandardMaterial3D.new()
var _beam: MeshInstance3D = null
var _spinning := {}  # id -> turns per second (0 = still)
var _time := 0.0


# places: [{"id", "model", "at": Vector3 (world), "yaw", "solid"}]; lens_spots: world spots (one shown at a time).
func setup(places: Array, lens_spots: Array) -> void:
	for place: Dictionary in places:
		var id := String(place["id"])
		var root := Node3D.new()
		root.position = place["at"]
		root.rotation.y = float(place["yaw"])
		add_child(root)
		var glow := StandardMaterial3D.new()
		glow.albedo_color = LIT.get(id, Color.WHITE).darkened(0.6)
		glow.emission = LIT.get(id, Color.WHITE)
		var made := FantasyModels.scene(String(place["model"]))
		var spin: Node3D = null
		if made != null:
			root.add_child(made)
			for found in made.find_children("*", "MeshInstance3D", true, false):
				if String(found.name).begins_with("Glow") or String(found.get_parent().name).begins_with("Glow"):
					(found as MeshInstance3D).material_override = glow
			spin = made.find_child("Spin", true, false) as Node3D
			_solid(root, made, id, float(place.get("solid", 1.0)))
		_pieces[id] = {"root": root, "glow": glow, "spin": spin}
		if id == "lighthouse" and spin != null:
			_beam = _make_beam()
			spin.add_child(_beam)
	_lens_glow.albedo_color = Color(1.0, 0.85, 0.5)
	_lens_glow.emission_enabled = true
	_lens_glow.emission = Color(1.0, 0.8, 0.4)
	_lens_glow.emission_energy_multiplier = 1.2
	for spot: Vector3 in lens_spots:
		var holder := Node3D.new()
		holder.position = spot
		holder.visible = false
		add_child(holder)
		var lens := FantasyModels.scene("quest_lens")
		if lens != null:
			lens.scale = Vector3.ONE * 1.6
			holder.add_child(lens)
			for found in lens.find_children("*", "MeshInstance3D", true, false):
				if String(found.name).begins_with("Glow") or String(found.get_parent().name).begins_with("Glow"):
					(found as MeshInstance3D).material_override = _lens_glow
		_lens_nodes.append(holder)


func _solid(root: Node3D, made: Node3D, id: String, radius: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := FantasyModels.bounds(made)
	if id == "lighthouse":
		var tower := CylinderShape3D.new()
		tower.radius = radius
		tower.height = box.size.y
		shape.shape = tower
		shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	else:
		var solid := BoxShape3D.new()
		solid.size = Vector3(box.size.x * 0.85, box.size.y, box.size.z * 0.85)
		shape.shape = solid
		shape.position = box.get_center()
	body.add_child(shape)
	root.add_child(body)


# The lighthouse's beam: two long faint cones out of the lamp's two lenses (unshaded, added light, no shadow).
func _make_beam() -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.3
	cone.bottom_radius = 3.2
	cone.height = 36.0
	cone.radial_segments = 10
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var light := StandardMaterial3D.new()
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	light.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	light.cull_mode = BaseMaterial3D.CULL_DISABLED
	light.albedo_color = Color(1.0, 0.92, 0.6, 0.18)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [1.0, -1.0]:  # each cone lies along z, its narrow end at the lamp
		tool.append_from(cone, 0, Transform3D(Basis(Vector3.RIGHT, -side * PI * 0.5), Vector3(0, 0, side * 18.3)))
	var mesh := tool.commit()
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.material_override = light
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	return beam


func _process(delta: float) -> void:
	_time += delta
	for id: String in _spinning:
		var rate := float(_spinning[id])
		var piece: Dictionary = _pieces.get(id, {})
		if rate != 0.0 and piece.get("spin") != null:
			(piece["spin"] as Node3D).rotate_object_local(Vector3.UP if id == "lighthouse" else Vector3.RIGHT, delta * TAU * rate)
	for holder in _lens_nodes:
		if holder.visible and holder.get_child_count() > 0:
			var lens := holder.get_child(0) as Node3D
			lens.rotation.y = _time * 1.2
			lens.position.y = 0.25 + sin(_time * 2.0) * 0.08


# done: piece id -> true; lens_at: which lens spot holds it (shown until found); turning: the tide wheel's ritual runs;
# cranking: someone holds the foghorn's crank (this machine's player); power_on: the island's power.
func show_state(done: Dictionary, lens_at: int, lens_found: bool, turning: bool, cranking: bool, power_on: bool) -> void:
	for i in _lens_nodes.size():
		_lens_nodes[i].visible = i == lens_at and not lens_found
	for id: String in _pieces:
		var piece: Dictionary = _pieces[id]
		var lit := power_on and done.has(id)
		var glow: StandardMaterial3D = piece["glow"]
		glow.emission_enabled = lit or (id == "tide_wheel" and turning)
		glow.emission_energy_multiplier = 2.2 if id == "lighthouse" else 1.4
		glow.albedo_color = LIT.get(id, Color.WHITE) if glow.emission_enabled else LIT.get(id, Color.WHITE).darkened(0.6)
	_spinning = {
		"lighthouse": 0.12 if power_on and done.has("lighthouse") else 0.0,
		"foghorn": 0.6 if cranking else 0.0,
		"tide_wheel": (0.18 if done.has("tide_wheel") else 0.3) if power_on and (turning or done.has("tide_wheel")) else 0.0,
	}
	if _beam != null:
		_beam.visible = power_on and done.has("lighthouse")


# Where a piece stands (world), for the session's reach checks and sounds.
func piece_at(id: String) -> Vector3:
	return (_pieces[id]["root"] as Node3D).global_position if _pieces.has(id) else Vector3.INF
