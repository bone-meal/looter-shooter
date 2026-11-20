# Purpose: phase 2's FALSE LURES round the Lantern Queen's pool (sea step 13 R2d, design approved in
# diary/DESIGN_BOSSES.md): 2-5 glowing bulbs on stalks rising out of the black water (by party size,
# core/sea/lantern_rules.gd false_count), pulsing together while her real lure pulses out of step. Shooting one makes it
# BURST into a spore cloud (it rises again after regrow_s). The HOST owns them (angles, health, burst, regrow); every
# machine draws them from the host's list and makes the burst's cloud when one goes. Each bulb carries a hit box
# (game/boss_part.gd, part id "false_<n>") whose hits go through the fight like any part (game/sea_boss.gd part_hit).
# Dependencies: core/sea/lantern_rules.gd (via the lantern), game/boss_part.gd, game/fx_kit.gd,
# game/sea_boss_lantern.gd (parent: rules, fight, add_cloud).
extends Node

const BossPart = preload("res://game/boss_part.gd")
const FxKit = preload("res://game/fx_kit.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const MODEL := "res://assets/models/sea/false_lure.gltf"  # (polish1 A7) tools/blender/sea_marsh_fx.py: nodes Bulb, Hood, Stalk

var lantern: Node  # game/sea_boss_lantern.gd
var lures: Array = []  # [{ang, alive, hp, back_at, node, bulb, part}]
var bursts := 0  # dev / checks
var _mat: StandardMaterial3D
var _stalk_mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.78, 1.0, 0.58)
	_stalk_mat = StandardMaterial3D.new()
	_stalk_mat.albedo_color = Color(0.17, 0.12, 0.08)


func _cfg() -> Dictionary:
	return (lantern.call("cfg") as Dictionary).get("false_lures", {})


func phase() -> int:
	return int(_cfg().get("phase", 1))


# Host: the false lures rise, evenly round the pool from a random start.
func host_begin(count: int, rng: RandomNumberGenerator) -> void:
	clear()
	var start := rng.randf() * TAU
	for i in count:
		lures.append({"ang": start + TAU * float(i) / float(maxi(count, 1)) + 0.4, "alive": true, "hp": float(_cfg().get("hp", 300.0)), "back_at": -1.0})
	_build()


# Host: burst ones rise again after regrow_s.
func host_tick(now: float) -> void:
	for l: Dictionary in lures:
		if not bool(l["alive"]) and float(l["back_at"]) >= 0.0 and now >= float(l["back_at"]):
			l["alive"] = true
			l["hp"] = float(_cfg().get("hp", 300.0))
			l["back_at"] = -1.0
			_show(l)


# Host: a hit on false lure n; true when it burst.
func host_hit(n: int, damage: float, now: float) -> bool:
	if n < 0 or n >= lures.size() or not bool(lures[n]["alive"]) or not is_finite(damage) or damage <= 0.0:
		return false
	lures[n]["hp"] = float(lures[n]["hp"]) - minf(damage, 5000.0)
	if float(lures[n]["hp"]) > 0.0:
		return false
	lures[n]["alive"] = false
	lures[n]["back_at"] = now + float(_cfg().get("regrow_s", 18.0))
	_burst(lures[n])
	return true


func to_net() -> Array:
	var out: Array = []
	for l: Dictionary in lures:
		out.append_array([snappedf(float(l["ang"]), 0.001), bool(l["alive"])])
	return out


# Client: the host's false lures (rebuilt if their number or places changed; a burst one bursts here too).
func from_net(flat: Array) -> void:
	var n := mini(flat.size() >> 1, 6)
	var same := n == lures.size()
	for i in n:
		if same and absf(float(lures[i]["ang"]) - float(flat[i * 2])) > 0.01:
			same = false
	if not same:
		clear()
		for i in n:
			lures.append({"ang": float(flat[i * 2]), "alive": bool(flat[i * 2 + 1]), "hp": 1.0, "back_at": -1.0})
		_build()
		return
	for i in n:
		var alive := bool(flat[i * 2 + 1])
		if bool(lures[i]["alive"]) and not alive:
			lures[i]["alive"] = false
			_burst(lures[i])
		elif alive and not bool(lures[i]["alive"]):
			lures[i]["alive"] = true
			_show(lures[i])


