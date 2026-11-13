# Purpose: photo mode. The photo key (F10) hides every screen of the game and flies a free camera from where the
# player stands: move keys fly, jump / crouch rise and sink, sprint flies fast, the mouse looks, the wheel zooms,
# skill keys (Q / E) roll, the shoot key takes a picture into the Pictures folder (data/photo_mode.json), the photo
# key or Esc leaves. Alone the game stands still while it is open; online it goes on and the character stands.
# The character is shown in third person meanwhile, so it can be in the picture.
# Dependencies: core/photo_rules.gd, core/data_store.gd, data/photo_mode.json, game/input_setup.gd (key names), game/player.gd (controls_enabled,
# third_person, set_third_person).
extends Node

const PhotoRules = preload("res://core/photo_rules.gd")
const DataStore = preload("res://core/data_store.gd")
const InputSetup = preload("res://game/input_setup.gd")

signal saved(path: String)  # a picture was written

var rules := PhotoRules.new()
var active := false
var last_path := ""
var folder_override := ""  # developer runs write here instead of the player's Pictures folder

var _cfg := {}
var _player: Node3D
var _settings: RefCounted
var _camera := Camera3D.new()
var _before: Camera3D  # the camera that was in use
var _hidden: Array = []  # the screens (CanvasLayers) hidden while it is open
var _paused_it := false
var _was_third := false
var _yaw := 0.0
var _pitch := 0.0
var _roll := 0.0
var _hint := Label.new()
var _layer := CanvasLayer.new()
var _note_time := 0.0
var _taking := false


func setup(player: Node3D, settings: RefCounted) -> void:
	_player = player
	_settings = settings
	_cfg = DataStore.load_json("res://data/photo_mode.json")
	rules.setup(_cfg)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_camera)
	_layer.layer = 20
	add_child(_layer)
	_hint.position = Vector2(16, 12)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 4)
	_layer.add_child(_hint)
	_layer.visible = false


# Opens it. `alone` = nobody else plays here, so the game may stand still.
func enter(alone: bool) -> void:
	if active:
		return
	active = true
	_before = get_viewport().get_camera_3d()
	if _before == null:
		active = false
		return
	_camera.global_transform = _before.global_transform
	_camera.fov = _before.fov
	var turn := _before.global_transform.basis.get_euler()
	_yaw = turn.y
	_pitch = turn.x
	_roll = 0.0
	_camera.current = true
	_hidden.clear()
	for screen: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if screen != _layer and (screen as CanvasLayer).visible:
			(screen as CanvasLayer).visible = false
			_hidden.append(screen)
	_was_third = bool(_player.get("third_person"))
	_player.call("set_third_person", true)
	_player.set("controls_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_layer.visible = true
	_show_hint("")
	_paused_it = alone and not get_tree().paused
	if _paused_it:  # a moment first: the character's body is placed and posed by its own updates, which a pause stops
		await get_tree().create_timer(0.25).timeout
		if active:
			get_tree().paused = true


func leave() -> void:
	if not active:
		return
	active = false
	_layer.visible = false
	for screen: Variant in _hidden:
		if is_instance_valid(screen):
			(screen as CanvasLayer).visible = true
	_hidden.clear()
	if is_instance_valid(_before):
		_before.current = true
	_player.call("set_third_person", _was_third)
	_player.set("controls_enabled", true)
	if _paused_it:
		get_tree().paused = false
	_paused_it = false


func _input(event: InputEvent) -> void:
	if not active:
		return
	get_viewport().set_input_as_handled()  # nothing else of the game reacts while it is open
	if event is InputEventMouseMotion:
		var sens := 0.0025 * (_camera.fov / 75.0)
		_yaw -= (event as InputEventMouseMotion).relative.x * sens
		_pitch = clampf(_pitch - (event as InputEventMouseMotion).relative.y * sens, -1.55, 1.55)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_camera.fov = rules.zoomed(_camera.fov, 1 if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		_show_hint("")
	elif event.is_action_pressed("photo_mode") or (event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE):
		leave()
	elif event.is_action_pressed("shoot"):
		take()


func _process(delta: float) -> void:
	if not active:
		return
	var step := float(_cfg.get("fast", 12.0)) if Input.is_action_pressed("sprint") else float(_cfg.get("speed", 4.0))
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var rise := (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	_roll += (float(Input.is_action_pressed("skill_1")) - float(Input.is_action_pressed("skill_2"))) * deg_to_rad(float(_cfg.get("roll", 45.0))) * delta
	var look := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var wanted := _camera.global_position + (look * Vector3(input.x, 0.0, input.y) + Vector3.UP * rise) * step * delta
	_camera.global_position = rules.keep_near(_player.global_position + Vector3(0, 1.6, 0), wanted)
	_camera.global_basis = look * Basis(Vector3.FORWARD, _roll)
	_note_time = maxf(_note_time - delta, 0.0)
	if _note_time <= 0.0 and _hint.text.begins_with("Saved"):
		_show_hint("")


# Writes what the camera sees (without the hint) into the pictures folder.
func take() -> void:
	if _taking:
		return
	_taking = true
	_hint.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_hint.visible = true
	_taking = false
	var folder := folder_path()
	DirAccess.make_dir_recursive_absolute(folder)
	var when := Time.get_datetime_dict_from_system()
	var extra := 0
	var path := folder.path_join(rules.file_name(when, extra))
	while FileAccess.file_exists(path):
		extra += 1
		path = folder.path_join(rules.file_name(when, extra))
	if image == null or image.save_png(path) != OK:
		_show_hint("Could not save the picture in %s" % folder)
		return
	last_path = path
	saved.emit(path)
	_show_hint("Saved %s" % path)
	_note_time = 4.0


func folder_path() -> String:
	if folder_override != "":
		return folder_override
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pictures == "" or not DirAccess.dir_exists_absolute(pictures):
		return ProjectSettings.globalize_path("user://screenshots")
	return pictures.path_join(String(_cfg.get("folder", "Looter Shooter Photos")))


func _show_hint(note: String) -> void:
	var keys := func(action: String) -> String: return InputSetup.label(_settings, action)
	_hint.text = "PHOTO MODE   move keys fly, %s / %s up / down, %s fast, mouse look, wheel zoom (%d), %s / %s roll, %s = take a picture, %s or Esc = back" % [keys.call("jump"), keys.call("crouch"), keys.call("sprint"), int(_camera.fov), keys.call("skill_1"), keys.call("skill_2"), keys.call("shoot"), keys.call("photo_mode")] + ("\n" + note if note != "" else "")
