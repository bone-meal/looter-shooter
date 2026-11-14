# Purpose: builds the casino annex on the club island (east of the club): shell with a door, carpet, neon, the giant pachinko machine that IS the back wall, four slot machines along the east wall, the blackjack and roulette tables with their dealers and two waitresses.
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

# Annex bounds relative to the club centre: x 12..23, z -7..6 (door in the south wall at x 16..19, facing the sea).
const X0 := 12.0
const X1 := 23.0
const Z0 := -7.0
const Z1 := 6.0


# Returns {"vendors" (Array of game/gun_vendor.gd), "pachinko", "slots" (Array), "blackjack", "roulette", "crew", "bj_dealer", "rt_dealer", "card_table", "card_dealer", "card_vendor", "player_tables" (Array)}.
static func build(parent: Node3D, center: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = center
	parent.add_child(root)
	_shell(root)
	_ceiling_lights(root)
	var wall: PachinkoWall = PachinkoWall.new()
	wall.position = Vector3(17.5, 8.8, Z0 + 0.55)
	root.add_child(wall)
	var slots: Array = []
	for i in 4:
		var m: SlotMachine = SlotMachine.new()
		m.position = Vector3(21.6, 0.0, -2.7 + float(i) * 2.1)  # against the east wall, facing west
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
	# Waitress routes stay in the aisles: east aisle (x 17.7..20.3, between the roulette table and the slot machines) and the north aisle (z ~4.9, south of the blackjack table).
	var loop_a: Array = [Vector3(17.7, 0, 4.9), Vector3(20.3, 0, 4.9), Vector3(20.3, 0, -1.2), Vector3(17.7, 0, -1.2)]
	var loop_b: Array = [Vector3(14.4, 0, 4.9), Vector3(18.8, 0, 4.9), Vector3(18.8, 0, -4.5), Vector3(18.8, 0, 4.9)]
	crew.add_obstacle(Vector3(15.2, 0.0, 2.6), 1.35, 0.72)  # blackjack table
	crew.add_obstacle(Vector3(15.0, 0.0, -1.4), 1.95, 0.75)  # roulette table
	crew.add_obstacle(Vector3(15.2, 0.0, 1.65), 0.3, 0.3)  # blackjack dealer
	crew.add_obstacle(Vector3(14.3, 0.0, -2.6), 0.3, 0.3)  # roulette dealer
	for i in 4:
		crew.add_obstacle(Vector3(21.6, 0.0, -2.7 + float(i) * 2.1), 0.5, 0.5)  # slot machines
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
	card_vendor.position = Vector3(13.0, 0.0, -4.6)
	card_vendor.rotation_degrees.y = 90.0
	root.add_child(card_vendor)
	crew.add_obstacle(Vector3(13.0, 0.0, -4.6), 0.6, 0.9)
	return {"vendors": vendors, "pachinko": wall, "slots": slots, "blackjack": bj, "roulette": rt, "crew": crew, "bj_dealer": bj_dealer, "rt_dealer": rt_dealer, "card_table": card_table, "card_dealer": card_dealer, "card_vendor": card_vendor, "player_tables": player_tables}


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
	_box(root, Vector3(4.0, H, 0.4), Vector3(21.0, H * 0.5, Z1), wall, true)  # south, east of the door
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
	for ix in 3:
		for iz in 3:
			_box(root, Vector3(1.4, 0.08, 1.4), Vector3(14.0 + ix * 3.5, H - 0.05, -4.0 + iz * 4.5), warm)
