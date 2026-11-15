# Purpose: FLUSH's whirlpool (diary/DESIGN_UNIQUES.md, region 7 chase gun): opened where a grenade lands, it swirls
# for `seconds`: every 0.2 s each living, non-boss enemy inside `radius` is pushed round and in; one below flush_share
# of its health is FLUSHED (killed, "FLUSHED"). The shooter's own whirlpool does that; another player's copy
# (game/net_chase.gd "whirl") only shows. Drawn as a dark disc and two turning rings that shrink away at the end.
# Dependencies: game/explosives.gd (enemy source, damage numbers).
extends Node3D

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
var _rings: Array[MeshInstance3D] = []
var flushed := 0


static func can_open(tree: SceneTree) -> bool:
	return tree.get_nodes_in_group(GROUP).size() < MAX_OPEN


func _ready() -> void:
	add_to_group(GROUP)
	var disc := MeshInstance3D.new()
	var flat := CylinderMesh.new()
	flat.top_radius = 1.0
	flat.bottom_radius = 1.0
	flat.height = 0.02
	flat.radial_segments = 24
	disc.mesh = flat
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.05, 0.18, 0.3, 0.75)
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = dark
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_rings.append(disc)
	for k in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.85 - k * 0.35
		torus.outer_radius = 1.0 - k * 0.35
		torus.rings = 24
		torus.ring_segments = 6
		ring.mesh = torus
		var foam := StandardMaterial3D.new()
		foam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		foam.albedo_color = Color(0.7, 0.9, 1.0)
		ring.material_override = foam
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_rings.append(ring)
	scale = Vector3(radius, 1.0, radius)


func _process(delta: float) -> void:
	_age += delta
	var fade := clampf((seconds - _age) / 0.5, 0.0, 1.0)
	scale = Vector3(radius * fade, 1.0, radius * fade)
	for k in _rings.size():
		_rings[k].rotation.y += delta * (2.0 + k * 1.5)
		_rings[k].position.y = 0.03 + k * 0.02
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
