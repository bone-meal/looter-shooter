# Purpose: the islands' traps as things in the world: a coil on a hut's roof or a fire pit, each with a lever post
# where it is switched on; a running trap flickers. Draws only: core/trap_state.gd keeps the time and the session
# does the hurting.
# Dependencies: game/surface_library.gd, game/fantasy_models.gd (the fire pit model, polish1 item 32). `add(kind, centre, lever)` per trap, `show_running(index, on)`.
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")

var _glows: Array[StandardMaterial3D] = []
var _flames: Array[Node3D] = []
var _running: Array[bool] = []
var _fire_at := PackedVector3Array()  # a fire pit's centre (electric coils: never fire)
var _fire_reach := PackedFloat32Array()  # its radius, -1 for a coil
var _t := 0.0


# kind = "electric" (centre = the hut's middle: the coil goes on its roof) or "fire" (centre = the pit). `radius` =
# how far it reaches; `lever` = where its switch post stands.
func _ready() -> void:
	add_to_group("fire_sources")  # fire_near: Swamp Gas clouds catch from a running fire pit


func add(kind: String, centre: Vector3, lever: Vector3, radius: float) -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.25, 0.3, 0.35) if kind == "electric" else Color(0.3, 0.2, 0.15)
	glow.emission = Color(0.5, 0.85, 1.0) if kind == "electric" else Color(1.0, 0.5, 0.1)
	glow.emission_energy_multiplier = 2.5
	_glows.append(glow)
	_running.append(false)
	_fire_at.append(centre)
	_fire_reach.append(radius if kind == "fire" else -1.0)
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
		_piece(self, pole, iron, centre + Vector3(0, 5.3, 0))  # (polish1 D4b) on the bigger huts' ridge (4.6 m)
		var ball := SphereMesh.new()
		ball.radius = 0.32
		ball.height = 0.64
		_piece(self, ball, glow, centre + Vector3(0, 6.3, 0))
		var ring := TorusMesh.new()
		ring.inner_radius = radius - 0.12
		ring.outer_radius = radius
		ring.rings = 48
		ring.ring_segments = 6
		_piece(flames, ring, glow, centre + Vector3(0, 0.12, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif FantasyModels.has_model("fire_pit"):  # (polish1 item 32) a real fire pit: stone ring, ash, log pyres, embers
		var pit := FantasyModels.scene("fire_pit")
		pit.scale = Vector3.ONE * (radius / 6.0)
		pit.position = centre
		add_child(pit)
		for found in pit.find_children("Glow*", "MeshInstance3D", true, false):
			(found as MeshInstance3D).material_override = glow
		var flame := CylinderMesh.new()
		flame.top_radius = 0.0
		flame.bottom_radius = 0.4
		flame.height = 1.6
		flame.radial_segments = 6
		var heaps := [Vector2.ZERO]
		for k in 3:
			var a := TAU * (float(k) + 0.3) / 3.0
			heaps.append(Vector2(cos(a), sin(a)) * 3.2 * (radius / 6.0))
		for h: Vector2 in heaps:  # flames on the pyres, and licking the ash between them
			for n in 3:
				var o := Vector2(cos(TAU * float(n) / 3.0), sin(TAU * float(n) / 3.0)) * 0.35
				var lick := _piece(flames, flame, glow, centre + Vector3(h.x + o.x, 0.85, h.y + o.y))
				lick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				lick.set_meta("base", centre.y + 0.05)
		var board := Label3D.new()  # the lever says what it is
		board.text = "FIRE PIT"
		board.font_size = 48
		board.pixel_size = 0.004
		board.outline_size = 8
		board.modulate = Color(1.0, 0.62, 0.25)
		board.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		board.position = lever + Vector3(0, 1.75, 0)
		add_child(board)
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
	var embers := _fire_reach[index] > 0.0  # (polish1 item 32) a cold fire pit's embers still glow a little: it reads as a fire pit
	_glows[index].emission_enabled = on or embers
	if embers and not on:
		_glows[index].emission_energy_multiplier = 0.35


func _process(delta: float) -> void:
	_t += delta
	for i in _running.size():
		if _running[i]:
			_glows[i].emission_energy_multiplier = 1.6 + 1.4 * absf(sin(_t * 17.0 + float(i)))
			if _fire_reach[i] > 0.0:  # (polish1 item 32) the flames lick up and down, each on its own beat
				var k := 0
				for flame: Node3D in _flames[i].get_children():
					var tall := 0.6 + 0.55 * absf(sin(_t * (5.0 + float(k % 4)) + float(k) * 1.7))
					flame.scale = Vector3(1.0, tall, 1.0)
					if flame.has_meta("base"):  # grows from its foot, not its middle
						flame.position.y = float(flame.get_meta("base")) + 0.8 * tall
					k += 1


func _piece(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)
	return part


# True when a running fire pit reaches within `reach` of `point` (game/swamp_gas.gd asks).
func fire_near(point: Vector3, reach: float) -> bool:
	for i in _running.size():
		if _running[i] and _fire_reach[i] > 0.0 and point.distance_to(_fire_at[i]) <= _fire_reach[i] + reach:
			return true
	return false
