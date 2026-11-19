# Purpose: what another player's gunfire looks and sounds like here (sea step 12b): a muzzle flash at his gun, a
# tracer to where each pellet ended, the gun's sound from his body, and harmless copies of his slow shots (rockets and
# grenades fly and burst with a flash and a bang; harpoons, bolts and flares fly as their own models and lie a moment).
# Nothing here does damage. Pools: 32 tracers, 8 flashes, 8 slow shots; one shared material each (no per-shot allocation).
# Dependencies: game/net_fire.gd (queues), game/remote_player.gd muzzle_point(), the session's sounds, explosives
# (show_flash) and shot bolts (their models) found through group "game_session".
extends Node3D

const TRACERS := 32
const FLASHES := 8
const SLOW := 8
const TRACER_LIFE := 0.07
const FLASH_LIFE := 0.05
const SLOW_LIFE := 6.0
const LIE := 3.0  # s a landed harpoon / bolt / flare copy stays

var shown := 0  # dev / checks: shots and slow shots shown here
var slow_shown := 0
var _queue: Array = []  # [due, kind ("shot" | "slow"), body, ...]
var _tracers: Array[MeshInstance3D] = []
var _tracer_t := PackedFloat32Array()
var _flashes: Array[MeshInstance3D] = []
var _flash_t := PackedFloat32Array()
var _slow: Array = []  # {"node", "vel", "grav", "life", "kind", "radius", "lie"}
var _tracer_mat := StandardMaterial3D.new()
var _flash_mat := StandardMaterial3D.new()
var _rocket_mesh := BoxMesh.new()
var _grenade_mesh := SphereMesh.new()
var _query := PhysicsRayQueryParameters3D.new()
var _session: Node = null


