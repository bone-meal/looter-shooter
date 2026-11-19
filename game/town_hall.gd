# Purpose: inside the home port's TROPHY HALL (sea step 7b-4; director 2026-11-17: real interiors, built like the
# hub's trophy room): six cabinets (game/trophy_room.gd) with the session's players' achievements from level 1; from
# level 2 the CASES of the eight archaeology collections (a player puts a completed collection's trophy from his bag
# into its case; the cases belong to the host's world); from level 3 the BOSS PLINTHS, one per sea region (empty, with
# ??? plaques, until the sea's bosses of step 10 give trophies); at level 4 the CREW'S LEGEND board (everyone in the
# session: level and trophies, and the port's own record). Lamps burn inside only while the player is near. Looking at
# a trophy, a case, a plinth or the board shows a card (game/hub_hud.gd's).
# Dependencies: game/trophy_room.gd, game/fantasy_models.gd, data/sea/town.json "hall", markers in the trophy hall's
# models (tools/blender/sea_town.py: Cab_<yaw>_<n>, Cases, Plinths, Legend, Lamp_<n>).
extends Node3D

const TrophyRoom = preload("res://game/trophy_room.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")

const CASE_REACH := 1.6  # m from a case to put a trophy in or read it
const LOOK_REACH := 3.5
const BRASS := Color(0.78, 0.6, 0.28)

var town: Node3D  # game/sea_town.gd
var cases := {}  # collection id -> name of the player who put its trophy in (the host's world, saved)
var room: TrophyRoom
var _model: Node3D
var _level := 0
var _cfg: Dictionary
var _case_spots: Array = []  # [collection id, Node3D jar (its piece inside), Label3D plaque]
var _plinths: Array = []  # [region number, Node3D plinth, Label3D plaque, Node3D trophy piece or null]
var plinths := {}  # region number (as text) -> name of the player who set its boss's trophy there (the host's world, saved)
var _bosses := {}  # region number -> its boss in data/sea/bosses.json (sea step 10)
var _legend: Label3D
var _lamps: Array = []
var _wait := 0.0
var _glass: StandardMaterial3D
var _wood: StandardMaterial3D
var _velvet: StandardMaterial3D
var _brass: StandardMaterial3D
var _stone: StandardMaterial3D


func _init() -> void:
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/bosses.json"))
	for id: String in all["bosses"]:
		var b: Dictionary = all["bosses"][id]
		_bosses[int(b.get("region", 0))] = b
	_glass = _mat(Color(0.75, 0.85, 0.9, 0.18))
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.roughness = 0.05
	_glass.metallic_specular = 0.9
	_wood = _mat(Color(0.3, 0.19, 0.11))
	_velvet = _mat(Color(0.42, 0.08, 0.1))
	_velvet.roughness = 0.9
	_brass = _mat(BRASS)
	_brass.metallic = 0.5
	_brass.roughness = 0.35
	_stone = _mat(Color(0.7, 0.67, 0.6))


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func collections() -> Array:
	return _cfg.get("collections", [])


# The trophy hall's model was put up (a new level): fill it. The pieces are children of the model, so they go with it.
func fit(model: Node3D, level: int, cfg: Dictionary) -> void:
	_cfg = cfg
	_model = model
	_level = level
	_case_spots.clear()
	_plinths.clear()
	_lamps.clear()
	_legend = null
	room = null
	if model == null or level < 1:
		return
	var cabinets: Array = []
	for found in model.find_children("Cab_*", "", true, false):
		var at := model.to_local((found as Node3D).global_position)
		cabinets.append([at.x, at.z, float(String(found.name).split("_")[1]), at.y])
	cabinets.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	room = TrophyRoom.new()
	room.cfg = {"cabinets": cabinets}
	model.add_child(room)
	for k in range(1, 9):
		var spot := model.find_child("Lamp_%d" % k, true, false) as Node3D
		if spot == null:
			break
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.8, 0.55)
		lamp.light_energy = float(cfg.get("lamp_energy", 1.4))
		lamp.omni_range = float(cfg.get("lamp_range", 9.0))
		lamp.shadow_enabled = false
		lamp.visible = false
		spot.add_child(lamp)
		_lamps.append(lamp)
		_lantern(spot)
	var mark := model.find_child("Cases", true, false) as Node3D
	if mark != null and level >= 2:
		_build_cases(mark)
	mark = model.find_child("Plinths", true, false) as Node3D
	if mark != null and level >= 3:
		_build_plinths(mark)
	mark = model.find_child("Legend", true, false) as Node3D
	if mark != null and level >= 4:
		_build_legend(mark)
	show_cases()