func _build() -> void:
	var arena: Node3D = lantern.get("fight").call("_arena")
	var fight: Node = lantern.get("fight")
	var enemy: Node3D = fight.get("enemy")
	if arena == null:
		return
	var b: Dictionary = fight.call("boss_cfg", String(fight.get("boss_id")))
	var home := Vector3(float(b["home"][0]), 0.0, float(b["home"][1]))
	for i in lures.size():
		var l: Dictionary = lures[i]
		var root := Node3D.new()
		root.position = lantern.get("rules").call("false_at", home, float(l["ang"]))
		var bulb := _modelled(root)
		if bulb == null:  # no model file: a stalk and a ball
			var stalk := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.05
			cyl.bottom_radius = 0.09
			cyl.height = root.position.y + 2.0
			cyl.radial_segments = 6
			stalk.mesh = cyl
			stalk.material_override = _stalk_mat
			stalk.position = Vector3(0.0, -cyl.height * 0.5 + 0.3, 0.0)
			root.add_child(stalk)
			bulb = MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 0.45
			ball.height = 1.0
			ball.radial_segments = 12
			ball.rings = 6
			bulb.mesh = ball
			bulb.material_override = _mat
			root.add_child(bulb)
		arena.add_child(root)
		l["node"] = root
		l["bulb"] = bulb
		if enemy != null and is_instance_valid(enemy):
			var part := BossPart.new()
			part.fight = fight
			part.target = enemy
			part.part_id = "false_%d" % i
			part.radius = 0.8
			bulb.add_child(part)
			var me: Node = lantern.get("_player")
			if me != null:
				(me as CharacterBody3D).add_collision_exception_with(part)
			l["part"] = part
		_show(l)


# (polish1 A7) The modelled lure under `root`: the stalk stretched down to the water, the bulb lit. Returns the bulb
# (null = no model file).
func _modelled(root: Node3D) -> MeshInstance3D:
	if not ResourceLoader.exists(MODEL):
		return null
	var made := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(made)
	for found in made.find_children("*", "MeshInstance3D", true, false):
		FantasyModels.dress((found as MeshInstance3D).mesh)
	var stalk := made.find_child("Stalk", true, false) as Node3D
	if stalk != null:  # the model's stalk is 1 m long from the hood down
		stalk.position.y = 0.3
		stalk.scale.y = root.position.y + 2.0
	var bulb := made.find_child("Bulb", true, false) as MeshInstance3D
	if bulb != null:
		bulb.material_override = _mat
	return bulb


func _show(l: Dictionary) -> void:
	if l.has("node") and is_instance_valid(l["node"]):
		(l["node"] as Node3D).visible = bool(l["alive"])
	if l.has("part") and is_instance_valid(l["part"]):
		(l["part"] as Node).call("set_live", bool(l["alive"]))


func _burst(l: Dictionary) -> void:
	bursts += 1
	_show(l)
	if not l.has("node") or not is_instance_valid(l["node"]):
		return
	var root: Node3D = l["node"]
	var arena := root.get_parent() as Node3D
	FxKit.burst(arena, root.global_position, Color(0.72, 0.95, 0.42), 40, 1.2, 0.35, 4.0, -1.0)
	var c: Dictionary = _cfg().get("cloud", {})
	lantern.call("add_cloud", Vector3(root.position.x, 0.0, root.position.z), {"radius": float(c.get("radius", 3.0)), "cloud_s": float(c.get("cloud_s", 4.0)), "blind_s": float(c.get("blind_s", 3.0))})


# Every frame: the bulbs pulse together (the real one is pulsed by the lantern, out of step).
func pulse(t: float) -> void:
	var s: float = lantern.get("rules").call("pulse", t, false)
	for l: Dictionary in lures:
		if l.has("bulb") and is_instance_valid(l["bulb"]):
			(l["bulb"] as Node3D).scale = Vector3.ONE * s


func clear() -> void:
	for l: Dictionary in lures:
		if l.has("node") and is_instance_valid(l["node"]):
			(l["node"] as Node).queue_free()
	lures.clear()
