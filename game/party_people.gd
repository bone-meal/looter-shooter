# Purpose: the club's people (dancers, stage performers, DJ, bartender, seated patrons): builds blocky characters and animates all of them plus the floor lights, disco ball and sign.
# With the character packs installed the people are rigged bodies (game/rigged_body.gd) standing in one still pose;
# the same animation code turns their joints through the handle nodes of game/rigged_pose.gd.
# Dependencies: game/rigged_body.gd, game/npc_body.gd, game/appearance_data.gd. game/club_island.gd creates one of these, adds people with add_person(), and sets tiles/ball/sign.
extends Node3D

const RiggedBody = preload("res://game/rigged_body.gd")
const NpcBody = preload("res://game/npc_body.gd")
const AppearanceData = preload("res://game/appearance_data.gd")

const TILE_COLORS := [Color(1.0, 0.1, 0.6), Color(0.1, 0.9, 1.0), Color(0.6, 0.2, 1.0), Color(1.0, 0.8, 0.1), Color(0.2, 1.0, 0.5)]
const TILE_INTERVAL := 0.35
const HIDE_BEYOND := 150.0  # metres from the camera to the club people

var tiles: Array[StandardMaterial3D] = []  # dance-floor tile materials, recolored on a beat
var ball: Node3D  # disco ball (spins)
var sign_label: Label3D  # neon sign (flickers)

var _people: Array[Dictionary] = []  # {"node", "role", "phase"}
var _beat := 0.0
var _shown := true
var _time := 0.0
var _beat_index := 0


# role: "dancer", "performer", "dj", "bartender" or "sitter".
func add_person(person: Node3D, role: String, phase: float) -> void:
	_people.append({"node": person, "role": role, "phase": phase})


func _process(delta: float) -> void:
	_time += delta
	var camera := get_viewport().get_camera_3d()
	var near := camera == null or _people.is_empty() or camera.global_position.distance_squared_to((_people[0]["node"] as Node3D).global_position) < HIDE_BEYOND * HIDE_BEYOND
	if near != _shown:  # nobody can see the club from far away: hidden people cost nothing
		_shown = near
		for p in _people:
			(p["node"] as Node3D).visible = near
	if near:
		for p in _people:
			_animate(p["node"], p["role"], _time + p["phase"])
	if ball != null:
		ball.rotation.y += delta * 0.8
	if sign_label != null:
		sign_label.modulate.a = 0.85 + 0.15 * sin(_time * 9.0) * sin(_time * 2.3)
	_beat += delta
	if _beat >= TILE_INTERVAL and not tiles.is_empty():
		_beat = 0.0
		_beat_index += 1
		for i in tiles.size():
			tiles[i].albedo_color = TILE_COLORS[(i * 7 + _beat_index * 3) % TILE_COLORS.size()]


func _animate(person: Node3D, role: String, t: float) -> void:
	var body: Node3D = person.get_node("Body")
	var arm_l: Node3D = person.get_node("Body/ArmL")
	var arm_r: Node3D = person.get_node("Body/ArmR")
	var leg_l: Node3D = person.get_node("Body/LegL")
	var leg_r: Node3D = person.get_node("Body/LegR")
	match role:
		"dancer":
			body.position.y = absf(sin(t * 6.0)) * 0.08
			body.rotation.y = sin(t * 3.0) * 0.35
			arm_l.rotation = Vector3(2.3 + sin(t * 6.0) * 0.5, 0, -0.3)
			arm_r.rotation = Vector3(2.3 + sin(t * 6.0 + PI) * 0.5, 0, 0.3)
			leg_l.rotation.x = sin(t * 6.0) * 0.3
			leg_r.rotation.x = -sin(t * 6.0) * 0.3
		"performer":
			body.position.y = absf(sin(t * 4.0)) * 0.1
			body.rotation.y = sin(t * 2.0) * 0.6
			body.rotation.z = sin(t * 4.0) * 0.12
			arm_l.rotation = Vector3(0.0, 0, -2.4 + sin(t * 4.0) * 0.5)
			arm_r.rotation = Vector3(0.0, 0, 2.4 - sin(t * 4.0 + 1.0) * 0.5)
			leg_l.rotation.x = sin(t * 4.0) * 0.4
			leg_r.rotation.x = -sin(t * 4.0) * 0.4
		"dj":
			body.position.y = absf(sin(t * 5.0)) * 0.04
			person.get_node("Body/Head").rotation.x = sin(t * 5.0) * 0.18  # nodding to the beat
			arm_l.rotation = Vector3(1.2 + sin(t * 3.0) * 0.3, 0, 0.1)
			arm_r.rotation = Vector3(1.2 + sin(t * 9.0) * 0.4, 0, -0.1)  # scratching
		"bartender":
			arm_l.rotation = Vector3(1.0, 0, 0.1)  # holds the glass
			arm_r.rotation = Vector3(1.0 + sin(t * 3.0) * 0.35, 0, -0.15)  # wipes
			body.rotation.y = sin(t * 0.8) * 0.2
		"sitter":
			leg_l.rotation.x = 1.5  # seated: thighs forward
			leg_r.rotation.x = 1.5
			arm_r.rotation = Vector3(maxf(sin(t * 0.7), 0.0) * 2.0, 0, 0)  # lifts a drink now and then
			person.get_node("Body/Head").rotation.y = sin(t * 0.4) * 0.3


