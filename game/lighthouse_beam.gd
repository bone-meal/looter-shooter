# Purpose: LIGHTHOUSE IN A BOTTLE's beam (diary/DESIGN_UNIQUES.md, region 7 chase gun): a long beam of light sweeps
# round whoever holds the gun. The holder's own beam sets the enemies it passes burning; another player's copy on THIS
# machine heals this machine's player when it passes over him (so every teammate is healed by his own copy; the holder
# is not healed by his own). A child of the gimmick with top_level, so it goes when the gun goes.
# Dependencies: the enemy source (`explosives`), the local player (health) for copies.
extends Node3D

const GROUP := "lighthouse_beams"
const HEIGHT := 1.3

var owned := true
var explosives: Node3D
var damage_per_second := 10.0
var burn_seconds := 3.0
var heal_share := 0.04
var reach := 12.0
var sweep_seconds := 3.0
var half_angle := 0.18  # radians either side of the beam that count as "passed"
var local_player: Node3D

var _anchor: Node3D
var _beam: MeshInstance3D
var _last := {}  # node -> engine time it was last touched
var burned := 0
var healed := 0


func _ready() -> void:
	top_level = true
	add_to_group(GROUP)
	_anchor = get_parent() as Node3D
	_beam = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.5, 1.0)
	_beam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.55, 0.48, 0.2)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.scale = Vector3(1.0, 1.0, reach)
	_beam.position = Vector3(0, 0, -reach * 0.5)
	add_child(_beam)
	if local_player == null:
		var link: Node = get_tree().get_first_node_in_group("net_chase")
		if link != null and link.get("net") != null:
			local_player = link.get("net").call("local_player")


func angle() -> float:
	return fmod(Time.get_ticks_msec() / 1000.0 / sweep_seconds, 1.0) * TAU


func _process(_delta: float) -> void:
	var shown := _anchor != null and is_instance_valid(_anchor) and _anchor.is_visible_in_tree()
	visible = shown
	if not shown:
		return
	var center := _anchor.global_position
	global_position = Vector3(center.x, center.y + 0.2, center.z)
	rotation = Vector3(0.0, angle(), 0.0)
	var now := Time.get_ticks_msec() / 1000.0
	if owned:
		var source: Variant = explosives.get("source") if explosives != null else null
		if source == null:
			return
		for enemy: Node3D in source.call("enemy_list"):
			if is_instance_valid(enemy) and not enemy.health.is_dead() and _passes(enemy.global_position) and now - float(_last.get(enemy, -9.0)) > 1.0:
				_last[enemy] = now
				enemy.call("apply_burn", damage_per_second, burn_seconds)
				burned += 1
	elif local_player != null and is_instance_valid(local_player) and _passes(local_player.global_position) and now - float(_last.get(local_player, -9.0)) > sweep_seconds * 0.8:
		_last[local_player] = now
		var health: Variant = local_player.get("health")
		if health != null:
			health.call("heal", float(health.get("max_hp")) * heal_share)
			healed += 1


# Is `point` under the beam now?
func passes(point: Vector3) -> bool:
	return _passes(point)


func _passes(point: Vector3) -> bool:
	var off := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if off.length() > reach or off.length() < 0.5:
		return false
	var beam_dir := -global_transform.basis.z
	return absf(Vector2(beam_dir.x, beam_dir.z).angle_to(Vector2(off.x, off.z))) <= half_angle
