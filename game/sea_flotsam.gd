# Purpose: FLOATING CARGO at sea (sea step 8; director: loot = floating debris you sail through to collect, and drops
# on deck after a boarding fight): barrels, crates and sea chests a sunk pirate ship leaves, bobbing on the waves.
# Sailing a ship through one (reach_ship of her middle line) or swimming to it picks it up; the HOST decides who got
# it (first come); the one who got it rolls its loot himself (doubloons, materials into the shared skills' bag, a
# chance of a rolled gun at the region's item level). Pieces sink after last_seconds.
# Dependencies: core/sea/encounter_rules.gd (loot), core/gun_gen.gd, core/item_level.gd, core/loot_pool.gd,
# core/gun_stats.gd, game/fantasy_models.gd, data/sea/encounters.json "flotsam"; the fleet (game/sea_ships.gd), the
# sea world (water_height, skills), game/net_sea.gd (request_flotsam / tell_flotsam), game/game_session.gd (doubloons).
# Positions: this node hangs under the fleet, so its children's positions are sea coordinates.
extends Node3D

const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const ItemLevel = preload("res://core/item_level.gd")
const LootPool = preload("res://core/loot_pool.gd")
const EncounterRules = preload("res://core/sea/encounter_rules.gd")

var rules: EncounterRules
var pieces := {}  # id -> {"node": Node3D, "x", "z", "model": int, "loot": String, "region": String, "until": float, "spin": float}
var taken := 0  # dev / checks: pieces this player got
var last_got := ""  # dev / checks: what the last piece gave
var _next_id := 1
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _asked := {}  # piece id -> time we asked the host (client: ask once a second at most)
var _rng := RandomNumberGenerator.new()
var _t := 0.0


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D, encounter_rules: EncounterRules) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	rules = encounter_rules
	_rng.randomize()


func _cfg() -> Dictionary:
	return rules.cfg["flotsam"]


func _net() -> Node:
	return _fleet.call("_net")


# Host / alone: a sunk foe's cargo spread round where she went down.
func spill(x: float, z: float, loot_id: String, region_id: String) -> void:
	var n := rules.pieces(loot_id, _rng)
	var models: Array = _cfg()["models"]
	for i in n:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * float(_cfg()["spread_m"])
		var model := 2 if i == 0 else _rng.randi_range(0, models.size() - 2)  # one sea chest, the rest barrels and crates
		add_piece(_next_id, x + cos(a) * r, z + sin(a) * r, model, loot_id, region_id)
		_next_id += 1
	var net := _net()
	if net != null:
		net.call("tell_flotsam", to_net())


func add_piece(id: int, x: float, z: float, model: int, loot_id: String, region_id: String) -> void:
	if pieces.has(id):
		return
	var models: Array = _cfg()["models"]
	var node: Node3D = null
	var path := "res://assets/models/sea/%s.gltf" % String(models[clampi(model, 0, models.size() - 1)])
	if ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate() as Node3D
	else:
		node = MeshInstance3D.new()
		(node as MeshInstance3D).mesh = BoxMesh.new()
	add_child(node)
	node.position = Vector3(x, 0.0, z)
	pieces[id] = {"node": node, "x": x, "z": z, "model": model, "loot": loot_id, "region": region_id,
		"until": _now() + float(_cfg()["last_seconds"]), "spin": _rng.randf_range(-0.3, 0.3), "phase": _rng.randf() * TAU}
	_next_id = maxi(_next_id, id + 1)


func remove_piece(id: int) -> void:
	if pieces.has(id):
		(pieces[id]["node"] as Node).queue_free()
		pieces.erase(id)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	if pieces.is_empty() or not bool(_sea.call("running")):
		return
	_t += delta
	var net := _net()
	var host := net == null or not bool(net.call("is_client"))
	var me: Vector3 = _sea.call("local_of", _player.global_position)
	var my_ship: Node3D = _fleet.get("helm_ship") if _fleet.get("helm_ship") != null else _fleet.call("ship_aboard")
	var gone: Array = []
	for id: int in pieces:
		var p: Dictionary = pieces[id]
		var node: Node3D = p["node"]
		var world := node.global_position
		var water := float(_sea.call("water_height", Vector3(world.x, 0.0, world.z)))
		node.position.y = water - _sea.call("world_of", Vector3.ZERO).y + sin(_t * 1.3 + float(p["phase"])) * 0.06 - 0.1
		node.rotation = Vector3(sin(_t * 0.9 + float(p["phase"])) * 0.12, node.rotation.y + float(p["spin"]) * delta, cos(_t * 0.7 + float(p["phase"])) * 0.1)
		if host and _now() > float(p["until"]):
			gone.append(id)
			continue
		if _reached(Vector2(float(p["x"]), float(p["z"])), me, my_ship):
			_take(id, host, net)
	for id: int in gone:
		remove_piece(id)
	if not gone.is_empty() and net != null:
		net.call("tell_flotsam", to_net())


