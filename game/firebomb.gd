# Purpose: KEEPER'S LANTERN thrown as a firebomb (diary/DESIGN_UNIQUES.md): the lantern flies in an arc, smashes in
# a blast and leaves a patch of burning oil that sets enemies on fire for a few seconds and counts as fire for Swamp
# Gas (fire_near). The thrower's own bomb deals the damage; another player's (a copy, game/net_chase.gd) only shows.
# Dependencies: game/explosives.gd (blast, show_flash, its enemy source, sounds),
# assets/models/weapons/uniques/keepers_lantern_free.gltf.
extends Node3D

const MODEL := "res://assets/models/weapons/uniques/keepers_lantern_free.gltf"
const GRAVITY := 12.0
const FLAMES := 7

var explosives: Node3D
var owned := true  # false = another player's bomb: no damage here
var cfg: Dictionary = {}
var damage := 0.0

var _body: Node3D
var _vel := Vector3.ZERO
var _burning := -1.0  # seconds of fire left once it smashed (< 0 = still flying)
var _tick := 0.0
var _flames: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _query := PhysicsRayQueryParameters3D.new()
var _ignore: Array[RID] = []
var _life := 6.0


func throw(from: Vector3, velocity: Vector3, ignore: Array[RID]) -> void:
	add_to_group("fire_sources")
	position = from
	_vel = velocity
	_ignore = ignore
	if ResourceLoader.exists(MODEL):
		_body = (load(MODEL) as PackedScene).instantiate() as Node3D
		_body.scale = Vector3.ONE * 2.0
		add_child(_body)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.65, 0.3)
	_light.omni_range = 5.0
	_light.light_energy = 1.2
	add_child(_light)


func _physics_process(delta: float) -> void:
	if _burning >= 0.0:
		return
	_life -= delta
	_vel.y -= GRAVITY * delta
	var to := position + _vel * delta
	_query.from = position
	_query.to = to
	_query.exclude = _ignore
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty() or _life <= 0.0:
		_smash(hit.position if not hit.is_empty() else to)
		return
	position = to
	if _body != null:
		_body.rotate_x(delta * 9.0)


func _smash(at: Vector3) -> void:
	position = at
	_burning = float(cfg.get("fire_seconds", 5.0))
	if _body != null:
		_body.queue_free()
		_body = null
	var radius := float(cfg.get("fire_radius", 3.0))
	if explosives != null:
		if owned:
			explosives.blast(at, radius, damage)
		else:
			explosives.show_flash(at, radius)
		if explosives.sounds != null:
			explosives.sounds.call("play", "explosion", at)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.22
	cone.height = 0.9
	cone.radial_segments = 6
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.55, 0.15)
	for n in FLAMES:
		var flame := MeshInstance3D.new()
		flame.mesh = cone
		flame.material_override = fire
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := TAU * float(n) / float(FLAMES)
		flame.position = Vector3(cos(angle), 0.4, sin(angle)) * Vector3(radius * 0.55, 1.0, radius * 0.55) * (0.5 if n % 2 == 0 else 1.0)
		add_child(flame)
		_flames.append(flame)


func _process(delta: float) -> void:
	if _burning < 0.0:
		return
	_burning -= delta
	var k := 0
	for flame in _flames:  # the oil flickers and dies down at the end
		flame.scale = Vector3.ONE * clampf(_burning, 0.0, 1.0) * (0.8 + 0.35 * absf(sin(Time.get_ticks_msec() * 0.011 + float(k))))
		k += 1
	if _light != null:
		_light.light_energy = 1.6 * clampf(_burning, 0.0, 1.0)
	if _burning <= 0.0:
		queue_free()
		return
	_tick -= delta
	if owned and _tick <= 0.0 and explosives != null and explosives.source != null:
		_tick = 0.5
		var radius := float(cfg.get("fire_radius", 3.0))
		for enemy: Node3D in explosives.source.enemy_list():
			if is_instance_valid(enemy) and enemy.has_method("apply_burn") and enemy.global_position.distance_to(global_position) <= radius:
				enemy.apply_burn(damage * float(cfg.get("burn_share", 0.12)), 1.5)


# Swamp Gas asks: burning oil here?
func fire_near(point: Vector3, reach: float) -> bool:
	return _burning > 0.0 and point.distance_to(global_position) <= float(cfg.get("fire_radius", 3.0)) + reach
