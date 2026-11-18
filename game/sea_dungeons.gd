# Purpose: the sea's dungeons (sea step 9, LOCKED: hand-made from a room kit, own space behind the door): each one's
# GATE on its island ([F] Enter), its SPACE far off the map above the water (game/sea_dungeon.gd, built when someone is
# near or inside), going in and out behind the fade, the look inside (the camera's own environment: dark, warm torch
# light, a lamp that walks with the player; the sea, its rain and sky are not drawn there), and the puzzles' state:
# the host's world (saved in its profile, sent to everyone on every change and every 3 s), changed only by the host:
# the plates by where the players stand, everything else by [F] asks (net_sea request_dungeon), checked against where
# the asker really is. A chest's loot is rolled on the opener's own machine (game/sea_flotsam.gd grant).
# Dependencies: data/sea/dungeons.json, game/sea_dungeon.gd, core/encounter_rules (region number), the sea world
# (world_of, local_of, notice, ships.foes.flotsam), the session (fade, net), game/net_sea.gd.
extends Node3D

const SeaDungeon = preload("res://game/sea_dungeon.gd")

var cfg: Dictionary
var spaces := {}  # id -> SeaDungeon
var gates := {}  # id -> {"node": Node3D, "ground": float (NAN until found)}
var where := ""  # the dungeon this player is in ("" = outside)
var acts := 0  # dev / checks: [F] uses done (here or asked), host changes applied
var applied := 0
var last := ""
var _sea: Node3D
var _player: CharacterBody3D
var _env: Environment
var _lamp: OmniLight3D
var _dirty := false
var _send_t := 0.0
var _press_t := 0.0
var _gate_t := 0.0


func setup(sea: Node3D, player: CharacterBody3D) -> void:
	_sea = sea
	_player = player
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/dungeons.json"))
	for id: String in cfg["dungeons"]:
		var d := SeaDungeon.new()
		d.setup(id, cfg["dungeons"][id], cfg)
		d.position = space_of(id)
		d.visible = false
		add_child(d)
		spaces[id] = d
		var gate := SeaDungeon.piece("dk_gate")
		gate.visible = false
		var e: Dictionary = cfg["dungeons"][id]["entrance"]
		gate.rotation.y = deg_to_rad(float(e["yaw"]))
		add_child(gate)
		gates[id] = {"node": gate, "ground": NAN}
	var ec: Dictionary = cfg["env"]
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = _col(ec["background"])
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = _col(ec["ambient"])
	_env.ambient_light_energy = float(ec["ambient_energy"])
	_env.fog_enabled = true
	_env.fog_light_color = _col(ec["fog_color"])
	_env.fog_density = float(ec["fog_density"])
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_lamp = OmniLight3D.new()
	_lamp.light_color = _col(ec["lamp_color"])
	_lamp.omni_range = float(ec["lamp_range"])
	_lamp.light_energy = float(ec["lamp_energy"])
	_lamp.shadow_enabled = false
	_lamp.visible = false
	add_child(_lamp)


static func _col(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))


# A dungeon's space in sea coordinates (its map's cell 0, 0).
func space_of(id: String) -> Vector3:
	var s: Dictionary = cfg["space"]
	return Vector3(float(s["first_x"]) + float(s["step_x"]) * float(cfg["dungeons"][id].get("slot", 0)), float(s["y"]), float(s["z"]))


# Is this sea position inside a dungeon (above the water, far off the map)?
func indoor_at(sea_pos: Vector3) -> bool:
	return sea_pos.y > float(cfg["indoor_y"])


func dungeon_at(sea_pos: Vector3) -> String:
	if not indoor_at(sea_pos):
		return ""
	var best := ""
	var best_d := INF
	for id: String in spaces:
		var d := Vector2(sea_pos.x, sea_pos.z).distance_to(Vector2(space_of(id).x, space_of(id).z))
		if d < best_d:
			best_d = d
			best = id
	return best if best_d < float(cfg["space"]["step_x"]) * 0.5 else ""


func _net() -> Node:
	var s := get_tree().get_first_node_in_group("game_session")
	var net: Variant = s.get("net") if s != null else null
	return (net as Node).get_node_or_null("Sea") if net != null else null


func _host() -> bool:
	var net := _net()
	return net == null or not bool(net.call("active")) or not bool(net.call("is_client"))


# --- every frame ---

