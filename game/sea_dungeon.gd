# Purpose: one dungeon's space (sea step 9a, LOCKED: hand-made from a room kit, own space behind the door): drawn from
# its map with the room kit (one MultiMesh each for floors, walls, ceilings; a node per door, plate, lever, block,
# key, chest, torch, the exit gate), solid (one body of boxes; closed doors and blocks have their own), and shown in the
# state the rules hold (doors slide / swing, plates sink, levers lean, blocks glide, keys vanish, chest lids open).
# The local player's prompts here and what [F] asks for go to the manager (game/sea_dungeons.gd), which applies them
# (host / alone) or asks the host.
# Dependencies: core/sea/dungeon_rules.gd, assets/models/sea/dungeon/*.gltf (tools/blender/sea_dungeon_kit.py),
# game/fx_kit.gd. Placed under the sea root at its space (sea coordinates) by the manager.
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


func setup(dungeon_id: String, entry: Dictionary, all_cfg: Dictionary) -> void:
	cfg = all_cfg
	rules = DungeonRules.new(dungeon_id, entry, float(cfg["tile"]))
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
	var h := float(cfg["wall_h"])
	var floors: Array = []
	var walls: Array = []
	for z in rules.size.y:
		for x in rules.size.x:
			var c := Vector2i(x, z)
			if rules.is_floor(c):
				floors.append(c)
			elif rules.is_wall(c) and _beside_floor(c):
				walls.append(c)
	_multi("dk_floor", floors, 0.0)
	_multi("dk_ceiling", floors, 0.0)
	_multi("dk_wall", walls, 0.0)
	# one body: a floor slab under the whole map, a ceiling slab over it, a box per wall cell
	var body := StaticBody3D.new()
	add_child(body)
	var span := Vector3(rules.size.x * t, 0.4, rules.size.y * t)
	var mid := Vector3((rules.size.x - 1) * t * 0.5, -0.2, (rules.size.y - 1) * t * 0.5)
	_box(body, span, mid)
	_box(body, span, mid + Vector3(0.0, h + 0.4, 0.0))
	for c: Vector2i in walls:
		_box(body, Vector3(t, h, t), rules.at_of(c) + Vector3(0.0, h * 0.5, 0.0))
	for ch: String in rules.things:
		_place(ch)
	_place_torches(walls)
	refresh(true)


func _beside_floor(c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if rules.is_floor(c + d):
			return true
	return false


func _multi(id: String, cells: Array, yaw: float) -> void:
	var mesh := piece_mesh(id)
	if mesh == null or cells.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = cells.size()
	for i in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), rules.at_of(cells[i])))
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
			node = piece("dk_door_lock" if String(th.get("open", "key")) == "key" else "dk_door")
			node.rotation.y = 0.0 if rules.door_along_z(ch) else PI * 0.5
			var solid := StaticBody3D.new()
			node.add_child(solid)
			_box(solid, Vector3(2.4, 3.4, 0.4), Vector3(0.0, 1.7, 0.0))
			_solids[ch] = solid
			var frame := StaticBody3D.new()  # the jambs
			node.add_child(frame)
			for side in [-1.0, 1.0]:
				_box(frame, Vector3(0.5, float(cfg["wall_h"]), rules.tile), Vector3(side * (rules.tile * 0.5 - 0.25), float(cfg["wall_h"]) * 0.5, 0.0))
		"plate":
			node = piece("dk_plate")
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
		"chest":
			node = piece("dk_chest")
			node.rotation.y = _face_wall(th["cell"])
		"exit":
			node = piece("dk_gate")
			node.rotation.y = _face_wall(th["cell"])
			node.scale = Vector3.ONE * 0.62  # (the island's gate, smaller to fit under the vault)
	if node == null:
		return
	node.position = at
	add_child(node)
	_nodes[ch] = node


# Turned so its back is to the nearest wall (a lever, a chest, the exit gate).
func _face_wall(c: Vector2i) -> float:
	for pair: Array in [[Vector2i(0, -1), 0.0], [Vector2i(0, 1), PI], [Vector2i(-1, 0), PI * 0.5], [Vector2i(1, 0), -PI * 0.5]]:
		if rules.is_wall(c + (pair[0] as Vector2i)):
			return float(pair[1])  # (the kit's pieces face +z: front away from that wall)
	return 0.0


func _place_torches(walls: Array) -> void:
	var every := maxi(int(cfg.get("torch_every", 4)), 1)
	var n := 0
	for c: Vector2i in walls:
		for pair: Array in [[Vector2i(0, 1), 0.0], [Vector2i(0, -1), PI], [Vector2i(1, 0), PI * 0.5], [Vector2i(-1, 0), -PI * 0.5]]:
			var out: Vector2i = pair[0]
			if not rules.is_floor(c + out) or rules.things.has(rules.char_at(c + out)):
				continue
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
			"key":
				node.visible = not bool(rules.state["taken"].get(ch, false))
			"chest":
				if now:
					_anim[ch] = 1.0 if bool(rules.state["taken"].get(ch, false)) else 0.0


func _set_solid(body: StaticBody3D, on: bool) -> void:
	for s: Node in body.get_children():
		if s is CollisionShape3D:
			(s as CollisionShape3D).disabled = not on


func _process(delta: float) -> void:
	if not built or not visible:
		return
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
			"key":
				node.rotation.y += delta * 1.5
				node.position.y = 0.6 + sin(Time.get_ticks_msec() / 400.0) * 0.12
				continue
			_:
				continue
		var shown := move_toward(float(_anim.get(ch, 0.0)), want, delta * (0.6 if kind == "door" else 3.0))
		_anim[ch] = shown
		match kind:
			"door":
				var leaf := node.find_child("Leaf", true, false) as Node3D
				if leaf != null:
					if String(th.get("open", "key")) == "key":
						leaf.rotation.y = -shown * 1.75  # swings in
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
		var words := ""
		match String(th["kind"]):
			"key":
				if not bool(rules.state["taken"].get(ch, false)) and d < reach:
					words = "Take the key"
			"door":
				if String(th.get("open", "")) == "key" and not rules.door_open(ch) and d < reach + 0.8:
					words = "Unlock the door (keys: %d)" % int(rules.state["keys"]) if int(rules.state["keys"]) > 0 else "Locked: it needs a key"
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
	return "%s: keys %d, doors open %s, pressed %s, levers %s, blocks %s, taken %s" % [rules.id, int(rules.state["keys"]), str(open), str(rules.state["pressed"]), str(rules.state["levers"]), str(rules.state["blocks"]), str(rules.state["taken"].keys())]
