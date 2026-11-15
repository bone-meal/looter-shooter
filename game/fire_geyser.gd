# Purpose: VOLCANO SAUCE's eruption (diary/DESIGN_UNIQUES.md, region 3 chase gun): a geyser of fire bursting up from
# the ground under an enemy that took too much sauce. The shooter's own geyser blasts and sets enemies near it
# burning; a copy (another player's, game/net_chase.gd) only shows. While it burns it is fire for Swamp Gas.
# Drawn with modelled flame tongues and embers (game/fx_kit.gd).
# Dependencies: game/explosives.gd (blast, show_flash, its enemy source, sounds), game/fx_kit.gd.
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")

const SECONDS := 1.4
const RINGS := 6

var explosives: Node3D
var owned := true
var damage := 0.0
var radius := 2.5
var burn_share := 0.2

var _t := 0.0
var _flames: Array[Node3D] = []  # modelled flame tongues (game/fx_kit.gd)
var _light: OmniLight3D


func erupt(at: Vector3) -> void:
	add_to_group("fire_sources")
	position = at
	for i in RINGS:
		var tongue := FxKit.flame()
		if tongue == null:
			break
		tongue.rotation.y = TAU * float(i) / float(RINGS)
		add_child(tongue)
		_flames.append(tongue)
	var embers := FxKit.particles(Color(1.0, 0.6, 0.2), 20, 1.1, 0.22, 7.0, 15.0, -3.0, false)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.4
	add_child(embers)
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
	for i in _flames.size():  # the tongues stack up the column, licking and turning
		var f := _flames[i]
		var part := (float(i) + 0.5) / float(RINGS)
		f.position = Vector3(0.0, height * part * 0.55, 0.0)
		f.rotation.y = TAU * float(i) / float(RINGS) + _t * (3.0 + float(i) * 0.7)
		var wide := (1.25 - part * 0.6) * (0.85 + 0.25 * sin(_t * 18.0 + float(i) * 2.1))
		f.scale = Vector3(wide * 3.5, maxf(0.05, height * (0.55 + 0.25 * part)), wide * 3.5)
	_light.light_energy = 2.0 * (1.0 - k)


func fire_near(point: Vector3, reach: float) -> bool:
	return _t < SECONDS * 0.8 and Vector2(point.x - position.x, point.z - position.z).length() <= radius + reach
