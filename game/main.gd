# Purpose: entry scene: owns settings and the start, save, pause, settings and controls menus; starts and ends a game session.
# Dependencies: game/input_setup.gd, game/settings_io.gd, game/main_menu.gd, game/save_menu.gd, game/pause_menu.gd, game/settings_menu.gd, game/controls_menu.gd,
# game/game_session.gd, core/settings_state.gd, game/renderer_switch.gd.
extends Node3D

const InputSetup = preload("res://game/input_setup.gd")
const SettingsIO = preload("res://game/settings_io.gd")
const SettingsState = preload("res://core/settings_state.gd")
const MainMenu = preload("res://game/main_menu.gd")
const SaveMenu = preload("res://game/save_menu.gd")
const PauseMenu = preload("res://game/pause_menu.gd")
const SettingsMenu = preload("res://game/settings_menu.gd")
const ControlsMenu = preload("res://game/controls_menu.gd")
const SoundMenu = preload("res://game/sound_menu.gd")
const CrosshairMenu = preload("res://game/crosshair_menu.gd")
const LoadingScreen = preload("res://game/loading_screen.gd")
const LoadClock = preload("res://game/load_clock.gd")
const NetSession = preload("res://game/net_session.gd")
const LobbyMenu = preload("res://game/lobby_menu.gd")
const RendererSwitch = preload("res://game/renderer_switch.gd")

var _settings := SettingsState.new()
var _main_menu: Control
var _save_menu: Control  # the three save slots, shown before a solo game and before the lobby
var _save_for_online := false  # the save menu was opened from Multiplayer
var _character := ""  # name of the chosen slot's character ("" = no slot: scripted developer runs)
var _fresh := false  # that character was just created: its first session opens the customize menu
var _pause_menu: Control
var _settings_menu: Control
var _controls_menu: Control
var _sound_menu: Control
var _crosshair_menu: Control
var _loading: Control  # the picture shown while a session is built or Aurelind is entered
var _settings_return: Control  # menu to show again when settings closes
var _session: Node3D
var _net: Node3D  # online session (always present, idle until used)
var _lobby: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus keep working while the game is paused
	LoadClock.mark("engine start, main scene, menu scripts")
	SettingsIO.load_into(_settings)
	if RendererSwitch.relaunch_if_needed(_settings.renderer, get_tree(), ""):
		set_process_unhandled_input(false)
		return
	InputSetup.register(_settings)
	SettingsIO.apply_display(_settings)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_net = NetSession.new()
	_net.name = "Net"  # same node path on every peer, required for RPC
	add_child(_net)
	_net.begin_play.connect(_start_online)
	_net.left.connect(_on_net_left)

	_main_menu = MainMenu.new()
	_main_menu.multiplayer_pressed.connect(_pick_save.bind(true))
	_main_menu.start_pressed.connect(_pick_save.bind(false))
	_main_menu.settings_pressed.connect(_open_settings.bind(_main_menu))
	_main_menu.quit_pressed.connect(_quit)
	layer.add_child(_main_menu)

	_save_menu = SaveMenu.new()
	_save_menu.chosen.connect(_on_save_chosen)
	_save_menu.back_pressed.connect(func() -> void: _show_only(_main_menu))
	layer.add_child(_save_menu)

	_pause_menu = PauseMenu.new()
	_pause_menu.resume_pressed.connect(_resume)
	_pause_menu.settings_pressed.connect(_open_settings.bind(_pause_menu))
	_pause_menu.main_menu_pressed.connect(_end_game)
	_pause_menu.quit_pressed.connect(_quit)
	layer.add_child(_pause_menu)

	_settings_menu = SettingsMenu.new()
	_settings_menu.settings = _settings
	_settings_menu.changed.connect(_on_settings_changed)
	_settings_menu.closed.connect(_close_settings)
	_settings_menu.controls_pressed.connect(_open_controls)
	_settings_menu.sounds_pressed.connect(func() -> void: _show_only(_sound_menu))
	_settings_menu.crosshair_pressed.connect(func() -> void: _show_only(_crosshair_menu))
	layer.add_child(_settings_menu)

	_controls_menu = ControlsMenu.new()
	_controls_menu.settings = _settings
	_controls_menu.changed.connect(_on_controls_changed)
	_controls_menu.closed.connect(_close_controls)
	layer.add_child(_controls_menu)

	_sound_menu = SoundMenu.new()
	_sound_menu.settings = _settings
	_sound_menu.changed.connect(_on_settings_changed)
	_sound_menu.closed.connect(_close_controls)  # saves and goes back to the settings, like the controls page
	layer.add_child(_sound_menu)

	_crosshair_menu = CrosshairMenu.new()
	_crosshair_menu.settings = _settings
	_crosshair_menu.changed.connect(_on_settings_changed)
	_crosshair_menu.closed.connect(_close_controls)  # saves and goes back to the settings
	layer.add_child(_crosshair_menu)

	_lobby = LobbyMenu.new()
	_lobby.net = _net
	_lobby.back_pressed.connect(func() -> void: _show_only(_main_menu))
	layer.add_child(_lobby)
	_loading = LoadingScreen.new()
	layer.add_child(_loading)  # last = on top of every menu
	LoadClock.mark("settings, input, menus")

	_show_only(_main_menu)
	if OS.get_cmdline_user_args().has("--autostart"):  # developer check (tools/game_boot_check.tscn): skip the menu
		_start_game()
		if ResourceLoader.exists("res://tools/dev_boot.gd"):
			add_child((load("res://tools/dev_boot.gd") as GDScript).new())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	if _session != null and _session.close_inventory():
		pass
	elif _controls_menu.visible or _crosshair_menu.visible:
		_close_controls()
	elif _settings_menu.visible:
		_close_settings()
	elif _session == null:
		return
	elif _pause_menu.visible:
		_resume()
	else:
		get_tree().paused = true
		_show_only(_pause_menu)
	get_viewport().set_input_as_handled()


