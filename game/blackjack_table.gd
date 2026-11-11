# Purpose: the 3D blackjack table: green felt table with a rim, betting circles, a card shoe and a pool of 16 real cards that slide out of the shoe and flip. Draws only; core/blackjack_rules.gd decides the game and game_session calls place()/reveal()/clear_cards().
# Dependencies: game/symbol_art.gd (suit icons), core/blackjack_rules.gd (rank/suit helpers).
# Layout (table-local): long axis x, dealer side -z, player side +z, tabletop y = TOP.
extends Node3D

const SymbolArt = preload("res://game/symbol_art.gd")
const ChipStack = preload("res://game/chip_stack.gd")
const Blackjack = preload("res://core/blackjack_rules.gd")

const TOP := 0.95
const CARD_W := 0.1
const CARD_L := 0.14
const POOL := 16
const SHOE := Vector3(0.95, TOP + 0.04, -0.35)
const RANKS: Array[String] = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const FLY := 0.35

signal changed(op: String, args: Array)  # what the local game did at this table, for online spectators (game_session -> net_session)

var _stacks: Array = []  # ChipStack nodes (untyped: a typed array of a preloaded script fails to parse in some load orders)

var _cards: Array[Node3D] = []
var _faces: Array[StandardMaterial3D] = []
var _labels: Array[Label3D] = []
var _keys := {}  # slot key ("d:0", "p0:1") -> pool index
var _used := 0
var _back_mat: StandardMaterial3D
var _quiet := false  # true while applying another player's table events (no re-broadcast)


func _ready() -> void:
	_table()
	_card_pool()
	for hand in 2:
		var stack: Node3D = ChipStack.new()
		stack.position = Vector3(-0.45 + 0.9 * float(hand), TOP, 0.43)
		add_child(stack)
		_stacks.append(stack)


func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, solid: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	add_child(n)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)


func _table() -> void:
	var wood := _mat(Color(0.3, 0.14, 0.06))
	_box(Vector3(2.6, 0.1, 1.3), Vector3(0, TOP - 0.05, 0), _mat(Color(0.05, 0.4, 0.2)))  # felt
	_box(Vector3(2.6, 0.16, 0.14), Vector3(0, TOP - 0.02, 0.72), wood)  # rim, player side
	_box(Vector3(2.6, 0.16, 0.14), Vector3(0, TOP - 0.02, -0.72), wood)
	_box(Vector3(0.14, 0.16, 1.3), Vector3(-1.37, TOP - 0.02, 0), wood)
	_box(Vector3(0.14, 0.16, 1.3), Vector3(1.37, TOP - 0.02, 0), wood)
	_box(Vector3(2.5, 0.85, 1.2), Vector3(0, 0.425, 0), _mat(Color(0.12, 0.05, 0.08)), true)  # base + collider
	_box(Vector3(2.62, 0.04, 1.32), Vector3(0, TOP - 0.11, 0), _mat(Color(1.0, 0.8, 0.25), true))  # gold edge line under the felt
	# betting circles (flat gold rings) for hands 0 and 1
	for x in [-0.45, 0.45]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.11
		ring.outer_radius = 0.125
		ring.rings = 16
		ring.ring_segments = 4
		var n := MeshInstance3D.new()
		n.mesh = ring
		n.material_override = _mat(Color(1.0, 0.8, 0.25), true)
		n.position = Vector3(x, TOP + 0.002, 0.25)
		n.scale = Vector3(1.0, 0.1, 1.0)
		add_child(n)
	var shoe_mesh := BoxMesh.new()
	shoe_mesh.size = Vector3(0.2, 0.08, 0.16)
	var shoe := MeshInstance3D.new()
	shoe.mesh = shoe_mesh
	shoe.material_override = _mat(Color(0.08, 0.08, 0.1))
	shoe.position = SHOE + Vector3(0.05, -0.0, -0.02)
	add_child(shoe)
	var text := Label3D.new()
	text.text = "BLACKJACK pays 3 to 2     dealer stands on all 17"
	text.font_size = 40
	text.pixel_size = 0.0028
	text.modulate = Color(1.0, 0.85, 0.4)
	text.shaded = false
	text.rotation_degrees.x = -90.0
	text.position = Vector3(0, TOP + 0.003, 0.52)
	add_child(text)


