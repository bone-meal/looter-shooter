# Purpose: the 3D card table (locked step 12): the cards of a match lie on the beach table as flat 3D cards: your hand
# fanned up at your edge facing you, the other hand as backs at the far edge, creatures on the arc spots of the mat
# (data/tcg/mat_layout.json, tilted the same way), each leader on its portrait spot at the back, the decks as stacks.
# A camera sits over your side; hovering a card lifts it; holding Alt looks around. It only SHOWS what the 2D table
# screen (game/tcg/table_screen.gd) holds: that screen keeps its card faces (hidden) and all the rules of clicking,
# and asks this view which face is under the mouse (`pick`). Pictures come from game/tcg/card_bake.gd.
# Legendary creatures get a small 3D figure standing on their card (data/tcg/figures.json; how many per table by the
# graphics tier, none on Potato; wasteland models painted in their enemy colours like the game does).
# Dependencies: game/tcg/card_bake.gd, data/tcg/mat_layout.json, data/tcg/figures.json, data/enemies.json, game/npc_body.gd + game/weapon_models.gd (people); the table
# node (game/tcg/beach_table.gd) handed in.
extends Node3D

const NpcBody = preload("res://game/npc_body.gd")
const CardShine3D = preload("res://game/tcg/card_shine_3d.gd")
const NUMBER_FONT = preload("res://assets/fonts/LilitaOne.ttf")
const WeaponModels = preload("res://game/weapon_models.gd")
const TOP := 0.818  # the mat's surface in table space
const PX := 0.00138  # metres per pixel of the mat picture (1.42 m / 1024 px)
const CARD := Vector2(0.108, 0.151)
const HAND := Vector2(0.105, 0.147)
const LEADER := Vector2(0.12, 0.168)

var bake: Node  # game/tcg/card_bake.gd
var graphics := "high"  # the graphics tier id (sets how many figures stand on the table)
var _figures_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/figures.json"))
var _figures := {}  # creature uid -> figure node standing on its card
var _models := {}  # model path -> [PackedScene, scale] (loaded once)
var _layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/mat_layout.json"))
var _cam := Camera3D.new()
var _before: Camera3D  # the camera to give back
var _cards: Array = []  # {"node", "face", "half": Vector2, "home": Transform3D}
var _pool: Array = []  # spare card nodes
var _decks: Array = []  # two stacks
var _hover: Node3D
var _prev := {}  # creature uid -> {"at": Transform3D, "mat": Material} as it lay before the last redraw (crumble, damage on the dead)
var _hand_nodes: Array = []  # my hand's card nodes, in order (the newest last)
var _moves: Array = []  # running slides and lunges on card nodes (stopped by the next redraw)
static var _ghost_quad: QuadMesh
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
	for uid: int in _figures.keys():
		(_figures[uid] as Node3D).queue_free()
	_figures = {}
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
	for tw: Variant in _moves:
		if (tw as Tween).is_valid():
			(tw as Tween).kill()
	_moves = []
	_prev = {}
	for c: Dictionary in _cards:
		var was: Variant = c["face"]
		if was is Control and not ((was as Control).get("creature") as Dictionary).is_empty():
			_prev[int((was as Control).get("slot"))] = {"at": c["home"], "mat": (c["node"] as MeshInstance3D).material_override}
	_hand_nodes = []
	for c: Dictionary in _cards:
		(c["node"] as Node3D).visible = false
		_pool.append(c["node"])
	_cards = []
	_hover = null
	var n := hand.size()
	for i in n:  # my hand: a fan standing up at my edge
		var t := (float(i) - float(n - 1) * 0.5)
		var spread := minf(0.11, 1.1 / maxf(n, 1))
		var at := Vector3(-t * spread, TOP + 0.035 - absf(t) * 0.004, -0.58 + absf(t) * 0.006)  # low and close: your leader shows above it
		_add(hand[i], Transform3D(Basis.from_euler(Vector3(deg_to_rad(-38.0), deg_to_rad(180.0 + t * 4.0), 0.0)), at), HAND)
		_hand_nodes.append((_cards.back() as Dictionary)["node"])
	for i in foe_hand:  # their hand: backs at the far edge
		var t := (float(i) - float(foe_hand - 1) * 0.5)
		_add(null, Transform3D(Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(t * 3.0), 0.0)), Vector3(t * 0.06, TOP + 0.002 + i * 0.0005, 0.48)), HAND * 0.8)
	var cap := int((_figures_cfg.get("per_tier", {}) as Dictionary).get(graphics, 0))
	var standing := {}
	for half: Array in [[mine, 1.0], [foe, -1.0]]:
		var list: Array = half[0]
		var s: float = half[1]  # 1 = my half (-z), -1 = theirs
		var spots: Array = _layout["creatures"]
		var first := floori((spots.size() - list.size()) / 2.0)
		for i in list.size():
			var spot: Array = spots[clampi(first + i, 0, spots.size() - 1)]
			var where := _flat(float(spot[0]), float(spot[1]), float(spot[2]), s)
			_add(list[i], where, CARD)
			var id := String((list[i] as Control).get("id"))
			var pony := String((list[i] as Control).get("finish")) == "pony" and (_figures_cfg.get("pony", {}) as Dictionary).has(id)
			if standing.size() < cap and ((_figures_cfg.get("figures", {}) as Dictionary).has(id) or pony):  # legendary and up: legendaries, and any pony foil
				var uid := int((list[i] as Control).get("slot"))
				standing[uid] = true
				_stand(uid, id, where.origin, s)
	for uid: int in _figures.keys():  # figures whose creature left the table
		if not standing.has(uid):
			(_figures[uid] as Node3D).queue_free()
			_figures.erase(uid)
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


