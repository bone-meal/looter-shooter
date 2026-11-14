# Purpose: the blasts and missiles of gun skills (sea step 1d): Orbital Strike (marked spot, beam after a delay),
# Meteor Shower (falling rocks over a few seconds), Rocket Barrage (one homing rocket per enemy), Sticky Mines (burst
# when an enemy comes near), Ice Lance (pierces a line, freezes) and Harpoon Yank (drags one enemy in, stuns it).
# Pooled meshes, fixed caps, no allocation per frame.
# Dependencies: game/skill_effects.gd (`fx`: near, nearest, pick_target, burst, bolt, ring, number, glow, colour_of),
# core/skill_state.gd.
extends Node3D

const SkillState = preload("res://core/skill_state.gd")

const ORBITAL_MAX := 2
const METEOR_MAX := 10
const ROCKET_MAX := 14
const MINE_MAX := 5
const FALL_TIME := 0.6  # a meteor is seen falling this long before it lands
const FALL_HEIGHT := 22.0
const BEAM_TIME := 0.35
const ARM_TIME := 0.5
const LANCE_TIME := 0.25
const NONE: Array = []

var fx: Node3D  # game/skill_effects.gd

# orbital strikes: marker on the ground until the beam
var _orb_at := PackedFloat32Array()  # engine time the beam lands (0 = free); after it, the beam shows until +BEAM_TIME
var _orb_pos := PackedVector3Array()
var _orb_radius := PackedFloat32Array()
var _orb_damage := PackedFloat32Array()
var _orb_mark: Array[MeshInstance3D] = []
var _orb_beam: Array[MeshInstance3D] = []
# meteors
var _met_at := PackedFloat32Array()  # landing time (0 = free)
var _met_pos := PackedVector3Array()
var _met_radius := 3.0
var _met_damage := 0.0
var _met_mesh: Array[MeshInstance3D] = []
# rockets
var _rk_start := PackedFloat32Array()
var _rk_time := PackedFloat32Array()  # flight time (0 = free)
var _rk_from := PackedVector3Array()
var _rk_to := PackedVector3Array()  # the last known spot of its target
var _rk_target: Array = []
var _rk_mesh: Array[MeshInstance3D] = []
var _rk_radius := 2.5
var _rk_damage := 0.0
var _rk_colour := Color.WHITE
# mines
var _mine_until := PackedFloat32Array()  # 0 = free
var _mine_armed := PackedFloat32Array()
var _mine_pos := PackedVector3Array()
var _mine_mesh: Array[MeshInstance3D] = []
var _mine_radius := 4.0
var _mine_trigger := 2.5
var _mine_damage := 0.0
var _mine_colour := Color.WHITE
# the ice lance's shaft
var _lance: MeshInstance3D
var _lance_until := 0.0
# a harpooned enemy is stunned a moment after the pull (a frozen enemy would not slide)
var _stun_target: Variant = null
var _stun_at := 0.0
var _stun_seconds := 0.0


func _ready() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.05
	disc.radial_segments = 32
	var beam := CylinderMesh.new()
	beam.top_radius = 1.0
	beam.bottom_radius = 1.0
	beam.height = 40.0
	beam.radial_segments = 16
	var rock := SphereMesh.new()
	rock.radius = 0.55
	rock.height = 1.1
	rock.radial_segments = 10
	rock.rings = 5
	var rocket := BoxMesh.new()
	rocket.size = Vector3(0.12, 0.12, 0.6)
	var mine := CylinderMesh.new()
	mine.top_radius = 0.22
	mine.bottom_radius = 0.28
	mine.height = 0.12
	mine.radial_segments = 10
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.18, 0.18, 1.0)
	for _i in ORBITAL_MAX:
		_orb_at.append(0.0)
		_orb_pos.append(Vector3.ZERO)
		_orb_radius.append(1.0)
		_orb_damage.append(0.0)
		_orb_mark.append(_part(disc))
		_orb_beam.append(_part(beam))
	for _i in METEOR_MAX:
		_met_at.append(0.0)
		_met_pos.append(Vector3.ZERO)
		_met_mesh.append(_part(rock))
		(_met_mesh[-1].material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.45, 0.15, 0.95)
	for _i in ROCKET_MAX:
		_rk_start.append(0.0)
		_rk_time.append(0.0)
		_rk_from.append(Vector3.ZERO)
		_rk_to.append(Vector3.ZERO)
		_rk_target.append(null)
		_rk_mesh.append(_part(rocket))
	for _i in MINE_MAX:
		_mine_until.append(0.0)
		_mine_armed.append(0.0)
		_mine_pos.append(Vector3.ZERO)
		_mine_mesh.append(_part(mine))
	_lance = _part(shaft)


