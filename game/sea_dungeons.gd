# Purpose: the sea's dungeons (sea step 9, LOCKED: hand-made from a room kit, own space behind the door): each one's
# GATE on its island ([F] Enter), its SPACE far off the map above the water (game/sea_dungeon.gd, built when someone is
# near or inside), going in and out behind the fade, the look inside (the camera's own environment: dark, warm torch
# light, a lamp that walks with the player; the sea, its rain and sky are not drawn there), and the puzzles' state:
# the host's world (saved in its profile, sent to everyone on every change and every 3 s), changed only by the host:
# the plates by where the players stand, everything else by [F] asks (net_sea request_dungeon), checked against where
# the asker really is. A chest's loot is rolled on the opener's own machine (game/sea_flotsam.gd grant).
# CHART PIECES (sea step 9d): a chest with a `piece` gives it to every player there; a chart's pieces (data "pieces")
# join into the chart in the bag. OUTDOOR courts (entry "outdoor": sea at + y) stand on their islands, built while
# anyone is near, with no gate and the island's own light.
# FIGHTS (sea step 9c): a fight thing starts when a player comes within its reach; the host sends its waves one after
# another (game/sea_crews.gd dungeon_spawn: host-run foes, puppets online); all of the last wave down = cleared (its
# doors open); everyone gone from the dungeon while it goes on = its foes go and it starts again next time.
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
var _came_from := {}  # id -> [sea position, yaw] where this player stood when he went in (he comes back out there)
var _fights := {}  # host: "dungeon:letter" -> ids of that fight's foes still standing (game/sea_crews.gd men)
var _fight_t := 0.0
var _settle := {}  # after coming out: {"at": sea position, "until": seconds} held until the island's ground is solid under him


func setup(sea: Node3D, player: CharacterBody3D) -> void:
	_sea = sea
	_player = player
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/dungeons.json"))
	for id: String in cfg["dungeons"]:
		var d := SeaDungeon.new()
		d.setup(id, cfg["dungeons"][id], cfg)
		d.position = space_of(id)
		d.sea_seconds = Callable(sea, "seconds")
		d.visible = false
		add_child(d)
		spaces[id] = d
		if not cfg["dungeons"][id].has("entrance"):
			continue  # (an outdoor court has no gate)
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
	var out: Dictionary = cfg["dungeons"][id].get("outdoor", {})
	if not out.is_empty():  # (sea step 9d) an outdoor court: its cell (0, 0) stands at these sea coordinates on its island
		return Vector3(float(out["at"][0]), float(out["y"]), float(out["at"][1]))
	var s: Dictionary = cfg["space"]
	return Vector3(float(s["first_x"]) + float(s["step_x"]) * float(cfg["dungeons"][id].get("slot", 0)), float(s["y"]), float(s["z"]))


# Is this sea position inside a dungeon (above the water, far off the map)?
func indoor_at(sea_pos: Vector3) -> bool:
	return sea_pos.y > float(cfg["indoor_y"])


func outdoor(id: String) -> bool:
	return cfg["dungeons"][id].has("outdoor")


func dungeon_at(sea_pos: Vector3) -> String:
	if not indoor_at(sea_pos):
		for id: String in spaces:  # an outdoor court: on its map's cells, about its height
			if outdoor(id):
				var local := sea_pos - space_of(id)
				var r := (spaces[id] as SeaDungeon).rules
				var c := r.cell_of(local)
				if c.x >= 0 and c.y >= 0 and c.x < r.size.x and c.y < r.size.y and r.char_at(c) != " " and local.y > -4.0 and local.y < 6.0:
					return id
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
		_indoor(where != "" and not outdoor(where))
	_lamp.visible = where != "" and not outdoor(where)
	if where != "":
		_lamp.global_position = _player.global_position + Vector3(0.0, 2.2, 0.0)
		_watch_pits(delta)
		_watch_tide(delta)
	# spaces: built and shown when this player is inside; the host also keeps one built while others are in it
	var others := _others_in()
	for id: String in spaces:
		var d: SeaDungeon = spaces[id]
		var wanted: bool = id == where or others.has(id)
		if outdoor(id):  # an outdoor court is built and shown while anyone is near its island
			wanted = wanted or _near_court(id, here)
		if wanted and not d.built:
			d.build()
		d.visible = id == where or (outdoor(id) and wanted)
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
		_fight_t -= delta
		if _fight_t <= 0.0:
			_fight_t = 0.3
			_run_fights()
		_send_t -= delta
		if _dirty or _send_t <= 0.0:
			_send_t = 3.0
			_dirty = false
			var net := _net()
			if net != null and bool(net.call("active")):
				net.call("tell_dungeons", world_dict())


