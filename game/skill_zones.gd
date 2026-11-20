# Purpose: the lingering areas of gun skills (sea step 1d): Fire Trail Dash's burning path, Plague Cloud, Time Bubble,
# Inferno Ring, Thunder Totem, Storm Call (follows the caster), the War Banner, and the pony trait Bloom's healing
# flower (game/pony_traits.gd). Up to MAX areas at once; each ticks
# a few times a second; pooled meshes, no allocation per frame.
# Dependencies: game/skill_effects.gd (`fx`: near, nearest, bolt, ring, number, follow, glow, colour_of), core/skill_state.gd.
extends Node3D

const SkillState = preload("res://core/skill_state.gd")

const MAX := 8
const NONE: Array = []

var fx: Node3D  # game/skill_effects.gd

var _kind: Array[String] = []
var _until := PackedFloat32Array()
var _next_tick := PackedFloat32Array()
var _every := PackedFloat32Array()
var _pos := PackedVector3Array()
var _end := PackedVector3Array()  # the far end of a burning path
var _radius := PackedFloat32Array()
var _amount := PackedFloat32Array()  # damage / burn per second / slow share
var _extra := PackedFloat32Array()  # slow of a cloud, targets of a totem
var _mesh: Array[MeshInstance3D] = []
var _post: Array[MeshInstance3D] = []  # the totem's and the banner's pole
var _edge: Array[MeshInstance3D] = []  # a bright ring on the ground at the area's edge (bubble, cloud, inferno, banner)
var _disc := CylinderMesh.new()
var _ball := SphereMesh.new()
var _strip := BoxMesh.new()
var _pole := CylinderMesh.new()
var _rim := TorusMesh.new()


func _ready() -> void:
	add_to_group("fire_sources")  # fire_near: Swamp Gas clouds catch from burning paths and infernos
	_disc.top_radius = 1.0
	_disc.bottom_radius = 1.0
	_disc.height = 0.04
	_disc.radial_segments = 32
	_ball.radius = 1.0
	_ball.height = 2.0
	_ball.radial_segments = 20
	_ball.rings = 10
	_strip.size = Vector3(1.0, 0.05, 1.0)
	_pole.top_radius = 0.08
	_pole.bottom_radius = 0.12
	_pole.height = 2.6
	_pole.radial_segments = 8
	_rim.inner_radius = 0.97
	_rim.outer_radius = 1.0
	_rim.rings = 48
	_rim.ring_segments = 6
	for _i in MAX:
		_kind.append("")
		_until.append(0.0)
		_next_tick.append(0.0)
		_every.append(0.5)
		_pos.append(Vector3.ZERO)
		_end.append(Vector3.ZERO)
		_radius.append(1.0)
		_amount.append(0.0)
		_extra.append(0.0)
		_mesh.append(_part())
		_post.append(_part())
		_post[-1].mesh = _pole
		_edge.append(_part())
		_edge[-1].mesh = _rim
		_mesh[-1].material_override.set("cull_mode", BaseMaterial3D.CULL_BACK)  # a camera inside a bubble or cloud sees no wash over everything


func _part() -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.material_override = fx.call("glow", Color.WHITE)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visible = false
	add_child(inst)
	return inst


# A free slot, else the one that ends first.
func _slot() -> int:
	var best := 0
	for i in MAX:
		if _until[i] <= 0.0:
			return i
		if _until[i] < _until[best]:
			best = i
	return best


# Fire Trail Dash: the path from `a` to `b` burns.
func burn_line(db: RefCounted, entry: Dictionary, base: float, a: Vector3, b: Vector3) -> void:
	var i := _open(db, entry, "burn_line", a, SkillState.value(db, entry, "seconds"), 0.5)
	_end[i] = b
	_radius[i] = SkillState.value(db, entry, "width") * 0.5
	_amount[i] = base * SkillState.value(db, entry, "burn")
	var mid := (a + b) * 0.5
	var span := Vector3(b.x - a.x, 0.0, b.z - a.z)
	_mesh[i].mesh = _strip
	_mesh[i].position = Vector3(mid.x, mid.y + 0.1, mid.z)
	_mesh[i].rotation = Vector3(0.0, atan2(span.x, span.z), 0.0)
	_mesh[i].scale = Vector3(_radius[i] * 2.0, 1.0, maxf(span.length(), 0.5))
	_show(i, db, entry, 0.45)


