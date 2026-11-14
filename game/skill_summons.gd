# Purpose: the helpers gun skills call up (sea step 1d): Decoy Hologram (enemies near it chase it instead, then it
# bursts), Mirror Clone (a see-through copy beside the caster that shoots), Sentry Turret (stands where dropped and
# shoots) and Spinning Blades (circle the caster and cut what they touch). One of each at a time; pooled meshes.
# Dependencies: game/skill_effects.gd (`fx`: near, nearest, burst, bolt, number, follow, glow, colour_of),
# core/skill_state.gd, enemies' set_target / current_target (game/enemy.gd).
extends Node3D

const SkillState = preload("res://core/skill_state.gd")

const BLADE_MAX := 4
const BLADE_HIT_EVERY := 0.4  # one enemy is cut at most this often by the blades
const BLADE_REACH := 1.1
const DECOY_RESCAN := 1.0
const NONE: Array = []


# What the decoy is to an enemy: something to walk to and hit (the blows do nothing).
class DecoyBody extends Node3D:
	var struck_by: Variant = null

	func take_damage(_amount: float, _element: String = "physical") -> void:
		pass


var fx: Node3D  # game/skill_effects.gd

var _decoy := DecoyBody.new()
var _decoy_mesh: MeshInstance3D
var _decoy_until := 0.0
var _decoy_rescan := 0.0
var _decoy_reach := 15.0
var _decoy_radius := 5.0
var _decoy_damage := 0.0
var _lured: Array = []  # [enemy, its own target before]
var _clone_mesh: MeshInstance3D
var _clone_until := 0.0
var _turret_mesh: MeshInstance3D
var _turret_until := 0.0
var _shooter_next := PackedFloat32Array([0.0, 0.0])  # clone, turret
var _shooter_every := PackedFloat32Array([0.25, 0.33])
var _shooter_damage := PackedFloat32Array([0.0, 0.0])
var _shooter_range := PackedFloat32Array([30.0, 25.0])
var _shooter_colour: Array[Color] = [Color.WHITE, Color.WHITE]
var _blades: Array[MeshInstance3D] = []
var _blade_count := 0
var _blade_until := 0.0
var _blade_damage := 0.0
var _blade_orbit := 2.5
var _blade_next := {}  # enemy -> engine time it can be cut again (cleared when the blades end)


func _ready() -> void:
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.8
	body.radial_segments = 12
	body.rings = 4
	add_child(_decoy)
	_decoy_mesh = _part(body)
	_clone_mesh = _part(body)
	var turret := BoxMesh.new()
	turret.size = Vector3(0.6, 0.9, 0.6)
	_turret_mesh = _part(turret)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.7, 0.05, 0.16)
	for _i in BLADE_MAX:
		_blades.append(_part(blade))


func _part(mesh: Mesh) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = fx.call("glow", Color.WHITE)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visible = false
	add_child(inst)
	return inst


func decoy(db: RefCounted, entry: Dictionary, base: float, at: Vector3) -> void:
	_release()
	var t: float = fx.call("now")
	_decoy.global_position = at
	_decoy_until = t + SkillState.value(db, entry, "seconds")
	_decoy_reach = SkillState.value(db, entry, "reach")
	_decoy_radius = SkillState.value(db, entry, "radius")
	_decoy_damage = base * SkillState.value(db, entry, "damage")
	_decoy_mesh.position = at + Vector3(0, 0.9, 0)
	(_decoy_mesh.material_override as StandardMaterial3D).albedo_color = Color(fx.call("colour_of", db, entry), 0.45)
	_decoy_mesh.visible = true
	_decoy_rescan = 0.0


func start(db: RefCounted, entry: Dictionary, base: float, feet: Vector3) -> void:
	var t: float = fx.call("now")
	var colour: Color = fx.call("colour_of", db, entry)
	match String(entry["id"]):
		"mirror_clone":
			_clone_until = t + SkillState.value(db, entry, "seconds")
			_shooter(0, db, entry, base, colour)
			(_clone_mesh.material_override as StandardMaterial3D).albedo_color = Color(colour, 0.4)
			_clone_mesh.visible = true
		"sentry_turret":
			_turret_until = t + SkillState.value(db, entry, "seconds")
			_shooter(1, db, entry, base, colour)
			var side := Vector3(1.6, 0.0, 0.0)
			var follow: Node3D = fx.get("follow")
			if follow != null and follow.has_method("aim_flat"):
				side = (follow.call("aim_flat") as Vector3).cross(Vector3.UP) * 1.6  # to the caster's right
			_turret_mesh.position = feet + side + Vector3(0, 0.45, 0)
			(_turret_mesh.material_override as StandardMaterial3D).albedo_color = Color(colour, 0.85)
			_turret_mesh.visible = true
		"spinning_blades":
			_blade_count = clampi(roundi(SkillState.value(db, entry, "blades")), 1, BLADE_MAX)
			_blade_until = t + SkillState.value(db, entry, "seconds")
			_blade_damage = base * SkillState.value(db, entry, "damage")
			_blade_orbit = SkillState.value(db, entry, "orbit")
			_blade_next.clear()
			for i in BLADE_MAX:
				_blades[i].visible = i < _blade_count
				(_blades[i].material_override as StandardMaterial3D).albedo_color = Color(colour, 0.9)