# A brass ceiling lamp where each light hangs (its glow carries the light; the OmniLight is the real one).
func _lantern(spot: Node3D) -> void:
	var cup := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.radial_segments = 16
	m.rings = 1
	m.top_radius = 0.08
	m.bottom_radius = 0.28
	m.height = 0.22
	cup.mesh = m
	cup.material_override = _brass
	cup.position = Vector3(0, 0.2, 0)
	spot.add_child(cup)
	var bulb := MeshInstance3D.new()
	var b := SphereMesh.new()
	b.radius = 0.12
	b.height = 0.24
	b.radial_segments = 12  # (the defaults made 32k triangles a sphere: 830k for the hall's few lamps and bells)
	b.rings = 6
	bulb.mesh = b
	var glow := _mat(Color(1.0, 0.86, 0.6))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb.material_override = glow
	bulb.position = Vector3(0, 0.06, 0)
	spot.add_child(bulb)
	var chain := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.radial_segments = 6
	c.rings = 1
	c.top_radius = 0.015
	c.bottom_radius = 0.015
	c.height = 0.6
	chain.mesh = c
	chain.material_override = _brass
	chain.position = Vector3(0, 0.6, 0)
	spot.add_child(chain)


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shown := MeshInstance3D.new()
	shown.mesh = mesh
	shown.material_override = mat
	shown.position = at
	parent.add_child(shown)
	return shown


