# Purpose: one dungeon's space (sea step 9a, LOCKED: hand-made from a room kit, own space behind the door): drawn from
# its map with the room kit (one MultiMesh each for floors, walls, ceilings; a node per door, plate, lever, block,
# key, chest, torch, the exit gate), solid (one body of boxes; closed doors and blocks have their own), and shown in the
# state the rules hold (doors slide / swing, plates sink, levers lean, blocks glide, keys vanish, chest lids open).
# The local player's prompts here and what [F] asks for go to the manager (game/sea_dungeons.gd), which applies them
# (host / alone) or asks the host.
# Dependencies: core/sea/dungeon_rules.gd, assets/models/sea/dungeon/*.gltf (tools/blender/sea_dungeon_kit.py),
# game/fx_kit.gd. Placed under the sea root at its space (sea coordinates) by the manager.
# Sea step 9c-2: things on ledges stand on the ledge's top; the Great Key and its door, the sealed door; a fight's
# rising tide is a water sheet over its flood cells, eased to the level the rules give.
# Sea step 9d: an OUTDOOR court (entry "outdoor") stands on its island: no ceiling, its own torches setting (0 = none).
extends Node3D

const DungeonRules = preload("res://core/sea/dungeon_rules.gd")
const FxKit = preload("res://game/fx_kit.gd")
const KIT := "res://assets/models/sea/dungeon/%s.gltf"

var rules: DungeonRules
var cfg: Dictionary  # data/sea/dungeons.json (all of it)
var built := false
var _nodes := {}  # letter -> Node3D (doors, plates, levers, blocks, keys, chests, the exit)
var _solids := {}  # letter -> StaticBody3D (closed doors, blocks)
var _anim := {}  # letter -> 0..1 shown (doors open, plates down, levers pulled, chest lids)
var _torches: Array = []
var _floods := {}  # fight letter -> MeshInstance3D (its tide's water sheet)
var outdoor := false  # (sea step 9d) a puzzle court out on an island: no ceiling, the island's own light
var wall_h := 4.5  # this dungeon's walls (its entry's "wall_h", else the kit's): tall halls stack the kit's wall
var sea_seconds := Callable()  # the shared sea clock (the fog walkways' reveal is timed on it), set by the manager


func setup(dungeon_id: String, entry: Dictionary, all_cfg: Dictionary) -> void:
	cfg = all_cfg
	rules = DungeonRules.new(dungeon_id, entry, float(cfg["tile"]))
	wall_h = float(entry.get("wall_h", cfg["wall_h"]))
	outdoor = entry.has("outdoor")
	name = "Dungeon_" + dungeon_id


static func piece(id: String) -> Node3D:
	var path := KIT % id
	if not ResourceLoader.exists(path):
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		return box
	return (load(path) as PackedScene).instantiate() as Node3D


# The first mesh found in a kit piece (for MultiMeshes).
static func piece_mesh(id: String) -> Mesh:
	var p := piece(id)
	var found: Mesh = null
	for m: Node in p.find_children("*", "MeshInstance3D", true, false):
		found = (m as MeshInstance3D).mesh
		break
	if found == null and p is MeshInstance3D:
		found = (p as MeshInstance3D).mesh
	p.free()
	return found


