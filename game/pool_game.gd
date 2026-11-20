# Purpose: (polish1 item 71) 8-ball at the games room's pool tables, against the house: F at a table opens the menu
# (opponent, stake). Playing, like an online pool game: the mouse turns the aim (Shift: fine), the guide shows the
# ghost ball and both balls' paths; hold LEFT mouse and pull the mouse back to draw the cue (the power bar fills),
# release to strike; hold RIGHT mouse and move to put the red dot on the cue ball (spin: follow, draw, left / right
# english); C switches the camera (behind the cue / over the table); on the 8, Q / E choose the called pocket; with
# ball in hand the mouse moves the cue ball and a click puts it down. A shot clock runs out into a foul. The house
# player thinks, places, aims and shoots with its skill. Physics core/pool_sim.gd, rules core/pool_rules.gd, the
# house core/pool_ai.gd. Chips: the stake leaves the wallet at the start, a win pays it back twice.
# ONLINE (game/net_pool.gd, `link`): "Another player" opens the table; someone else there gets Join. The host plays
# every shot with its own physics: ours sends only the cue ball spot (if in hand), angle, power, spin and the called
# pocket; every machine plays the host's shot on its own table and snaps to the host's end. Others watch the balls.
# Dependencies: core/pool_sim.gd, core/pool_rules.gd, core/pool_ai.gd, game/pool_table.gd, game/pool_screen.gd,
# data/pool.json, core/data_store.gd, core/wallet.gd (handed in), game/player.gd, game/player_hud.gd,
# game/fantasy_sounds.gd (sounds pool_strike / pool_click / pool_cushion / pool_pocket), game/net_pool.gd (optional).
extends Node3D

const Sim = preload("res://core/pool_sim.gd")
const Rules = preload("res://core/pool_rules.gd")
const AI = preload("res://core/pool_ai.gd")
const PoolTable = preload("res://game/pool_table.gd")
const PoolScreen = preload("res://game/pool_screen.gd")
const DataStore = preload("res://core/data_store.gd")

signal finished  # chips changed: the session saves

const NEAR := 1.9  # metres from a table's middle to get the prompt
const TURN := 0.0026  # aim radians per mouse pixel (Shift: a fifth)
const PULL := 0.004  # power per mouse pixel pulled back
const SPIN_MOVE := 0.008

var cfg: Dictionary
var tables: Array[PoolTable] = []
var sims: Array = []
var rules := Rules.new()
var player_name := "You"
var _wallet: RefCounted
var _player: CharacterBody3D
var _hud: Control
var _sounds: Node
var _rng: RandomNumberGenerator
var _screen: PoolScreen
var _cam: Camera3D
var _was_cam: Camera3D
var _t_i := -1
var _table: PoolTable
var _sim: Sim
var _state := ""  # "" closed, "menu", "aim", "place", "rolling", "wait", "result"
var _ai: Dictionary
var _stake := 0
var _paid := false
var _names: Array = ["You", "House"]
var _me := 0
var _angle := 0.0
var _power := 0.0
var _pulling := false
var _spin := Vector2.ZERO
var _spinning := false
var _top_view := false
var _called := -1
var _clock := 45.0
var _token := 0
var _shot_called := -1
var _last_opp := ""
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _sound_gap := 0.0
var link: Node = null  # game/net_pool.gd in a lobby
var my_peer := Callable()
var _net := false
var _placed := Vector2.INF  # where we put the cue ball with ball in hand (sent with the shot online)
var _net_shot: Dictionary = {}  # the host's shot being played on our table
var _pending_end: Dictionary = {}  # the host's result, shown once the last shot has rolled
var _watch := {}  # table -> the host's shot rolling there for us as onlookers
var _sent_at := 0.0