# A fall into a pit puts the player back on the last ground he stood on (a little hurt), as in the old adventures.
var _safe := Vector3.INF
var _safe_t := 0.0
var falls := 0


# Is this player (or, on the host, another player) within 260 m of an outdoor court?
func _near_court(id: String, here: Vector3) -> bool:
	var at := space_of(id)
	if Vector2(here.x - at.x, here.z - at.z).length() < 260.0:
		return true
	var others: Callable = _sea.get("others")
	if others.is_valid() and _host():
		for o: Vector3 in others.call():
			var sea_o: Vector3 = _sea.call("local_of", o)
			if Vector2(sea_o.x - at.x, sea_o.z - at.z).length() < 260.0:
				return true
	return false


func _watch_pits(delta: float) -> void:
	var d: SeaDungeon = spaces[where]
	var local := _local_in(where)
	if local.y < -1.5 and d.rules.terrain(d.rules.cell_of(local)) in ["=", "%", "_"]:
		if _safe.is_finite():
			_player.call("teleport", _sea.call("world_of", space_of(where) + _safe + Vector3(0.0, 0.4, 0.0)), float(_player.call("look_yaw")))
		_player.call("take_damage", 8.0, "physical")
		_sea.emit_signal("notice", "You climb back out of the water")
		falls += 1
		return
	_safe_t -= delta
	if _safe_t <= 0.0 and _player.is_on_floor():
		_safe_t = 0.25
		var c := d.rules.cell_of(local)
		if local.y > -0.3 and local.y < 0.6 and d.rules.ground_at(c, float(_sea.call("seconds"))) and d.rules.terrain(c) != "%":
			_safe = d.rules.at_of(c)


# A fight's rising tide (sea step 9c-2): standing deep in it hurts (each player's own machine), more the deeper.
var tide_hurt := 0.0  # dev / checks: damage the tide has done here
var _tide_t := 0.0
var _tide_said := -10.0


func _watch_tide(delta: float) -> void:
	_tide_t -= delta
	if _tide_t > 0.0:
		return
	_tide_t = 0.5
	var r := (spaces[where] as SeaDungeon).rules
	var local := _local_in(where)
	var cell := r.cell_of(local)
	for ch: String in r.of_kind("fight"):
		var level := r.flood_level(ch)
		if level <= 0.0 or not r.in_flood(ch, cell):
			continue
		var depth := level - maxf(local.y, 0.0)
		var hurt: Dictionary = cfg.get("tide_hurt", {"from_m": 1.0, "dps_per_m": 8.0})
		if depth > float(hurt["from_m"]):
			var dmg := (depth - float(hurt["from_m"]) + 0.5) * float(hurt["dps_per_m"]) * 0.5
			_player.call("take_damage", dmg, "physical")
			tide_hurt += dmg
			var now := Time.get_ticks_msec() / 1000.0
			if now - _tide_said > 5.0:
				_tide_said = now
				_sea.emit_signal("notice", "The tide drags at you: get up high")


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
	if where == "":
		_came_from[id] = [_sea.call("local_of", _player.global_position), float(_player.call("look_yaw"))]
	var d: SeaDungeon = spaces[id]
	d.build()
	var arrive: Array = d.rules.of_kind("arrive")
	var cell: Vector2i = d.rules.things[arrive[0]]["cell"] if not arrive.is_empty() else Vector2i(1, 1)
	_safe = d.rules.at_of(cell)
	_player.call("teleport", _sea.call("world_of", space_of(id) + d.rules.at_of(cell) + Vector3(0.0, 0.6, 0.0)), 0.0)
	_fade()
	_sea.emit_signal("notice", String(cfg["dungeons"][id]["name"]))
	last = "entered " + id


