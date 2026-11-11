# Purpose: the world effects of gun skills (Nova Burst, Chain Lightning, Gravity Well, Frost Pulse, Swarm Drones, and the Rally Cry ring): damage, knockback, pulls, freezes plus pooled visuals (rings, bolts, wells, drones). No allocation per frame.
# Dependencies: core/skill_state.gd (rolled numbers), game/explosives.gd (blast), game/damage_numbers.gd (optional), enemies from source.enemy_list() (game/wave_director.gd) with on_hit / push / apply_freeze / apply_vulnerable / apply_slow (game/enemy.gd).
extends Node3D

const SkillState = preload("res://core/skill_state.gd")

const RING_POOL := 4
const BOLT_POOL := 16
const WELL_MAX := 2
const DRONE_MAX := 4
const RING_TIME := 0.45
const BOLT_TIME := 0.18
const TARGET_RANGE := 40.0
const NONE: Array = []

var source  # has enemy_list()
var explosives  # Explosives (blast), or null
var numbers  # DamageNumbers or null
var follow: Node3D  # the drones orbit this (the player)

var _rings: Array[MeshInstance3D] = []
var _ring_age := PackedFloat32Array()
var _ring_max := PackedFloat32Array()
var _next_ring := 0
var _bolts: Array[MeshInstance3D] = []
var _bolt_age := PackedFloat32Array()
var _next_bolt := 0
var _wells: Array[MeshInstance3D] = []
var _well_until := PackedFloat32Array()  # engine time the well ends; 0 = free slot
var _well_pos := PackedVector3Array()
var _well_radius := PackedFloat32Array()
var _well_pull := PackedFloat32Array()
var _well_damage := PackedFloat32Array()
var _drones: Array[MeshInstance3D] = []
var _drone_timer := PackedFloat32Array()
var _drone_count := 0
var _drone_until := 0.0
var _drone_damage := 0.0
var _drone_interval := 0.5
var _drone_range := 25.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for _i in RING_POOL:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 0.06
		cyl.radial_segments = 24
		cyl.rings = 1
		_rings.append(_glow_mesh(cyl))
		_ring_age.append(RING_TIME)
		_ring_max.append(1.0)
	for _i in BOLT_POOL:
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 1.0)
		_bolts.append(_glow_mesh(box))
		_bolt_age.append(BOLT_TIME)
	for _i in WELL_MAX:
		var ball := SphereMesh.new()
		ball.radius = 0.5
		ball.height = 1.0
		ball.radial_segments = 12
		ball.rings = 6
		var well := _glow_mesh(ball)
		(well.material_override as StandardMaterial3D).albedo_color = Color(0.45, 0.15, 0.8, 0.8)
		_wells.append(well)
		_well_until.append(0.0)
		_well_pos.append(Vector3.ZERO)
		_well_radius.append(1.0)
		_well_pull.append(0.0)
		_well_damage.append(0.0)
	for _i in DRONE_MAX:
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 0.12, 0.28)
		var drone := _glow_mesh(box)
		(drone.material_override as StandardMaterial3D).albedo_color = Color(0.5, 1.0, 0.9, 1.0)
		_drones.append(drone)
		_drone_timer.append(0.0)


func _glow_mesh(mesh: Mesh) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visible = false
	add_child(inst)
	return inst


# Fires the skill `entry` ({"id", "q"}). base_damage = the held gun's damage; feet = the caster's position; eye/forward = camera; aim_point = where the crosshair meets the world.
func cast(db: RefCounted, entry: Dictionary, base_damage: float, feet: Vector3, eye: Vector3, forward: Vector3, aim_point: Vector3) -> void:
	match String(entry["id"]):
		"nova_burst":
			_nova(db, entry, base_damage, feet)
		"chain_lightning":
			_chain(db, entry, base_damage, eye, forward)
		"gravity_well":
			_start_well(db, entry, base_damage, aim_point)
		"frost_pulse":
			_frost(db, entry, feet)
		"swarm_drones":
			_start_drones(db, entry, base_damage)
		"rally_cry":
			_ring(feet, 4.0, Color(1.0, 0.85, 0.3))


func active_wells() -> int:
	var n := 0
	for u in _well_until:
		if u > 0.0:
			n += 1
	return n


func drone_count() -> int:
	return _drone_count


