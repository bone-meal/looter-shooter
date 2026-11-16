# Purpose: developer check (director: "add ways to check proper paths to each poi are generated on each island, and
# path can actually be used to the pois"): the REAL player walks an island's generated paths in the running game.
# Stands him at the island's start place, then for every place in turn takes the way along the paths
# (core/sea/isle_routes.gd), steers him along it like a road (heading for the point 3 m ahead of where he is along
# it) and holds the move + sprint keys; a place counts as
# reached when he stands within ARRIVE of it, then he also walks "into" it where the island says so (inside the cave,
# onto the temple, out along the jetty) and back. STUCK = no metre of progress for STUCK_SECONDS (one jump is tried
# first), WATER = he ended up swimming. Lines go to the dev log (`!isle walk`, tools/dev_boot.gd).
# Dependencies: core/sea/isle_routes.gd, the sea world (world_of / local_of, islands' config), game/player.gd
# (teleport, look_at_point, swimming), data/sea/isles/<island>.json.
extends Node

const IsleRoutes = preload("res://core/sea/isle_routes.gd")
const ARRIVE := 1.8
const STUCK_SECONDS := 4.0
const PLACE_SECONDS := 420.0
const LOOKAHEAD := 3.0

var lines := PackedStringArray()


# Walks to `only` (a place name) or every place; returns how many places failed. `snap` (optional, awaited with a
# picture name) takes a picture at each place reached, looking the way he came in (or into the place).
func walk(player: CharacterBody3D, sea: Node, island_id: String, only: String, snap := Callable()) -> int:
	var island := _island(sea, island_id)
	if island.is_empty():
		lines.append("WALK no island %s with paths" % island_id)
		return 1
	var routes := IsleRoutes.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/isles/%s.json" % String(island["props"]))))
	for problem in routes.problems():
		lines.append("WALK NETWORK %s" % problem)
	var origin := Vector2(float(island["pos"][0]), float(island["pos"][1]))
	var here: Vector2 = routes.pois[routes.start]
	player.call("teleport", sea.call("world_of", Vector3(origin.x + here.x, 140.0, origin.y + here.y)), 0.0)
	await _settle(player)
	var failed := 0
	for place: String in routes.pois:
		if place == routes.start or (only != "" and only != "all" and place != only):
			continue
		var target: Vector2 = routes.pois[place]
		var way: Array[Vector2] = routes.way(here, target)
		if way.is_empty():
			lines.append("WALK %s FAILED: no way along the paths" % place)
			failed += 1
			continue
		var said := await _follow(player, sea, origin, way, place)
		if said != "":
			lines.append("WALK %s FAILED: %s" % [place, said])
			failed += 1
			if snap.is_valid():
				var aim2: Vector3 = sea.call("world_of", Vector3(origin.x + target.x, 0.0, origin.y + target.y))
				player.call("look_at_point", Vector3(aim2.x, player.global_position.y + 1.4, aim2.z))
				await snap.call("walk_stuck_" + place)
			player.call("teleport", sea.call("world_of", Vector3(origin.x + target.x, 140.0, origin.y + target.y)), 0.0)
			await _settle(player)
		else:
			lines.append("WALK %s OK (%d path points, %.0f m)" % [place, way.size(), _length(way)])
			if snap.is_valid():
				var toward: Vector2 = routes.walk_into.get(place, target + (target - way[maxi(way.size() - 3, 0)]).normalized() * 10.0)
				var aim: Vector3 = sea.call("world_of", Vector3(origin.x + toward.x, 0.0, origin.y + toward.y))
				player.call("look_at_point", Vector3(aim.x, player.global_position.y + 1.4, aim.z))
				await snap.call("walk_" + place)
		if routes.walk_into.has(place):
			var inside: Array[Vector2] = [target, routes.walk_into[place]]
			var into := await _follow(player, sea, origin, inside, place + " (into)")
			lines.append("WALK %s into: %s" % [place, "OK" if into == "" else "FAILED: " + into])
			if into != "":
				failed += 1
				if snap.is_valid():
					var aim3: Vector3 = sea.call("world_of", Vector3(origin.x + inside[1].x, 0.0, origin.y + inside[1].y))
					player.call("look_at_point", Vector3(aim3.x, player.global_position.y + 1.4, aim3.z))
					await snap.call("walk_stuck_into_" + place)
			var back: Array[Vector2] = [routes.walk_into[place], target]
			await _follow(player, sea, origin, back, place + " (back out)")
		here = target
	_release()
	lines.append("WALK DONE failed=%d" % failed)
	return failed


func _island(sea: Node, island_id: String) -> Dictionary:
	var cfg: Dictionary = sea.get("islands").get("_cfg")
	for island: Dictionary in cfg["islands"]:
		if island.has("props") and (island_id == "" and String(island["id"]) == "start" or String(island["id"]) == island_id):
			return island
	return {}