func _part(mesh: Mesh) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = fx.call("glow", Color.WHITE)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visible = false
	add_child(inst)
	return inst


func start(db: RefCounted, entry: Dictionary, base: float, eye: Vector3, aim: Vector3) -> void:
	var t: float = fx.call("now")
	var colour: Color = fx.call("colour_of", db, entry)
	match String(entry["id"]):
		"orbital_strike":
			var i := 0
			for k in ORBITAL_MAX:
				if _orb_at[k] <= 0.0:
					i = k
					break
			_orb_at[i] = t + SkillState.value(db, entry, "delay")
			_orb_pos[i] = aim
			_orb_radius[i] = SkillState.value(db, entry, "radius")
			_orb_damage[i] = base * SkillState.value(db, entry, "damage")
			_orb_mark[i].position = aim + Vector3(0, 0.1, 0)
			_orb_mark[i].scale = Vector3(_orb_radius[i], 1.0, _orb_radius[i])
			(_orb_mark[i].material_override as StandardMaterial3D).albedo_color = Color(colour, 0.35)
			(_orb_beam[i].material_override as StandardMaterial3D).albedo_color = Color(colour, 0.7)
			_orb_mark[i].visible = true
		"meteor_shower":
			var count := mini(roundi(SkillState.value(db, entry, "meteors")), METEOR_MAX)
			var area := SkillState.value(db, entry, "area") * 0.5
			var span := SkillState.value(db, entry, "seconds")
			_met_radius = SkillState.value(db, entry, "radius")
			_met_damage = base * SkillState.value(db, entry, "damage")
			for k in count:
				var angle := float(k) * 2.39996  # golden-angle spiral: spread evenly, no random state
				var r := area * sqrt((float(k) + 0.5) / float(count))
				_met_pos[k] = aim + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
				_met_at[k] = t + FALL_TIME + span * float(k) / float(maxi(count - 1, 1))
			fx.call("ring", aim, area, Color(colour, 0.6))
		"rocket_barrage":
			var count := mini(roundi(SkillState.value(db, entry, "rockets")), ROCKET_MAX)
			var reach := SkillState.value(db, entry, "range")
			_rk_radius = SkillState.value(db, entry, "radius")
			_rk_damage = base * SkillState.value(db, entry, "damage")
			_rk_colour = colour
			var targets: Array = fx.call("near", eye, reach)
			if targets.is_empty():
				return
			for k in count:
				var e = targets[k % targets.size()]  # one each, then round again
				_rk_target[k] = e
				_rk_from[k] = eye + Vector3(0, -0.3, 0)
				_rk_to[k] = e.global_position + Vector3(0, e.head_height() * 0.5, 0)
				_rk_start[k] = t + 0.05 * float(k)
				_rk_time[k] = 0.45 + 0.04 * float(k)
				(_rk_mesh[k].material_override as StandardMaterial3D).albedo_color = Color(colour, 0.95)
		"sticky_mines":
			var count := mini(roundi(SkillState.value(db, entry, "mines")), MINE_MAX)
			var seconds := SkillState.value(db, entry, "seconds")
			_mine_radius = SkillState.value(db, entry, "radius")
			_mine_trigger = SkillState.value(db, entry, "trigger")
			_mine_damage = base * SkillState.value(db, entry, "damage")
			_mine_colour = colour
			for k in count:
				var angle := TAU * float(k) / float(count)
				_mine_pos[k] = aim + (Vector3(cos(angle), 0.0, sin(angle)) * 2.2 if count > 1 else Vector3.ZERO)
				_mine_until[k] = t + seconds
				_mine_armed[k] = t + ARM_TIME
				_mine_mesh[k].position = _mine_pos[k] + Vector3(0, 0.08, 0)
				(_mine_mesh[k].material_override as StandardMaterial3D).albedo_color = Color(colour, 0.9)
				_mine_mesh[k].visible = true


