# Purpose: VOLCANO SAUCE's eruption (diary/DESIGN_UNIQUES.md, region 3 chase gun): a geyser of fire bursting up from
# the ground under an enemy that took too much sauce. The shooter's own geyser blasts and sets enemies near it
# burning; a copy (another player's, game/net_chase.gd) only shows. While it burns it is fire for Swamp Gas.
# Dependencies: game/explosives.gd (blast, show_flash, its enemy source, sounds).
extends Node3D

const SECONDS := 1.4
const RINGS := 6

var explosives: Node3D
var owned := true
var damage := 0.0
var radius := 2.5
var burn_share := 0.2

var _t := 0.0
var _flames: Array[MeshInstance3D] = []
var _light: OmniLight3D


func erupt(at: Vector3) -> void:
	add_to_group("fire_sources")
	position = at
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.45
	cone.height = 1.0
	cone.radial_segments = 8
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.45, 0.1)
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = Color(1.0, 0.85, 0.4)
	for i in RINGS:
		var flame := MeshInstance3D.new()
		flame.mesh = cone
		flame.material_override = core if i % 2 == 0 else fire
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.scale = Vector3(1.0 - 0.12 * float(i), 1.0, 1.0 - 0.12 * float(i))
		add_child(flame)
		_flames.append(flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 7.0
	_light.light_energy = 2.0
	_light.position = Vector3(0, 1.5, 0)
	add_child(_light)
	if explosives == null:
		return
	if owned:
		explosives.blast(at, radius, damage)
		if explosives.source != null:
			for enemy: Node3D in explosives.source.enemy_list():
				if is_instance_valid(enemy) and enemy.has_method("apply_burn") and enemy.global_position.distance_to(at) <= radius:
					enemy.apply_burn(damage * burn_share, 3.0)
	else:
		explosives.show_flash(at, radius)
	if explosives.sounds != null:
		explosives.sounds.call("play", "explosion", at)


func _process(delta: float) -> void:
	_t += delta
	var k := _t / SECONDS
	if k >= 1.0:
		queue_free()
		return
	var height := sin(minf(k * 2.0, 1.0) * PI * 0.5) * 4.5 * (1.0 - maxf(0.0, k - 0.6) * 2.5)  # shoots up, hangs, falls away
	for i in _flames.size():
		var f := _flames[i]
		f.position.y = height * (float(i) + 0.5) / float(RINGS)
		f.rotation.y = _t * (6.0 + float(i))
		f.scale.y = maxf(0.05, height / float(RINGS) * 1.6)
	_light.light_energy = 2.0 * (1.0 - k)


func fire_near(point: Vector3, reach: float) -> bool:
	return _t < SECONDS * 0.8 and Vector2(point.x - position.x, point.z - position.z).length() <= radius + reach
