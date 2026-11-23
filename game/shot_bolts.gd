# Purpose: the non-exploding projectiles of the sea step 2 guns, pooled and stepped on the physics tick: HARPOON (pins
# what it hits and reels small enemies to the shooter), FLARE (arcs, sets fire round where it lands and burns on there
# as a light: lights dark places, counts as fire for Swamp Gas) and BOLT (drops over distance, lies where it lands and
# goes back into the crossbow's pool when the shooter walks over it). Damage itself is the shooter's: an enemy hit is
# handed to shooter.projectile_hit(collider, point, normal, stats) (game/player.gd), like one hitscan pellet.
# Dependencies: game/fx_kit.gd (glow); `source` has enemy_list() (game/wave_director.gd). Numbers: data/weapons.json
# "projectile" blocks of harpoon_gun, flare_gun and crossbow.
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")

const POOL := 10
const LIFETIME := 4.0
const LYING := 12  # bolts lying about at most (the oldest goes)
const FLARES := 3  # burning flares on the ground at most
const PICKUP := 1.3

var ignore: RID  # the shooter's body
var source  # has enemy_list()

var _shots: Array[Dictionary] = []  # {node, vel, grav, life, stats, shooter}
var _lying: Array[Dictionary] = []  # {node, until, shooter}
var _flares: Array[Dictionary] = []  # {node, light, until, burn_at, stats}
var _query := PhysicsRayQueryParameters3D.new()
var _meshes := {}


func _ready() -> void:
	add_to_group("fire_sources")  # fire_near: a burning flare sets Swamp Gas off
	_query.collision_mask = 3  # world + enemies
	for i in POOL:
		var node := Node3D.new()
		node.visible = false
		add_child(node)
		_shots.append({"node": node, "life": 0.0})


# Fires one projectile of `stats["kind"]` (harpoon / flare / bolt). Silently dropped when the pool is full.
func fire(origin: Vector3, direction: Vector3, stats: Dictionary, shooter: Node3D) -> void:
	for shot: Dictionary in _shots:
		if float(shot["life"]) > 0.0:
			continue
		var node: Node3D = shot["node"]
		for child in node.get_children():
			child.queue_free()
		node.add_child(_look(String(stats["kind"])))
		node.position = origin
		node.look_at(origin + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
		node.visible = true
		shot["vel"] = direction * float(stats["speed"])
		shot["grav"] = float(stats["gravity"])
		shot["life"] = LIFETIME
		shot["stats"] = stats
		shot["shooter"] = shooter
		return


func active_count() -> int:
	return _shots.filter(func(s: Dictionary) -> bool: return float(s["life"]) > 0.0).size()


func lying_count() -> int:
	return _lying.size()


func flare_count() -> int:
	return _flares.size()


func _physics_process(delta: float) -> void:
	_query.exclude = [ignore]
	var space := get_world_3d().direct_space_state
	for shot: Dictionary in _shots:
		if float(shot["life"]) <= 0.0:
			continue
		var node: Node3D = shot["node"]
		var vel: Vector3 = shot["vel"]
		vel.y -= float(shot["grav"]) * delta
		shot["vel"] = vel
		_query.from = node.position
		_query.to = node.position + vel * delta
		var hit := space.intersect_ray(_query)
		if hit.is_empty():
			node.position += vel * delta
			if vel.length() > 0.1:
				node.look_at(node.position + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.FORWARD)
			shot["life"] = float(shot["life"]) - delta
			if float(shot["life"]) <= 0.0:
				node.visible = false
			continue
		shot["life"] = 0.0
		node.visible = false
		_land(shot, hit.position, hit.normal, hit.collider, vel)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_lying.size() - 1, -1, -1):  # bolts: picked up by walking over them, or gone after a while
		var bolt: Dictionary = _lying[i]
		var shooter := bolt["shooter"] as Node3D
		var node := bolt["node"] as Node3D
		if is_instance_valid(shooter) and shooter.global_position.distance_to(node.global_position) <= PICKUP and shooter.has_method("bolt_picked") and bool(shooter.call("bolt_picked")):
			node.queue_free()
			_lying.remove_at(i)
		elif now >= float(bolt["until"]):
			node.queue_free()
			_lying.remove_at(i)
	for i in range(_flares.size() - 1, -1, -1):  # flares: burn what comes near, flicker, go out
		var flare: Dictionary = _flares[i]
		var light := flare["light"] as OmniLight3D
		var left := float(flare["until"]) - now
		if left <= 0.0:
			(flare["node"] as Node3D).queue_free()
			_flares.remove_at(i)
			continue
		light.light_energy = (1.6 + 0.4 * sin(now * 23.0) + 0.25 * sin(now * 7.0)) * clampf(left / 2.0, 0.0, 1.0)
		if now >= float(flare["burn_at"]):
			flare["burn_at"] = now + 0.5
			_ignite((flare["node"] as Node3D).global_position, 1.0, flare["stats"])


