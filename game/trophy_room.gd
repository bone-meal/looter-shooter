# Purpose: the hub's trophy room (locked: diary/DECISIONS_HUB.md; data/trophies.json): the room behind the hall's
# left doorway, six cabinets with brass name plates, one per player in the session, every achievement in the same
# place in each: the hardest at eye level with their own shapes, the 3 hardest of all on the lit centre podium, the
# rest in common shapes tinted by difficulty; an unearned one is a dusty stand with ??? (its text = the hint). All
# trophies of one model are ONE MultiMesh across all cabinets. look() tells which trophy the player looks at.
# Dependencies: game/fantasy_models.gd (models by tools/blender/hub_trophies.py), game/jukebox.gd, data/trophies.json,
# data/achievements.json, data/hub.json (`cfg`, set before add_child; this node sits at the hub's middle). The home
# port's trophy hall (game/town_hall.gd) uses it too: cfg = {"cabinets"} only (no room, lights or jukebox of its own).
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")
const Jukebox = preload("res://game/jukebox.gd")

const SLOT_ROWS := [0, 1, 2, 4, 5]  # the shelves the common trophies fill, bottom first (row 3 = eye level = middle_row)
const PER_ROW := 24
const WING_IN := 0.5  # x of a wing's inner edge; slots run out to 2.42
const SHELF_Y := 0.35
const SHELF_STEP := 0.38
const PODIUM_Y := 1.12
const PODIUM_SCALE := 1.8
const DUST := Color(0.55, 0.55, 0.52)
const LOOK_REACH := 2.0
const LOOK_ANGLE := 0.992  # cosine: about 7 degrees off the view line

var cfg: Dictionary
var jukebox: Node3D
var _data: Dictionary
var _achievements: Dictionary
var _slots: Dictionary = {}  # achievement id -> [local position in a cabinet, scale]
var _cabinets: Array = []  # [Transform3D (hub-local), Label3D]
var _shown: Array = []  # per cabinet: {owner, name, trophies {id: date}}
var _sig := ""
var _material := StandardMaterial3D.new()
var _drawn: Dictionary = {}  # model id -> MultiMeshInstance3D
var _where: Array = []  # [world position, cabinet index, achievement id] of every filled slot