func _process(delta: float) -> void:
	if _player == null:
		return
	var here: Vector3 = _sea.call("local_of", _player.global_position)
	var now_in := dungeon_at(here) if bool(_sea.get("inside")) else ""
	if now_in != where:
		where = now_in
		_indoor(where != "")
	_lamp.visible = where != ""
	if where != "":
		_lamp.global_position = _player.global_position + Vector3(0.0, 2.2, 0.0)
	# spaces: built and shown when this player is inside; the host also keeps one built while others are in it
	var others := _others_in()
	for id: String in spaces:
		var d: SeaDungeon = spaces[id]
		var wanted: bool = id == where or others.has(id)
		if wanted and not d.built:
			d.build()
		d.visible = id == where
		d.process_mode = Node.PROCESS_MODE_INHERIT if wanted else Node.PROCESS_MODE_DISABLED
	_gate_t -= delta
	if _gate_t <= 0.0:
		_gate_t = 1.0
		_place_gates(here)
	if _host():
		_press_t -= delta
		if _press_t <= 0.0:
			_press_t = 0.25
			_press_plates()
		_send_t -= delta
		if _dirty or _send_t <= 0.0:
			_send_t = 3.0
			_dirty = false
			var net := _net()
			if net != null and bool(net.call("active")):
				net.call("tell_dungeons", world_dict())


# Other players' dungeons (the host keeps those spaces built and solid).
func _others_in() -> Dictionary:
	var out := {}
	var others: Callable = _sea.get("others")
	if others.is_valid():
		for at: Vector3 in others.call():
			var id := dungeon_at(_sea.call("local_of", at))
			if id != "":
				out[id] = true
	return out


func _indoor(on: bool) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		camera.environment = _env if on else null
	_sea.call("set_indoor", on)


# The gates stand on their islands' ground: found by a ray once the island near it is solid.
func _place_gates(here: Vector3) -> void:
	for id: String in gates:
		var g: Dictionary = gates[id]
		var e: Dictionary = cfg["dungeons"][id]["entrance"]
		var node: Node3D = g["node"]
		var near := Vector2(here.x, here.z).distance_to(Vector2(float(e["at"][0]), float(e["at"][1]))) < 250.0
		if near and is_nan(float(g["ground"])):
			var from: Vector3 = _sea.call("world_of", Vector3(float(e["at"][0]), 300.0, float(e["at"][1])))
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -400.0, 0.0), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				g["ground"] = float(_sea.call("local_of", hit["position"]).y)
		node.visible = near and not is_nan(float(g["ground"])) and where == ""
		if not is_nan(float(g["ground"])):
			node.position = Vector3(float(e["at"][0]), float(g["ground"]), float(e["at"][1]))


# --- going in and out ---

func gate_front(id: String) -> Vector3:
	var e: Dictionary = cfg["dungeons"][id]["entrance"]
	var g: Dictionary = gates[id]
	var yaw := deg_to_rad(float(e["yaw"]))
	var ground := float(g["ground"]) if not is_nan(float(g["ground"])) else 20.0
	return Vector3(float(e["at"][0]), ground, float(e["at"][1])) + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.3, 3.2)


func enter(id: String) -> void:
	var d: SeaDungeon = spaces[id]
	d.build()
	var arrive: Array = d.rules.of_kind("arrive")
	var cell: Vector2i = d.rules.things[arrive[0]]["cell"] if not arrive.is_empty() else Vector2i(1, 1)
	_player.call("teleport", _sea.call("world_of", space_of(id) + d.rules.at_of(cell) + Vector3(0.0, 0.6, 0.0)), 0.0)
	_fade()
	_sea.emit_signal("notice", String(cfg["dungeons"][id]["name"]))
	last = "entered " + id


func leave() -> void:
	if where == "":
		return
	var id := where
	_player.call("teleport", _sea.call("world_of", gate_front(id)), deg_to_rad(float(cfg["dungeons"][id]["entrance"]["yaw"])))
	_fade()
	last = "left " + id


func _fade() -> void:
	var s := get_tree().get_first_node_in_group("game_session")
	if s != null:
		var hud: Variant = s.get("_player_hud")
		if hud != null:
			(hud as Node).call("play_fade")


# --- the [F] key ---

func _local_in(id: String) -> Vector3:
	return _sea.call("local_of", _player.global_position) - space_of(id)


func _facing() -> Vector3:
	var yaw := float(_player.call("look_yaw"))
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _gate_near() -> String:
	var here: Vector3 = _sea.call("local_of", _player.global_position)
	for id: String in gates:
		if (gates[id]["node"] as Node3D).visible and here.distance_to(gate_front(id)) < 4.0:
			return id
	return ""


