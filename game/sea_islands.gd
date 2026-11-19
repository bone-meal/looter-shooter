# Purpose: the sea world's islands streamed by distance (sea step 4): within data/sea/islands.json `near` metres of
# the player an island's full model stands (loaded then, freed when it falls behind), out to `far` only a plain
# silhouette (a low cone in the island's colour) so the horizon is never empty, beyond that nothing (the fog).
# Island positions are sea coordinates; the nodes hang under the sea world's root, which carries the floating origin.
# Islands of the kit (an entry with "props"; director: kit + a showcase start island) get the blended textured ground
# (game/isle_ground.gd, tinted by the entry's "ground"), their props and set pieces (game/sea_isle_props.gd) and
# their rivers / waterfalls (<model>_water.glb, game/isle_water.gd). A big island (its data has "chunks") is streamed
# by chunk instead (game/sea_isle_stream.gd: near / far ground, collision and clutter near the player; on the host
# collision near every player at sea).
# No hitch when one comes near (sea step 13g, director: load in background): from `near` + `prefetch` metres its
# model is loaded and its list read and sorted on background threads; once inside `near` it is put together a few
# pieces a frame (`build_ms_per_frame`). Only an island a player is already standing by (arriving, a teleport) is
# built at once. Their ground collision is baked beforehand (tools/bake_isle_shapes.tscn) and loaded on the loader's
# thread too; a model changed since its bake is given collision the old way.
# Dependencies: assets/models/sea/<model>.glb (tools/blender/sea_islands.py, sea_isle_start.py), data/sea/islands.json,
# game/isle_ground.gd, game/sea_isle_props.gd, game/isle_water.gd, game/sea_isle_stream.gd, assets/models/sea/shapes/.
extends Node3D

const IsleGround = preload("res://game/isle_ground.gd")
const IsleProps = preload("res://game/sea_isle_props.gd")
const IsleWater = preload("res://game/isle_water.gd")
const IsleStream = preload("res://game/sea_isle_stream.gd")
const MODELS := "res://assets/models/sea/"
const SHAPES := "res://assets/models/sea/shapes/"  # baked island collision (tools/bake_isle_shapes.tscn, sea step 13g)

var graphics := "medium"  # the graphics tier (game/sea_world.gd enter): how thick and far the props are drawn
var _cfg: Dictionary
var _shown := {}  # island id -> {"full": Node3D or null, "far": MeshInstance3D}
var build_ms := {}  # island id -> its last full build (dev, sea step 13g): {"frames", "main_ms" (on the main thread), "worst_ms" (one frame), "waited_ms" (blocked on the background work), "sync"}
var events: Array = []  # dev (sea step 13g): "ms what id" of the last builds / take-downs
var retired := {}  # dev (sea step 13g): the longest single free while taking islands down
var _jobs := {}  # island id -> {"task": WorkerThreadPool id, "path": model, "out": Dictionary filled by _prep} (sea step 13g)


func setup(cfg: Dictionary) -> void:
	_cfg = cfg


# Call every half second. points = sea positions of the players the islands are kept for: the first is this machine's
# own player when own is true; on the host the rest are other players at sea (director 2026-11-16 "1": the host keeps
# the full island and its detailed collision round every player out there, as it decides hits and drops round them).
# Small clutter only follows this machine's own player.
func follow(points: Array, own: bool = true) -> void:
	var near := float(_cfg["near"])
	var far := float(_cfg["far"])
	var flat: Array = []
	for point: Vector3 in points:
		flat.append(Vector2(point.x, point.z))
	for island: Dictionary in _cfg["islands"]:
		var id := String(island["id"])
		var at := Vector2(float(island["pos"][0]), float(island["pos"][1]))
		var d := INF
		for point: Vector2 in flat:
			d = minf(d, at.distance_to(point) - float(island["radius"]))
		var entry: Dictionary = _shown.get(id, {})
		if d > far * 1.05:
			if not entry.is_empty():
				_free(entry)
				_shown.erase(id)
			_drop_job(id)
			continue
		if entry.is_empty():
			entry = {"full": null, "far": _silhouette(island)}
			_shown[id] = entry
		var want_full := d < near
		if d > near + float(_cfg.get("prefetch", 0.0)):
			entry["cool"] = false
		if entry["full"] == null and not _jobs.has(id) and (want_full or (d < near + float(_cfg.get("prefetch", 0.0)) and not bool(entry.get("cool", false)))):
			_start_job(island)  # (not again on the way out from one just let go: only when coming back, or once past the ring)
		if want_full and entry["full"] == null:
			var close := d < float(_cfg.get("close", 150.0))  # a player by it already (arrival, teleport): at once
			if close or _job_ready(id):
				_build(island, entry, close)
		elif not want_full and d > near * 1.15 and entry["full"] != null:
			_retire(entry["full"])
			entry["full"] = null
			entry["cool"] = true
		(entry["far"] as Node3D).visible = entry["full"] == null
		if entry["full"] != null and (entry["full"] as Node).has_node("Stream"):
			var locals: Array = flat.map(func(point: Vector2) -> Vector2: return point - at)
			((entry["full"] as Node).get_node("Stream") as Object).call("follow", locals, own)