func build() -> void:
	if built:
		return
	built = true
	var t := rules.tile
	var h := wall_h
	var floors: Array = []  # tiles at floor level
	var tops: Array = []  # every non-wall cell (ceilings)
	var pits: Array = []  # water pits, fog walkways, rafts (their bottoms and water)
	var ledges: Array = []
	var walls: Array = []
	for z in rules.size.y:
		for x in rules.size.x:
			var c := Vector2i(x, z)
			if rules.is_floor(c):
				tops.append(c)
				match rules.terrain(c):
					"=", "%", "_":
						pits.append(c)
					"H":
						ledges.append(c)
					_:
						floors.append(c)
			elif rules.is_wall(c) and _beside_floor(c):
				walls.append(c)
	var dress: Dictionary = rules.cfg.get("dress", {})
	for pair: Array in _mix(floors, dress, ["dk_floor", "dk_floor_worn", "dk_floor_mosaic"], ["floor_worn", "floor_mosaic"], 1):
		_multi(String(pair[0]), pair[1], 0.0)
	if not outdoor:
		_multi("dk_ceiling", tops, wall_h - KIT_H)
	for pair: Array in _mix(walls, dress, ["dk_wall", "dk_wall_crusted", "dk_wall_relief"], ["wall_crusted", "wall_relief"], 2):
		_multi(String(pair[0]), pair[1], 0.0, wall_h / KIT_H)
	if not dress.is_empty():
		_clutter(floors, float(dress.get("clutter", 0.0)), int(dress.get("seed", 1)))
	var doors: Array = []
	for ch: String in rules.of_kind("door"):
		doors.append(rules.things[ch]["cell"])
	if wall_h > KIT_H + 0.1:  # over the doors, up to a tall hall's ceiling: more wall
		_multi("dk_wall", doors, KIT_H, (wall_h - KIT_H) / KIT_H)
	_multi("dk_ledge", ledges, 0.0)
	_multi("dk_floor", pits, -PIT_DEPTH)  # the pits' bottoms
	_water(pits)
	# one body: the floor in runs along each row (none over pits), a slab under the pits, a ceiling slab, a box per
	# wall cell and per ledge
	var body := StaticBody3D.new()
	add_child(body)
	for z in rules.size.y:
		var run_from := -1
		for x in rules.size.x + 1:
			var c := Vector2i(x, z)
			var solid := x < rules.size.x and rules.is_floor(c) and not rules.terrain(c) in ["=", "%", "_"]
			if solid and run_from < 0:
				run_from = x
			elif not solid and run_from >= 0:
				var n := x - run_from
				_box(body, Vector3(n * t, 0.4, t), Vector3((run_from + (n - 1) * 0.5) * t, -0.2, z * t))
				run_from = -1
	var span := Vector3(rules.size.x * t, 0.4, rules.size.y * t)
	var mid := Vector3((rules.size.x - 1) * t * 0.5, -0.2, (rules.size.y - 1) * t * 0.5)
	_box(body, span, mid + Vector3(0.0, -PIT_DEPTH, 0.0))
	if not outdoor:
		_box(body, span, mid + Vector3(0.0, h + 0.4, 0.0))  # (the ceiling)
	for c: Vector2i in walls:
		_box(body, Vector3(t, h, t), rules.at_of(c) + Vector3(0.0, h * 0.5, 0.0))
	if wall_h > KIT_H + 0.1:
		for c: Vector2i in doors:
			_box(body, Vector3(t, h - KIT_H, t), rules.at_of(c) + Vector3(0.0, (h + KIT_H) * 0.5, 0.0))
	for c: Vector2i in ledges:
		_box(body, Vector3(t, 3.0, t), rules.at_of(c) + Vector3(0.0, 1.5, 0.0))
	for c: Vector2i in pits:  # the pits' sides: walls under the floor round them
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb := c + d
			if not rules.terrain(nb) in ["=", "%", "_"]:
				_box(body, Vector3(t if d.x == 0 else 0.2, PIT_DEPTH, t if d.x != 0 else 0.2), rules.at_of(c) + Vector3(d.x * t * 0.5, -PIT_DEPTH * 0.5, d.y * t * 0.5))
	_terrain_nodes()
	for ch: String in rules.things:
		_place(ch)
	_place_torches(walls)
	_flood_sheets()
	refresh(true)


const PIT_DEPTH := 3.0
const KIT_H := 4.5  # the room kit's wall height (tools/blender/sea_dungeon_kit.py H)
const WATER_Y := -0.7
var _fogwalks: Array = []  # [node, body] per fog walkway cell
var _rafts: Array = []  # [node, cell]


func _water(cells: Array) -> void:
	if cells.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := PlaneMesh.new()
	quad.size = Vector2(rules.tile, rules.tile)
	mm.mesh = quad
	mm.instance_count = cells.size()
	for i in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis(), rules.at_of(cells[i]) + Vector3(0.0, WATER_Y, 0.0)))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.42, 0.45, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic_specular = 0.9
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