# Is this piece in reach of the local player: swimming to it, or his ship (helm or deck) sailing through it.
func _reached(at: Vector2, me: Vector3, my_ship: Node3D) -> bool:
	if Vector2(me.x, me.z).distance_to(at) <= float(_cfg()["reach_swimmer"]) and bool(_player.get("swimming")):
		return true
	if my_ship == null:
		return false
	var st: Dictionary = my_ship.get("state")
	var yaw := float(st["yaw"])
	var rel := at - Vector2(float(st["x"]), float(st["z"]))
	var along := rel.dot(Vector2(-sin(yaw), -cos(yaw)))
	var half_len := absf(float((my_ship.get("spec")["outline"] as Array)[0][0]))
	var across := absf(rel.dot(Vector2(cos(yaw), -sin(yaw))))
	return absf(along) <= half_len + 1.0 and across <= float(_cfg()["reach_ship"])


func _take(id: int, host: bool, net: Node) -> void:
	if host:
		var p: Dictionary = pieces[id]
		grant(String(p["loot"]), String(p["region"]))
		remove_piece(id)
		if net != null:
			net.call("tell_flotsam", to_net())
		return
	if _now() - float(_asked.get(id, -10.0)) > 1.0:
		_asked[id] = _now()
		net.call("request_flotsam", id)


# This player got a piece: roll its loot here (his doubloons, his bag, his gun).
func grant(loot_id: String, region_id: String) -> void:
	var got := rules.loot(loot_id, region_id, _rng)
	var said := PackedStringArray()
	var s := get_tree().get_first_node_in_group("game_session")
	if int(got["doubloons"]) > 0 and s != null:
		var purse: RefCounted = s.call("doubloons")
		purse.set("balance", int(purse.get("balance")) + int(got["doubloons"]))
		said.append("%d doubloons" % int(got["doubloons"]))
	var skills: Variant = _sea.get("skills")
	for item: String in got["items"]:
		if skills != null:
			(skills as Node).call("give", item, int(got["items"][item]))
			said.append("%d %s" % [int(got["items"][item]), String((skills as Node).get("bag").call("item_name", item))])
	if bool(got["gun"]):
		var db: RefCounted = _player.get("gun_db")
		var band := ItemLevel.region_band(EncounterRules.region_number(region_id))
		var lvl := ItemLevel.roll(_rng, band.x, band.y)
		var guns: Array = [GunGen.generate(db, _rng, 0.0, "", "", "", lvl)]
		guns.append_array(LootPool.roll(db, _rng, "sea_world", lvl))  # the rare sea-world uniques
		for gun: Dictionary in guns:
			if (_player.get("inventory") as RefCounted).call("add_gun", gun):
				said.append(GunStats.display_name(db, gun))
		_player.call("refresh_held")
	taken += 1
	last_got = ", ".join(said)
	if _sea.has_signal("notice"):
		_sea.emit_signal("notice", "Floating cargo: %s" % (last_got if last_got != "" else "empty"))
	if s != null and s.has_method("save_profile"):
		s.call("save_profile")


# --- online (game/net_sea.gd) ---

func to_net() -> Array:
	var out: Array = []
	for id: int in pieces:
		var p: Dictionary = pieces[id]
		out.append([id, snappedf(float(p["x"]), 0.1), snappedf(float(p["z"]), 0.1), int(p["model"]), String(p["loot"]), String(p["region"])])
	return out


# Client: the host's pieces (what is not there any more goes).
func from_net(list: Array) -> void:
	var seen := {}
	for got: Variant in list:
		if not got is Array or (got as Array).size() < 6:
			continue
		var id := int(got[0])
		seen[id] = true
		if not pieces.has(id) and is_finite(float(got[1])) and is_finite(float(got[2])):
			add_piece(id, float(got[1]), float(got[2]), int(got[3]), String(got[4]).left(24), String(got[5]).left(16))
	for id: int in pieces.keys():
		if not seen.has(id):
			remove_piece(id)


# Host: may this player have that piece (it is still here, he is near it)? Takes it away.
func host_give(id: int, at: Vector3) -> bool:
	if not pieces.has(id):
		return false
	var p: Dictionary = pieces[id]
	if Vector2(at.x, at.z).distance_to(Vector2(float(p["x"]), float(p["z"]))) > 40.0:
		return false
	remove_piece(id)
	return true


func status() -> String:
	return "flotsam %d afloat, taken %d, last '%s'" % [pieces.size(), taken, last_got]