func _card_pool() -> void:
	_back_mat = _mat(Color(0.1, 0.2, 0.7), true)
	var white := _mat(Color(0.97, 0.97, 0.97))
	for i in POOL:
		var card := Node3D.new()
		card.visible = false
		card.scale = Vector3(1.4, 1.0, 1.4)
		add_child(card)
		var body := BoxMesh.new()
		body.size = Vector3(CARD_W, 0.004, CARD_L)
		var b := MeshInstance3D.new()
		b.mesh = body
		b.material_override = white
		card.add_child(b)
		var back := QuadMesh.new()
		back.size = Vector2(CARD_W * 0.9, CARD_L * 0.92)
		var bm := MeshInstance3D.new()
		bm.mesh = back
		bm.material_override = _back_mat
		bm.rotation_degrees.x = 90.0  # faces down
		bm.position = Vector3(0, -0.0023, 0)
		card.add_child(bm)
		var face := StandardMaterial3D.new()
		face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face.albedo_texture = SymbolArt.suit_atlas()
		face.uv1_scale = Vector3(0.25, 1.0, 1.0)
		_faces.append(face)
		var icon := QuadMesh.new()
		icon.size = Vector2(0.065, 0.039)
		var im := MeshInstance3D.new()
		im.mesh = icon
		im.material_override = face
		im.rotation_degrees.x = -90.0  # faces up
		im.position = Vector3(0, 0.0025, 0.012)
		card.add_child(im)
		var label := Label3D.new()
		label.font_size = 48
		label.pixel_size = 0.0014
		label.shaded = false
		label.double_sided = false
		label.rotation_degrees.x = -90.0
		label.position = Vector3(-0.028, 0.0026, -0.052)
		card.add_child(label)
		_labels.append(label)
		_cards.append(card)


# Slot position on the felt: "d:i" dealer card i, "p0:i" / "p1:i" player hand cards.
func slot_position(key: String) -> Vector3:
	var parts := key.split(":")
	var i := int(parts[1])
	if parts[0] == "d":
		return Vector3(-0.2 + 0.16 * float(i), TOP + 0.005 + 0.003 * float(i), -0.3)
	var hand := int(String(parts[0]).substr(1))
	return Vector3(-0.45 + 0.9 * float(hand) - 0.08 + 0.15 * float(i), TOP + 0.005 + 0.003 * float(i), 0.25 + 0.03 * float(i))


# Deals `card` (0..51) into a slot: it slides out of the shoe; face down shows the back.
func place(key: String, card: int, face_up: bool) -> void:
	if _used >= POOL:
		return
	if not _quiet:
		changed.emit("place", [key, card, face_up])
	var idx := _used
	_used += 1
	_keys[key] = idx
	var c := _cards[idx]
	c.visible = true
	c.position = SHOE
	c.rotation = Vector3(0, 0.3, 0.0 if face_up else PI)
	_faces[idx].uv1_offset = Vector3(float(Blackjack.suit_of(card)) * 0.25, 0.0, 0.0)
	_labels[idx].text = RANKS[Blackjack.rank_of(card)]
	var suit := Blackjack.suit_of(card)
	_labels[idx].modulate = Color(0.85, 0.08, 0.12) if suit == 1 or suit == 2 else Color(0.08, 0.08, 0.1)
	var tw := create_tween()
	tw.tween_property(c, "position", slot_position(key), FLY).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "rotation:y", 0.0, FLY)


# Flips a face-down card face up (the dealer's hole card).
func reveal(key: String) -> void:
	if not _quiet:
		changed.emit("reveal", [key])
	if not _keys.has(key):
		return
	var c := _cards[int(_keys[key])]
	var tw := create_tween()
	var rest := slot_position(key)
	tw.tween_property(c, "position:y", rest.y + 0.12, 0.15)
	tw.parallel().tween_property(c, "rotation:z", 0.0, 0.3)
	tw.tween_property(c, "position:y", rest.y, 0.15)


# Sweeps every card to the dealer's side and hides it.
func clear_cards(instant: bool = false) -> void:
	if not _quiet:
		changed.emit("clear", [])
	for i in _used:
		var c := _cards[i]
		if instant:
			c.visible = false
			continue
		var tw := create_tween()
		tw.tween_property(c, "position", Vector3(-1.1, TOP + 0.02, -0.35), 0.35)
		tw.tween_callback(c.set_visible.bind(false))
	_used = 0
	_keys.clear()


# Shows the coins staked on hand 0 and 1 (an empty array or 0 hides a stack).
func show_bets(amounts: Array[int]) -> void:
	if not _quiet:
		changed.emit("bets", amounts.duplicate())
	for i in _stacks.size():
		_stacks[i].set_amount(amounts[i] if i < amounts.size() else 0)


# Applies a table event from another player (already validated by net_session) so spectators see their hand.
func apply_remote(op: String, args: Array) -> void:
	_quiet = true
	match op:
		"place":
			place(String(args[0]), int(args[1]), bool(args[2]))
		"reveal":
			reveal(String(args[0]))
		"clear":
			clear_cards()
		"bets":
			var amounts: Array[int] = []
			for a: Variant in args:
				amounts.append(int(a))
			show_bets(amounts)
	_quiet = false