# Fog walkways, rafts, updraft vents: one node each.
func _terrain_nodes() -> void:
	for z in rules.size.y:
		for x in rules.size.x:
			var c := Vector2i(x, z)
			match rules.terrain(c):
				"%":
					var walk := piece("dk_fogwalk")
					walk.position = rules.at_of(c)
					add_child(walk)
					FxKit.paint(walk, FxKit.glow(Color(0.75, 0.9, 1.0, 0.55), false))
					var b := StaticBody3D.new()
					walk.add_child(b)
					_box(b, Vector3(rules.tile, 0.3, rules.tile), Vector3(0.0, -0.15, 0.0))
					_fogwalks.append([walk, b])
				"_":
					var raft := piece("dk_raft")
					raft.position = rules.at_of(c)
					add_child(raft)
					var rb := StaticBody3D.new()
					raft.add_child(rb)
					_box(rb, Vector3(rules.tile - 0.1, 0.3, rules.tile - 0.1), Vector3(0.0, -0.05, 0.0))
					_rafts.append(raft)
				"u":
					var vent := piece("dk_vent")
					vent.position = rules.at_of(c) + Vector3(0.0, 0.02, 0.0)
					add_child(vent)
					var air := FxKit.particles(Color(0.85, 0.95, 1.0, 0.35), 24, 1.6, 0.25, 6.0, 8.0, 0.0, false, false)
					air.position = Vector3(0.0, 0.2, 0.0)
					vent.add_child(air)


func _beside_floor(c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if rules.is_floor(c + d):
			return true
	return false


# --- the art pass (sea step 9c-3): a dungeon whose entry has "dress" mixes in the kit's variant floors and walls by
# their shares and lays clutter (rubble, urns, coral; drawn only, no collision) against its walls ---

# A cell's own steady roll 0..1 (the same on every machine).
static func _roll(c: Vector2i, salt: int) -> float:
	return fposmod(sin(float(c.x) * 12.9898 + float(c.y) * 78.233 + float(salt) * 37.719) * 43758.5453, 1.0)


# [[piece, cells], ...]: the plain piece for most cells, a variant where the cell's roll falls in its share.
func _mix(cells: Array, dress: Dictionary, pieces: Array, keys: Array, salt: int) -> Array:
	var out: Array = [[pieces[0], []]]
	for k in keys.size():
		out.append([pieces[k + 1], []])
	for c: Vector2i in cells:
		var r := _roll(c, salt + int(dress.get("seed", 1)))
		var pick := 0
		var edge := 0.0
		for k in keys.size():
			edge += float(dress.get(String(keys[k]), 0.0))
			if r < edge:
				pick = k + 1
				break
		(out[pick][1] as Array).append(c)
	return out


func _clutter(floors: Array, share: float, salt: int) -> void:
	if share <= 0.0:
		return
	var keep_off: Array = []  # [cell, cells round it kept clear]: 3 round blocks and plates (a block slides there), 1 round doors and the rest
	for ch: String in rules.things:
		var kind := String(rules.things[ch]["kind"])
		if kind in ["block", "plate"]:
			keep_off.append([rules.things[ch]["cell"], 3])
		elif kind in ["door", "exit", "arrive", "chest", "lever", "key", "bigkey", "ring"]:
			keep_off.append([rules.things[ch]["cell"], 1])
	var kinds := ["dk_rubble", "dk_urns", "dk_coral"]
	var placed := {}
	for k: String in kinds:
		placed[k] = []
	for c: Vector2i in floors:
		if rules.things.has(rules.char_at(c)) or _roll(c, salt + 7) >= share:
			continue
		var near := false
		for pair: Array in keep_off:
			var o: Vector2i = pair[0]
			if absi(o.x - c.x) <= int(pair[1]) and absi(o.y - c.y) <= int(pair[1]):
				near = true
				break
		if near:
			continue
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if rules.is_wall(c + d):
				var face := atan2(float(-d.x), float(-d.y))  # its front away from the wall
				var at := rules.at_of(c) + Vector3(float(d.x), 0.0, float(d.y)) * rules.tile * 0.3
				var kind_c: String = kinds[int(_roll(c, salt + 11) * kinds.size()) % kinds.size()]
				(placed[kind_c] as Array).append(Transform3D(Basis(Vector3.UP, face + (_roll(c, salt + 13) - 0.5) * 0.6), at))
				break
	for k: String in kinds:
		var list: Array = placed[k]
		var mesh := piece_mesh(k)
		if mesh == null or list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)