# The other areas: placed at `at` (the caster's feet or the crosshair, see game/skill_effects.gd cast).
func start(db: RefCounted, entry: Dictionary, base: float, at: Vector3) -> void:
	var id := String(entry["id"])
	var seconds := SkillState.value(db, entry, "seconds")
	match id:
		"plague_cloud":
			var i := _open(db, entry, "cloud", at, seconds, 0.5)
			_radius[i] = SkillState.value(db, entry, "radius")
			_amount[i] = base * SkillState.value(db, entry, "damage")
			_extra[i] = SkillState.value(db, entry, "slow") / 100.0
			_ball_at(i, at, 0.35)
			_show(i, db, entry, 0.28)
			_edge_at(i, at, db, entry, 0.7)
		"time_bubble":
			var i := _open(db, entry, "bubble", at, seconds, 0.25)
			_radius[i] = SkillState.value(db, entry, "radius")
			_amount[i] = 1.0 - SkillState.value(db, entry, "speed") / 100.0
			_ball_at(i, at, 1.0)
			_show(i, db, entry, 0.16)
			_edge_at(i, at, db, entry, 0.9)
		"inferno_ring":
			var i := _open(db, entry, "inferno", at, seconds, 0.5)
			_radius[i] = SkillState.value(db, entry, "radius")
			_amount[i] = base * SkillState.value(db, entry, "burn")
			_disc_at(i, at)
			_show(i, db, entry, 0.08)
			_edge_at(i, at, db, entry, 0.95, 8.0)  # the ring of fire itself: taller and brighter than other edges
		"thunder_totem":
			var i := _open(db, entry, "totem", at, seconds, SkillState.value(db, entry, "every"))
			_radius[i] = SkillState.value(db, entry, "radius")
			_amount[i] = base * SkillState.value(db, entry, "damage")
			_extra[i] = roundf(SkillState.value(db, entry, "targets"))
			_disc_at(i, at)
			_pole_at(i, at, db, entry)
			_show(i, db, entry, 0.12)
		"storm_call":
			var i := _open(db, entry, "storm", at, seconds, SkillState.value(db, entry, "every"))
			_radius[i] = SkillState.value(db, entry, "radius")
			_amount[i] = base * SkillState.value(db, entry, "damage")
			fx.call("ring", at, 3.0, fx.call("colour_of", db, entry))
		"war_banner":
			var i := _open(db, entry, "banner", at, seconds, 1.0)
			_radius[i] = SkillState.value(db, entry, "radius")
			_disc_at(i, at)
			_pole_at(i, at, db, entry)
			_show(i, db, entry, 0.1)
			_edge_at(i, at, db, entry, 0.8)


# (polish1 B4) A teammate's War Banner, shown only (its bonus is game/net_party.gd's): the pole, the disc and the
# ring in the banner's colour, gone after `seconds`.
func ally_banner(at: Vector3, radius: float, seconds: float, colour: Color) -> void:
	var i := _open(null, {}, "ally_banner", at, seconds, 1.0)
	_radius[i] = radius
	_disc_at(i, at)
	(_mesh[i].material_override as StandardMaterial3D).albedo_color = Color(colour, 0.1)
	_mesh[i].visible = true
	_post[i].position = at + Vector3(0, 1.3, 0)
	(_post[i].material_override as StandardMaterial3D).albedo_color = Color(colour, 0.9)
	_post[i].visible = true
	_edge[i].position = at + Vector3(0, 0.1, 0)
	_edge[i].scale = Vector3(radius, 2.0, radius)
	(_edge[i].material_override as StandardMaterial3D).albedo_color = Color(colour, 0.8)
	_edge[i].visible = true


