# Purpose: the 3D card table (locked step 12): the cards of a match lie on the beach table as flat 3D cards: your hand
# fanned up at your edge facing you, the other hand as backs at the far edge, creatures on the arc spots of the mat
# (data/tcg/mat_layout.json, tilted the same way), each leader on its portrait spot at the back, the decks as stacks.
# A camera sits over your side; hovering a card lifts it; holding Alt looks around. It only SHOWS what the 2D table
# screen (game/tcg/table_screen.gd) holds: that screen keeps its card faces (hidden) and all the rules of clicking,
# and asks this view which face is under the mouse (`pick`). Pictures come from game/tcg/card_bake.gd.
# Dependencies: game/tcg/card_bake.gd, data/tcg/mat_layout.json; the table node (game/tcg/beach_table.gd) handed in.
extends Node3D

const TOP := 0.818  # the mat's surface in table space
const PX := 0.00138  # metres per pixel of the mat picture (1.42 m / 1024 px)
const CARD := Vector2(0.108, 0.151)
const HAND := Vector2(0.105, 0.147)
const LEADER := Vector2(0.12, 0.168)

var bake: Node  # game/tcg/card_bake.gd
var _layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/mat_layout.json"))
var _cam := Camera3D.new()
var _before: Camera3D  # the camera to give back
var _cards: Array = []  # {"node", "face", "half": Vector2, "home": Transform3D}
var _pool: Array = []  # spare card nodes
var _decks: Array = []  # two stacks
var _hover: Node3D
var _yaw := 0.0
var _pitch := 0.0
const CAM_HOME := Vector3(0.0, 1.62, -1.0)
const CAM_LOOK := Vector3(0.0, 0.78, 0.02)


func _ready() -> void:
	add_child(_cam)
	_cam.fov = 52.0
	_place_camera()
	var edge := StandardMaterial3D.new()  # the stack's sides: card edges
	edge.albedo_color = Color(0.85, 0.82, 0.74)
	for i in 2:
		var stack := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(CARD.x, 0.01, CARD.y)
		stack.mesh = box
		stack.material_override = edge
		var top := MeshInstance3D.new()  # the back of the top card
		var quad := QuadMesh.new()
		quad.size = CARD
		top.mesh = quad
		top.rotation_degrees.x = -90.0
		stack.add_child(top)
		add_child(stack)
		_decks.append(stack)


func enter() -> void:
	_before = get_viewport().get_camera_3d()
	_yaw = 0.0
	_pitch = 0.0
	_place_camera()
	_cam.current = true
	visible = true
	get_parent().call("show_parasol", false)


func leave() -> void:
	visible = false
	get_parent().call("show_parasol", true)
	if _before != null and is_instance_valid(_before):
		_before.current = true


# Hold Alt and move the mouse: look around the table (the screen passes the motion on).
func free_look(relative: Vector2) -> void:
	_yaw = clampf(_yaw - relative.x * 0.004, -1.2, 1.2)
	_pitch = clampf(_pitch - relative.y * 0.003, -0.5, 0.6)
	_place_camera()


func _place_camera() -> void:
	var offset := (CAM_HOME - CAM_LOOK).rotated(Vector3.UP, _yaw)
	var side := offset.cross(Vector3.UP).normalized()
	offset = offset.rotated(side, _pitch)
	if not is_inside_tree():
		return
	_cam.look_at_from_position(to_global(CAM_LOOK + offset), to_global(CAM_LOOK), Vector3.UP)  # global points


# What the table shows. faces = the screen's CardFace controls: hand (mine, in order), mine and foe (creatures, in
# board order); foe_hand = how many cards the other side holds; leaders = [my leader id, theirs]; decks = [mine, theirs].
func show_cards(hand: Array, mine: Array, foe: Array, foe_hand: int, leaders: Array, decks: Array) -> void:
	for c: Dictionary in _cards:
		(c["node"] as Node3D).visible = false
		_pool.append(c["node"])
	_cards = []
	_hover = null
	var n := hand.size()
	for i in n:  # my hand: a fan standing up at my edge
		var t := (float(i) - float(n - 1) * 0.5)
		var spread := minf(0.11, 1.1 / maxf(n, 1))
		var at := Vector3(-t * spread, TOP + 0.06 + absf(t) * -0.004, -0.5 + absf(t) * 0.006)
		_add(hand[i], Transform3D(Basis.from_euler(Vector3(deg_to_rad(-38.0), deg_to_rad(180.0 + t * 4.0), 0.0)), at), HAND)
	for i in foe_hand:  # their hand: backs at the far edge
		var t := (float(i) - float(foe_hand - 1) * 0.5)
		_add(null, Transform3D(Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(t * 3.0), 0.0)), Vector3(t * 0.06, TOP + 0.002 + i * 0.0005, 0.48)), HAND * 0.8)
	for half: Array in [[mine, 1.0], [foe, -1.0]]:
		var list: Array = half[0]
		var s: float = half[1]  # 1 = my half (-z), -1 = theirs
		var spots: Array = _layout["creatures"]
		var first := floori((spots.size() - list.size()) / 2.0)
		for i in list.size():
			var spot: Array = spots[clampi(first + i, 0, spots.size() - 1)]
			_add(list[i], _flat(float(spot[0]), float(spot[1]), float(spot[2]), s), CARD)
	for k in 2:  # leaders on their portrait spots
		var s := 1.0 if k == 0 else -1.0
		var l: Array = _layout["leader"]["at"]
		_add({"id": String(leaders[k]), "leader": true, "side": k}, _flat(float(l[0]), float(l[1]), 0.0, s), LEADER)
	for k in 2:  # decks as stacks
		var s := 1.0 if k == 0 else -1.0
		var d: Array = _layout["deck"]
		var count := int(decks[k])
		var stack: MeshInstance3D = _decks[k]
		stack.visible = count > 0
		var h := maxf(count, 1) * 0.0012
		(stack.mesh as BoxMesh).size = Vector3(CARD.x, h, CARD.y)
		var spot := _flat(float(d[0]), float(d[1]), float(d[2]), s)
		var yaw := (180.0 - float(d[2])) if s > 0.0 else -float(d[2])
		stack.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(spot.origin.x, TOP + h * 0.5, spot.origin.z))
		var top: MeshInstance3D = stack.get_child(0)
		top.position.y = h * 0.5 + 0.0005
		bake.call("texture", "", "", func(tex: Texture2D) -> void: top.material_override = _material(tex))


