# Purpose: builds the casino annex on the club island (east of the club): shell with a door, carpet, neon, lamps that
# light the tables (polish1 item 73), the giant pachinko machine on the back wall, six slot machines along the east wall, the blackjack and roulette tables with their dealers and two waitresses.
# (polish1 item 72, D3) Grown from 11 x 13 m to 20 x 18 m: a round cocktail bar with a bartender in the middle of the
# new east half, the pachinko wall in the middle of a longer back wall flanked by neon signs, six slot machines.
# Also the card table on the beach outside the door with its House Dealer (data/tcg/table.json) and the card vending machine.
# Dependencies: game/pachinko_wall.gd, game/slot_machine.gd, game/staff_crew.gd, game/blackjack_table.gd, game/roulette_table.gd, game/tcg/beach_table.gd, game/tcg/card_vendor.gd. Walls and floor have colliders; decoration is visual only.
extends RefCounted

const PachinkoWall = preload("res://game/pachinko_wall.gd")
const SlotMachine = preload("res://game/slot_machine.gd")
const StaffCrew = preload("res://game/staff_crew.gd")
const BlackjackTable = preload("res://game/blackjack_table.gd")
const RouletteTable = preload("res://game/roulette_table.gd")
const GunVendor = preload("res://game/gun_vendor.gd")
const BeachTable = preload("res://game/tcg/beach_table.gd")
const CardVendor = preload("res://game/tcg/card_vendor.gd")
const DataStore = preload("res://core/data_store.gd")

const H := 10.0
const MAGENTA := Color(1.0, 0.1, 0.6)
const CYAN := Color(0.1, 0.9, 1.0)
const GOLD := Color(1.0, 0.8, 0.25)

# Annex bounds relative to the club centre: x 12..32, z -12..6 (door in the south wall at x 16..19, facing the sea).
const X0 := 12.0
const X1 := 32.0
const Z0 := -12.0
const Z1 := 6.0