# Background work for an island (sea step 13g): its model loads on the resource loader's thread, its list is read and
# sorted on a worker thread (_prep).
func _start_job(island: Dictionary) -> void:
	var path := MODELS + String(island["model"]) + ".glb"
	if not ResourceLoader.exists(path):
		return
	ResourceLoader.load_threaded_request(path)
	var shapes: Array = _shape_index(String(island["model"]))
	for entry: Array in shapes:
		ResourceLoader.load_threaded_request(String(entry[1]))
	var out := {}
	_jobs[String(island["id"])] = {"path": path, "shapes": shapes, "out": out, "task": WorkerThreadPool.add_task(_prep.bind(island, _cfg["props"], graphics, out))}


# The island model's baked collision (tools/bake_isle_shapes.tscn): [[node path, shape file, mesh vertex count]].
static func _shape_index(model: String) -> Array:
	var path := SHAPES + model + ".json"
	if not FileAccess.file_exists(path):
		return []
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return index if index is Array else []


func _job_ready(id: String) -> bool:
	var job: Dictionary = _jobs.get(id, {})
	if job.is_empty() or not WorkerThreadPool.is_task_completed(int(job["task"])) or ResourceLoader.load_threaded_get_status(String(job["path"])) != ResourceLoader.THREAD_LOAD_LOADED:
		return false
	for entry: Array in job["shapes"]:
		if ResourceLoader.load_threaded_get_status(String(entry[1])) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
	return true


# The job's results (waiting for them if they are not ready: an island needed at once). No job: done here and now.
func _take(island: Dictionary) -> Dictionary:
	var id := String(island["id"])
	if not _jobs.has(id):
		var out := {}
		_prep(island, _cfg["props"], graphics, out)
		out["scene"] = load(MODELS + String(island["model"]) + ".glb")
		out["shapes"] = {}
		for entry: Array in _shape_index(String(island["model"])):
			if ResourceLoader.exists(String(entry[1])):
				_add_piece(out["shapes"], entry, load(String(entry[1])))
		return out
	var job: Dictionary = _jobs[id]
	_jobs.erase(id)
	WorkerThreadPool.wait_for_task_completion(int(job["task"]))
	var out: Dictionary = job["out"]
	out["scene"] = ResourceLoader.load_threaded_get(String(job["path"]))
	out["shapes"] = {}
	for entry: Array in job["shapes"]:
		var shape: Resource = ResourceLoader.load_threaded_get(String(entry[1]))
		if shape != null:
			_add_piece(out["shapes"], entry, shape)
	return out


static func _add_piece(shapes: Dictionary, entry: Array, shape: Resource) -> void:  # node path -> {"vertices", "pieces"}
	if not shapes.has(String(entry[0])):
		shapes[String(entry[0])] = {"vertices": int(entry[2]), "pieces": []}
	(shapes[String(entry[0])]["pieces"] as Array).append(shape)


func _drop_job(id: String) -> void:  # an island gone out of sight before it was built: its finished work let go
	if _jobs.has(id) and _job_ready(id):
		_take({"id": id})


# Plain data only (runs on a worker thread): the island's list read, its props grouped and their colliders worked out.
static func _prep(island: Dictionary, props_cfg: Dictionary, tier: String, out: Dictionary) -> void:
	if not island.has("props") or not FileAccess.file_exists(IsleProps.LISTS + String(island["props"]) + ".json"):
		return
	var list: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(IsleProps.LISTS + String(island["props"]) + ".json"))
	out["list"] = list
	if list.has("chunks"):
		out["sorted"] = IsleStream.bucket(list, props_cfg, tier)
	else:
		out["groups"] = IsleProps.groups_of(list["props"], props_cfg, tier)
		out["solids"] = IsleProps.solid_specs(list["props"], list.get("solid", {}))


