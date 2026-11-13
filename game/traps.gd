# Purpose: the islands' traps as things in the world: a coil on a hut's roof or a fire pit, each with a lever post
# where it is switched on; a running trap flickers. Draws only: core/trap_state.gd keeps the time and the session
# does the hurting.
# Dependencies: game/surface_library.gd. `add(kind, centre, lever)` per trap, `show_running(index, on)`.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")

var _glows: Array[StandardMaterial3D] = []
var _flames: Array[Node3D] = []
var _running: Array[bool] = []
var _t := 0.0


# kind = "electric" (centre = the hut's middle: the coil goes on its roof) or "fire" (centre = the pit). `radius` =
# how far it reaches; `lever` = where its switch post stands.
func add(kind: String, centre: Vector3, lever: Vector3, radius: float) -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.25, 0.3, 0.35) if kind == "electric" else Color(0.3, 0.2, 0.15)
	glow.emission = Color(0.5, 0.85, 1.0) if kind == "electric" else Color(1.0, 0.5, 0.1)
	glow.emission_energy_multiplier = 2.5
	_glows.append(glow)
	_running.append(false)
	var flames := Node3D.new()
	flames.visible = false
	add_child(flames)
	_flames.append(flames)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.3, 0.31, 0.34)
	iron.metallic = 0.6
	if kind == "electric":
		var pole := CylinderMesh.new()
		pole.top_radius = 0.07
		pole.bottom_radius = 0.1
		pole.height = 1.6
		_piece(self, pole, iron, centre + Vector3(0, 3.6, 0))
		var ball := SphereMesh.new()
		ball.radius = 0.32
		ball.height = 0.64
		_piece(self, ball, glow, centre + Vector3(0, 4.6, 0))
		var ring := TorusMesh.new()
		ring.inner_radius = radius - 0.12
		ring.outer_radius = radius
		ring.rings = 48
		ring.ring_segments = 6
		_piece(flames, ring, glow, centre + Vector3(0, 0.12, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var stones := TorusMesh.new()
		stones.inner_radius = radius - 0.35
		stones.outer_radius = radius
		stones.rings = 32
		stones.ring_segments = 6
		_piece(self, stones, iron, centre + Vector3(0, 0.05, 0))
		var flame := CylinderMesh.new()
		flame.top_radius = 0.0
		flame.bottom_radius = 0.35
		flame.height = 1.5
		flame.radial_segments = 6
		for n in 10:
			var angle := TAU * float(n) / 10.0
			_piece(flames, flame, glow, centre + Vector3(cos(angle), 0, sin(angle)) * (radius * (0.45 if n % 2 == 0 else 0.85)) + Vector3(0, 0.75, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var post := BoxMesh.new()
	post.size = Vector3(0.14, 1.2, 0.14)
	_piece(self, post, SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15)), lever + Vector3(0, 0.6, 0))
	var knob := BoxMesh.new()
	knob.size = Vector3(0.24, 0.3, 0.2)
	_piece(self, knob, glow, lever + Vector3(0, 1.3, 0))


func show_running(index: int, on: bool) -> void:
	_running[index] = on
	_flames[index].visible = on
	_glows[index].emission_enabled = on


func _process(delta: float) -> void:
	_t += delta
	for i in _running.size():
		if _running[i]:
			_glows[i].emission_energy_multiplier = 1.6 + 1.4 * absf(sin(_t * 17.0 + float(i)))


func _piece(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)
	return part
