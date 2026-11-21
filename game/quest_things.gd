# Purpose: the main quest's things in the world (polish1 D4f: real models, tools/blender/quest_main.py): the keeper's
# logbook by a driftwood stump (its pages flip when read), the brine jars (a glowing strip of brine rises in each as
# they fill), the three old lamp posts (their lanterns are shot out: game/hidden_target.gd; they swing and go dark),
# the keeper's spyglass up in Wreck Cay's tree (turns toward Gull Rock when looked through), the bell key (rises
# glowing over the Re-forge's tray once forged, until the bell is opened) and the drowned bell on Gull Rock (chained
# shut; the key drops the chains and the bell swings and tolls). Draws, animates and reports lamp hits only:
# core/quest_state.gd decides.
# Dependencies: game/hidden_target.gd, game/fantasy_models.gd. `setup(places, on_lamp)`, `show_state(...)`, `play(id)`.
extends Node3D

const HiddenTarget = preload("res://game/hidden_target.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")

const BRINE := Color(0.4, 1.0, 0.9)
const LAMP_LIT := Color(1.0, 0.82, 0.45)

var _jar_glow := StandardMaterial3D.new()
var _fills: Array[Node3D] = []
var _lamp_glows: Array[StandardMaterial3D] = []
var _lanterns: Array[Node3D] = []
var _lamp_bodies: Array = []
var _was_out: Array[bool] = []
var _pages: Node3D = null
var _scope: Node3D = null
var _scope_rest := 0.0
var _scope_look := 0.0
var _key: Node3D = null
var _key_glow := StandardMaterial3D.new()
var _bell: Node3D = null
var _chain: Node3D = null
var _chain_rest := Vector3.ZERO
var _glow_soft := StandardMaterial3D.new()
var _time := 0.0
var _key_up := 0.0  # 0..1 how far the forged key has risen


# places (any may be missing): "log", "jars", "bell": {"at": Vector3, "yaw": float}; "lamps": [{"at": foot, "yaw"}];
# "spyglass": {"at", "yaw", "look": the yaw it turns to}; "key": Vector3 over the Re-forge's tray.
# on_lamp(index) is called when a lamp's lantern is shot.
func setup(places: Dictionary, on_lamp: Callable) -> void:
	_glow_soft.albedo_color = Color(0.85, 0.95, 1.0)
	_glow_soft.emission_enabled = true
	_glow_soft.emission = Color(0.7, 0.9, 1.0)
	_glow_soft.emission_energy_multiplier = 0.6
	if places.has("log"):
		var book := _place("quest_logbook", places["log"], _glow_soft)
		if book != null:
			_pages = book.find_child("Pages", true, false) as Node3D
	if places.has("jars"):
		_jar_glow.albedo_color = BRINE.darkened(0.7)
		_jar_glow.emission = BRINE
		var jars := _place("quest_jars", places["jars"], _jar_glow)
		if jars != null:
			for found in jars.find_children("Fill*", "Node3D", true, false):
				_fills.append(found as Node3D)
	var lamps: Array = places.get("lamps", [])
	for i in lamps.size():
		var glow := StandardMaterial3D.new()
		glow.albedo_color = LAMP_LIT
		glow.emission_enabled = true
		glow.emission = LAMP_LIT
		glow.emission_energy_multiplier = 2.2
		var post := _place("quest_lamp_post", lamps[i], glow)
		_lamp_glows.append(glow)
		_was_out.append(false)
		var lantern: Node3D = post.find_child("Lantern", true, false) as Node3D if post != null else null
		_lanterns.append(lantern)
		var body := HiddenTarget.new()  # the lantern takes the shot
		var spot: Dictionary = lamps[i]
		body.position = (spot["at"] as Vector3) + Basis(Vector3.UP, float(spot["yaw"])) * Vector3(0.0, 2.6, 0.78)
		body.hit_by = on_lamp.bind(i)
		var shape := CollisionShape3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.3
		shape.shape = ball
		body.add_child(shape)
		add_child(body)
		_lamp_bodies.append(body)
	if places.has("spyglass"):
		var glass := _place("quest_spyglass", places["spyglass"], _glow_soft)
		if glass != null:
			_scope = glass.find_child("Spin", true, false) as Node3D
			_scope_rest = 0.0
			_scope_look = wrapf(float(places["spyglass"]["look"]) - float(places["spyglass"]["yaw"]), -PI, PI)
	if places.has("key"):
		_key_glow.albedo_color = BRINE
		_key_glow.emission_enabled = true
		_key_glow.emission = BRINE
		_key_glow.emission_energy_multiplier = 2.0
		_key = _place("quest_bell_key", {"at": places["key"], "yaw": 0.0}, _key_glow)
		if _key != null:
			_key.scale = Vector3.ONE * 1.8
			_key.visible = false
	if places.has("bell"):
		var lock := StandardMaterial3D.new()
		lock.albedo_color = BRINE
		lock.emission_enabled = true
		lock.emission = BRINE
		lock.emission_energy_multiplier = 1.5
		var belfry := _place("quest_drowned_bell", places["bell"], lock)
		if belfry != null:
			_bell = belfry.find_child("Bell", true, false) as Node3D
			_chain = belfry.find_child("Chain", true, false) as Node3D
			if _chain != null:
				_chain_rest = _chain.position