func _multi(id: String, cells: Array, y: float, stretch: float = 1.0) -> void:
	var mesh := piece_mesh(id)
	if mesh == null or cells.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = cells.size()
	for i in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, stretch, 1.0)), rules.at_of(cells[i]) + Vector3(0.0, y, 0.0)))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


func _box(body: StaticBody3D, box_size: Vector3, at: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = box_size
	shape.shape = b
	shape.position = at
	body.add_child(shape)
	return shape


func _place(ch: String) -> void:
	var th: Dictionary = rules.things[ch]
	var at := rules.at_of(th["cell"])
	var node: Node3D = null
	match String(th["kind"]):
		"door":
			var opens := String(th.get("open", "key"))
			node = piece("dk_door_lock" if opens in ["key", "bigkey", "sealed"] else ("dk_whorl_door" if opens == "whorl" else "dk_door"))
			node.rotation.y = 0.0 if rules.door_along_z(ch) else PI * 0.5
			if opens in ["bigkey", "sealed"]:  # the great doors: a glow on the lock (gold: the Great Key's; sea-green: sealed)
				node.add_child(_halo(Color(1.0, 0.8, 0.3, 0.7) if opens == "bigkey" else Color(0.35, 0.95, 0.8, 0.7), 2.2, Vector3(0.0, 1.6, 0.0)))
			var solid := StaticBody3D.new()
			node.add_child(solid)
			_box(solid, Vector3(2.4, 3.4, 0.4), Vector3(0.0, 1.7, 0.0))
			_solids[ch] = solid
			var frame := StaticBody3D.new()  # the jambs
			node.add_child(frame)
			for side in [-1.0, 1.0]:
				_box(frame, Vector3(0.5, KIT_H, rules.tile), Vector3(side * (rules.tile * 0.5 - 0.25), KIT_H * 0.5, 0.0))
		"plate":
			node = piece("dk_plate")
		"ring":
			node = piece("dk_ring")
		"brazier":
			node = piece("dk_brazier")
			var fire := FxKit.flame()
			if fire != null:
				fire.name = "Fire"
				fire.scale = Vector3.ONE * 0.7
				fire.position = Vector3(0.0, 1.38, 0.0)
				node.add_child(fire)
			var bb := StaticBody3D.new()
			node.add_child(bb)
			_box(bb, Vector3(1.0, 1.4, 1.0), Vector3(0.0, 0.7, 0.0))
		"basin":
			node = piece("dk_basin")
			var bs := StaticBody3D.new()
			node.add_child(bs)
			_box(bs, Vector3(1.4, 1.1, 1.4), Vector3(0.0, 0.55, 0.0))
		"bramble":
			node = piece("dk_bramble")
			node.rotation.y = 0.0 if rules.is_wall(th["cell"] + Vector2i(0, -1)) else PI * 0.5
			var thorns := StaticBody3D.new()
			node.add_child(thorns)
			_box(thorns, Vector3(rules.tile, 3.4, rules.tile), Vector3(0.0, 1.7, 0.0))
			_solids[ch] = thorns
		"lever":
			node = piece("dk_lever")
			node.rotation.y = _face_wall(th["cell"])
		"block":
			node = piece("dk_block")
			var solid2 := StaticBody3D.new()
			node.add_child(solid2)
			_box(solid2, Vector3(2.6, 2.6, 2.6), Vector3(0.0, 1.3, 0.0))
			_solids[ch] = solid2
		"key":
			node = piece("dk_key")
			node.scale = Vector3.ONE * 2.2
			var halo := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(1.6, 1.6)
			halo.mesh = q
			var mat := FxKit.glow(Color(1.0, 0.85, 0.45, 0.6), true, FxKit.soft_dot())
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			halo.material_override = mat
			halo.position = Vector3(0.0, 0.3, 0.0)
			node.add_child(halo)
		"bigkey":
			node = piece("dk_key")
			node.scale = Vector3.ONE * 3.6
			node.add_child(_halo(Color(1.0, 0.75, 0.25, 0.75), 1.4, Vector3(0.0, 0.25, 0.0)))
		"chest":
			node = piece("dk_chest")
			node.rotation.y = _face_wall(th["cell"])
		"exit":
			node = piece("dk_gate")
			node.rotation.y = _face_wall(th["cell"])
			node.scale = Vector3.ONE * 0.62  # (the island's gate, smaller to fit under the vault)
	if node == null:
		return
	node.position = at + Vector3(0.0, rules.height_of(th["cell"]), 0.0)
	add_child(node)
	_nodes[ch] = node


func _halo(color: Color, size_m: float, at: Vector3) -> MeshInstance3D:
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size_m, size_m)
	halo.mesh = q
	var mat := FxKit.glow(color, true, FxKit.soft_dot())
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo.material_override = mat
	halo.position = at
	return halo