# A legendary's figure on its card, facing the other side of the table.
func _stand(uid: int, id: String, at: Vector3, s: float) -> void:
	if not _figures.has(uid):
		var f: Dictionary = _figures_cfg["figures"][id] if (_figures_cfg["figures"] as Dictionary).has(id) else _figures_cfg["pony"][id]
		var node: Node3D
		if f.has("person"):  # a person: a rigged NPC body (one merged mesh) held still in one moment of a clip
			node = NpcBody.build(f["person"])
			add_child(node)
			if node.has_method("hold"):
				node.call("hold", String(f.get("clip", "Idle")), float(f.get("time", 0.0)))
			if f.has("prop") and node.has_method("hand_anchor"):
				(node.call("hand_anchor") as Node3D).add_child(WeaponModels.build(String(f["prop"])))
		else:
			var model := String(f["model"])
			if not _models.has(model):
				var path := "res://assets/models/%s.gltf" % model
				if not ResourceLoader.exists(path):
					return
				_models[model] = load(path)
			node = (_models[model] as PackedScene).instantiate()
			_paint(node, model.get_file())
			add_child(node)
		var box := _bounds(node)
		var k := float(f.get("height", 0.11)) / maxf(box.size.y, 0.01)
		node.scale = Vector3(k, k, k)
		node.set_meta("lift", -box.position.y * k)
		_figures[uid] = node
	var fig: Node3D = _figures[uid]
	fig.position = Vector3(at.x, TOP + 0.004 + float(fig.get_meta("lift", 0.0)), at.z)
	fig.rotation = Vector3(0, 0.0 if s > 0.0 else PI, 0)  # models face +z: mine look across at theirs


