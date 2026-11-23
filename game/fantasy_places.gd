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
const NEAR_M := 28.0  # people farther than this stand still and cast no shadow: a moving body is skinned piece by piece every frame and drawn a dozen times in every shadow split (ten guards cost Millbrook 2-4 ms, round 5). Guards on their round keep walking.
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
var plain := false  # graphics tier: buildings are shown as their plain models (assets/models/fantasy/plain/, about 30 % of the triangles)
var _merges: Array = []  # places whose buildings are still being folded into one mesh: {"holder", "list", "next", "tools"}
var signs: Array = []  # (polish1 item 123) road signs built now: {"place", "at": Vector3 local, "face": Vector2 (toward the road)}
var stations: Array = []  # {"kind": workbench|forge|cauldron|fire, "at": Vector3, "place": id, "until": engine time or 0}
var _player_at := Vector3(INF, 0.0, INF)  # where the player was at the last `follow` (guards halt when he is close)
var people: Array = []  # {"id", "name", "at": Vector3, "place", "greet", "look", "folk": bool, "node", "mark"}

var _built := {}  # place or site id -> Node3D
var _sails: Array[Node3D] = []
var _fires: Array = []  # lit by players: {"node", "until"}
var _piles: Array = []  # (polish1 item 107) logs laid on the ground, not lit yet: {"node", "at", "log"}
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
					for who: Dictionary in people:
						if bool(who.get("indoors", false)) and String(who["place"]) == String(place["id"]):
							var inside: Vector2 = layout.interiors.call("standing_spot", item, n)
							who["at"] = Vector3(inside.x, terrain.height(inside.x, inside.y) + 0.02, inside.y)
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
		_post_guards(place, things, folk.get("guard", {}))


# Show-only guards (round 5, numbers in data/fantasy/layouts.json "guards"): some stand just inside each gate looking
# out, the others walk a round inside the place. They are ordinary folk to talk to; what keeps the creatures out is
# core/safe_places.gd, not them. Each machine walks its own guards (they are not sent over the network).
func _post_guards(place: Dictionary, things: Array, words: Dictionary) -> void:
	var all: Dictionary = layout.rules.get("guards", {})
	var rule: Dictionary = all.get("kinds", {}).get(String(place["kind"]), {})
	if rule.is_empty():
		return
	var middle := Vector2(float(place["pos"][0]), float(place["pos"][1]))
	var lines: Array = words.get("lines", [])
	var count := 0
	for item: Dictionary in things:
		if not String(item["model"]).ends_with("gate"):
			continue
		var gate := Vector2(float(item["x"]), float(item["z"]))
		var inward := (middle - gate).normalized()
		for n in int(rule.get("at_gate", 0)):
			var side := inward.orthogonal() * (3.2 if n % 2 == 0 else -3.2) * float(1 + (n >> 1))
			var spot := layout.push_out(gate.x + inward.x * 4.5 + side.x, gate.y + inward.y * 4.5 + side.y, 0.9)
			_add_guard(place, count, all["gate_looks"], spot, words, lines).merge({"yaw": atan2(-inward.x, -inward.y) + PI})
			count += 1
	var ring := float(rule.get("ring", 0.3)) * float(place["flat"])
	var steps := maxi(int(TAU * ring / 1.5), 8)
	for n in int(rule.get("patrol", 0)):
		var path := PackedVector2Array()
		for step in steps:
			var a := TAU * float(step) / float(steps) * (1.0 if n % 2 == 0 else -1.0)  # every second guard walks the other way round
			var spot := layout.push_out(middle.x + cos(a) * ring, middle.y + sin(a) * ring, 0.9)
			if path.is_empty() or spot.distance_to(path[path.size() - 1]) > 0.5:
				path.append(spot)
		var start := floori(float(steps * n) / float(maxi(int(rule["patrol"]), 1))) % path.size()
		_add_guard(place, count, all["patrol_looks"], path[start], words, lines).merge({"path": path, "next": (start + 1) % path.size()})
		count += 1