# A spot of the mat picture (pixels; y from the centre line toward the owner) as a lying card in table space.
func _flat(px: float, py: float, angle: float, s: float) -> Transform3D:
	var at := Vector3(-(px - 512.0) * PX * s, TOP + 0.003, -py * PX * s)
	var yaw := (180.0 - angle) if s > 0.0 else -angle
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(yaw), 0.0)), at)


# face: a CardFace of the screen (its id, live creature, finish and outline), null = a back, or {"id", "leader"}.
func _add(face: Variant, where: Transform3D, size: Vector2) -> void:
	var node: MeshInstance3D = _pool.pop_back() if not _pool.is_empty() else _new_card()
	node.visible = true
	node.transform = where
	node.scale = Vector3(size.x, size.y, 1.0)
	_cards.append({"node": node, "face": face, "home": where, "size": size})
	var glow: MeshInstance3D = node.get_child(0)
	glow.visible = false
	var id := ""
	var finish := ""
	var live := {}
	if face is Control:
		id = String((face as Control).get("id"))
		finish = String((face as Control).get("finish"))
		live = (face as Control).get("creature")
		var outline: Color = (face as Control).get("outline")
		glow.visible = outline.a > 0.0
		(glow.material_override as StandardMaterial3D).albedo_color = outline
	elif face is Dictionary:
		id = String(face["id"])
	bake.call("texture", id, finish, func(tex: Texture2D) -> void:
		if is_instance_valid(node):
			node.material_override = _material(tex), live)


func _new_card() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	node.mesh = quad
	var glow := MeshInstance3D.new()  # the outline: a coloured card just behind and a little larger
	var gq := QuadMesh.new()
	gq.size = Vector2(1.12, 1.09)
	glow.mesh = gq
	glow.position = Vector3(0, 0, -0.002)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.material_override = gm
	node.add_child(glow)
	add_child(node)
	return node


static var _materials := {}


static func _material(tex: Texture2D) -> Material:
	var key := tex.get_rid()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR  # the card's rounded corners
		m.roughness = 0.7
		_materials[key] = m
		if _materials.size() > 96:  # textures leave the baker's cache; drop old materials with them
			_materials.erase(_materials.keys()[0])
	return _materials[key]


# The screen face (or {"leader": true, ...}) under a point of the screen, or null. Also lifts the card under it.
func pick(screen_pos: Vector2) -> Variant:
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	var best: Dictionary = {}
	var best_d := INF
	for c: Dictionary in _cards:
		var node: Node3D = c["node"]
		var g := node.global_transform
		var normal := g.basis.z.normalized()
		var denom := normal.dot(dir)
		if absf(denom) < 0.0001:
			continue
		var d := normal.dot(g.origin - from) / denom
		if d <= 0.0 or d >= best_d:
			continue
		var local := g.affine_inverse() * (from + dir * d)
		if absf(local.x) <= 0.5 and absf(local.y) <= 0.5:
			best = c
			best_d = d
	_lift(best.get("node") as Node3D if not best.is_empty() else null)
	return best.get("face") if not best.is_empty() else null


func _lift(node: Node3D) -> void:
	if node == _hover:
		return
	for c: Dictionary in _cards:
		if c["node"] == _hover:
			(c["node"] as Node3D).transform = c["home"]
			(c["node"] as Node3D).scale = Vector3((c["size"] as Vector2).x, (c["size"] as Vector2).y, 1.0)
	_hover = node
	if node != null:
		node.position += Vector3(0, 0.025, 0) + node.global_transform.basis.z.normalized() * 0.01
		node.scale *= 1.12
