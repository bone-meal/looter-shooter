# Purpose: SWAMP GAS's clouds (diary/DESIGN_UNIQUES.md, region 2 chase gun): every shot of the gun leaves a small
# cloud of green swamp gas hanging where it went. Any fire sets a cloud off (a burning enemy inside it, a burning path
# or inferno, a running fire pit, any blast's flash: nodes in group "fire_sources" answer fire_near); a cloud going
# off is itself a blast, so the flash sets off every cloud near it: a chain. Pool of a few clouds, oldest replaced.
# Numbers from the gun's data "cfg" (data/gun_uniques.json swamp_gas). ONLINE (game/net_chase.gd): our clouds are
# told to the others, who show copies; a copy near fire on their machine tells us, and our cloud goes off.
# Dependencies: game/explosives.gd (blast, its enemy source, sounds), groups "fire_sources", "net_chase" (optional).
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")

const POOL_SIZE := 8
const CHECK_EVERY := 0.1  # seconds between looks for fire

var explosives: Node3D

var _puffs: Array[Node3D] = []  # two modelled puffs per cloud (game/fx_kit.gd gas_cloud), the first with rising bubbles
var _life := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _fuse := PackedFloat32Array()  # > 0: caught fire, goes off when it reaches 0 (the chain's small delay)
var _owner := PackedInt32Array()  # 0 = our own cloud; else the peer whose cloud this is a copy of
var _their_slot := PackedInt32Array()
var _asked := PackedByteArray()  # a copy already told its owner it caught fire
var _cfg: Dictionary = {}
var _check := 0.0
var _clock := 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("swamp_gas")
	_material = FxKit.glow(Color(0.6, 0.76, 0.28, 0.5), false)  # seen from outside only (no green wash with the eye inside)
	for i in POOL_SIZE * 2:
		var puff_node: Node3D = FxKit.shape("gas_cloud")
		if puff_node == null:
			puff_node = Node3D.new()
		FxKit.paint(puff_node, _material)
		puff_node.rotation.y = float(i) * 1.7
		puff_node.visible = false
		add_child(puff_node)
		_puffs.append(puff_node)
		if i % 2 == 0:  # swamp bubbles rising out of the cloud
			var bubbles := FxKit.particles(Color(0.55, 0.7, 0.25, 0.8), 6, 1.6, 0.18, 1.2, 25.0, 0.2, false)
			bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			bubbles.emission_sphere_radius = 0.7
			bubbles.emitting = false
			puff_node.add_child(bubbles)
	_life.resize(POOL_SIZE)
	_damage.resize(POOL_SIZE)
	_fuse.resize(POOL_SIZE)
	_owner.resize(POOL_SIZE)
	_their_slot.resize(POOL_SIZE)
	_asked.resize(POOL_SIZE)
	if _cfg.is_empty():  # a copy may come before any cloud of ours: the gun's own numbers
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_uniques.json"))
		if data is Dictionary:
			_cfg = (((data as Dictionary).get("uniques", {}) as Dictionary).get("swamp_gas", {}) as Dictionary).get("cfg", {})


# A new cloud at `at` (cfg: radius, seconds, damage share of the gun's damage).
func puff(at: Vector3, cfg: Dictionary, gun_damage: float) -> void:
	_cfg = cfg
	var i := _slot_for_new()
	_owner[i] = 0
	_show(i, at)
	_damage[i] = gun_damage * float(cfg.get("pop_damage", 2.5))
	_tell("gas", i, _puffs[i * 2].position)


func _slot_for_new() -> int:
	var i := 0
	for k in POOL_SIZE:
		if _life[k] <= 0.0:
			return k
		if _life[k] < _life[i]:
			i = k
	return i


func _show(i: int, at: Vector3) -> void:
	var r := float(_cfg.get("cloud_radius", 1.8))
	_life[i] = float(_cfg.get("cloud_seconds", 9.0))
	_fuse[i] = 0.0
	_asked[i] = 0
	for n in 2:
		var p := _puffs[i * 2 + n]
		p.position = at + Vector3(randf_range(-0.3, 0.3), randf_range(-0.1, 0.3), randf_range(-0.3, 0.3)) * r
		p.scale = Vector3.ONE * r * (0.75 if n == 0 else 0.6)
		p.visible = true
		_bubble(p, true)


func active_count() -> int:
	var n := 0
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			n += 1
	return n


