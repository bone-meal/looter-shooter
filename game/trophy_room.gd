# Purpose: the hub's trophy room (locked: diary/DECISIONS_HUB.md; data/trophies.json): the room behind the hall's
# left doorway, six cabinets with brass name plates (and the character's playtime under them), one per player in the
# session. What each shows is the player's own choice (polish1 item 16, core/trophy_shelves.gd): 5 podium spots he can
# switch, the eye-level row of pinned favourites (the hardest fill the rest), 10 shelves each turned to a page of the
# other achievements by its brass button. Unique shapes for the hardest, common shapes tinted by difficulty for the
# rest; an unearned one is a dusty stand with ??? (its text = the hint). All trophies of one model are ONE MultiMesh
# across all cabinets. look() tells which trophy (or shelf button) the player looks at and what F does there.
# Dependencies: game/fantasy_models.gd (models by tools/blender/hub_trophies.py), game/jukebox.gd, core/trophy_shelves.gd,
# core/stat_book.gd, data/trophies.json,
# data/achievements.json, data/hub.json (`cfg`, set before add_child; this node sits at the hub's middle). The home
# port's trophy hall (game/town_hall.gd) uses it too: cfg = {"cabinets"} only (no room, lights or jukebox of its own).
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")
const Jukebox = preload("res://game/jukebox.gd")
const StatBook = preload("res://core/stat_book.gd")
const TrophyShelves = preload("res://core/trophy_shelves.gd")

const SLOT_ROWS := [0, 1, 2, 4, 5]  # the shelves' rows in each wing, bottom first (row 3 = eye level: the pinned row)
const PER_ROW := 24
const PODIUM_X := [-0.32, -0.17, 0.0, 0.17, 0.32]  # (polish1 item 16) five podium spots, the middle one biggest
const PODIUM_Z := [0.16, 0.2, 0.25, 0.2, 0.16]
const PODIUM_SIZES := [1.15, 1.4, 1.8, 1.4, 1.15]
const BUTTON_X := 2.475  # each shelf's brass button on the wing's outer post (tools/blender/hub_trophies.py cabinet)
const BUTTON_UP := 0.06
const BUTTON_OUT := 0.52
const ACTS := {"pin": "Pin it to the eye-level row", "unpin": "Take it off the eye-level row", "podium": "Change this podium trophy", "shelf": "Show other achievements on this shelf"}
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
var _cabinets: Array = []  # [Transform3D (hub-local), Label3D]
var _shown: Array = []  # per cabinet: {owner, name, trophies {id: date}}
var _sig := ""
var _material := StandardMaterial3D.new()
var _drawn: Dictionary = {}  # model id -> MultiMeshInstance3D
var _where: Array = []  # [world position, cabinet index, achievement id, role ("podium" / "eye" / "row"), spot] of every filled slot
var _layouts: Array = []  # per cabinet: core/trophy_shelves.gd layout() of what it shows


