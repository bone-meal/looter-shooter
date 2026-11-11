# Purpose: shows other players' regular enemies as see-through spirits (look only: no collision, no attacks). Streams our own enemies' positions to the others.
# Dependencies: game/net_session.gd (parent; `net`, `director`), game/character_models.gd, data/enemies.json, data/net.json.
extends Node

const CharacterModels = preload("res://game/character_models.gd")
const DataStore = preload("res://core/data_store.gd")

var net: Node3D
var director: Node3D  # our wave director (enemy_list)

var _stats: Dictionary
var _kinds: Array = []
var _mat := StandardMaterial3D.new()
var _spirits := {}  # owner peer id -> Array of {"node": Node3D, "kind": int, "pos": Vector3, "yaw": float}
var _timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stats = DataStore.load_json("res://data/enemies.json")["enemies"]
	_kinds = net.config("spirit_kinds")
	_mat.albedo_color = Color(0.6, 0.85, 1.0, 0.32)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = false


func _process(delta: float) -> void:
	var k := 1.0 - exp(-10.0 * delta)
	for owner_id in _spirits:
		for s in _spirits[owner_id]:
			var node: Node3D = s["node"]
			if node.visible:
				node.global_position = node.global_position.lerp(s["pos"], k)
				node.rotation.y = lerp_angle(node.rotation.y, s["yaw"], k)
	if net == null or not net.started or not net.can_send() or director == null or not is_instance_valid(director):
		return
	_timer += delta
	if _timer < 1.0 / float(net.config("spirit_rate_hz")):
		return
	_timer = 0.0
	var data := _snapshot()
	if net.is_host():
		_spirits_broadcast.rpc(1, data)
	else:
		_spirits_to_host.rpc_id(1, data)


# 5 numbers per enemy: kind index, x, y, z, yaw. The boss is not included (it is shared for real).
func _snapshot() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var cap := int(net.config("spirit_cap"))
	var count := 0
	for e in director.enemy_list():
		if count >= cap:
			break
		if not is_instance_valid(e):
			continue
		var kind := _kinds.find(e.enemy_id)
		if kind < 0:
			continue
		out.append(float(kind))
		out.append(e.global_position.x)
		out.append(e.global_position.y)
		out.append(e.global_position.z)
		out.append(e.rotation.y)
		count += 1
	return out


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _spirits_to_host(data: PackedFloat32Array) -> void:
	if not net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not net.roster.has(id) or data.size() > int(net.config("spirit_cap")) * 5:
		return
	_apply(id, data)
	_spirits_broadcast.rpc(id, data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _spirits_broadcast(owner_id: int, data: PackedFloat32Array) -> void:
	_apply(owner_id, data)


func _apply(owner_id: int, data: PackedFloat32Array) -> void:
	if net.world() == null or owner_id == multiplayer.get_unique_id():
		return
	if not _spirits.has(owner_id):
		_spirits[owner_id] = []
	var list: Array = _spirits[owner_id]
	var count := floori(data.size() / 5.0)
	for i in count:
		var kind := int(data[i * 5])
		if kind < 0 or kind >= _kinds.size():
			continue
		if i >= list.size():
			list.append(_make(kind))
		elif list[i]["kind"] != kind:
			list[i]["node"].queue_free()
			list[i] = _make(kind)
		var s: Dictionary = list[i]
		var target := Vector3(data[i * 5 + 1], data[i * 5 + 2], data[i * 5 + 3])
		if not target.is_finite():
			continue
		if not s["node"].visible:
			s["node"].global_position = target  # newly shown: appear in place
			s["node"].visible = true
		s["pos"] = target
		s["yaw"] = data[i * 5 + 4]
	for i in range(count, list.size()):
		list[i]["node"].visible = false


func _make(kind: int) -> Dictionary:
	var id := String(_kinds[kind])
	var stats: Dictionary = _stats[id]
	var model_name := String(stats["model"]).trim_prefix("skeleton_")
	var model := CharacterModels.skeleton(model_name, _mat, Color(0.6, 0.85, 1.0))
	var size_y := float((stats["size"] as Array)[1])
	model.scale = Vector3.ONE * (size_y / 1.8)
	_tint_all(model)
	model.visible = false
	net.world().add_child(model)
	return {"node": model, "kind": kind, "pos": Vector3.ZERO, "yaw": 0.0}


func _tint_all(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _mat
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_tint_all(child)


func remove_owner(owner_id: int) -> void:
	if _spirits.has(owner_id):
		for s in _spirits[owner_id]:
			if is_instance_valid(s["node"]):
				s["node"].queue_free()
		_spirits.erase(owner_id)


func clear_all() -> void:
	for owner_id in _spirits.keys():
		remove_owner(owner_id)