# A model at {"at", "yaw"}, its Glow parts in `glow`, with one smooth box collider (not for the small key).
func _place(model: String, spot: Dictionary, glow: StandardMaterial3D) -> Node3D:
	var made := FantasyModels.scene(model)
	if made == null:
		push_warning("quest_things: no model " + model)
		return null
	var root := Node3D.new()
	root.position = spot["at"]
	root.rotation.y = float(spot.get("yaw", 0.0))
	add_child(root)
	root.add_child(made)
	for found in made.find_children("*", "MeshInstance3D", true, false):
		var n := found as Node
		while n != made:
			if String(n.name).begins_with("Glow"):
				(found as MeshInstance3D).material_override = glow
				break
			n = n.get_parent()
	if model in ["quest_drowned_bell", "quest_jars"]:
		var box := FantasyModels.bounds(made)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var solid := BoxShape3D.new()
		solid.size = Vector3(box.size.x * 0.9, box.size.y, box.size.z * 0.9)
		shape.shape = solid
		shape.position = box.get_center()
		body.add_child(shape)
		root.add_child(body)
	return made


func _process(delta: float) -> void:
	_time += delta
	if _key != null and _key.visible:
		_key_up = minf(_key_up + delta * 0.6, 1.0)
		_key.rotation.y = _time * 1.5
		_key.position.y = _key_up * 0.55 + sin(_time * 2.0) * 0.05
		_key_glow.emission_energy_multiplier = 1.4 + sin(_time * 3.0) * 0.5


# fill = 0..1 of the jars; lamps_out[i] = that lamp is out (lamps take shots only while `lamps_armed`); finished =
# step id -> true for every finished step; key_shown = the forged key hovers over the Re-forge.
func show_state(fill: float, lamps_out: Array, lamps_armed: bool, finished: Dictionary, key_shown: bool) -> void:
	var f := clampf(fill, 0.0, 1.0)
	_jar_glow.emission_enabled = f > 0.0
	_jar_glow.emission_energy_multiplier = 0.6 + 2.2 * f
	for fill_node in _fills:
		fill_node.scale = Vector3(1.0, maxf(f, 0.02), 1.0)
		fill_node.visible = f > 0.0
	for i in _lamp_glows.size():
		var out: bool = i < lamps_out.size() and bool(lamps_out[i])
		_lamp_glows[i].emission_enabled = not out
		_lamp_glows[i].albedo_color = Color(0.1, 0.1, 0.1) if out else LAMP_LIT
		(_lamp_bodies[i] as Node).set("armed", lamps_armed and not out)
		if out and not _was_out[i] and _lanterns[i] != null:  # just shot: the lantern jerks and swings itself still
			var swing := create_tween()
			var lantern: Node3D = _lanterns[i]
			for k in 5:
				swing.tween_property(lantern, "rotation:x", 0.6 * pow(0.55, k) * (1.0 if k % 2 == 0 else -1.0), 0.28)
			swing.tween_property(lantern, "rotation:x", 0.0, 0.3)
		_was_out[i] = out
	if _scope != null:
		_scope.rotation.y = _scope_look if finished.has("spyglass") else _scope_rest
	if _key != null:
		if key_shown and not _key.visible:
			_key_up = 0.0
		_key.visible = key_shown
	if _chain != null:
		_chain.visible = not finished.has("bell")


# A step was just finished here: its thing moves (shown after show_state put it in its end state).
func play(step_id: String) -> void:
	match step_id:
		"log":
			if _pages != null:
				var flip := create_tween()
				for k in 3:
					flip.tween_property(_pages, "rotation:z", -2.6, 0.35)
					flip.tween_property(_pages, "rotation:z", 0.0, 0.0)
		"spyglass":
			if _scope != null:
				_scope.rotation.y = _scope_rest
				create_tween().tween_property(_scope, "rotation:y", _scope_look, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		"bell":
			if _chain != null:
				_chain.visible = true
				_chain.position = _chain_rest
				var drop := create_tween()
				drop.tween_property(_chain, "position", _chain_rest + Vector3(0, -2.4, 0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				drop.tween_callback(func() -> void: _chain.visible = false)
			if _bell != null:
				var ring := create_tween()
				ring.tween_interval(0.5)
				for k in 8:
					ring.tween_property(_bell, "rotation:x", 0.5 * pow(0.8, k) * (1.0 if k % 2 == 0 else -1.0), 0.7).set_trans(Tween.TRANS_SINE)
				ring.tween_property(_bell, "rotation:x", 0.0, 0.7).set_trans(Tween.TRANS_SINE)


# Where the bell hangs (world), for the toll's sound.
func bell_at() -> Vector3:
	return _bell.global_position if _bell != null else Vector3.INF
