extends Node3D
# Purpose: (polish1 F3, item 130) the farm animals of the fantasy world and the ox carts on its roads. SHOW ONLY:
# cows, sheep and hens graze round the farms, villages and farmsteads (data/fantasy/livestock.json says which place
# keeps what), wander a little, stand, and step out of a player's way (so they need no colliders); a carter on the
# road (a traveller with "cart" in game/fantasy_places.gd) leads an ox that draws a cart behind him. Each machine
# keeps its own animals; nothing is sent over the network and nothing here can be hunted or hurt.
# Budget: a herd exists only within show_m of the player, its animals walk and cast shadows only within near_m, at
# most `most` animals are built, and `share` (the graphics tier's "folk") thins every herd.
# Dependencies: core/fantasy_terrain.gd (ground, water), core/fantasy_layout.gd (sites, keeping out of buildings),
# game/fantasy_models.gd (creature and prop models), game/fantasy_places.gd (`people`, read only).

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")
const FantasyLayout = preload("res://core/fantasy_layout.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")

const SWING := 0.5  # radians a leg swings at a walk
const SHY_PACE := 2.6  # times its pace when it steps away from a player
const TRAIL_STEP := 0.3  # metres between the remembered points of a carter's way
const TRAIL_KEEP := 40  # points remembered (12 m: more than the cart trails behind)

var share := 1.0  # graphics tier: the share of each herd that is kept
var motion := 2  # graphics tier: under 1 nothing here moves
var _terrain: FantasyTerrain
var _layout: FantasyLayout
var _people: Node  # game/fantasy_places.gd
var _rules: Dictionary = {}
var _plans: Array = []  # every place that keeps animals: {"id", "x", "z", "reach", "spots": [[kind, Vector2]]}
var _herds := {}  # herd id (place id or site id) -> {"x", "z", "reach", "near": bool, "animals": Array}
var _carts := {}  # carter's id -> {"who": Dictionary, "ox": Node3D, "cart": Node3D, "swings": Array, "trail": PackedVector3Array, "phase": float}
var _count := 0
var _player := Vector3(INF, 0.0, INF)
var _rng := RandomNumberGenerator.new()
var _shared := {}  # surface kind -> the one material every animal wears


func setup(land_terrain: FantasyTerrain, world_layout: FantasyLayout, people: Node, rules: Dictionary) -> void:
	_terrain = land_terrain
	_layout = world_layout
	_people = people
	_rules = rules
	var herds: Dictionary = rules.get("herds", {})
	for place: Dictionary in _terrain.places:
		var kept: Array = herds.get(String(place.get("layout", "")), herds.get(String(place["kind"]), []))
		if kept.is_empty():
			continue
		var cx := float(place["pos"][0])
		var cz := float(place["pos"][1])
		var flat := float(place["flat"])
		var spots := _spots(kept, cx, cz, flat, int(cx) * 7 + int(cz))
		if not spots.is_empty():
			_plans.append({"id": String(place["id"]), "x": cx, "z": cz, "reach": flat * 2.0, "spots": spots})


# Where each animal of a herd grazes: [[kind, Vector2]] on dry, gentle ground in the herd's rings round (cx, cz).
func _spots(kept: Array, cx: float, cz: float, flat: float, salt: int) -> Array:
	var out: Array = []
	var n := 0
	for entry: Dictionary in kept:
		var ring: Array = entry.get("ring_m", [float(entry.get("ring", [1.0, 1.5])[0]) * flat, float(entry.get("ring", [1.0, 1.5])[1]) * flat])
		var bearing := FantasyTerrain.hash01(salt, 41, n) * TAU  # grazers keep together on one side of the place
		for i in int(entry["count"]):
			n += 1
			if FantasyTerrain.hash01(salt, n, 977) > share:
				continue
			for attempt in 6:
				var a := bearing + (FantasyTerrain.hash01(salt, n, 31 + attempt) - 0.5) * (1.6 if float(ring[0]) > flat else TAU)
				var r := lerpf(float(ring[0]), float(ring[1]), FantasyTerrain.hash01(salt, n, 57 + attempt))
				var spot := _layout.push_out(cx + cos(a) * r, cz + sin(a) * r, 1.0)
				if _fits(spot):
					out.append([String(entry["kind"]), spot])
					break
	return out


# Ground an animal may stand on: dry, not steep.
func _fits(spot: Vector2) -> bool:
	if _terrain.water_at(spot.x, spot.y) != "":
		return false
	var h := _terrain.height(spot.x, spot.y)
	return absf(_terrain.height(spot.x + 1.5, spot.y) - h) < 0.9 and absf(_terrain.height(spot.x, spot.y + 1.5) - h) < 0.9


