# Purpose: THE REGIONS' OWN SEA CREATURES (sea step 8e; director 2026-11-17: "all 7 as written", one signature creature
# per region). This node keeps every such beast: the HOST spawns them (game/sea_encounters.gd kinds "creature":
# "beast", only in their own region, some only in certain weather), runs each one's behaviour script (game/beasts/
# <kind>.gd: start / step on the host, pose on every machine) and tells everyone (game/net_sea.gd beasts, 10 Hz:
# place in sea coordinates, yaw, health, mode and its clock); other machines show puppets whose hits go to the host.
# Beasts are game/enemy.gd bodies made by the wave director (kill XP, shots, grenades, skills reach them) under the
# fleet, driven here (no physics). Shared tools for the behaviours: the players at sea, a ship's sides, knocking a
# player flat or snatching him into the sea (his own machine: net_sea tell_player_fx), FIRES on a deck (ship space,
# drawn on every machine, each machine's own player burns in them), hull bites. Slain = loot afloat.
# Dependencies: game/beasts/*.gd, core/sea/deck_walk.gd, game/fx_kit.gd, data/sea/encounters.json "beasts" (+ loot),
# data/enemies.json sea_*; the fleet (ships, rules, hull_part, _net), the sea world (world_of, local_of, water_height,
# map, notice), game/sea_flotsam.gd (spill), the wave director and score card (set by game/sea_encounters.gd).
extends Node3D

const DeckWalk = preload("res://core/sea/deck_walk.gd")
const FxKit = preload("res://game/fx_kit.gd")
const KINDS := {
	"sunskate": preload("res://game/beasts/sunskate.gd"),
	"fogmaw": preload("res://game/beasts/fogmaw.gd"),
	"cinder_turtle": preload("res://game/beasts/cinder_turtle.gd"),
}

