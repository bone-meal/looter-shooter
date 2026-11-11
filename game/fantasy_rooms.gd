# Purpose: going into the fantasy world's buildings and searching what is in them. Two cases (the rules are
# core/fantasy_interiors.gd): the main story's WALK-IN houses are part of the open world, so here only their chests and
# cupboards are found and searched; every other building is entered at its door (a short fade) into a furnished room
# built for it on the spot, far from the map, whose windows carry a small picture of the land outside. A search gives
# items from the container's loot table and the container stays empty until it refills (remembered per player).
# Dependencies: game/fantasy_world.gd (terrain, layout, interiors, give, toast, sound, set_indoors), game/fantasy_models.gd.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")

signal station_opened(kind: String)  # a hearth, forge, bench or cauldron indoors was used
signal faded  # the screen should fade (going in or out)

const STATION_WORDS := {"fire": "Cook at the hearth", "forge": "Work the forge", "workbench": "Use the workbench", "cauldron": "Brew at the cauldron"}
const FLOORS := {"wood": ["wood", Color(0.46, 0.35, 0.23)], "stone": ["stone", Color(0.5, 0.48, 0.45)], "dirt": ["rock", Color(0.36, 0.29, 0.22)]}

var looted := {}  # container key -> unix time it can be searched again
var prop_share := 1.0  # graphics tier: share of the plain furniture that is placed (containers and stations always are)

var _world: Node3D
var _player: Node3D
var _near := "?"  # which place and site the lists below were made for
var _doors: Array = []  # buildings that can be entered here: {"at": Vector2, "item", "kind", "key"}
var _boxes: Array = []  # containers in reach of the open world (walk-in houses): {"at": Vector3 local, "loot", "key", "model"}
var _room: Node3D  # the room the player is in (null = outdoors)
var _room_boxes: Array = []  # {"at": Vector3 world, "loot", "key", "model"}
var _room_stations: Array = []  # {"at": Vector3 world, "kind"}
var _exit := Vector3.ZERO  # world position of the room's door
var _outside := Vector3.ZERO  # world position in front of the building, to return to
var _anchor := Vector3.ZERO  # the same spot in map metres: where the player counts as standing while indoors
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(fantasy_world: Node3D, player: Node3D) -> void:
	_world = fantasy_world
	_player = player
	_rng.randomize()


func inside() -> bool:
	return _room != null


func anchor() -> Vector3:
	return _anchor


# Leaves any room at once without moving the player (the world is being left, or the player was moved).
func reset() -> void:
	if _room != null:
		_room.queue_free()
		_room = null
		_world.call("set_indoors", false)
	_near = "?"


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.5 or _room != null or not bool(_world.get("inside")):
		return
	_timer = 0.0
	var local: Vector3 = _world.call("player_local")
	var layout: RefCounted = _world.get("layout")
	var site: Dictionary = layout.call("site", layout.call("site_cell", local.x, local.z))
	var place_id := String(_world.call("place_here"))
	var id := place_id + "|" + String(site.get("id", ""))
	if id == _near:
		return
	_near = id
	_doors.clear()
	_boxes.clear()
	if place_id != "":
		_collect(place_id, layout.call("place_items", _world.terrain.place(place_id)))
	if not site.is_empty():
		_collect(String(site["id"]), site["items"])


func _collect(source: String, items: Array) -> void:
	var rules: RefCounted = _world.get("interiors")
	for i in items.size():
		var item: Dictionary = items[i]
		var model := String(item["model"])
		var key := "%s:%d" % [source, i]
		if String(item.get("loot", "")) != "":
			_boxes.append({"at": Vector3(float(item["x"]), _world.terrain.height(float(item["x"]), float(item["z"])), float(item["z"])), "loot": String(item["loot"]), "key": key, "model": model})
		elif not bool(item.get("inside", false)) and not bool(rules.call("walk_in", model)):
			var kind := String(rules.call("kind_of", model, float(item["x"]), float(item["z"])))
			if kind != "":
				_doors.append({"at": rules.call("door", item), "item": item, "kind": kind, "key": key})


func _name(group: String, id: String) -> String:
	return String(_world.data["interiors"]["names"][group].get(id, id))


func _nearest(list: Array, at: Vector3, reach: float) -> Dictionary:
	var best := {}
	for entry: Dictionary in list:
		var spot: Variant = entry["at"]
		var d := Vector2(at.x - spot.x, at.z - (spot.y if spot is Vector2 else spot.z)).length()
		if d < reach:
			reach = d
			best = entry
	return best