# Call twice a second with the player's spot: builds the nearest missing herd (one a call), frees far ones, and
# gives every carter in sight his ox and cart.
func follow(local: Vector3) -> void:
	_player = local
	var show_m := float(_rules.get("show_m", 90.0))
	var want := {}
	var best_d := INF
	for plan: Dictionary in _plans:
		var d := Vector2(local.x - float(plan["x"]), local.z - float(plan["z"])).length() - float(plan["reach"])
		if d < show_m and not _herds.has(plan["id"]) and d < best_d:
			best_d = d
			want = plan
	var herds: Dictionary = _rules.get("herds", {})
	var here := _layout.site_cell(local.x, local.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var site := _layout.site(here + Vector2i(dx, dz))
			if site.is_empty() or _herds.has(site["id"]) or not herds.has("site:" + String(site["kind"])):
				continue
			var d := Vector2(local.x - float(site["x"]), local.z - float(site["z"])).length() - 30.0
			if d < show_m and d < best_d:
				best_d = d
				var cell := here + Vector2i(dx, dz)
				want = {"id": String(site["id"]), "x": float(site["x"]), "z": float(site["z"]), "reach": 34.0,
					"spots": _spots(herds["site:" + String(site["kind"])], float(site["x"]), float(site["z"]), 16.0, cell.x * 131 + cell.y * 17)}
	if not want.is_empty() and _count < int(_rules.get("most", 30)):
		_build(want)
	for id: String in _herds.keys():
		var herd: Dictionary = _herds[id]
		var d := Vector2(local.x - float(herd["x"]), local.z - float(herd["z"])).length() - float(herd["reach"])
		if d > show_m + 40.0:
			for animal: Dictionary in herd["animals"]:
				(animal["node"] as Node3D).queue_free()
			_count -= (herd["animals"] as Array).size()
			_herds.erase(id)
			continue
		var near := d < float(_rules.get("near_m", 45.0))
		if near != bool(herd["near"]):
			herd["near"] = near
			for animal: Dictionary in herd["animals"]:
				_shadows(animal["node"], near)
	for who: Dictionary in _people.get("people"):
		if not who.has("cart"):
			continue
		var id := String(who["id"])
		if who["node"] != null and not _carts.has(id):
			_hitch(who)
		elif who["node"] == null and _carts.has(id):
			(_carts[id]["ox"] as Node3D).queue_free()
			(_carts[id]["cart"] as Node3D).queue_free()
			_carts.erase(id)


func _build(plan: Dictionary) -> void:
	var animals: Array = []
	for spot: Array in plan["spots"]:
		var kind: Dictionary = _rules["kinds"][String(spot[0])]
		var home: Vector2 = spot[1]
		var body := _body(String(kind["model"]))
		body.position = Vector3(home.x, _terrain.height(home.x, home.y), home.y)
		body.rotation.y = FantasyTerrain.hash01(int(home.x), int(home.y), 5) * TAU
		add_child(body)
		_shadows(body, false)
		animals.append({"kind": kind, "home": home, "to": home, "wait": _rng.randf_range(0.0, float(kind["rest_s"][1])), "node": body,
			"swings": body.find_children("Swing*", "Node3D", true, false), "phase": 0.0, "hurry": 1.0})
	_count += animals.size()
	_herds[plan["id"]] = {"x": float(plan["x"]), "z": float(plan["z"]), "reach": float(plan["reach"]), "near": false, "animals": animals}


# One animal's model. Every animal wears the same few materials (one per kind of surface), unlike a creature that
# can be hit and flashes its own.
func _body(model: String) -> Node3D:
	var root := (load("res://assets/models/fantasy/creatures/" + model + ".gltf") as PackedScene).instantiate() as Node3D
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var piece := found as MeshInstance3D
		for i in piece.mesh.get_surface_count():
			var made := piece.mesh.surface_get_material(i)
			var kind := String(made.resource_name) if made != null else "paint"
			if kind == "glow":
				kind = "paint"  # no glowing eyes on a cow
			if not _shared.has(kind):
				var surface := FantasyModels.surface(kind).duplicate() as StandardMaterial3D
				surface.uv1_world_triplanar = false
				if kind == "paint":
					surface.albedo_color = Color(0.05, 0.04, 0.05)
				_shared[kind] = surface
			piece.set_surface_override_material(i, _shared[kind])
	return root


func _shadows(body: Node3D, on: bool) -> void:
	for found in body.find_children("*", "MeshInstance3D", true, false):
		(found as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# A carter gets his ox and cart, standing behind him back along his road.
func _hitch(who: Dictionary) -> void:
	var ox := _body("ox")
	add_child(ox)
	var cart := FantasyModels.scene("cart")
	if cart == null:
		cart = Node3D.new()
	add_child(cart)
	var trail := PackedVector3Array()
	var path: PackedVector2Array = who["path"]
	for k in range(5, 0, -1):  # the way he came: the points of his path behind him
		var p := path[posmod(int(who["next"]) - 1 - k, path.size())]
		trail.append(Vector3(p.x, _terrain.walk_height(p.x, p.y), p.y))
	trail.append(who["at"])
	_carts[String(who["id"])] = {"who": who, "ox": ox, "cart": cart, "swings": ox.find_children("Swing*", "Node3D", true, false), "trail": trail, "phase": 0.0}
	_draw_behind(_carts[String(who["id"])], 0.0)


# Where the ox and the cart are behind their carter, from the remembered points of his way.
func _draw_behind(hitched: Dictionary, moved: float) -> void:
	var cart_rules: Dictionary = _rules.get("cart", {})
	var trail: PackedVector3Array = hitched["trail"]
	var ox: Node3D = hitched["ox"]
	var cart: Node3D = hitched["cart"]
	var ox_at := _behind(trail, float(cart_rules.get("ox_behind_m", 2.3)))
	var axle_at := _behind(trail, float(cart_rules.get("axle_behind_m", 5.2)))
	ox.position = ox_at[0]
	ox.rotation.y = atan2(-(ox_at[1] as Vector3).x, -(ox_at[1] as Vector3).z)  # a model's front is its -z
	cart.position = axle_at[0]
	var pull: Vector3 = ox_at[0] - axle_at[0]
	cart.rotation = Vector3(deg_to_rad(float(cart_rules.get("shafts_deg", 14.0))), atan2(-pull.x, -pull.z), 0.0)
	hitched["phase"] = float(hitched["phase"]) + moved * 3.2
	var stride := sin(float(hitched["phase"])) * SWING * (1.0 if moved > 0.0 else 0.0)
	for part: Node3D in hitched["swings"]:
		part.rotation.x = stride if String(part.name).begins_with("SwingA") else -stride


# The point `metres` back along a trail from its newest end, and the way the trail runs there: [Vector3, Vector3].
func _behind(trail: PackedVector3Array, metres: float) -> Array:
	var left := metres
	for i in range(trail.size() - 1, 0, -1):
		var step := trail[i].distance_to(trail[i - 1])
		if step >= left:
			return [trail[i].lerp(trail[i - 1], left / maxf(step, 0.001)), (trail[i] - trail[i - 1]).normalized()]
		left -= step
	var way := (trail[1] - trail[0]).normalized() if trail.size() > 1 else Vector3.FORWARD
	return [trail[0] - way * left, way]


func _process(delta: float) -> void:
	if motion < 1:
		return
	for herd: Dictionary in _herds.values():
		if bool(herd["near"]):
			for animal: Dictionary in herd["animals"]:
				_live(animal, delta)
	for hitched: Dictionary in _carts.values():
		var who: Dictionary = hitched["who"]
		var trail: PackedVector3Array = hitched["trail"]
		var at: Vector3 = who["at"]
		var moved := at.distance_to(trail[trail.size() - 1])
		if moved >= TRAIL_STEP:
			trail.append(at)
			if trail.size() > TRAIL_KEEP:
				trail.remove_at(0)
			hitched["trail"] = trail
			_draw_behind(hitched, moved)
		else:
			for part: Node3D in hitched["swings"]:  # standing: the legs come to rest
				part.rotation.x = move_toward(part.rotation.x, 0.0, delta * 2.0)


# One animal for one frame: it stands grazing, then walks to another spot near its home; a player close by makes
# it step away.
func _live(animal: Dictionary, delta: float) -> void:
	var kind: Dictionary = animal["kind"]
	var body: Node3D = animal["node"]
	var at := Vector2(body.position.x, body.position.z)
	var from_player := at - Vector2(_player.x, _player.z)
	if from_player.length() < float(kind["shy_m"]) and float(animal["hurry"]) == 1.0:
		var away := at + from_player.normalized() * 4.0
		if _fits(away):
			animal["to"] = _layout.push_out(away.x, away.y, 1.0)
			animal["wait"] = 0.0
			animal["hurry"] = SHY_PACE
	if float(animal["wait"]) > 0.0:
		animal["wait"] = float(animal["wait"]) - delta
		for part: Node3D in animal["swings"]:
			part.rotation.x = move_toward(part.rotation.x, 0.0, delta * 2.0)
		return
	var to: Vector2 = animal["to"]
	var way := to - at
	if way.length() < 0.2:
		animal["hurry"] = 1.0
		animal["wait"] = _rng.randf_range(float(kind["rest_s"][0]), float(kind["rest_s"][1]))
		var home: Vector2 = animal["home"]
		var next := home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * float(kind["roam_m"])
		next = _layout.push_out(next.x, next.y, 1.0)
		if _fits(next):
			animal["to"] = next
		return
	var pace := float(kind["pace"]) * float(animal["hurry"])
	at += way.normalized() * minf(pace * delta, way.length())
	body.position = Vector3(at.x, _terrain.height(at.x, at.y), at.y)
	body.rotation.y = lerp_angle(body.rotation.y, atan2(-way.x, -way.y), minf(delta * 4.0, 1.0))
	animal["phase"] = float(animal["phase"]) + pace * delta * 5.0
	var stride := sin(float(animal["phase"])) * SWING
	for part: Node3D in animal["swings"]:
		part.rotation.x = stride if String(part.name).begins_with("SwingA") else -stride


# For checks (tools/dev_boot.gd): how many animals and carts are built.
func counts() -> Vector2i:
	return Vector2i(_count, _carts.size())