# The game's own scripts (about a hundred files) are read here, under the loading picture, and not before the menu
# shows: the menu comes up sooner and the wait has something to look at.
func _start_game() -> void:
	_show_only(null)
	_loading.call("begin", 10)
	var session_script := load("res://game/game_session.gd") as GDScript
	LoadClock.mark("game scripts read")
	_session = session_script.new() as Node3D
	_session.loading = _loading
	_session.settings = _settings
	_session.net = _net
	_session.process_mode = Node.PROCESS_MODE_PAUSABLE
	_session.player_name = _net.local_name() if _net.is_active() else _character
	add_child(_session)
	_session.look_changed.connect(_net.send_look)
	_session.card_changed.connect(_net.send_card)
	_session.table_event.connect(_net.send_table_event)
	_net.table_event_received.connect(_session.apply_table_event)
	if _net.is_active():
		_net.bind_world(_session, _session.local_player(), _session.director())
	_loading.call("finish")
	_show_only(null)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _fresh:
		_fresh = false
		_session.customize_now()


# Start Game and Multiplayer both go through the save slots first.
func _pick_save(online: bool) -> void:
	_save_for_online = online
	_show_only(_save_menu)


func _on_save_chosen(character: String, fresh: bool) -> void:
	_character = character
	_fresh = fresh
	if _save_for_online:
		_lobby.set_player_name(character)
		_show_only(_lobby)
	else:
		_start_game()


func _resume() -> void:
	get_tree().paused = false
	_show_only(null)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Online: the host pressed Start (or we joined a running session).
func _start_online() -> void:
	if _session == null:
		_start_game()


# Online session ended (we left, or the host closed it).
func _on_net_left(_reason: String) -> void:
	if _session != null:
		_end_game()
		_show_only(_lobby)


# Closes the online session first so quitting never waits on the network.
func _quit() -> void:
	_net.leave()
	get_tree().quit()


func _end_game() -> void:
	get_tree().paused = false
	if _session != null:
		_session.queue_free()
		_session = null
	if _net.is_active() or _net.is_migrating():
		_net.leave()
	_show_only(_main_menu)


func _open_settings(from: Control) -> void:
	_settings_return = from
	_show_only(_settings_menu)


func _close_settings() -> void:
	SettingsIO.save(_settings)
	_show_only(_settings_return)


func _open_controls() -> void:
	_show_only(_controls_menu)


func _close_controls() -> void:
	SettingsIO.save(_settings)
	_show_only(_settings_menu)


func _on_controls_changed() -> void:
	SettingsIO.save(_settings)
	if _session != null:
		_session.apply_settings()


func _on_settings_changed() -> void:
	SettingsIO.apply_display(_settings)
	if _session != null:
		_session.apply_settings()


# Shows one menu (or none) and frees the mouse whenever a menu is up.
func _show_only(menu: Control) -> void:
	for m in [_main_menu, _save_menu, _pause_menu, _settings_menu, _controls_menu, _sound_menu, _crosshair_menu, _lobby]:
		m.visible = (m == menu)
	if menu != null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