# True while a flare burns within `reach` of `point` (game/swamp_gas.gd asks every fire source).
func fire_near(point: Vector3, reach: float) -> bool:
	for flare: Dictionary in _flares:
		if point.distance_to((flare["node"] as Node3D).global_position) <= reach + 1.0:
			return true
	return false


func _land(shot: Dictionary, point: Vector3, normal: Vector3, collider: Object, vel: Vector3) -> void:
	var stats: Dictionary = shot["stats"]
	var shooter := shot["shooter"] as Node3D
	var enemy := collider != null and collider.has_method("on_hit")
	if enemy and is_instance_valid(shooter) and shooter.has_method("projectile_hit"):
		shooter.call("projectile_hit", collider, point, normal, stats)
	match String(stats["kind"]):
		"harpoon":
			if enemy:
				(collider as Node).set_meta("harpooned_at", Time.get_ticks_msec() / 1000.0)  # a shark killed soon after is ours to harvest (game/sea_sharks.gd)
				if collider.has_method("apply_slow"):
					collider.call("apply_slow", 0.8, float(stats["pin_seconds"]))  # pinned (the strongest slow there is)
				var small: bool = not String(collider.get("enemy_id")).begins_with("boss") and collider.get("health") != null and float(collider.get("health").max_hp) <= float(stats["pull_max_health"])
				if small and is_instance_valid(shooter) and collider.has_method("push"):
					var toward := (shooter.global_position - (collider as Node3D).global_position) * Vector3(1, 0, 1)
					collider.call("push", toward.normalized() * float(stats["pull_speed"]))
			else:
				_lie(_look("harpoon"), point, vel, null, 6.0)  # stuck in the wall for a moment
		"flare":
			_ignite(point, float(stats["ignite_radius"]), stats)
			_burn_flare(point + normal * 0.05, stats)
		"bolt":
			var at := point
			if enemy:  # it drops at the enemy's feet
				_query.from = point
				_query.to = point + Vector3.DOWN * 6.0
				_query.collision_mask = 1
				var floor_hit := get_world_3d().direct_space_state.intersect_ray(_query)
				_query.collision_mask = 3
				at = floor_hit.position if not floor_hit.is_empty() else point
				vel = Vector3(vel.x, -vel.length() * 0.2, vel.z)
			_lie(_look("bolt_lying"), at, vel, shooter, float(stats["lie_seconds"]), 0.06)  # (polish1 item 147) a bigger bolt with glowing flights, barely buried: easy to spot and pick up


func _lie(look: Node3D, point: Vector3, vel: Vector3, shooter: Node3D, seconds: float, buried: float = 0.15) -> void:
	while _lying.size() >= LYING:
		(_lying[0]["node"] as Node3D).queue_free()
		_lying.remove_at(0)
	var node := Node3D.new()
	node.add_child(look)
	add_child(node)
	node.position = point - vel.normalized() * buried  # partly in whatever it hit
	if vel.length() > 0.1:
		node.look_at(node.position + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.FORWARD)
	_lying.append({"node": node, "until": Time.get_ticks_msec() / 1000.0 + seconds, "shooter": shooter if shooter != null else null})


func _burn_flare(point: Vector3, stats: Dictionary) -> void:
	while _flares.size() >= FLARES:
		(_flares[0]["node"] as Node3D).queue_free()
		_flares.remove_at(0)
	var node := Node3D.new()
	add_child(node)
	node.position = point
	node.add_child(_look("flare"))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.22)
	light.omni_range = float(stats["light_range"])
	light.shadow_enabled = false
	light.position.y = 0.3
	node.add_child(light)
	_flares.append({"node": node, "light": light, "until": Time.get_ticks_msec() / 1000.0 + float(stats["light_seconds"]), "burn_at": 0.0, "stats": stats})


