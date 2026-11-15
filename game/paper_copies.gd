# Purpose: CARBON COPY's printed copies (diary/DESIGN_UNIQUES.md, raid chase gun): a flat paper cut-out of the shooter
# pops up beside him, fires once at what he aims at (owned: first enemy on the line takes `damage`; a copy only draws
# the shot), falls over flat and lies on the floor a while: raid floors fill with paper. One pool node in the world,
# at most MAX_SHEETS lying about (the oldest goes first).
# Dependencies: the paper_copy model; game/fx_kit.gd (tracer glow, muzzle flash); the enemy hit through physics.
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")

const MODEL := "res://assets/models/weapons/uniques/paper_copy.gltf"
const GROUP := "paper_copies"
const MAX_SHEETS := 24
const FIRE_AFTER := 0.3
const LIE_SECONDS := 12.0

var _sheets: Array = []  # {"node", "age", "aim", "owned", "damage", "fired", "ignore"}
var _scene: PackedScene
var _tracer_mesh: BoxMesh
var _tracer_mat: StandardMaterial3D
var hits := 0


static func pool(world: Node) -> Node3D:
	if world == null or not world.is_inside_tree():
		return null
	var found := world.get_tree().get_first_node_in_group(GROUP) as Node3D
	if found == null:
		found = (load("res://game/paper_copies.gd") as GDScript).new() as Node3D
		world.add_child(found)
	return found


func _ready() -> void:
	add_to_group(GROUP)
	if ResourceLoader.exists(MODEL):
		_scene = load(MODEL) as PackedScene


# A copy standing at `at` facing `yaw`, firing at `aim` in a moment.
func print_copy(at: Vector3, yaw: float, aim: Vector3, owned: bool, damage: float, ignore: Array = []) -> void:
	if _scene == null:
		return
	if _sheets.size() >= MAX_SHEETS:
		(_sheets.pop_front()["node"] as Node3D).queue_free()
	var sheet := _scene.instantiate() as Node3D
	add_child(sheet)
	sheet.global_position = at
	sheet.rotation = Vector3(0.0, yaw, 0.0)
	sheet.scale = Vector3(1.0, 0.05, 1.0)
	var pop := sheet.create_tween()
	pop.tween_property(sheet, "scale", Vector3.ONE, 0.12)
	_sheets.append({"node": sheet, "age": 0.0, "aim": aim, "owned": owned, "damage": damage, "fired": false, "ignore": ignore})


func count() -> int:
	return _sheets.size()


func _process(delta: float) -> void:
	for s: Dictionary in _sheets.duplicate():
		var sheet := s["node"] as Node3D
		if not is_instance_valid(sheet):
			_sheets.erase(s)
			continue
		s["age"] = float(s["age"]) + delta
		var age := float(s["age"])
		if not bool(s["fired"]) and age >= FIRE_AFTER:
			s["fired"] = true
			_fire(sheet, s)
			var fall := sheet.create_tween()
			fall.tween_interval(0.2)
			fall.tween_property(sheet, "rotation:x", -PI * 0.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if age >= LIE_SECONDS:
			_sheets.erase(s)
			var gone := sheet.create_tween()
			gone.tween_property(sheet, "scale", Vector3(1.0, 1.0, 0.01), 0.3)
			gone.tween_callback(sheet.queue_free)


func _fire(sheet: Node3D, s: Dictionary) -> void:
	var from := sheet.global_position + Vector3(0, 1.3, 0)
	var aim: Vector3 = s["aim"]
	var to := aim
	if bool(s["owned"]):
		var query := PhysicsRayQueryParameters3D.create(from, from + (aim - from).normalized() * 80.0, 3)
		var skip: Array[RID] = []
		for rid: RID in s["ignore"]:
			skip.append(rid)
		query.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			to = hit.position
			var thing: Object = hit.collider
			if thing != null and thing.has_method("on_hit"):
				thing.call("on_hit", float(s["damage"]), hit.position, hit.normal)
				hits += 1
	_tracer(from, to)


func _tracer(from: Vector3, to: Vector3) -> void:
	if _tracer_mesh == null:
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = Vector3(0.03, 0.03, 1.0)
		_tracer_mat = FxKit.glow(Color(1.0, 0.85, 0.5))
	FxKit.burst(self, from, Color(1.0, 0.8, 0.4), 6, 0.2, 0.25, 2.0, 0.0)  # its muzzle flash
	var line := MeshInstance3D.new()
	line.mesh = _tracer_mesh
	line.material_override = _tracer_mat
	add_child(line)
	line.global_position = (from + to) * 0.5
	if from.distance_to(to) > 0.05:
		line.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	line.scale = Vector3(1.0, 1.0, from.distance_to(to))
	get_tree().create_timer(0.06).timeout.connect(line.queue_free)