func _shooter(k: int, db: RefCounted, entry: Dictionary, base: float, colour: Color) -> void:
	_shooter_every[k] = 1.0 / maxf(SkillState.value(db, entry, "shots_per_second"), 0.5)
	_shooter_damage[k] = base * SkillState.value(db, entry, "damage") / 100.0
	_shooter_range[k] = SkillState.value(db, entry, "range")
	_shooter_colour[k] = colour
	_shooter_next[k] = 0.0


# Every helper goes at once (the decoy without its burst; whoever it drew goes back to its own target).
func clear() -> void:
	_release()
	_decoy_until = 0.0
	_decoy_mesh.visible = false
	_clone_until = 0.0
	_clone_mesh.visible = false
	_turret_until = 0.0
	_turret_mesh.visible = false
	_blade_until = 0.0
	_blade_count = 0
	for b in _blades:
		b.visible = false
	_blade_next.clear()


# What is up (tools/skill_pass2_check): "decoy", "clone", "turret", "blades"; and how many enemies chase the decoy.
func active(kind: String) -> bool:
	var t: float = fx.call("now")
	match kind:
		"decoy":
			return t < _decoy_until
		"clone":
			return t < _clone_until
		"turret":
			return t < _turret_until
		"blades":
			return t < _blade_until
	return false


func lured() -> int:
	return _lured.size()


func _physics_process(_delta: float) -> void:
	var t: float = fx.call("now")
	var follow: Node3D = fx.get("follow")
	_step_decoy(t)
	if _clone_mesh.visible:
		if t >= _clone_until or follow == null:
			_clone_mesh.visible = false
		else:
			_clone_mesh.global_position = follow.global_position + Vector3(1.3 * cos(t * 0.4), 0.9, 1.3 * sin(t * 0.4))
			_shoot(0, _clone_mesh.global_position + Vector3(0, 0.5, 0), t)
	if _turret_mesh.visible:
		if t >= _turret_until:
			_turret_mesh.visible = false
		else:
			_shoot(1, _turret_mesh.global_position + Vector3(0, 0.35, 0), t)
	if _blade_count > 0:
		_step_blades(t, follow)


func _shoot(k: int, from: Vector3, t: float) -> void:
	if t < _shooter_next[k]:
		return
	_shooter_next[k] = t + _shooter_every[k]
	var e = fx.call("nearest", from, _shooter_range[k], NONE)
	if e == null:
		return
	var spot: Vector3 = e.global_position + Vector3(0, e.head_height() * 0.5, 0)
	e.on_hit(_shooter_damage[k], spot, Vector3.UP)
	fx.call("bolt", from, spot, _shooter_colour[k])
	fx.call("number", spot, _shooter_damage[k])


func _step_decoy(t: float) -> void:
	if not _decoy_mesh.visible:
		return
	if t >= _decoy_until:
		_decoy_mesh.visible = false
		fx.call("burst", _decoy.global_position, _decoy_radius, _decoy_damage, (_decoy_mesh.material_override as StandardMaterial3D).albedo_color)
		_release()
		return
	_decoy_mesh.rotation.y = t * 2.0
	if t < _decoy_rescan:
		return
	_decoy_rescan = t + DECOY_RESCAN
	for e in fx.call("near", _decoy.global_position, _decoy_reach):
		if String(e.get("enemy_id")).begins_with("boss") or not e.has_method("set_target"):
			continue  # bosses are not fooled
		var before: Variant = e.call("current_target") if e.has_method("current_target") else null
		if before == _decoy:
			continue
		_lured.append([e, before])
		e.set_target(_decoy)


# Everyone the decoy drew goes back to what it chased before.
func _release() -> void:
	for pair: Array in _lured:
		var e = pair[0]
		if is_instance_valid(e) and e.has_method("current_target") and e.call("current_target") == _decoy and is_instance_valid(pair[1]):
			e.set_target(pair[1])
	_lured.clear()


func _step_blades(t: float, follow: Node3D) -> void:
	if t >= _blade_until or follow == null:
		_blade_count = 0
		for b in _blades:
			b.visible = false
		_blade_next.clear()
		return
	var center := follow.global_position + Vector3(0, 1.1, 0)
	var close: Array = fx.call("near", follow.global_position, _blade_orbit + BLADE_REACH)  # one look a tick for all blades
	for i in _blade_count:
		var angle := t * 4.0 + TAU * float(i) / float(_blade_count)
		var pos := center + Vector3(cos(angle) * _blade_orbit, 0.0, sin(angle) * _blade_orbit)
		_blades[i].global_position = pos
		_blades[i].rotation = Vector3(0.0, -angle, 0.0)
		for e in close:
			if Vector2(e.global_position.x - pos.x, e.global_position.z - pos.z).length() > BLADE_REACH or t < float(_blade_next.get(e, 0.0)):
				continue
			_blade_next[e] = t + BLADE_HIT_EVERY
			var spot: Vector3 = e.global_position + Vector3(0, e.head_height() * 0.5, 0)
			e.on_hit(_blade_damage, spot, Vector3.UP)
			fx.call("number", spot, _blade_damage)