# Bloom (pony trait): a flower at `at` that heals the caster `heal` a second while within `radius`.
func bloom(at: Vector3, radius: float, seconds: float, heal: float) -> void:
	var i := _slot()
	_kind[i] = "bloom"
	_pos[i] = at
	_until[i] = float(fx.call("now")) + seconds
	_every[i] = 0.25
	_next_tick[i] = 0.0
	_radius[i] = radius
	_amount[i] = heal
	_disc_at(i, at)
	(_mesh[i].material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.9, 0.35, 0.18)
	_mesh[i].visible = true
	_post[i].visible = false
	_edge[i].position = at + Vector3(0, 0.1, 0)
	_edge[i].scale = Vector3(radius, 2.0, radius)
	(_edge[i].material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.85, 0.3, 0.9)
	_edge[i].visible = true


func _open(_db: RefCounted, _entry: Dictionary, kind: String, at: Vector3, seconds: float, every: float) -> int:
	var i := _slot()
	_kind[i] = kind
	_pos[i] = at
	_until[i] = float(fx.call("now")) + seconds
	_every[i] = maxf(every, 0.1)
	_next_tick[i] = 0.0
	_extra[i] = 0.0
	_mesh[i].visible = false
	_post[i].visible = false
	_edge[i].visible = false
	return i


func _show(i: int, db: RefCounted, entry: Dictionary, alpha: float) -> void:
	(_mesh[i].material_override as StandardMaterial3D).albedo_color = Color(fx.call("colour_of", db, entry), alpha)
	_mesh[i].visible = true


func _disc_at(i: int, at: Vector3) -> void:
	_mesh[i].mesh = _disc
	_mesh[i].position = at + Vector3(0, 0.08, 0)
	_mesh[i].rotation = Vector3.ZERO
	_mesh[i].scale = Vector3(_radius[i], 1.0, _radius[i])


func _ball_at(i: int, at: Vector3, squash: float) -> void:
	_mesh[i].mesh = _ball
	_mesh[i].position = at + Vector3(0, _radius[i] * squash * 0.5, 0)
	_mesh[i].rotation = Vector3.ZERO
	_mesh[i].scale = Vector3(_radius[i], _radius[i] * squash, _radius[i])


# The ring at the area's edge; `tall` stretches it up (the Inferno Ring's flames).
func _edge_at(i: int, at: Vector3, db: RefCounted, entry: Dictionary, alpha: float, tall: float = 2.0) -> void:
	_edge[i].position = at + Vector3(0, 0.1, 0)
	_edge[i].scale = Vector3(_radius[i], tall, _radius[i])
	(_edge[i].material_override as StandardMaterial3D).albedo_color = Color(fx.call("colour_of", db, entry), alpha)
	_edge[i].visible = true


func _pole_at(i: int, at: Vector3, db: RefCounted, entry: Dictionary) -> void:
	_post[i].position = at + Vector3(0, 1.3, 0)
	(_post[i].material_override as StandardMaterial3D).albedo_color = Color(fx.call("colour_of", db, entry), 0.9)
	_post[i].visible = true


# Every area ends at once.
func clear() -> void:
	for i in MAX:
		_until[i] = 0.0
		_mesh[i].visible = false
		_post[i].visible = false
		_edge[i].visible = false


func near_banner(pos: Vector3) -> bool:
	var t: float = fx.call("now")
	for i in MAX:
		if _kind[i] == "banner" and _until[i] > t and Vector2(pos.x - _pos[i].x, pos.z - _pos[i].z).length() <= _radius[i]:
			return true
	return false


# How many areas are up (tools/skill_pass2_check).
func active(kind: String) -> int:
	var n := 0
	for i in MAX:
		if _until[i] > 0.0 and (kind == "" or _kind[i] == kind):
			n += 1
	return n


