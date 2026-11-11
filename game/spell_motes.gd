# Purpose: the small flying bits that tell one spell from another at a glance. Every substance (water, fire, ice,
# lightning ...) has its own shape, its own way of moving and a second colour it fades into (data/fantasy/spells.json
# "look" on each substance and secret): water is falling drops, fire is rising tongues, earth is tumbling rocks, air is
# thin crescents, ice is straight shards, lightning is flickering zigzags, nature is fluttering leaves, and so on.
# game/spell_effects.gd asks for them along jets, behind bolts, at impacts and inside lingering pools.
# Dependencies: none. One MultiMesh per shape with a fixed number of places, reused in turn: nothing is allocated while
# spells fly, and a shape costs one draw call however many of its bits are in the air.
extends Node3D

const PER_SHAPE := 220
# shape -> [gravity m/s2 (+ rises), drag per second, stretch along its flight, growth over its life (x), spin rad/s, glows (additive), how solid it is drawn 0..1]
# (a flame is the exception to "along its flight": it always stands upright, like a tongue of fire)
const RULES := {
	"drop": [-15.0, 0.4, 2.2, 0.7, 0.0, false, 0.9],
	"flame": [4.0, 1.4, 1.6, 0.25, 0.0, true, 0.9],
	"rock": [-24.0, 0.2, 1.0, 1.0, 7.0, false, 1.0],
	"gust": [0.0, 1.6, 3.4, 1.8, 0.0, false, 0.6],
	"puff": [1.4, 1.8, 1.0, 2.8, 0.0, false, 0.42],
	"shard": [-2.0, 0.1, 2.6, 1.0, 0.0, true, 0.95],
	"leaf": [-2.5, 1.2, 1.0, 1.0, 9.0, false, 1.0],
	"spark": [0.0, 3.0, 2.0, 0.6, 0.0, true, 1.0],
	"grain": [-5.0, 0.8, 1.0, 0.8, 4.0, false, 0.9],
	"prism": [0.0, 0.5, 1.8, 1.0, 6.0, true, 0.9],
	"blob": [-18.0, 0.3, 1.2, 0.8, 0.0, true, 0.95],
}

var share := 1.0  # graphics tier: the share of bits that are really thrown
var _pools := {}  # shape -> Pool


# The places of one shape. An object (not a dictionary) so its arrays are written in place, never copied.
class Pool:
	var multi: MultiMesh
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var left := PackedFloat32Array()  # seconds each bit still lives (0 = free)
	var life := PackedFloat32Array()
	var size := PackedFloat32Array()
	var color := PackedColorArray()
	var tail := PackedColorArray()
	var next := 0
	var live := 0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	for shape: String in RULES:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _mesh(shape, bool(RULES[shape][5]))
		multi.instance_count = PER_SHAPE
		for i in PER_SHAPE:
			multi.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
		var drawn := MultiMeshInstance3D.new()
		drawn.multimesh = multi
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drawn.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))  # bits fly anywhere: never culled as a group
		add_child(drawn)
		var pool := Pool.new()
		pool.multi = multi
		pool.pos.resize(PER_SHAPE)
		pool.vel.resize(PER_SHAPE)
		pool.left.resize(PER_SHAPE)
		pool.life.resize(PER_SHAPE)
		pool.size.resize(PER_SHAPE)
		pool.color.resize(PER_SHAPE)
		pool.tail.resize(PER_SHAPE)
		_pools[shape] = pool


# One bit of a spell's look at a point, flying at `velocity`. `size` in metres; it fades from `color` to the look's second colour.
func emit(look: Dictionary, at: Vector3, velocity: Vector3, life: float, size: float, color: Color) -> void:
	if share < 1.0 and randf() > share:
		return
	var pool: Pool = _pools.get(String(look.get("shape", "puff")), _pools["puff"])
	var i := pool.next
	pool.next = (i + 1) % PER_SHAPE
	pool.live += 1
	pool.pos[i] = at
	pool.vel[i] = velocity
	pool.left[i] = life
	pool.life[i] = life
	pool.size[i] = size * float(look.get("size", 1.0))
	pool.color[i] = Color(color.r, color.g, color.b, color.a * float(RULES.get(String(look.get("shape", "puff")), RULES["puff"])[6]))
	if look.has("second"):
		var second: Array = look["second"]
		pool.tail[i] = Color(second[0], second[1], second[2], 0.0)
	else:
		pool.tail[i] = Color(color.r, color.g, color.b, 0.0)


# Many bits thrown out from a point in every direction (an impact). `up` lifts them (a fountain) when above 0.
func burst(look: Dictionary, at: Vector3, count: int, speed: float, life: float, size: float, color: Color, up: float = 0.3) -> void:
	for n in count:
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 1.0) + up, randf_range(-1.0, 1.0)).normalized()
		emit(look, at + dir * 0.2, dir * speed * randf_range(0.5, 1.0), life * randf_range(0.6, 1.0), size * randf_range(0.7, 1.2), color)


func clear() -> void:
	for shape: String in _pools:
		var pool: Pool = _pools[shape]
		pool.left.fill(0.0)
		pool.live = 0
		for i in PER_SHAPE:
			pool.multi.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))