# A fight's rising tide: one water sheet over its flood cells (hidden while dry).
func _flood_sheets() -> void:
	for ch: String in rules.of_kind("fight"):
		var f: Array = rules.things[ch].get("flood", [])
		if f.size() != 2 or (rules.things[ch].get("tide", []) as Array).is_empty():
			continue
		var a := rules.at_of(Vector2i(int(f[0][0]), int(f[0][1])))
		var b := rules.at_of(Vector2i(int(f[1][0]), int(f[1][1])))
		var sheet := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(b.x - a.x + rules.tile, b.z - a.z + rules.tile)
		sheet.mesh = plane
		sheet.position = (a + b) * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.38, 0.42, 0.78)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # (seen from under it too)
		mat.roughness = 0.08
		mat.metallic_specular = 0.9
		sheet.material_override = mat
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheet.visible = false
		sheet.position.y = 0.0
		add_child(sheet)
		_floods[ch] = sheet


# Turned so its back is to the nearest wall (a lever, a chest, the exit gate).
func _face_wall(c: Vector2i) -> float:
	for pair: Array in [[Vector2i(0, -1), 0.0], [Vector2i(0, 1), PI], [Vector2i(-1, 0), PI * 0.5], [Vector2i(1, 0), -PI * 0.5]]:
		if rules.is_wall(c + (pair[0] as Vector2i)):
			return float(pair[1])  # (the kit's pieces face +z: front away from that wall)
	return 0.0


func _place_torches(walls: Array) -> void:
	var every := int(rules.cfg.get("torch_every", cfg.get("torch_every", 4)))
	if every <= 0:
		return  # (none: an outdoor court)
	var n := 0
	for c: Vector2i in walls:
		for pair: Array in [[Vector2i(0, 1), 0.0], [Vector2i(0, -1), PI], [Vector2i(1, 0), PI * 0.5], [Vector2i(-1, 0), -PI * 0.5]]:
			var out: Vector2i = pair[0]
			if not rules.is_floor(c + out) or rules.things.has(rules.char_at(c + out)) or rules.terrain(c + out) == "H":
				continue  # (none over a thing or inside a ledge)
			n += 1
			if n % every != 0:
				continue
			var torch := piece("dk_torch")
			var yaw := float(pair[1])
			torch.rotation.y = yaw
			torch.position = rules.at_of(c) + Vector3(out.x, 0.0, out.y) * rules.tile * 0.5
			add_child(torch)
			var flame := FxKit.flame()
			if flame != null:
				flame.scale = Vector3.ONE * 0.35
				torch.add_child(flame)
				flame.position = Vector3(0.0, 2.95, 0.36)
			var halo := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(3.0, 3.0)
			halo.mesh = q
			var mat := FxKit.glow(Color(1.0, 0.6, 0.28, 0.7), true, FxKit.soft_dot())
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			halo.material_override = mat
			halo.position = Vector3(0.0, 3.05, 0.36)
			torch.add_child(halo)
			_torches.append(torch)
			var seen := float(cfg.get("torch_seen_m", 0.0))  # (big dungeons: far torches are not drawn; walls hide them anyway)
			if seen > 0.0:
				for g: Node in torch.find_children("*", "GeometryInstance3D", true, false):
					(g as GeometryInstance3D).visibility_range_end = seen