# A blocky, clothed party-goer. Pivots (under "Body"): ArmL, ArmR, LegL, LegR, Head.
static func build(shirt: Color, pants: Color, skin: Color, hair: Color, skirt: bool = false) -> Node3D:
	var rigged := _rigged(shirt, skin, hair, skirt)
	if rigged != null:
		return rigged
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var m_shirt := _mat(shirt)
	var m_pants := _mat(pants)
	var m_skin := _mat(skin)
	var m_hair := _mat(hair)
	_box(body, Vector3(0.38, 0.52, 0.22), Vector3(0, 1.14, 0), m_shirt)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.6, 0)
	body.add_child(head)
	_box(head, Vector3(0.24, 0.24, 0.24), Vector3.ZERO, m_skin)
	_box(head, Vector3(0.26, 0.09, 0.26), Vector3(0, 0.14, 0), m_hair)
	_box(head, Vector3(0.26, 0.2, 0.06), Vector3(0, -0.02, 0.12), m_hair)
	_box(head, Vector3(0.03, 0.03, 0.02), Vector3(-0.05, 0.02, -0.125), _mat(Color.BLACK))
	_box(head, Vector3(0.03, 0.03, 0.02), Vector3(0.05, 0.02, -0.125), _mat(Color.BLACK))
	for side in [["LegL", -1.0], ["LegR", 1.0]]:
		var leg := _pivot(body, side[0], Vector3(side[1] * 0.1, 0.9, 0))
		_box(leg, Vector3(0.14, 0.86, 0.16), Vector3(0, -0.43, 0), m_pants)
		_box(leg, Vector3(0.15, 0.06, 0.22), Vector3(0, -0.88, -0.03), _mat(Color(0.1, 0.1, 0.12)))
	for side in [["ArmL", -1.0], ["ArmR", 1.0]]:
		var arm := _pivot(body, side[0], Vector3(side[1] * 0.26, 1.4, 0))
		_box(arm, Vector3(0.1, 0.34, 0.12), Vector3(0, -0.17, 0), m_shirt)
		_box(arm, Vector3(0.1, 0.24, 0.11), Vector3(0, -0.46, 0), m_skin)
	if skirt:
		_bunny(body, head, m_shirt)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.2
		cone.bottom_radius = 0.34
		cone.height = 0.45
		cone.radial_segments = 8
		cone.rings = 1
		var n := MeshInstance3D.new()
		n.mesh = cone
		n.material_override = m_shirt
		n.position = Vector3(0, 0.8, 0)
		body.add_child(n)
	return root


# A rigged, clothed party-goer: outfit, hairstyle and height vary steadily with the colours; the shirt colour tints
# the clothes; `skirt` marks the stage performers (ears, tail, bow). Null when the character packs are missing.
static func _rigged(shirt: Color, skin: Color, hair: Color, skirt: bool) -> Node3D:
	if not RiggedBody.available():
		return null
	var db := AppearanceData.db()
	var tone := 0
	var best := INF
	for i in db.skin_tones.size():
		var c := Color.html(String(db.skin_tones[i]))
		var miss := Vector3(c.r - skin.r, c.g - skin.g, c.b - skin.b).length_squared()
		if miss < best:
			best = miss
			tone = i
	var pick := absi(hash(shirt.to_html() + hair.to_html()))
	var body := RiggedBody.build(db.sanitize({
		"gender": "female" if skirt or pick % 2 == 0 else "male",
		"skin": tone,
		"hair_color": "#" + hair.to_html(false),
		"rig_outfit": String(db.rig_outfits[pick % db.rig_outfits.size()]["id"]),
		"rig_hair": String(db.rig_hair[(pick >> 3) % db.rig_hair.size()]["id"]),
		"height": 0.94 + 0.03 * float(pick % 5),
	}), false)
	if body == null:
		return null
	body.call("tint_outfit", Color.WHITE.lerp(shirt, 0.45))
	body.call("hold", "Idle", 0.1 * float(pick % 20))  # one still base pose; _animate turns the joints on top of it
	if skirt:
		NpcBody.add_bunny(body, shirt)
	return body


# Bunny-girl accessories: tall ears (pink inside), fluffy tail and a bow collar. Clothing stays as is.
static func _bunny(body: Node3D, head: Node3D, bow_mat: Material) -> void:
	var white := _mat(Color(0.97, 0.97, 0.97))
	var pink := _mat(Color(1.0, 0.65, 0.8))
	for sx in [-1.0, 1.0]:
		var ear := _pivot(head, "Ear", Vector3(sx * 0.07, 0.12, 0.0))
		ear.rotation.z = -sx * 0.18
		_box(ear, Vector3(0.07, 0.34, 0.03), Vector3(0, 0.17, 0), white)
		_box(ear, Vector3(0.035, 0.26, 0.032), Vector3(0, 0.17, -0.004), pink)
	var tail := SphereMesh.new()
	tail.radius = 0.07
	tail.height = 0.14
	tail.radial_segments = 8
	tail.rings = 4
	var t := MeshInstance3D.new()
	t.mesh = tail
	t.material_override = white
	t.position = Vector3(0, 0.95, 0.15)
	body.add_child(t)
	_box(body, Vector3(0.42, 0.06, 0.26), Vector3(0, 1.42, 0), white)  # collar
	_box(body, Vector3(0.14, 0.07, 0.04), Vector3(0, 1.4, -0.14), bow_mat)  # bow


static func _pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


static func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	parent.add_child(n)