# Puts the island together: the model at once, then its collision, props, set pieces and water as small steps, a few
# milliseconds of them a frame (all at once when `now`). The steps stop if the island is let go meanwhile.
func _build(island: Dictionary, entry: Dictionary, now: bool) -> void:
	_note("build " + String(island["id"]))
	var began := Time.get_ticks_usec()
	var got := _take(island)
	var waited := Time.get_ticks_usec() - began
	if got.get("scene") == null:
		return
	var made: Node3D = (got["scene"] as PackedScene).instantiate()
	add_child(made)
	made.position = Vector3(float(island["pos"][0]), 0.0, float(island["pos"][1]))
	entry["full"] = made
	var ground: Material = _ground()
	if island.has("props"):
		ground = IsleGround.material(String(island["id"]), island.get("ground", {}))
	var list: Dictionary = got.get("list", {})
	var steps: Array = []
	if list.has("chunks"):  # a big island: ground, collision and clutter streamed by chunk (game/sea_isle_stream.gd)
		var stream := IsleStream.new()
		stream.name = "Stream"
		made.add_child(stream)
		steps = stream.setup(made, ground, list, _cfg["props"], graphics, got.get("sorted", {}))
	else:
		for found in made.find_children("*", "MeshInstance3D", true, false):  # walked on and sailed into
			var mesh := found as MeshInstance3D
			if mesh.mesh != null:
				mesh.material_override = ground
				var baked: Dictionary = (got["shapes"] as Dictionary).get(String(made.get_path_to(mesh)), {})
				if not baked.is_empty() and int(baked["vertices"]) == _vertices(mesh.mesh):  # baked and still this mesh's: attached piece by piece
					var body := StaticBody3D.new()
					body.name = String(mesh.name) + "_col"
					mesh.add_child(body)
					for piece: Shape3D in baked["pieces"]:
						steps.append(_shape_step.bind(body, piece))
				else:
					steps.append(mesh.create_trimesh_collision)
		if not list.is_empty():
			var count := {"n": 0}
			for g: Dictionary in got["groups"]:
				steps.append(_group_step.bind(made, g, count))
			var body := StaticBody3D.new()
			body.name = "PropSolids"
			made.add_child(body)
			var specs: Array = got["solids"]
			for i in range(0, specs.size(), 40):
				steps.append(_solids_step.bind(body, specs.slice(i, i + 40)))
			for p: Array in list.get("places", []):
				steps.append(_place_step.bind(made, p, count))
			steps.append(func() -> void: made.set_meta("props", int(count["n"])))
	steps.append(_water.bind(made, island))
	var slice := int(float(_cfg.get("build_ms_per_frame", 3.0)) * 1000.0)
	var frame_began := Time.get_ticks_usec()
	var spent := frame_began - began
	var worst := spent
	var frames := 1
	var longest := 0
	var longest_is := ""
	for step: Callable in steps:
		if not now and Time.get_ticks_usec() - frame_began > slice:
			worst = maxi(worst, Time.get_ticks_usec() - frame_began)
			await get_tree().process_frame
			if not is_instance_valid(made) or entry.get("full") != made:
				return
			frame_began = Time.get_ticks_usec()
			frames += 1
		var step_began := Time.get_ticks_usec()
		step.call()
		spent += Time.get_ticks_usec() - step_began
		if Time.get_ticks_usec() - step_began > longest:
			longest = Time.get_ticks_usec() - step_began
			longest_is = "%s %s" % [String((step.get_object() as Node).name) if step.get_object() is Node else "", step.get_method()]
	worst = maxi(worst, Time.get_ticks_usec() - frame_began)
	_note("built " + String(island["id"]))
	build_ms[String(island["id"])] = {"frames": frames, "main_ms": snappedf(spent / 1000.0, 0.1), "worst_ms": snappedf(worst / 1000.0, 0.1), "waited_ms": snappedf(waited / 1000.0, 0.1), "sync": now,
		"longest_step": "%s %.1f ms" % [longest_is, longest / 1000.0], "steps": steps.size()}


# One piece of the baked collision, on the body under the mesh (as create_trimesh_collision() names it).
func _shape_step(body: StaticBody3D, shape: Shape3D) -> void:
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)


static func _vertices(mesh: Mesh) -> int:  # (as tools/bake_isle_shapes.gd counts them)
	var count := 0
	for i in mesh.get_surface_count():
		count += (mesh as ArrayMesh).surface_get_array_len(i) if mesh is ArrayMesh else 0
	return count


func _group_step(made: Node3D, g: Dictionary, count: Dictionary) -> void:
	count["n"] = int(count["n"]) + IsleProps.add_group(made, g)


func _place_step(made: Node3D, p: Array, count: Dictionary) -> void:
	if IsleProps.place(made, p):
		count["n"] = int(count["n"]) + 1


func _solids_step(body: StaticBody3D, specs: Array) -> void:
	IsleProps.add_solids(body, specs)