# --- shown as the state says ---

func refresh(now: bool) -> void:
	if not built:
		return
	for ch: String in _nodes:
		var th: Dictionary = rules.things[ch]
		var node: Node3D = _nodes[ch]
		match String(th["kind"]):
			"door":
				var open := rules.door_open(ch)
				if _solids.has(ch):
					_set_solid(_solids[ch], not open)
				if now:
					_anim[ch] = 1.0 if open else 0.0
			"plate":
				if now:
					_anim[ch] = 1.0 if bool(rules.state["pressed"].get(ch, false)) else 0.0
			"lever":
				if now:
					_anim[ch] = 1.0 if bool(rules.state["levers"].get(ch, false)) else 0.0
			"block":
				if now:
					node.position = rules.at_of(rules.cell_of_thing(ch))
			"key", "bigkey":
				node.visible = not bool(rules.state["taken"].get(ch, false))
			"bramble":
				var burned := bool(rules.state["burned"].get(ch, false))
				node.visible = not burned
				_set_solid(_solids[ch], not burned)
			"brazier":
				var fire_n := node.find_child("Fire", true, false) as Node3D
				if fire_n != null:
					fire_n.visible = bool(rules.state["lit"].get(ch, false))
			"chest":
				if now:
					_anim[ch] = 1.0 if bool(rules.state["taken"].get(ch, false)) else 0.0


func _reveal_shown(now: float) -> void:
	var on := now < float(rules.state["reveal_until"])
	for pair: Array in _fogwalks:
		(pair[0] as Node3D).visible = on
		_set_solid(pair[1], on)


func _set_solid(body: StaticBody3D, on: bool) -> void:
	for s: Node in body.get_children():
		if s is CollisionShape3D:
			(s as CollisionShape3D).disabled = not on


func _process(delta: float) -> void:
	if not built or not visible:
		return
	var raft_y := 0.0 if bool(rules.state["tide"]) else WATER_Y - 1.6
	for raft: Node3D in _rafts:
		raft.position.y = move_toward(raft.position.y, raft_y, delta * 0.8)
	_reveal_shown(sea_seconds.call() if sea_seconds.is_valid() else 0.0)
	for f: String in _floods:  # the tide eases up (0.35 m/s) and drains (0.5 m/s)
		var sheet: MeshInstance3D = _floods[f]
		var level := rules.flood_level(f)
		var y := move_toward(sheet.position.y, level, delta * (0.35 if level > sheet.position.y else 0.5))
		sheet.position.y = y
		sheet.visible = y > 0.03
	for ch: String in _nodes:
		var th: Dictionary = rules.things[ch]
		var node: Node3D = _nodes[ch]
		var kind := String(th["kind"])
		var want := 0.0
		match kind:
			"door":
				want = 1.0 if rules.door_open(ch) else 0.0
			"plate":
				want = 1.0 if bool(rules.state["pressed"].get(ch, false)) else 0.0
			"lever":
				want = 1.0 if bool(rules.state["levers"].get(ch, false)) else 0.0
			"chest":
				want = 1.0 if bool(rules.state["taken"].get(ch, false)) else 0.0
			"block":
				node.position = node.position.move_toward(rules.at_of(rules.cell_of_thing(ch)), delta * 2.0)
				continue
			"basin":
				var w := node.find_child("Water", true, false) as Node3D
				if w != null:
					w.position.y = move_toward(w.position.y, 1.08 if bool(rules.state["tide"]) else 0.85, delta * 0.3)
				continue
			"key", "bigkey":
				node.rotation.y += delta * 1.5
				node.position.y = rules.height_of(th["cell"]) + 0.6 + sin(Time.get_ticks_msec() / 400.0) * 0.12
				continue
			_:
				continue
		var shown := move_toward(float(_anim.get(ch, 0.0)), want, delta * (0.6 if kind == "door" else 3.0))
		_anim[ch] = shown
		match kind:
			"door":
				var leaf := node.find_child("Leaf", true, false) as Node3D
				if leaf != null:
					if String(th.get("open", "key")) in ["key", "bigkey", "sealed"]:
						leaf.rotation.y = -shown * 1.75  # swings in
					elif String(th.get("open", "")) == "whorl":
						leaf.position.y = -shown * 3.4  # sinks into the floor
					else:
						leaf.position.y = shown * 3.2  # the gate slides up
			"plate":
				var top := node.find_child("Plate", true, false) as Node3D
				if top != null:
					top.position.y = -shown * 0.07
			"lever":
				var handle := node.find_child("Handle", true, false) as Node3D
				if handle != null:
					handle.rotation.x = lerpf(-0.6, 0.6, shown)
			"chest":
				var lid := node.find_child("Lid", true, false) as Node3D
				if lid != null:
					lid.rotation.x = -shown * 1.7