func setup(wallet: RefCounted, player: CharacterBody3D, hud: Control, layer: CanvasLayer, sounds: Node, rng: RandomNumberGenerator, club_centre: Vector3) -> void:
	_wallet = wallet
	_player = player
	_hud = hud
	_sounds = sounds
	_rng = rng
	cfg = DataStore.load_json("res://data/pool.json")
	for t: Dictionary in cfg["tables"]:
		var sim := Sim.new(cfg)
		sim.rack(_rng)
		var table: PoolTable = PoolTable.new()
		add_child(table)
		table.global_position = club_centre + Vector3(float(t["at"][0]), float(t["at"][1]), float(t["at"][2]))
		table.rotation_degrees.y = float(t.get("yaw", 0.0))
		table.setup(sim)
		tables.append(table)
		sims.append(sim)
	_screen = PoolScreen.new()
	layer.add_child(_screen)
	_screen.setup(cfg)
	_screen.start.connect(_on_start)
	_screen.again.connect(func() -> void: _on_start(_last_opp, _stake))
	_screen.closed.connect(close)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.03
	add_child(_cam)
	_screen.join.connect(_on_join)


func set_link(net_pool: Node, peer_of_me: Callable) -> void:
	link = net_pool
	my_peer = peer_of_me
	link.started.connect(_on_net_started)
	link.shot.connect(_on_net_shot)
	link.ended.connect(_on_net_ended)
	link.refused.connect(_on_net_refused)


func _online() -> bool:
	return link != null and bool(link.call("online"))


func _table_state(i: int) -> Dictionary:
	if not _online():
		return {}
	var t: Array = link.get("tables")
	return t[i] if i < t.size() else {}


func near(pos: Vector3) -> int:
	for i in tables.size():
		var c := tables[i].global_position
		var l := tables[i].to_local(pos)
		if absf(l.x) < 1.27 + NEAR * 0.5 and absf(l.z) < 0.64 + NEAR * 0.5 and Vector2(pos.x - c.x, pos.z - c.z).length() < 2.6:
			return i
	return -1


func is_open() -> bool:
	return _state != ""


func open(i: int) -> void:
	_t_i = i
	_table = tables[i]
	_sim = sims[i]
	_state = "menu"
	_player.controls_enabled = false
	_hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_was_cam = get_viewport().get_camera_3d()
	_player.visible = false  # (its held gun stood in the view)
	_top_view = true
	_place_camera(true)
	_cam.make_current()
	var t := _table_state(i)
	if t.is_empty():
		_screen.show_menu(int(_wallet.get("balance")), _online())
	elif String(t["state"]) == "open":
		_screen.show_offer("%s waits for a challenger:\n8-ball for %s" % [String((t["names"] as Array)[0]), "fun (no chips)" if int(t["stake"]) == 0 else "%d chips" % int(t["stake"])])
	else:
		_screen.show_result("%s and %s are playing here." % [String((t["names"] as Array)[0]), String((t["names"] as Array)[1])], false, false)


func close() -> void:
	if _state == "":
		return
	if _online() and (_net or _state == "waiting"):
		link.call("ask_leave", _t_i)  # a running match is lost (the other wins), an open table is taken down
	if _state == "waiting" and _paid:
		_wallet.call("add", _stake)
	_net = false
	_net_shot = {}
	_pending_end = {}
	_token += 1
	_state = ""
	_paid = false
	_screen.visible = false
	_table.hide_guides()
	_table.show_cue(false)
	_table.show_called(-1)
	_table.show_place(false)
	if _was_cam != null and is_instance_valid(_was_cam):
		_was_cam.make_current()
	_player.visible = true
	_player.controls_enabled = true
	_hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	finished.emit()


func request_close() -> void:
	close()