func _add_guard(place: Dictionary, n: int, looks: Array, spot: Vector2, words: Dictionary, lines: Array) -> Dictionary:
	var style: Array = looks[(n + int(absf(float(place["pos"][0])))) % looks.size()]
	var who := {"id": "guard:%s:%d" % [place["id"], n], "name": String(words.get("name", "")), "at": Vector3(spot.x, terrain.height(spot.x, spot.y), spot.y),
		"place": String(place["id"]), "greet": String(lines[(n + int(absf(float(place["pos"][1])))) % lines.size()]) if not lines.is_empty() else "", "folk": true, "node": null, "mark": null,
		"look": {"gender": style[0], "outfit": style[1], "hair": style[2], "hair_color": style[3], "skin": (n * 3 + int(absf(float(place["pos"][0])))) % 10}}
	people.append(who)
	return who


# (polish1 E5, item 126) The coachman of every walled town: standing before its coach house (layout station
# "coach"), facing the town's middle; data/fantasy/coaches.json gives his name and look. Talking to him opens the
# coach page (game/fantasy_work.gd).
func add_coachmen(coaches: Dictionary) -> void:
	var who: Dictionary = coaches.get("coachman", {})
	var lines: Array = coaches.get("lines", [])
	for place: Dictionary in terrain.places:
		if not String(place["kind"]) in ["town", "town_palisade"]:
			continue
		for item: Dictionary in layout.place_items(place):
			if String(item["station"]) != "coach":
				continue
			var turn := float(item["turn"])
			var front := Vector2(-sin(turn), -cos(turn))  # a model's front is its -z
			var spot := layout.push_out(float(item["x"]) + front.x * 3.9 + front.y * 1.4, float(item["z"]) + front.y * 3.9 - front.x * 1.4, 0.9)
			var mid := Vector2(float(place["pos"][0]), float(place["pos"][1]))
			people.append({"id": "coachman:%s" % place["id"], "name": String(who.get("name", "Coachman")), "at": Vector3(spot.x, terrain.height(spot.x, spot.y), spot.y),
				"place": String(place["id"]), "greet": String(lines[0]) if not lines.is_empty() else "", "folk": true, "node": null, "mark": null,
				"look": (who.get("look", {}) as Dictionary).duplicate(), "coach": true, "yaw": atan2(spot.x - mid.x, spot.y - mid.y)})


# One frame of a guard's round: towards the next point of its path, halting while a player stands close.
# Returns how fast it walks (0..1) for its animation.
func _walk(who: Dictionary, delta: float) -> float:
	var at: Vector3 = who["at"]
	var guards: Dictionary = layout.rules["guards"]
	if Vector2(_player_at.x - at.x, _player_at.z - at.z).length() < float(guards["halt_m"]):
		return 0.0
	var path: PackedVector2Array = who["path"]
	var to := path[int(who["next"])] - Vector2(at.x, at.z)
	if to.length() < 0.25:
		who["next"] = (int(who["next"]) + 1) % path.size()
		return 0.45
	var step := to.normalized() * float(guards["pace"]) * delta
	at.x += step.x
	at.z += step.y
	at.y = terrain.height(at.x, at.z)
	who["at"] = at
	var body: Node3D = who["node"]
	body.position = at
	body.rotation.y = lerp_angle(body.rotation.y, atan2(to.x, to.y) + PI, minf(delta * 6.0, 1.0))
	return 0.45