# Rivers and waterfalls: seen, not solid.
func _water(made: Node3D, island: Dictionary) -> void:
	var water_path := MODELS + String(island["model"]) + "_water.glb"
	if ResourceLoader.exists(water_path):
		var water := (load(water_path) as PackedScene).instantiate() as Node3D
		made.add_child(water)
		for found in water.find_children("*", "MeshInstance3D", true, false):
			var surface := found as MeshInstance3D
			surface.material_override = IsleWater.material("waterfall" if String(surface.name).begins_with("waterfall") else "water")
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static var _ground_mat: StandardMaterial3D


# The old test islands are painted in their vertex colours (sand, grass, rock).
static func _ground() -> StandardMaterial3D:
	if _ground_mat == null:
		_ground_mat = StandardMaterial3D.new()
		_ground_mat.vertex_color_use_as_albedo = true
		_ground_mat.roughness = 0.95
	return _ground_mat


func _silhouette(island: Dictionary) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	var r := float(island["radius"])
	cone.top_radius = r * 0.25
	cone.bottom_radius = r
	cone.height = clampf(r * 0.35, 6.0, 160.0)
	cone.radial_segments = 16
	cone.rings = 1
	var mesh := MeshInstance3D.new()
	mesh.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.42, 0.3)
	mat.roughness = 1.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.position = Vector3(float(island["pos"][0]), cone.height * 0.5 - 2.0, float(island["pos"][1]))
	return mesh


func _free(entry: Dictionary) -> void:
	if entry["full"] != null:
		_retire(entry["full"])
	(entry["far"] as Node3D).queue_free()


# An island let go is taken down a few pieces a frame too (sea step 13g: freeing one whole at once cost ~60 ms):
# hidden at once, then its parts (the parts of big ones like the streamed island's) freed within the frame budget.
func _retire(made: Node3D) -> void:
	_note("retire " + String(made.name))
	made.visible = false
	var pieces: Array = []
	_post_order(made, pieces)
	pieces.pop_back()  # (made itself: freed last)
	var off_began := Time.get_ticks_usec()
	for piece: Node in pieces:  # out of the physics space first: a body losing its shapes one by one while in it is slow (~0.1 s)
		if piece is CollisionObject3D:
			(piece as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE
			piece.process_mode = Node.PROCESS_MODE_DISABLED
	retired["off_us"] = maxi(int(retired.get("off_us", 0)), Time.get_ticks_usec() - off_began)
	var slice := int(float(_cfg.get("build_ms_per_frame", 3.0)) * 1000.0)
	var began := Time.get_ticks_usec()
	for piece: Node in pieces:
		if Time.get_ticks_usec() - began > slice:
			await get_tree().process_frame
			if not is_instance_valid(made):
				return
			began = Time.get_ticks_usec()
		while is_instance_valid(piece) and piece.has_method("shed") and bool(piece.call("shed", 4)):  # a streamed island's lists, a few at a time
			if Time.get_ticks_usec() - began > slice:
				await get_tree().process_frame
				if not is_instance_valid(made):
					return
				began = Time.get_ticks_usec()
		if is_instance_valid(piece):
			var at := Time.get_ticks_usec()
			var called := "%s %s" % [String(piece.name), piece.get_class()]
			piece.free()
			if Time.get_ticks_usec() - at > 5000:
				_note("freed %s %.1f ms" % [called, (Time.get_ticks_usec() - at) / 1000.0])
	var last := Time.get_ticks_usec()
	made.free()
	retired["last_us"] = Time.get_ticks_usec() - last
	_note("retired")
	retired["count"] = int(retired.get("count", 0)) + 1


func _note(what: String) -> void:
	events.append("%d %s" % [Time.get_ticks_msec(), what])
	if events.size() > 40:
		events.pop_front()


static func _post_order(node: Node, into: Array) -> void:  # children before their parent
	for child in node.get_children():
		_post_order(child, into)
	into.append(node)


func shown_count() -> Vector2i:  # (full models, silhouettes) for checks
	var full := 0
	var far := 0
	for id: String in _shown:
		if _shown[id]["full"] != null:
			full += 1
		elif (_shown[id]["far"] as Node3D).visible:
			far += 1
	return Vector2i(full, far)


func props_shown() -> int:  # copies of props standing (checks)
	var n := 0
	for id: String in _shown:
		var full: Variant = _shown[id]["full"]
		if full != null:
			n += int((full as Node3D).get_meta("props", 0))
			if (full as Node).has_node("Stream"):
				n += int((full as Node).get_node("Stream").call("drawn"))
	return n