func _nova(db: RefCounted, entry: Dictionary, base: float, origin: Vector3) -> void:
	var radius := SkillState.value(db, entry, "radius")
	var dmg := base * SkillState.value(db, entry, "damage")
	var knock := SkillState.value(db, entry, "knock")
	_ring(origin, radius, Color(1.0, 0.6, 0.2))
	for e in _near(origin, radius):
		var center: Vector3 = e.global_position + Vector3(0, e.head_height() * 0.5, 0)
		var away: Vector3 = e.global_position - origin
		e.on_hit(dmg, center, Vector3.UP)
		e.push(Vector3(away.x, 0.0, away.z).normalized() * knock)
		_number(center, dmg)


func _chain(db: RefCounted, entry: Dictionary, base: float, origin: Vector3, forward: Vector3) -> void:
	var cur = _pick_target(origin, forward)
	if cur == null:
		return
	var jumps := roundi(SkillState.value(db, entry, "jumps"))
	var dmg := base * SkillState.value(db, entry, "damage")
	var keep := SkillState.value(db, entry, "keep")
	var reach := SkillState.value(db, entry, "jump_range")
	var vuln := 1.0 + SkillState.value(db, entry, "vuln") / 100.0
	var hit: Array = []
	var from := origin + forward * 0.5 + Vector3(0, -0.15, 0)
	for _n in jumps + 1:
		var center: Vector3 = cur.global_position + Vector3(0, cur.head_height() * 0.5, 0)
		_bolt(from, center, Color(0.7, 0.85, 1.0))
		cur.on_hit(dmg, center, Vector3.UP)
		cur.apply_vulnerable(vuln, 4.0)
		_number(center, dmg)
		hit.append(cur)
		dmg *= keep
		from = center
		cur = _nearest(center, reach, hit)
		if cur == null:
			break


func _frost(db: RefCounted, entry: Dictionary, origin: Vector3) -> void:
	var radius := SkillState.value(db, entry, "radius")
	var seconds := SkillState.value(db, entry, "seconds")
	var vuln := 1.0 + SkillState.value(db, entry, "vuln") / 100.0
	var boss_slow := SkillState.value(db, entry, "boss_slow")
	_ring(origin, radius, Color(0.5, 0.85, 1.0))
	for e in _near(origin, radius):
		if String(e.enemy_id).begins_with("boss"):
			e.apply_slow(boss_slow, seconds)
		else:
			e.apply_freeze(seconds)
		e.apply_vulnerable(vuln, seconds)


func _start_well(db: RefCounted, entry: Dictionary, base: float, point: Vector3) -> void:
	var slot := 0
	for i in WELL_MAX:  # a free slot, else the one that ends first
		if _well_until[i] <= 0.0:
			slot = i
			break
		if _well_until[i] < _well_until[slot]:
			slot = i
	_well_until[slot] = _now() + SkillState.value(db, entry, "seconds")
	_well_pos[slot] = point
	_well_radius[slot] = SkillState.value(db, entry, "radius")
	_well_pull[slot] = SkillState.value(db, entry, "pull")
	_well_damage[slot] = base * SkillState.value(db, entry, "damage")
	_wells[slot].position = point + Vector3(0, 1.0, 0)
	_wells[slot].visible = true


func _start_drones(db: RefCounted, entry: Dictionary, base: float) -> void:
	_drone_count = clampi(roundi(SkillState.value(db, entry, "drones")), 1, DRONE_MAX)
	_drone_until = _now() + SkillState.value(db, entry, "seconds")
	_drone_damage = base * SkillState.value(db, entry, "damage")
	_drone_interval = 1.0 / maxf(SkillState.value(db, entry, "shots_per_second"), 0.1)
	_drone_range = SkillState.value(db, entry, "range")
	for i in DRONE_MAX:
		_drones[i].visible = i < _drone_count
		_drone_timer[i] = randf() * _drone_interval


func _physics_process(delta: float) -> void:
	var now := _now()
	for i in WELL_MAX:
		if _well_until[i] <= 0.0:
			continue
		var pos := _well_pos[i]
		if now >= _well_until[i]:
			_well_until[i] = 0.0
			_wells[i].visible = false
			_ring(pos, _well_radius[i], Color(0.7, 0.3, 1.0))
			if explosives != null:
				explosives.blast(pos, _well_radius[i], _well_damage[i])
			continue
		for e in _near(pos, _well_radius[i]):
			var toward: Vector3 = pos - e.global_position
			toward.y = 0.0
			if toward.length() > 1.0:
				e.push(toward.normalized() * _well_pull[i])
		var pulse := 1.0 + 0.15 * sin(now * 8.0)
		_wells[i].scale = Vector3.ONE * pulse * (0.8 + _well_radius[i] * 0.1)
	if _drone_count > 0:
		_step_drones(delta, now)