func _ready() -> void:
	top_level = true
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_mat.albedo_color = Color(1.0, 0.82, 0.45)
	_tracer_mat.disable_fog = true
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1.0, 0.7, 0.3)
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.disable_fog = true
	var line := BoxMesh.new()
	line.size = Vector3(0.025, 0.025, 1.0)
	for i in TRACERS:
		var m := MeshInstance3D.new()
		m.mesh = line
		m.material_override = _tracer_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_tracers.append(m)
		_tracer_t.append(0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	for i in FLASHES:
		var f := MeshInstance3D.new()
		f.mesh = quad
		f.material_override = _flash_mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		add_child(f)
		_flashes.append(f)
		_flash_t.append(0.0)
	_rocket_mesh.size = Vector3(0.12, 0.12, 0.5)
	_grenade_mesh.radius = 0.07
	_grenade_mesh.height = 0.14
	_grenade_mesh.radial_segments = 8
	_grenade_mesh.rings = 4
	_query.collision_mask = 1


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _part(name_of: String) -> Variant:
	if _session == null or not is_instance_valid(_session):
		_session = get_tree().get_first_node_in_group("game_session")
	return _session.get(name_of) if _session != null else null


func queue_shot(t: float, body: Node3D, sound: String, ends: PackedVector3Array) -> void:
	_queue.append([_now() + t, "shot", body, sound, ends])


func queue_projectile(t: float, body: Node3D, kind: String, from: Vector3, vel: Vector3, grav: float, radius: float) -> void:
	_queue.append([_now() + t, "slow", body, kind, from, vel, grav, radius])


func _muzzle(body: Node3D) -> Vector3:
	if body.has_method("muzzle_point"):
		return body.call("muzzle_point")
	return body.global_position + Vector3(0.0, 1.4, 0.0)


func _process(delta: float) -> void:
	var now := _now()
	var i := 0
	while i < _queue.size():
		var q: Array = _queue[i]
		if float(q[0]) > now:
			i += 1
			continue
		_queue.remove_at(i)
		var body: Node3D = q[2]
		if not is_instance_valid(body):
			continue
		if String(q[1]) == "shot":
			_show_shot(body, String(q[3]), q[4])
		else:
			_show_slow(body, String(q[3]), q[4], q[5], float(q[6]), float(q[7]))
	for t in TRACERS:
		if _tracer_t[t] > 0.0:
			_tracer_t[t] -= delta
			if _tracer_t[t] <= 0.0:
				_tracers[t].visible = false
	for f in FLASHES:
		if _flash_t[f] > 0.0:
			_flash_t[f] -= delta
			if _flash_t[f] <= 0.0:
				_flashes[f].visible = false
	_step_slow(delta)


func _show_shot(body: Node3D, sound: String, ends: PackedVector3Array) -> void:
	var from := _muzzle(body)
	shown += 1
	var sounds: Variant = _part("_sounds")
	if sounds != null and sound != "":
		(sounds as Node).call("play", sound, from)
	_flash_at(from)
	for e: Vector3 in ends:
		var t := _free_tracer()
		var m := _tracers[t]
		var length := from.distance_to(e)
		if length < 0.3:
			continue
		var up := Vector3.UP if absf((e - from).normalized().y) < 0.99 else Vector3.FORWARD
		m.look_at_from_position((from + e) * 0.5, e, up)
		m.scale = Vector3(1.0, 1.0, length)
		m.visible = true
		_tracer_t[t] = TRACER_LIFE


func _free_tracer() -> int:
	var best := 0
	for t in TRACERS:
		if _tracer_t[t] <= 0.0:
			return t
		if _tracer_t[t] < _tracer_t[best]:
			best = t
	return best


func _flash_at(at: Vector3) -> void:
	for f in FLASHES:
		if _flash_t[f] <= 0.0:
			_flashes[f].global_position = at
			_flashes[f].visible = true
			_flash_t[f] = FLASH_LIFE
			return


func _show_slow(body: Node3D, kind: String, from: Vector3, vel: Vector3, grav: float, radius: float) -> void:
	slow_shown += 1
	_flash_at(_muzzle(body))
	if _slow.size() >= SLOW:
		var old: Dictionary = _slow.pop_front()
		(old["node"] as Node).queue_free()
	var node: Node3D
	if kind == "rocket" or kind == "grenade":
		var m := MeshInstance3D.new()
		if kind == "rocket":
			m.mesh = _rocket_mesh
		else:
			m.mesh = _grenade_mesh
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node = m
	else:
		var bolts: Variant = _part("_bolts")
		node = (bolts as Node).call("_look", kind) if bolts != null else Node3D.new()
	add_child(node)
	node.global_position = from
	if vel.length() > 0.01:
		node.look_at(from + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.FORWARD)
	_slow.append({"node": node, "vel": vel, "grav": grav, "life": SLOW_LIFE, "kind": kind, "radius": radius, "lie": -1.0})


func _step_slow(delta: float) -> void:
	var i := 0
	while i < _slow.size():
		var s: Dictionary = _slow[i]
		var node: Node3D = s["node"]
		if float(s["lie"]) >= 0.0:  # landed: lies a moment
			s["lie"] = float(s["lie"]) - delta
			if float(s["lie"]) < 0.0:
				node.queue_free()
				_slow.remove_at(i)
				continue
			i += 1
			continue
		s["life"] = float(s["life"]) - delta
		var vel: Vector3 = s["vel"]
		vel.y -= float(s["grav"]) * delta
		s["vel"] = vel
		var from := node.global_position
		var to := from + vel * delta
		_query.from = from
		_query.to = to
		var hit := get_world_3d().direct_space_state.intersect_ray(_query)
		if not hit.is_empty() or float(s["life"]) <= 0.0:
			var at: Vector3 = hit.position if not hit.is_empty() else to
			if String(s["kind"]) == "rocket" or String(s["kind"]) == "grenade":
				var sounds: Variant = _part("_sounds")
				if sounds != null:
					(sounds as Node).call("play", "explosion", at)
				var boom: Variant = _part("_explosives")
				if boom != null:
					(boom as Node).call("show_flash", at, maxf(float(s["radius"]), 1.0))
				node.queue_free()
				_slow.remove_at(i)
				continue
			node.global_position = at
			s["lie"] = LIE
			i += 1
			continue
		node.global_position = to
		if vel.length() > 0.01:
			node.look_at(to + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.FORWARD)
		i += 1


func status() -> String:
	return "fire copies: shots %d, slow %d, flying %d, queued %d" % [shown, slow_shown, _slow.size(), _queue.size()]