func prompt(key: String) -> String:
	if where != "":
		var use: Array = (spaces[where] as SeaDungeon).usable_at(_local_in(where), _facing())
		return "[%s] %s" % [key, String(use[1])] if not use.is_empty() else ""
	var g := _gate_near()
	return "[%s] Enter %s" % [key, String(cfg["dungeons"][g]["name"])] if g != "" else ""


func interact() -> bool:
	if where != "":
		var d: SeaDungeon = spaces[where]
		var use: Array = d.usable_at(_local_in(where), _facing())
		if use.is_empty():
			return false
		var ch := String(use[0])
		if String(d.rules.things[ch]["kind"]) == "exit":
			leave()
			return true
		acts += 1
		if _host():
			host_act(_my_id(), where, ch, _local_in(where))
		else:
			var net := _net()
			if net != null:
				net.call("request_dungeon", where, ch, _local_in(where))
		return true
	var g := _gate_near()
	if g != "":
		enter(g)
		return true
	return false


func _my_id() -> int:
	var net := _net()
	return int(net.call("my_id")) if net != null and bool(net.call("active")) else 1


# --- the host decides ---

# Applies a player's use of a thing (he stands at `at`, local to the dungeon). Returns true when it changed anything.
func host_act(peer: int, id: String, ch: String, at: Vector3) -> bool:
	if not spaces.has(id):
		return false
	var d: SeaDungeon = spaces[id]
	var r := d.rules
	if not r.things.has(ch):
		return false
	var spot := r.at_of(r.cell_of_thing(ch))
	if Vector2(at.x - spot.x, at.z - spot.z).length() > r.tile * 1.6:
		last = "refused %s %s: too far (%s)" % [id, ch, str(at.snapped(Vector3.ONE * 0.1))]
		return false  # not where he says
	var done := false
	match String(r.things[ch]["kind"]):
		"key":
			done = r.take_key(ch)
		"door":
			done = r.use_key(ch)
		"lever":
			done = r.pull(ch)
		"block":
			done = r.push(ch, r.cell_of(at))
		"chest":
			var loot := r.open_chest(ch)
			done = loot != ""
			if done:
				_give_chest(peer, loot, int(cfg["dungeons"][id].get("region", 1)))
	if done:
		applied += 1
		r.press(_occupied(id))
		d.refresh(false)
		_dirty = true
		last = "%s %s by %d" % [id, ch, peer]
	return done


func _give_chest(peer: int, loot: String, region_n: int) -> void:
	if peer == _my_id():
		grant(loot, region_n)
	else:
		var net := _net()
		if net != null:
			net.call("tell_dungeon_loot", peer, loot, region_n)


# This player opened a chest: its loot is rolled here (game/sea_flotsam.gd grant).
func grant(loot: String, region_n: int) -> void:
	var flotsam: Node = _sea.get("ships").get("foes").get("flotsam")
	flotsam.call("grant", loot, "region_%d" % region_n)


# Cells of every player in that dungeon (the plates).
func _occupied(id: String) -> Array:
	var out: Array = []
	var r := (spaces[id] as SeaDungeon).rules
	var bodies: Array = [_player.global_position]
	var others: Callable = _sea.get("others")
	if others.is_valid():
		bodies.append_array(others.call())
	for at: Vector3 in bodies:
		var sea_at: Vector3 = _sea.call("local_of", at)
		if dungeon_at(sea_at) == id:
			out.append(r.cell_of(sea_at - space_of(id)))
	return out


func _press_plates() -> void:
	for id: String in spaces:
		var d: SeaDungeon = spaces[id]
		if not d.built:
			continue
		if d.rules.press(_occupied(id)):
			d.refresh(false)
			_dirty = true


# --- saved and sent ---

func world_dict() -> Dictionary:
	var out := {}
	for id: String in spaces:
		out[id] = (spaces[id] as SeaDungeon).rules.to_dict()
	return out


func load_world(saved: Variant) -> void:
	if not saved is Dictionary:
		return
	for id: String in spaces:
		if (saved as Dictionary).get(id) is Dictionary:
			(spaces[id] as SeaDungeon).rules.from_dict(saved[id])
			(spaces[id] as SeaDungeon).refresh(true)


# Client: the host's states.
func from_net(states: Dictionary) -> void:
	for id: String in spaces:
		if states.get(id) is Dictionary:
			(spaces[id] as SeaDungeon).rules.from_dict(states[id])
			(spaces[id] as SeaDungeon).refresh(false)


func status() -> String:
	var parts: Array = []
	for id: String in spaces:
		parts.append((spaces[id] as SeaDungeon).status())
	return "dungeons: in '%s', acts %d, applied %d, last '%s'; %s" % [where, acts, applied, last, "; ".join(parts)]
