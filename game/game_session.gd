# Purpose: one play session: light, starting island, colosseum, local player, wave director, reward area (chest + door) after the arena is cleared, damage numbers, inventory screen and the HUD layers.
# Dependencies: game/pachinko_wall.gd, core/wallet.gd, data/casino.json, game/player.gd, game/island.gd, game/club_island.gd, game/crow_model.gd, game/reward_area.gd, game/damage_numbers.gd, game/inventory_screen.gd, core/loot_roll.gd, core/inventory_state.gd, game/input_setup.gd, game/colosseum.gd, game/wave_director.gd, game/player_hud.gd, game/enemy_bars.gd, game/debug_overlay.gd, game/scope_overlay.gd, core/settings_state.gd.
extends Node3D

const Player = preload("res://game/player.gd")
const Island = preload("res://game/island.gd")
const InputSetup = preload("res://game/input_setup.gd")
const RewardArea = preload("res://game/reward_area.gd")
const Explosives = preload("res://game/explosives.gd")
const SkillEffects = preload("res://game/skill_effects.gd")
const DamageNumbers = preload("res://game/damage_numbers.gd")
const InventoryScreen = preload("res://game/inventory_screen.gd")
const LootRoll = preload("res://core/loot_roll.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const DropRules = preload("res://core/drop_rules.gd")
const LootField = preload("res://game/loot_field.gd")
const VENDOR_RANGE := 2.0
const DataStore = preload("res://core/data_store.gd")
const ClubIsland = preload("res://game/club_island.gd")
const CrowModel = preload("res://game/crow_model.gd")
const Colosseum = preload("res://game/colosseum.gd")
const WaveDirector = preload("res://game/wave_director.gd")
const DebugOverlay = preload("res://game/debug_overlay.gd")
const ScopeOverlay = preload("res://game/scope_overlay.gd")
const PlayerHud = preload("res://game/player_hud.gd")
const EnemyBars = preload("res://game/enemy_bars.gd")
const OmahaWorld = preload("res://game/omaha_world.gd")
const OmahaSpawner = preload("res://game/omaha_spawner.gd")
const PaintingArt = preload("res://game/painting_art.gd")
const SettingsState = preload("res://core/settings_state.gd")
const ProfileIO = preload("res://game/profile_io.gd")
const Lifeguard = preload("res://game/lifeguard.gd")
const ProgressState = preload("res://core/progress_state.gd")
const CardScreen = preload("res://game/card_screen.gd")
const NpcChatter = preload("res://game/npc_chatter.gd")
const RenderStyle = preload("res://game/render_style.gd")
const CustomizeMenu = preload("res://game/customize_menu.gd")
const Wallet = preload("res://core/wallet.gd")
const PachinkoWall = preload("res://game/pachinko_wall.gd")
const SlotMachine = preload("res://game/slot_machine.gd")
const SlotScreen = preload("res://game/slot_screen.gd")
const SlotMath = preload("res://core/slot_math.gd")
const CasinoGames = preload("res://game/casino_games.gd")
const ChatBox = preload("res://game/chat_box.gd")
const ChatCommand = preload("res://core/chat_command.gd")
const AdminCommands = preload("res://game/admin_commands.gd")
const FantasyWorld = preload("res://game/fantasy_world.gd")

const HUD_REFRESH := 0.25
const ARENA_SPAWN := Vector3(0, 0.1, 10)
const PAINTING_RANGE := 4.5
const OMAHA_FOG := 0.0035
const REWARD_RANGE := 3.0
const CROW_RANGE := 6.0
const LIFEGUARD_RANGE := 3.2
const PACHINKO_RANGE := 2.8
const PACHINKO_HOLD_DELAY := 0.4
const PACHINKO_HOLD_EVERY := 0.15
const SLOT_RANGE := 2.0

signal look_changed(look: Dictionary)
signal table_event(op: String, args: Array)  # our blackjack table actions, sent to other players so they can watch
signal card_changed(progress: Dictionary)  # level, achievements or card edited: main.gd sends it to the other players

var settings: SettingsState  # set before add_child
var net: Node3D  # game/net_session.gd, set before add_child (idle when playing alone)
var player_name := ""  # set before add_child when playing online (the lobby name)
var _save_key := ""  # which save file (the typed name)
var _profile_name := ""  # saved with the inventory (see game/profile_io.gd)
var no_save := false  # scripted developer runs (tools/dev_boot.gd) leave the save file alone

var _player: Player
var _director: WaveDirector
var _hud := Label.new()
var _overlay := DebugOverlay.new()
var _scope := ScopeOverlay.new()
var _player_hud := PlayerHud.new()
var _bars := EnemyBars.new()
var _cross := Label.new()
var _hud_timer := 0.0
var _painting := Vector3.ZERO
var _painting_omaha := Vector3.ZERO
var _in_omaha := false
var _painting_fantasy := Vector3.ZERO
var _in_fantasy := false
var _fantasy: FantasyWorld  # built the first time the player enters (or from the save)
var _fantasy_saved: Variant  # the fantasy part of the profile, until that world is built
var _fantasy_exit := Vector3.ZERO
var _fantasy_dirty := false  # something changed in there: saved at most every 20 s
var _fantasy_saved_at := 0.0
var _hud_layer: CanvasLayer
var _omaha: OmahaWorld  # built the first time the player enters
var _spawner: OmahaSpawner
var _omaha_exit := Vector3.ZERO
var _env_saved: Dictionary = {}
var _in_arena := false
var _island_spawn := Vector3.ZERO
var _reward: RewardArea
var _customizer := CustomizeMenu.new()
var _progress := ProgressState.new(DataStore.load_json("res://data/progression.json"), DataStore.load_json("res://data/achievements.json"))  # level, stats, traits, achievements, card (saved in the profile)
var _card_screen := CardScreen.new()
var _render_style := RenderStyle.new()
var _wallet := Wallet.new()  # casino coins (saved in the profile)
var _jackpot := 500.0  # this player's progressive slot pot (saved in the profile)
var _casino_cfg: Dictionary
var _pachinko: PachinkoWall
var _pachinko_hold := 0.0
var _field := LootField.new()  # gun drops lying in the world
var _drops_cfg: Dictionary  # data/drops.json
var _casino: Dictionary
var _coins_dirty := false
var _slot_data: Dictionary
var _slot_math: SlotMath
var _slot_screen := SlotScreen.new()
var _slot_machines: Array = []
var _slot_machine: SlotMachine
var _slot_pending: Dictionary = {}
var _games := CasinoGames.new()
var _reset_left := 0.0  # seconds until a cleared arena starts over at round 1
var _numbers := DamageNumbers.new()
var _explosives := Explosives.new()
var _skill_fx := SkillEffects.new()
var _inventory_screen := InventoryScreen.new()
var _rng := RandomNumberGenerator.new()
var _loot_tables: Dictionary
var _crow_a: Node3D  # home-island crow (feed it worms to fly to the club island)
var _crow_b: Node3D  # club-island crow (flies you home for free)
var _ride_crow: Node3D  # the crow that actually flies
var _crow_cfg: Dictionary
var _club_spawn := Vector3.ZERO
var _crow_a_pos := Vector3.ZERO
var _crow_b_pos := Vector3.ZERO
var _fed := 0
var _eat_time := 0.0  # seconds left of the eating animation
var _time := 0.0
var _flight_t := -1.0  # seconds into a flight (-1 = not flying)
var _flight_from := Vector3.ZERO
var _flight_to := Vector3.ZERO
var _flight_dest := Vector3.ZERO
var _flight_src: Node3D  # the perched crow hidden during the flight
var _flight_prev_view := false
var _chat := ChatBox.new()
var _commands := AdminCommands.new()
var _chat_closed_at := -1.0  # engine time the chat input last closed (the same Enter must not reopen it)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_environment()
	var gates := Colosseum.build(self)
	var island := Island.build(self)
	_painting = island["painting"]
	_painting_omaha = island["painting_omaha"]
	_painting_fantasy = island["painting_fantasy"]
	_island_spawn = island["spawn"]
	_loot_tables = DataStore.load_json("res://data/loot_tables.json")["tables"]
	_rng.randomize()
	var club := ClubIsland.build(self)
	_club_spawn = club["spawn"]
	_casino_cfg = DataStore.load_json("res://data/casino.json")
	_wallet = Wallet.new(int(_casino_cfg["starting_coins"]))
	_casino = club["casino"]
	_pachinko = _casino["pachinko"]
	_pachinko.ball_landed.connect(_on_pachinko_landed)
	_slot_data = DataStore.load_json("res://data/slots.json")
	_slot_math = SlotMath.new(_slot_data)
	_jackpot = _slot_math.jackpot_seed
	_slot_machines = club["casino"]["slots"]
	for m in _slot_machines:
		m.finished.connect(_on_slot_finished)
	_crow_a_pos = Island.CROW_POS
	_crow_b_pos = club["crow"]
	_crow_cfg = DataStore.load_json("res://data/crow.json")
	_crow_a = _place_crow(_crow_a_pos, island["spawn"])
	_crow_b = _place_crow(_crow_b_pos, _club_spawn)
	var lifeguard := Lifeguard.new()
	lifeguard.position = Lifeguard.POS
	add_child(lifeguard)
	lifeguard.look_at(Lifeguard.POS + (Lifeguard.POS - Island.CENTER), Vector3.UP)
	_ride_crow = CrowModel.build()
	_ride_crow.visible = false
	add_child(_ride_crow)
	add_child(_numbers)
	add_child(_explosives)
	add_child(_skill_fx)
	_build_hud()

	_player = Player.new()
	_player.settings = settings
	_player.position = island["spawn"]
	add_child(_player)
	_player.damaged.connect(_player_hud.flash)
	_player.died.connect(_on_player_died)
	_player.blocked.connect(_player_hud.notice.bind("Blocked!"))
	_player.damage_numbers = _numbers
	_player.explosives = _explosives
	_player.skill_fx = _skill_fx
	_skill_fx.explosives = _explosives
	_skill_fx.numbers = _numbers
	_skill_fx.follow = _player
	_explosives.numbers = _numbers
	_explosives.ignore = _player.get_rid()
	_player_hud.player = _player
	_inventory_screen.inventory = _player.inventory
	_inventory_screen.items = _player.items
	_inventory_screen.gun_db = _player.gun_db
	_inventory_screen.changed.connect(_on_inventory_changed)
	add_child(_inventory_screen_layer())
	_customizer.applied.connect(_on_look_applied)
	_customizer.cancelled.connect(_close_customizer)
	var custom_layer := CanvasLayer.new()
	custom_layer.layer = 6
	custom_layer.add_child(_customizer)
	_card_screen.progress = _progress
	_card_screen.changed.connect(_on_card_changed)
	_card_screen.closed.connect(_on_card_closed)
	custom_layer.add_child(_card_screen)
	custom_layer.add_child(_slot_screen)
	_slot_screen.setup(_slot_data)
	_slot_screen.spin_requested.connect(_on_slot_spin)
	_slot_screen.closed.connect(_close_slots)
	_games.setup(_wallet, _casino_cfg, _casino, custom_layer, _player, _player_hud, _rng)
	(_casino["blackjack"] as Node3D).connect("changed", func(op: String, args: Array) -> void: table_event.emit(op, args))
	_games.round_finished.connect(save_profile)
	_games.left.connect(save_profile)
	add_child(_games)
	add_child(custom_layer)
	_load_profile()
	_update_pots()

	_director = WaveDirector.new()
	_director.setup(_player, gates)
	add_child(_director)
	_bars.source = _director
	_drops_cfg = DataStore.load_json("res://data/drops.json")
	_field.setup(_player.gun_db, _drops_cfg)
	add_child(_field)
	_director.killed.connect(_on_enemy_killed)
	_explosives.source = _director
	_skill_fx.source = _director
	_commands.session = self
	add_child(_commands)
	_chat.submitted.connect(_on_chat_submitted)
	_chat.opened.connect(func() -> void: _player.controls_enabled = false)
	_chat.closed.connect(_on_chat_closed)
	if net != null:
		net.chat.line.connect(func(sender: String, text: String) -> void: _chat.add_line("%s: %s" % [sender, text]))
		net.chat.reply.connect(func(text: String) -> void: _chat.add_line(text, Color(0.75, 0.9, 1.0)))
		net.chat.op_changed.connect(func(on: bool) -> void: _chat.add_line("The host %s commands." % ("lets you use" if on else "took away your"), Color(1.0, 0.85, 0.4)))
		net.chat.world_command = _run_world_command
		if net.is_active():
			_build_fantasy()
	apply_settings()


func apply_settings() -> void:
	_player.apply_settings()
	_render_style.apply(settings.graphics, settings.shaders)
	if _in_fantasy:
		_fantasy_detail()
		_fantasy.enter(_player.global_position)
	_overlay.visible = settings.show_debug


func _place_crow(at: Vector3, facing: Vector3) -> Node3D:
	var crow := CrowModel.build()
	add_child(crow)
	crow.position = at
	crow.look_at(Vector3(facing.x, at.y, facing.z), Vector3.UP)
	return crow


func _unhandled_input(event: InputEvent) -> void:
	if _customizer.visible or _slot_screen.visible or _games.is_open() or _card_screen.visible or (_fantasy != null and _fantasy.panel_open()):
		return
	if _flight_t >= 0.0:
		return
	if _chat.is_open():
		return
	if (event.is_action_pressed("chat") or event.is_action_pressed("command")) and not _inventory_screen.visible:
		if _time - _chat_closed_at > 0.15:
			_chat.open("/" if event.is_action_pressed("command") else "")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("card") and not _inventory_screen.visible:
		_open_card()
	elif event.is_action_pressed("inventory"):
		_toggle_inventory()
	elif event.is_action_pressed("interact") and not _inventory_screen.visible:
		_interact()


# Closes the inventory if it is open (main.gd calls this on Esc). Returns true if it did.
func close_inventory() -> bool:
	if _fantasy != null and _fantasy.close_panel():
		return true
	if _card_screen.visible:
		_card_screen.close()
		return true
	if _games.is_open():
		_games.request_close()
		return true
	if _slot_screen.visible:
		_slot_screen.close()
		return true
	if _customizer.visible:
		_close_customizer()
		return true
	if not _inventory_screen.visible:
		return false
	_toggle_inventory()
	return true


# Another player's blackjack table action: shown on our table unless we are playing a table game ourselves.
func apply_table_event(_peer: int, op: String, args: Array) -> void:
	if _games.is_open():
		return
	(_casino["blackjack"] as Node3D).call("apply_remote", op, args)


func _open_card() -> void:
	_card_screen.open(_card_line())
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_card_closed() -> void:
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	save_profile()


func _on_card_changed() -> void:
	_apply_progress()
	save_profile()
	card_changed.emit(_progress.to_dict())


func _card_line() -> String:
	return "Kills %d   Elites %d   Bosses %d   Chests %d" % [_progress.value_of("kills"), _progress.value_of("elite_kills"), _progress.value_of("boss_kills"), _progress.value_of("chests")]


# Pushes stat/trait bonuses into the player and the callsign into NPC greetings.
func _apply_progress() -> void:
	_player.set_progress_bonuses(_progress.bonus("damage_pct"), _progress.bonus("speed_pct"), _progress.bonus("max_hp_pct"))
	NpcChatter.player_name = _progress.callsign if _progress.callsign != "" else _profile_name


# Awards XP for an event and bumps achievement counters; shows level-up and achievement notices (and saves when something was earned).
func _award(kind: String, counter_names: Array) -> void:
	var levels: int = _progress.add_xp(_progress.xp_reward(kind))
	for counter_name: String in counter_names:
		_progress.count(counter_name, 1)
	_progress_notices(levels)


func _progress_notices(levels: int) -> void:
	var parts: Array[String] = []
	if levels > 0:
		parts.append("LEVEL UP! Level %d (press P for your card)" % _progress.level())
	for id: String in _progress.take_unlocked():
		parts.append("ACHIEVEMENT: %s" % String((_progress.achievement_defs()[id] as Dictionary)["name"]))
	if not parts.is_empty():
		_player_hud.notice("  |  ".join(parts))
		_apply_progress()
		save_profile()
		card_changed.emit(_progress.to_dict())


func _open_customizer() -> void:
	_customizer.open(_player.appearance)
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_customizer() -> void:
	_customizer.visible = false
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_look_applied(look: Dictionary) -> void:
	_player.set_appearance(look)
	save_profile()
	look_changed.emit(_player.appearance)
	_close_customizer()


func _toggle_inventory() -> void:
	if _inventory_screen.visible:
		_inventory_screen.close()
		_player.controls_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_inventory_screen.selected_hotbar = _player.hotbar_index()
		_inventory_screen.open()
		_player.controls_enabled = false


func _on_inventory_changed() -> void:
	_player.refresh_held()
	_player.refresh_equipment()
	_inventory_screen.selected_hotbar = _player.hotbar_index()
	save_profile()


func local_player() -> Player:
	return _player


func progress() -> ProgressState:
	return _progress


func wallet() -> Wallet:
	return _wallet


# The fantasy world while the player is in it, else null (commands that belong to it only work inside).
func fantasy() -> Node3D:
	return _fantasy if _in_fantasy else null


# --- chat and commands ---

# Runs a line as if it had been typed into the chat (also used by tools/dev_boot.gd).
func run_chat(text: String) -> void:
	_on_chat_submitted(text)


func _on_chat_closed() -> void:
	_chat_closed_at = _time
	_player.controls_enabled = not _inventory_screen.visible


func _on_chat_submitted(text: String) -> void:
	if ChatCommand.parse(text).is_empty():
		if net != null and net.is_active():
			net.chat.say(text)
		else:
			_chat.add_line("%s: %s" % [_profile_name if _profile_name != "" else "You", ChatCommand.clean(text)])
		return
	_chat.add_line(ChatCommand.clean(text), Color(0.7, 0.7, 0.7))
	if not settings.dev_commands:
		_chat.add_line("Commands are switched off (setting dev_commands).", Color(1.0, 0.6, 0.5))
		return
	var scope := _commands.scope_of(text)
	var online: bool = net != null and net.can_send()
	var parsed := ChatCommand.parse(text)
	if scope == "host":
		var who := " ".join(PackedStringArray(parsed["args"]))
		_chat.add_line(net.chat.set_op(who, String(parsed["name"]) == "op") if online else "You are not hosting a session.", Color(0.75, 0.9, 1.0))
	elif online and not net.is_host() and not net.chat.allowed:
		_chat.add_line("The host has not allowed you to use commands (/op).", Color(1.0, 0.6, 0.5))
	elif online and not net.is_host() and scope == "world":
		net.chat.send_command(text)
	else:
		for answer in _commands.run(text, _player):
			_chat.add_line(answer, Color(0.75, 0.9, 1.0))


# Host: a client who is an operator sent a command that changes the shared world.
func _run_world_command(peer: int, text: String) -> PackedStringArray:
	if _commands.scope_of(text) != "world":
		return PackedStringArray(["That command runs on your own machine."])
	var body: Node3D = net.player_node(peer)
	return _commands.run(text, body if body != null else _player)


# After a command changed the inventory or the level: rebuild what depends on them and save.
func refresh_after_command() -> void:
	_on_inventory_changed()
	_apply_progress()
	card_changed.emit(_progress.to_dict())


# Command /tp: leaves whatever painting world the player is in and goes to a named place. Returns what to tell them.
func travel(place: String) -> String:
	if place == "fantasy" or (_fantasy != null and _fantasy.place_names().has(place)):
		if _in_omaha:
			_leave_omaha()
		elif _in_arena:
			_leave_arena()
		if not _in_fantasy:
			_enter_fantasy()
		return "Moved to Aurelind." if place == "fantasy" else _fantasy.travel(place)
	if place in ["island", "club", "arena", "omaha"]:
		if _in_omaha:
			_leave_omaha()
		elif _in_arena:
			_leave_arena()
		elif _in_fantasy:
			_leave_fantasy()
	match place:
		"island":
			_player.teleport(_island_spawn, 0.0)
		"club":
			_player.teleport(_club_spawn, 0.0)
		"arena":
			_enter_arena()
		"omaha":
			_enter_omaha()
		_:
			return "Unknown place %s. Places: island, club, arena, omaha, fantasy (inside it also: %s)." % [place, ", ".join(_fantasy.place_names()) if _fantasy != null else "its regions and towns"]
	return "Moved to %s." % place


func director() -> Node3D:
	return _director


# Restores the signed profile if there is a valid one; a modified or damaged file is ignored.
func _load_profile() -> void:
	_save_key = player_name.strip_edges().substr(0, 20)
	var saved := ProfileIO.load_profile(_save_key)
	if saved.is_empty():
		_profile_name = ProfileIO.current(player_name)["name"]
		if ProfileIO.last_problem != "":
			_player_hud.notice("Your save file was modified or damaged, so it was ignored.")
	else:
		_profile_name = String(saved["name"])
		_player.inventory.from_dict(saved["inv"])
		_player.set_appearance(saved["look"])
		var extra: Dictionary = saved["extra"]
		if extra.has("coins"):
			_wallet.balance = maxi(int(extra["coins"]), 0)
			_jackpot = float(extra.get("jackpot", _jackpot))
		_progress.from_dict(extra.get("progress", {}))
		_fantasy_saved = extra.get("fantasy")
	if player_name != "":
		_profile_name = player_name.strip_edges().substr(0, 20)
	_apply_progress()
	_apply_name_loadout()
	_player.refresh_equipment()
	_player.refresh_held()
	_inventory_screen.selected_hotbar = _player.hotbar_index()


# Easter egg: some names start with extra items (data/player.json "name_loadouts"). Anyone can type the name, so these are not secret or cheat-proof.
func _apply_name_loadout() -> void:
	var loadouts: Dictionary = DataStore.load_json("res://data/player.json").get("name_loadouts", {})
	var key := _profile_name.strip_edges().to_lower()
	if not loadouts.has(key):
		return
	var loadout: Dictionary = loadouts[key]
	for entry in loadout.get("items", []):
		if _player.inventory.count_of(String(entry[0])) == 0:
			_player.inventory.add(String(entry[0]), int(entry[1]))
	var worn: Dictionary = loadout.get("equip", {})
	for slot in worn:
		var id := String(worn[slot])
		if _player.items.has_item(id) and _player.items.equip_slot(id) == slot and _player.inventory.equipment[slot].is_empty():
			_player.inventory.equipment[slot] = {"id": id, "count": 1}


func save_profile() -> void:
	if no_save:
		return
	if _player != null and _profile_name != "":
		var extra := {"coins": _wallet.balance, "jackpot": _jackpot, "progress": _progress.to_dict()}
		if _fantasy != null:
			extra["fantasy"] = _fantasy.to_dict()
		elif _fantasy_saved != null:
			extra["fantasy"] = _fantasy_saved  # never entered this session: keep what was saved
		ProfileIO.save(_profile_name, _player.inventory.to_dict(), _player.appearance, _save_key, extra)


func _exit_tree() -> void:
	save_profile()


func _inventory_screen_layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.add_child(_inventory_screen)
	return layer


func _near(point: Vector3, range_m: float) -> bool:
	return _player.global_position.distance_to(point) < range_m


func _near_painting() -> bool:
	return not _in_arena and not _in_omaha and not _in_fantasy and _near(_painting, PAINTING_RANGE)


func _near_painting_omaha() -> bool:
	return not _in_arena and not _in_omaha and not _in_fantasy and _near(_painting_omaha, PAINTING_RANGE)


func _near_painting_fantasy() -> bool:
	return not _in_arena and not _in_omaha and not _in_fantasy and _near(_painting_fantasy, PAINTING_RANGE)


func _near_fantasy_exit() -> bool:
	return _in_fantasy and _near(_fantasy_exit, PAINTING_RANGE)


func _near_omaha_exit() -> bool:
	return _in_omaha and _near(_omaha_exit, PAINTING_RANGE)


# Text for the E prompt, or "" when nothing is in reach.
func _prompt() -> String:
	var key := InputSetup.label(settings, "interact")
	if _inventory_screen.visible or _customizer.visible or _card_screen.visible or _slot_screen.visible or _games.is_open() or _flight_t >= 0.0:
		return ""
	if _near(Lifeguard.POS, LIFEGUARD_RANGE):
		return "[%s] Talk to the lifeguard: change your look" % key
	var drop := _field.nearest(_player.global_position)
	if not drop.is_empty():
		return "[%s] Pick up %s" % [key, GunStats.display_name(_player.gun_db, drop["gun"])]
	var vendor := _vendor_near()
	if not vendor.is_empty():
		return "[%s] Buy a %s (%d coins) - a random rolled gun, %s or better" % [key, vendor["name"], int(vendor["price"]), vendor["min_tier"]]
	if _slot_near() != null:
		return "[%s] Play the slot machine (free coins)" % key
	var table := _games.spot_near(_player.global_position)
	if table != "":
		return "[%s] Sit at the %s table (free coins)" % [key, table]
	if _near(_pachinko.console_position(), PACHINKO_RANGE):
		return "[%s] Launch a pachinko ball (%d coins, hold to keep firing): fire when the marker is on the gold line" % [key, _pachinko.ball_cost()]
	var food: String = _crow_cfg["food_item"]
	var needed: int = int(_crow_cfg["worms_needed"])
	if _near(_crow_a_pos, CROW_RANGE):
		if _player.inventory.count_of(food) > 0:
			return "[%s] Feed the crow a %s (%d/%d)" % [key, _player.items.item_name(food), _fed, needed]
		return "The crow wants %s (%d/%d fed)" % [_player.items.item_name(food), _fed, needed]
	if _near(_crow_b_pos, CROW_RANGE):
		return "[%s] Ride the crow home" % key
	if _near_painting():
		return "[%s] Enter the colosseum" % key
	if _near_painting_omaha():
		return "[%s] Enter the wasteland: Omaha, Nebraska" % key
	if _near_omaha_exit() or _near_fantasy_exit():
		return "[%s] Return to the island" % key
	if _near_painting_fantasy():
		return "[%s] Step into the painting: the wheat fields of Aurelind" % key
	if _in_fantasy:
		return _fantasy.prompt(key)
	if _reward != null:
		if not _reward.is_chest_open() and _near(_reward.chest_position(), REWARD_RANGE):
			return "[%s] Open the chest" % key
		if _reward.is_door_ready() and _near(_reward.door_position(), REWARD_RANGE):
			return "[%s] Return to the island" % key
	return ""


func _interact() -> void:
	if _near(Lifeguard.POS, LIFEGUARD_RANGE):
		_open_customizer()
	elif not _field.nearest(_player.global_position).is_empty():
		_pick_up(_field.nearest(_player.global_position))
	elif not _vendor_near().is_empty():
		_buy_crate(_vendor_near())
	elif _slot_near() != null:
		_open_slots(_slot_near())
	elif _games.spot_near(_player.global_position) != "":
		_games.open(_games.spot_near(_player.global_position))
	elif _near(_pachinko.console_position(), PACHINKO_RANGE):
		_launch_pachinko()
	elif _near(_crow_a_pos, CROW_RANGE):
		_feed_crow()
	elif _near(_crow_b_pos, CROW_RANGE):
		_start_flight(_crow_b, _crow_b_pos, _crow_a_pos, _island_spawn)
	elif _near_painting_omaha():
		_enter_omaha()
	elif _near_omaha_exit():
		_leave_omaha()
	elif _near_painting_fantasy():
		_enter_fantasy()
	elif _near_fantasy_exit():
		_leave_fantasy()
	elif _in_fantasy:
		_fantasy.interact()
	elif _near_painting():
		_enter_arena()
	elif _reward != null and not _reward.is_chest_open() and _near(_reward.chest_position(), REWARD_RANGE):
		_open_chest()
	elif _reward != null and _reward.is_door_ready() and _near(_reward.door_position(), REWARD_RANGE):
		_leave_arena()


func _slot_near() -> SlotMachine:
	for m in _slot_machines:
		if _near(m.global_position, SLOT_RANGE):
			return m
	return null


func _update_pots() -> void:
	for m in _slot_machines:
		m.set_pot(_jackpot)


func _open_slots(machine: SlotMachine) -> void:
	_slot_machine = machine
	var refill: Dictionary = _casino_cfg["free_refill"]
	if _wallet.balance < int(refill["below"]):
		_wallet.balance = int(refill["to"])
		_player_hud.notice("The casino tops you up to %d free coins." % _wallet.balance)
	_player.look_at_point(machine.global_position + Vector3(0, 1.5, 0))
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_slot_screen.open(_wallet.balance, _jackpot)


func _close_slots() -> void:
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_slot_machine.set_screen("FREE PLAY  -  press F")
	save_profile()


func _on_slot_spin(bet: int) -> void:
	var cost := _slot_math.cost(bet)
	if _slot_machine.is_busy() or not _wallet.spend(cost):
		return
	var grown := _slot_math.grow_pool(_jackpot, cost)
	var stops := _slot_math.random_stops(_rng)
	_slot_pending = {"result": _slot_math.evaluate(stops, bet, grown), "grown": grown, "bet": bet}
	_jackpot = grown
	_update_pots()
	_slot_screen.set_busy(true)
	_slot_screen.show_state(_wallet.balance, _jackpot, "Spinning...")
	_slot_machine.set_screen("BET %d   spinning..." % cost)
	_slot_machine.spin_to(stops)


func _on_slot_finished() -> void:
	if _slot_pending.is_empty():
		return
	var result: Dictionary = _slot_pending["result"]
	_slot_pending = {}
	var won := int(result["total"])
	var message := "No win this time."
	var big := false
	if won > 0:
		_wallet.add(won)
		message = "You win %d coins!" % won
	if result["jackpot_won"]:
		big = true
		_progress.count("jackpots", 1)
		_progress_notices(0)
		_jackpot = _slot_math.jackpot_seed
		message = "JACKPOT!  +%d coins" % won
		_update_pots()
	if won > 0:
		_slot_machine.flash_win(big)
	_slot_machine.set_screen("WIN %d" % won if won > 0 else "no win")
	_slot_screen.set_busy(false)
	_slot_screen.show_state(_wallet.balance, _jackpot, message)
	save_profile()


# Holding the interact key at the console keeps launching balls (after a short delay, then fast).
func _hold_pachinko(delta: float) -> void:
	var busy: bool = _customizer.visible or _slot_screen.visible or _games.is_open() or _inventory_screen.visible
	if busy or not Input.is_action_pressed("interact") or not _near(_pachinko.console_position(), PACHINKO_RANGE):
		_pachinko_hold = 0.0
		return
	_pachinko_hold += delta
	if _pachinko_hold >= PACHINKO_HOLD_DELAY:
		_pachinko_hold -= PACHINKO_HOLD_EVERY
		_launch_pachinko()


func _launch_pachinko() -> void:
	var cost: int = _pachinko.ball_cost()
	if not _wallet.can_afford(cost):
		var refill: Dictionary = _casino_cfg["free_refill"]
		if _wallet.balance < int(refill["below"]):
			_wallet.balance = int(refill["to"])
			_coins_dirty = true
			_player_hud.notice("The casino tops you up to %d free coins." % _wallet.balance)
		else:
			_player_hud.notice("Not enough coins (a ball costs %d)." % cost)
		return
	if _pachinko.launch():
		_wallet.spend(cost)
		_coins_dirty = true
	else:
		_player_hud.notice("The board is full, wait for balls to land.")


func _on_pachinko_landed(_pocket: int, coins: int, pocket_name: String) -> void:
	if coins > 0:
		_wallet.add(coins)
		_player_hud.notice("%s: +%d coins" % [pocket_name, coins])
	_coins_dirty = true


func _feed_crow() -> void:
	var food: String = _crow_cfg["food_item"]
	if _player.inventory.remove(food, 1) == 0:
		_player_hud.notice("Bring the crow some %s." % _player.items.item_name(food))
		return
	_fed += 1
	_eat_time = 1.2
	_player.refresh_held()
	if _fed >= int(_crow_cfg["worms_needed"]):
		_fed = 0
		_player_hud.notice("The crow gobbles it up and spreads its wings...")
		_start_flight(_crow_a, _crow_a_pos, _crow_b_pos, _club_spawn)
	else:
		_player_hud.notice("The crow gobbles the worm (%d/%d)" % [_fed, int(_crow_cfg["worms_needed"])])


func _start_flight(source: Node3D, from: Vector3, to: Vector3, dest_spawn: Vector3) -> void:
	_flight_t = 0.0
	_flight_from = from
	_flight_to = to
	_flight_dest = dest_spawn
	_flight_src = source
	source.visible = false
	_ride_crow.visible = true
	_ride_crow.position = from
	_player.carried = true
	_player.controls_enabled = false
	_flight_prev_view = _player.third_person
	_player.set_third_person(true)


# Moves the crow along an arc and keeps the rider on its back; lands at the destination spawn.
func _fly(delta: float) -> void:
	_flight_t += delta
	var duration: float = float(_crow_cfg["flight_seconds"])
	var u: float = clampf(_flight_t / duration, 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, u)
	var pos := _flight_from.lerp(_flight_to, e) + Vector3(0, float(_crow_cfg["altitude"]) * sin(PI * e), 0)
	var ahead := _flight_from.lerp(_flight_to, minf(e + 0.02, 1.0)) + Vector3(0, float(_crow_cfg["altitude"]) * sin(PI * minf(e + 0.02, 1.0)), 0)
	_ride_crow.position = pos
	if ahead.distance_to(pos) > 0.01:
		_ride_crow.look_at(ahead, Vector3.UP)
	CrowModel.pose(_ride_crow, CrowModel.FLAP, _flight_t)
	_player.global_position = _ride_crow.to_global(CrowModel.SADDLE)
	if u >= 1.0:
		_ride_crow.visible = false
		_flight_src.visible = true
		_flight_t = -1.0
		_player.carried = false
		_player.controls_enabled = true
		_player.set_third_person(_flight_prev_view)
		_player.teleport(_flight_dest, 0.0)
		_player_hud.play_fade()


# Vendor kiosk within reach: its crate dictionary, or {}.
func _vendor_near() -> Dictionary:
	for v: Node3D in _casino["vendors"]:
		if _near(v.global_position, VENDOR_RANGE):
			return v.crate
	return {}


func _buy_crate(crate: Dictionary) -> void:
	var price := int(crate["price"])
	if not _wallet.can_afford(price):
		_player_hud.notice("A %s costs %d coins (you have %d)." % [crate["name"], price, _wallet.balance])
		return
	var gun := GunGen.generate(_player.gun_db, _rng, float(crate["luck"]) * _luck_mult(), "", "", String(crate["min_tier"]))
	if not _player.inventory.add_gun(gun):
		_player_hud.notice("Inventory full: make room first.")
		return
	_wallet.spend(price)
	_player.refresh_held()
	_progress.count("vendor_buys", 1)
	_progress_notices(0)
	save_profile()
	_player_hud.notice("%s: %s" % [crate["name"], GunStats.display_name(_player.gun_db, gun)])


func _pick_up(drop: Dictionary) -> void:
	if _player.inventory.add_gun(drop["gun"]):
		var gun: Dictionary = _field.take(drop)
		_player.refresh_held()
		save_profile()
		_player_hud.notice("Picked up %s" % GunStats.display_name(_player.gun_db, gun))
	else:
		_player_hud.notice("Inventory full: make room first.")


# An enemy died: roll its gun drops (wave luck, elite and boss floors) and drop them where it fell.
func _on_enemy_killed(where: Vector3, enemy_id: String, elite: String, wave: int) -> void:
	_player.on_enemy_killed(elite, enemy_id)
	var kill_counters: Array = ["kills"]
	var xp_kind := "kill"
	if elite != "":
		kill_counters.append("elite_kills")
		xp_kind = "elite"
	if enemy_id == "boss" or enemy_id.begins_with("boss_"):
		kill_counters.append("boss_kills")
		xp_kind = "boss"
	var guns: Array = [] if _in_fantasy else DropRules.roll_drops(_player.gun_db, _drops_cfg, _rng, enemy_id, elite != "", wave, _luck_mult())  # the fantasy world has its own drops
	for i in guns.size():
		var gun: Dictionary = guns[i]
		_field.spawn(gun, where + Vector3(0.6 * float(i), 0.0, 0.0))
		var tier := String(gun["tier"])
		if tier == "rainbow" or tier == "pony":
			_player_hud.notice("%s DROP!" % String(_player.gun_db.tier(tier)["name"]).to_upper())
			kill_counters.append("rare_drops")
	_award(xp_kind, kill_counters)


# Gun luck multiplier from Fortune points and the Lucky Find trait.
func _luck_mult() -> float:
	return 1.0 + _progress.bonus("luck_pct") / 100.0


func _open_chest() -> void:
	_reward.open_chest()
	_award("chest", ["chests"])
	var found: Array[String] = []
	var lost := false
	for drop in LootRoll.roll(_loot_tables["arena_chest"], _rng):
		var left: int = _player.inventory.add(drop["id"], drop["count"])
		lost = lost or left > 0
		found.append("%s x%d" % [_player.items.item_name(drop["id"]), drop["count"] - left])
	var chest: Dictionary = DataStore.load_json("res://data/gun_loot.json")["chest"]
	for n in int(chest["guns"]):
		var gun := GunGen.generate(_player.gun_db, _rng, float(chest["luck"]) * _luck_mult(), "", "", String(chest["min_tier"]) if n == 0 else "")
		if _player.inventory.add_gun(gun):
			found.append(GunStats.display_name(_player.gun_db, gun))
		else:
			lost = true
	_player.refresh_held()
	save_profile()
	_player_hud.notice("Found: " + ", ".join(found) + ("  (inventory full, some was left behind)" if lost else ""))


# Dying sends you back to the island and your arena run starts over.
func _enter_arena() -> void:
	_in_arena = true
	_player.teleport(ARENA_SPAWN, 0.0)
	_director.start()
	_player_hud.play_fade()


func _on_player_died() -> void:
	_progress.count("deaths", 1)
	_progress_notices(0)
	if _in_arena:
		_leave_arena()
	elif _in_omaha:
		_player.teleport(_omaha.spawn_world(), 0.0)  # you wake up back at the Old Market haven
		_player_hud.play_fade()
	elif _in_fantasy:
		_player.teleport(_fantasy.haven_world(), 0.0)  # you wake up in the nearest town
		_fantasy.enter(_player.global_position)
		_player_hud.play_fade()
	else:
		_player.teleport(_island_spawn, 0.0)


# The second painting: a streamed wasteland Omaha (game/omaha_world.gd) with district enemies and bosses (game/omaha_spawner.gd).
func _enter_omaha() -> void:
	if _omaha == null:
		_omaha = OmahaWorld.new()
		add_child(_omaha)
		_omaha.setup(_player)
		_spawner = OmahaSpawner.new()
		add_child(_spawner)
		_spawner.setup(_director, _player, _omaha, _drops_cfg)
		_spawner.notice.connect(_player_hud.notice)
		_omaha_exit = _omaha.spawn_world() + Vector3(3.0, 0.0, 0.0)
		Island.build_painting(self, _omaha_exit, PaintingArt.island_texture())
	var spawn := _omaha.spawn_world()
	_omaha.load_around(spawn)
	_in_omaha = true
	_player.teleport(spawn, 0.0)
	_wasteland_env(true)
	_spawner.start()
	_player_hud.play_fade()


# The third painting: the fantasy world Aurelind (game/fantasy_world.gd), a streamed open land with its own magic,
# skills and quests.
func _enter_fantasy() -> void:
	_build_fantasy()
	_in_fantasy = true
	_player.teleport(_fantasy.spawn_world(), 0.0)
	_player.look_at_point(_fantasy.farm_world() + Vector3(0.0, 3.0, 0.0))  # you arrive facing the farmhouse
	apply_settings()  # switches to the painted look and loads the land around the player
	_player_hud.play_fade()


# Builds the fantasy world once. Online this happens as soon as the session starts, because the host runs its
# creatures and keeps the party's quests even while standing somewhere else.
func _build_fantasy() -> void:
	if _fantasy != null:
		return
	_fantasy = FantasyWorld.new()
	add_child(_fantasy)
	_fantasy.setup(_player, _director, _render_style, _hud_layer, _numbers, settings)
	_fantasy.from_dict(_fantasy_saved)
	_fantasy.notice.connect(_player_hud.notice)
	_fantasy.fade.connect(_player_hud.play_fade)
	_fantasy.said.connect(func(text: String, color: Color) -> void: _chat.add_line(text, color))
	_fantasy.changed.connect(func() -> void: _fantasy_dirty = true)
	_fantasy_exit = _fantasy.exit_world()
	Island.build_painting(self, _fantasy_exit, PaintingArt.island_texture())
	if net != null and net.is_active():
		net.fantasy.bind(_fantasy, _director)


func _leave_fantasy() -> void:
	_fantasy.leave()
	_director.reset()
	_in_fantasy = false
	apply_settings()
	save_profile()
	_player.teleport(_island_spawn, 0.0)
	_player_hud.play_fade()


# How much of the land is kept around the player, by graphics tier (data/graphics.json "fantasy").
func _fantasy_detail() -> void:
	var tier: Dictionary = RenderStyle.presets()["graphics"][0]
	for entry: Dictionary in RenderStyle.presets()["graphics"]:
		if String(entry["id"]) == settings.graphics:
			tier = entry
	var detail: Dictionary = tier.get("fantasy", {})
	_fantasy.set_detail(detail)


func _leave_omaha() -> void:
	_spawner.stop()
	_director.reset()
	_field.clear()
	_in_omaha = false
	_wasteland_env(false)
	_player.teleport(_island_spawn, 0.0)
	_player_hud.play_fade()


# Dusty orange haze while in Omaha; the saved values come back when leaving.
func _wasteland_env(on: bool) -> void:
	var env := _render_style.env
	if on:
		_env_saved = {"fog": env.fog_enabled, "density": env.fog_density, "color": env.fog_light_color, "ambient": env.ambient_light_color}
		env.fog_enabled = true
		env.fog_density = OMAHA_FOG
		env.fog_light_color = Color(0.74, 0.60, 0.44)
		env.ambient_light_color = Color(0.62, 0.55, 0.48)
	elif not _env_saved.is_empty():
		env.fog_enabled = _env_saved["fog"]
		env.fog_density = _env_saved["density"]
		env.fog_light_color = _env_saved["color"]
		env.ambient_light_color = _env_saved["ambient"]


func _leave_arena() -> void:
	_field.clear()
	if _reward != null:
		_reward.queue_free()
	_reward = null
	_in_arena = false
	_director.reset()
	_player.teleport(_island_spawn, 0.0)
	_player_hud.play_fade()


func _process(delta: float) -> void:
	_time += delta
	if _flight_t >= 0.0:
		_fly(delta)
	if _eat_time > 0.0:
		_eat_time -= delta
		CrowModel.pose(_crow_a, CrowModel.EAT, _time)
	else:
		CrowModel.pose(_crow_a, CrowModel.IDLE, _time)
	CrowModel.pose(_crow_b, CrowModel.IDLE, _time + 1.7)
	_hold_pachinko(delta)
	if _fantasy_dirty and _time - _fantasy_saved_at > 20.0:
		_fantasy_dirty = false
		_fantasy_saved_at = _time
		save_profile()
	_player_hud.prompt_text = _prompt()
	_player_hud.coins = _wallet.balance if _near(_pachinko.global_position, 30.0) else -1
	if _coins_dirty and _pachinko.balls_in_play() == 0:
		_coins_dirty = false
		save_profile()
	if _in_arena and _reward == null and _director.is_cleared():
		_reward = RewardArea.new()
		add_child(_reward)
		_reset_left = _director.reset_delay()
		_player_hud.notice("Arena resets to round 1 in %d s" % int(_reset_left))
	elif _in_arena and _reward != null:
		_reset_left -= delta
		if _reset_left <= 0.0:
			_reward.queue_free()
			_reward = null
			_director.reset()
			_director.start()
			_player_hud.notice("Round 1")
	var scope: float = _player.scope_amount()
	_scope.amount = scope
	_cross.visible = scope < ScopeOverlay.SHOW_FROM
	if settings.show_debug:
		_overlay.push_frame(delta)
	_hud_timer += delta
	if _hud_timer < HUD_REFRESH:
		return
	_hud_timer = 0.0
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_hud.text = "fps %d  frame %.1f ms  draws %d  mem %.0f MB\n%s move, %s jump, %s sprint, %s shoot, %s reload, %s aim, %s-%s hotbar, %s inventory, %s view, Esc menu" % [
		fps, 1000.0 / maxf(fps, 1.0), draws, mem_mb, _moves(), _key("jump"), _key("sprint"), _key("shoot"),
		_key("reload"), _key("aim"), _key("weapon_1"), _key("weapon_9"), _key("inventory"), _key("toggle_view")]
	_player_hud.wave_text = _director.status_text()
	_player_hud.boss_ratio = _director.boss_ratio()
	_player_hud.level = _progress.level()
	_player_hud.xp_ratio = 1.0 if _progress.xp_for_level() == 0 else float(_progress.xp_into_level()) / float(_progress.xp_for_level())
	if settings.show_debug:
		_overlay.fps = fps
		_overlay.draws = draws
		_overlay.mem_mb = mem_mb
		_overlay.process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_overlay.physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_overlay.nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		_overlay.enemies = _director.enemy_count()
		_overlay.projectiles = _director.projectile_count()
		_overlay.on_floor = _player.is_on_floor()


func _key(action: String) -> String:
	return InputSetup.label(settings, action)


func _moves() -> String:
	return _key("move_forward") + _key("move_left") + _key("move_back") + _key("move_right")


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = false
	add_child(sun)
	_render_style.env = env
	_render_style.sun = sun
	add_child(_render_style)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud_layer = layer
	layer.add_child(_bars)
	layer.add_child(_scope)
	layer.add_child(_player_hud)
	_hud.position = Vector2(12, 8)
	layer.add_child(_hud)
	_cross.text = "+"
	_cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(_cross)
	layer.add_child(_overlay)
	layer.add_child(_chat)
	add_child(layer)