# --- the local player inside ---

# The thing within reach of a local point that [F] would use, and what it says: [letter, words] or [].
func usable_at(local: Vector3, facing: Vector3) -> Array:
	var me := rules.cell_of(local)
	var reach := float(cfg.get("reach", 2.2))
	var best: Array = []
	var best_d := INF
	for ch: String in rules.things:
		var th: Dictionary = rules.things[ch]
		var c := rules.cell_of_thing(ch)
		var spot := rules.at_of(c)
		var d := Vector2(local.x - spot.x, local.z - spot.z).length()
		if absf(local.y - rules.height_of(c)) > 2.0:
			continue  # (on a ledge above or below)
		var words := ""
		match String(th["kind"]):
			"key":
				if not bool(rules.state["taken"].get(ch, false)) and d < reach:
					words = "Take the key"
			"bigkey":
				if not bool(rules.state["taken"].get(ch, false)) and d < reach:
					words = "Take the Great Key"
			"door":
				var opens := String(th.get("open", ""))
				if opens == "key" and not rules.door_open(ch) and d < reach + 0.8:
					words = "Unlock the door (keys: %d)" % int(rules.state["keys"]) if int(rules.state["keys"]) > 0 else "Locked: it needs a key"
				elif opens == "bigkey" and not rules.door_open(ch) and d < reach + 0.8:
					words = "Unlock the great door with the Great Key" if bool(rules.state["big"]) else "Locked: it needs the Great Key"
				elif opens == "sealed" and d < reach + 0.8:
					words = String(th.get("says", "Sealed fast"))
			"lever":
				if d < reach:
					words = "Pull the lever"
			"chest":
				if not bool(rules.state["taken"].get(ch, false)) and d < reach:
					words = "Open the chest"
			"exit":
				if d < reach + 0.6:
					words = "Leave %s" % String(rules.cfg.get("name", "the dungeon"))
			"block":
				var way := c - me
				if absi(way.x) + absi(way.y) == 1 and d < rules.tile * 1.3 and Vector2(facing.x, facing.z).normalized().dot(Vector2(way.x, way.y)) > 0.6:
					words = "Push the block" if rules.push_to(ch, me).x >= 0 else "The block won't move that way"
		if words != "" and d < best_d:
			best_d = d
			best = [ch, words]
	return best


func status() -> String:
	var open: Array = []
	for d: String in rules.of_kind("door"):
		if rules.door_open(d):
			open.append(d)
	return "%s: keys %d, great key %s, fights on %s cleared %s, doors open %s, pressed %s, levers %s, blocks %s, taken %s, burned %s, lit %s, tide %s, reveal till %.0f" % [rules.id, int(rules.state["keys"]), str(rules.state["big"]), str(rules.state["active"]), str(rules.state["cleared"].keys()), str(open), str(rules.state["pressed"]), str(rules.state["levers"]), str(rules.state["blocks"]), str(rules.state["taken"].keys()),
		str(rules.state["burned"].keys()), str(rules.state["lit"].keys()), str(rules.state["tide"]), float(rules.state["reveal_until"])]
