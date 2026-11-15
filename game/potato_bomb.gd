# Purpose: HOT POTATO thrown (diary/DESIGN_UNIQUES.md, region 3 chase gun): the whole red-hot grenade launcher flies
# end over end and goes off in a big blast where it lands. The thrower's own bomb deals the damage; another player's
# (a copy, game/net_chase.gd "potato") only shows.
# Dependencies: game/explosives.gd (blast, show_flash, sounds), game/weapon_models.gd (the launcher's model).
extends Node3D

const WeaponModels = preload("res://game/weapon_models.gd")
const GRAVITY := 12.0

var explosives: Node3D
var owned := true
var damage := 0.0
var radius := 6.0

var _vel := Vector3.ZERO
var _body: Node3D
var _query := PhysicsRayQueryParameters3D.new()
var _ignore: Array[RID] = []
var _life := 5.0


func throw(from: Vector3, velocity: Vector3, ignore: Array[RID]) -> void:
	position = from
	_vel = velocity
	_ignore = ignore
	_body = WeaponModels.build("grenade_launcher")
	if _body != null:
		add_child(_body)
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.albedo_color = Color(1.0, 0.35, 0.05)
		for mesh in _body.find_children("*", "GeometryInstance3D", true, false):
			(mesh as GeometryInstance3D).material_overlay = glow
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.15)
	light.omni_range = 4.0
	light.light_energy = 1.5
	add_child(light)


func _physics_process(delta: float) -> void:
	_life -= delta
	_vel.y -= GRAVITY * delta
	var to := position + _vel * delta
	_query.from = position
	_query.to = to
	_query.exclude = _ignore
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty() or _life <= 0.0:
		_boom(hit.position if not hit.is_empty() else to)
		return
	position = to
	if _body != null:
		_body.rotate_x(delta * 11.0)
		_body.rotate_y(delta * 3.0)


func _boom(at: Vector3) -> void:
	if explosives != null:
		if owned:
			explosives.blast(at, radius, damage)
		else:
			explosives.show_flash(at, radius)
		if explosives.sounds != null:
			explosives.sounds.call("play", "explosion", at)
	queue_free()