# Ice Lance: every enemy within `width` of the line ahead.
func lance(db: RefCounted, entry: Dictionary, base: float, eye: Vector3, forward: Vector3) -> void:
	var length := SkillState.value(db, entry, "length")
	var width := SkillState.value(db, entry, "width")
	var dmg := base * SkillState.value(db, entry, "damage")
	var freeze := SkillState.value(db, entry, "freeze")
	var from := eye + forward * 0.6 + Vector3(0, -0.2, 0)
	for e in fx.call("near", eye, length + 1.0):
		var center: Vector3 = e.global_position + Vector3(0, e.head_height() * 0.5, 0)
		var along := (center - from).dot(forward)
		if along < 0.0 or along > length:
			continue
		if (from + forward * along).distance_to(center) > width + 0.4:
			continue
		e.on_hit(dmg, center, Vector3.UP)
		e.apply_freeze(freeze)
		fx.call("number", center, dmg)
	_lance.look_at_from_position(from + forward * length * 0.5, from + forward * length, Vector3.UP if absf(forward.y) < 0.99 else Vector3.RIGHT)
	_lance.scale = Vector3(1.0, 1.0, length)
	(_lance.material_override as StandardMaterial3D).albedo_color = Color(fx.call("colour_of", db, entry), 0.8)
	_lance.visible = true
	_lance_until = float(fx.call("now")) + LANCE_TIME


# Harpoon Yank: the aimed enemy is hit, dragged toward `feet`, then stunned.
func harpoon(db: RefCounted, entry: Dictionary, base: float, eye: Vector3, forward: Vector3, feet: Vector3) -> void:
	var e = fx.call("pick_target", eye, forward)
	if e == null or e.global_position.distance_to(eye) > SkillState.value(db, entry, "range"):
		return
	var center: Vector3 = e.global_position + Vector3(0, e.head_height() * 0.5, 0)
	var dmg := base * SkillState.value(db, entry, "damage")
	e.on_hit(dmg, center, Vector3.UP)
	var back: Vector3 = (feet - e.global_position) * Vector3(1, 0, 1)
	if back.length() > 1.5:
		e.push(back.normalized() * SkillState.value(db, entry, "pull"))
	fx.call("bolt", eye + forward * 0.5 + Vector3(0, -0.2, 0), center, fx.call("colour_of", db, entry))
	fx.call("number", center, dmg)
	_stun_target = e
	_stun_at = float(fx.call("now")) + 0.45
	_stun_seconds = SkillState.value(db, entry, "stun")


# Everything pending stops at once (nothing lands).
func clear() -> void:
	for i in ORBITAL_MAX:
		_orb_at[i] = 0.0
		_orb_mark[i].visible = false
		_orb_beam[i].visible = false
	for i in METEOR_MAX:
		_met_at[i] = 0.0
		_met_mesh[i].visible = false
	for i in ROCKET_MAX:
		_rk_time[i] = 0.0
		_rk_target[i] = null
		_rk_mesh[i].visible = false
	for i in MINE_MAX:
		_mine_until[i] = 0.0
		_mine_mesh[i].visible = false
	_lance.visible = false
	_stun_target = null


# How many of each are running (tools/skill_pass2_check).
func pending(kind: String) -> int:
	var n := 0
	match kind:
		"orbital":
			for v in _orb_at:
				n += 1 if v > 0.0 else 0
		"meteor":
			for v in _met_at:
				n += 1 if v > 0.0 else 0
		"rocket":
			for v in _rk_time:
				n += 1 if v > 0.0 else 0
		"mine":
			for v in _mine_until:
				n += 1 if v > 0.0 else 0
	return n


func _physics_process(_delta: float) -> void:
	var t: float = fx.call("now")
	_step_orbitals(t)
	_step_meteors(t)
	_step_rockets(t)
	_step_mines(t)
	if _lance.visible and t >= _lance_until:
		_lance.visible = false
	if _stun_target != null and t >= _stun_at:
		if is_instance_valid(_stun_target) and not _stun_target.health.is_dead():
			_stun_target.apply_freeze(_stun_seconds)
		_stun_target = null


