# Purpose: what spells leave on the ground of the fantasy world (rules: core/ground_rules.gd, numbers:
# data/fantasy/ground.json): spikes that stay standing, ground that keeps burning, puddles that grow into floods
# and carry lightning. Draws them (three MultiMeshes: discs of water, scorched discs, spikes; flames and steam are
# the spell bits of game/spell_motes.gd) and hurts the creatures standing in them through game/spell_effects.gd.
# A fixed number of marks, no allocation while playing.
# Dependencies: game/spell_effects.gd (signal touched, ground_hit, motes), an enemy list (`source.enemy_list()`),
# core/ground_rules.gd.
extends Node3D

const GroundRules = preload("res://core/ground_rules.gd")

const SPIKES_EACH := 9  # spikes drawn for one spikes mark
const FLAME := {"shape": "flame", "second": [0.9, 0.1, 0.02], "size": 1.0}
const STEAM := {"shape": "puff", "second": [1.0, 1.0, 1.0], "size": 1.2}
const SPARK := {"shape": "spark", "second": [1.0, 1.0, 1.0], "size": 1.3}
const WATER := Color(0.25, 0.5, 0.85, 0.5)
const SCORCH := Color(0.07, 0.05, 0.04, 0.6)
const HIDDEN := Transform3D(Basis(Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)), Vector3(0, 0, 0))  # an instance shrunk to nothing

var cfg: Dictionary
var source: Node  # has enemy_list()
var effects: Node  # game/spell_effects.gd

# one mark: {"kind": "spikes" | "fire" | "water", "at": Vector3, "up": Vector3, "radius", "left", "life", "age",
# "next" (seconds to its next tick), "damage", "spell", "show" (another player's: drawn, hurts nothing), "slot",
# "seed", "color", "flash" (water: lit by lightning), "again" (water: seconds until lightning may run through again),
# "new" (not yet drawn at full size)}
var _marks: Array = []
var _free: Array[int] = []
var _water := MultiMesh.new()
var _scorch := MultiMesh.new()
var _spikes := MultiMesh.new()
var _rng := RandomNumberGenerator.new()
var _flame_due := 0.0
var _found: Array = []  # scratch list of _standing_in