# What the interact key would do here ("" = nothing of ours).
func prompt(key: String) -> String:
	var reach := float(_world.data["interiors"]["reach"])
	if _room != null:
		var at := _player.global_position
		var box := _nearest(_room_boxes, at, reach)
		if not box.is_empty():
			return "[%s] Search %s" % [key, _name("container", String(box["model"])).to_lower()]
		var station := _nearest(_room_stations, at, reach)
		if not station.is_empty():
			return "[%s] %s" % [key, STATION_WORDS[String(station["kind"])]]
		if Vector2(at.x - _exit.x, at.z - _exit.z).length() < reach:
			return "[%s] Leave" % key
		return ""
	var local: Vector3 = _world.call("player_local")
	var chest := _nearest(_boxes, local, reach)
	if not chest.is_empty():
		return "[%s] Search %s" % [key, _name("container", String(chest["model"])).to_lower()]
	var door := _nearest(_doors, local, float(_world.data["interiors"]["door_reach"]))
	if not door.is_empty():
		return "[%s] Enter the %s" % [key, _name("building", String(door["kind"])).to_lower()]
	return ""


# Does it. Returns true if the key press was ours.
func interact() -> bool:
	var reach := float(_world.data["interiors"]["reach"])
	if _room != null:
		var at := _player.global_position
		var box := _nearest(_room_boxes, at, reach)
		if not box.is_empty():
			_search(box)
			return true
		var station := _nearest(_room_stations, at, reach)
		if not station.is_empty():
			station_opened.emit(String(station["kind"]))
			return true
		if Vector2(at.x - _exit.x, at.z - _exit.z).length() < reach:
			_leave()
		return true
	var local: Vector3 = _world.call("player_local")
	var chest := _nearest(_boxes, local, reach)
	if not chest.is_empty():
		_search(chest)
		return true
	var door := _nearest(_doors, local, float(_world.data["interiors"]["door_reach"]))
	if door.is_empty():
		return false
	_enter(door)
	return true


func _search(box: Dictionary) -> void:
	var now := Time.get_unix_time_from_system()
	if float(looted.get(box["key"], 0.0)) > now:
		_world.emit_signal("toast", "Nothing left in here for now.", Color(1, 1, 1, 0.8))
		return
	var rules: RefCounted = _world.get("interiors")
	var found: Dictionary = rules.call("roll", String(box["loot"]), _rng)
	looted[box["key"]] = now + float(rules.call("refill_seconds", String(box["loot"])))
	_world.call("sound", "ui_open")
	for item: String in found:
		_world.call("give", item, int(found[item]))
	_world.emit_signal("changed")


# --- the room behind a door ---

func _enter(door: Dictionary) -> void:
	var rules: RefCounted = _world.get("interiors")
	var item: Dictionary = door["item"]
	var cfg: Dictionary = _world.data["interiors"]
	var half: Vector2 = rules.call("half_size", String(item["model"]))
	var high := float(cfg["room_height"])
	var def: Dictionary = cfg["rooms"][String(door["kind"])]
	_anchor = Vector3(door["at"].x, _world.terrain.height(door["at"].x, door["at"].y), door["at"].y)
	_outside = _world.call("world_of", _anchor + Vector3(0.0, 0.3, 0.0))
	_room = Node3D.new()
	_room.position = Vector3(float(item["x"]) + float(cfg["offset"][0]), float(cfg["offset"][1]), float(item["z"]) + float(cfg["offset"][2]))
	add_child(_room)
	var wall_tint: Array = def["wall_color"]
	var wall := FantasyModels.tinted(String(def["wall"]), Color(wall_tint[0], wall_tint[1], wall_tint[2]) * 0.8)
	var floor_look: Array = FLOORS[String(def["floor"])]
	var ground := FantasyModels.tinted(String(floor_look[0]), floor_look[1])
	var timber := FantasyModels.tinted("timber", Color(0.3, 0.22, 0.15))
	var body := StaticBody3D.new()
	_room.add_child(body)
	_slab(body, ground, Vector3(half.x * 2.0 + 0.6, 0.3, half.y * 2.0 + 0.6), Vector3(0, -0.15, 0), true)
	_slab(body, timber, Vector3(half.x * 2.0 + 0.6, 0.2, half.y * 2.0 + 0.6), Vector3(0, high + 0.1, 0), false)
	for side: float in [-1.0, 1.0]:
		_slab(body, wall, Vector3(half.x * 2.0 + 0.6, high, 0.3), Vector3(0, high * 0.5, side * (half.y + 0.15)), true)
		_slab(body, wall, Vector3(0.3, high, half.y * 2.0), Vector3(side * (half.x + 0.15), high * 0.5, 0), true)
		_window(Vector3(side * half.x, 1.75, 0.0), side, timber)
	for k in 3:  # beams under the ceiling
		_slab(body, timber, Vector3(0.2, 0.22, half.y * 2.0), Vector3(half.x * (float(k) - 1.0) * 0.6, high - 0.11, 0), false)
	_slab(body, timber, Vector3(1.3, 2.15, 0.1), Vector3(0, 1.075, -half.y + 0.05), false)  # the door, on the front wall
	_exit = _room.global_position + Vector3(0.0, 0.0, -half.y + 0.7)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.84, 0.64)
	lamp.light_energy = 1.5
	lamp.omni_range = maxf(half.x, half.y) * 2.0 + 3.0
	lamp.position = Vector3(0.0, high - 0.6, 0.0)
	_room.add_child(lamp)
	_room_boxes.clear()
	_room_stations.clear()
	var pieces: Array = rules.call("furniture", String(door["kind"]), half)
	for i in pieces.size():
		var piece: Dictionary = pieces[i]
		var plain := String(piece["loot"]) == "" and String(piece["station"]) == ""
		if plain and float(i % 10) / 10.0 >= prop_share:
			continue
		var made := FantasyModels.scene(String(piece["model"]))
		if made == null:
			continue
		made.position = Vector3(float(piece["x"]), 0.0, float(piece["z"]))
		made.rotation.y = float(piece["turn"])
		_room.add_child(made)
		var at := _room.global_position + made.position
		if String(piece["loot"]) != "":
			_room_boxes.append({"at": at, "loot": String(piece["loot"]), "key": "%s:%d" % [door["key"], i], "model": String(piece["model"])})
		if String(piece["station"]) != "":
			_room_stations.append({"at": at, "kind": String(piece["station"])})
	_world.call("set_indoors", true)
	faded.emit()
	_player.call("teleport", _exit + Vector3(0.0, 0.2, 0.3), 0.0)
	_player.call("look_at_point", _room.global_position + Vector3(0.0, 1.5, half.y))
	_world.emit_signal("notice", _name("building", String(door["kind"])))
	_world.call("sound", "ui_open")


