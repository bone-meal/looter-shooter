# Purpose: what a lit KEEPER'S LANTERN does to the world on this machine (diary/DESIGN_UNIQUES.md): enemies within its
# light glow (enemy.set_glow), the weather's fog thins while one is near the camera (island_weather.set_clear: "clears
# the fog round you for the whole party"), and every lantern sways on its hook. A lantern is any gimmick piece in group
# "lanterns" with the meta "lantern_held" (ours in hand, or another player's on his body: game/remote_player.gd) whose
# "Swing" node is showing (hidden while thrown). One per world, made by whoever first holds or sees a lantern.
# Dependencies: groups "lanterns", "island_weather"; the enemy list of the local player's explosives (group "fire_sources").
extends Node3D

const EVERY := 0.2  # seconds between looks
const GLOW_RANGE := 7.0  # metres round a lantern that enemies glow
const CLEAR_RANGE := 14.0  # a lantern this near the camera thins the fog
const FOG_LEFT := 0.25  # share of the weather's fog left near a lantern

var _wait := 0.0
var _t := 0.0
var _lit: Array[Node3D] = []  # enemies glowing now


static func ensure(world: Node) -> void:
	if world == null or world.get_tree() == null or world.get_tree().get_first_node_in_group("lantern_glow") != null:
		return
	var glow: Node3D = (load("res://game/lantern_glow.gd") as GDScript).new()
	glow.name = "LanternGlow"
	world.add_child(glow)


func _ready() -> void:
	add_to_group("lantern_glow")


func _process(delta: float) -> void:
	_t += delta
	var spots: Array[Vector3] = []
	for piece: Node in get_tree().get_nodes_in_group("lanterns"):
		var swing := (piece as Node3D).find_child("Swing", true, false) as Node3D
		if swing == null or not piece.has_meta("lantern_held") or not (piece as Node3D).is_visible_in_tree() or not swing.visible:
			continue
		swing.rotation = Vector3(sin(_t * 2.1 + float(piece.get_instance_id() % 7)) * 0.16, 0.0, sin(_t * 1.7) * 0.12)
		spots.append((piece as Node3D).global_position)
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = EVERY
	_glow_enemies(spots)
	_clear_fog(spots)


func _glow_enemies(spots: Array[Vector3]) -> void:
	var now: Array[Node3D] = []
	if not spots.is_empty():
		for enemy: Node3D in _enemy_list():
			if not is_instance_valid(enemy) or not enemy.has_method("set_glow"):
				continue
			for at in spots:
				if enemy.global_position.distance_squared_to(at) <= GLOW_RANGE * GLOW_RANGE:
					now.append(enemy)
					break
	for enemy in _lit:
		if is_instance_valid(enemy) and not now.has(enemy):
			enemy.call("set_glow", false)
	for enemy in now:
		enemy.call("set_glow", true)
	_lit = now


func _clear_fog(spots: Array[Vector3]) -> void:
	var weather := get_tree().get_first_node_in_group("island_weather")
	var camera := get_viewport().get_camera_3d()
	if weather == null or camera == null:
		return
	var near := false
	for at in spots:
		near = near or camera.global_position.distance_squared_to(at) <= CLEAR_RANGE * CLEAR_RANGE
	weather.call("set_clear", FOG_LEFT if near else 1.0)


func _enemy_list() -> Array:
	for node: Node in get_tree().get_nodes_in_group("fire_sources"):
		var source: Variant = node.get("source")
		if source != null and (source as Object).has_method("enemy_list"):
			return source.call("enemy_list")
	return []