func _ignite(point: Vector3, radius: float, stats: Dictionary) -> void:
	if source == null:
		return
	for enemy: Node3D in source.enemy_list():
		if is_instance_valid(enemy) and enemy.global_position.distance_to(point) <= radius + 0.5 and enemy.has_method("apply_burn"):
			enemy.call("apply_burn", float(stats["burn_dps"]), float(stats["burn_seconds"]))


# What a projectile looks like (pointing down -Z), made once per kind and shared.
func _look(kind: String) -> Node3D:
	var root := Node3D.new()
	if not _meshes.has(kind):
		_meshes[kind] = _make(kind)
	for part: Array in _meshes[kind]:
		var piece := MeshInstance3D.new()
		piece.mesh = part[0]
		piece.material_override = part[1]
		piece.transform = part[2]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(piece)
	return root


func _make(kind: String) -> Array:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.57, 0.6)
	steel.metallic = 0.6
	steel.roughness = 0.4
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.26, 0.13)
	var flight := StandardMaterial3D.new()
	flight.albedo_color = Color(0.85, 0.2, 0.15)
	flight.cull_mode = BaseMaterial3D.CULL_DISABLED
	var along := Basis(Vector3.RIGHT, -PI / 2.0)  # cylinders stand on Y: lay them along -Z
	match kind:
		"harpoon":
			return [[_rod(0.012, 0.9), steel, Transform3D(along, Vector3(0, 0, 0.1))],
				[_cone(0.035, 0.12), steel, Transform3D(along, Vector3(0, 0, -0.41))],
				[_box(Vector3(0.09, 0.008, 0.05)), steel, Transform3D(Basis(), Vector3(0, 0, -0.33))]]
		"bolt":
			return [[_rod(0.006, 0.42), wood, Transform3D(along, Vector3.ZERO)],
				[_cone(0.012, 0.05), steel, Transform3D(along, Vector3(0, 0, -0.235))],
				[_box(Vector3(0.002, 0.03, 0.07)), flight, Transform3D(Basis(), Vector3(0, 0.012, 0.17))],
				[_box(Vector3(0.03, 0.002, 0.07)), flight, Transform3D(Basis(), Vector3(0, 0, 0.17))]]
		"bolt_lying":  # (polish1 item 147) on the ground to be picked up: 1.6x, flights glowing, a glow at the tail
			var k := 1.6
			var tip := SphereMesh.new()
			tip.radius = 0.035
			tip.height = 0.07
			tip.radial_segments = 8
			tip.rings = 4
			return [[_rod(0.006 * k, 0.42 * k), wood, Transform3D(along, Vector3.ZERO)],
				[_cone(0.012 * k, 0.05 * k), steel, Transform3D(along, Vector3(0, 0, -0.235 * k))],
				[_box(Vector3(0.003, 0.03 * k, 0.07 * k)), FxKit.glow(Color(1.0, 0.45, 0.2), true), Transform3D(Basis(), Vector3(0, 0.012 * k, 0.17 * k))],
				[_box(Vector3(0.03 * k, 0.003, 0.07 * k)), FxKit.glow(Color(1.0, 0.45, 0.2), true), Transform3D(Basis(), Vector3(0, 0, 0.17 * k))],
				[tip, FxKit.glow(Color(1.0, 0.6, 0.3), true), Transform3D(Basis(), Vector3(0, 0, 0.21 * k))]]
		"flare":
			var ball := SphereMesh.new()
			ball.radius = 0.05
			ball.height = 0.1
			ball.radial_segments = 10
			ball.rings = 5
			return [[ball, FxKit.glow(Color(1.0, 0.45, 0.3), true), Transform3D()],
				[_rod(0.02, 0.08), flight, Transform3D(along, Vector3(0, 0, 0.06))]]
	return []


func _rod(radius: float, length: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = length
	m.radial_segments = 8
	m.rings = 1
	return m


func _cone(radius: float, length: float) -> CylinderMesh:
	var m := _rod(radius, length)
	m.top_radius = 0.0  # the point at +Y = -Z once laid along
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
