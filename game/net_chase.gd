# Purpose: the chase guns' effects for the other players (AVALANCHE CONTROL: a snowball "snowball": from, flat direction) (director 2026-11-15: "effects should be seen by online
# players too"). The holder's machine plays an effect and tells the host; the host passes it to everyone else, who
# show it. CROAK: where the holder's frog is (leaping, riding an enemy's head) or that it is back on the gun.
# KEEPER'S LANTERN: a thrown lantern ("bomb": from, velocity) flies and burns on every machine (damage only from the
# thrower's own). SWAMP GAS: the holder's clouds (made, gone off); a copy of a cloud near fire on another machine (a teammate's
# inferno, his burning enemy) tells the owner, whose cloud goes off for real (his blast, his damage).
# Node "Chase" under game/net_session.gd (`chase`). (The Mixtape and the beach balls have their own: net_mixtape.gd,
# net_beachballs.gd.)
# Dependencies: game/net_session.gd (parent `net`), game/swamp_gas.gd (copies), the croak_frog model.
extends Node

const SwampGas = preload("res://game/swamp_gas.gd")
const FROG := "res://assets/models/weapons/uniques/croak_frog.gltf"
const KINDS := ["frog", "frog_off", "gas", "gas_pop", "gas_lit", "bomb", "food", "food_take", "geyser", "potato", "penguin", "snowball"]
const PenguinRescue = preload("res://game/signatures/penguin_rescue.gd")
const AvalancheControl = preload("res://game/signatures/avalanche_control.gd")
const HotPotato = preload("res://game/signatures/hot_potato.gd")
const VolcanoSauce = preload("res://game/signatures/volcano_sauce.gd")
const Grillmaster = preload("res://game/signatures/grillmaster.gd")
const KeepersLantern = preload("res://game/signatures/keepers_lantern.gd")
const FAR := 100000.0

var net: Node3D
var sent := 0
var heard := 0
var _frogs := {}  # peer -> the copy of his frog
var _frog_goal := {}  # peer -> where his frog is now (the copy glides there)
var _foods := {}  # host: "owner:slot" -> engine time it spoils (Grillmaster's food not yet eaten)


func _ready() -> void:
	add_to_group("net_chase")


func active() -> bool:
	return net != null and net.can_send()


func my_id() -> int:
	return int(net.my_id()) if net != null else 1


# From an effect on this machine. slot = which of our things (a cloud's number), target = whose thing it is (gas_lit).
func send(kind: String, slot: int, at: Vector3, target: int = 0, b: Vector3 = Vector3.ZERO) -> void:
	if not active():
		return
	sent += 1
	if net.is_host():
		_pass_on(my_id(), kind, slot, at, target, b)
	else:
		_up.rpc_id(1, kind, slot, at, target, b)


@rpc("any_peer", "call_remote", "reliable")
func _up(kind: String, slot: int, at: Vector3, target: int, b: Vector3) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not net.is_host() or not net.roster.has(from) or not KINDS.has(kind) or slot < -1 or slot > 64:
		return
	if not at.is_finite() or at.length() > FAR or not b.is_finite() or b.length() > FAR:
		return
	_pass_on(from, kind, slot, at, target, b)


func _pass_on(from: int, kind: String, slot: int, at: Vector3, target: int, b: Vector3) -> void:
	if kind == "food_take":  # the host alone decides who ate it: first come, first fed
		var key := "%d:%d" % [target, slot]
		if float(_foods.get(key, 0.0)) > Time.get_ticks_msec() / 1000.0:
			_foods.erase(key)
			_down.rpc(target, "food_gone", slot, at, from, b)
			_down(target, "food_gone", slot, at, from, b)
		return
	if kind == "food":
		_foods["%d:%d" % [from, slot]] = Time.get_ticks_msec() / 1000.0 + float(_grill_cfg().get("food_seconds", 20.0))
	_down.rpc(from, kind, slot, at, target, b)
	_down(from, kind, slot, at, target, b)


