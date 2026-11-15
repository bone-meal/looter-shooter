# Purpose: GRILLMASTER's party barbecue (diary/DESIGN_UNIQUES.md, region 3 chase gun): grilled food dropped where a
# burning enemy fell to the gun. Any player who walks over it eats it and heals. Pool in the world, each food lasts
# a while, turning and bobbing. ONLINE (game/net_chase.gd): the dropper tells everyone ("food"), each machine shows
# it; whoever walks over it asks the host ("food_take"), and the host alone decides who got it ("food_gone"), so
# one kebab feeds one player. Offline it is eaten at once.
# Dependencies: assets/models/weapons/uniques/grilled_kebab.gltf; the local player (`eater`: health);
# group "net_chase" (optional).
extends Node3D

const POOL_SIZE := 12
const MODEL := "res://assets/models/weapons/uniques/grilled_kebab.gltf"
const REACH := 1.3  # metres from the player's feet that count as walking over it

var eater: Node3D  # the local player
var eaten := 0  # meals eaten on this machine (dev: !grill)

var _food: Array[Node3D] = []
var _life := PackedFloat32Array()
var _heal := PackedFloat32Array()  # share of max health it gives
var _owner := PackedInt32Array()  # the peer who dropped it (0 = us, offline or online)
var _their_slot := PackedInt32Array()
var _asked := PackedByteArray()  # we asked the host for it already
var _base := PackedVector3Array()
var _t := 0.0


func _ready() -> void:
	add_to_group("grill_food")
	var scene: PackedScene = load(MODEL) if ResourceLoader.exists(MODEL) else null
	for i in POOL_SIZE:
		var node: Node3D
		if scene != null:
			node = scene.instantiate() as Node3D
			node.scale = Vector3.ONE * 2.0  # big enough to see on the ground
		else:
			node = MeshInstance3D.new()
			(node as MeshInstance3D).mesh = BoxMesh.new()
			node.scale = Vector3(0.1, 0.1, 0.4)
		node.visible = false
		add_child(node)
		_food.append(node)
	_life.resize(POOL_SIZE)
	_heal.resize(POOL_SIZE)
	_owner.resize(POOL_SIZE)
	_their_slot.resize(POOL_SIZE)
	_asked.resize(POOL_SIZE)
	_base.resize(POOL_SIZE)


# Our own drop: shown here and told to the others. Returns its slot.
func drop(at: Vector3, heal_share: float, seconds: float) -> int:
	var i := _free_slot()
	_place(i, at, heal_share, seconds, 0, i)
	var link := _link()
	if link != null:
		link.call("send", "food", i, at)
	return i


# Another player's drop, told by the host.
func remote_drop(owner: int, slot: int, at: Vector3, heal_share: float, seconds: float) -> void:
	_place(_free_slot(), at, heal_share, seconds, owner, slot)


# The host says this food is gone (eaten by `taker`): it vanishes; if we were the taker we eat.
func gone(owner: int, slot: int, taker: int) -> void:
	for i in POOL_SIZE:
		if _life[i] > 0.0 and _owner_id(i) == owner and _their_slot[i] == slot:
			if taker == _my_id():
				_eat(i)
			_life[i] = 0.0
			_food[i].visible = false


func active_count() -> int:
	var n := 0
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			n += 1
	return n


func _process(delta: float) -> void:
	_t += delta
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_food[i].visible = false
			continue
		_food[i].position = _base[i] + Vector3(0, 0.35 + sin(_t * 2.5 + float(i)) * 0.06, 0)
		_food[i].rotation.y = _t * 1.4 + float(i)
		if eater != null and _asked[i] == 0 and eater.global_position.distance_to(_base[i]) <= REACH:
			_take(i)


func _take(i: int) -> void:
	var link := _link()
	if link == null or not bool(link.call("active")):  # offline: eaten at once
		_eat(i)
		_life[i] = 0.0
		_food[i].visible = false
		return
	_asked[i] = 1  # the host decides (first come, first fed)
	link.call("send", "food_take", _their_slot[i], _base[i], _owner_id(i))


func _eat(i: int) -> void:
	eaten += 1
	var health: Variant = eater.get("health") if eater != null else null
	if health != null:
		health.call("heal", float(health.get("max_hp")) * _heal[i])
	var numbers: Variant = eater.get("damage_numbers") if eater != null else null
	if numbers is Node:
		(numbers as Node).call("say", _base[i] + Vector3(0, 1.0, 0), "BARBECUE", Color(1.0, 0.7, 0.3))


func _place(i: int, at: Vector3, heal_share: float, seconds: float, owner: int, slot: int) -> void:
	_base[i] = at
	_heal[i] = heal_share
	_life[i] = seconds
	_owner[i] = owner
	_their_slot[i] = slot
	_asked[i] = 0
	_food[i].position = at
	_food[i].visible = true


func _free_slot() -> int:
	var oldest := 0
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			return i
		if _life[i] < _life[oldest]:
			oldest = i
	return oldest


# Who dropped food i, as a peer id (our own drops = our id).
func _owner_id(i: int) -> int:
	return _owner[i] if _owner[i] != 0 else _my_id()


func _my_id() -> int:
	var link := _link()
	return int(link.call("my_id")) if link != null else 1


func _link() -> Node:
	return get_tree().get_first_node_in_group("net_chase") if is_inside_tree() else null