# What just happened, shown on the table after the redraw (cheap tweens, locked): new creatures slide in from the
# hand, attackers lunge at their target and spring back, damage and healing rise as numbers, the dead crumble to dust,
# my drawn card slides out of my deck; a pony foil coming down bursts into pastel sparkles. events = the match log of
# that move (core/tcg/match_state.gd), me = our side.
func play(events: Array, me: int) -> void:
	var at := 0.0
	for e: Dictionary in events:
		match String(e.get("e", "")):
			"summon":
				var node := _node_of(int(e["uid"]))
				if node != null:
					var mine := int(e["side"]) == me
					_slide(node, Vector3(0.0, TOP + 0.06, -0.5 if mine else 0.45), at)
					if _finish_of(node) == "pony":
						_sparkle(node.position, at + 0.28)
				at += 0.1
			"attack":
				var node := _node_of(int(e["uid"]))
				var to: Variant = _spot_of(int(e["target"]), me)
				if node != null and to != null:
					_lunge(node, to, at)
				at += 0.3
			"damage":
				var to: Variant = _spot_of(int(e["target"]), me)
				if to != null and int(e.get("amount", 0)) > 0:
					_number(to, "-%d" % int(e["amount"]), Color(1.0, 0.32, 0.25), at)
			"heal":
				var to: Variant = _spot_of(int(e["target"]), me)
				if to != null and int(e.get("amount", 0)) > 0:
					_number(to, "+%d" % int(e["amount"]), Color(0.4, 1.0, 0.45), at)
			"death":
				var was: Dictionary = _prev.get(int(e["uid"]), {})
				if not was.is_empty():
					_crumble(was, at + 0.15)
			"draw":
				if int(e["side"]) == me and not _hand_nodes.is_empty():
					var node: Node3D = _hand_nodes.back()
					_slide(node, (_decks[0] as Node3D).position + Vector3(0, 0.03, 0), at)


func _node_of(uid: int) -> Node3D:
	for c: Dictionary in _cards:
		var face: Variant = c["face"]
		if face is Control and int((face as Control).get("slot")) == uid and not ((face as Control).get("creature") as Dictionary).is_empty():
			return c["node"]
	return null


func _finish_of(node: Node3D) -> String:
	for c: Dictionary in _cards:
		if c["node"] == node and c["face"] is Control:
			return String((c["face"] as Control).get("finish"))
	return ""


# A target code of the match (creature uid, or -10 - side for a leader) as a point on the table; null = not shown.
func _spot_of(code: int, me: int) -> Variant:
	if code >= 0:
		var node := _node_of(code)
		if node != null:
			return node.position
		if _prev.has(code):
			return ((_prev[code] as Dictionary)["at"] as Transform3D).origin
		return null
	var k := 0 if -10 - code == me else 1
	for c: Dictionary in _cards:
		if c["face"] is Dictionary and int((c["face"] as Dictionary).get("side", -1)) == k:
			return (c["node"] as Node3D).position
	return null


