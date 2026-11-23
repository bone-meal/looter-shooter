# Purpose: the 3D Texas Hold'em table in the casino (polish1 item 167): an oval felt table with a padded rail, a dealer's
# notch, six seats round it, the five community cards in the middle, two hole cards in front of each seat (yours face
# up toward you, the others face down until the showdown), each seat's bet as a chip stack, the pot in the middle and
# the dealer button. Draws only: set_view() takes core/poker_rules.gd view() (what this machine may see).
# Layout (table-local): long axis x, the dealer at the far side (-z), your seat (0) at the near side (+z), top y = TOP.
# Dependencies: game/chip_stack.gd, core/poker_rules.gd (card helpers).
extends Node3D

const ChipStack = preload("res://game/chip_stack.gd")
const Rules = preload("res://core/poker_rules.gd")

const TOP := 0.92
const RX := 1.45  # the felt's half length ...
const RZ := 0.85  # ... and half width
const CARD_W := 0.075
const CARD_L := 0.105
# Seats round the oval (degrees: 0 = +x, 90 = toward you); seat 0 is yours. The dealer stands at DEALER.
const SEAT_ANGLES := [90.0, 148.0, 32.0, 206.0, 334.0, 250.0]
const DEALER_ANGLE := 290.0
const RANK_TEXT := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const SUIT_TEXT := ["♣", "♦", "♥", "♠"]  # clubs, diamonds, hearts, spades (core/poker_rules.gd order)

var _cards: Array = []  # [Node3D, Label3D rank, Label3D suit, MeshInstance3D back]
var _stacks: Array = []
var _pot: Node3D
var _button: Node3D
var _back_mat: StandardMaterial3D


func _ready() -> void:
	_build_table()
	_back_mat = _mat(Color(0.1, 0.16, 0.45))
	for i in 5 + 2 * SEAT_ANGLES.size():
		_cards.append(_new_card())
	for i in SEAT_ANGLES.size():
		var stack: Node3D = ChipStack.new()
		stack.position = _on_felt(float(SEAT_ANGLES[i]), 0.58)
		add_child(stack)
		_stacks.append(stack)
	_pot = ChipStack.new()
	_pot.position = Vector3(0, TOP, -0.22)
	add_child(_pot)
	_button = _disc()


# Where seat `i` sits (table-local, on the floor) and which way it faces (yaw degrees, toward the middle).
static func seat_spot(i: int) -> Vector3:
	var a := deg_to_rad(float(SEAT_ANGLES[i]))
	return Vector3(cos(a) * (RX + 0.55), 0.0, sin(a) * (RZ + 0.55))


static func seat_yaw(i: int) -> float:
	var p := seat_spot(i)
	return rad_to_deg(atan2(p.x, p.z))  # a body faces -z: turn it so it faces the table's middle


static func dealer_spot() -> Vector3:
	var a := deg_to_rad(DEALER_ANGLE)
	return Vector3(cos(a) * (RX + 0.42), 0.0, sin(a) * (RZ + 0.42))


# Shows a hand as this machine may see it (core/poker_rules.gd view()); `me` = our seat (its cards face up toward us).
func set_view(view: Dictionary, me: int) -> void:
	for c: Array in _cards:
		(c[0] as Node3D).visible = false
	var board: Array = view.get("board", [])
	for k in board.size():
		_show_card(k, int(board[k]), Vector3(-0.34 + 0.17 * float(k), TOP + 0.004, 0.02), 0.0, true)
	var seats: Array = view.get("seats", [])
	var showdown := String(view.get("phase", "")) == "showdown"
	for i in mini(seats.size(), SEAT_ANGLES.size()):
		var s: Dictionary = seats[i]
		var cards: Array = s.get("cards", [])
		var at := _on_felt(float(SEAT_ANGLES[i]), 0.74)
		var yaw := seat_yaw(i)
		if not bool(s.get("folded", false)):
			for k in cards.size():
				var face := int(cards[k]) >= 0 and (i == me or showdown)
				var side := Vector3(cos(deg_to_rad(-yaw)), 0.0, sin(deg_to_rad(-yaw))) * (0.045 * (float(k) - 0.5) * 2.0)
				_show_card(5 + i * 2 + k, int(cards[k]), at + side + Vector3(0, 0.004 + 0.002 * float(k), 0), yaw, face)
		(_stacks[i] as Node3D).call("set_amount", int(s.get("bet", 0)))
	var in_bets := 0
	for s: Dictionary in seats:
		in_bets += int(s.get("bet", 0))
	_pot.call("set_amount", int(view.get("pot", 0)) - in_bets)
	var btn := int(view.get("button", -1))
	_button.visible = btn >= 0 and btn < SEAT_ANGLES.size()
	if _button.visible:
		_button.position = _on_felt(float(SEAT_ANGLES[btn]) + 14.0, 0.62) + Vector3(0, 0.006, 0)


func clear() -> void:
	for c: Array in _cards:
		(c[0] as Node3D).visible = false
	for st: Node3D in _stacks:
		st.call("set_amount", 0)
	_pot.call("set_amount", 0)
	_button.visible = false