# Follows the way like a driver on a road: finds where he is along it and heads for the point LOOKAHEAD metres
# further on (so he never cuts a corner off the road); returns "" once he stands at the last point, else why not.
func _follow(player: CharacterBody3D, sea: Node, origin: Vector2, way: Array[Vector2], label: String) -> String:
	var began := Time.get_ticks_msec()
	var along := 0.0  # metres along the way reached so far
	var best := -1.0
	var since := Time.get_ticks_msec()
	var jumped := false
	var total := _length(way)
	var since_at := Vector2.INF  # where he stood when progress last counted
	var slow := 0  # 4-second spells in a row without progress along the way
	while true:
		await get_tree().physics_frame
		var local: Vector3 = sea.call("local_of", player.global_position)
		var at := Vector2(local.x - origin.x, local.z - origin.y)
		if at.distance_to(way[way.size() - 1]) < ARRIVE:
			break
		if bool(player.get("swimming")):
			_release()
			return "in the water at (%.0f, %.0f), %.0f of %.0f m along" % [at.x, at.y, along, total]
		along = maxf(along, _project(way, at, along))
		if since_at == Vector2.INF:
			since_at = at
		if along > best + 1.0:
			best = along
			since = Time.get_ticks_msec()
			since_at = at
			jumped = false
			slow = 0
		elif Time.get_ticks_msec() - since > STUCK_SECONDS * 1000.0 and at.distance_to(since_at) > 2.0 and slow < 2:
			slow += 1  # moving but not along the way (a hairpin): give him a little longer
			since = Time.get_ticks_msec()
			since_at = at
		elif Time.get_ticks_msec() - since > STUCK_SECONDS * 1000.0:
			var goal := _point_at(way, minf(along + LOOKAHEAD, total))
			if jumped:
				_release()
				return "stuck at (%.0f, %.0f), %.0f of %.0f m along, heading for (%.0f, %.0f); %s" % [at.x, at.y, along, total, goal.x, goal.y, _blocker(player, sea, origin, goal)]
			jumped = true  # one jump over whatever is in the way
			since = Time.get_ticks_msec()
			Input.action_press("jump")
			await get_tree().physics_frame
			Input.action_release("jump")
		if Time.get_ticks_msec() - began > PLACE_SECONDS * 1000.0:
			_release()
			return "out of time (%s)" % label
		var aim2d := _point_at(way, minf(along + LOOKAHEAD, total))
		var aim: Vector3 = sea.call("world_of", Vector3(origin.x + aim2d.x, 0.0, origin.y + aim2d.y))
		player.call("look_at_point", Vector3(aim.x, player.global_position.y + 1.6, aim.z))
		Input.action_press("move_forward")
		Input.action_press("sprint")
	return ""


# How far along the way the point nearest to `at` lies (searched from a little before `from` onwards).
static func _project(way: Array[Vector2], at: Vector2, from: float) -> float:
	var run := 0.0
	var best := from
	var gap := INF
	for i in range(1, way.size()):
		var a := way[i - 1]
		var b := way[i]
		var seg := a.distance_to(b)
		if run + seg >= from - 10.0 and run <= from + 30.0 and seg > 0.0:
			var t := clampf((at - a).dot(b - a) / (seg * seg), 0.0, 1.0)
			var d := at.distance_to(a.lerp(b, t))
			if d < gap:
				gap = d
				best = run + seg * t
		run += seg
	return best


static func _point_at(way: Array[Vector2], dist: float) -> Vector2:
	var run := 0.0
	for i in range(1, way.size()):
		var seg := way[i - 1].distance_to(way[i])
		if run + seg >= dist and seg > 0.0:
			return way[i - 1].lerp(way[i], (dist - run) / seg)
		run += seg
	return way[way.size() - 1]


# What stands in his way: rays toward the goal at knee, waist and head height (what they hit, how far, how steep),
# and the ground's height under him and 1 m ahead.
func _blocker(player: CharacterBody3D, sea: Node, origin: Vector2, goal: Vector2) -> String:
	var space := player.get_world_3d().direct_space_state
	var aim: Vector3 = sea.call("world_of", Vector3(origin.x + goal.x, 0.0, origin.y + goal.y))
	var flat := Vector3(aim.x - player.global_position.x, 0.0, aim.z - player.global_position.z).normalized()
	var out := PackedStringArray()
	for up in [0.3, 0.9, 1.6]:
		var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, up, 0), player.global_position + Vector3(0, up, 0) + flat * 2.0)
		ray.exclude = [player.get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			out.append("%.1f m: clear" % up)
		else:
			var thing: Object = hit["collider"]
			var label := String((thing as Node).get_path()).get_slice("/", -1) if thing is Node else str(thing)
			if thing is Node and (thing as Node).get_parent() != null:
				label = String((thing as Node).get_parent().name) + "/" + label
			out.append("%.1f m: %s at %.1f m, slope %.0f deg" % [up, label, (hit["position"] as Vector3).distance_to(player.global_position + Vector3(0, up, 0)), rad_to_deg(acos(clampf((hit["normal"] as Vector3).y, -1.0, 1.0)))])
	for ahead in [0.0, 1.0]:
		var down := PhysicsRayQueryParameters3D.create(player.global_position + flat * ahead + Vector3(0, 3, 0), player.global_position + flat * ahead + Vector3(0, -6, 0))
		down.exclude = [player.get_rid()]
		var ground := space.intersect_ray(down)
		if not ground.is_empty():
			var local: Vector3 = sea.call("local_of", ground["position"])
			out.append("ground %+.0f m: %.2f" % [ahead, local.y])
	return ", ".join(out)


func _release() -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")


func _settle(player: CharacterBody3D) -> void:
	var waited := 0.0
	while waited < 20.0 and not player.is_on_floor():
		await get_tree().create_timer(0.25, true, false, true).timeout
		waited += 0.25
	await get_tree().create_timer(0.5, true, false, true).timeout


static func _length(way: Array[Vector2]) -> float:
	var total := 0.0
	for i in range(1, way.size()):
		total += way[i - 1].distance_to(way[i])
	return total
