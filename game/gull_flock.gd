# Purpose: CHIP THIEF's seagulls (diary/DESIGN_UNIQUES.md, region 5 chase gun): a few gulls circle above whoever
# holds the gun, flapping. send_gull() tosses a chip onto an enemy and sends an idle gull diving at it to peck (each
# peck calls `on_peck` with the target: the holder's flock deals the damage there; another player's copy only shows
# it). A child of the gimmick with top_level, so it goes when the gun goes.
# Dependencies: the gull model (nodes "WingL" / "WingR").
extends Node3D

const MODEL := "res://assets/models/weapons/uniques/gull.gltf"
const GROUP := "gull_flocks"
const RADIUS := 3.2
const HIGH := 5.0
const SCALE := 1.6

var count := 4
var pecks := 4
var peck_every := 0.4

var _anchor: Node3D
var _gulls: Array = []  # Node3D models
var _state: Array = []  # per gull: {} = circling, else {"target", "spot", "t", "pecked", "on_peck"}
var _chip_mesh: SphereMesh
var _chip_mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	add_to_group(GROUP)
	_anchor = get_parent() as Node3D
	if not ResourceLoader.exists(MODEL):
		return
	var scene := load(MODEL) as PackedScene
	for i in count:
		var g := scene.instantiate() as Node3D
		g.scale = Vector3.ONE * SCALE
		add_child(g)
		_gulls.append(g)
		_state.append({})
		g.global_position = _orbit(i)


func _orbit(i: int) -> Vector3:
	var center := _anchor.global_position if _anchor != null and is_instance_valid(_anchor) else global_position
	var a := Time.get_ticks_msec() / 1000.0 * 0.7 + TAU * float(i) / maxf(count, 1)
	return center + Vector3(cos(a) * RADIUS, HIGH + 0.4 * sin(a * 2.0 + float(i)), sin(a) * RADIUS)


func idle_count() -> int:
	var n := 0
	for s: Dictionary in _state:
		if s.is_empty():
			n += 1
	return n


# Tosses a chip from `from` onto `target` (or onto `spot` with no target) and sends an idle gull to peck. False = none idle.
func send_gull(from: Vector3, target: Node3D, spot: Vector3, on_peck: Callable = Callable()) -> bool:
	for i in _state.size():
		if (_state[i] as Dictionary).is_empty():
			_state[i] = {"target": target, "spot": spot, "t": 0.0, "pecked": 0, "on_peck": on_peck, "from": (_gulls[i] as Node3D).global_position}
			_toss(from, target.global_position if target != null and is_instance_valid(target) else spot)
			return true
	return false


func _toss(from: Vector3, to: Vector3) -> void:
	if _chip_mesh == null:
		_chip_mesh = SphereMesh.new()
		_chip_mesh.radius = 0.05
		_chip_mesh.height = 0.02
		_chip_mesh.radial_segments = 8
		_chip_mesh.rings = 3
		_chip_mat = StandardMaterial3D.new()
		_chip_mat.albedo_color = Color(0.95, 0.78, 0.38)
	var chip := MeshInstance3D.new()
	chip.mesh = _chip_mesh
	chip.material_override = _chip_mat
	chip.top_level = true
	add_child(chip)
	chip.global_position = from + Vector3(0, 1.0, 0)
	var tween := chip.create_tween()
	var top := (from + to) * 0.5 + Vector3(0, 2.5, 0)
	var start := from + Vector3(0, 1.0, 0)
	var land := to + Vector3(0, 0.1, 0)
	var fly := func(t: float) -> void:
		if is_instance_valid(chip):
			chip.global_position = start.lerp(top, t).lerp(top.lerp(land, t), t)
			chip.rotation.z = t * 12.0
	tween.tween_method(fly, 0.0, 1.0, 0.5)
	tween.tween_interval(1.2)
	tween.tween_callback(chip.queue_free)


func _process(delta: float) -> void:
	var visible_now := _anchor != null and is_instance_valid(_anchor) and _anchor.is_visible_in_tree()
	visible = visible_now
	var t_now := Time.get_ticks_msec() / 1000.0
	for i in _gulls.size():
		var g := _gulls[i] as Node3D
		var s: Dictionary = _state[i]
		for wing: String in ["WingL", "WingR"]:
			var w := g.find_child(wing, true, false) as Node3D
			if w != null:
				w.rotation.z = sin(t_now * (14.0 if not s.is_empty() else 7.0) + float(i)) * 0.6 * (1.0 if wing == "WingR" else -1.0)
		var goal: Vector3
		if s.is_empty():
			goal = _orbit(i)
			var ahead := goal + (goal - g.global_position) * 3.0
			g.global_position = g.global_position.lerp(goal, minf(1.0, delta * 3.0))
			if g.global_position.distance_to(ahead) > 0.1:
				g.look_at(Vector3(ahead.x, g.global_position.y, ahead.z), Vector3.UP, true)
			continue
		var target: Node3D = s["target"] if s["target"] != null and is_instance_valid(s["target"]) else null
		var spot: Vector3 = target.global_position if target != null else s["spot"]
		var head := spot + Vector3(0, 2.0, 0)
		s["t"] = float(s["t"]) + delta
		var t := float(s["t"])
		if t < 0.6:  # the dive
			g.global_position = (s["from"] as Vector3).lerp(head, t / 0.6)
			if head.distance_to(s["from"]) > 0.1:
				g.look_at(head + (head - (s["from"] as Vector3)), Vector3.UP, true)
		elif int(s["pecked"]) < pecks and (target == null or not target.health.is_dead() or s["on_peck"] == Callable()):  # pecking at its head
			g.global_position = head + Vector3(0, 0.25 * absf(sin(t * 8.0)), 0)
			if t >= 0.6 + peck_every * float(int(s["pecked"]) + 1):
				s["pecked"] = int(s["pecked"]) + 1
				var told: Callable = s["on_peck"]
				if told.is_valid() and target != null:
					told.call(target)
		else:  # back up to the circle
			var home := _orbit(i)
			g.global_position = g.global_position.lerp(home, minf(1.0, delta * 3.0))
			if g.global_position.distance_to(home) < 0.5:
				_state[i] = {}


# Whose flock this is (0 = ours / unknown): the remote player body it circles.
func peer() -> int:
	var n: Node = get_parent()
	while n != null:
		if "peer_id" in n:
			return int(n.get("peer_id"))
		n = n.get_parent()
	return 0