func _ready() -> void:
	_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/trophies.json"))
	_achievements = (JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json")) as Dictionary)["achievements"]
	_material.vertex_color_use_as_albedo = true
	_material.metallic = 0.15  # (fully metallic goes black on Compatibility)
	_material.roughness = 0.4
	_lay_out_slots()
	for spot: Array in cfg["cabinets"]:  # [x, z, yaw degrees, (y: the home port's halls stand on a raised floor)]
		var at := Transform3D(Basis(Vector3.UP, deg_to_rad(float(spot[2]))), Vector3(float(spot[0]), float(spot[3]) if spot.size() > 3 else 0.0, float(spot[1])))
		var made := FantasyModels.scene("hub_cabinet")
		if made != null:
			made.transform = at
			add_child(made)
		var plate := Label3D.new()
		plate.pixel_size = 0.0022
		plate.font_size = 48
		plate.outline_size = 0
		plate.modulate = Color(0.12, 0.08, 0.03)
		plate.position = at * Vector3(0.0, 2.4, 0.515)
		plate.rotation.y = deg_to_rad(float(spot[2]))
		add_child(plate)
		_cabinets.append([at, plate])
		_solid(at, Vector3(5.0, 2.7, 0.5), Vector3(0.0, 1.35, 0.25))
		_shown.append({})
	if not cfg.has("trophy_room_middle"):  # the home port's trophy hall (game/town_hall.gd) is its own building
		return
	var r: Array = cfg["trophy_room_middle"]  # the room's own middle (its floor rect "trophy_room" also takes in the doorway)
	var middle := Vector3(float(r[0]), 0.0, float(r[1]))
	var shell := FantasyModels.scene("hub_trophy_room")
	if shell != null:
		shell.position = middle
		add_child(shell)
	var j: Array = cfg["jukebox"]
	jukebox = Jukebox.new()
	jukebox.position = Vector3(float(j[0]), 0.0, float(j[1]))
	jukebox.rotation.y = deg_to_rad(float(j[2]))
	add_child(jukebox)
	# Warm lights: one in the middle (the hall's one mesh then has 8 lights, the Compatibility limit per object) and two
	# by the west wall that stay out of the hall.
	for spot: Array in [[middle + Vector3(0.0, 4.3, 0.0), 2.4, 10.0], [middle + Vector3(-4.0, 3.6, -5.0), 1.8, 6.5], [middle + Vector3(-4.0, 3.6, 5.0), 1.8, 6.5]]:
		var lamp := OmniLight3D.new()
		lamp.position = spot[0]
		lamp.light_color = Color(1.0, 0.78, 0.5)
		lamp.light_energy = float(spot[1])
		lamp.omni_range = float(spot[2])
		lamp.omni_attenuation = 0.9
		lamp.shadow_enabled = false
		add_child(lamp)
	var t: Array = cfg["trophy_room"]
	var w := float(t[2]) - float(t[0])
	var d := float(t[3]) - float(t[1])
	_solid(Transform3D.IDENTITY, Vector3(w + 1.0, 1.0, d + 1.0), Vector3((float(t[0]) + float(t[2])) * 0.5, -0.5, middle.z))  # floor
	_solid(Transform3D.IDENTITY, Vector3(1.0, 5.0, d + 2.0), Vector3(float(t[0]) - 0.5, 2.5, middle.z))  # walls
	_solid(Transform3D.IDENTITY, Vector3(w + 2.0, 5.0, 1.0), Vector3(middle.x, 2.5, float(t[1]) - 0.5))
	_solid(Transform3D.IDENTITY, Vector3(w + 2.0, 5.0, 1.0), Vector3(middle.x, 2.5, float(t[3]) + 0.5))
	_solid(Transform3D.IDENTITY, Vector3(w + 2.0, 1.0, d + 2.0), middle + Vector3(0.0, 5.5, 0.0))


# Where each achievement stands in a cabinet (the same place in all of them).
func _lay_out_slots() -> void:
	var podium: Array = _data["pedestal"]
	for i in podium.size():
		_slots[String(podium[i])] = [Vector3((float(i) - 1.0) * 0.27, PODIUM_Y, 0.25), PODIUM_SCALE]
	var middle: Array = _data["middle_row"]
	for i in middle.size():
		_slots[String(middle[i])] = [Vector3(_slot_x(i), SHELF_Y + SHELF_STEP * 3.0, 0.27), 1.0]
	var n := 0
	for id: String in _data["trophies"]:
		var row: int = SLOT_ROWS[mini(floori(float(n) / float(PER_ROW)), SLOT_ROWS.size() - 1)]
		_slots[id] = [Vector3(_slot_x(n % PER_ROW), SHELF_Y + SHELF_STEP * float(row), 0.27), 1.0]
		n += 1


func _slot_x(i: int) -> float:
	var half := PER_ROW >> 1
	var step := (2.42 - WING_IN) / float(half)
	var k := i % half
	var x := WING_IN + step * (float(k) + 0.5)
	return -x if i < half else x


# owners = up to 6 [{owner (peer), name, trophies {achievement id: date}}], in cabinet order. Rebuilds the trophies only
# when something changed.
func show_owners(owners: Array) -> void:
	var sig := str(owners)
	if sig == _sig:
		return
	_sig = sig
	var by_model := {}  # model id -> [[Transform3D, Color]]
	_where.clear()
	for c in _cabinets.size():
		var plate: Label3D = _cabinets[c][1]
		_shown[c] = owners[c] if c < owners.size() else {}
		plate.text = String((_shown[c] as Dictionary).get("name", ""))
		if (_shown[c] as Dictionary).is_empty():
			continue
		var at: Transform3D = _cabinets[c][0]
		var have: Dictionary = (_shown[c] as Dictionary).get("trophies", {})
		for id: String in _slots:
			var slot: Array = _slots[id]
			var model := "trophy_stand"
			var tint := DUST
			if have.has(id):
				model = _model_of(id)
				tint = _tint_of(id)
			var place := at * Transform3D(Basis().scaled(Vector3.ONE * float(slot[1])), slot[0])
			if not by_model.has(model):
				by_model[model] = []
			(by_model[model] as Array).append([place, tint])
			_where.append([global_transform * (place.origin + Vector3(0.0, 0.07 * float(slot[1]), 0.0)), c, id])
	for model: String in _drawn:
		(_drawn[model] as Node).visible = by_model.has(model)
	for model: String in by_model:
		var list: Array = by_model[model]
		if not _drawn.has(model):
			var mesh := FantasyModels.mesh(model)
			if mesh == null:
				continue
			var shown := MultiMeshInstance3D.new()
			shown.multimesh = MultiMesh.new()
			shown.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			shown.multimesh.use_colors = true
			shown.multimesh.mesh = mesh
			shown.material_override = _material
			add_child(shown)
			_drawn[model] = shown
		var many: MultiMesh = (_drawn[model] as MultiMeshInstance3D).multimesh
		many.instance_count = list.size()
		for i in list.size():
			many.set_instance_transform(i, list[i][0])
			many.set_instance_color(i, list[i][1])
		(_drawn[model] as Node).visible = true


func _model_of(id: String) -> String:
	var unique: Dictionary = _data["unique"]
	if unique.has(id):
		return String((unique[id] as Dictionary)["model"])
	return "trophy_" + String((_data["trophies"][id] as Dictionary)["shape"])


func _tint_of(id: String) -> Color:
	var unique: Dictionary = _data["unique"]
	var rgb: Array = (unique[id] as Dictionary)["tint"] if unique.has(id) else _data["tiers"][String((_data["trophies"][id] as Dictionary)["tier"])]
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


# The trophy the player looks at from `eye` along `ahead` (within 2 m), as text for the HUD; {} when none.
func look(eye: Vector3, ahead: Vector3) -> Dictionary:
	var best := LOOK_ANGLE
	var found: Array = []
	for spot: Array in _where:
		var to: Vector3 = (spot[0] as Vector3) - eye
		var far := to.length()
		if far > LOOK_REACH or far < 0.05:
			continue
		var facing := to.dot(ahead) / far
		if facing > best:
			best = facing
			found = spot
	if found.is_empty():
		return {}
	var id := String(found[2])
	var who: Dictionary = _shown[int(found[1])]
	var a: Dictionary = _achievements.get(id, {})
	var have: Dictionary = who.get("trophies", {})
	if not have.has(id):
		return {"title": "???", "line": "Hint: " + String(a.get("desc", "")), "owner": String(who.get("name", "")), "tint": DUST}
	var day := String(have[id])
	return {"title": String(a.get("name", id)), "line": String(a.get("desc", "")), "owner": String(who.get("name", "")),
		"date": ("Earned " + day) if day != "" else "Earned before dates were kept", "tint": _tint_of(id)}


func _solid(at: Transform3D, size: Vector3, middle: Vector3) -> void:
	var body := StaticBody3D.new()
	body.transform = at * Transform3D(Basis.IDENTITY, middle)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