func setup(numbers: Dictionary) -> void:
	cfg = numbers
	top_level = true  # marks are placed in world coordinates, whatever the hub's own offset is
	global_transform = Transform3D.IDENTITY
	var count := int(cfg["max_marks"])
	for slot in count:
		_free.append(count - 1 - slot)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.04
	disc.radial_segments = 24
	disc.rings = 1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	for part: Array in [[_water, disc, count, true, false], [_scorch, disc, count, true, false], [_spikes, cone, count * SPIKES_EACH, false, true]]:
		var many: MultiMesh = part[0]
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.use_colors = true
		many.mesh = part[1]
		many.instance_count = int(part[2])
		for i in many.instance_count:
			many.set_instance_transform(i, HIDDEN)
			many.set_instance_color(i, Color.WHITE)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		if bool(part[3]):
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		else:
			mat.roughness = 0.9
		var shown := MultiMeshInstance3D.new()
		shown.multimesh = many
		shown.material_override = mat
		shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(part[4]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shown.custom_aabb = AABB(Vector3(-100000, -1000, -100000), Vector3(200000, 3000, 200000))  # instances move: never culled as a whole
		add_child(shown)


func clear() -> void:
	for mark: Dictionary in _marks:
		_hide(mark)
		_free.append(int(mark["slot"]))
	_marks.clear()


# How many marks of a kind lie about (for checks and the log).
func count_of(kind: String) -> int:
	var n := 0
	for mark: Dictionary in _marks:
		if String(mark["kind"]) == kind:
			n += 1
	return n


# The widest mark of a kind (0 = none).
func widest(kind: String) -> float:
	var best := 0.0
	for mark: Dictionary in _marks:
		if String(mark["kind"]) == kind:
			best = maxf(best, float(mark["radius"]))
	return best


# A spell touched the world at `at` (game/spell_effects.gd signal `touched`).
func touch(at: Vector3, spell_radius: float, damage: float, spell: Dictionary, show_only: bool) -> void:
	var kinds := GroundRules.leaves(cfg, spell)
	if kinds.is_empty():
		return
	var query := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 1.5, 0.0), at - Vector3(0.0, float(cfg["max_height"]) + 0.5, 0.0))
	query.collision_mask = 1
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(query)
	if floor_hit.is_empty():
		return  # it burst in the air
	var spot: Vector3 = floor_hit["position"]
	var up: Vector3 = floor_hit["normal"]
	if up.y < 0.5:
		up = Vector3.UP  # a wall: lay the mark flat at its foot
	var c: Array = spell["color"]
	var color := Color(c[0], c[1], c[2])
	if kinds.has("shock"):
		for mark: Dictionary in _marks:
			if String(mark["kind"]) == "water" and _flat(mark["at"], spot) < float(mark["radius"]) + spell_radius * 0.5:
				_electrify(mark, damage, spell, show_only)
	if kinds.has("fire"):
		var size := GroundRules.radius(cfg["fire"], spell_radius)
		var doused := false
		for i in range(_marks.size() - 1, -1, -1):
			var mark: Dictionary = _marks[i]
			if String(mark["kind"]) == "water" and _flat(mark["at"], spot) < float(mark["radius"]):
				doused = true  # fire into water: steam, and part of the puddle boils away
				effects.get("motes").call("burst", STEAM, spot + Vector3(0, 0.3, 0), 16, 2.5, 1.2, 0.7, Color(1, 1, 1, 0.6), 0.8)
				mark["radius"] = GroundRules.boiled(cfg["water"], float(mark["radius"]), size)
				if float(mark["radius"]) <= 0.0:
					_remove(i)
				else:
					_place(mark)
		if not doused:
			var seconds := float(cfg["fire"]["seconds"]) + float(cfg["fire"]["seconds_per_element"]) * float(spell.get("count", 1))
			var burning := _near("fire", spot, 0.6)
			if burning.is_empty():
				burning = _add("fire", spot, up, size, seconds, damage, spell, show_only, color)
			else:  # more fire on burning ground: it burns on, as wide as the wider of the two
				burning["radius"] = maxf(float(burning["radius"]), size)
				burning["left"] = maxf(float(burning["left"]), seconds)
				burning["life"] = burning["left"]
				burning["damage"] = maxf(float(burning["damage"]), damage)
				_place(burning)
	if kinds.has("water"):
		var size := GroundRules.radius(cfg["water"], spell_radius)
		var puddle := {}
		for mark: Dictionary in _marks:  # water that lands in or at the edge of a puddle runs into it
			if String(mark["kind"]) == "water" and _flat(mark["at"], spot) < float(mark["radius"]) + size * 0.6:
				puddle = mark
				break
		if puddle.is_empty():
			puddle = _add("water", spot, up, size, GroundRules.dries_in(cfg["water"], size), damage, spell, show_only, color)
		else:  # more water in the same place: the puddle grows, towards a flood
			puddle["radius"] = GroundRules.pooled(cfg["water"], float(puddle["radius"]), size)
			puddle["left"] = GroundRules.dries_in(cfg["water"], float(puddle["radius"]))
			puddle["life"] = puddle["left"]
			_place(puddle)
		var wet_at: Vector3 = puddle["at"]
		var wet_size := float(puddle["radius"])
		for i in range(_marks.size() - 1, -1, -1):  # whatever burns where the water now lies goes out
			var mark: Dictionary = _marks[i]
			if String(mark["kind"]) == "fire" and _flat(mark["at"], wet_at) < wet_size + float(mark["radius"]) * 0.5:
				effects.get("motes").call("burst", STEAM, (mark["at"] as Vector3) + Vector3(0, 0.3, 0), 16, 2.5, 1.2, 0.7, Color(1, 1, 1, 0.6), 0.8)
				_remove(i)
	if kinds.has("spikes"):
		_add("spikes", spot, up, GroundRules.radius(cfg["spikes"], spell_radius), float(cfg["spikes"]["seconds"]), damage, spell, show_only, color)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# The mark of this kind that `spot` falls into (within `share` of its radius), or {}.
