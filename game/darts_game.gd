# Purpose: (polish1 item 71) darts in the club's games room against the house: F on a throw line opens the start
# menu (game, opponent, stake); the view goes to the line looking at the board. You aim with the mouse while the aim
# drifts like a real hand (hold right mouse to steady it for a few seconds, then it shakes), left mouse throws: the
# dart flies and sticks where it lands. Three darts a turn, then the house player throws (it picks targets like a
# club player and scatters by its skill). Rules and scoring: core/darts_rules.gd. Chips: the stake leaves the wallet
# at the start, a win pays it back twice; leaving a running game forfeits it.
# Dependencies: core/darts_rules.gd, game/dart_board.gd, game/darts_screen.gd, data/darts.json, core/data_store.gd,
# core/wallet.gd (handed in), game/player.gd, game/player_hud.gd, game/fantasy_sounds.gd (sounds dart_throw / dart_hit / dart_bust).
extends Node3D

const Rules = preload("res://core/darts_rules.gd")
const DartBoard = preload("res://game/dart_board.gd")
const DartsScreen = preload("res://game/darts_screen.gd")
const DataStore = preload("res://core/data_store.gd")

signal finished  # chips changed: the session saves

const NEAR := 1.1  # metres from the middle of a throw line
const SENSITIVITY := 0.32  # board millimetres per mouse pixel
const YOU := Color(0.95, 0.15, 0.2)
const HOUSE := Color(0.2, 0.55, 1.0)

var cfg: Dictionary
var rules: Rules
var boards: Array[DartBoard] = []
var _wallet: RefCounted
var _player: CharacterBody3D
var _hud: Control
var _sounds: Node
var _rng: RandomNumberGenerator
var _screen: DartsScreen
var _cam: Camera3D
var _was_cam: Camera3D
var _board: DartBoard
var _state := ""  # "" closed, "menu", "aim", "flying", "wait", "result"
var _ai: Dictionary
var _stake := 0
var _paid := false
var _names: Array = ["You", "House"]
var _aim := Vector2.ZERO  # board mm where the hand points
var _t := 0.0
var _steady_left := 1.0  # share of the steady time left (refills when not held)
var _steadying := false
var _token := 0  # bumped when a game ends or the board is left, so waiting steps stop
var _flights: Array = []  # [node, from, to, mm, colour, t, dur, done Callable]
var _last_mode := "501"
var _last_opp := ""
var _turn_text: Array = ["", ""]
var player_name := "You"


func setup(wallet: RefCounted, player: CharacterBody3D, hud: Control, layer: CanvasLayer, sounds: Node, rng: RandomNumberGenerator, club_centre: Vector3) -> void:
	_wallet = wallet
	_player = player
	_hud = hud
	_sounds = sounds
	_rng = rng
	cfg = DataStore.load_json("res://data/darts.json")
	rules = Rules.new(cfg)
	for b: Dictionary in cfg["boards"]:
		var board: DartBoard = DartBoard.new()
		add_child(board)
		board.global_position = club_centre + Vector3(float(b["at"][0]), float(b["at"][1]), float(b["at"][2]))
		board.rotation_degrees.y = float(b.get("yaw", 90.0))
		board.setup(rules, float(cfg["distance_m"]), float(b["at"][1]))
		boards.append(board)
	_screen = DartsScreen.new()
	layer.add_child(_screen)
	_screen.setup(cfg)
	_screen.start.connect(_on_start)
	_screen.again.connect(func() -> void: _on_start(_last_mode, _last_opp, _stake))
	_screen.closed.connect(close)
	_cam = Camera3D.new()
	_cam.fov = 24.0
	add_child(_cam)


# The board whose throw line `pos` stands at, or -1.
func near(pos: Vector3) -> int:
	for i in boards.size():
		var o := boards[i].oche_position()
		if Vector2(pos.x - o.x, pos.z - o.z).length() < NEAR:
			return i
	return -1


func is_open() -> bool:
	return _state != ""


func open(i: int) -> void:
	_board = boards[i]
	_state = "menu"
	_player.controls_enabled = false
	_hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var behind := _board.oche_position() + _board.normal() * 0.7  # the body steps back from the line (the view is at the line)
	_player.call("teleport", behind + Vector3(0, 0.1, 0), _player.rotation.y)
	_was_cam = get_viewport().get_camera_3d()
	_cam.global_position = _board.eye_position()
	_cam.look_at(_board.global_position, Vector3.UP)
	_cam.make_current()
	_screen.show_menu(int(_wallet.get("balance")))
	_board.set_chalk("DARTS\n\n501\nAround the\nClock")