func _ready() -> void:
	_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/trophies.json"))
	_achievements = (JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json")) as Dictionary)["achievements"]
	_material.vertex_color_use_as_albedo = true
	_material.metallic = 0.15  # (fully metallic goes black on Compatibility)
	_material.roughness = 0.4
	for spot: Array in cfg["cabinets"]:  # [x, z, yaw degrees, (y: the home port's halls stand on a raised floor)]
		var at := Transform3D(Basis(Vector3.UP, deg_to_rad(float(spot[2]))), Vector3(float(spot[0]), float(spot[3]) if spot.size() > 3 else 0.0, float(spot[1])))
		var made := FantasyModels.scene("hub_cabinet")
		if made != null:
			made.transform = at
			add_child(made)
		var plate := Label3D.new()
		plate.pixel_size = 0.0022
		plate.font_size = 40
		plate.outline_size = 0
		plate.modulate = Color(0.12, 0.08, 0.03)
		plate.position = at * Vector3(0.0, 2.425, 0.515)
		plate.rotation.y = deg_to_rad(float(spot[2]))
		add_child(plate)
		var time_plate := plate.duplicate() as Label3D  # (polish1 item 135) the character's playtime under the name
		time_plate.font_size = 24
		time_plate.position = at * Vector3(0.0, 2.365, 0.515)
		add_child(time_plate)
		_cabinets.append([at, plate, time_plate])
		_solid(at, Vector3(5.0, 2.7, 0.5), Vector3(0.0, 1.35, 0.25))
		_shown.append({})
		_layouts.append({})
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


# Where a trophy stands in a cabinet: [local position, scale] for a podium spot, an eye-level place or a shelf place
# (shelf s: wing s / 5, row SLOT_ROWS[s % 5]).
func _place(role: String, spot: int) -> Array:
	if role == "podium":
		return [Vector3(float(PODIUM_X[spot]), PODIUM_Y, float(PODIUM_Z[spot])), float(PODIUM_SIZES[spot])]
	if role == "eye":
		return [Vector3(_slot_x(spot), SHELF_Y + SHELF_STEP * 3.0, 0.27), 1.0]
	var s := floori(float(spot) / float(TrophyShelves.PER_SHELF))
	var k := spot % TrophyShelves.PER_SHELF
	var wing := floori(float(s) / float(SLOT_ROWS.size()))
	return [Vector3(_slot_x(k + wing * TrophyShelves.PER_SHELF), SHELF_Y + SHELF_STEP * float(SLOT_ROWS[s % SLOT_ROWS.size()]), 0.27), 1.0]


# A shelf's button, in the cabinet's own space.
func _button_at(s: int) -> Vector3:
	var wing := floori(float(s) / float(SLOT_ROWS.size()))
	return Vector3(BUTTON_X * (1.0 if wing == 1 else -1.0), SHELF_Y + SHELF_STEP * float(SLOT_ROWS[s % SLOT_ROWS.size()]) + BUTTON_UP, BUTTON_OUT)


# (dev, tools/dev_boot.gd !shelf) [world point of a podium spot / eye place / shelf place / shelf button ("button", s) / the name plate ("plate"),
# world point 1.1 m in front of it] in cabinet c.
func dev_point(c: int, role: String, spot: int) -> Array:
	var at: Transform3D = _cabinets[c][0]
	var local: Vector3 = _button_at(spot) if role == "button" else (Vector3(0.0, 2.4, 0.515) if role == "plate" else (_place(role, spot)[0] as Vector3) + Vector3(0.0, 0.07, 0.0))
	var target := global_transform * (at * local)
	return [target, target + (global_transform.basis * at.basis * Vector3(0.0, 0.0, 1.1))]


# The trophy data (data/trophies.json) the shelves are laid out from.
func data() -> Dictionary:
	return _data


func _slot_x(i: int) -> float:
	var half := PER_ROW >> 1
	var step := (2.42 - WING_IN) / float(half)
	var k := i % half
	var x := WING_IN + step * (float(k) + 0.5)
	return -x if i < half else x


# owners = up to 6 [{owner (peer), name, trophies {achievement id: date}}], in cabinet order. Rebuilds the trophies only
# when something changed.
func show_owners(owners: Array) -> void:
	var bare: Array = []
	for c in _cabinets.size():  # (polish1 item 135) the playtime plates change every minute: set them without rebuilding
		var played := int((owners[c] as Dictionary).get("played", 0)) if c < owners.size() else 0
		(_cabinets[c][2] as Label3D).text = ("played " + StatBook.duration(float(played))) if played > 0 else ""
		if c < owners.size():
			var one := (owners[c] as Dictionary).duplicate()
			one.erase("played")
			bare.append(one)
	var sig := str(bare)
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
		var shelves := TrophyShelves.clean((_shown[c] as Dictionary).get("shelves", {}), _achievements)
		var lay := TrophyShelves.layout(_data, shelves, have)
		_layouts[c] = lay
		var places: Array = []  # [id, role, spot]
		for i in (lay["podium"] as Array).size():
			places.append([String(lay["podium"][i]), "podium", i])
		for i in (lay["eye"] as Array).size():
			places.append([String(lay["eye"][i]), "eye", i])
		for s in (lay["rows"] as Array).size():
			var row: Array = lay["rows"][s]
			for k in row.size():
				places.append([String(row[k]), "row", s * TrophyShelves.PER_SHELF + k])
		for one: Array in places:
			var id := String(one[0])
			if id == "":
				continue
			var slot := _place(String(one[1]), int(one[2]))
			var model := "trophy_stand"
			var tint := DUST
			if have.has(id):
				model = _model_of(id)
				tint = _tint_of(id)
			var place := at * Transform3D(Basis().scaled(Vector3.ONE * float(slot[1])), slot[0])
			if not by_model.has(model):
				by_model[model] = []
			(by_model[model] as Array).append([place, tint])
			_where.append([global_transform * (place.origin + Vector3(0.0, 0.07 * float(slot[1]), 0.0)), c, id, String(one[1]), int(one[2])])
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


# The trophy (or, in his own cabinet, the shelf button) the player looks at from `eye` along `ahead` (within 2 m), as
# text for the HUD; {} when none. `me` = the looker's peer: in his own cabinet the card also carries "act" (what F does:
# {do: pin / unpin / podium / shelf, id / spot / shelf}) and "act_text".
func look(eye: Vector3, ahead: Vector3, me := -1) -> Dictionary:
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
	var button := -1
	var button_c := -1
	for c in _cabinets.size():  # (polish1 item 16) shelf buttons, own cabinet only
		if me < 0 or int((_shown[c] as Dictionary).get("owner", -2)) != me:
			continue
		for s in TrophyShelves.SHELVES:
			var to: Vector3 = global_transform * ((_cabinets[c][0] as Transform3D) * _button_at(s)) - eye
			var far := to.length()
			if far > LOOK_REACH or far < 0.05:
				continue
			var facing := to.dot(ahead) / far
			if facing > best:
				best = facing
				button = s
				button_c = c
	if button >= 0:
		var lay: Dictionary = _layouts[button_c]
		var page := int(TrophyShelves.clean((_shown[button_c] as Dictionary).get("shelves", {}), _achievements)["pages"][button]) % maxi(int(lay.get("pages", 1)), 1)
		return {"title": "Shelf button", "line": "Page %d of %d: press to show other achievements here" % [page + 1, int(lay.get("pages", 1))],
			"owner": String((_shown[button_c] as Dictionary).get("name", "")), "tint": Color(0.85, 0.65, 0.3), "act": {"do": "shelf", "shelf": button}, "act_text": ACTS["shelf"]}
	if found.is_empty():
		return {}
	var id := String(found[2])
	var who: Dictionary = _shown[int(found[1])]
	var a: Dictionary = _achievements.get(id, {})
	var have: Dictionary = who.get("trophies", {})
	var card := {}
	if not have.has(id):
		card = {"title": "???", "line": "Hint: " + String(a.get("desc", "")), "owner": String(who.get("name", "")), "tint": DUST}
	else:
		var day := String(have[id])
		card = {"title": String(a.get("name", id)), "line": String(a.get("desc", "")), "owner": String(who.get("name", "")),
			"date": ("Earned " + day) if day != "" else "Earned before dates were kept", "tint": _tint_of(id)}
	if me >= 0 and int(who.get("owner", -2)) == me:
		var act := {}
		var role := String(found[3])
		if role == "podium" and not have.is_empty():
			act = {"do": "podium", "spot": int(found[4])}
		elif have.has(id):
			act = {"do": "unpin" if TrophyShelves.is_pinned(TrophyShelves.clean(who.get("shelves", {}), _achievements), id) else "pin", "id": id}
		if not act.is_empty():
			card["act"] = act
			card["act_text"] = ACTS[String(act["do"])]
	return card


func _solid(at: Transform3D, size: Vector3, middle: Vector3) -> void:
	var body := StaticBody3D.new()
	body.transform = at * Transform3D(Basis.IDENTITY, middle)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
