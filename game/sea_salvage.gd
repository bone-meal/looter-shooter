# Purpose: diving for salvage (sea step 5b): the hand-placed salvage spots (a sandy patch on the sea bed with a chest
# or a broken hull on it, a column of bubbles rising from it and fizzing at the surface while it still holds its
# find), taking a find when close enough under water (it fills that region's logbook set; a full set pays chips and
# Agility xp once), random trinkets brought up from dives deep enough (director: both kinds), Agility xp for time
# spent under water, and the logbook window (key J). The book is the character's (saved by the session).
# Dependencies: core/sea/salvage_book.gd, game/salvage_log_window.gd, game/fantasy_models.gd, data/sea/salvage.json,
# data/sea/writing/salvage.txt, assets/models/sea/{seabed_patch,salvage_chest,wreck_small}.gltf; the sea world
# (skills, notice), game/sea_swim.gd (under, depth), the session (group "game_session": wallet for chips).
extends Node3D

const SalvageBook = preload("res://core/sea/salvage_book.gd")
const LogWindow = preload("res://game/salvage_log_window.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const MODELS := "res://assets/models/sea/"

var cfg: Dictionary  # data/sea/salvage.json
var book: SalvageBook
var window := LogWindow.new()

var _sea: Node3D
var _player: CharacterBody3D
var _swim: Node3D  # game/sea_swim.gd
var _spots: Array = []  # {"cfg", "node", "bubbles": [CPUParticles3D]}
var _rng := RandomNumberGenerator.new()
var _deep_time := 0.0
var _under_time := 0.0
var _slow := 0.0
var _layer := CanvasLayer.new()


func setup(sea_world: Node3D, player: CharacterBody3D, swim: Node3D) -> void:
	_sea = sea_world
	_player = player
	_swim = swim
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/salvage.json"))
	book = SalvageBook.new(cfg, FileAccess.get_file_as_string("res://data/sea/writing/salvage.txt"))
	_rng.randomize()
	for spot: Dictionary in cfg["spots"]:
		_build_spot(spot)
	_layer.layer = 6
	window.book = book
	window.visible = false
	_layer.add_child(window)
	add_child(_layer)


func _build_spot(spot: Dictionary) -> void:
	var node := Node3D.new()
	node.position = Vector3(float(spot["at"][0]), -float(spot["depth"]), float(spot["at"][1]))
	add_child(node)
	for model: String in ["seabed_patch", String(spot["model"])]:
		if ResourceLoader.exists(MODELS + model + ".gltf"):
			var made := (load(MODELS + model + ".gltf") as PackedScene).instantiate() as Node3D
			for found in made.find_children("*", "MeshInstance3D", true, false):
				FantasyModels.dress((found as MeshInstance3D).mesh)
			made.rotation.y = float(_id(spot).hash() % 628) / 100.0
			node.add_child(made)
	var column := _bubbles(float(spot["depth"]) / 1.6, Vector3(0.4, 0.2, 0.4), 18, 1.6)  # rising from the find
	column.position.y = 0.6
	node.add_child(column)
	var fizz := _bubbles(0.7, Vector3(1.2, 0.05, 1.2), 26, 0.5)  # at the surface over it
	fizz.position.y = float(spot["depth"]) - 0.05
	node.add_child(fizz)
	_spots.append({"cfg": spot, "node": node, "bubbles": [column, fizz]})
	_show_found(_spots.back())


func _bubbles(life: float, box: Vector3, amount: int, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.05
	ball.height = 0.1
	ball.radial_segments = 6
	ball.rings = 3
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(0.92, 0.97, 1.0, 0.7)
	ball.material = look
	p.mesh = ball
	p.amount = amount
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3.UP
	p.spread = 8.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = speed * 0.8
	p.initial_velocity_max = speed * 1.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	return p


# The character's logbook from the save (the session calls this after building the sea).
func load_book(saved: Variant) -> void:
	book.from_dict(saved)
	for spot: Dictionary in _spots:
		_show_found(spot)


# A spot's find id, or the plan it holds.
func _id(spot_cfg: Dictionary) -> String:
	return String(spot_cfg.get("find", spot_cfg.get("plan", spot_cfg.get("hoard", ""))))


# Has this player already taken what a spot holds (a logged find, or a plan in the bag)?
func _taken(spot_cfg: Dictionary) -> bool:
	if spot_cfg.has("plan"):
		var skills: Variant = _sea.get("skills")
		return skills != null and int((skills as Node).get("bag").call("count", String(spot_cfg["plan"]))) > 0
	if spot_cfg.has("hoard"):  # (sea step 9d) a hoard a secret chart leads to: taken once per player
		return book.found.has("hoard:" + String(spot_cfg["hoard"]))
	return book.found.has(String(spot_cfg["find"]))


func _show_found(spot: Dictionary) -> void:
	var taken := _taken(spot["cfg"])
	for p: CPUParticles3D in spot["bubbles"]:
		p.emitting = not taken
		p.visible = not taken


# --- every frame ---

func _process(delta: float) -> void:
	if not bool(_sea.get("inside")):
		return
	_slow -= delta
	if _slow <= 0.0:
		_slow = 0.5
		var here: Vector3 = _sea.call("local_of", _player.global_position)
		for spot: Dictionary in _spots:
			var node: Node3D = spot["node"]
			node.visible = Vector2(node.position.x - here.x, node.position.z - here.z).length() <= float(cfg["dive"]["show_within"])
			if (spot["cfg"] as Dictionary).has("plan"):
				_show_found(spot)  # the plan may have come into the bag another way
	var dive: Dictionary = cfg["dive"]
	if not bool(_swim.get("under")):
		return
	_under_time += delta
	if _under_time >= 10.0:
		_under_time -= 10.0
		_xp(int(dive["xp_per_10s"]))
	if float(_swim.get("depth")) < float(dive["min_depth"]):
		return
	_deep_time += delta
	if _deep_time >= float(dive["random_every"]):
		_deep_time = 0.0
		if _rng.randf() < float(dive["random_chance"]):
			var id := book.roll_trinket(_rng)
			_logged(id, book.add_trinket(id))
			_xp(int(dive["xp_random"]))


# --- taking a find ---

func spot_near() -> Dictionary:
	if not bool(_player.get("swimming")):
		return {}
	for spot: Dictionary in _spots:
		var node: Node3D = spot["node"]
		if not _taken(spot["cfg"]) and node.global_position.distance_to(_player.global_position + Vector3(0, 0.8, 0)) <= float(cfg["dive"]["spot_reach"]) + 0.8:
			return spot
	return {}


func prompt(key: String) -> String:
	var spot := spot_near()
	if spot.is_empty():
		return ""
	return "[%s] Salvage: %s" % [key, spot_name(spot)]


func spot_name(spot: Dictionary) -> String:
	var cfg_spot: Dictionary = spot["cfg"]
	if cfg_spot.has("plan"):
		return String((_sea.get("skills") as Node).get("bag").call("item_name", String(cfg_spot["plan"])))
	if cfg_spot.has("hoard"):
		return String(cfg_spot.get("name", "a sunken hoard"))
	return book.name_of(String(cfg_spot["find"]))


# The nearest spot this player has not taken within `reach` m (flat) of a scene point: for the ship's crane.
func spot_within(at: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for spot: Dictionary in _spots:
		var node: Node3D = spot["node"]
		var d := Vector2(node.global_position.x - at.x, node.global_position.z - at.z).length()
		if not _taken(spot["cfg"]) and d <= best_d:
			best = spot
			best_d = d
	return best


func interact() -> bool:
	var spot := spot_near()
	if spot.is_empty():
		return false
	return take(spot, true)


# Takes what a spot holds: dived = by hand (Agility xp), else hauled up by the ship's crane (game/sea_crane.gd).
func take(spot: Dictionary, dived: bool) -> bool:
	if _taken(spot["cfg"]):
		return false
	if (spot["cfg"] as Dictionary).has("plan"):  # a ship's plan: into the bag, built at the shipyard
		var plan := String(spot["cfg"]["plan"])
		var skills: Node = _sea.get("skills")
		skills.call("give", plan, 1)
		_sea.emit_signal("notice", "Found the %s: build it at the shipyard" % String(skills.get("bag").call("item_name", plan)))
	elif (spot["cfg"] as Dictionary).has("hoard"):  # rolled on this player's machine like a chest (game/sea_flotsam.gd)
		book.found["hoard:" + String(spot["cfg"]["hoard"])] = true
		var flotsam: Node = _sea.get("ships").get("foes").get("flotsam")
		flotsam.call("grant", String(spot["cfg"]["loot"]), String(spot["cfg"].get("region", "region_1")))
		_sea.emit_signal("notice", "You raise %s" % String(spot["cfg"].get("name", "a sunken hoard")))
	else:
		var id := String(spot["cfg"]["find"])
		_logged(id, book.record(id))
	if dived:
		_xp(int(cfg["dive"]["xp_spot"]))
	_show_found(spot)
	return true


func _logged(id: String, result: Dictionary) -> void:
	if result.is_empty():
		return
	var set_id := String(result["set"])
	var title := String(book.titles.get(set_id, set_id))
	_sea.emit_signal("notice", "Logbook: %s%s  (%s %d/%d)" % [book.name_of(id), "" if bool(result["new"]) else " again", title, result["have"], result["of"]])
	if bool(result["complete"]):
		var pay: Dictionary = book.reward(set_id)
		var session := get_tree().get_first_node_in_group("game_session")
		if session != null and session.has_method("wallet"):
			session.call("wallet").call("add", int(pay.get("chips", 0)))
		if session != null and session.has_method("doubloons"):  # the sea's own money (sea step 6)
			session.call("doubloons").call("add", int(pay.get("doubloons", 0)))
		_xp(int(pay["xp"]))
		_sea.emit_signal("notice", "%s complete: +%d chips, +%d doubloons. %s" % [title, int(pay.get("chips", 0)), int(pay.get("doubloons", 0)), String(book.done_lines.get(set_id, ""))])
	window.queue_redraw()


func _xp(amount: int) -> void:
	var skills: Variant = _sea.get("skills")
	if skills != null and amount > 0:
		(skills as Node).call("gain_xp", "agility", amount)


func toggle_window() -> void:
	window.visible = not window.visible
	window.queue_redraw()


# --- dev ---

# Stands the player right at a spot's find (index in the data), under water.
func dev_to_spot(index: int) -> void:
	var node: Node3D = _spots[clampi(index, 0, _spots.size() - 1)]["node"]
	_player.call("teleport", node.global_position + Vector3(0.0, 1.0, 1.5), 0.0)


func status() -> String:
	return "salvage: under %s depth %.1f m, stamina %.0f/%.0f, found %s, trinkets %s, paid %s" % [str(_swim.get("under")), float(_swim.get("depth")), float(_swim.get("stamina")),
		float(_swim.call("max_stamina")), str(book.found.keys()), str(book.trinkets), str(book.paid.keys())]