func _solid(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	parent.add_child(body)


func _plaque(parent: Node3D, text: String, at: Vector3, size := 28) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.0022
	label.outline_size = 0
	label.modulate = Color(0.16, 0.1, 0.04)
	label.position = at
	parent.add_child(label)
	return label


# The collections' table: two rows of four glass bells on velvet, a brass plaque before each.
func _build_cases(mark: Node3D) -> void:
	var table := Node3D.new()
	mark.add_child(table)
	_box(table, Vector3(5.0, 0.08, 1.5), Vector3(0, 0.9, 0), _wood)
	_box(table, Vector3(4.8, 0.02, 1.36), Vector3(0, 0.95, 0), _velvet)
	for x in [-2.3, 2.3]:
		for z in [-0.6, 0.6]:
			_box(table, Vector3(0.12, 0.9, 0.12), Vector3(x, 0.45, z), _wood)
	_box(table, Vector3(4.9, 0.12, 1.4), Vector3(0, 0.78, 0), _wood)
	_solid(table, Vector3(5.0, 1.0, 1.5), Vector3(0, 0.5, 0))
	var list := collections()
	for i in list.size():
		var row := 0 if i < 4 else 1
		var x := -1.8 + 1.2 * float(i % 4)
		var z := 0.32 if row == 0 else -0.32
		var jar := Node3D.new()
		jar.position = Vector3(x, 0.96, z)
		table.add_child(jar)
		var bell := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 20
		cyl.rings = 1
		cyl.top_radius = 0.2
		cyl.bottom_radius = 0.22
		cyl.height = 0.5
		bell.mesh = cyl
		bell.material_override = _glass
		bell.position = Vector3(0, 0.27, 0)
		jar.add_child(bell)
		var cap := MeshInstance3D.new()
		var dome := SphereMesh.new()
		dome.radius = 0.2
		dome.height = 0.2
		dome.is_hemisphere = true
		dome.radial_segments = 20
		dome.rings = 5
		cap.mesh = dome
		cap.material_override = _glass
		cap.position = Vector3(0, 0.52, 0)
		jar.add_child(cap)
		var base := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.radial_segments = 20
		disc.rings = 1
		disc.top_radius = 0.24
		disc.bottom_radius = 0.26
		disc.height = 0.04
		base.mesh = disc
		base.material_override = _brass
		base.position = Vector3(0, 0.02, 0)
		jar.add_child(base)
		var piece := FantasyModels.scene(String((list[i] as Dictionary).get("model", "trophy_statuette")))
		if piece != null:
			piece.name = "Piece"
			piece.scale = Vector3.ONE * 0.8
			piece.position = Vector3(0, 0.05, 0)
			jar.add_child(piece)
			_tint(piece, _color((list[i] as Dictionary).get("tint", [0.8, 0.65, 0.3])))
		var plaque := _plaque(table, "", Vector3(x, 0.99, z + (0.3 if row == 0 else -0.3)), 22)
		plaque.rotation_degrees = Vector3(-90, 0 if row == 0 else 180, 0)
		_case_spots.append([String((list[i] as Dictionary)["id"]), jar, plaque])


func _color(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


func _tint(node: Node, color: Color) -> void:
	var m := _mat(color)
	m.metallic = 0.4
	m.roughness = 0.35
	for found in node.find_children("*", "MeshInstance3D", true, false):
		(found as MeshInstance3D).material_override = m


# One plinth per sea region in an arc, each waiting for its super boss's trophy (sea step 10).
func _build_plinths(mark: Node3D) -> void:
	var count := int(_cfg.get("boss_plinths", 7))
	var names: Array = _cfg.get("region_names", [])
	for i in count:
		var a := deg_to_rad(-60.0 + 120.0 * float(i) / float(maxi(count - 1, 1)))
		var plinth := Node3D.new()
		plinth.position = Vector3(sin(a) * 4.2, 0, cos(a) * 1.6 - 1.0)
		plinth.rotation.y = a + PI
		mark.add_child(plinth)
		_box(plinth, Vector3(0.7, 0.12, 0.7), Vector3(0, 0.06, 0), _stone)
		_box(plinth, Vector3(0.5, 1.0, 0.5), Vector3(0, 0.62, 0), _stone)
		_box(plinth, Vector3(0.66, 0.1, 0.66), Vector3(0, 1.17, 0), _stone)
		_solid(plinth, Vector3(0.7, 1.2, 0.7), Vector3(0, 0.6, 0))
		var plaque := _plaque(plinth, "???\n%s" % (String(names[i]) if i < names.size() else "Region %d" % (i + 1)), Vector3(0, 0.75, 0.26), 20)
		var piece: Node3D = null
		var b: Dictionary = _bosses.get(i + 1, {})
		if not b.is_empty():  # (sea step 10) its boss's trophy, shown once someone has set it there
			piece = FantasyModels.scene(String(b.get("trophy_model", "trophy_statuette")))
			if piece != null:
				piece.position = Vector3(0, 1.22, 0)
				piece.scale = Vector3.ONE * 1.1
				piece.visible = false
				plinth.add_child(piece)
		_plinths.append([i + 1, plinth, plaque, piece])
	show_plinths()


# The crew's legend: a tall board on two posts by the door, facing into the hall.
func _build_legend(mark: Node3D) -> void:
	var board := Node3D.new()
	mark.add_child(board)
	for x in [-1.9, 1.9]:
		_box(board, Vector3(0.14, 2.8, 0.14), Vector3(x, 1.4, 0), _wood)
	_box(board, Vector3(3.9, 2.2, 0.08), Vector3(0, 1.6, 0), _wood)
	_box(board, Vector3(3.6, 1.95, 0.02), Vector3(0, 1.6, 0.05), _mat(Color(0.12, 0.2, 0.16)))
	_box(board, Vector3(4.0, 0.12, 0.14), Vector3(0, 2.76, 0), _brass)
	_solid(board, Vector3(4.0, 2.8, 0.3), Vector3(0, 1.4, 0))
	_legend = Label3D.new()
	_legend.font_size = 30
	_legend.pixel_size = 0.0028
	_legend.outline_size = 0
	_legend.modulate = Color(0.95, 0.85, 0.55)
	_legend.width = 1200.0
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD
	_legend.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_legend.position = Vector3(0, 2.45, 0.07)
	board.add_child(_legend)


# The boss trophies stand on their plinths once set there; the plaques name the boss and who brought it.
func show_plinths() -> void:
	var names: Array = _cfg.get("region_names", [])
	for spot: Array in _plinths:
		var n := int(spot[0])
		var have := plinths.has(str(n))
		if spot[3] != null:
			(spot[3] as Node3D).visible = have
		var region := String(names[n - 1]) if n - 1 < names.size() else "Region %d" % n
		var b: Dictionary = _bosses.get(n, {})
		(spot[2] as Label3D).text = ("%s\n%s" % [String(b.get("name", "?")), String(plinths[str(n)])]) if have else "???\n%s" % region


# The boss's trophy item for a plinth's region ("" = no boss there yet).
func plinth_trophy(n: int) -> String:
	return String((_bosses.get(n, {}) as Dictionary).get("trophy", ""))


func plinth_boss(n: int) -> String:
	return String((_bosses.get(n, {}) as Dictionary).get("name", ""))


# The plinth the player stands at and faces (they stand close together in their arc): its region number, or 0.
func plinth_near(at: Vector3, ahead: Vector3) -> int:
	var best := -1.0
	var found := 0
	for spot: Array in _plinths:
		var to := (spot[1] as Node3D).global_position - at
		to.y = 0.0
		if to.length() > CASE_REACH + 1.0:
			continue
		var facing := Vector2(ahead.x, ahead.z).normalized().dot(Vector2(to.x, to.z).normalized()) if to.length() > 0.2 else 1.0
		var score := facing - to.length() * 0.2
		if facing > 0.5 and score > best:
			best = score
			found = int(spot[0])
	return found


# The case pieces stand when their trophy was put in; the plaques say what goes there and who brought it.
func show_cases() -> void:
	for spot: Array in _case_spots:
		var id := String(spot[0])
		var have := cases.has(id)
		var piece := (spot[1] as Node3D).get_node_or_null("Piece") as Node3D
		if piece != null:
			piece.visible = have
		(spot[2] as Label3D).text = String(town.call("item_name", "trophy_" + id)) + ("\n" + String(cases[id]) if have else "\n(empty)")


func _process(delta: float) -> void:
	if _model == null or not is_instance_valid(_model) or _level < 1:
		return
	var player: Node3D = town.get("_player")
	var far := player.global_position.distance_to(_model.global_position)
	for lamp: OmniLight3D in _lamps:
		lamp.visible = far < float(_cfg.get("lamps_within", 11.0))
	if room != null:
		room.visible = far < float(_cfg.get("shown_within", 14.0))  # the trophies: only drawn inside (the walls hide them from outside)
	if far > float(_cfg.get("shown_within", 14.0)):
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 1.0
	var s: Node = town.call("session")
	if room != null and s != null and s.has_method("_trophy_owners"):
		room.show_owners(s.call("_trophy_owners"))
	if _legend != null:
		_legend.text = _legend_text(s)


func _legend_text(s: Node) -> String:
	var lines := PackedStringArray(["THE CREW'S LEGEND", ""])
	if s != null and s.has_method("_trophy_owners"):
		for who: Dictionary in s.call("_trophy_owners"):
			lines.append("%s  -  %d trophies" % [String(who.get("name", "")), (who.get("trophies", {}) as Dictionary).size()])
	var rules: RefCounted = town.get("rules")
	lines.append("")
	lines.append("The port grown to %d%%" % roundi(float(rules.call("growth")) * 100.0))
	lines.append("Collections on show: %d of %d" % [cases.size(), collections().size()])
	var fleet: Variant = (town.get("_sea") as Node).get("ships")
	if fleet != null:
		lines.append("Ships in the fleet: %d" % ((fleet as Node).get("ships") as Array).size())
	return "\n".join(lines)


# The case the player stands at: its collection id, or "".
func case_near(at: Vector3) -> String:
	var best := CASE_REACH
	var found := ""
	for spot: Array in _case_spots:
		var far := (spot[1] as Node3D).global_position.distance_to(at)
		if far <= best:  # the nearest: the bells stand 1.2 m apart
			best = far
			found = String(spot[0])
	return found


# What the player looks at in the hall (a card for game/hub_hud.gd), or {}.
func look(eye: Vector3, ahead: Vector3) -> Dictionary:
	if _model == null or not is_instance_valid(_model) or eye.distance_to(_model.global_position) > 25.0:
		return {}
	if room != null:
		var card := room.look(eye, ahead)
		if not card.is_empty():
			return card
	var best := 0.985
	var found := {}
	for spot: Array in _case_spots:
		var to := (spot[1] as Node3D).global_position + Vector3(0, 0.3, 0) - eye
		if to.length() < LOOK_REACH and to.normalized().dot(ahead) > best:
			best = to.normalized().dot(ahead)
			var id := String(spot[0])
			var line := String(town.call("lore_of", id))
			found = {"title": String(town.call("item_name", "trophy_" + id)), "line": line if cases.has(id) else "An empty case. Complete the collection at a restoration table, then bring its trophy here.",
				"owner": String(cases.get(id, "Nobody")) if cases.has(id) else "The crew", "tint": BRASS}
	for spot: Array in _plinths:
		var to := (spot[1] as Node3D).global_position + Vector3(0, 1.2, 0) - eye
		if to.length() < LOOK_REACH and to.normalized().dot(ahead) > best:
			best = to.normalized().dot(ahead)
			var n := int(spot[0])
			var b: Dictionary = _bosses.get(n, {})
			if plinths.has(str(n)):
				found = {"title": String(town.call("item_name", String(b["trophy"]))), "line": String(b.get("trophy_line", "")) + "  (%s)" % String(b["name"]), "owner": String(plinths[str(n)]), "tint": BRASS}
			else:
				found = {"title": "???", "line": ("A plinth for the trophy of %s. Beat it and set its trophy here." % String(b["name"])) if not b.is_empty() else "A plinth for the trophy of sea region %d's super boss." % n, "owner": "The crew", "tint": Color(0.6, 0.6, 0.58)}
	return found