func _physics_process(_delta: float) -> void:
	var t: float = fx.call("now")
	for i in MAX:
		if _until[i] <= 0.0:
			continue
		if t >= _until[i]:
			_until[i] = 0.0
			_mesh[i].visible = false
			_post[i].visible = false
			_edge[i].visible = false
			continue
		if _kind[i] == "storm" and fx.get("follow") != null:
			_pos[i] = (fx.get("follow") as Node3D).global_position
		if _kind[i] == "bubble" or _kind[i] == "cloud":  # a slow breathing of the shell
			var squash := 1.0 if _kind[i] == "bubble" else 0.35
			_mesh[i].scale = Vector3(_radius[i], _radius[i] * squash, _radius[i]) * (1.0 + 0.03 * sin(t * 3.0 + float(i)))
		elif _kind[i] == "inferno":  # the flames flicker
			_edge[i].scale.y = 8.0 + 3.0 * sin(t * 13.0 + float(i)) * sin(t * 7.0)
		if t < _next_tick[i]:
			continue
		_next_tick[i] = t + _every[i]
		_tick(i, t)


func _tick(i: int, t: float) -> void:
	var at := _pos[i]
	match _kind[i]:
		"burn_line":
			for e in fx.call("near", (at + _end[i]) * 0.5, at.distance_to(_end[i]) * 0.5 + _radius[i]):
				if _off_line(e.global_position, at, _end[i]) <= _radius[i]:
					e.apply_burn(_amount[i], 2.0)
		"cloud":
			for e in fx.call("near", at, _radius[i]):
				var center: Vector3 = e.global_position + Vector3(0, e.head_height() * 0.5, 0)
				var dealt := _amount[i] * _every[i]
				e.on_hit(dealt, center, Vector3.UP)
				e.apply_slow(_extra[i], _every[i] + 0.2)
				fx.call("number", center, dealt)
		"bloom":
			var who: Node3D = fx.get("follow")
			if who != null and who.get("health") != null and Vector2(who.global_position.x - at.x, who.global_position.z - at.z).length() <= _radius[i]:
				who.get("health").heal(_amount[i] * _every[i])
		"bubble":
			for e in fx.call("near", at, _radius[i]):
				e.apply_slow(_amount[i], _every[i] + 0.15)
		"inferno":
			for e in fx.call("near", at, _radius[i]):
				e.apply_burn(_amount[i], 1.5)
		"totem":
			var top := at + Vector3(0, 2.6, 0)
			var hit: Array = []
			for _n in int(_extra[i]):
				var e = fx.call("nearest", at, _radius[i], hit)
				if e == null:
					break
				hit.append(e)
				var center: Vector3 = e.global_position + Vector3(0, e.head_height() * 0.5, 0)
				e.on_hit(_amount[i], center, Vector3.UP)
				e.apply_vulnerable(1.1, 1.0)
				fx.call("bolt", top, center, (_post[i].material_override as StandardMaterial3D).albedo_color)
				fx.call("number", center, _amount[i])
		"storm":
			var list: Array = fx.call("near", at, _radius[i])
			if list.is_empty():
				return
			var e = list[int(t * 1000.0) % list.size()]  # a different one most strikes, no random state needed
			var center: Vector3 = e.global_position + Vector3(0, e.head_height() * 0.5, 0)
			e.on_hit(_amount[i], center, Vector3.UP)
			fx.call("bolt", center + Vector3(0.6, 14.0, -0.4), center, Color(0.8, 0.9, 1.0))
			fx.call("ring", e.global_position, 1.2, Color(0.8, 0.9, 1.0))
			fx.call("number", center, _amount[i])


# Flat distance from `p` to the segment a-b.
func _off_line(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var k := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * k).length()


# True when a burning path or an inferno is alight within `reach` of `point` (game/swamp_gas.gd asks).
func fire_near(point: Vector3, reach: float) -> bool:
	for i in _until.size():
		if _until[i] <= 0.0:
			continue
		if _kind[i] == "inferno" and Vector2(point.x - _pos[i].x, point.z - _pos[i].z).length() <= _radius[i] + reach:
			return true
		if _kind[i] == "burn_line" and _off_line(point, _pos[i], _end[i]) <= _radius[i] + reach:
			return true
	return false
