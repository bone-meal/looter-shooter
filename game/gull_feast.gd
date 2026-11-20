# Purpose: polish1 item 36: seagulls come down on a dead crab. A small flock flies in from over the sea, lands round
# the body, pecks at it (the body shrinks away meanwhile: game/enemy.gd fall), then flies off and the node is gone.
# Crabs only (an island enemy with "remains": "gulls" in data/island_rounds.json). Each machine shows its own; at most
# MAX feasts at once (more crabs dying meanwhile just sink as before).
# Dependencies: the gull model (assets/models/weapons/uniques/gull.gltf, nodes "WingL" / "WingR"; the same as
# game/gull_flock.gd). `at` = the body's place; add it anywhere in the world (top_level).
extends Node3D

const MODEL := "res://assets/models/weapons/uniques/gull.gltf"
const GROUP := "gull_feasts"
const MAX := 3
const ARRIVE := 1.6  # seconds flying in
const PECK := 5.0  # seconds on the ground
const LEAVE := 2.0
const SCALE := 1.4

var at := Vector3.ZERO
var _gulls: Array = []
var _from: Array = []  # each gull's start in the sky
var _spot: Array = []  # where it lands round the body
var _t := 0.0


# True when another feast may start now (the cap).
static func room(tree: SceneTree) -> bool:
	return ResourceLoader.exists(MODEL) and tree.get_nodes_in_group(GROUP).size() < MAX


func _ready() -> void:
	top_level = true
	add_to_group(GROUP)
	global_position = at
	var scene := load(MODEL) as PackedScene
	var count := randi_range(3, 5)
	var sky := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	for i in count:
		var g := scene.instantiate() as Node3D
		g.scale = Vector3.ONE * SCALE
		add_child(g)
		var a := TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
		var land := at + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.55, 0.9)
		var start := at + sky * 28.0 + Vector3(randf_range(-4.0, 4.0), 14.0 + randf_range(0.0, 4.0), randf_range(-4.0, 4.0))
		g.global_position = start
		_gulls.append(g)
		_from.append(start)
		_spot.append(land)


func _process(delta: float) -> void:
	_t += delta
	var flap_fast := _t < ARRIVE or _t > ARRIVE + PECK
	for i in _gulls.size():
		var g := _gulls[i] as Node3D
		var start: Vector3 = _from[i]
		var land: Vector3 = _spot[i]
		var lag := float(i) * 0.15
		for wing: String in ["WingL", "WingR"]:
			var w := g.find_child(wing, true, false) as Node3D
			if w != null:
				w.rotation.z = (sin(_t * 14.0 + float(i)) * 0.7 if flap_fast else 0.15) * (1.0 if wing == "WingR" else -1.0)
		if _t < ARRIVE + lag:  # gliding down onto the sand round the body
			var u := clampf(_t / (ARRIVE + lag), 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 2.0)
			g.global_position = start.lerp(land, e) + Vector3(0.0, sin(u * PI) * 1.5, 0.0)
			_face(g, land + (land - start))
		elif _t < ARRIVE + PECK:  # hopping and pecking at the body
			var bob := absf(sin(_t * (7.0 + float(i)) + float(i)))
			g.global_position = land + Vector3(0.0, 0.0, 0.0)
			g.rotation.x = -0.6 * bob  # head down to peck
			_face(g, at)
		else:  # off again over the sea
			var u := (_t - ARRIVE - PECK) / LEAVE
			g.rotation.x = 0.0
			var away := land + (land - at).normalized() * 18.0 * u + Vector3(0.0, 10.0 * u * u + 2.0 * u, 0.0)
			_face(g, away + (away - g.global_position))
			g.global_position = away
	if _t >= ARRIVE + PECK + LEAVE:
		queue_free()


func _face(g: Node3D, point: Vector3) -> void:
	var p := g.global_position
	if Vector2(point.x - p.x, point.z - p.z).length() > 0.05:
		g.look_at(Vector3(point.x, p.y, point.z), Vector3.UP, true)