func _process(delta: float) -> void:
	_clock += delta
	if active_count() == 0:
		return
	_check -= delta
	var look := _check <= 0.0
	if look:
		_check = CHECK_EVERY
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		var at := _puffs[i * 2].position
		var r := float(_cfg.get("cloud_radius", 1.8))
		for n in 2:  # it drifts up a little and breathes
			var p := _puffs[i * 2 + n]
			p.position.y += delta * 0.08
			p.scale = Vector3.ONE * r * (0.75 if n == 0 else 0.6) * (1.0 + 0.06 * sin(_clock * 2.0 + float(i * 2 + n)))
		if _fuse[i] > 0.0:
			_fuse[i] -= delta
			if _fuse[i] <= 0.0:
				_go_off(i)
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_hide(i)
			continue
		if look and _fire_near(at, r):
			if _owner[i] == 0:
				_fuse[i] = float(_cfg.get("chain_delay", 0.12))
			elif _asked[i] == 0:  # somebody else's cloud near fire here: its owner sets it off
				_asked[i] = 1
				var link := _link()
				if link != null:
					link.call("send", "gas_lit", _their_slot[i], at, _owner[i])


func _fire_near(at: Vector3, r: float) -> bool:
	for source: Node in get_tree().get_nodes_in_group("fire_sources"):
		if source.call("fire_near", at, r):
			return true
	if explosives != null and explosives.source != null:
		for enemy: Node3D in explosives.source.enemy_list():
			if is_instance_valid(enemy) and enemy.has_method("is_burning") and enemy.is_burning() and enemy.global_position.distance_to(at) <= r + 0.6:
				return true
	return false


func _go_off(i: int) -> void:
	var at := _puffs[i * 2].position
	var r := float(_cfg.get("cloud_radius", 1.8)) * float(_cfg.get("blast_scale", 1.6))
	_hide(i)
	_tell("gas_pop", i, at)
	if explosives == null:
		return
	explosives.blast(at, r, _damage[i])  # its flash reaches the next cloud: the chain goes on
	if explosives.sounds != null:
		explosives.sounds.call("play", "explosion", at)
	if explosives.source != null:
		for enemy: Node3D in explosives.source.enemy_list():
			if is_instance_valid(enemy) and enemy.has_method("apply_burn") and enemy.global_position.distance_to(at) <= r:
				enemy.apply_burn(_damage[i] * float(_cfg.get("burn_share", 0.15)), 3.0)


func _hide(i: int) -> void:
	_life[i] = 0.0
	_fuse[i] = 0.0
	_puffs[i * 2].visible = false
	_puffs[i * 2 + 1].visible = false
	_bubble(_puffs[i * 2], false)


func _bubble(puff_node: Node3D, on: bool) -> void:
	for child in puff_node.get_children():
		if child is CPUParticles3D:
			(child as CPUParticles3D).emitting = on


# ---- online (game/net_chase.gd) ----

# Another player's cloud: a copy hangs here (it never blasts by itself).
func remote_puff(holder: int, slot: int, at: Vector3) -> void:
	var i := _copy_of(holder, slot)
	if i < 0:
		i = _slot_for_new()
	_owner[i] = holder
	_their_slot[i] = slot
	_show(i, at)
	_life[i] += 1.0  # the owner says when it is gone


# The owner's cloud went off (his blast did the damage): ours shows the blast.
func remote_pop(holder: int, slot: int, at: Vector3) -> void:
	var i := _copy_of(holder, slot)
	if i >= 0:
		_hide(i)
	if explosives != null:
		explosives.show_flash(at, float(_cfg.get("cloud_radius", 1.8)) * float(_cfg.get("blast_scale", 1.6)))
		if explosives.sounds != null:
			explosives.sounds.call("play", "explosion", at)


# A teammate saw fire at our cloud on his machine: it goes off.
func friend_lit(slot: int) -> void:
	if slot >= 0 and slot < POOL_SIZE and _life[slot] > 0.0 and _owner[slot] == 0 and _fuse[slot] <= 0.0:
		_fuse[slot] = float(_cfg.get("chain_delay", 0.12))


func _copy_of(holder: int, slot: int) -> int:
	for i in POOL_SIZE:
		if _life[i] > 0.0 and _owner[i] == holder and _their_slot[i] == slot:
			return i
	return -1


func _tell(kind: String, i: int, at: Vector3) -> void:
	if _owner[i] != 0:
		return
	var link := _link()
	if link != null:
		link.call("send", kind, i, at)


func _link() -> Node:
	return get_tree().get_first_node_in_group("net_chase") if is_inside_tree() else null