func _slide(node: Node3D, from: Vector3, delay: float) -> void:
	var home := node.position
	node.position = from
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(node, "position", home, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_moves.append(tw)


func _lunge(node: Node3D, to: Vector3, delay: float) -> void:
	var home := node.position
	var hit := home.lerp(Vector3(to.x, home.y + 0.025, to.z), 0.7)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(node, "position", hit, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "position", home, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_moves.append(tw)


func _number(at: Vector3, text: String, color: Color, delay: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = NUMBER_FONT
	label.font_size = 72
	label.outline_size = 14
	label.pixel_size = 0.0007
	label.modulate = color
	label.outline_modulate = Color(0.1, 0.02, 0.02)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = at + Vector3(0, 0.05, 0)
	label.visible = false
	add_child(label)
	var tw := label.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: label.visible = true)
	tw.tween_property(label, "position:y", label.position.y + 0.07, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tw.tween_callback(label.queue_free)


# A creature that died: its card shrinks and spins away while a puff of dust goes up.
func _crumble(was: Dictionary, delay: float) -> void:
	if _ghost_quad == null:
		_ghost_quad = QuadMesh.new()
		_ghost_quad.size = Vector2.ONE
	var ghost := MeshInstance3D.new()
	ghost.mesh = _ghost_quad
	ghost.transform = was["at"]
	ghost.scale = Vector3(CARD.x, CARD.y, 1.0)
	ghost.material_override = was["mat"]
	add_child(ghost)
	var dust := _burst(ghost.position, 14, [Color(0.82, 0.78, 0.68), Color(0.55, 0.5, 0.45)], 0.006)
	var tw := ghost.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: dust.emitting = true)
	tw.tween_property(ghost, "scale", Vector3(0.001, 0.001, 1.0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ghost, "rotation:y", ghost.rotation.y + 1.4, 0.45)
	tw.tween_callback(ghost.queue_free)


# A pony foil coming down: pastel sparkles (the pony guns' colours, game/pony_skin.gd).
func _sparkle(at: Vector3, delay: float) -> void:
	var spark := _burst(at, 28, [Color(1.0, 0.6, 0.85), Color(0.6, 1.0, 0.85), Color(0.75, 0.65, 1.0), Color(1.0, 0.95, 0.55), Color(0.55, 0.85, 1.0)], 0.005)
	var tw := spark.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: spark.emitting = true)


# A one-shot puff of little bits (CPU particles: cheap on the Compatibility renderer); frees itself afterwards.
func _burst(at: Vector3, amount: int, colors: Array, bit: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.12
	p.initial_velocity_max = 0.3
	p.gravity = Vector3(0, -0.5, 0)
	var box := BoxMesh.new()
	box.size = Vector3(bit, bit, bit)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	box.material = m
	p.mesh = box
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array()
	ramp.colors = PackedColorArray()
	for i in colors.size():
		ramp.add_point(float(i) / maxf(colors.size() - 1, 1), colors[i])
	p.color_initial_ramp = ramp
	p.position = at + Vector3(0, 0.01, 0)
	p.finished.connect(p.queue_free)
	add_child(p)
	return p


# The model's size in its own space (all meshes together).
func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		var box: AABB = (root.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if mi.is_inside_tree() else mi.transform * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


# Wasteland models carry plain white bodies: the game paints them with the enemy's colours (game/character_models.gd).
func _paint(root: Node3D, file: String) -> void:
	var enemies: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))["enemies"]
	for e: Dictionary in enemies.values():
		if String(e.get("model", "")) != file or not e.has("body_color"):
			continue
		var b: Array = e["body_color"]
		for found in root.find_children("*", "MeshInstance3D", true, false):
			var mi := found as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
				if m != null and String(m.resource_name) in ["body", "hide"]:
					var paint := m.duplicate() as BaseMaterial3D  # keeps its texture, takes the colour
					paint.albedo_color = Color(float(b[0]), float(b[1]), float(b[2]))
					paint.vertex_color_use_as_albedo = false
					mi.set_surface_override_material(i, paint)
		return


# A spot of the mat picture (pixels; y from the centre line toward the owner) as a lying card in table space.
func _flat(px: float, py: float, angle: float, s: float) -> Transform3D:
	var at := Vector3(-(px - 512.0) * PX * s, TOP + 0.003, -py * PX * s)
	var yaw := (180.0 - angle) if s > 0.0 else -angle
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(yaw), 0.0)), at)


# face: a CardFace of the screen (its id, live creature, finish and outline), null = a back, or {"id", "leader"}.
func _add(face: Variant, where: Transform3D, size: Vector2) -> void:
	var node: MeshInstance3D = _pool.pop_back() if not _pool.is_empty() else _new_card()
	node.visible = true
	node.material_override = null
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
	var want := "%s|%s|%s" % [id, finish, str(live)]
	node.set_meta("want", want)  # a reused node may still have an older picture on its way
	bake.call("texture", id, "", func(tex: Texture2D) -> void:  # baked plain: a foil's shine moves on the table (game/tcg/card_shine_3d.gd)
		if is_instance_valid(node) and node.get_meta("want", "") == want:
			var look: Material = _material(tex)
			if finish != "":
				look = CardShine3D.material(tex, finish)
			node.material_override = look, live)


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