func _near(kind: String, spot: Vector3, share: float) -> Dictionary:
	for mark: Dictionary in _marks:
		if String(mark["kind"]) == kind and _flat(mark["at"], spot) < float(mark["radius"]) * share:
			return mark
	return {}


func _add(kind: String, spot: Vector3, up: Vector3, size: float, seconds: float, damage: float, spell: Dictionary, show_only: bool, color: Color) -> Dictionary:
	if _free.is_empty():
		_remove(0)  # full: the oldest mark goes
	var mark := {"kind": kind, "at": spot, "up": up, "radius": size, "left": seconds, "life": seconds, "age": 0.0, "next": float(cfg["tick"]),
		"damage": damage, "spell": spell, "show": show_only, "slot": _free.pop_back(), "seed": randi(), "color": color, "flash": 0.0, "again": 0.0, "new": true}
	_marks.append(mark)
	_place(mark)
	return mark


func _remove(index: int) -> void:
	var mark: Dictionary = _marks[index]
	_hide(mark)
	_free.append(int(mark["slot"]))
	_marks.remove_at(index)


func _hide(mark: Dictionary) -> void:
	var slot := int(mark["slot"])
	match String(mark["kind"]):
		"water":
			_water.set_instance_transform(slot, HIDDEN)
		"fire":
			_scorch.set_instance_transform(slot, HIDDEN)
		"spikes":
			for n in SPIKES_EACH:
				_spikes.set_instance_transform(slot * SPIKES_EACH + n, HIDDEN)


# Puts a mark's drawing where the mark is now (after it was made, grew, shrank or faded a step).
func _place(mark: Dictionary) -> void:
	var slot := int(mark["slot"])
	var at: Vector3 = mark["at"]
	var up: Vector3 = mark["up"]
	var size := float(mark["radius"])
	var fade := clampf(float(mark["left"]) / 1.5, 0.0, 1.0) * clampf(float(mark["age"]) / 0.25 + 0.2, 0.0, 1.0)
	var lie := Basis(Quaternion(Vector3.UP, up))
	match String(mark["kind"]):
		"water":
			_water.set_instance_transform(slot, Transform3D(lie * Basis.from_scale(Vector3(size, 1.0, size)), at + up * 0.05))
			var lit := float(mark["flash"])
			_water.set_instance_color(slot, Color(WATER.r, WATER.g, WATER.b, WATER.a * fade).lerp(Color(1.0, 1.0, 0.75, 0.9), lit))
		"fire":
			_scorch.set_instance_transform(slot, Transform3D(lie * Basis.from_scale(Vector3(size, 1.0, size)), at + up * 0.03))
			_scorch.set_instance_color(slot, Color(SCORCH.r, SCORCH.g, SCORCH.b, SCORCH.a * fade))
		"spikes":
			# they shoot up in a fifth of a second and sink back in their last second
			var grown := clampf(float(mark["age"]) / 0.2, 0.0, 1.0) * clampf(float(mark["left"]) / 1.0, 0.0, 1.0)
			var tint: Color = mark["color"]
			_rng.seed = int(mark["seed"])
			for n in SPIKES_EACH:
				var a := _rng.randf() * TAU
				var r := sqrt(_rng.randf()) * size * 0.85 if n > 0 else 0.0
				var tall := _rng.randf_range(1.1, 2.4) * (1.35 if n == 0 else 1.0) * grown
				var wide := _rng.randf_range(0.35, 0.6)
				var lean := Basis(Vector3(cos(a + 1.3), 0.0, sin(a + 1.3)), _rng.randf_range(-0.22, 0.22))
				var foot := at + lie * Vector3(cos(a) * r, 0.0, sin(a) * r)
				_spikes.set_instance_transform(slot * SPIKES_EACH + n, Transform3D(lie * lean * Basis.from_scale(Vector3(wide, maxf(tall, 0.001), wide)), foot + up * tall * 0.5))
				_spikes.set_instance_color(slot * SPIKES_EACH + n, tint.darkened(_rng.randf_range(0.25, 0.5)))