# Returns {"vendors" (Array of game/gun_vendor.gd), "pachinko", "slots" (Array), "blackjack", "roulette", "crew", "bj_dealer", "rt_dealer", "card_table", "card_dealer", "card_vendor", "player_tables" (Array)}.
static func build(parent: Node3D, center: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = center
	parent.add_child(root)
	_shell(root)
	_ceiling_lights(root)
	_back_signs(root)
	var wall: PachinkoWall = PachinkoWall.new()
	wall.position = Vector3(22.0, 8.8, Z0 + 0.55)
	root.add_child(wall)
	var slots: Array = []
	for i in 6:
		var m: SlotMachine = SlotMachine.new()
		m.position = Vector3(X1 - 1.4, 0.0, -8.4 + float(i) * 2.3)  # against the east wall, facing west
		m.rotation_degrees.y = -90.0
		root.add_child(m)
		slots.append(m)
	var crew: StaffCrew = StaffCrew.new()
	root.add_child(crew)
	var bj: BlackjackTable = BlackjackTable.new()
	bj.position = Vector3(15.2, 0.0, 2.6)
	root.add_child(bj)
	var rt: RouletteTable = RouletteTable.new()
	rt.position = Vector3(15.5, 0.0, -1.4)
	root.add_child(rt)
	var bj_dealer: Node3D = crew.add("deal", StaffCrew.look("casino_pink", "twin_tails", "#f48fb1", "giggle", 1), Vector3(15.2, 0.0, 1.65), 180.0, null, "dealer_blackjack")
	var rt_dealer: Node3D = crew.add("deal", StaffCrew.look("casino_purple", "bob", "#3b2a6b", "gentle_smile", 0), Vector3(14.3, 0.0, -2.6), 180.0, null, "dealer_roulette")
	# Waitress routes stay in the aisles: one round the cocktail bar (x 20.3..28.6, z -4..4.6), one up the aisle east of
	# the roulette table (x 18.8) and along the south wall.
	var loop_a: Array = [Vector3(20.3, 0, 4.6), Vector3(28.6, 0, 4.6), Vector3(28.6, 0, -4.0), Vector3(20.3, 0, -4.0)]
	var loop_b: Array = [Vector3(14.4, 0, 4.9), Vector3(18.8, 0, 4.9), Vector3(18.8, 0, -6.0), Vector3(18.8, 0, 4.9)]
	_cocktail_bar(root, crew)
	crew.add_obstacle(Vector3(15.2, 0.0, 2.6), 1.35, 0.72)  # blackjack table
	crew.add_obstacle(Vector3(15.0, 0.0, -1.4), 1.95, 0.75)  # roulette table
	crew.add_obstacle(Vector3(15.2, 0.0, 1.65), 0.3, 0.3)  # blackjack dealer
	crew.add_obstacle(Vector3(14.3, 0.0, -2.6), 0.3, 0.3)  # roulette dealer
	for i in slots.size():
		crew.add_obstacle((slots[i] as Node3D).position, 0.5, 0.5)  # slot machines
	for i in 3:
		crew.add_obstacle(Vector3(12.75, 0.0, 0.8 + 1.9 * float(i)), 0.3, 0.7)  # vendor kiosks
	crew.add("walk", StaffCrew.look("casino_cyan", "ponytail", "#e8c36a", "beaming", 2), loop_a[0], 0.0, loop_a, "waitress_mint")
	crew.add("walk", StaffCrew.look("casino_gold", "high_ponytail", "#1b1b1b", "giggle", 4), loop_b[0], 0.0, loop_b, "waitress_goldie")
	var vendors: Array = []
	var crates: Array = DataStore.load_json("res://data/gun_loot.json")["vendor"]
	for i in crates.size():
		var v: GunVendor = GunVendor.new()
		v.crate = crates[i]
		v.position = Vector3(12.75, 0.0, 0.8 + 1.9 * float(i))
		root.add_child(v)
		vendors.append(v)
	_vendor_sign(root, 0.8 + 1.9, crates.size())
	var house: Dictionary = DataStore.load_json("res://data/tcg/table.json")["house"]
	var at := Vector3(float(house["at"][0]), float(house["at"][1]), float(house["at"][2]))
	var card_table: BeachTable = BeachTable.new()
	card_table.position = at
	card_table.rotation_degrees.y = float(house["yaw"])
	root.add_child(card_table)
	var seat := at + Vector3(0, 0, 0.85).rotated(Vector3.UP, deg_to_rad(float(house["yaw"])))  # on the dealer's stool, facing the player
	var card_dealer: Node3D = crew.add("sit", StaffCrew.look("casino_gold", "long_wavy", "#c0392b", "smirk", 1), seat, float(house["yaw"]), null, String(house["dealer_npc"]))
	var player_tables: Array = []  # the other three tables (locked: four on the beach): two players play there (online, build step 13)
	for t: Dictionary in DataStore.load_json("res://data/tcg/table.json").get("tables", []):
		var pt: BeachTable = BeachTable.new()
		pt.position = Vector3(float(t["at"][0]), float(t["at"][1]), float(t["at"][2]))
		pt.rotation_degrees.y = float(t.get("yaw", 0.0))
		root.add_child(pt)
		player_tables.append(pt)
	var card_vendor: CardVendor = CardVendor.new()  # the card vending machine: north-west corner, facing the room
	card_vendor.position = Vector3(13.0, 0.0, -9.6)
	card_vendor.rotation_degrees.y = 90.0
	root.add_child(card_vendor)
	crew.add_obstacle(Vector3(13.0, 0.0, -9.6), 0.6, 0.9)
	return {"vendors": vendors, "pachinko": wall, "slots": slots, "blackjack": bj, "roulette": rt, "crew": crew, "bj_dealer": bj_dealer, "rt_dealer": rt_dealer, "card_table": card_table, "card_dealer": card_dealer, "card_vendor": card_vendor, "player_tables": player_tables}


# (D3) A round cocktail bar in the middle of the east half: glowing counter rim, bottle tower, stools, a bartender.
const BAR_AT := Vector3(24.5, 0.0, 1.0)


static func _cocktail_bar(root: Node3D, crew: StaffCrew) -> void:
	# few draw calls: the counter is a tube + a flattened ring top, the stools and the bottles one MultiMesh each
	var tube := CylinderMesh.new()
	tube.top_radius = 2.2
	tube.bottom_radius = 2.2
	tube.height = 1.1
	tube.radial_segments = 28
	tube.rings = 1
	tube.cap_top = false
	tube.cap_bottom = false
	var wood := _mat(Color(0.32, 0.12, 0.06))
	wood.cull_mode = BaseMaterial3D.CULL_DISABLED
	var t := MeshInstance3D.new()
	t.mesh = tube
	t.material_override = wood
	t.position = BAR_AT + Vector3(0, 0.55, 0)
	root.add_child(t)
	var top := TorusMesh.new()
	top.inner_radius = 1.55
	top.outer_radius = 2.4
	top.rings = 28
	top.ring_segments = 6
	var tp := MeshInstance3D.new()
	tp.mesh = top
	tp.material_override = _mat(Color(0.7, 0.45, 0.18))
	tp.position = BAR_AT + Vector3(0, 1.12, 0)
	tp.scale = Vector3(1.0, 0.12, 1.0)
	root.add_child(tp)
	var stool := CylinderMesh.new()
	stool.top_radius = 0.22
	stool.bottom_radius = 0.18
	stool.height = 0.75
	stool.radial_segments = 10
	stool.rings = 1
	stool.material = _mat(Color(0.75, 0.08, 0.3))
	var stools := MultiMesh.new()
	stools.transform_format = MultiMesh.TRANSFORM_3D
	stools.mesh = stool
	stools.instance_count = 8
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		stools.set_instance_transform(i, Transform3D(Basis.IDENTITY, BAR_AT + Vector3(sin(a), 0.0, cos(a)) * 2.75 + Vector3(0, 0.375, 0)))
	var sn := MultiMeshInstance3D.new()
	sn.multimesh = stools
	root.add_child(sn)
	var body := StaticBody3D.new()  # one round collider for the counter
	body.position = BAR_AT + Vector3(0, 0.55, 0)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.2
	cyl.height = 1.1
	shape.shape = cyl
	body.add_child(shape)
	root.add_child(body)
	var rim := CylinderMesh.new()  # the glowing rim under the counter top
	rim.top_radius = 2.24
	rim.bottom_radius = 2.24
	rim.height = 0.06
	rim.radial_segments = 24
	rim.rings = 1
	rim.cap_top = false
	rim.cap_bottom = false
	var r := MeshInstance3D.new()
	r.mesh = rim
	var glow := _mat(CYAN, true)
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	r.material_override = glow
	r.position = BAR_AT + Vector3(0, 1.0, 0)
	root.add_child(r)
	_box(root, Vector3(0.9, 2.6, 0.9), BAR_AT + Vector3(0, 1.3 + 1.1, 0), _mat(Color(0.12, 0.05, 0.16)))  # bottle tower
	var bottle := CylinderMesh.new()
	bottle.top_radius = 0.05
	bottle.bottom_radius = 0.07
	bottle.height = 0.32
	bottle.radial_segments = 8
	bottle.rings = 1
	var glass := _mat(Color.WHITE, true)
	glass.vertex_color_use_as_albedo = true
	bottle.material = glass
	var bottles := MultiMesh.new()
	bottles.transform_format = MultiMesh.TRANSFORM_3D
	bottles.use_colors = true
	bottles.mesh = bottle
	bottles.instance_count = 12
	for i in 12:
		var a2 := TAU * float(i) / 12.0
		bottles.set_instance_transform(i, Transform3D(Basis.IDENTITY, BAR_AT + Vector3(sin(a2) * 0.52, 2.6 + float(i % 3) * 0.45, cos(a2) * 0.52)))
		bottles.set_instance_color(i, [MAGENTA, CYAN, GOLD, Color(0.4, 0.9, 0.4)][i % 4])
	var bm := MultiMeshInstance3D.new()
	bm.multimesh = bottles
	root.add_child(bm)
	_box(root, Vector3(1.0, 0.08, 1.0), BAR_AT + Vector3(0, 3.75, 0), _mat(MAGENTA, true))
	crew.add_obstacle(BAR_AT, 2.7, 2.7)
	crew.add("idle", StaffCrew.look("casino_purple", "twin_buns", "#2b1a12", "beaming", 5), BAR_AT + Vector3(0, 0, 1.15), 0.0)


# (D3) Neon pictures either side of the pachinko machine on the longer back wall.
static func _back_signs(root: Node3D) -> void:
	for side: float in [-1.0, 1.0]:
		var x := 22.0 + side * 7.6
		_box(root, Vector3(4.2, 3.0, 0.12), Vector3(x, 6.2, Z0 + 0.3), _mat(Color(0.08, 0.02, 0.1)))
		_box(root, Vector3(4.4, 0.1, 0.14), Vector3(x, 7.75, Z0 + 0.32), _mat(GOLD, true))
		_box(root, Vector3(4.4, 0.1, 0.14), Vector3(x, 4.65, Z0 + 0.32), _mat(GOLD, true))
		var l := Label3D.new()
		l.text = "777" if side < 0.0 else "LUCKY\nSTAR"
		l.font_size = 160 if side < 0.0 else 110
		l.pixel_size = 0.01
		l.modulate = MAGENTA if side < 0.0 else CYAN
		l.outline_size = 22
		l.outline_modulate = Color(0.25, 0.0, 0.2)
		l.shaded = false
		l.double_sided = false
		l.position = Vector3(x, 6.2, Z0 + 0.4)
		root.add_child(l)


# Neon sign on the west wall above the gun vendor kiosks, plus a glowing floor strip under them, so players can find them.
static func _vendor_sign(root: Node3D, center_z: float, kiosks: int) -> void:
	var span := 1.9 * float(kiosks) + 1.0
	_box(root, Vector3(0.12, 1.5, span - 0.4), Vector3(12.3, 4.4, center_z), _mat(Color(0.08, 0.03, 0.12)))
	_box(root, Vector3(0.14, 0.12, span - 0.2), Vector3(12.32, 5.2, center_z), _mat(GOLD, true))
	_box(root, Vector3(0.14, 0.12, span - 0.2), Vector3(12.32, 3.6, center_z), _mat(GOLD, true))
	_box(root, Vector3(1.6, 0.02, span - 0.8), Vector3(13.0, 0.12, center_z), _mat(Color(0.7, 0.5, 0.1), true))
	var title := Label3D.new()
	title.text = "GUN VENDOR"
	title.font_size = 96
	title.pixel_size = 0.009
	title.modulate = GOLD
	title.shaded = false
	title.double_sided = false
	title.rotation_degrees.y = 90.0
	title.position = Vector3(12.4, 4.65, center_z)
	root.add_child(title)
	var sub := Label3D.new()
	sub.text = "random rolled guns - pay with chips - press F"
	sub.font_size = 48
	sub.pixel_size = 0.006
	sub.modulate = CYAN
	sub.shaded = false
	sub.double_sided = false
	sub.rotation_degrees.y = 90.0
	sub.position = Vector3(12.4, 3.95, center_z)
	root.add_child(sub)


static func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	parent.add_child(n)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		parent.add_child(body)


static func _shell(root: Node3D) -> void:
	var wall := _mat(Color(0.16, 0.05, 0.2))
	var cx := (X0 + X1) * 0.5
	var cz := (Z0 + Z1) * 0.5
	var w := X1 - X0
	var d := Z1 - Z0
	_box(root, Vector3(w + 0.4, H, 0.4), Vector3(cx, H * 0.5, Z0), wall, true)  # back (behind the pachinko machine)
	_box(root, Vector3(0.4, H, d), Vector3(X0, H * 0.5, cz), wall, true)  # west
	_box(root, Vector3(0.4, H, d), Vector3(X1, H * 0.5, cz), wall, true)  # east
	_box(root, Vector3(4.0, H, 0.4), Vector3(14.0, H * 0.5, Z1), wall, true)  # south, west of the door
	_box(root, Vector3(X1 - 19.0, H, 0.4), Vector3((19.0 + X1) * 0.5, H * 0.5, Z1), wall, true)  # south, east of the door
	_box(root, Vector3(3.0, H - 3.5, 0.4), Vector3(17.5, 3.5 + (H - 3.5) * 0.5, Z1), wall, true)  # above the door
	_box(root, Vector3(w + 0.6, 0.3, d + 0.6), Vector3(cx, H + 0.15, cz), _mat(Color(0.1, 0.04, 0.14)))  # roof
	_box(root, Vector3(w, 0.1, d), Vector3(cx, 0.05, cz), _mat(Color(0.35, 0.04, 0.1)))  # carpet
	_box(root, Vector3(w - 0.6, 0.02, d - 0.6), Vector3(cx, 0.11, cz), _mat(Color(0.5, 0.06, 0.14)))
	var pink := _mat(MAGENTA, true)
	var blue := _mat(CYAN, true)
	_box(root, Vector3(w + 0.6, 0.15, 0.15), Vector3(cx, H, Z1 + 0.1), pink)  # trim along the front top
	_box(root, Vector3(0.15, 3.5, 0.15), Vector3(16.0, 1.75, Z1 + 0.1), blue)  # door frame
	_box(root, Vector3(0.15, 3.5, 0.15), Vector3(19.0, 1.75, Z1 + 0.1), blue)
	_box(root, Vector3(3.15, 0.15, 0.15), Vector3(17.5, 3.5, Z1 + 0.1), blue)
	var sign_label := Label3D.new()
	sign_label.text = "CASINO"
	sign_label.font_size = 128
	sign_label.pixel_size = 0.012
	sign_label.outline_size = 24
	sign_label.outline_modulate = Color(0.45, 0.3, 0.0)
	sign_label.modulate = GOLD
	sign_label.shaded = false
	sign_label.double_sided = false
	sign_label.position = Vector3(17.5, 6.5, Z1 + 0.3)
	root.add_child(sign_label)


static func _ceiling_lights(root: Node3D) -> void:
	var warm := _mat(Color(1.0, 0.85, 0.6), true)
	for ix in 5:
		for iz in 4:
			_box(root, Vector3(1.4, 0.08, 1.4), Vector3(14.0 + ix * 4.0, H - 0.05, -9.5 + iz * 4.6), warm)
	# (polish1 item 73) the room was too dark to see the tables: pendant lamps whose warm spot lights really light the
	# blackjack and roulette felts. Only these two: on the Compatibility renderer every light draws the meshes it
	# touches once more (a room-wide fill and two more spots cost ~800 draw calls), so they stay small and shadowless.
	_pendant(root, Vector3(15.2, 0.0, 2.6), 3.2, 2.4)  # blackjack
	_pendant(root, Vector3(15.5, 0.0, -1.4), 3.2, 2.6)  # roulette


# A lamp hanging over a table: cord, a brass shade with a glowing rim, and a warm spot light onto the felt.
static func _pendant(root: Node3D, table: Vector3, height: float, energy: float) -> void:
	var top := table + Vector3(0, height, 0)
	_box(root, Vector3(0.03, H - height, 0.03), top + Vector3(0, (H - height) * 0.5, 0), _mat(Color(0.1, 0.1, 0.1)))
	var shade := CylinderMesh.new()
	shade.top_radius = 0.18
	shade.bottom_radius = 0.75
	shade.height = 0.4
	shade.radial_segments = 16
	shade.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.55, 0.38, 0.12)
	brass.roughness = 0.4
	var s := MeshInstance3D.new()
	s.mesh = shade
	s.material_override = brass
	s.position = top
	root.add_child(s)
	var rim := CylinderMesh.new()
	rim.top_radius = 0.7
	rim.bottom_radius = 0.7
	rim.height = 0.02
	rim.radial_segments = 16
	rim.rings = 1
	var glow := MeshInstance3D.new()
	glow.mesh = rim
	glow.material_override = _mat(Color(1.0, 0.9, 0.65), true)
	glow.position = top - Vector3(0, 0.2, 0)
	root.add_child(glow)
	_spot(root, top - Vector3(0, 0.15, 0), table + Vector3(0, 0.9, 0), Color(1.0, 0.88, 0.7), energy, 48.0)


static func _spot(root: Node3D, from: Vector3, to: Vector3, colour: Color, energy: float, angle: float) -> void:
	var spot := SpotLight3D.new()
	root.add_child(spot)
	spot.position = from
	spot.basis = Basis.looking_at(to - from, Vector3.FORWARD if absf((to - from).normalized().y) > 0.99 else Vector3.UP)
	spot.light_color = colour
	spot.light_energy = energy
	spot.spot_range = from.distance_to(to) + 1.2
	spot.spot_angle = angle
	spot.spot_attenuation = 0.5
	spot.shadow_enabled = false