# A point on the felt toward seat angle `deg`, `f` of the way out from the middle.
func _on_felt(deg: float, f: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(cos(a) * RX * f, TOP, sin(a) * RZ * f)


func _show_card(slot: int, card: int, at: Vector3, yaw: float, face: bool) -> void:
	var c: Array = _cards[slot]
	var n: Node3D = c[0]
	n.visible = true
	n.position = at
	n.rotation = Vector3(0.0, deg_to_rad(yaw), 0.0 if face else PI)
	if face and card >= 0:
		(c[1] as Label3D).text = RANK_TEXT[card % 13]
		(c[2] as Label3D).text = SUIT_TEXT[floori(card / 13.0)]
		var red := floori(card / 13.0) == 1 or floori(card / 13.0) == 2
		(c[1] as Label3D).modulate = Color(0.8, 0.08, 0.12) if red else Color(0.06, 0.06, 0.08)
		(c[2] as Label3D).modulate = (c[1] as Label3D).modulate


func _new_card() -> Array:
	var card := Node3D.new()
	card.visible = false
	add_child(card)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CARD_W, 0.003, CARD_L)
	body.mesh = box
	body.material_override = _mat(Color(0.97, 0.96, 0.93))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.add_child(body)
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_W * 0.88, CARD_L * 0.9)
	back.mesh = quad
	back.material_override = _back_mat
	back.rotation_degrees.x = 90.0  # faces down
	back.position = Vector3(0, -0.0018, 0)
	card.add_child(back)
	var rank := Label3D.new()
	rank.font_size = 64
	rank.pixel_size = 0.00055
	rank.shaded = false
	rank.double_sided = false
	rank.outline_size = 0
	rank.rotation_degrees.x = -90.0
	rank.position = Vector3(0, 0.0019, 0.022)
	card.add_child(rank)
	var suit := Label3D.new()
	suit.font_size = 64
	suit.pixel_size = 0.0007
	suit.shaded = false
	suit.double_sided = false
	suit.outline_size = 0
	suit.rotation_degrees.x = -90.0
	suit.position = Vector3(0, 0.0019, -0.022)
	card.add_child(suit)
	return [card, rank, suit, back]


func _disc() -> Node3D:
	var n := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = 0.01
	cyl.radial_segments = 16
	n.mesh = cyl
	n.material_override = _mat(Color(0.96, 0.95, 0.9))
	var d := Label3D.new()
	d.text = "D"
	d.font_size = 48
	d.pixel_size = 0.0009
	d.modulate = Color(0.05, 0.05, 0.08)
	d.rotation_degrees.x = -90.0
	d.position = Vector3(0, 0.0056, 0)
	d.shaded = false
	n.add_child(d)
	n.visible = false
	add_child(n)
	return n


func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# The oval: felt top, a padded leather rail, a gold inlay line, a dark base on a pedestal, six chairs, a collider.
func _build_table() -> void:
	var felt := MeshInstance3D.new()
	var top := CylinderMesh.new()
	top.top_radius = 1.0
	top.bottom_radius = 1.0
	top.height = 0.06
	top.radial_segments = 40
	felt.mesh = top
	felt.scale = Vector3(RX, 1.0, RZ)
	felt.position = Vector3(0, TOP - 0.03, 0)
	felt.material_override = _mat(Color(0.05, 0.32, 0.2))
	add_child(felt)
	var rail := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.96
	ring.outer_radius = 1.1
	ring.rings = 48
	ring.ring_segments = 10
	rail.mesh = ring
	rail.scale = Vector3(RX, 0.6, RZ) * Vector3(1.0, 1.0, 1.0)
	rail.position = Vector3(0, TOP + 0.01, 0)
	rail.material_override = _mat(Color(0.18, 0.07, 0.05))
	(rail.material_override as StandardMaterial3D).roughness = 0.45
	add_child(rail)
	var inlay := MeshInstance3D.new()
	var line := TorusMesh.new()
	line.inner_radius = 0.9
	line.outer_radius = 0.915
	line.rings = 48
	line.ring_segments = 4
	inlay.mesh = line
	inlay.scale = Vector3(RX, 0.05, RZ)
	inlay.position = Vector3(0, TOP + 0.001, 0)
	inlay.material_override = _mat(Color(1.0, 0.8, 0.3), true)
	add_child(inlay)
	var base := MeshInstance3D.new()
	var col := CylinderMesh.new()
	col.top_radius = 0.95
	col.bottom_radius = 0.7
	col.height = TOP - 0.1
	col.radial_segments = 24
	base.mesh = col
	base.scale = Vector3(RX, 1.0, RZ)
	base.position = Vector3(0, (TOP - 0.1) * 0.5, 0)
	base.material_override = _mat(Color(0.1, 0.04, 0.05))
	add_child(base)
	var words := Label3D.new()
	words.text = "TEXAS HOLD'EM"
	words.font_size = 56
	words.pixel_size = 0.0022
	words.modulate = Color(1.0, 0.85, 0.4, 0.75)
	words.shaded = false
	words.rotation_degrees.x = -90.0
	words.position = Vector3(0, TOP + 0.002, 0.3)
	add_child(words)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.0
	cyl.height = TOP + 0.05
	shape.shape = cyl
	shape.scale = Vector3(RX + 0.1, 1.0, RZ + 0.1)
	shape.position = Vector3(0, (TOP + 0.05) * 0.5, 0)
	body.add_child(shape)
	add_child(body)
	var wood := _mat(Color(0.25, 0.12, 0.06))
	var pad := _mat(Color(0.35, 0.06, 0.08))
	for i in SEAT_ANGLES.size():
		var chair := Node3D.new()
		chair.position = seat_spot(i) + Vector3(0, 0, 0)
		chair.rotation_degrees.y = seat_yaw(i)
		add_child(chair)
		_box(chair, Vector3(0.46, 0.08, 0.44), Vector3(0, 0.46, 0), pad)
		_box(chair, Vector3(0.46, 0.5, 0.06), Vector3(0, 0.74, 0.22), pad)
		for corner: Vector2 in [Vector2(-0.19, -0.18), Vector2(0.19, -0.18), Vector2(-0.19, 0.18), Vector2(0.19, 0.18)]:
			_box(chair, Vector3(0.04, 0.44, 0.04), Vector3(corner.x, 0.22, corner.y), wood)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	parent.add_child(m)
