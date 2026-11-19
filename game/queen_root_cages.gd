# Purpose: the Lantern Queen's ROOT CAGES (sea step 13 R2d phase 3, design approved in diary/DESIGN_BOSSES.md): her
# root cage attack traps a player in a ring of roots where he stands; he cannot walk out until the others SHOOT the
# cage (its hit box: game/boss_part.gd, part id "cage_<peer>", routed by game/sea_boss.gd part_hit) or BURN it with the
# Ember Gauntlet (the hit box is in group "burnable": game/sea_tools.gd), or it crumbles by itself after cage_s. The
# HOST owns the cages (who, where, health, time); every machine draws them from the host's list; the caged player's
# own machine holds him in place.
# Dependencies: game/boss_part.gd, game/fx_kit.gd, game/sea_boss_lantern.gd (parent: fight, cfg, _player, _dungeons).
extends Node

const BossPart = preload("res://game/boss_part.gd")
const FxKit = preload("res://game/fx_kit.gd")

var lantern: Node  # game/sea_boss_lantern.gd
var cages := {}  # peer -> {at: arena-local Vector3, hp, t} (host) / {at} (clients); "node" once drawn
var made := 0  # dev / checks
var broken := 0
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.26, 0.19, 0.12)
	_mat.roughness = 0.9


func _cfg() -> Dictionary:
	return (lantern.call("cfg") as Dictionary).get("cage", {})


# Host: this player is caged where he stands (arena-local point).
func host_cage(peer: int, at: Vector3) -> void:
	if cages.has(peer):
		return
	cages[peer] = {"at": at, "hp": float(_cfg().get("hp", 600.0)), "t": float(_cfg().get("cage_s", 8.0))}
	made += 1
	_draw(peer)


# Host: time passes; a cage whose time is up crumbles.
func host_tick(delta: float) -> void:
	for peer: int in cages.keys():
		cages[peer]["t"] = float(cages[peer]["t"]) - delta
		if float(cages[peer]["t"]) <= 0.0:
			_free(peer, "The roots crumble")


# Host: a hit on this player's cage (shots, the Ember Gauntlet's fire).
func host_hit(peer: int, damage: float) -> void:
	if not cages.has(peer) or not is_finite(damage) or damage <= 0.0:
		return
	cages[peer]["hp"] = float(cages[peer]["hp"]) - minf(damage, 5000.0)
	if float(cages[peer]["hp"]) <= 0.0:
		broken += 1
		_free(peer, "The root cage breaks!")


func _free(peer: int, words: String) -> void:
	_undraw(peer)
	cages.erase(peer)
	lantern.get("fight").call("_tell_notice", words)


func is_caged(peer: int) -> bool:
	return cages.has(peer)


func to_net() -> Array:
	var out: Array = []
	for peer: int in cages:
		var at: Vector3 = cages[peer]["at"]
		out.append_array([peer, snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)])
	return out


# Client: the host's cages (new ones drawn, gone ones taken away).
func from_net(flat: Array) -> void:
	var seen := {}
	for i in range(0, mini(flat.size(), 24) - 3, 4):
		var peer := int(flat[i])
		var at := Vector3(float(flat[i + 1]), float(flat[i + 2]), float(flat[i + 3]))
		if not at.is_finite():
			continue
		seen[peer] = true
		if not cages.has(peer):
			cages[peer] = {"at": at}
			_draw(peer)
	for peer: int in cages.keys():
		if not seen.has(peer):
			_undraw(peer)
			cages.erase(peer)


func _draw(peer: int) -> void:
	var fight: Node = lantern.get("fight")
	var arena: Node3D = fight.call("_arena")
	var enemy: Node3D = fight.get("enemy")
	if arena == null:
		return
	var root := Node3D.new()
	root.position = cages[peer]["at"]
	for k in 9:  # roots bowing up and over from a ring round him
		var a := TAU * float(k) / 9.0
		var rod := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.13
		cyl.height = 2.6
		cyl.radial_segments = 5
		rod.mesh = cyl
		rod.material_override = _mat
		rod.position = Vector3(cos(a) * 0.75, 1.2, sin(a) * 0.75)
		rod.rotation = Vector3(cos(a + PI * 0.5) * 0.25, 0.0, sin(a + PI * 0.5) * 0.25)
		root.add_child(rod)
	arena.add_child(root)
	FxKit.burst(arena, root.global_position + Vector3(0.0, 0.5, 0.0), Color(0.35, 0.25, 0.15), 30, 0.7, 0.3, 3.0, -4.0)
	cages[peer]["node"] = root
	if enemy != null and is_instance_valid(enemy):
		var part := BossPart.new()
		part.fight = fight
		part.target = enemy
		part.part_id = "cage_%d" % peer
		part.radius = 1.15
		part.position = Vector3(0.0, 1.2, 0.0)
		part.add_to_group("burnable")
		root.add_child(part)
		var me: CharacterBody3D = lantern.get("_player")
		if me != null and peer != int(lantern.get("_dungeons").call("_my_id")):
			me.add_collision_exception_with(part)


func _undraw(peer: int) -> void:
	var c: Dictionary = cages.get(peer, {})
	if c.has("node") and is_instance_valid(c["node"]):
		var root: Node3D = c["node"]
		FxKit.burst(root.get_parent(), root.global_position + Vector3(0.0, 1.0, 0.0), Color(0.4, 0.3, 0.18), 30, 0.8, 0.3, 4.0, -5.0)
		root.queue_free()


func clear() -> void:
	for peer: int in cages.keys():
		var c: Dictionary = cages[peer]
		if c.has("node") and is_instance_valid(c["node"]):
			(c["node"] as Node).queue_free()
	cages.clear()
