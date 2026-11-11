# Purpose: draws what core/fantasy_layout.gd says stands in the fantasy world's places and scattered sites, builds it
# when the player comes near and removes it when far: every model once per place however many copies stand there (one
# draw call per material), boxes to bump into for everything the layout calls solid (`layout.boxes`, plus posts that
# close slits too narrow to pass), the crafting stations and fires, the containers that can be searched (each a
# scene of its own so its lid can open), and the people
# (quest givers from data/fantasy/world.json plus a few ordinary folk per place) on rigged NPC bodies.
# Dependencies: core/fantasy_terrain.gd, core/fantasy_layout.gd, game/fantasy_models.gd, game/npc_body.gd,
# game/body_motion.gd.
extends Node3D

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")
const FantasyLayout = preload("res://core/fantasy_layout.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const NpcBody = preload("res://game/npc_body.gd")
const BodyMotion = preload("res://game/body_motion.gd")

const HIDE_EXTRA := 60.0
const PEOPLE_AT := 80.0  # people are built later than houses (bodies cost more)
const JOINTED := ["windmill", "hearth"]  # models made of more than one part: placed as scenes, not as copies
const MERGE_PER_FRAME := 6  # buildings folded into a place's one mesh each frame
const INSIDE_M := 45.0  # furniture inside walk-in houses is drawn within this distance
const FOLK_LOOKS := [["male", "farmer", "crop", "#5a4630"], ["female", "farmer", "ponytail", "#8a5a2a"], ["male", "fisher", "curly", "#2e2a22"], ["female", "druid", "bob", "#3b2a1a"],
	["male", "monk", "buzz", "#777777"], ["female", "witch", "long_straight", "#b98a4a"]]

var terrain: FantasyTerrain
var layout: FantasyLayout
var show_at := 260.0  # metres: a place is built inside this distance (graphics tier)
var prop_share := 1.0  # share of the small loose things that are placed (graphics tier)
var folk_share := 1.0  # share of the ordinary folk that are placed (graphics tier)
var small_m := 100.0  # small loose things are drawn within this distance and cast no shadows (graphics tier)
var motion := 3  # graphics tier: 0 nothing moves, 1 windmill sails, 2 people breathe too
var _merges: Array = []  # places whose buildings are still being folded into one mesh: {"holder", "list", "next", "tools"}
var stations: Array = []  # {"kind": workbench|forge|cauldron|fire, "at": Vector3, "place": id, "until": engine time or 0}
var people: Array = []  # {"id", "name", "at": Vector3, "place", "greet", "look", "folk": bool, "node", "mark"}

var _built := {}  # place or site id -> Node3D
var _sails: Array[Node3D] = []
var _fires: Array = []  # lit by players: {"node", "until"}
var _timer := 0.0
var _clock := 0.0
var _marks := {}  # npc id -> text above the head ("!" quest to give, "..." a quest points here)
var _meshes := {}
var _containers := {}  # "place or site id:item index" -> the container's own Node3D (see game/fantasy_rooms.gd)


# `folk` = region id -> {"name": String, "lines": Array} for the ordinary people (from the writers' files).
func setup(land_terrain: FantasyTerrain, world_layout: FantasyLayout, folk: Dictionary) -> void:
	terrain = land_terrain
	layout = world_layout
	var keep := {}  # place id -> spots the layout leaves free
	for npc: Dictionary in terrain.data["npcs"]:
		var home := terrain.place(String(npc["place"]))
		var x := float(home["pos"][0]) + float(npc["offset"][0])
		var z := float(home["pos"][1]) + float(npc["offset"][1])
		people.append({"id": String(npc["id"]), "name": String(npc["name"]), "at": Vector3(x, terrain.height(x, z), z), "place": String(npc["place"]),
			"greet": String(npc["greet"]), "look": npc["look"], "folk": false, "node": null, "mark": null, "indoors": bool(npc.get("indoors", false))})
		if bool(npc.get("indoors", false)):
			continue  # stands inside the place's walk-in house: placed below, once the place is laid out
		if not keep.has(npc["place"]):
			keep[npc["place"]] = []
		(keep[npc["place"]] as Array).append(Vector2(x, z))
	var counts := {"town": 5, "town_palisade": 5, "town_open": 4, "village": 3, "farm": 1, "tribe_red": 4, "tribe_blue": 4, "camp": 0}
	for place: Dictionary in terrain.places:
		var things := layout.place_items(place, keep.get(place["id"], []))  # lay the place out once, around its people
		if layout.interiors != null:  # the main story's people stand in their walk-in house
			for item: Dictionary in things:
				if bool(layout.interiors.call("walk_in", String(item["model"]))):
					var n := 0
					for person: Dictionary in people:
						if bool(person.get("indoors", false)) and String(person["place"]) == String(place["id"]):
							var inside: Vector2 = layout.interiors.call("standing_spot", item, n)
							person["at"] = Vector3(inside.x, terrain.height(inside.x, inside.y) + 0.02, inside.y)
							n += 1
					break
		var words: Dictionary = folk.get(String(place["region"]), {})
		var lines: Array = words.get("lines", [])
		var cx := float(place["pos"][0])
		var cz := float(place["pos"][1])
		for i in int(counts.get(String(place["kind"]), 0)):
			var a := FantasyTerrain.hash01(int(cx), int(cz), 700 + i) * TAU
			var r := float(place["flat"]) * (0.12 + 0.4 * FantasyTerrain.hash01(int(cx), int(cz), 720 + i))
			var spot := layout.push_out(cx + cos(a) * r, cz + sin(a) * r, 0.9)
			var style: Array = FOLK_LOOKS[(i + int(absf(cx))) % FOLK_LOOKS.size()]
			var tribe := String(place["kind"]).begins_with("tribe")
			people.append({"id": "folk:%s:%d" % [place["id"], i], "name": String(words.get("name", "")), "at": Vector3(spot.x, terrain.height(spot.x, spot.y), spot.y),
				"place": String(place["id"]), "greet": String(lines[(i + int(absf(cz))) % lines.size()]) if not lines.is_empty() else "", "folk": true, "node": null, "mark": null,
				"look": {"gender": style[0], "outfit": "desert_nomad" if tribe else style[1], "hair": style[2], "hair_color": style[3], "skin": (i * 3 + int(absf(cx))) % 10}})


# Call twice a second with the player's spot. Builds ONE place or site per call, the nearest first (building every
# one in range in the same frame was a long stall on arriving), and removes what is far away.
func follow(local: Vector3) -> void:
	var next_id := ""
	var next_items: Array = []
	var next_d := INF
	for place: Dictionary in terrain.places:
		var id := String(place["id"])
		var d := Vector2(local.x - float(place["pos"][0]), local.z - float(place["pos"][1])).length() - float(place["flat"])
		if d < show_at and not _built.has(id):
			if d < next_d:
				next_d = d
				next_id = id
				next_items = layout.place_items(place)
		elif d > show_at + HIDE_EXTRA and _built.has(id):
			_unbuild(id)
	var here := layout.site_cell(local.x, local.z)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var site := layout.site(here + Vector2i(dx, dz))
			if site.is_empty() or _built.has(site["id"]):
				continue
			var d := Vector2(local.x - float(site["x"]), local.z - float(site["z"])).length()
			if d < show_at and d < next_d:
				next_d = d
				next_id = String(site["id"])
				next_items = site["items"]
	if next_id != "":
		_build(next_id, next_items)
	for id: String in _built.keys():
		if id.begins_with("site:"):
			var parts := id.split(":")
			var site := layout.site(Vector2i(int(parts[1]), int(parts[2])))
			if Vector2(local.x - float(site["x"]), local.z - float(site["z"])).length() > show_at + HIDE_EXTRA:
				_unbuild(id)
	for i in people.size():
		var person: Dictionary = people[i]
		var d := Vector2(local.x - person["at"].x, local.z - person["at"].z).length()
		var wanted := d < PEOPLE_AT and (not bool(person["folk"]) or FantasyTerrain.hash01(i, 7, 3) < folk_share)
		if wanted and person["node"] == null:
			_stand(person)
		elif person["node"] != null and d > PEOPLE_AT + 30.0:
			(person["node"] as Node3D).queue_free()
			person["node"] = null
			person["mark"] = null


func station_near(local: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for station: Dictionary in stations:
		var d := Vector2(local.x - station["at"].x, local.z - station["at"].z).length()
		if d < best_d:
			best_d = d
			best = station
	return best


func fire_near(local: Vector3, reach: float) -> bool:
	for station: Dictionary in stations:
		if String(station["kind"]) == "fire" and Vector2(local.x - station["at"].x, local.z - station["at"].z).length() < reach:
			return true
	return false


func person_near(local: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for person: Dictionary in people:
		var d := Vector2(local.x - person["at"].x, local.z - person["at"].z).length()
		if d < best_d and person["node"] != null:
			best_d = d
			best = person
	return best


func person(id: String) -> Dictionary:
	for entry: Dictionary in people:
		if String(entry["id"]) == id:
			return entry
	return {}


# The town, village, farm or camp closest to a point (where a fallen player wakes up).
func haven_near(local: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for place: Dictionary in terrain.places:
		var kind := String(place["kind"])
		if kind.begins_with("town") or kind in ["farm", "camp", "village"]:
			var x := float(place["pos"][0])
			var z := float(place["pos"][1])
			var d := Vector2(local.x - x, local.z - z).length()
			if d < best_d:
				best_d = d
				var spot := layout.push_out(x + 4.0, z + 6.0, 1.0)
				best = Vector3(spot.x, terrain.height(spot.x, spot.y) + 0.3, spot.y)
	return best


# Text shown above people's heads ("!" has a quest, "..." a quest points here). {} clears all.
func set_marks(marks: Dictionary) -> void:
	_marks = marks
	for entry: Dictionary in people:
		if entry["mark"] != null:
			(entry["mark"] as Label3D).text = String(marks.get(entry["id"], ""))


# A fire a player lit: burns for `seconds`, cooks food and warms (see game/fantasy_work.gd).
func light_fire(local: Vector3, seconds: float) -> void:
	var fire := FantasyModels.scene("campfire")
	if fire == null:
		fire = Node3D.new()
	fire.position = Vector3(local.x, terrain.height(local.x, local.z), local.z)
	add_child(fire)
	var until := Time.get_ticks_msec() / 1000.0 + seconds
	_fires.append({"node": fire, "until": until})
	stations.append({"kind": "fire", "at": fire.position, "place": "", "until": until})


# Folds a few more buildings of the place at the front of the queue into its one mesh; when all are in, shows it.
# One mesh per place means one draw call per material instead of one per kind of building and material.
func _merge_step() -> void:
	var job: Dictionary = _merges[0]
	if not is_instance_valid(job["holder"]):
		_merges.pop_front()
		return
	var list: Array = job["list"]
	var tools: Dictionary = job["tools"]
	var done := 0
	while int(job["next"]) < list.size() and done < MERGE_PER_FRAME:
		var entry: Array = list[int(job["next"])]
		job["next"] = int(job["next"]) + 1
		done += 1
		var mesh: Mesh = entry[0]
		if mesh == null:
			continue
		var kinds: PackedStringArray = mesh.get_meta("kinds", PackedStringArray())
		for s in mesh.get_surface_count():
			var kind := kinds[s] if s < kinds.size() else "paint"
			if not tools.has(kind):
				var fresh := SurfaceTool.new()
				fresh.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[kind] = fresh
			(tools[kind] as SurfaceTool).append_from(mesh, s, entry[1])
	if int(job["next"]) < list.size():
		return
	var merged := ArrayMesh.new()
	for kind: String in tools:
		(tools[kind] as SurfaceTool).commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, FantasyModels.surface(kind))
	var drawn := MeshInstance3D.new()
	drawn.mesh = merged
	(job["holder"] as Node3D).add_child(drawn)
	_merges.pop_front()


func _process(delta: float) -> void:
	if not _merges.is_empty():
		_merge_step()
	if motion >= 1:
		for sails in _sails:
			if is_instance_valid(sails):
				sails.rotation.z += delta * 0.5
	_clock += delta
	if motion >= 2:
		for i in people.size():  # people stand breathing, not frozen
			if people[i]["node"] != null:
				BodyMotion.animate(people[i]["node"], 0.0, 0.0, _clock + float(i) * 0.7, false)
	_timer += delta
	if _timer < 1.0:
		return
	_timer = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_fires.size() - 1, -1, -1):
		if now >= float(_fires[i]["until"]):
			(_fires[i]["node"] as Node3D).queue_free()
			_fires.remove_at(i)
	for i in range(stations.size() - 1, -1, -1):
		if float(stations[i]["until"]) > 0.0 and now >= float(stations[i]["until"]):
			stations.remove_at(i)


# The model of a container standing in the open world (null when its place is not built).
func container(key: String) -> Node3D:
	var found: Variant = _containers.get(key)
	return found as Node3D if is_instance_valid(found) else null


func _unbuild(id: String) -> void:
	(_built[id] as Node3D).queue_free()
	_built.erase(id)
	for key: String in _containers.keys():
		if key.begins_with(id + ":"):
			_containers.erase(key)
	for i in range(stations.size() - 1, -1, -1):
		if String(stations[i]["place"]) == id:
			stations.remove_at(i)


func _mesh(model: String) -> Mesh:
	if not _meshes.has(model):
		_meshes[model] = FantasyModels.mesh(model)
	return _meshes[model]


# Builds one place or site from its list of items.
func _build(id: String, items: Array) -> void:
	var holder := Node3D.new()
	add_child(holder)
	_built[id] = holder
	var copies := {}  # model (+ "|in" for furniture inside a walk-in house) -> Array[Transform3D]
	var big: Array = []  # [Mesh, Transform3D] of every building
	var body := StaticBody3D.new()
	holder.add_child(body)
	for i in items.size():
		var item: Dictionary = items[i]
		var model := String(item["model"])
		var x := float(item["x"])
		var z := float(item["z"])
		var size: Dictionary = layout.props.get(model, {})
		var loose := layout.loose(item)
		if loose and String(item["station"]) == "" and String(item.get("loot", "")) == "" and FantasyTerrain.hash01(i, int(x), int(z)) > prop_share:
			continue
		var sunk := 0.14 if size.has("inner") else 0.05  # a walk-in house sits lower: its floor is level with the ground
		var inside := bool(item.get("inside", false))
		var at := Transform3D(Basis(Vector3.UP, float(item["turn"])), Vector3(x, terrain.height(x, z) - (-0.03 if inside else sunk), z))
		if String(item["station"]) != "":
			stations.append({"kind": String(item["station"]), "at": at.origin, "place": id, "until": 0.0})
		if model in JOINTED or String(item.get("loot", "")) != "":
			var made := FantasyModels.scene(model)
			if made != null:
				made.transform = at
				holder.add_child(made)
				if made.find_child("Sails", true, false) != null:
					_sails.append(made.find_child("Sails", true, false) as Node3D)
				if String(item.get("loot", "")) != "":
					_containers["%s:%d" % [id, i]] = made
		elif not loose and bool(item["solid"]):
			big.append([_mesh(model), at])  # buildings and walls: folded into one mesh for the whole place
		else:
			var key := model + ("|in" if inside else "")
			if not copies.has(key):
				copies[key] = []
			(copies[key] as Array).append(at)
		for box: Array in layout.boxes(item):
			var shape := CollisionShape3D.new()
			var block := BoxShape3D.new()
			block.size = Vector3(float(box[2]), float(box[4]), float(box[3]))
			shape.shape = block
			shape.transform = at * Transform3D(Basis(), Vector3(float(box[0]), float(box[4]) * 0.5, float(box[1])))
			body.add_child(shape)
		if size.has("inner"):  # a walk-in house: a warm light inside
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.82, 0.6)
			lamp.light_energy = 1.4
			lamp.omni_range = 9.0
			lamp.distance_fade_enabled = true
			lamp.distance_fade_begin = 40.0
			lamp.position = at * Vector3(0.0, float(size["wall_h"]) - 0.7, 0.0)
			holder.add_child(lamp)
	for plug: Array in layout.plugs(id, items):  # slits too narrow to pass are closed, so nobody gets wedged in one
		var shape := CollisionShape3D.new()
		var post := CylinderShape3D.new()
		post.radius = float(plug[2])
		post.height = 3.0
		shape.shape = post
		shape.position = Vector3(float(plug[0]), terrain.height(float(plug[0]), float(plug[1])) + 1.5, float(plug[1]))
		body.add_child(shape)
	if not big.is_empty():
		_merges.append({"holder": holder, "list": big, "next": 0, "tools": {}})
	for key: String in copies:
		var model := key.trim_suffix("|in")
		var mesh := _mesh(model)
		if mesh == null:
			continue
		var list: Array = copies[key]
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = mesh
		many.instance_count = list.size()
		for i in list.size():
			many.set_instance_transform(i, list[i])
		var drawn := MultiMeshInstance3D.new()
		drawn.multimesh = many
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # only buildings throw shadows
		drawn.visibility_range_end = INSIDE_M if key.ends_with("|in") else small_m
		holder.add_child(drawn)


func _stand(entry: Dictionary) -> void:
	var look := {"gender": "female", "height": 1.0, "weight": 1.0, "bust": 0.3, "glutes": 0.3, "skin": 2, "hair": "bob", "hair_color": "#553322", "face": "gentle_smile", "outfit": "farmer"}
	look.merge(entry["look"], true)
	var body := NpcBody.build(look)
	body.position = entry["at"]
	BodyMotion.animate(body, 0.0, 0.0, 0.0, false)  # a standing pose even on tiers where people do not move
	var home := terrain.place(String(entry["place"]))
	body.rotation.y = atan2(float(home["pos"][0]) - entry["at"].x, float(home["pos"][1]) - entry["at"].z) + PI  # face the middle of the place
	add_child(body)
	if String(entry["name"]) != "":
		var plate := Label3D.new()
		plate.text = String(entry["name"])
		plate.font_size = 30 if bool(entry["folk"]) else 36
		plate.pixel_size = 0.005
		plate.outline_size = 8
		plate.modulate = Color(1, 1, 1, 0.75) if bool(entry["folk"]) else Color.WHITE
		plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		plate.position.y = 2.05
		body.add_child(plate)
	var mark := Label3D.new()
	mark.text = String(_marks.get(entry["id"], ""))
	mark.font_size = 96
	mark.pixel_size = 0.006
	mark.outline_size = 12
	mark.modulate = Color(1.0, 0.85, 0.2)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.position.y = 2.5
	body.add_child(mark)
	var solid := StaticBody3D.new()  # people are in the way like anything else
	var shape := CollisionShape3D.new()
	var post := CylinderShape3D.new()
	post.radius = 0.32
	post.height = 1.8
	shape.shape = post
	shape.position.y = 0.9
	solid.add_child(shape)
	body.add_child(solid)
	entry["node"] = body
	entry["mark"] = mark