@rpc("authority", "call_remote", "reliable")
func _down(from: int, kind: String, slot: int, at: Vector3, target: int, b: Vector3) -> void:
	if from == my_id() and kind != "food_gone":
		return  # our own news, already done here
	heard += 1
	match kind:
		"frog":
			_frog_goal[from] = at
			var frog := _frog_of(from)
			if frog != null and not frog.visible:
				frog.global_position = at
				frog.visible = true
		"frog_off":
			_frog_goal.erase(from)
			if _frogs.has(from) and is_instance_valid(_frogs[from]):
				(_frogs[from] as Node3D).visible = false
		"gas":
			var gas := gas_pool()
			if gas != null:
				gas.remote_puff(from, slot, at)
		"gas_pop":
			var gas_p := gas_pool()
			if gas_p != null:
				gas_p.remote_pop(from, slot, at)
		"bomb":  # another player's thrown lantern: it flies and burns here too (no damage from ours)
			var me: Node3D = net.local_player()
			if me != null and me.get_parent() != null:
				KeepersLantern.throw_bomb(me.get_parent(), me.get("explosives"), at, b, false, 0.0, _lantern_cfg(), [])
		"penguin":  # another player's freed penguin: it slides to where it was aimed and pops (no damage from ours)
			var me_n: Node3D = net.local_player()
			if me_n != null:
				PenguinRescue.release(me_n.get_parent(), me_n.get("explosives"), at, null, b, false, 0.0, {})
		"snowball":  # another player's Avalanche Control snowball: it rolls the same way here (no damage from ours)
			var me_s: Node3D = net.local_player()
			if me_s != null:
				AvalancheControl.roll(me_s.get_parent(), me_s.get("explosives"), at, Vector3(b.x, 0.0, b.z).normalized(), false, 0.0, cfg_of("avalanche_control"))
		"potato":  # another player's thrown Hot Potato: it flies and goes off here too (no damage from ours)
			var me_p: Node3D = net.local_player()
			if me_p != null:
				HotPotato.throw_bomb(me_p.get_parent(), me_p.get("explosives"), at, b, false, 0.0, 6.0, [])
		"geyser":  # another player's Volcano Sauce eruption: shown here (no damage from ours)
			var me_g: Node3D = net.local_player()
			if me_g != null:
				VolcanoSauce.erupt(me_g.get_parent(), me_g.get("explosives"), at, false, 0.0, _sauce_cfg())
		"food":  # another player's barbecue: it lies here too
			var food := Grillmaster.pool(net.local_player())
			if food != null:
				food.remote_drop(from, slot, at, float(_grill_cfg().get("heal_share", 0.25)), float(_grill_cfg().get("food_seconds", 20.0)))
		"food_gone":  # (from = who dropped it, target = who ate it)
			var food_g := Grillmaster.pool(net.local_player())
			if food_g != null:
				food_g.gone(from, slot, target)
		"gas_lit":
			if target == my_id():
				var gas_l := gas_pool()
				if gas_l != null:
					gas_l.friend_lit(slot)


func _process(delta: float) -> void:
	for peer: int in _frog_goal:
		var frog: Node3D = _frogs.get(peer)
		if frog != null and is_instance_valid(frog) and frog.visible:
			frog.global_position = frog.global_position.lerp(_frog_goal[peer], minf(1.0, delta * 10.0))


func _frog_of(peer: int) -> Node3D:
	if _frogs.has(peer) and is_instance_valid(_frogs[peer]):
		return _frogs[peer]
	var me: Node3D = net.local_player() if net != null else null
	if me == null or me.get_parent() == null or not ResourceLoader.exists(FROG):
		return null
	var frog := (load(FROG) as PackedScene).instantiate() as Node3D
	frog.scale = Vector3.ONE * 1.6
	frog.visible = false
	me.get_parent().add_child(frog)
	_frogs[peer] = frog
	return frog


# This machine's gas clouds (made on first use next to our player).
func gas_pool() -> SwampGas:
	var found := get_tree().get_first_node_in_group("swamp_gas") as SwampGas
	var me: Node3D = net.local_player() if net != null else null
	if found == null and me != null and me.get_parent() != null:
		found = SwampGas.new()
		found.name = "SwampGas"
		me.get_parent().add_child(found)
	if found != null and found.explosives == null and me != null:
		found.explosives = me.get("explosives")
	return found


func _lantern_cfg() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_uniques.json"))
	return ((((data as Dictionary).get("uniques", {}) as Dictionary).get("keepers_lantern", {}) as Dictionary).get("cfg", {})) if data is Dictionary else {}


func _grill_cfg() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_uniques.json"))
	return ((((data as Dictionary).get("uniques", {}) as Dictionary).get("grillmaster", {}) as Dictionary).get("cfg", {})) if data is Dictionary else {}


func _sauce_cfg() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_uniques.json"))
	return ((((data as Dictionary).get("uniques", {}) as Dictionary).get("volcano_sauce", {}) as Dictionary).get("cfg", {})) if data is Dictionary else {}


# A chase gun's "cfg" from data/gun_uniques.json.
func cfg_of(unique_id: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_uniques.json"))
	return ((((data as Dictionary).get("uniques", {}) as Dictionary).get(unique_id, {}) as Dictionary).get("cfg", {})) if data is Dictionary else {}