func _step_orbitals(t: float) -> void:
	for i in ORBITAL_MAX:
		if _orb_at[i] <= 0.0:
			continue
		if t < _orb_at[i]:
			var k := 1.0 - clampf((_orb_at[i] - t) / 2.0, 0.0, 1.0)  # the mark tightens as the beam comes
			_orb_mark[i].scale = Vector3(_orb_radius[i] * (1.0 - 0.3 * k), 1.0, _orb_radius[i] * (1.0 - 0.3 * k))
			continue
		if not _orb_beam[i].visible:  # the moment it lands
			_orb_beam[i].position = _orb_pos[i] + Vector3(0, 20.0, 0)
			_orb_beam[i].scale = Vector3(_orb_radius[i] * 0.6, 1.0, _orb_radius[i] * 0.6)
			_orb_beam[i].visible = true
			_orb_mark[i].visible = false
			fx.call("burst", _orb_pos[i], _orb_radius[i], _orb_damage[i], (_orb_beam[i].material_override as StandardMaterial3D).albedo_color)
		var fade := (t - _orb_at[i]) / BEAM_TIME
		_orb_beam[i].scale = Vector3(_orb_radius[i] * 0.6 * (1.0 - fade), 1.0, _orb_radius[i] * 0.6 * (1.0 - fade))
		if fade >= 1.0:
			_orb_beam[i].visible = false
			_orb_at[i] = 0.0


func _step_meteors(t: float) -> void:
	for i in METEOR_MAX:
		if _met_at[i] <= 0.0:
			continue
		var left := _met_at[i] - t
		if left > FALL_TIME:
			continue
		if left > 0.0:
			_met_mesh[i].visible = true
			_met_mesh[i].position = _met_pos[i] + Vector3(left * 6.0, FALL_HEIGHT * left / FALL_TIME + 0.5, left * 3.0)
			continue
		_met_mesh[i].visible = false
		_met_at[i] = 0.0
		fx.call("burst", _met_pos[i], _met_radius, _met_damage, Color(1.0, 0.5, 0.2))


func _step_rockets(t: float) -> void:
	for i in ROCKET_MAX:
		if _rk_time[i] <= 0.0 or t < _rk_start[i]:
			continue
		var e = _rk_target[i]
		if e != null and is_instance_valid(e) and not e.health.is_dead():
			_rk_to[i] = e.global_position + Vector3(0, e.head_height() * 0.5, 0)  # it homes
		var k := clampf((t - _rk_start[i]) / _rk_time[i], 0.0, 1.0)
		var pos := _rk_from[i].lerp(_rk_to[i], k) + Vector3(0, sin(k * PI) * 3.0, 0)
		if k >= 1.0:
			_rk_mesh[i].visible = false
			_rk_time[i] = 0.0
			_rk_target[i] = null
			fx.call("burst", _rk_to[i], _rk_radius, _rk_damage, _rk_colour)
			continue
		var ahead := _rk_from[i].lerp(_rk_to[i], minf(k + 0.05, 1.0)) + Vector3(0, sin(minf(k + 0.05, 1.0) * PI) * 3.0, 0)
		_rk_mesh[i].visible = true
		if pos.distance_squared_to(ahead) > 0.0001:
			_rk_mesh[i].look_at_from_position(pos, ahead, Vector3.UP)
		else:
			_rk_mesh[i].position = pos


func _step_mines(t: float) -> void:
	for i in MINE_MAX:
		if _mine_until[i] <= 0.0:
			continue
		if t >= _mine_until[i]:
			_mine_until[i] = 0.0
			_mine_mesh[i].visible = false
			continue
		if t < _mine_armed[i]:
			continue
		var blink := 0.6 + 0.4 * sin(t * 10.0 + float(i))
		(_mine_mesh[i].material_override as StandardMaterial3D).albedo_color = Color(_mine_colour, blink)
		if fx.call("nearest", _mine_pos[i], _mine_trigger, NONE) != null:
			_mine_until[i] = 0.0
			_mine_mesh[i].visible = false
			fx.call("burst", _mine_pos[i], _mine_radius, _mine_damage, _mine_colour)