var cfg: Dictionary  # encounters.json "beasts"
var director: Node
var card: RefCounted
var beasts := {}  # id -> {"kind", "enemy", "mode", "t" (s in this mode), "ship", plus the behaviour's own keys}
var fires: Array = []  # [ship, local x, local z, until (s on this machine's clock)]
var came := 0  # dev / checks
var slain := 0
var counts := {}  # dev / checks: event -> n (leaps, knocks, snatches, rams, fires, hull_bites, bites)
var _next_id := 1
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _stats := {}
var _rng := RandomNumberGenerator.new()
var _hitter := 0
var _pending := {}
var _missing := {}
var _sent_empty := true
var _fire_nodes := {}  # [ship, x, z] key -> flame node
var _burn_tick := 0.0


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D, encounters: Dictionary) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	cfg = encounters["beasts"]
	_stats = (JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json")) as Dictionary)["enemies"]
	_rng.randomize()


func _net() -> Node:
	return _fleet.call("_net")


func host() -> bool:
	var net := _net()
	return net == null or not bool(net.call("is_client"))


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func rng() -> RandomNumberGenerator:
	return _rng


func cfg_of(kind: String) -> Dictionary:
	return cfg[kind]


func count(what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1


func water(at: Vector3) -> float:
	return float(_sea.call("water_height", at))


func world_of(x: float, z: float) -> Vector3:
	return _sea.call("world_of", Vector3(x, 0.0, z))


func ships() -> Array:
	return _fleet.get("ships")


func is_ship(node: Node) -> bool:
	return ships().has(node)


# Everyone at sea: [{"body": Node3D, "ship": the ship he stands on or null, "swimming": bool}].
func players() -> Array:
	var out: Array = []
	var bodies: Array = []
	if bool(_sea.get("inside")) and not bool(_player.get("downed")):
		bodies.append(_player)
	var net := _net()
	if net != null and bool(net.call("active")):
		for body: Node3D in (net.get("net") as Node).call("target_nodes"):
			if body.global_position.x < -10000.0:  # (sea_world SIDE_X)
				bodies.append(body)
	var rules: RefCounted = _fleet.get("rules")
	for body: Node3D in bodies:
		var on: Node3D = null
		for ship: Node3D in ships():
			if not (ship.get("state") as Dictionary).has("foe") and bool(rules.call("aboard", String(ship.get("state")["ship"]), ship.global_transform.affine_inverse() * body.global_position)):
				on = ship
		var swimming := bool(body.get("swimming")) if body == _player else bool(body.get("_swimming"))
		out.append({"body": body, "ship": on, "swimming": swimming})
	return out


# The player's ship nearest a point (null = none within `within` m).
func ship_near(at: Vector3, within: float) -> Node3D:
	var best: Node3D = null
	var best_d := within
	for who: Dictionary in players():
		var ship: Node3D = who["ship"]
		if ship != null and ship.global_position.distance_to(at) < best_d:
			best_d = ship.global_position.distance_to(at)
			best = ship
	return best


# A point beside a ship: `side` +1 starboard / -1 port, `out` m past her side, at her own z `lz`, `up` m above the sea.
func beside(ship: Node3D, side: float, out: float, lz: float, up: float) -> Vector3:
	var spec: Dictionary = ship.get("spec")
	var p: Vector3 = ship.global_transform * Vector3(side * (DeckWalk.half_width(spec, lz) + out), 0.0, lz)
	return Vector3(p.x, water(p) + up, p.z)


static func ship_length(ship: Node3D) -> Vector2:  # (stern z, bow z) of her outline
	var outline: Array = (ship.get("spec") as Dictionary)["outline"]
	return Vector2(float(outline[0][0]), float(outline[outline.size() - 1][0]))


# --- spawning ---

func spawn(kind: String, x: float, z: float, region_n: int) -> void:
	if not KINDS.has(kind):
		return
	var c: Dictionary = cfg[kind]
	var n := _rng.randi_range(int((c.get("count", [1, 1]) as Array)[0]), int((c.get("count", [1, 1]) as Array)[1]))
	for i in n:
		var id := _next_id
		_next_id += 1
		var stats: Dictionary = (_stats[String(c["enemy"])] as Dictionary).duplicate()
		stats["max_hp"] = float(stats["max_hp"]) * (1.0 + float(cfg["hp_per_region"]) * float(region_n - 1))
		stats["damage"] = float(stats.get("damage", 0.0)) * (1.0 + float(cfg["damage_per_region"]) * float(region_n - 1))
		var enemy := _make(id, kind, stats, false)
		if enemy == null:
			continue
		var b: Dictionary = beasts[id]
		b["region"] = region_n
		b["nth"] = i
		b["mult"] = 1.0 + float(cfg["damage_per_region"]) * float(region_n - 1)
		enemy.global_position = world_of(x + float(i) * 4.0, z)
		(KINDS[kind] as Script).call("start", self, b)
		came += 1
	_sea.emit_signal("notice", String(c["notice"]))


func _make(id: int, kind: String, stats: Dictionary, puppet: bool) -> Node3D:
	if director == null:
		return null
	var c: Dictionary = cfg[kind]
	var enemy: Node3D = director.call("adopt", String(c["enemy"]), stats)
	enemy.set("puppet", puppet)
	enemy.set_meta("net_id", id)
	enemy.set_meta("beast", kind)
	_fleet.add_child(enemy)
	enemy.set_physics_process(false)
	var model: Node3D = enemy.get("_model")
	if model != null:
		model.scale = Vector3.ONE * float(c.get("scale", 1.0))
	_player.add_collision_exception_with(enemy as PhysicsBody3D)  # its body never shoves us about
	enemy.died.connect(_on_died.bind(id))
	if puppet:
		enemy.set_meta("host_pays", true)
		enemy.connect("puppet_hit", func(damage: float) -> void: _pending[id] = float(_pending.get(id, 0.0)) + damage)
	beasts[id] = {"kind": kind, "enemy": enemy, "mode": "", "t": 0.0, "ship": null, "id": id}
	return enemy


func set_mode(b: Dictionary, mode: String) -> void:
	b["mode"] = mode
	b["t"] = 0.0


func _remove(id: int) -> void:
	var b: Dictionary = beasts.get(id, {})
	beasts.erase(id)
	var enemy: Node3D = b.get("enemy")
	if is_instance_valid(enemy):
		if director != null:
			director.call("forget", enemy)
		enemy.queue_free()


# --- every frame ---

func _process(delta: float) -> void:
	if _fleet == null or not bool(_sea.call("running")) or delta <= 0.0:
		return
	var is_host := host()
	for id: int in beasts.keys():
		if not beasts.has(id):
			continue
		var b: Dictionary = beasts[id]
		if not is_instance_valid(b["enemy"]):
			beasts.erase(id)
			continue
		b["t"] = float(b["t"]) + delta
		if is_host:
			if _far_from_all(b["enemy"]):
				_remove(id)
				continue
			(KINDS[String(b["kind"])] as Script).call("step", self, b, delta)
		else:
			var e: Node3D = b["enemy"]
			e.global_position = e.global_position.lerp(world_of(float(b.get("net_x", 0.0)), float(b.get("net_z", 0.0))) + Vector3(0.0, float(b.get("net_y", 0.0)), 0.0), 0.2)
			e.rotation.y = lerp_angle(e.rotation.y, float(b.get("net_yaw", 0.0)), 0.2)
		(KINDS[String(b["kind"])] as Script).call("pose", self, b, delta)
	_fires_step(delta)
	if not is_host:
		_send_hits()


func _far_from_all(enemy: Node3D) -> bool:
	for who: Dictionary in players():
		if (who["body"] as Node3D).global_position.distance_to(enemy.global_position) < float(cfg["lose_m"]):
			return false
	return true


# --- what beasts do to players and ships (host) ---

# Knocked flat: thrown along `push` (m/s) and hurt; another player's machine does it to him.
func knock(body: Node3D, push: Vector3, damage: float) -> void:
	count("knocks")
	if body == _player:
		player_fx("knock", push, damage)
		return
	var peer := _peer_of(body)
	if peer != 0:
		_net().call("tell_player_fx", peer, "knock", push, damage)


# Snatched off the deck into the sea at `to` (sea coordinates) and hurt.
func snatch(body: Node3D, to: Vector3, damage: float) -> void:
	count("snatches")
	if body == _player:
		player_fx("snatch", to, damage)
		return
	var peer := _peer_of(body)
	if peer != 0:
		_net().call("tell_player_fx", peer, "snatch", to, damage)


func _peer_of(body: Node3D) -> int:
	var net := _net()
	if net == null:
		return 0
	var ns: Node = net.get("net")
	for peer: int in ns.get("roster"):
		if ns.call("player_node", peer) == body:
			return peer
	return 0


# This machine's player: what a beast did to him (the host's word, or the host's own player).
func player_fx(kind: String, v: Vector3, damage: float) -> void:
	if not v.is_finite() or not is_finite(damage):
		return
	if kind == "knock":
		_player.call("shove", v.limit_length(14.0))
		_player.call("take_damage", clampf(damage, 0.0, 200.0), "physical")
		_sea.emit_signal("notice", String(cfg["knock_notice"]))
	elif kind == "snatch":
		var to := world_of(v.x, v.z)
		_player.call("teleport", Vector3(to.x, water(to) - 0.6, to.z), float(_player.call("look_yaw")) if _player.has_method("look_yaw") else 0.0)
		_player.call("take_damage", clampf(damage, 0.0, 200.0), "physical")
		_sea.emit_signal("notice", String(cfg["snatch_notice"]))


func hull_bite(ship: Node3D, at: Vector3, amount: float) -> void:
	count("hull_bites")
	_fleet.get("hull_part").call("damage", ship, ship.global_transform.affine_inverse() * at, amount)
	FxKit.burst(self, at, Color(0.45, 0.32, 0.2), 18, 0.8, 0.25, 6.0, -9.0)


# A fire on a ship's deck (ship space x, z) for `seconds` (host: it goes out to everyone with the list).
func add_fire(ship: Node3D, lx: float, lz: float, seconds: float) -> void:
	count("fires")
	fires.append([ship, lx, lz, now() + seconds])


func _fires_step(delta: float) -> void:
	var t := now()
	var keep: Array = []
	var shown := {}
	for f: Array in fires:
		var ship: Node3D = f[0]
		if not is_instance_valid(ship) or t > float(f[3]) or bool(ship.get("state").get("sinking", false)):
			continue
		keep.append(f)
		var key := "%d:%.1f:%.1f" % [ship.get_instance_id(), float(f[1]), float(f[2])]
		shown[key] = true
		if not _fire_nodes.has(key):
			var flame := Node3D.new()
			ship.add_child(flame)
			flame.position = Vector3(float(f[1]), DeckWalk.height_at(ship.get("spec"), float(f[1]), float(f[2])), float(f[2]))
			for k in 3:
				var tongue := FxKit.flame()
				if tongue != null:
					flame.add_child(tongue)
					tongue.position = Vector3(cos(k * 2.1) * 0.35, 0.0, sin(k * 2.1) * 0.35)
					tongue.scale = Vector3.ONE * (0.7 + 0.2 * k)
			var embers := FxKit.particles(Color(1.0, 0.5, 0.1), 10, 0.9, 0.06, 2.0, 25.0, 1.5, false)
			flame.add_child(embers)
			_fire_nodes[key] = flame
	fires = keep
	for key: String in _fire_nodes.keys():
		if not shown.has(key):
			var node: Node3D = _fire_nodes[key]
			if is_instance_valid(node):
				node.queue_free()
			_fire_nodes.erase(key)
	_burn_tick -= delta
	if _burn_tick <= 0.0 and not fires.is_empty() and bool(_sea.get("inside")):  # our own player burns standing in one
		_burn_tick = 1.0
		for f: Array in fires:
			var ship: Node3D = f[0]
			var local := ship.global_transform.affine_inverse() * _player.global_position
			if Vector2(local.x - float(f[1]), local.z - float(f[2])).length() <= float(cfg["cinder_turtle"]["fire_m"]) and absf(local.y - DeckWalk.height_at(ship.get("spec"), float(f[1]), float(f[2]))) < 1.5:
				_player.call("take_damage", float(cfg["cinder_turtle"]["fire_dps"]), "fire")
				break


# --- deaths ---

func _on_died(_enemy: Node, id: int) -> void:
	var b: Dictionary = beasts.get(id, {})
	beasts.erase(id)
	slain += 1
	if b.is_empty() or not host():
		return
	var e: Node3D = b["enemy"]
	var at: Vector3 = _sea.call("local_of", e.global_position) if is_instance_valid(e) else Vector3.ZERO
	var region := "region_%d" % int(b.get("region", 1))
	(get_parent().get("flotsam") as Node).call("spill", at.x, at.z, String(cfg[String(b["kind"])]["loot"]), region)
	var net := _net()
	if net != null:
		net.call("tell_beast_died", id, _hitter)


# --- online (game/net_sea.gd) ---

func to_net() -> Array:
	var out: Array = []
	for id: int in beasts:
		var b: Dictionary = beasts[id]
		var e: Node3D = b["enemy"]
		if not is_instance_valid(e):
			continue
		var p: Vector3 = _sea.call("local_of", e.global_position)
		var hp: RefCounted = e.get("health")
		out.append([id, String(b["kind"]), snappedf(p.x, 0.01), snappedf(e.global_position.y - _fleet.global_position.y, 0.01), snappedf(p.z, 0.01), snappedf(e.rotation.y, 0.01), snappedf(float(hp.get("hp")) / maxf(float(hp.get("max_hp")), 1.0), 0.01), String(b["mode"]), snappedf(float(b["t"]), 0.01)])
	return out


func fires_to_net() -> Array:
	var out: Array = []
	for f: Array in fires:
		out.append([ships().find(f[0]), snappedf(float(f[1]), 0.1), snappedf(float(f[2]), 0.1), snappedf(float(f[3]) - now(), 0.1)])
	return out


func should_send() -> bool:
	if not beasts.is_empty() or not fires.is_empty():
		_sent_empty = false
		return true
	if not _sent_empty:
		_sent_empty = true
		return true
	return false


func from_net(list: Array, fire_list: Array) -> void:
	var seen := {}
	for got: Variant in list:
		if not got is Array or (got as Array).size() < 9:
			continue
		var id := int(got[0])
		var kind := String(got[1]).left(24)
		if not KINDS.has(kind):
			continue
		seen[id] = true
		if not beasts.has(id) or not is_instance_valid(beasts[id]["enemy"]):
			var e := _make(id, kind, (_stats[String(cfg[kind]["enemy"])] as Dictionary).duplicate(), true)
			if e == null:
				continue
			e.global_position = world_of(float(got[2]), float(got[4])) + Vector3(0.0, float(got[3]), 0.0)
		var b: Dictionary = beasts[id]
		b["net_x"] = float(got[2])
		b["net_y"] = float(got[3])
		b["net_z"] = float(got[4])
		b["net_yaw"] = float(got[5])
		if String(got[7]) != String(b["mode"]):
			b["mode"] = String(got[7]).left(16)
			b["t"] = float(got[8])
		var hp: RefCounted = (b["enemy"] as Node).get("health")
		hp.set("hp", clampf(float(got[6]), 0.0, 1.0) * float(hp.get("max_hp")))
	for id: int in beasts.keys():
		if seen.has(id):
			_missing.erase(id)
		elif now() - float(_missing.get(id, now())) > 0.6:
			_remove(id)
			_missing.erase(id)
		elif not _missing.has(id):
			_missing[id] = now()
	var all := ships()
	fires.clear()
	for f: Variant in fire_list:
		if f is Array and (f as Array).size() >= 4 and int(f[0]) >= 0 and int(f[0]) < all.size():
			fires.append([all[int(f[0])], clampf(float(f[1]), -20.0, 20.0), clampf(float(f[2]), -40.0, 40.0), now() + clampf(float(f[3]), 0.0, 60.0)])


func _send_hits() -> void:
	if _pending.is_empty():
		return
	var net := _net()
	for id: int in _pending:
		if net != null:
			net.call("request_beast_hit", id, float(_pending[id]))
	_pending.clear()


func host_hit(id: int, damage: float, from: int) -> void:
	if not beasts.has(id) or not is_finite(damage) or damage <= 0.0:
		return
	var e: Node3D = beasts[id]["enemy"]
	if not is_instance_valid(e):
		return
	var before := String(card.get("blow")) if card != null else ""
	if card != null:
		card.set("blow", "other")
	_hitter = from
	e.call("on_hit", minf(damage, float(cfg["max_hit"])))
	_hitter = 0
	if card != null:
		card.set("blow", before)


func fell(id: int, killer: int, me: int) -> void:
	if not beasts.has(id):
		return
	var e: Node3D = beasts[id]["enemy"]
	beasts.erase(id)
	if not is_instance_valid(e):
		return
	var before := String(card.get("blow")) if card != null else ""
	if card != null and killer != me:
		card.set("blow", "other")
	e.call("die_now")
	if card != null:
		card.set("blow", before)


func status() -> String:
	var parts := PackedStringArray()
	for id: int in beasts:
		var b: Dictionary = beasts[id]
		var hp: RefCounted = (b["enemy"] as Node).get("health") if is_instance_valid(b["enemy"]) else null
		parts.append("%s %s %.0f" % [String(b["kind"]), String(b["mode"]), float(hp.get("hp")) if hp != null else 0.0])
	return "beasts %d [%s], came %d, slain %d, fires %d, %s" % [beasts.size(), ", ".join(parts), came, slain, fires.size(), str(counts)]