func leave() -> void:
	if where == "":
		return
	var id := where
	var back: Vector3 = gate_front(id)
	var yaw := deg_to_rad(float(cfg["dungeons"][id]["entrance"]["yaw"])) + PI  # facing away from the gate
	if _came_from.has(id):  # where he went in: that ground was solid under him then
		back = _came_from[id][0]
		yaw = float(_came_from[id][1]) + PI
	_player.call("teleport", _sea.call("world_of", back + Vector3(0.0, 0.3, 0.0)), yaw)
	_settle = {"at": back + Vector3(0.0, 0.3, 0.0), "until": Time.get_ticks_msec() / 1000.0 + 4.0}
	where = ""
	_indoor(false)
	_fade()
	last = "left " + id


# Coming out: the island's solid ground round him may take a few frames to be built (it is only kept near players):
# till a ray finds it under him he is held where he came out, then set on it. Never falls through or drops into the sea.
func _physics_process(_delta: float) -> void:
	if _settle.is_empty() or _player == null:
		return
	var at: Vector3 = _sea.call("world_of", _settle["at"])
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 3.0, 0.0), at + Vector3(0.0, -6.0, 0.0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_player.global_position = (hit["position"] as Vector3) + Vector3(0.0, 0.1, 0.0)
		_settle = {}
		return
	if Time.get_ticks_msec() / 1000.0 > float(_settle["until"]):
		_settle = {}  # (nothing solid there after 4 s: let him be)
		return
	_player.global_position = at
	_player.set("velocity", Vector3.ZERO)


# The sea was left (a painting, /tp, the session) while inside: the look and lamp go back to the sea's.
func reset_indoor() -> void:
	_settle = {}
	if where != "":
		where = ""
		_indoor(false)
	_lamp.visible = false


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
		act(ch)
		return true
	var g := _gate_near()
	if g != "":
		enter(g)
		return true
	return false


# Use a thing (or "!" = the Fog Bell rang) in the dungeon this player is in: the host decides.
func act(ch: String) -> void:
	if where == "":
		return
	acts += 1
	if _host():
		host_act(_my_id(), where, ch, _local_in(where))
	else:
		var net := _net()
		if net != null:
			net.call("request_dungeon", where, ch, _local_in(where))


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
	if ch == "!":  # the Fog Bell rang here (sea step 9b): the fog walkways stand for a while
		var tcfg: Dictionary = (_sea.get("tools") as Node).get("cfg")["tools"]["bell"]
		if r.reveal(float(_sea.call("seconds")) + float(tcfg["reveal_s"])):
			applied += 1
			_dirty = true
			last = "%s fog walkways shown by %d" % [id, peer]
		return true
	if not r.things.has(ch):
		return false
	var spot := r.at_of(r.cell_of_thing(ch))
	var kind0 := String(r.things[ch]["kind"])
	var reach := r.tile * 1.6
	if kind0 in ["bramble", "brazier"]:
		reach = 16.0  # the Ember Gauntlet's bolt
	elif kind0 == "basin" or (kind0 == "door" and String(r.things[ch].get("open", "")) == "whorl"):
		reach = 5.0
	if Vector2(at.x - spot.x, at.z - spot.z).length() > reach or (kind0 != "bramble" and kind0 != "brazier" and absf(at.y - r.height_of(r.cell_of_thing(ch))) > 2.5):
		last = "refused %s %s: too far (%s)" % [id, ch, str(at.snapped(Vector3.ONE * 0.1))]
		return false  # not where he says
	var done := false
	match String(r.things[ch]["kind"]):
		"key", "bigkey":
			done = r.take_key(ch)
		"door":
			done = r.whorl(ch) if String(r.things[ch].get("open", "")) == "whorl" else r.use_key(ch)
		"bramble":
			done = r.burn(ch)
		"brazier":
			done = r.light(ch)
		"basin":
			done = r.turn_tide(ch)
		"lever":
			done = r.pull(ch)
		"block":
			done = r.push(ch, r.cell_of(at))
		"chest":
			var loot := r.open_chest(ch)
			done = loot != ""
			if done:
				if loot != "-":
					_give_chest(peer, loot, int(cfg["dungeons"][id].get("region", 1)))
				if r.things[ch].has("tool"):  # a tool: for every player in the dungeon
					_give_tool_all(id, String(r.things[ch]["tool"]))
				if r.things[ch].has("piece"):  # a chart piece (sea step 9d): for every player there
					_give_piece_all(id, String(r.things[ch]["piece"]))
	if done and kind0 == "bigkey":
		_sea.emit_signal("notice", "The Great Key!")
	if done:
		applied += 1
		r.press(_occupied(id))
		d.refresh(false)
		_dirty = true
		last = "%s %s by %d" % [id, ch, peer]
	return done


func _give_tool_all(id: String, tool: String) -> void:
	if where == id:
		(_sea.get("tools") as Node).call("give", tool)
	var net := _net()
	if net == null or not bool(net.call("active")):
		return
	var all: Dictionary = (net.get("net") as Node).call("positions")
	for peer: int in all:
		if peer != _my_id() and dungeon_at(_sea.call("local_of", all[peer])) == id:
			net.call("tell_tool_gift", peer, tool)


func _give_piece_all(id: String, piece: String) -> void:
	if where == id:
		receive_piece(piece)
	var net := _net()
	if net == null or not bool(net.call("active")):
		return
	var all: Dictionary = (net.get("net") as Node).call("positions")
	for peer: int in all:
		if peer != _my_id() and dungeon_at(_sea.call("local_of", all[peer])) == id:
			net.call("tell_dungeon_gift", peer, piece)


# This player got a chart piece: into the bag; all the pieces of a chart (data "pieces") join into that chart.
func receive_piece(piece: String) -> void:
	var skills: Node = _sea.get("skills")
	if skills == null:
		return
	var bag: RefCounted = skills.get("bag")
	if not bool(bag.call("has_item", piece)):
		return
	if int(bag.call("count", piece)) == 0:
		skills.call("give", piece, 1)
	_sea.emit_signal("notice", "Found %s" % String(bag.call("item_name", piece)))
	for chart: String in cfg.get("pieces", {}):
		var need: Array = cfg["pieces"][chart]
		if not need.has(piece) or int(bag.call("count", chart)) > 0:
			continue
		var all_in := true
		for p: String in need:
			all_in = all_in and int(bag.call("count", p)) > 0
		if all_in:
			for p: String in need:
				bag.call("remove", p, 1)
			skills.call("give", chart, 1)
			_sea.emit_signal("notice", "The pieces fit together: %s. It is marked on your sea chart (M)" % String(bag.call("item_name", chart)))


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
	for local: Vector3 in _bodies_in(id):
		out.append(r.cell_of(local))
	return out


# Where every player in that dungeon stands (local to it).
func _bodies_in(id: String) -> Array:
	var out: Array = []
	var bodies: Array = [_player.global_position]
	var others: Callable = _sea.get("others")
	if others.is_valid():
		bodies.append_array(others.call())
	for at: Vector3 in bodies:
		var sea_at: Vector3 = _sea.call("local_of", at)
		if dungeon_at(sea_at) == id:
			out.append(sea_at - space_of(id))
	return out


# --- fights (host) ---

func _crews() -> Node:
	return _sea.get("ships").get("foes").get("crews")


func _run_fights() -> void:
	var crews := _crews()
	for id: String in spaces:
		var d: SeaDungeon = spaces[id]
		var fights := d.rules.of_kind("fight")
		if fights.is_empty():
			continue
		var bodies := _bodies_in(id) if d.built else []
		var changed := false
		for ch: String in fights:
			var key := id + ":" + ch
			var r := d.rules
			if r.state["active"].has(ch):
				if bodies.is_empty():  # everyone left: it starts again next time
					drop_fight(id, ch)
					changed = true
					continue
				var alive: Array = (_fights.get(key, []) as Array).filter(func(m: int) -> bool: return (crews.get("men") as Dictionary).has(m))
				_fights[key] = alive
				if alive.is_empty():
					if r.next_wave(ch):
						_spawn_wave(id, ch)
						last = "%s fight %s wave %d" % [id, ch, int(r.state["active"][ch]) + 1]
					else:
						r.clear_fight(ch)
						_fights.erase(key)
						last = "%s fight %s cleared" % [id, ch]
						_sea.emit_signal("notice", String(r.things[ch].get("notice", "The way opens")))
					changed = true
			elif not bool(r.state["cleared"].get(ch, false)) and not bodies.is_empty():
				var spot := r.at_of(r.cell_of_thing(ch))
				for local: Vector3 in bodies:
					if Vector2(local.x - spot.x, local.z - spot.z).length() <= float(r.things[ch].get("reach_m", 7.0)):
						r.start_fight(ch)
						_spawn_wave(id, ch)
						last = "%s fight %s started" % [id, ch]
						changed = true
						break
		if changed:
			d.refresh(false)
			_dirty = true


func _spawn_wave(id: String, ch: String) -> void:
	var d: SeaDungeon = spaces[id]
	var r := d.rules
	var th: Dictionary = r.things[ch]
	var wave: Array = th["waves"][int(r.state["active"][ch])]
	var spawns: Array = th.get("spawns", [[r.cell_of_thing(ch).x, r.cell_of_thing(ch).y]])
	var ids: Array = []
	for i in wave.size():
		var c: Array = spawns[i % spawns.size()]
		var at := r.at_of(Vector2i(int(c[0]), int(c[1]))) + Vector3(float(floori(float(i) / float(spawns.size()))) * 0.9, 0.0, 0.0)
		var n := int(_crews().call("dungeon_spawn", String(wave[i]), d, at, int(cfg["dungeons"][id].get("region", 1))))
		if n >= 0:
			ids.append(n)
	_fights[id + ":" + ch] = ids


# Host: a fight's foes taken away and it set back (everyone left, or the dungeon reset).
func drop_fight(id: String, ch: String) -> void:
	_crews().call("dungeon_clear", _fights.get(id + ":" + ch, []))
	_fights.erase(id + ":" + ch)
	(spaces[id] as SeaDungeon).rules.reset_fight(ch)


# Dev / checks: every foe of this dungeon's fights struck down (as if by this player).
func slay(id: String) -> int:
	var n := 0
	var men: Dictionary = _crews().get("men")
	for key: String in _fights:
		if key.begins_with(id + ":"):
			for m: int in _fights[key]:
				if men.has(m) and is_instance_valid(men[m]["enemy"]):
					(men[m]["enemy"] as Node).call("on_hit", 1.0e6)
					n += 1
	return n


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
			(spaces[id] as SeaDungeon).rules.state["active"] = {}  # (nobody is in it now: a fight left going starts again)
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
		if where == "" or id == where:  # (inside: only that one)
			parts.append((spaces[id] as SeaDungeon).status())
	var camera := get_viewport().get_camera_3d()
	var foes: Array = []
	var men: Dictionary = _crews().get("men")
	for m: int in men:
		if men[m].has("dungeon"):
			var e: Node3D = men[m]["enemy"]
			if is_instance_valid(e):
				foes.append("%s@%s hp%d%s" % [String(men[m]["kind"]).left(8), str(e.position.snapped(Vector3(0.1, 0.1, 0.1))), int(float(e.get("health").get("hp"))), " P" if bool(e.get("puppet")) else ""])
	var held: Array = []  # chart pieces / joined charts in this player's bag (sea step 9d)
	var skills: Node = _sea.get("skills")
	if skills != null:
		for chart: String in cfg.get("pieces", {}):
			for item: String in [chart] + Array(cfg["pieces"][chart]):
				if int(skills.get("bag").call("count", item)) > 0:
					held.append(item)
	return "dungeons: pieces %s; in '%s' (dark look %s, settling %s, falls %d, tide hurt %.0f), acts %d, applied %d, last '%s'; foes [%s]; %s" % [str(held), where, str(camera != null and camera.environment == _env), str(not _settle.is_empty()), falls, tide_hurt, acts, applied, last, ", ".join(foes), "; ".join(parts)]
