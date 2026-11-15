# Purpose: SWAMP GAS's clouds (diary/DESIGN_UNIQUES.md, region 2 chase gun): every shot of the gun leaves a small
# cloud of green swamp gas hanging where it went. Any fire sets a cloud off (a burning enemy inside it, a burning path
# or inferno, a running fire pit, any blast's flash: nodes in group "fire_sources" answer fire_near); a cloud going
# off is itself a blast, so the flash sets off every cloud near it: a chain. Pool of a few clouds, oldest replaced.
# Numbers from the gun's data "cfg" (data/gun_uniques.json swamp_gas).
# Dependencies: game/explosives.gd (blast, its enemy source, sounds), groups "fire_sources".
extends Node3D

const POOL_SIZE := 8
const CHECK_EVERY := 0.1  # seconds between looks for fire

var explosives: Node3D

var _puffs: Array[MeshInstance3D] = []  # two soft balls per cloud
var _life := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _fuse := PackedFloat32Array()  # > 0: caught fire, goes off when it reaches 0 (the chain's small delay)
var _cfg: Dictionary = {}
var _check := 0.0
var _clock := 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("swamp_gas")
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.45, 0.62, 0.2, 0.32)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_BACK  # seen from outside only (no green wash with the eye inside)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	for i in POOL_SIZE * 2:
		var ball_node := MeshInstance3D.new()
		ball_node.mesh = ball
		ball_node.material_override = _material
		ball_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball_node.visible = false
		add_child(ball_node)
		_puffs.append(ball_node)
	_life.resize(POOL_SIZE)
	_damage.resize(POOL_SIZE)
	_fuse.resize(POOL_SIZE)


# A new cloud at `at` (cfg: radius, seconds, damage share of the gun's damage).
func puff(at: Vector3, cfg: Dictionary, gun_damage: float) -> void:
	_cfg = cfg
	var i := 0
	for k in POOL_SIZE:
		if _life[k] <= 0.0:
			i = k
			break
		if _life[k] < _life[i]:
			i = k
	var r := float(cfg.get("cloud_radius", 1.8))
	_life[i] = float(cfg.get("cloud_seconds", 9.0))
	_damage[i] = gun_damage * float(cfg.get("pop_damage", 2.5))
	_fuse[i] = 0.0
	for n in 2:
		var p := _puffs[i * 2 + n]
		p.position = at + Vector3(randf_range(-0.3, 0.3), randf_range(-0.1, 0.3), randf_range(-0.3, 0.3)) * r
		p.scale = Vector3.ONE * r * (0.75 if n == 0 else 0.6)
		p.visible = true


func active_count() -> int:
	var n := 0
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			n += 1
	return n


func _process(delta: float) -> void:
	_clock += delta
	if active_count() == 0:
		return
	_check -= delta
	var look := _check <= 0.0
	if look:
		_check = CHECK_EVERY
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		var at := _puffs[i * 2].position
		var r := float(_cfg.get("cloud_radius", 1.8))
		for n in 2:  # it drifts up a little and breathes
			var p := _puffs[i * 2 + n]
			p.position.y += delta * 0.08
			p.scale = Vector3.ONE * r * (0.75 if n == 0 else 0.6) * (1.0 + 0.06 * sin(_clock * 2.0 + float(i * 2 + n)))
		if _fuse[i] > 0.0:
			_fuse[i] -= delta
			if _fuse[i] <= 0.0:
				_go_off(i)
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_hide(i)
			continue
		if look and _fire_near(at, r):
			_fuse[i] = float(_cfg.get("chain_delay", 0.12))


func _fire_near(at: Vector3, r: float) -> bool:
	for source: Node in get_tree().get_nodes_in_group("fire_sources"):
		if source.call("fire_near", at, r):
			return true
	if explosives != null and explosives.source != null:
		for enemy: Node3D in explosives.source.enemy_list():
			if is_instance_valid(enemy) and enemy.has_method("is_burning") and enemy.is_burning() and enemy.global_position.distance_to(at) <= r + 0.6:
				return true
	return false


func _go_off(i: int) -> void:
	var at := _puffs[i * 2].position
	var r := float(_cfg.get("cloud_radius", 1.8)) * float(_cfg.get("blast_scale", 1.6))
	_hide(i)
	if explosives == null:
		return
	explosives.blast(at, r, _damage[i])  # its flash reaches the next cloud: the chain goes on
	if explosives.sounds != null:
		explosives.sounds.call("play", "explosion", at)
	if explosives.source != null:
		for enemy: Node3D in explosives.source.enemy_list():
			if is_instance_valid(enemy) and enemy.has_method("apply_burn") and enemy.global_position.distance_to(at) <= r:
				enemy.apply_burn(_damage[i] * float(_cfg.get("burn_share", 0.15)), 3.0)


func _hide(i: int) -> void:
	_life[i] = 0.0
	_fuse[i] = 0.0
	_puffs[i * 2].visible = false
	_puffs[i * 2 + 1].visible = false