func _step_drones(delta: float, now: float) -> void:
	if now >= _drone_until or follow == null:
		_drone_count = 0
		for d in _drones:
			d.visible = false
		return
	var center := follow.global_position
	for i in _drone_count:
		var angle := now * 1.6 + float(i) * TAU / float(_drone_count)
		var pos := center + Vector3(cos(angle) * 1.6, 2.4 + 0.2 * sin(now * 3.0 + float(i)), sin(angle) * 1.6)
		_drones[i].global_position = pos
		_drone_timer[i] -= delta
		if _drone_timer[i] > 0.0:
			continue
		_drone_timer[i] = _drone_interval
		var target = _nearest(pos, _drone_range, NONE)
		if target == null:
			continue
		var spot: Vector3 = target.global_position + Vector3(0, target.head_height() * 0.5, 0)
		target.on_hit(_drone_damage, spot, Vector3.UP)
		_bolt(pos, spot, Color(0.5, 1.0, 0.9))


func _process(delta: float) -> void:
	for i in RING_POOL:
		if _ring_age[i] >= RING_TIME:
			continue
		_ring_age[i] += delta
		var k := clampf(_ring_age[i] / RING_TIME, 0.0, 1.0)
		var ring := _rings[i]
		ring.scale = Vector3(_ring_max[i] * k, 1.0, _ring_max[i] * k)
		var mat := ring.material_override as StandardMaterial3D
		mat.albedo_color = Color(mat.albedo_color, 0.45 * (1.0 - k))
		if k >= 1.0:
			ring.visible = false
	for i in BOLT_POOL:
		if _bolt_age[i] >= BOLT_TIME:
			continue
		_bolt_age[i] += delta
		if _bolt_age[i] >= BOLT_TIME:
			_bolts[i].visible = false


func _ring(at: Vector3, radius: float, color: Color) -> void:
	var i := _next_ring
	_next_ring = (_next_ring + 1) % RING_POOL
	_ring_age[i] = 0.0
	_ring_max[i] = maxf(radius, 0.5)
	_rings[i].position = at + Vector3(0, 0.15, 0)
	_rings[i].scale = Vector3(0.01, 1.0, 0.01)
	(_rings[i].material_override as StandardMaterial3D).albedo_color = Color(color, 0.45)
	_rings[i].visible = true


func _bolt(a: Vector3, b: Vector3, color: Color) -> void:
	var i := _next_bolt
	_next_bolt = (_next_bolt + 1) % BOLT_POOL
	_bolt_age[i] = 0.0
	var span := a.distance_to(b)
	if span < 0.05:
		return
	var bolt := _bolts[i]
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT
	bolt.visible = true
	bolt.look_at_from_position((a + b) * 0.5, b, up)
	bolt.scale = Vector3(1.0, 1.0, span)
	(bolt.material_override as StandardMaterial3D).albedo_color = Color(color, 0.9)


# Enemies within `radius` of `point` (a fresh array: fine for a skill cast, not for per-frame use outside wells).
func _near(point: Vector3, radius: float) -> Array:
	var out: Array = []
	if source == null:
		return out
	for e in source.enemy_list():
		if is_instance_valid(e) and not e.health.is_dead() and e.global_position.distance_to(point) <= radius:
			out.append(e)
	return out


# The closest living enemy within `radius` of `point` that is not in `skip`, or null.
func _nearest(point: Vector3, radius: float, skip: Array):
	var best = null
	var best_d := radius
	if source == null:
		return null
	for e in source.enemy_list():
		if not is_instance_valid(e) or e.health.is_dead() or skip.has(e):
			continue
		var d: float = e.global_position.distance_to(point)
		if d <= best_d:
			best_d = d
			best = e
	return best


# The enemy closest to the crosshair line (within 40 m), else the nearest one within 12 m.
func _pick_target(origin: Vector3, forward: Vector3):
	var best = null
	var best_dot := 0.9
	if source == null:
		return null
	for e in source.enemy_list():
		if not is_instance_valid(e) or e.health.is_dead():
			continue
		var to: Vector3 = e.global_position + Vector3(0, 1.0, 0) - origin
		var dist := to.length()
		if dist > TARGET_RANGE or dist < 0.1:
			continue
		var dot := forward.dot(to / dist)
		if dot > best_dot:
			best_dot = dot
			best = e
	return best if best != null else _nearest(origin, 12.0, NONE)


func _number(at: Vector3, amount: float) -> void:
	if numbers != null:
		numbers.spawn(at, amount)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