func _process(delta: float) -> void:
	var clock := Time.get_ticks_msec() / 1000.0
	for shape: String in _pools:
		var pool: Pool = _pools[shape]
		if pool.live <= 0:
			continue
		var rule: Array = RULES[shape]
		var multi := pool.multi
		var gravity := float(rule[0])
		var drag := maxf(1.0 - float(rule[1]) * delta, 0.0)
		var stretch := float(rule[2])
		var growth := float(rule[3])
		var spin := float(rule[4])
		var live := 0
		for i in PER_SHAPE:
			if pool.left[i] <= 0.0:
				continue
			pool.left[i] -= delta
			if pool.left[i] <= 0.0:
				multi.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), pool.pos[i]))
				continue
			live += 1
			var v := pool.vel[i] * drag + Vector3(0.0, gravity * delta, 0.0)
			if shape == "spark":  # lightning never flies straight
				v += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 40.0 * delta
			elif shape == "leaf":
				v.x += sin(clock * 9.0 + float(i)) * 6.0 * delta
			pool.vel[i] = v
			pool.pos[i] += v * delta
			var age := 1.0 - pool.left[i] / pool.life[i]
			var grow := pool.size[i] * lerpf(1.0, growth, age)
			var basis := Basis.IDENTITY
			if stretch != 1.0 and shape != "flame" and v.length_squared() > 0.01:
				var along := v.normalized()
				var side := along.cross(Vector3.UP)
				side = side.normalized() if side.length_squared() > 0.001 else Vector3.RIGHT
				basis = Basis(side, along, side.cross(along))  # the mesh's long axis (y) points where it flies
			if spin != 0.0:
				basis = basis * Basis(Vector3(0.6, 0.5, 0.62).normalized(), clock * spin + float(i))
			multi.set_instance_transform(i, Transform3D(basis.scaled_local(Vector3(grow, grow * stretch, grow)), pool.pos[i]))
			var shade := pool.color[i].lerp(pool.tail[i], age * age)
			if shape == "prism":  # the rainbow turns through every colour
				shade = Color.from_hsv(fmod(age * 1.5 + float(i) * 0.13, 1.0), 0.75, 1.0, 1.0 - age * age)
			multi.set_instance_color(i, shade)
		pool.live = live


# --- the shapes (built once) ---

func _mesh(shape: String, glows: bool) -> Mesh:
	var mesh: Mesh
	match shape:
		"drop":
			var drop := SphereMesh.new()
			drop.radius = 0.5
			drop.height = 1.0
			drop.radial_segments = 6
			drop.rings = 3
			mesh = drop
		"flame":
			mesh = _cone(0.5, 1.0, 5)
		"rock":
			var rock := SphereMesh.new()
			rock.radius = 0.5
			rock.height = 0.8
			rock.radial_segments = 5
			rock.rings = 2
			mesh = rock
		"gust":
			mesh = _strip([Vector3(-0.5, 0.0, 0.0), Vector3(-0.3, 0.35, 0.0), Vector3(0.0, 0.5, 0.0), Vector3(0.3, 0.35, 0.0), Vector3(0.5, 0.0, 0.0)], 0.07)
		"puff":
			var puff := SphereMesh.new()
			puff.radius = 0.5
			puff.height = 1.0
			puff.radial_segments = 8
			puff.rings = 4
			mesh = puff
		"shard":
			var shard := SphereMesh.new()  # two rings and four sides: a long diamond
			shard.radius = 0.22
			shard.height = 1.0
			shard.radial_segments = 4
			shard.rings = 1
			mesh = shard
		"leaf":
			mesh = _strip([Vector3(0.0, -0.5, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.5, 0.0)], 0.3, true)
		"spark":
			mesh = _strip([Vector3(0.0, -0.5, 0.0), Vector3(0.22, -0.2, 0.0), Vector3(-0.18, 0.05, 0.0), Vector3(0.15, 0.3, 0.0), Vector3(0.0, 0.5, 0.0)], 0.06)
		"grain":
			var grain := BoxMesh.new()
			grain.size = Vector3(0.5, 0.5, 0.5)
			mesh = grain
		"prism":
			mesh = _cone(0.35, 1.0, 3, 0.35)
		_:
			var blob := SphereMesh.new()
			blob.radius = 0.5
			blob.height = 0.9
			blob.radial_segments = 7
			blob.rings = 4
			mesh = blob
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glows or shape in ["gust", "puff"] else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glows:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if shape == "drop":
		mat.roughness = 0.15
	mesh.surface_set_material(0, mat)
	return mesh


func _cone(radius: float, height: float, sides: int, top: float = 0.0) -> Mesh:
	var cone := CylinderMesh.new()
	cone.top_radius = top
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = sides
	cone.rings = 1
	return cone


# A flat ribbon through points (x right, y along the flight), `width` wide; `pointed` narrows both ends (a leaf).
func _strip(points: Array, width: float, pointed: bool = false) -> Mesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var wa := 0.0 if pointed and i == 0 else width
		var wb := 0.0 if pointed and i == points.size() - 2 else width
		var across := (b - a).cross(Vector3.BACK).normalized()
		verts.append_array(PackedVector3Array([a - across * wa, a + across * wa, b + across * wb, a - across * wa, b + across * wb, b - across * wb]))
		for n in 6:
			normals.append(Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