# Call twice a second with the player's spot. Builds ONE place or site per call, the nearest first (building every
# one in range in the same frame was a long stall on arriving), and removes what is far away.
func follow(local: Vector3) -> void:
	_player_at = local
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
	var stood := 0
	for i in people.size():
		var who: Dictionary = people[i]
		var d := Vector2(local.x - who["at"].x, local.z - who["at"].z).length()
		var wanted := d < PEOPLE_AT and (not bool(who["folk"]) or FantasyTerrain.hash01(i, 7, 3) < folk_share)
		if wanted and who["node"] == null and stood < 2:  # two a call: the first body of each kind takes a moment to merge
			_stand(who)
			stood += 1
		if who["node"] != null and bool(who.get("shaded", true)) != (d < NEAR_M):
			who["shaded"] = d < NEAR_M
			for part: Node in (who["node"] as Node).find_children("*", "MeshInstance3D", true, false):
				(part as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d < NEAR_M else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if d >= NEAR_M and not who.has("path") and (who["node"] as Node).has_method("still"):
				(who["node"] as Node).call("still")
		elif who["node"] != null and d > PEOPLE_AT + 30.0:
			(who["node"] as Node3D).queue_free()
			who["node"] = null
			who["mark"] = null


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
	for who: Dictionary in people:
		var d := Vector2(local.x - who["at"].x, local.z - who["at"].z).length()
		if d < best_d and who["node"] != null:
			best_d = d
			best = who
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
		if entry["mark"] != null:  # (polish1 item 101) "!" a quest to give, gold "?" waiting to be spoken to, grey "?" a quest of theirs under way
			var m := String(marks.get(entry["id"], ""))
			var label := entry["mark"] as Label3D
			label.text = m.substr(0, 1)
			label.modulate = Color(0.7, 0.7, 0.7) if m == "?grey" else Color(1.0, 0.85, 0.3)
		_tint_plate(entry)


# (polish1 item 102) A person an open quest sends you to (gold "?") wears a gold name plate; everyone else white.
func _tint_plate(entry: Dictionary) -> void:
	var held: Variant = entry.get("plate")  # (a Variant first: the body may have been freed with its plate)
	if held == null or not is_instance_valid(held):
		return
	var plate := held as Label3D
	var target := String(_marks.get(entry["id"], "")) == "?gold"
	if target:
		plate.modulate = Color(1.0, 0.8, 0.25)
		plate.outline_modulate = Color(0.25, 0.14, 0.02)
	else:
		plate.modulate = Color(1, 1, 1, 0.75) if bool(entry["folk"]) else Color.WHITE
		plate.outline_modulate = Color.BLACK


# (polish1 item 107) Logs laid on the ground, to be lit with a fire spell.
func lay_logs(local: Vector3, log_id: String) -> void:
	var pile := Node3D.new()
	pile.position = Vector3(local.x, terrain.height(local.x, local.z), local.z)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.25, 0.15)
	for k in 4:
		var wood := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.08
		cyl.height = 0.7
		cyl.radial_segments = 6
		wood.mesh = cyl
		wood.material_override = bark
		wood.rotation = Vector3(deg_to_rad(90.0 - 18.0), float(k) * PI * 0.5, 0.0)
		wood.position = Vector3(sin(float(k) * PI * 0.5) * 0.12, 0.18, cos(float(k) * PI * 0.5) * 0.12)
		pile.add_child(wood)
	add_child(pile)
	_piles.append({"node": pile, "at": pile.position, "log": log_id})


# The laid pile within reach of a spot, -1 = none.
func pile_near(local: Vector3, reach: float) -> int:
	for i in _piles.size():
		var at: Vector3 = _piles[i]["at"]
		if Vector2(local.x - at.x, local.z - at.z).length() < reach:
			return i
	return -1


# Takes a laid pile away (it is being lit): its log id and place.
func take_pile(i: int) -> Dictionary:
	var pile: Dictionary = _piles[i]
	(pile["node"] as Node3D).queue_free()
	_piles.remove_at(i)
	return pile


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
			if people[i]["node"] != null and (bool(people[i].get("shaded", true)) or people[i].has("path")):
				BodyMotion.animate(people[i]["node"], _walk(people[i], delta) if people[i].has("path") else 0.0, 0.0, _clock + float(i) * 0.7, false)
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
	for i in range(signs.size() - 1, -1, -1):
		if String(signs[i]["place"]) == id:
			signs.remove_at(i)