func _on_start(opponent: String, stake: int) -> void:
	if opponent == "player":
		_open_for_player(stake)
		return
	if not _table_state(_t_i).is_empty():
		_screen.callout("This table is in use", Color(1.0, 0.45, 0.4))
		return
	_net = false
	_ai = {}
	for a: Dictionary in cfg["ai"]:
		if String(a["id"]) == opponent:
			_ai = a
	if _ai.is_empty():
		return
	if stake > 0 and not bool(_wallet.call("spend", stake)):
		_screen.callout("Not enough chips", Color(1.0, 0.45, 0.4))
		return
	_token += 1
	_stake = stake
	_paid = stake > 0
	_last_opp = opponent
	_me = 0
	_names = [player_name, String(_ai["name"])]
	_sim.rack(_rng)
	rules.start()
	_table.update_balls(0.0)
	_screen.show_play()
	_screen.names = _names
	_top_view = false
	_next_shot()


# ------------------------------------------------------------------ turns

func _next_shot() -> void:
	_refresh_bar()
	_spin = Vector2.ZERO
	_power = 0.0
	_pulling = false
	_clock = float(cfg["shot_clock"])
	_called = -1
	_placed = Vector2.INF
	_angle = _default_angle()
	_screen.message(rules.message.replace("{p0}", String(_names[0])).replace("{p1}", String(_names[1])))
	if rules.current == _me:
		_state = "place" if rules.ball_in_hand else "aim"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _state == "place" and _sim.on_table[0] == 0:
			_sim.place(0, _free_near(_sim.head_spot()))
		_hints()
	else:
		_state = "wait"
		_table.hide_guides()
		_table.show_cue(false)
		_screen.hint("" if not _net else "%s is shooting..." % String(_names[rules.current]))
		if not _net:
			_house_shot(_token)


func _default_angle() -> float:  # toward the nearest legal ball (or along the table on the break)
	if rules.break_shot:
		return (_sim.foot_spot() - _sim.pos[0]).angle()
	var best := 99.0
	var a := 0.0
	for b: int in rules.legal_targets(rules.current, _sim.on_table):
		var d := _sim.pos[0].distance_to(_sim.pos[b])
		if d < best:
			best = d
			a = (_sim.pos[b] - _sim.pos[0]).angle()
	return a


func _hints() -> void:
	if _state == "place":
		_screen.hint("BALL IN HAND: mouse moves the cue ball, left click puts it down    C: camera")
	else:
		var eight := rules.on_the_eight(rules.current, _sim.on_table)
		_screen.hint("Mouse: aim (Shift: fine)    Hold left mouse + pull back: power, let go: shoot    Hold right mouse: spin    C: camera" + ("    Q / E: called pocket" if eight else "") + "    Esc: leave")


func _refresh_bar() -> void:
	_screen.names = _names
	_screen.groups = rules.groups.duplicate()
	_screen.left = [_icons(0), _icons(1)]
	_screen.current = rules.current


