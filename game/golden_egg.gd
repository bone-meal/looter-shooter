# Purpose: GOLDEN GOOSE's egg (diary/DESIGN_UNIQUES.md, Vault chase gun): fired from the grenade launcher instead of a
# grenade, it flies in an arc, bounces to a stop and sits; after hatch_seconds it HATCHES: a blast (the launcher's
# splash) and a few chips for the shooter. The shooter's own egg does both; another player's copy (game/net_chase.gd
# "egg") only flashes.
# Dependencies: game/explosives.gd (blast, show_flash), the golden_egg model, game/fx_kit.gd (shell halves, gold dust); the session (group "game_session")
# for the chips.
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")

const MODEL := "res://assets/models/weapons/uniques/golden_egg.gltf"
const GROUP := "golden_eggs"
const SIZE := 0.13

var explosives: Node3D
var owned := true
var damage := 0.0
var radius := 4.0
var chips := 5
var hatch_seconds := 3.0
var numbers: Node

var _vel := Vector3.ZERO
var _age := 0.0
var _resting := false
var _query := PhysicsRayQueryParameters3D.new()
var _body: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	if ResourceLoader.exists(MODEL):
		_body = (load(MODEL) as PackedScene).instantiate() as Node3D
		_body.scale = Vector3.ONE * SIZE
		add_child(_body)
	_query.collision_mask = 1


func throw(from: Vector3, vel: Vector3, ignore: Array[RID]) -> void:
	global_position = from
	_vel = vel
	_query.exclude = ignore


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= hatch_seconds:
		_hatch()
		return
	if _body != null and _age > hatch_seconds - 0.8:
		_body.rotation.z = sin(_age * 40.0) * 0.25  # it wobbles before it hatches
	if _resting:
		return
	_vel.y -= 9.8 * delta
	var to := global_position + _vel * delta
	_query.from = global_position
	_query.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		global_position = to
		if _body != null:
			_body.rotation.x += delta * 8.0
		return
	global_position = (hit.position as Vector3) + (hit.normal as Vector3) * SIZE
	_vel = _vel.bounce(hit.normal) * 0.35
	if _vel.length() < 1.5 or (hit.normal as Vector3).y > 0.7 and absf(_vel.y) < 1.0:
		_resting = true
		if _body != null:
			_body.rotation = Vector3.ZERO


func _hatch() -> void:
	_shell_burst()
	if explosives != null:
		if owned:
			explosives.call("blast", global_position, radius, damage)
			var session: Node = get_tree().get_first_node_in_group("game_session")
			if session != null and session.has_method("wallet") and chips > 0:
				session.call("wallet").call("add", chips)
			if numbers != null and numbers.has_method("say"):
				numbers.call("say", global_position + Vector3(0, 1.0, 0), "+%d CHIPS" % chips, Color(1.0, 0.85, 0.3))
		else:
			explosives.call("show_flash", global_position, radius)
	queue_free()


# The shell splits in two halves that tumble away, with a puff of gold dust (game/fx_kit.gd egg_shell, burst).
func _shell_burst() -> void:
	var world := get_parent()
	if world == null:
		return
	FxKit.burst(world, global_position + Vector3(0, 0.1, 0), Color(1.0, 0.82, 0.3), 18, 0.8, 0.14, 3.5)
	for half in 2:
		var shell: Node3D = FxKit.shape("egg_shell")
		if shell == null:
			return
		world.add_child(shell)
		shell.global_position = global_position
		shell.scale = Vector3.ONE * SIZE
		shell.rotation.x = 0.0 if half == 0 else PI
		var away := Vector3(randf_range(-1, 1), 1.6, randf_range(-1, 1)).normalized() * 0.9
		var tween := shell.create_tween()
		tween.tween_property(shell, "global_position", global_position + away, 0.4).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(shell, "rotation", shell.rotation + Vector3(randf_range(4, 9), randf_range(-3, 3), 0), 0.4)
		tween.tween_property(shell, "scale", Vector3.ONE * 0.01, 0.6)
		tween.tween_callback(shell.queue_free)