func _mesh(model: String) -> Mesh:
	var id := "plain/" + model if plain and FantasyModels.has_model("plain/" + model) else model
	if not _meshes.has(id):
		_meshes[id] = FantasyModels.mesh(id)
	return _meshes[id]


# Builds one place or site from its list of items.
func _build(id: String, items: Array) -> void:
	var holder := Node3D.new()
	add_child(holder)
	_built[id] = holder
	var copies := {}  # model (+ "|in" for furniture inside a walk-in house) -> Array[Transform3D]
	var big: Array = []  # [Mesh, Transform3D] of every building
	var body := StaticBody3D.new()
	holder.add_child(body)
	_road_signs(id, holder, body)
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
		if String(item["station"]) != "":  # model, yaw and n (its number among the place's stations of that kind): Agility's obstacles
			var n := 0
			for other: Dictionary in stations:
				if String(other["place"]) == id and String(other["kind"]) == String(item["station"]):
					n += 1
			stations.append({"kind": String(item["station"]), "at": at.origin, "place": id, "until": 0.0, "model": model, "yaw": float(item["turn"]), "n": n})
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
			var radius := layout.round_radius(item, box)
			if radius > 0.0:
				var drum := CylinderShape3D.new()
				drum.radius = radius
				drum.height = float(box[4])
				shape.shape = drum
			else:
				var block := BoxShape3D.new()
				var trim := 0.22 if inside else 0.0  # (polish1 item 100) furniture in a walk-in house is a little smaller than drawn: corners no longer catch
				block.size = Vector3(maxf(float(box[2]) - trim, 0.3), float(box[4]), maxf(float(box[3]) - trim, 0.3))
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


# (polish1 item 123) Road signs: where each road leaves a place, a post at the roadside just past the place's edge
# with an arm for EVERY road leaving that place (the junction), each pointing down its road with the name of the place
# at its end and the distance, and a board with this place's name on top. Text on both faces.
func _road_signs(id: String, holder: Node3D, body: StaticBody3D) -> void:
	var home := terrain.place(id)
	if home.is_empty():
		return
	var center := Vector2(float(home["pos"][0]), float(home["pos"][1]))
	var leaving: Array = []  # [direction from the place along the road, destination name, road length]
	for k in terrain.road_ends.size():
		var ends: Array = terrain.road_ends[k]
		var line: PackedVector2Array = terrain.roads[k]
		var other := ""
		if String(ends[0]) == id:
			other = String(ends[1])
		elif String(ends[1]) == id:
			other = String(ends[0])
		else:
			continue
		var length := line[0].distance_to(line[1]) + line[1].distance_to(line[2])
		leaving.append([(line[1] - center).normalized(), String(terrain.place(other).get("name", other)), length])
	if leaving.is_empty():
		return
	var wood := FantasyModels.tinted("timber", Color(0.55, 0.42, 0.28))
	var face_font: Font = load("res://assets/fonts/GrenzeGotisch.ttf")
	for road: Array in leaving:
		var dir: Vector2 = road[0]
		var side := Vector2(-dir.y, dir.x)
		var spot := center + dir * (float(home["flat"]) + 9.0) + side * 3.6
		spot = layout.push_out(spot.x, spot.y, 0.6)
		var post := Node3D.new()
		post.position = Vector3(spot.x, terrain.height(spot.x, spot.y) - 0.15, spot.y)
		holder.add_child(post)
		signs.append({"place": id, "at": post.position, "face": -side})
		var pole := MeshInstance3D.new()
		var pole_mesh := BoxMesh.new()
		pole_mesh.size = Vector3(0.16, 3.0, 0.16)
		pole.mesh = pole_mesh
		pole.material_override = wood
		pole.position.y = 1.5
		post.add_child(pole)
		var shape := CollisionShape3D.new()  # a slim round post: nothing to catch on
		var drum := CylinderShape3D.new()
		drum.radius = 0.14
		drum.height = 3.0
		shape.shape = drum
		shape.position = post.position + Vector3(0, 1.5, 0)
		body.add_child(shape)
		_sign_board(post, String(home.get("name", id)), 2.95, atan2(-side.x, -side.y), clampf(0.4 + float(String(home.get("name", id)).length()) * 0.1, 1.2, 2.6), wood, face_font, true)  # this place's name across the top, facing the road
		var arms := leaving.duplicate()
		arms.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) < float(b[2]))
		for k in arms.size():
			var to_dir: Vector2 = arms[k][0]
			var aim := (center + to_dir * (float(home["flat"]) + 60.0)) - spot  # down that road, seen from this post
			var yaw := atan2(-aim.y, aim.x)
			var words := "%s  %s" % [String(arms[k][1]), ("%.1f km" % (float(arms[k][2]) / 1000.0)) if float(arms[k][2]) >= 1000.0 else "%d m" % roundi(float(arms[k][2]))]
			_sign_board(post, words, 2.55 - 0.34 * k, yaw, clampf(0.3 + float(words.length()) * 0.085, 1.2, 2.8), wood, face_font, false)  # the plank as long as its words