func _leave() -> void:
	faded.emit()
	_player.call("teleport", _outside, 0.0)
	_world.call("sound", "ui_close")
	reset()
	_near = "?"


# One box of the room's shell: drawn, and solid when `solid`.
func _slab(body: StaticBody3D, look: Material, size: Vector3, at: Vector3, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var drawn := MeshInstance3D.new()
	drawn.mesh = mesh
	drawn.material_override = look
	drawn.position = at
	_room.add_child(drawn)
	if solid:
		var shape := CollisionShape3D.new()
		var block := BoxShape3D.new()
		block.size = size
		shape.shape = block
		shape.position = at
		body.add_child(shape)


# A window on a side wall: a small picture of the land outside behind a timber cross.
func _window(at: Vector3, side: float, timber: Material) -> void:
	var pane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.1)
	pane.mesh = quad
	var view := StandardMaterial3D.new()
	view.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view.albedo_texture = _view()
	pane.material_override = view
	pane.position = at - Vector3(side * 0.01, 0.0, 0.0)
	pane.rotation.y = -side * PI * 0.5
	_room.add_child(pane)
	for bar: Array in [[Vector3(0.06, 1.2, 0.07), Vector3.ZERO], [Vector3(0.06, 0.07, 1.4), Vector3.ZERO], [Vector3(0.08, 0.1, 1.5), Vector3(0, 0.6, 0)], [Vector3(0.08, 0.1, 1.5), Vector3(0, -0.6, 0)],
			[Vector3(0.08, 1.3, 0.1), Vector3(0, 0, 0.7)], [Vector3(0.08, 1.3, 0.1), Vector3(0, 0, -0.7)]]:
		var mesh := BoxMesh.new()
		mesh.size = bar[0]
		var drawn := MeshInstance3D.new()
		drawn.mesh = mesh
		drawn.material_override = timber
		drawn.position = at - Vector3(side * 0.03, 0.0, 0.0) + (bar[1] as Vector3)
		_room.add_child(drawn)


# The picture in the windows: this region's sky, far hills, the ground outside and a couple of roofs, painted once per room.
func _view() -> ImageTexture:
	var terrain: RefCounted = _world.terrain
	var mood: Dictionary = terrain.mood(_anchor.x, _anchor.z)
	var land: Color = terrain.color(_anchor.x, _anchor.z, _anchor.y, 0.0)
	var top: Color = mood["sky_top"]
	var low: Color = mood["sky_horizon"]
	var image := Image.create(64, 54, false, Image.FORMAT_RGB8)
	for y in 54:
		var row := top.lerp(low, clampf(float(y) / 30.0, 0.0, 1.0))
		if y >= 38:
			row = land.lerp(low, 0.25).darkened(0.15 * float(y - 38) / 16.0)
		image.fill_rect(Rect2i(0, y, 64, 1), row)
	for x in 64:  # far hills along the horizon
		var rise := int(4.0 + 3.0 * sin(float(x) * 0.21 + _anchor.x) + 2.0 * sin(float(x) * 0.5 + _anchor.z))
		image.fill_rect(Rect2i(x, 38 - rise, 1, rise), land.lerp(low, 0.6))
	for house: Array in [[8, 30, 14, 9], [40, 32, 11, 7]]:  # two roofs across the way
		image.fill_rect(Rect2i(int(house[0]), int(house[1]), int(house[2]), int(house[3])), Color(0.8, 0.76, 0.66).lerp(low, 0.3))
		for step in 5:
			image.fill_rect(Rect2i(int(house[0]) - 1 + step, int(house[1]) - 1 - step, int(house[2]) + 2 - step * 2, 1), Color(0.36, 0.27, 0.2).lerp(low, 0.3))
	return ImageTexture.create_from_image(image)