func _icons(i: int) -> Array:
	if String(rules.groups[i]) == "":
		return []
	var out: Array = rules.left_of(i, _sim.on_table)
	if out.is_empty() and _sim.on_table[8] == 1:
		out = [8]
	return out


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if _state != "aim" and _state != "place":
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_C:
			_top_view = not _top_view
			get_viewport().set_input_as_handled()
		elif _state == "aim" and (key.keycode == KEY_Q or key.keycode == KEY_E) and rules.on_the_eight(rules.current, _sim.on_table):
			_called = posmod((_called if _called >= 0 else 0) + (1 if key.keycode == KEY_E else -1), 6)
			get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		get_viewport().set_input_as_handled()
		if _state == "place":
			var p := _sim.pos[0] + _screen_move(motion.relative) * 0.0016
			p.x = clampf(p.x, -_sim.length * 0.5 + _sim.r, _sim.length * 0.5 - _sim.r)
			p.y = clampf(p.y, -_sim.width * 0.5 + _sim.r, _sim.width * 0.5 - _sim.r)
			_sim.pos[0] = p
		elif _spinning:
			_spin = (_spin + Vector2(motion.relative.x, -motion.relative.y) * SPIN_MOVE).limit_length(0.85)
		elif _pulling:
			_power = clampf(_power + motion.relative.y * PULL, 0.0, 1.0)
		else:
			_angle += motion.relative.x * TURN * (0.2 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		return
	var click := event as InputEventMouseButton
	if click == null:
		return
	get_viewport().set_input_as_handled()
	if _state == "place":
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			if _sim.place(0, _sim.pos[0]):
				_placed = _sim.pos[0]
				_state = "aim"
				_angle = _default_angle()
				_hints()
			else:
				_screen.callout("Not there", Color(1.0, 0.45, 0.4))
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		_spinning = click.pressed
	elif click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_pulling = true
			_power = 0.0
		else:
			_pulling = false
			if _power > 0.02:
				_take_shot(_angle, _power, _spin, _called_for_shot())
			_power = 0.0


# Mouse movement turned into a move on the cloth as the camera sees it.
func _screen_move(rel: Vector2) -> Vector2:
	var right := _cam.global_basis.x
	var fwd := -_cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = _cam.global_basis.y  # looking straight down: screen up is the camera's up
		fwd.y = 0.0
	fwd = fwd.normalized()
	var w := right * rel.x - fwd * rel.y
	var l := _table.global_basis.inverse() * w
	return Vector2(l.x, l.z)


func _called_for_shot() -> int:
	if not rules.on_the_eight(rules.current, _sim.on_table):
		return -1
	return _called


# ------------------------------------------------------------------ the shot

func _take_shot(angle: float, power: float, spin: Vector2, called: int) -> void:
	if _net:  # the host plays it; it rolls here when its answer comes
		_state = "sent"
		_table.hide_guides()
		_table.show_cue(false)
		_table.show_place(false)
		_screen.show_power = false
		_screen.hint("")
		_sounds.call("play", "pool_strike", _table.to_world(_sim.pos[0]))
		link.call("ask_shot", _t_i, _placed, angle, power, spin, called)
		_sent_at = Time.get_ticks_msec() / 1000.0
		return
	_state = "rolling"
	_shot_called = called
	_table.hide_guides()
	_table.show_cue(false)
	_table.show_place(false)
	_screen.show_power = false
	_screen.hint("")
	_sounds.call("play", "pool_strike", _table.to_world(_sim.pos[0]))
	_sim.shoot(angle, power * power * 0.85 + power * 0.15, spin)  # finer control at the soft end


func _process(delta: float) -> void:
	_watch_step(delta)
	if _state == "":
		return
	if _state == "sent" and Time.get_ticks_msec() / 1000.0 - _sent_at > 5.0:  # the host did not take it: shoot again
		_state = "aim"
	_sound_gap = maxf(_sound_gap - delta, 0.0)
	if _state == "rolling":
		var hits_before := _sim.pocketed.size()
		var clicks := _sim.clicks
		var bumps := _sim.bumps
		_sim.step(delta)
		_table.update_balls(delta)
		var at := _table.centre_top()
		if _sim.clicks > clicks:
			_sounds.call("play", "pool_click", at)
		if _sim.bumps > bumps:
			_sounds.call("play", "pool_cushion", at)
		if _sim.pocketed.size() > hits_before:
			_sounds.call("play", "pool_pocket", at)
		if not _sim.moving:
			if _net:
				_net_shot_done(_token)
			else:
				_shot_done(_token, false)
	elif _state == "aim":
		if rules.current == _me:
			_clock -= delta
			if _clock <= 0.0 and not _net:  # (online the host calls the time)
				_shot_done(_token, true)
				return
		var target := _table.show_guides(_angle)
		if rules.on_the_eight(rules.current, _sim.on_table):
			if _called < 0:
				_called = _nearest_pocket_from(target)
			_table.show_called(_called)
		else:
			_table.show_called(-1)
		_table.show_cue(true, _angle, _power * 0.25 + 0.02, _spin)
		_screen.show_power = _pulling
	elif _state == "place":
		_clock -= delta
		var ok := true
		for j in range(1, 16):
			if _sim.on_table[j] == 1 and _sim.pos[j].distance_to(_sim.pos[0]) < 2.0 * _sim.r:
				ok = false
		_table.show_place(true, _sim.pos[0], ok)
		_table.update_balls(0.0)
		if _clock <= 0.0 and not _net:
			_shot_done(_token, true)
			return
	_screen.power = _power
	_screen.spin = _spin
	_screen.clock_share = clampf(_clock / float(cfg["shot_clock"]), 0.0, 1.0)
	_place_camera(false, delta)


func _nearest_pocket_from(ball: int) -> int:
	if ball < 0:
		return 0
	var ghost_dir := (_sim.pos[ball] - _sim.pos[0]).normalized()
	var best := 0
	var best_dot := -2.0
	var pockets: Array = _sim.pockets
	for k in pockets.size():
		var dd := ghost_dir.dot((pockets[k] - _sim.pos[ball]).normalized())
		if dd > best_dot:
			best_dot = dd
			best = k
	return best


func _shot_done(token: int, timed_out: bool) -> void:
	if token != _token:
		return
	var shooter := rules.current
	var res: Dictionary
	if timed_out:
		_sim.first_hit = -1
		_sim.pocketed.clear()
		res = rules.judge(-1, [], false, _sim.on_table, -1, true)
	else:
		res = rules.judge(_sim.first_hit, _sim.pocketed, _sim.rail_after_contact, _sim.on_table, _shot_called)
	_table.show_called(-1)
	_table.show_place(false)
	if bool(res["eight_respot"]):
		_sim.place(8, _free_near(_sim.foot_spot()))
	if _sim.on_table[0] == 0:
		_sim.place(0, _free_near(_sim.head_spot()))
	_table.update_balls(0.0)
	if int(res["winner"]) >= 0:
		_end_game(int(res["winner"]) == _me)
		return
	if String(res["foul"]) != "":
		_screen.callout("FOUL", Color(1.0, 0.4, 0.35))
	elif bool(res["turn_kept"]) and shooter == rules.current:
		_screen.callout("NICE", Color(0.6, 1.0, 0.6))
	_state = "wait"
	await get_tree().create_timer(0.9).timeout
	if token != _token:
		return
	_next_shot()


func _free_near(at: Vector2) -> Vector2:
	for k in 40:
		var p := at + Vector2(float(k % 5) * 0.07 - 0.14, floorf(float(k) / 5.0) * 0.07 * (1.0 if k % 2 == 0 else -1.0))
		var ok := true
		for j in 16:
			if j != 0 and j != 8 and _sim.on_table[j] == 1 and _sim.pos[j].distance_to(p) < 2.1 * _sim.r:
				ok = false
		if ok:
			return p
	return at


func _house_shot(token: int) -> void:
	await get_tree().create_timer(float(_ai["think"])).timeout
	if token != _token:
		return
	if rules.ball_in_hand:
		var at := AI.place_cue(_sim, rules, rules.current)
		if not _sim.place(0, at):
			_sim.place(0, _free_near(_sim.head_spot()))
		_table.update_balls(0.0)
		await get_tree().create_timer(0.6).timeout
		if token != _token:
			return
	var shot: Dictionary
	if rules.break_shot:
		shot = {"angle": (_sim.foot_spot() - _sim.pos[0]).angle() + _rng.randf_range(-0.02, 0.02), "power": 0.97, "spin": Vector2.ZERO, "called": -1}
	else:
		shot = AI.choose(_sim, rules, rules.current, _ai, _rng)
	# the house lines up: the cue swings round and draws back before the strike
	var from := _angle
	var steps := 30
	for k in steps:
		if token != _token:
			return
		var u := float(k + 1) / float(steps)
		_angle = lerp_angle(from, float(shot["angle"]), u)
		_table.show_cue(true, _angle, 0.02 + 0.2 * sin(u * PI * 0.5) * float(shot["power"]), shot["spin"])
		if rules.on_the_eight(rules.current, _sim.on_table):
			_table.show_called(int(shot["called"]))
		await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	if token != _token:
		return
	_take_shot(float(shot["angle"]), sqrt(float(shot["power"])), shot["spin"], int(shot["called"]))


func _end_game(won: bool) -> void:
	_state = "result"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_table.hide_guides()
	_table.show_cue(false)
	var text := ("YOU WIN!" if won else "%s wins." % String(_names[1 - _me])) + "\n" + rules.message
	if _paid and won:
		_wallet.call("add", _stake * 2)
		text += "\n+%d chips" % _stake
	elif _paid:
		text += "\nYou lose %d chips." % _stake
	_paid = false
	_screen.callout("GAME", Color(1.0, 0.85, 0.35))
	_screen.show_result(text, won)
	finished.emit()


# ------------------------------------------------------------------ online

func _open_for_player(stake: int) -> void:
	if not _online():
		return
	if not _table_state(_t_i).is_empty():
		_screen.callout("This table is in use", Color(1.0, 0.45, 0.4))
		return
	if stake > 0 and not bool(_wallet.call("spend", stake)):
		_screen.callout("Not enough chips", Color(1.0, 0.45, 0.4))
		return
	_stake = stake
	_paid = stake > 0
	_state = "waiting"
	link.call("ask_open", _t_i, stake)
	_screen.show_waiting("Waiting for a challenger at this table...\n8-ball for %s\n(another player walks up to this table and joins)" % ("fun" if stake == 0 else "%d chips" % stake))


func _on_join() -> void:
	var t := _table_state(_t_i)
	if t.is_empty() or String(t["state"]) != "open":
		_screen.show_result("Nobody is waiting here any more.", false, false)
		return
	var stake := int(t["stake"])
	if stake > 0 and not bool(_wallet.call("spend", stake)):
		_screen.callout("Not enough chips (%d)" % stake, Color(1.0, 0.45, 0.4))
		return
	_stake = stake
	_paid = stake > 0
	_state = "waiting"
	link.call("ask_join", _t_i)
	_screen.show_waiting("Joining...")


func _on_net_started(table: int, players: Array, names: Array, start: Dictionary, rules_d: Dictionary) -> void:
	var me := int(my_peer.call()) if my_peer.is_valid() else 0
	if table == _t_i and _state == "waiting" and players.has(me):
		_token += 1
		_net = true
		_me = players.find(me)
		_names = names.duplicate()
		_sim.from_dict(start)
		rules.from_dict(rules_d)
		_table.update_balls(0.0)
		_screen.show_play()
		_screen.callout("GAME ON", Color(1.0, 0.85, 0.35))
		_top_view = false
		_next_shot()
	elif table < sims.size() and not (_state != "" and table == _t_i):  # onlookers see the new rack
		(sims[table] as Sim).from_dict(start)
		tables[table].update_balls(0.0)


func _on_net_shot(table: int, data: Dictionary) -> void:
	if _net and table == _t_i:
		_net_shot = data
		_sim.from_dict(data["start"])
		var params: Array = data["params"]
		if params.is_empty():  # the shot clock ran out
			_net_shot_done(_token)
			return
		_state = "rolling"
		_table.hide_guides()
		_table.show_cue(false)
		var p := float(params[1])
		_angle = float(params[0])
		_sim.shoot(float(params[0]), p * p * 0.85 + p * 0.15, params[2])
		if int(data["shooter"]) != _me:
			_sounds.call("play", "pool_strike", _table.to_world(_sim.pos[0]))
	elif table < sims.size() and not (_state != "" and table == _t_i):
		var sim: Sim = sims[table]
		sim.from_dict(data["start"])
		var params2: Array = data["params"]
		if params2.is_empty():
			sim.from_dict(data["end"])
			tables[table].update_balls(0.0)
			return
		var p2 := float(params2[1])
		sim.shoot(float(params2[0]), p2 * p2 * 0.85 + p2 * 0.15, params2[2])
		_watch[table] = data


func _watch_step(delta: float) -> void:
	for t: int in _watch.keys():
		var sim: Sim = sims[t]
		sim.step(delta)
		tables[t].update_balls(delta)
		if not sim.moving:
			sim.from_dict((_watch[t] as Dictionary)["end"])
			tables[t].update_balls(0.0)
			_watch.erase(t)


func _net_shot_done(token: int) -> void:
	if token != _token or _net_shot.is_empty():
		return
	var data := _net_shot
	_net_shot = {}
	_sim.from_dict(data["end"])
	rules.from_dict(data["rules"])
	_table.update_balls(0.0)
	_table.show_called(-1)
	_table.show_place(false)
	if not _pending_end.is_empty() or rules.winner >= 0:
		_state = "wait"
		if not _pending_end.is_empty():
			_show_net_end()
		return
	if rules.foul != "":
		_screen.callout("FOUL", Color(1.0, 0.4, 0.35))
	elif rules.current == int(data["shooter"]):
		_screen.callout("NICE", Color(0.6, 1.0, 0.6))
	_state = "wait"
	await get_tree().create_timer(0.9).timeout
	if token != _token:
		return
	_next_shot()


func _on_net_ended(table: int, winner_peer: int, reason: String) -> void:
	if table != _t_i or not _net:
		return
	var me := int(my_peer.call()) if my_peer.is_valid() else 0
	var won := winner_peer == me
	var stake := _stake if _paid else 0
	if won and stake > 0:  # paid at once; shown once the last shot has rolled
		_wallet.call("add", stake * 2)
	_paid = false
	finished.emit()
	_pending_end = {"won": won, "reason": reason, "stake": stake}
	if reason != "won" or (_net_shot.is_empty() and _state != "rolling"):
		_show_net_end()


func _show_net_end() -> void:
	var e := _pending_end
	_pending_end = {}
	_net = false
	_state = "result"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_table.hide_guides()
	_table.show_cue(false)
	var other := String(_names[1 - _me])
	var won := bool(e["won"])
	var text := ("YOU WIN!" if String(e["reason"]) == "won" else "%s left: YOU WIN!" % other) if won else "%s wins." % other
	if String(e["reason"]) == "won":
		text += "\n" + rules.message
	var stake := int(e["stake"])
	if stake > 0:
		text += ("\n+%d chips" % stake) if won else ("\nYou lose %d chips." % stake)
	_screen.show_result(text, won, false)


func _on_net_refused(text: String) -> void:
	if _state != "waiting":
		return
	if _paid:
		_wallet.call("add", _stake)
		_paid = false
	_state = "menu"
	_screen.show_result(text, false, false)


# ------------------------------------------------------------------ camera

# Behind the cue (low, along the aim) or over the table; while balls roll the behind view rises to see more.
func _place_camera(snap: bool, delta := 0.0) -> void:
	var want_pos: Vector3
	var want_look: Vector3
	if _top_view or _state == "menu" or _state == "result" or _state == "place":
		var c := _table.centre_top()
		want_pos = c + Vector3(0, 2.75, 0) + _table.global_basis.z * 0.01
		want_look = c
	else:
		var p := _table.to_world(_sim.pos[0])
		var d := _table.dir_world(_angle)
		var rolling := _state == "rolling" or _state == "wait"
		want_pos = p - d * (1.45 if rolling else 0.85) + Vector3(0, 0.75 if rolling else 0.28, 0)
		want_look = p + d * (0.9 if rolling else 0.55)
	if snap:
		_cam_pos = want_pos
		_cam_look = want_look
	else:
		var k := 1.0 - exp(-delta * 8.0)
		_cam_pos = _cam_pos.lerp(want_pos, k)
		_cam_look = _cam_look.lerp(want_look, k)
	_cam.global_position = _cam_pos
	_cam.cull_mask = 0xFFFFF & ~PoolTable.LAMP_LAYER if (_top_view or _state in ["menu", "result", "place"]) else 0xFFFFF
	var up := Vector3.UP if absf((_cam_look - _cam_pos).normalized().y) < 0.98 else -_table.global_basis.z
	_cam.look_at(_cam_look, up)