# One board on a sign post: an arm pointing along `yaw` (a pointed end) or the name board (centred). Text both sides.
func _sign_board(post: Node3D, words: String, height: float, yaw: float, length: float, wood: Material, face_font: Font, centred: bool) -> void:
	var arm := Node3D.new()
	arm.position.y = height
	arm.rotation.y = yaw
	post.add_child(arm)
	var plank := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(length, 0.26, 0.05)
	plank.mesh = board
	plank.material_override = wood
	plank.position.x = 0.0 if centred else length * 0.5 + 0.05
	arm.add_child(plank)
	if not centred:  # the pointed end
		var tip := MeshInstance3D.new()
		var point := PrismMesh.new()
		point.size = Vector3(0.26, 0.22, 0.05)
		tip.mesh = point
		tip.material_override = wood
		tip.rotation.z = -PI * 0.5
		tip.position.x = length + 0.05 + 0.11
		arm.add_child(tip)
	for back in 2:
		var label := Label3D.new()
		label.text = words
		label.font = face_font
		label.font_size = 64
		label.pixel_size = 0.0032
		label.modulate = Color(0.12, 0.07, 0.03)
		label.outline_size = 0
		label.double_sided = false
		label.width = length * 300.0
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.position = Vector3(plank.position.x, 0.0, 0.03 if back == 0 else -0.03)
		label.rotation.y = 0.0 if back == 0 else PI
		label.visibility_range_end = 45.0
		arm.add_child(label)


func _stand(entry: Dictionary) -> void:
	var look := {"gender": "female", "height": 1.0, "weight": 1.0, "bust": 0.3, "glutes": 0.3, "skin": 2, "hair": "bob", "hair_color": "#553322", "face": "gentle_smile", "outfit": "farmer"}
	look.merge(entry["look"], true)
	var body := NpcBody.build(look)
	entry["shaded"] = true  # a new body casts a shadow until `follow` finds it far away
	body.position = entry["at"]
	BodyMotion.animate(body, 0.0, 0.0, 0.0, false)  # a standing pose even on tiers where people do not move
	var home := terrain.place(String(entry["place"]))
	body.rotation.y = atan2(float(home["pos"][0]) - entry["at"].x, float(home["pos"][1]) - entry["at"].z) + PI  # face the middle of the place
	if entry.has("yaw"):
		body.rotation.y = float(entry["yaw"])  # a gate guard looks out through its gate
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
		entry["plate"] = plate
		_tint_plate(entry)
	var mark := Label3D.new()
	var m := String(_marks.get(entry["id"], ""))
	mark.text = m.substr(0, 1)
	mark.font_size = 96
	mark.pixel_size = 0.006
	mark.outline_size = 12
	mark.modulate = Color(0.7, 0.7, 0.7) if m == "?grey" else Color(1.0, 0.85, 0.2)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = bool(entry.get("indoors", false))  # (polish1 item 123) shows through the roof: their house is findable from the street
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