func _process(delta: float) -> void:
	if _marks.is_empty():
		return
	_flame_due -= delta
	var flames := _flame_due <= 0.0
	if flames:
		_flame_due = 0.05
	for i in range(_marks.size() - 1, -1, -1):
		var mark: Dictionary = _marks[i]
		mark["age"] = float(mark["age"]) + delta
		mark["left"] = float(mark["left"]) - delta
		mark["again"] = float(mark["again"]) - delta
		if float(mark["left"]) <= 0.0:
			_remove(i)
			continue
		var kind := String(mark["kind"])
		# drawn again only while it changes: appearing (until once drawn full), fading out, or lit by lightning
		var moving := bool(mark["new"]) or float(mark["left"]) < 1.6 or float(mark["flash"]) > 0.0
		if float(mark["flash"]) > 0.0:
			mark["flash"] = maxf(float(mark["flash"]) - delta * 2.5, 0.0)
		if moving:
			mark["new"] = float(mark["age"]) < 0.3
			_place(mark)
		if kind == "fire" and flames:
			var size := float(mark["radius"])
			var motes: Node = effects.get("motes")
			for n in clampi(int(size * 1.5), 2, 8):  # tongues of flame all over the burning ground
				var a := randf() * TAU
				var r := sqrt(randf()) * size
				motes.call("emit", FLAME, (mark["at"] as Vector3) + Vector3(cos(a) * r, 0.15, sin(a) * r), Vector3(0.0, randf_range(0.6, 1.8), 0.0), randf_range(0.35, 0.7), randf_range(0.35, 0.6), Color(1.0, 0.55, 0.12))
		mark["next"] = float(mark["next"]) - delta
		if float(mark["next"]) <= 0.0:
			mark["next"] = float(cfg["tick"])
			if not bool(mark["show"]):
				_tick(mark, kind)


# What a mark does to the creatures standing in it.
func _tick(mark: Dictionary, kind: String) -> void:
	var hit := {}
	var damage := 0.0
	match kind:
		"fire":
			hit = {"burn": float(cfg["fire"]["burn_seconds"])}
			damage = float(mark["damage"]) * float(cfg["fire"]["damage_share"])
		"spikes":
			hit = {"slow": float(cfg["spikes"]["slow"])}
			damage = float(mark["damage"]) * float(cfg["spikes"]["damage_share"])
		"water":
			hit = {"wet": float(cfg["water"]["wet_seconds"])}
			if GroundRules.flooded(cfg["water"], float(mark["radius"])):
				hit["slow"] = float(cfg["water"]["flood_slow"])
	for enemy: Variant in _standing_in(mark):
		effects.call("ground_hit", enemy, damage, mark["spell"], hit)


# Lightning runs through a puddle: everything standing in it is hit.
func _electrify(mark: Dictionary, damage: float, spell: Dictionary, show_only: bool) -> void:
	if float(mark["again"]) > 0.0:
		return
	mark["again"] = float(cfg["shock"]["again"])
	mark["flash"] = 1.0
	var at: Vector3 = mark["at"]
	var size := float(mark["radius"])
	var motes: Node = effects.get("motes")
	for n in clampi(int(size * 4.0), 8, 36):
		var a := randf() * TAU
		var r := sqrt(randf()) * size
		motes.call("emit", SPARK, at + Vector3(cos(a) * r, 0.2, sin(a) * r), Vector3(randf_range(-2.0, 2.0), randf_range(2.0, 6.0), randf_range(-2.0, 2.0)), randf_range(0.2, 0.45), 0.4, Color(1.0, 1.0, 0.7))
	if show_only:
		return
	for enemy: Variant in _standing_in(mark):
		effects.call("ground_hit", enemy, damage * float(cfg["shock"]["damage_share"]), spell, {"shock": float(cfg["shock"]["stun"])})


# The creatures on foot inside a mark.
func _standing_in(mark: Dictionary) -> Array:
	var out := _found
	out.clear()
	if source == null:
		return out
	var at: Vector3 = mark["at"]
	for enemy: Variant in source.call("enemy_list"):
		if not is_instance_valid(enemy):
			continue
		var body := enemy as Node3D
		if String((body.get("_stats") as Dictionary).get("walks", "land")) == "fly":
			continue
		if _flat(body.global_position, at) < float(mark["radius"]) + 0.3 and absf(body.global_position.y - at.y) < 3.0:
			out.append(body)
	return out
