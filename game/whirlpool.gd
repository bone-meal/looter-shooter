# Purpose: FLUSH's whirlpool (diary/DESIGN_UNIQUES.md, region 7 chase gun): opened where a grenade lands, it swirls
# for `seconds`: every 0.2 s each living, non-boss enemy inside `radius` is pushed round and in; one below flush_share
# of its health is FLUSHED (killed, "FLUSHED"). The shooter's own whirlpool does that; another player's copy
# (game/net_chase.gd "whirl") only shows. Drawn as the modelled vortex (dark water, foam spirals) turning, with spray
# off its rim; it shrinks away at the end.
# Dependencies: game/explosives.gd (enemy source, damage numbers), game/fx_kit.gd.
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")

const GROUP := "whirlpools"
const MAX_OPEN := 4

var explosives: Node3D
var owned := true
var radius := 4.0
var seconds := 4.0
var flush_share := 0.15
var swirl := 6.0

var _age := 0.0
var _tick := 0.0
var _rings: Array[Node3D] = []
var flushed := 0


static func can_open(tree: SceneTree) -> bool:
	return tree.get_nodes_in_group(GROUP).size() < MAX_OPEN


func _ready() -> void:
	add_to_group(GROUP)
	var funnel: Node3D = FxKit.shape("vortex")  # the modelled whirlpool (game/fx_kit.gd): dark water, foam spirals
	if funnel != null:
		FxKit.paint(funnel, FxKit.glow(Color(0.05, 0.22, 0.34, 0.8), false))
		var foam := funnel.find_child("Foam", true, false)
		if foam != null:
			FxKit.paint(foam, FxKit.glow(Color(0.8, 0.93, 1.0, 0.75), false))
		add_child(funnel)
		_rings.append(funnel)
	var spray := FxKit.particles(Color(0.85, 0.95, 1.0, 0.8), 10, 0.9, 0.06, 1.6, 30.0, -3.0, false)
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	spray.emission_ring_axis = Vector3.UP
	spray.emission_ring_radius = 0.95
	spray.emission_ring_inner_radius = 0.8
	spray.emission_ring_height = 0.0
	add_child(spray)
	scale = Vector3(radius, 1.0, radius)


func _process(delta: float) -> void:
	_age += delta
	var fade := clampf((seconds - _age) / 0.5, 0.0, 1.0)
	scale = Vector3(radius * fade, 1.0, radius * fade)
	for k in _rings.size():
		_rings[k].rotation.y -= delta * (2.5 + k * 1.5)
		_rings[k].position.y = 0.36
	if _age >= seconds:
		queue_free()
		return
	if not owned:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.2
	if explosives == null or explosives.get("source") == null:
		return
	for enemy: Node3D in explosives.get("source").call("enemy_list"):
		if not is_instance_valid(enemy) or enemy.health.is_dead() or String(enemy.get("enemy_id")).begins_with("boss"):
			continue
		var off := Vector3(enemy.global_position.x - global_position.x, 0.0, enemy.global_position.z - global_position.z)
		if off.length() > radius:
			continue
		if float(enemy.health.hp) < float(enemy.health.max_hp) * flush_share:
			var spot := enemy.global_position + Vector3(0, 1.0, 0)
			enemy.call("on_hit", float(enemy.health.hp) + 1.0, spot, Vector3.UP)
			flushed += 1
			var numbers: Variant = explosives.get("numbers")
			if numbers != null and (numbers as Object).has_method("say"):
				numbers.call("say", spot, "FLUSHED", Color(0.6, 0.85, 1.0))
			continue
		var round_dir := Vector3(-off.z, 0.0, off.x).normalized()
		enemy.call("push", (round_dir * swirl - off.normalized() * swirl * 0.5))