func close() -> void:
	if _state == "":
		return
	_token += 1
	_state = ""
	_screen.visible = false
	_screen.set_reticle(false, Vector2.ZERO, 1.0, false)
	for f: Array in _flights:
		(f[0] as Node3D).queue_free()
	_flights.clear()
	_board.clear_darts()
	_board.set_chalk("DARTS\n\n501\nAround the\nClock")
	if _was_cam != null and is_instance_valid(_was_cam):
		_was_cam.make_current()
	_player.controls_enabled = true
	_hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	finished.emit()


func _on_start(mode: String, opponent: String, stake: int) -> void:
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
	_last_mode = mode
	_last_opp = opponent
	_names = [player_name, String(_ai["name"])]
	rules.start(mode, 2)
	_board.clear_darts()
	_turn_text = ["", ""]
	_aim = Vector2(0, 103.0) if mode == "501" else rules.target_point("S1")  # start on the treble 20 / the 1
	_screen.show_play()
	_begin_turn()


func _begin_turn() -> void:
	_board.clear_darts()
	_turn_text[rules.current] = ""
	_show()
	if rules.current == 0:
		_state = "aim"
		_steady_left = 1.0
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_state = "wait"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_ai_turn(_token)


func _show() -> void:
	var needs: Array = [rules.need_text(0), rules.need_text(1)]
	var co := ""
	if rules.mode == "501" and rules.winner < 0:
		var path := rules.checkout(rules.scores[rules.current], rules.darts_left)
		if path != "":
			co = "Checkout: " + path
	elif rules.mode == "clock" and rules.winner < 0:
		co = "Aim for the " + ("BULL" if rules.scores[rules.current] >= 21 else str(rules.scores[rules.current]))
	_screen.show_scores(_names, needs, _turn_text, rules.current, co)
	var chalk := "%s\n" % ("501" if rules.mode == "501" else "CLOCK")
	for i in 2:
		chalk += "\n%s  %s" % [String(_names[i]).substr(0, 10), needs[i]]
	_board.set_chalk(chalk)


func _unhandled_input(event: InputEvent) -> void:
	if _state != "aim":
		return
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_aim += Vector2(motion.relative.x, -motion.relative.y) * SENSITIVITY
		_aim = _aim.limit_length(250.0)
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click == null:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		_steadying = click.pressed and _steady_left > 0.05
		get_viewport().set_input_as_handled()
	elif click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
		get_viewport().set_input_as_handled()
		_throw(_aim + _sway() + Vector2(_rng.randfn(0.0, float(cfg["aim"]["spread"])), _rng.randfn(0.0, float(cfg["aim"]["spread"]))), YOU, true)


# Where the drifting hand is off the aim: a slow figure of eight, calmer while steadying, shaking once steady runs out.
func _sway() -> Vector2:
	var a: Dictionary = cfg["aim"]
	var sp := float(a["sway_speed"])
	var amp := float(a["sway"])
	if _steadying:
		amp *= float(a["steady"])
	elif _steady_left <= 0.02:
		amp *= float(a["shake"])
	var wobble := Vector2(sin(_t * sp) + 0.35 * sin(_t * sp * 2.7 + 1.3), sin(_t * sp * 1.6 + 0.7) * 0.8 + 0.3 * sin(_t * sp * 3.3))
	return wobble * amp * (0.75 + 0.25 * sin(_t * 0.41))


func _process(delta: float) -> void:
	if _state == "":
		return
	_t += delta
	var a: Dictionary = cfg["aim"]
	if _steadying:
		_steady_left -= delta / float(a["steady_seconds"])
		if _steady_left <= 0.0:
			_steady_left = 0.0
			_steadying = false
	else:
		_steady_left = minf(_steady_left + delta / (float(a["steady_seconds"]) * 1.6), 1.0)
	if _state == "aim":
		var at := _board.mm_to_world(_aim + _sway(), 0.01)
		_screen.set_reticle(true, _cam.unproject_position(at), _steady_left, _steadying)
	else:
		_screen.set_reticle(false, Vector2.ZERO, _steady_left, false)
	var k := 0
	while k < _flights.size():
		var f: Array = _flights[k]
		f[5] = float(f[5]) + delta
		var u := clampf(float(f[5]) / float(f[6]), 0.0, 1.0)
		var from: Vector3 = f[1]
		var to: Vector3 = f[2]
		var pos := from.lerp(to, u) + Vector3(0, 0.09 * sin(PI * u), 0)  # a little arc
		var node := f[0] as Node3D
		var ahead := from.lerp(to, minf(u + 0.05, 1.0)) + Vector3(0, 0.09 * sin(PI * minf(u + 0.05, 1.0)), 0)
		node.global_position = pos
		if ahead.distance_to(pos) > 0.0001:
			node.look_at(ahead, Vector3.UP)
		if u >= 1.0:
			node.queue_free()
			_flights.remove_at(k)
			(f[7] as Callable).call()
			continue
		k += 1


