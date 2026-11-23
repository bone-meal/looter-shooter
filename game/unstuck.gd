# Purpose: the automatic unstuck (polish1 item 110, TOP PRIORITY): frees a player before they notice when the body
# has ended up INSIDE solid ground (a hill, a rock, a wall) or wedged so that it cannot move any way while trying to.
# Every tick: (1) a slightly smaller copy of the body's capsule is tested against the world; overlapping for STUCK_IN s
# means stuck inside something; (2) wanting to move but moving under 3 % of it for WEDGED s while every way out
# (four sides and up) is blocked means wedged. Then the nearest free spot is searched (up first, then a ring of
# spots out to 3 m) and the body is put there; if none, back to the last spot it stood on freely. (3) In Aurelind
# (ground_height set) feet more than 0.4 m under the land = inside a hill: put back on top.
# Dependencies: none. game/player.gd calls step() after move_and_slide and remembers good spots through it.
extends RefCounted

const STUCK_IN := 0.25  # seconds inside geometry before it acts
const WEDGED := 1.0  # seconds of no progress with every way blocked
const GOOD_EVERY := 0.5  # how often a free standing spot is remembered

var freed := 0  # how many times it acted (dev status)
var ground_height := Callable()  # func(world x, z) -> the land's height there, while in a world made of one terrain (Aurelind)
var last_reason := ""
var notes: PackedStringArray = []  # (dev status, polish1 H1) the last few frees: why, where the feet were, the land and the collision floor there
var _inside_t := 0.0
var _wedged_t := 0.0
var _under_t := 0.0
var _good := Vector3.INF
var _good_t := 0.0
var _probe := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


# body: the player; capsule: its collision capsule and the node holding it; wish: the wanted move (world, m/s);
# moved: how far it really went this tick; dt: the tick. Returns true when it moved the body.
func step(body: CharacterBody3D, capsule: CapsuleShape3D, holder: Node3D, wish: Vector3, moved: Vector3, dt: float) -> bool:
	var at := holder.global_transform
	var inside := _overlaps(body, capsule, at)
	_inside_t = _inside_t + dt if inside else 0.0
	var want := Vector2(wish.x, wish.z).length()
	var went := Vector2(moved.x, moved.z).length()
	if want > 0.5 and went < want * dt * 0.03:
		_wedged_t += dt
	else:
		_wedged_t = 0.0
	if not inside and body.is_on_floor():
		_good_t += dt
		if _good_t >= GOOD_EVERY:
			_good_t = 0.0
			_good = body.global_position
	var why := ""
	if ground_height.is_valid():  # under the land's surface (inside a hill): straight back up onto it
		var land := float(ground_height.call(body.global_position.x, body.global_position.z))
		if body.global_position.y < land - 0.4:
			_under_t += dt
			if _under_t >= STUCK_IN:
				_under_t = 0.0
				_note(body, "under the land %.2f" % land)
				body.global_position.y = land + 0.3
				body.velocity = Vector3.ZERO
				freed += 1
				last_reason = "under the land"
				return true
		else:
			_under_t = 0.0
	if _inside_t >= STUCK_IN:
		why = "inside"
	elif _wedged_t >= WEDGED and _boxed_in(body):
		why = "wedged"
	if why == "":
		return false
	_inside_t = 0.0
	_wedged_t = 0.0
	_note(body, why)
	var spot := _free_spot(body, capsule, holder)
	if spot == Vector3.INF:
		if _good == Vector3.INF:
			return false
		spot = _good + Vector3.UP * 0.3
	body.global_position = spot
	body.velocity = Vector3.ZERO
	freed += 1
	last_reason = why
	return true


func _overlaps(body: CharacterBody3D, capsule: CapsuleShape3D, at: Transform3D) -> bool:
	_probe.radius = maxf(capsule.radius - 0.08, 0.05)
	_probe.height = maxf(capsule.height - 0.3, _probe.radius * 2.0)
	_query.shape = _probe
	_query.transform = at
	_query.collision_mask = body.collision_mask
	_query.exclude = [body.get_rid()]
	return not body.get_world_3d().direct_space_state.intersect_shape(_query, 1).is_empty()


# Every way out blocked: the four sides and up.
func _boxed_in(body: CharacterBody3D) -> bool:
	for way: Vector3 in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0, 0.3), Vector3(0, 0, -0.3), Vector3(0, 0.3, 0)]:
		if not body.test_move(body.global_transform, way):
			return false
	return true


# The nearest spot where the whole capsule is free and there is ground under it: straight up first (out of a hill),
# then rings round the body.
func _free_spot(body: CharacterBody3D, capsule: CapsuleShape3D, holder: Node3D) -> Vector3:
	var offset := holder.global_position - body.global_position
	var tries: Array[Vector3] = []
	for up: float in [0.6, 1.2, 2.0, 3.0, 4.5]:
		tries.append(Vector3(0, up, 0))
	for r: float in [0.8, 1.6, 2.4, 3.2]:
		for k in 8:
			var a := TAU * float(k) / 8.0
			tries.append(Vector3(cos(a) * r, 0.5, sin(a) * r))
	var full := CapsuleShape3D.new()
	full.radius = capsule.radius
	full.height = capsule.height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = full
	q.collision_mask = body.collision_mask
	q.exclude = [body.get_rid()]
	var space := body.get_world_3d().direct_space_state
	for t: Vector3 in tries:
		var spot := body.global_position + t
		q.transform = Transform3D(holder.global_basis, spot + offset)
		if not space.intersect_shape(q, 1).is_empty():
			continue
		var down := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.2, spot + Vector3.DOWN * 6.0, body.collision_mask, [body.get_rid()])
		var hit := space.intersect_ray(down)
		if hit.is_empty():
			continue
		return (hit["position"] as Vector3) + Vector3.UP * 0.05
	return Vector3.INF


func _note(body: CharacterBody3D, why: String) -> void:
	var p := body.global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p - Vector3(0, 6, 0), body.collision_mask, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	notes.append("%s at %.1f %.2f %.1f, floor below %s" % [why, p.x, p.y, p.z, "%.2f" % (hit["position"] as Vector3).y if not hit.is_empty() else "none"])
	if notes.size() > 12:
		notes.remove_at(0)
