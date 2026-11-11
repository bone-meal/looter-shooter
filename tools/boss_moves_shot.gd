# Purpose: developer check of the bosses' special attacks without the whole game: a stand-in boss and a stand-in
# player on a flat field. Every move of every boss (data/fantasy/enemies.json "moves") is started once as the host
# would start it; a picture is saved while it warns and when it strikes (tools/shots/move_<boss>_<move>_a/b.png), and
# the log says how often the player standing in the warned place was hit, shoved or shot at.
# Writes tools/boss_moves_shot.log. Run scene tools/boss_moves_shot.tscn.
# Dependencies: core/fantasy_data.gd, game/boss_moves.gd.
extends Node3D

const FantasyData = preload("res://core/fantasy_data.gd")
const BossMoves = preload("res://game/boss_moves.gd")


class Health:
	func is_dead() -> bool:
		return false


class Dummy extends Node3D:  # stands in for game/enemy.gd (the boss) and for the player
	var health := Health.new()
	var _stats := {}
	var _size := Vector3(2.4, 4.0, 2.4)
	var element := "physical"
	var puppet := false
	var hits := 0
	var shots := 0
	var shoves := 0
	func take_damage(_amount: float, _element: String = "physical") -> void:
		hits += 1
	func shoot(_origin: Vector3, _aim: Vector3, _speed: float, _damage: float) -> void:
		shots += 1
	func shove(_v: Vector3) -> void:
		shoves += 1


class World extends Node3D:  # stands in for game/fantasy_world.gd
	func ground_height(_x: float, _z: float) -> float:
		return 0.0
	func walk_world(from: Vector3, step: Vector3, _pad: float, _mode: int, _hover: float) -> Vector3:
		return Vector3(from.x + step.x, 0.0, from.z + step.z)
	func local_of(at: Vector3) -> Vector3:
		return at
	func sound(_id: String, _at: Vector3 = Vector3.INF) -> void:
		pass


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.55, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(200, 200)
	floor_mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.26)
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(6.0, 22.0, 26.0)
	camera.look_at(Vector3(6.0, 0.0, 0.0))
	camera.current = true
	var world := World.new()
	add_child(world)
	var boss := Dummy.new()
	var player := Dummy.new()
	for body: Dummy in [boss, player]:
		var post := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 1.2 if body == boss else 0.4
		capsule.height = 4.0 if body == boss else 1.8
		post.mesh = capsule
		post.position.y = capsule.height * 0.5
		body.add_child(post)
		add_child(body)
	var moves := BossMoves.new()
	add_child(moves)
	moves.setup(world, player)
	moves.bodies = func() -> Array: return [player]
	var summoned := [0]
	moves.summoned.connect(func(_id: String, _x: float, _z: float) -> void: summoned[0] += 1)
	var enemies: Dictionary = FantasyData.load_all()["enemies"]["enemies"]
	var lines := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	for id: String in enemies:
		for move: Dictionary in enemies[id].get("moves", []):
			boss.global_position = Vector3.ZERO
			player.global_position = Vector3(5.0, 0.0, 1.0)  # inside every warning that is aimed at the player or around the boss
			boss._stats = enemies[id]
			player.hits = 0
			player.shoves = 0
			boss.shots = 0
			summoned[0] = 0
			moves.call("_begin", boss, move, player.global_position, 12345, false)
			await get_tree().create_timer(float(move["windup"]) * 0.75).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tools/shots/move_%s_%s_a.png" % [id, move["id"]])
			await get_tree().create_timer(float(move["windup"]) * 0.25 + 0.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tools/shots/move_%s_%s_b.png" % [id, move["id"]])
			await get_tree().create_timer(float(move.get("seconds", move.get("linger", 1.0))) + 2.5).timeout
			lines.append("%-14s %-14s %-7s '%s': hits=%d shoves=%d shots=%d summoned=%d boss moved %.1f m" % [id, move["id"], move["kind"], move.get("name", "?"), player.hits, player.shoves, boss.shots, summoned[0], boss.global_position.length()])
			moves.clear()
	lines.append("DONE")
	var f := FileAccess.open("res://tools/boss_moves_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