# A dart toward board point p (mm). The player's comes from the right hand, the house's from the left.
func _throw(p: Vector2, colour: Color, mine: bool) -> void:
	_state = "flying"
	_steadying = false
	var dart := DartBoard.make_dart(colour)
	add_child(dart)
	var side := 0.16 if mine else -0.16
	var from := _cam.global_position + _cam.global_basis.x * side - _cam.global_basis.y * 0.1 - _cam.global_basis.z * 0.35
	_sounds.call("play", "dart_throw", from)
	var token := _token
	_flights.append([dart, from, _board.mm_to_world(p), p, colour, 0.0, float(cfg["aim"]["flight_seconds"]), func() -> void: _landed(p, colour, token)])


func _landed(p: Vector2, colour: Color, token: int) -> void:
	if token != _token:
		return
	_board.stick(p, colour, _rng)
	var res := rules.throw_dart(p)
	var hit: Dictionary = res["hit"]
	_sounds.call("play", "dart_hit" if String(hit["label"]) != "MISS" else "dart_throw", _board.mm_to_world(p))
	var who := rules.current
	var turn_sum := 0
	var parts: PackedStringArray = []
	for h: Dictionary in rules.turn_hits:
		parts.append(String(h["label"]))
		turn_sum += int(h["points"])
	_turn_text[who] = " ".join(parts) + ((" = %d" % turn_sum) if rules.mode == "501" else "")
	if bool(res["bust"]):
		_turn_text[who] = " ".join(parts) + "  BUST"
		_screen.callout("BUST", Color(1.0, 0.4, 0.35))
		_sounds.call("play", "dart_bust")
	elif String(hit["label"]) != "MISS":
		_screen.callout(String(hit["label"]), Color(1.0, 0.85, 0.35) if int(hit["mult"]) >= 2 or int(hit["number"]) == 25 else Color.WHITE)
	else:
		_screen.callout("MISS", Color(0.7, 0.7, 0.75))
	_show()
	if bool(res["won"]):
		_end_game(token)
		return
	if bool(res["turn_over"]):
		if rules.mode == "501" and not bool(res["bust"]) and rules.turn_hits.size() == 3:
			if turn_sum == 180:
				_screen.callout("ONE HUNDRED AND EIGHTY!", Color(1.0, 0.8, 0.2))
			elif turn_sum >= 100:
				_screen.callout("%d!" % turn_sum, Color(1.0, 0.85, 0.35))
		_state = "wait"
		await get_tree().create_timer(1.6).timeout
		if token != _token:
			return
		rules.next_turn()
		_begin_turn()
	elif who == 0:
		_state = "aim"


func _ai_turn(token: int) -> void:
	while token == _token and rules.current == 1 and rules.winner < 0:
		await get_tree().create_timer(float(_ai["think"])).timeout
		if token != _token or _state != "wait":
			return
		var target := rules.ai_target()
		var p := Rules.scatter(_rng, rules.target_point(target), float(_ai["sigma"]))
		var darts_before := rules.darts_left
		_throw(p, HOUSE, false)
		while token == _token and rules.darts_left == darts_before and rules.winner < 0:
			await get_tree().process_frame
		if token != _token or darts_before == 1 or rules.last_bust or rules.winner >= 0:
			return
		_state = "wait"


func _end_game(token: int) -> void:
	_state = "result"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(1.2).timeout
	if token != _token:
		return
	var won := rules.winner == 0
	var text := "YOU WIN!" if won else "%s wins." % String(_names[1])
	if _paid and won:
		_wallet.call("add", _stake * 2)
		text += "\n+%d chips" % _stake
	elif _paid:
		text += "\nYou lose %d chips." % _stake
	_paid = false
	_screen.show_result(text, won)
	finished.emit()


# Esc while playing: leave (a running game with a stake is lost).
func request_close() -> void:
	close()
