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
const LoadClock = preload("res://game/load_clock.gd")
const PlayerHud = preload("res://game/player_hud.gd")
const EnemyBars = preload("res://game/enemy_bars.gd")
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
const TradeScreen = preload("res://game/trade_screen.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ScoreCard = preload("res://core/score_card.gd")
const KnifeModels = preload("res://game/knife_models.gd")
const IslandRounds = preload("res://game/island_rounds.gd")
const DroppedPack = preload("res://game/dropped_pack.gd")
const GameOverScreen = preload("res://game/game_over_screen.gd")
const BankState = preload("res://core/bank_state.gd")
const BankBox = preload("res://game/bank_box.gd")
const ISLAND_REACH := 60.0  # metres from the island's middle that still count as being on it
const Scoreboard = preload("res://game/scoreboard.gd")

const HUD_REFRESH := 0.25
const ARENA_SPAWN := Vector3(0, 0.1, 10)
const PAINTING_RANGE := 4.5
const REWARD_RANGE := 3.0
const CROW_RANGE := 6.0
const LIFEGUARD_RANGE := 3.2
const PACHINKO_RANGE := 2.8
const PACHINKO_HOLD_DELAY := 0.4
const PACHINKO_HOLD_EVERY := 0.15
const SLOT_RANGE := 2.0
const TRADE_RANGE := 4.0  # metres: look at a player this near and hold the interact key to ask for a trade
const TRADE_HOLD := 0.6  # seconds the key must be held
const CLUB_NEAR := 300.0  # metres from the club's middle within which its inside is built and runs

signal look_changed(look: Dictionary)
signal table_event(op: String, args: Array)  # our blackjack table actions, sent to other players so they can watch
signal card_changed(progress: Dictionary)  # level, achievements or card edited: main.gd sends it to the other players

var settings: SettingsState  # set before add_child
var net: Node3D  # game/net_session.gd, set before add_child (idle when playing alone)
var loading: Control  # game/loading_screen.gd, set before add_child (may be null in test scenes)
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
var _painting_fantasy := Vector3.ZERO
var _in_fantasy := false
var _fantasy: FantasyWorld  # built the first time the player enters (or from the save)
var _fantasy_saved: Variant  # the fantasy part of the profile, until that world is built
var _fantasy_exit := Vector3.ZERO
var _fantasy_dirty := false  # something changed in there: saved at most every 20 s
var _fantasy_saved_at := 0.0
var _hud_layer: CanvasLayer
var _in_arena := false
var _island_spawn := Vector3.ZERO
var _reward: RewardArea
var _customizer := CustomizeMenu.new()
var _progress := ProgressState.new(DataStore.load_json("res://data/progression.json"), DataStore.load_json("res://data/achievements.json"))  # level, stats, traits, achievements, card (saved in the profile)
var _card_screen := CardScreen.new()
var _render_style := RenderStyle.new()
var _wallet := Wallet.new()  # casino coins (saved in the profile)
var _points_cfg: Dictionary = DataStore.load_json("res://data/points.json")
var _score := ScoreCard.new(_points_cfg)  # zombies-style points (saved in the profile) and this session's scoreboard row
var _scoreboard := Scoreboard.new()
var _knife_rolled := false  # this character has its knife type
var _rounds := IslandRounds.new()  # the island's endless rounds (run here when alone or hosting)
var _first_look := false  # a new character is still in its first customize menu: the rounds wait
var _hurt_at := 0.0  # when the local player was last hurt (the island heals whoever is left alone for a while)
var _pack: DroppedPack  # our backpack lying where we went down on the islands (null = none); saved with the character
var _game_over := GameOverScreen.new()
var _best_round := 0  # the furthest this character ever got on the islands (saved)
var _bank_cfg: Dictionary = DataStore.load_json("res://data/bank.json")
var _bank := BankState.new(_bank_cfg)  # slots on the spawn island that are safe when we go down (saved)
var _bank_pos := Vector3.ZERO
var _run_kills := 0  # the score card's kills when this run began ...
var _run_earned := 0  # ... and the points earned since
var _down_until := 0.0  # online, lying down: when we bleed out
var _out := false  # online: bled out, waiting at the spawn for the next round
var _revive_target := 0  # online: the downed player we stand next to (0 = nobody)
var _revive_hold := 0.0  # ... and for how long we have held the key
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
var _trade_screen := TradeScreen.new()  # online: the trade window (game/net_trade.gd tells it what to show)
var _trade_asker := ""  # somebody asked us to trade: their name ...
var _trade_ask_until := 0.0  # ... until this _time
var _trade_hold := 0.0  # how long the interact key has been held on a player
var _slot_machines: Array = []
var _slot_machine: SlotMachine
var _slot_pending: Dictionary = {}
var _games := CasinoGames.new()
var _reset_left := 0.0  # seconds until a cleared arena starts over at round 1
var _numbers := DamageNumbers.new()
var _explosives := Explosives.new()
var _sounds: Node3D = preload("res://game/fantasy_sounds.gd").new()  # guns, explosions and enemy attacks (data/sounds.json)
var _skill_fx := SkillEffects.new()
var _inventory_screen := InventoryScreen.new()
var _rng := RandomNumberGenerator.new()
var _loot_tables: Dictionary
var _crow_a: Node3D  # home-island crow (feed it worms to fly to the club island)
var _crow_b: Node3D  # club-island crow (flies you home for free)
var _ride_crow: Node3D  # the crow that actually flies
var _gun_side: Array[Node] = []  # the colosseum, the island, the club's shell, the crows and the lifeguard (see _rest_worlds)
var _club_parts: Array[Node] = []  # the club's inside and the casino, built on the first trip there (_build_club)
var _custom_layer: CanvasLayer  # the overlays' layer (the table games add theirs when the club is built)
var _fantasy_left_at := -1000.0  # _time when the player last left Aurelind: it sleeps a little later, once its sounds have faded
var _rest_in := 0.0  # seconds until _rest_worlds looks again
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
	LoadClock.mark("session created")
	_build_environment()
	LoadClock.mark("sky and light")
	var first_gun_side := get_child_count()
	var gates := Colosseum.build(self)
	LoadClock.mark("colosseum")
	var island := Island.build(self)
	LoadClock.mark("island")
	_painting = island["painting"]
	_painting_fantasy = island["painting_fantasy"]
	_island_spawn = island["spawn"]
	_loot_tables = DataStore.load_json("res://data/loot_tables.json")["tables"]
	_rng.randomize()
	ClubIsland.build_shell(self)  # only what is seen from afar; the inside and the casino wait for the first trip (_build_club)
	LoadClock.mark("club island shell")
	_club_spawn = ClubIsland.SPAWN
	_casino_cfg = DataStore.load_json("res://data/casino.json")
	_wallet = Wallet.new(int(_casino_cfg["starting_coins"]))
	_slot_data = DataStore.load_json("res://data/slots.json")
	_slot_math = SlotMath.new(_slot_data)
	_jackpot = _slot_math.jackpot_seed
	_crow_a_pos = Island.CROW_POS
	_crow_b_pos = ClubIsland.CROW_POS
	_crow_cfg = DataStore.load_json("res://data/crow.json")
	_crow_a = _place_crow(_crow_a_pos, island["spawn"])
	_crow_b = _place_crow(_crow_b_pos, _club_spawn)
	var lifeguard := Lifeguard.new()
	lifeguard.position = Lifeguard.POS
	add_child(lifeguard)
	lifeguard.look_at(Lifeguard.POS + (Lifeguard.POS - Island.CENTER), Vector3.UP)
	var bank_box := BankBox.new()
	_bank_pos = Island.CENTER + Vector3(float(_bank_cfg["place"][0]), 0.0, float(_bank_cfg["place"][1]))
	bank_box.position = _bank_pos
	add_child(bank_box)
	bank_box.look_at(Vector3(Island.CENTER.x, 0.0, Island.CENTER.z) + (bank_box.position - Island.CENTER) * 2.0, Vector3.UP)  # its slot faces the middle of the island
	for index in range(first_gun_side, get_child_count()):
		_gun_side.append(get_child(index))
	_ride_crow = CrowModel.build()
	_ride_crow.visible = false
	add_child(_ride_crow)
	add_child(_numbers)
	add_child(_explosives)
	_sounds.set("folder", "res://assets/audio/game/")
	add_child(_sounds)
	_sounds.call("setup", DataStore.load_json("res://data/sounds.json"))
	_explosives.sounds = _sounds
	add_child(_skill_fx)
	LoadClock.mark("crows, lifeguard, effects")
	_build_hud()
	LoadClock.mark("hud")

	_player = Player.new()
	_player.settings = settings
	_player.position = island["spawn"]
	add_child(_player)
	LoadClock.mark("player (body, guns)")
	_player.damaged.connect(_player_hud.flash)
	_player.died.connect(_on_player_died)
	_player.blocked.connect(_player_hud.notice.bind("Blocked!"))
	_player.damage_numbers = _numbers
	_player.explosives = _explosives
	_player.sounds = _sounds
	_player.skill_fx = _skill_fx
	_skill_fx.explosives = _explosives
	_skill_fx.numbers = _numbers
	_skill_fx.follow = _player
	_explosives.numbers = _numbers
	_explosives.ignore = _player.get_rid()
	_explosives.score = _score
	_player.score = _score
	_player.head_share = float(_points_cfg["headshot"]["head_share"])
	_player.head_mult = float(_points_cfg["headshot"]["damage_mult"])
	_player_hud.player = _player
	_player_hud.watch(_score)
	_scoreboard.card = _score
	_scoreboard.others = func() -> Array: return _player_hud.party
	_inventory_screen.inventory = _player.inventory
	_inventory_screen.items = _player.items
	_inventory_screen.gun_db = _player.gun_db
	_inventory_screen.changed.connect(_on_inventory_changed)
	_inventory_screen.dropped.connect(_on_gun_dropped)
	_inventory_screen.bank_upgrade.connect(_on_bank_upgrade)
	add_child(_inventory_screen_layer())
	_customizer.applied.connect(_on_look_applied)
	_customizer.cancelled.connect(_close_customizer)
	var custom_layer := CanvasLayer.new()
	_custom_layer = custom_layer
	custom_layer.layer = 6
	custom_layer.add_child(_customizer)
	_card_screen.progress = _progress
	_card_screen.changed.connect(_on_card_changed)
	_card_screen.closed.connect(_on_card_closed)
	custom_layer.add_child(_card_screen)
	custom_layer.add_child(_slot_screen)
	custom_layer.add_child(_trade_screen)
	_trade_screen.setup(_player.inventory, _player.items, _player.gun_db)
	_slot_screen.setup(_slot_data)
	_slot_screen.spin_requested.connect(_on_slot_spin)
	_slot_screen.closed.connect(_close_slots)
	_games.round_finished.connect(save_profile)
	_games.left.connect(save_profile)
	add_child(_games)
	add_child(custom_layer)
	_load_profile()
	_update_pots()

	_director = WaveDirector.new()
	_director.sounds = _sounds
	_director.setup(_player, gates)
	add_child(_director)
	_bars.source = _director
	_drops_cfg = DataStore.load_json("res://data/drops.json")
	_field.setup(_player.gun_db, _drops_cfg)
	add_child(_field)
	_director.killed.connect(_on_enemy_killed)
	_rounds.director = _director
	_rounds.bodies = _island_bodies
	_rounds.rules.alive_cap = int((_rounds.config()["alive_cap"] as Dictionary).get(settings.graphics, 24))
	_rounds.round_started.connect(_on_round_started)
	_rounds.round_ended.connect(_on_round_ended)
	add_child(_rounds)
	_player.damaged.connect(func() -> void: _hurt_at = _time)
	_score.earned.connect(func(amount: int) -> void: _run_earned += amount)
	_explosives.cripple = _rounds.config()["cripple"]
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
		net.trade.desk.legal = _legal_thing
		net.trade.message.connect(_on_trade_message)
		_trade_screen.offered.connect(net.trade.offer)
		_trade_screen.withdrawn.connect(net.trade.withdraw)
		_trade_screen.ready_set.connect(net.trade.set_ready)
		_trade_screen.confirmed.connect(net.trade.confirm)
		_trade_screen.cancelled.connect(net.trade.cancel)
		_trade_screen.cancelled.connect(_close_trade)  # at once, also when the host's desk is gone (it left, or a new host took over)
		net.drops.legal = _legal_gun
		net.drops.spawned.connect(_on_shared_drop)
		net.drops.removed.connect(_field.remove_shared)
		net.drops.granted.connect(_on_drop_granted)
		net.drops.refused.connect(_on_drop_refused)
		net.scores.card = _score
		net.rounds.bind(_rounds, _director, _score)
		net.rounds.on_gun_side = func() -> bool: return not _in_fantasy
		net.rounds.round_started.connect(_on_round_started)  # as a client: the host's rounds
		net.rounds.round_ended.connect(_on_round_ended)
		var downs: Dictionary = _rounds.config()["downs"]
		net.downs.reach = float(downs["reach"])
		net.downs.health_share = float(downs["health"])
		net.downs.on_island = _on_island
		net.downs.round_now = func() -> int: return _rounds.rules.number
		net.downs.revived.connect(_on_revived)
		net.downs.gave_revive.connect(_on_gave_revive)
		net.downs.party_over.connect(_on_party_over)
		net.downs.states_changed.connect(_show_downs)
		_player.down_check = _goes_down
		_player.went_down.connect(_on_went_down)
		if net.is_active():
			_build_fantasy()
	apply_settings()


func apply_settings() -> void:
	_player.apply_settings()
	_render_style.apply(settings.graphics, settings.shaders, settings.picks)
	if _in_fantasy:
		_fantasy_detail()
		_fantasy.enter(_player.global_position)
	_overlay.visible = settings.show_debug
	_player_hud.show_speed = settings.show_debug


func _place_crow(at: Vector3, facing: Vector3) -> Node3D:
	var crow := CrowModel.build()
	add_child(crow)
	crow.position = at
	crow.look_at(Vector3(facing.x, at.y, facing.z), Vector3.UP)
	return crow


func _unhandled_input(event: InputEvent) -> void:
	if _customizer.visible or _slot_screen.visible or _games.is_open() or _card_screen.visible or _trade_screen.visible or (_fantasy != null and _fantasy.panel_open()):
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
	if _trade_screen.visible:  # Esc = cancel the trade
		net.trade.cancel()
		_close_trade()
		return true
	if not _inventory_screen.visible:
		return false
	_toggle_inventory()
	return true


# Another player's blackjack table action: shown on our table unless we are playing a table game ourselves.
func apply_table_event(_peer: int, op: String, args: Array) -> void:
	if _casino.is_empty() or _games.is_open():
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


# A character's first session starts in the customize menu (game/main.gd, after the loading picture).
func customize_now() -> void:
	_first_look = true
	_open_customizer()


func _close_customizer() -> void:
	_first_look = false
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
		_inventory_screen.in_hand = _player.hand_index()
		_inventory_screen.knife_name = KnifeModels.db().name_of(_player.knife)
		_inventory_screen.knife_key = InputSetup.label(settings, "knife")
		_inventory_screen.gun_keys.clear()
		for n in InventoryState.HOLSTERS:
			_inventory_screen.gun_keys.append(InputSetup.label(settings, "weapon_%d" % (n + 1)))
		_inventory_screen.open()
		_player.controls_enabled = false


# The bank: the inventory window with the bank's slots beside the bag (core/bank_state.gd).
func _open_bank() -> void:
	if _inventory_screen.visible:
		return
	_inventory_screen.bank = _bank
	_inventory_screen.bank_price = _bank_price()
	_toggle_inventory()


func _bank_price() -> String:
	var cost: Dictionary = _bank.next_upgrade()
	if cost.is_empty():
		return ""
	var slots := int(_bank_cfg["per_upgrade"])
	return "%d more slots: %d points (you have %d)" % [slots, int(cost["points"]), _score.points] if cost.has("points") else "%d more slots: %d casino coins (you have %d)" % [slots, int(cost["coins"]), _wallet.balance]


# The bank's upgrade button: the first upgrades cost points, the later ones casino coins.
func _on_bank_upgrade() -> void:
	var cost: Dictionary = _bank.next_upgrade()
	if cost.is_empty():
		return
	var paid: bool = _score.spend(int(cost["points"])) if cost.has("points") else _wallet.spend(int(cost["coins"]))
	if not paid:
		_player_hud.notice("Not enough %s for more bank slots." % ("points" if cost.has("points") else "casino coins"))
		return
	_bank.upgrade()
	_inventory_screen.bank_price = _bank_price()
	_player_hud.notice("The bank now has %d slots." % _bank.capacity())
	save_profile()


# A gun thrown out of the inventory lies on the ground a step ahead until somebody picks it up or the area is left.
func _on_gun_dropped(gun: Dictionary) -> void:
	var ahead := -_player.global_transform.basis.z
	ahead.y = 0.0
	var at := _player.global_position + ahead.normalized() * 1.6
	if net != null and net.can_send():
		net.drops.drop(gun, at)  # online a dropped gun is for everyone: the host lays it down (_on_shared_drop)
	else:
		_field.spawn(gun, at)
	_player_hud.notice("Dropped %s" % GunStats.display_name(_player.gun_db, gun))


# --- online: guns players drop for each other (game/net_drops.gd) and trading (game/net_trade.gd) ---

func _on_shared_drop(id: int, gun: Dictionary, pos: Vector3) -> void:
	if not _field.has_shared(id) and _legal_gun(gun):  # a gun this machine cannot build is not shown
		_field.spawn(gun, pos, id)


func _on_drop_granted(gun: Dictionary) -> void:
	if _player.inventory.add_gun(gun):
		_player.refresh_held()
		save_profile()
		_player_hud.notice("Picked up %s" % GunStats.display_name(_player.gun_db, gun))
	else:
		_on_gun_dropped(gun)  # the bag filled up meanwhile: it goes back on the ground


func _on_drop_refused(gun: Dictionary) -> void:
	_player.inventory.add_gun(gun)
	_on_inventory_changed()
	_player_hud.notice("That gun cannot be dropped here.")


# Host: may this gun be laid down or traded? A legal roll of the game's own data, nothing a client made up.
func _legal_gun(gun: Dictionary) -> bool:
	return GunGen.validate(_player.gun_db, gun) == ""


# Host: guns and armour only (director, round 5).
func _legal_thing(thing: Dictionary) -> bool:
	if thing.has("gun"):
		return _legal_gun(thing["gun"])
	var id := String(thing.get("id", ""))
	return _player.items.has_item(id) and _player.items.equip_slot(id) != ""


func _free_slots() -> int:
	var free := 0
	for slot in InventoryState.SIZE:
		if _player.inventory.item_id(slot) == "":
			free += 1
	return free


# The other player this one is looking at from close by (0 = nobody): hold the interact key on them to ask for a trade.
func _trade_target() -> int:
	if net == null or not net.can_send():
		return 0
	var eye := _player.global_position + Vector3.UP * 1.5
	var forward: Vector3 = _player.view_forward()
	var best := 0
	var best_dot := 0.9
	for id: int in net.roster:
		var body: Node3D = net.player_node(id)
		if id == net.my_id() or body == null:
			continue
		var to := body.global_position + Vector3.UP - eye
		if to.length() <= TRADE_RANGE and to.normalized().dot(forward) > best_dot:
			best_dot = to.normalized().dot(forward)
			best = id
	return best


func _hold_trade(delta: float) -> void:
	var busy: bool = _customizer.visible or _slot_screen.visible or _games.is_open() or _inventory_screen.visible or _trade_screen.visible or _chat.is_open()
	if busy or not Input.is_action_pressed("interact") or _trade_target() == 0 or not _field.nearest(_player.global_position).is_empty():
		_trade_hold = 0.0
		return
	_trade_hold += delta
	if _trade_hold >= TRADE_HOLD:
		_trade_hold = -2.0  # asked: not again for a moment
		net.trade.ask(_trade_target())


# "/trade <name>": the same ask by name.
func _trade_by_name(who: String) -> String:
	if net == null or not net.can_send():
		return "Trading needs an online session."
	for id: int in net.roster:
		if id != net.my_id() and String(net.roster[id]).to_lower() == who.to_lower():
			net.trade.ask(id)
			return "Asked %s to trade." % net.roster[id]
	return "No player called %s." % who


# What the host's trade desk tells this player (core/trade_desk.gd).
func _on_trade_message(what: String, args: Array) -> void:
	match what:
		"asked":
			_trade_asker = String(args[1])
			_trade_ask_until = _time + 20.0
			_player_hud.notice("%s wants to trade." % _trade_asker)
		"waiting":
			_player_hud.notice("Asked %s to trade..." % args[0])
		"table":
			if not _trade_screen.is_open():
				if _inventory_screen.visible:
					_toggle_inventory()
				_player.controls_enabled = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_trade_screen.in_hand = _player.hand_index()
			_trade_screen.show_table(args[0])
		"refused":
			_player_hud.notice("That cannot be traded.")
		"done":
			_close_trade()
			_finish_trade(args[0], args[1])
		"ended":
			_trade_ask_until = 0.0
			if _trade_screen.is_open():
				_close_trade()
			if String(args[0]) != "":
				_player_hud.notice(String(args[0]))


func _close_trade() -> void:
	_trade_screen.close()
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# The trade went through: what we gave leaves the bag (by the slots we named), what we got goes in.
func _finish_trade(gave: Array, got: Array) -> void:
	for ref: Variant in gave:
		var slot := int(ref)
		if slot < 0 or slot >= InventoryState.SIZE:
			continue
		if _player.inventory.take_gun(slot).is_empty() and _player.inventory.item_id(slot) != "":
			_player.inventory.remove(_player.inventory.item_id(slot), 1)
	for thing: Variant in got:
		if not thing is Dictionary:
			continue
		var given: Dictionary = thing
		if given.has("gun") and _legal_gun(given["gun"]):
			if not _player.inventory.add_gun(given["gun"]):
				_on_gun_dropped(given["gun"])
		elif given.has("id") and _player.items.has_item(String(given["id"])):
			_player.inventory.add(String(given["id"]), 1)
	_on_inventory_changed()
	save_profile()
	_player_hud.notice("Trade done: gave %d, got %d." % [gave.size(), got.size()])


func _on_inventory_changed() -> void:
	_player.refresh_held()
	_player.refresh_equipment()
	_inventory_screen.in_hand = _player.hand_index()
	save_profile()


func local_player() -> Player:
	return _player


func progress() -> ProgressState:
	return _progress


func wallet() -> Wallet:
	return _wallet


func score() -> ScoreCard:
	return _score


func rounds() -> IslandRounds:
	return _rounds


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
	if String(ChatCommand.parse(text).get("name", "")) == "trade":  # every player may trade: no operator right needed
		_chat.add_line(ChatCommand.clean(text), Color(0.7, 0.7, 0.7))
		_chat.add_line(_trade_by_name(" ".join(PackedStringArray(ChatCommand.parse(text)["args"]))), Color(0.75, 0.9, 1.0))
		return
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
		if _in_arena:
			_leave_arena()
		if not _in_fantasy:
			_enter_fantasy()
		return "Moved to Aurelind." if place == "fantasy" else _fantasy.travel(place)
	if place in ["island", "club", "arena"]:
		if _in_arena:
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
		_:
			return "Unknown place %s. Places: island, club, arena, fantasy (inside it also: %s)." % [place, ", ".join(_fantasy.place_names()) if _fantasy != null else "its regions and towns"]
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
		_score.from_dict(extra.get("score"))
		_player.pools.from_dict(extra.get("ammo"))
		_best_round = maxi(int(extra.get("best_round", 0)), 0)
		_bank.from_dict(extra.get("bank"), _player.inventory)
		var lying: Variant = extra.get("pack")
		if lying is Dictionary and lying.get("at") is Array and (lying["at"] as Array).size() == 3 and InventoryState.bundle_size(lying) > 0:
			_place_pack(Vector3(float(lying["at"][0]), float(lying["at"][1]), float(lying["at"][2])), {"things": lying["things"]})
		if KnifeModels.db().has(String(extra.get("knife", ""))):
			_player.set_knife(String(extra["knife"]))
			_knife_rolled = true
		_fantasy_saved = extra.get("fantasy")
	if player_name != "":
		_profile_name = player_name.strip_edges().substr(0, 20)
	if not _knife_rolled:  # a new character (or one from before the knives): its knife type is rolled once and kept
		_knife_rolled = true
		_player.set_knife(KnifeModels.db().roll(_rng))
		_player_hud.notice("Your knife: %s" % KnifeModels.db().name_of(_player.knife))
	if _progress.callsign == "":  # the card (P) starts with the character's name instead of "Unnamed"
		_progress.set_card(_profile_name, _progress.emblem, _progress.title)
	_apply_progress()
	_apply_name_loadout()
	_player.refresh_equipment()
	_player.reload_inventory()
	_inventory_screen.in_hand = _player.hand_index()


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
		var extra := {"coins": _wallet.balance, "jackpot": _jackpot, "progress": _progress.to_dict(), "score": _score.to_dict(), "ammo": _player.pools.to_dict(), "knife": _player.knife, "best_round": _best_round, "bank": _bank.to_dict(_player.inventory)}
		if _pack != null:
			extra["pack"] = {"at": [_pack.global_position.x, _pack.global_position.y, _pack.global_position.z], "things": _pack.bundle["things"]}
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
	return not _in_arena and not _in_fantasy and _near(_painting, PAINTING_RANGE)


func _near_painting_fantasy() -> bool:
	return not _in_arena and not _in_fantasy and _near(_painting_fantasy, PAINTING_RANGE)


func _near_fantasy_exit() -> bool:
	return _in_fantasy and _near(_fantasy_exit, PAINTING_RANGE)


# Text for the E prompt, or "" when nothing is in reach.
func _prompt() -> String:
	var key := InputSetup.label(settings, "interact")
	if _inventory_screen.visible or _customizer.visible or _card_screen.visible or _slot_screen.visible or _trade_screen.visible or _games.is_open() or _flight_t >= 0.0:
		return ""
	if _player.downed:
		return "You are out until the next round." if _out else "DOWN: a teammate can help you up (%d s)" % ceili(maxf(_down_until - _time, 0.0))
	if _revive_target != 0:
		return "[hold %s] Help %s up%s" % [key, net.roster.get(_revive_target, "your teammate"), "" if _revive_hold <= 0.0 else "  %d %%" % roundi(_revive_hold / float(_rounds.config()["downs"]["hold"]) * 100.0)]
	if _time < _trade_ask_until:
		return "[%s] Trade with %s  (ignore it to say no)" % [key, _trade_asker]
	if _pack != null and _near(_pack.global_position, DroppedPack.REACH):
		return "[%s] Take your things back (%d)" % [key, InventoryState.bundle_size(_pack.bundle)]
	if not _in_arena and not _in_fantasy and _near(_bank_pos, BankBox.REACH):
		return "[%s] Open the bank: what is in it is safe when you go down (%d of %d slots used)" % [key, _bank.used(), _bank.capacity()]
	if _near(Lifeguard.POS, LIFEGUARD_RANGE):
		return "[%s] Talk to the lifeguard: change your look" % key
	var drop := _field.nearest(_player.global_position)
	if not drop.is_empty():
		return "[%s] Pick up %s" % [key, GunStats.display_name(_player.gun_db, drop["gun"])]
	var partner := _trade_target()
	if partner != 0:
		return "[hold %s] Trade with %s" % [key, net.roster[partner]]
	var vendor := _vendor_near()
	if not vendor.is_empty():
		return "[%s] Buy a %s (%d coins) - a random rolled gun, %s or better" % [key, vendor["name"], int(vendor["price"]), vendor["min_tier"]]
	if _slot_near() != null:
		return "[%s] Play the slot machine (free coins)" % key
	var table := _games.spot_near(_player.global_position)
	if table != "":
		return "[%s] Sit at the %s table (free coins)" % [key, table]
	if _near_pachinko():
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
	if _near_fantasy_exit():
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
	if _player.downed or _revive_target != 0:
		return  # lying down, or busy helping somebody up (the key is held for that)
	if _time < _trade_ask_until:
		_trade_ask_until = 0.0
		net.trade.answer(true)
	elif _pack != null and _near(_pack.global_position, DroppedPack.REACH):
		_take_pack()
	elif not _in_arena and not _in_fantasy and _near(_bank_pos, BankBox.REACH):
		_open_bank()
	elif _near(Lifeguard.POS, LIFEGUARD_RANGE):
		_open_customizer()
	elif not _field.nearest(_player.global_position).is_empty():
		_pick_up(_field.nearest(_player.global_position))
	elif not _vendor_near().is_empty():
		_buy_crate(_vendor_near())
	elif _slot_near() != null:
		_open_slots(_slot_near())
	elif _games.spot_near(_player.global_position) != "":
		_games.open(_games.spot_near(_player.global_position))
	elif _near_pachinko():
		_launch_pachinko()
	elif _near(_crow_a_pos, CROW_RANGE):
		_feed_crow()
	elif _near(_crow_b_pos, CROW_RANGE):
		_start_flight(_crow_b, _crow_b_pos, _crow_a_pos, _island_spawn)
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
func _near_pachinko() -> bool:
	return _pachinko != null and _near(_pachinko.console_position(), PACHINKO_RANGE)


func _hold_pachinko(delta: float) -> void:
	var busy: bool = _customizer.visible or _slot_screen.visible or _games.is_open() or _inventory_screen.visible
	if busy or not Input.is_action_pressed("interact") or not _near_pachinko():
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
	if dest_spawn == _club_spawn and _casino.is_empty():
		_build_club()  # before take-off, so the flight itself does not stall
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
	if _casino.is_empty():
		return {}
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
	if int(drop["shared"]) != 0:  # a gun another player may be reaching for too: the host says who gets it (_on_drop_granted)
		if _free_slots() == 0:
			_player_hud.notice("Inventory full: make room first.")
		else:
			net.drops.take(int(drop["shared"]))
		return
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
	_score.kill()  # paid by how the blow landed (the player sets `blow` around its hits); nothing in Aurelind
	var kill_counters: Array = ["kills"]
	var xp_kind := "kill"
	if elite != "":
		kill_counters.append("elite_kills")
		xp_kind = "elite"
	if enemy_id == "boss" or enemy_id.begins_with("boss_"):
		kill_counters.append("boss_kills")
		xp_kind = "boss"
	var island_kill: bool = is_instance_valid(_director.last_killed) and _director.last_killed.has_meta("island")
	var guns: Array = [] if (_in_fantasy or island_kill) else DropRules.roll_drops(_player.gun_db, _drops_cfg, _rng, enemy_id, elite != "", wave, _luck_mult())  # the fantasy world has its own drops; the island's enemies drop no guns
	if island_kill and enemy_id.begins_with("boss"):  # until bosses drop power-ups: a beaten island boss fills every pool
		_player.pools.fill_all()
		_player_hud.notice("Max ammo")
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
	_player.pools.fill_all()  # until ammo can be bought or found (wall buys, max ammo): every colosseum run starts with full pools
	_player.teleport(ARENA_SPAWN, 0.0)
	_director.start()
	_player_hud.play_fade()


func _on_player_died() -> void:
	_progress.count("deaths", 1)
	_progress_notices(0)
	if _in_arena:
		_leave_arena()
	elif _in_fantasy:
		_player.teleport(_fantasy.haven_world(), 0.0)  # you wake up in the nearest town
		_fantasy.enter(_player.global_position)
		_player_hud.play_fade()
	else:
		if (net == null or not net.can_send()) and _rounds.rules.number > 0:  # alone, going down ends the run
			_score.downs += 1
			_end_run(_rounds.rules.number, _player.died_at, true)
		elif _out:  # online, nobody came: everything carried stays where we lay, and we wait for the next round
			_drop_pack(_player.died_at)
			save_profile()
		_player.teleport(_island_spawn, 0.0)
		_player.downed = _out  # out = lying at the spawn, untouchable, until the next round starts


# --- online: down, helped up, out (game/net_downs.gd keeps the party's states on the host) ---

# Asked by the player the moment its health runs out: true = lie down and wait for a teammate instead of dying.
func _goes_down() -> bool:
	return net != null and net.can_send() and not _in_arena and not _in_fantasy and _on_island(_player.global_position) and _island_round() > 0


func _island_round() -> int:
	return net.rounds.round_number if net != null and net.rounds.is_client() else _rounds.rules.number


func _on_went_down() -> void:
	_score.downs += 1
	_down_until = _time + float(_rounds.config()["downs"]["seconds"])
	net.downs.report("down")


# Nobody helped in time.
func _bleed_out() -> void:
	_out = true
	net.downs.report("out")
	_player.finish_off()  # -> _on_player_died: the backpack is left, we wait at the spawn
	_player_hud.notice("Nobody came. You are out until the next round.")


func _on_revived(share: float) -> void:
	if _player.downed and not _out:
		_player.revive(share)
		_hurt_at = _time
		_player_hud.notice("You are back on your feet.")


func _on_gave_revive() -> void:
	_score.revives += 1
	_player_hud.notice("You helped a teammate up.")


# The host ended the run for the whole party: nobody on the islands was left standing.
func _on_party_over(reached: int) -> void:
	var was_there := _player.downed or _out or (not _in_arena and not _in_fantasy and _on_island(_player.global_position))
	var lying := _player.downed and not _out
	var at := _player.global_position
	if _player.downed:
		_player.revive(1.0)
	_out = false
	if lying:
		_player.teleport(_island_spawn, 0.0)
	if was_there:
		_end_run(reached, at, lying)
	else:
		_player_hud.notice("The party's run on the islands ended in round %d." % reached)
		if _rounds.active:
			_rounds.stop()


# Other players lying down are shown lying down.
func _show_downs() -> void:
	for id: int in net.roster:
		var body: Node3D = net.player_node(id)
		if id != net.my_id() and body != null and body.has_method("set_down"):
			body.call("set_down", net.downs.state_of(id) != "up")


# Standing by a downed teammate and holding the interact key helps them up (the host has the last word).
func _hold_revive(delta: float) -> void:
	_revive_target = 0
	if _player.downed:
		_revive_hold = 0.0
		return
	for id: int in net.downs.states:
		var body: Node3D = net.player_node(id)
		if id != net.my_id() and net.downs.state_of(id) == "down" and body != null and _near(body.global_position, net.downs.reach):
			_revive_target = id
			break
	if _revive_target == 0 or not Input.is_action_pressed("interact"):
		_revive_hold = 0.0
		return
	_revive_hold += delta
	if _revive_hold >= float(_rounds.config()["downs"]["hold"]):
		_revive_hold = 0.0
		net.downs.ask_revive(_revive_target)


# --- the island's rounds (game/island_rounds.gd runs them; core/round_rules.gd decides) ---

func _on_island(at: Vector3) -> bool:
	return Vector2(at.x - Island.CENTER.x, at.z - Island.CENTER.z).length() < ISLAND_REACH


# The players standing on the island: us and, when hosting, the others. Nobody = the rounds wait.
func _island_bodies() -> Array:
	var out: Array = []
	if _on_island(_player.global_position) and not _player.carried and not _first_look and not _player.downed:
		out.append(_player)
	if net != null and net.can_send() and net.is_host():
		for body: Node3D in net.target_nodes():
			if _on_island(body.global_position) and not (body.has_method("is_down") and bool(body.call("is_down"))):
				out.append(body)
	return out


# The run on the islands is over for us: the game-over screen, the character's best round, and everything carried
# stays behind in a backpack where we went down. The island starts again at round 1.
func _end_run(reached: int, at: Vector3, drop: bool) -> void:
	var record := reached > _best_round
	_best_round = maxi(_best_round, reached)
	_game_over.show_run(reached, _best_round, record, PackedStringArray(["Kills %d        Points earned %d" % [_score.kills - _run_kills, _run_earned], "Everything you carried lies in a backpack where you went down." if (drop or _pack != null) else "You were still standing: you keep what you carry."]))
	if drop:
		_drop_pack(at)
	if _rounds.active:
		_rounds.stop()
	save_profile()


# Everything carried (ready guns and the whole bag; what is worn stays) is left in a backpack at `at`. A backpack
# still lying somewhere from last time is lost with all that is in it. A pistol goes into the empty hand.
func _drop_pack(at: Vector3) -> void:
	var bundle: Dictionary = _player.inventory.take_all()
	if _pack != null:
		_pack.queue_free()
		_pack = null
		_player_hud.notice("The backpack you left before is gone for good.")
	if InventoryState.bundle_size(bundle) > 0:
		var flat := Vector2(at.x - Island.CENTER.x, at.z - Island.CENTER.z)
		if flat.length() > Island.RADIUS - 1.5:  # went down in the water: it washes up on the sand
			flat = flat.normalized() * (Island.RADIUS - 1.5)
		_place_pack(Island.CENTER + Vector3(flat.x, Island.height_at(flat.x, flat.y), flat.y), bundle)
	for entry in DataStore.load_json("res://data/player.json")["starting_items"]:
		_player.inventory.add(String(entry[0]), int(entry[1]))
	_player.refresh_held()
	_player.refresh_equipment()
	_inventory_screen.in_hand = _player.hand_index()


func _place_pack(at: Vector3, bundle: Dictionary) -> void:
	_pack = DroppedPack.new()
	_pack.bundle = bundle
	add_child(_pack)
	_pack.global_position = at


# Back at the backpack: what fits goes back to where it belongs (guns into free holsters first), the rest waits.
func _take_pack() -> void:
	var rest: Dictionary = _player.inventory.put_all(_pack.bundle)
	if InventoryState.bundle_size(rest) == 0:
		_pack.queue_free()
		_pack = null
		_player_hud.notice("You have your things back.")
	else:
		_pack.bundle = rest
		_player_hud.notice("%d things found no room and stay in the backpack." % InventoryState.bundle_size(rest))
	_on_inventory_changed()


func _on_round_started(number: int, kind: String) -> void:
	if _out:  # online: whoever bled out is back in when the next round starts
		_out = false
		_player.revive(1.0)
		net.downs.report("up")
		_player_hud.notice("You are back in.")
	if number == 1:
		_player.pools.fill_all()  # a run starts with full pools
		_run_kills = _score.kills
		_run_earned = 0
	match kind:
		"boss":
			_player_hud.notice("Round %d: something big is wading in" % number)
			_sounds.call("play", "sting_boss")
		"special":
			_player_hud.notice("Round %d: the sea is crawling" % number)
			_sounds.call("play", "sting_special")
		_:
			_player_hud.notice("Round %d" % number)
			_sounds.call("play", "sting_round")


func _on_round_ended(number: int, kind: String) -> void:
	if kind == "special" and bool(_rounds.config()["special"]["max_ammo"]):
		_player.pools.fill_all()
		_player_hud.notice("Round %d survived: max ammo" % number)
	else:
		_player_hud.notice("Round %d survived" % number)
	_sounds.call("play", "sting_round_end")
	save_profile()


# The third painting: the fantasy world Aurelind (game/fantasy_world.gd), a streamed open land with its own magic,
# skills and quests.
func _enter_fantasy() -> void:
	LoadClock.mark("(play until the fantasy world was entered)")
	if loading != null:
		loading.call("begin", 10 if _fantasy == null else 5)
	_build_fantasy()
	LoadClock.mark("fantasy: world built")
	_in_fantasy = true
	_rest_worlds()
	_player.teleport(_fantasy.spawn_world(), 0.0)
	_player.look_at_point(_fantasy.farm_world() + Vector3(0.0, 3.0, 0.0))  # you arrive facing the farmhouse
	apply_settings()  # switches to the painted look and loads the land around the player
	LoadClock.mark("fantasy: look applied, land around the player")
	if loading != null:
		loading.call("finish")
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
	_fantasy_left_at = _time
	_rest_worlds()
	apply_settings()
	save_profile()
	_player.teleport(_island_spawn, 0.0)
	_player_hud.play_fade()


# ONLY THE WORLDS IN USE RUN (round 5). The gun side (colosseum, island, club shell) and Aurelind lie 20 km apart, yet
# each kept its ~1500-2000 nodes running while the player was in the other (0.6 ms a frame in Aurelind, 2.7 ms on the
# island). Asleep = not processed and out of the physics world; nothing is freed. A world is in use while the player
# is in it; on the HOST also while any other player is, because the host runs the shared boss and the party's fantasy
# world for them. A joining machine runs nothing for others. The club's inside runs only while the player is near it.
# Called every second and at once when the player changes world.
func _rest_worlds() -> void:
	_rest_in = 1.0
	_score.paused = _in_fantasy  # the points game is the gun side's
	_player_hud.show_points = not _in_fantasy
	if _player.knife_stowed != _in_fantasy:  # in Aurelind the hand without a gun holds the staff, not the knife
		_player.knife_stowed = _in_fantasy
		_player.refresh_held()
	var gun_side := not _in_fantasy
	var aurelind := _in_fantasy or _time - _fantasy_left_at < 3.0
	if net != null and net.is_active() and net.is_host():
		for spot: Vector3 in net.other_positions():
			if spot.x > FantasyWorld.OFFSET.x * 0.5:
				aurelind = true
			else:
				gun_side = true
	for part in _gun_side:
		part.process_mode = Node.PROCESS_MODE_INHERIT if gun_side else Node.PROCESS_MODE_DISABLED
	if _fantasy != null:
		_fantasy.process_mode = Node.PROCESS_MODE_INHERIT if aurelind else Node.PROCESS_MODE_DISABLED
	var at_club := _player.global_position.distance_to(ClubIsland.CENTER) < CLUB_NEAR
	if at_club and _casino.is_empty():
		_build_club()
	for part in _club_parts:
		part.process_mode = Node.PROCESS_MODE_INHERIT if at_club else Node.PROCESS_MODE_DISABLED


# The club's inside, its people and the casino exist only from the player's first trip there (crow ride or /tp club);
# until then the island shows its shell (ClubIsland.build_shell). Costs about a second, under the loading picture.
func _build_club() -> void:
	if loading != null:
		loading.call("begin", 2)
	var first := get_child_count()
	_casino = ClubIsland.build_inside(self)
	for index in range(first, get_child_count()):
		_club_parts.append(get_child(index))
	_pachinko = _casino["pachinko"]
	_pachinko.ball_landed.connect(_on_pachinko_landed)
	_slot_machines = _casino["slots"]
	for m in _slot_machines:
		m.finished.connect(_on_slot_finished)
	_games.setup(_wallet, _casino_cfg, _casino, _custom_layer, _player, _player_hud, _rng)
	(_casino["blackjack"] as Node3D).connect("changed", func(op: String, args: Array) -> void: table_event.emit(op, args))
	LoadClock.mark("club inside and casino")
	if loading != null:
		loading.call("finish")


# How much of the land is kept around the player, by graphics tier (data/graphics.json "fantasy").
func _fantasy_detail() -> void:
	var tier: Dictionary = RenderStyle.presets()["graphics"][0]
	for entry: Dictionary in RenderStyle.presets()["graphics"]:
		if String(entry["id"]) == settings.graphics:
			tier = entry
	var detail: Dictionary = tier.get("fantasy", {})
	_fantasy.set_detail(detail)


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
	if net != null and net.can_send():
		_hold_trade(delta)
		_hold_revive(delta)
		if _player.downed and not _out and _time >= _down_until:
			_bleed_out()
	_rest_in -= delta
	if _rest_in <= 0.0:
		_rest_worlds()
	if _fantasy_dirty and _time - _fantasy_saved_at > 20.0:
		_fantasy_dirty = false
		_fantasy_saved_at = _time
		save_profile()
	var regen: Dictionary = _rounds.config()["regen"]  # the classic way: left alone for a moment, you get your breath back
	if not _in_arena and not _in_fantasy and _time - _hurt_at >= float(regen["delay"]) and _player.health.hp > 0.0 and _player.health.hp < _player.health.max_hp:
		_player.health.heal(float(regen["per_second"]) * delta)
	_player_hud.prompt_text = _prompt()
	_player_hud.coins = _wallet.balance if _pachinko != null and _near(_pachinko.global_position, 30.0) else -1
	if _coins_dirty and (_pachinko == null or _pachinko.balls_in_play() == 0):
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
	var scope: float = _player.sight_amount()
	_scope.kind = _player.sight_kind()
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
	_hud.text = "fps %d  frame %.1f ms  draws %d  mem %.0f MB\n%s move, %s jump, %s sprint, %s shoot, %s reload, %s aim, %s/%s guns, %s knife, %s inventory, %s view, Esc menu" % [
		fps, 1000.0 / maxf(fps, 1.0), draws, mem_mb, _moves(), _key("jump"), _key("sprint"), _key("shoot"),
		_key("reload"), _key("aim"), _key("weapon_1"), _key("weapon_2"), _key("knife"), _key("inventory"), _key("toggle_view")]
	_player_hud.wave_text = _director.status_text()
	_player_hud.boss_ratio = _director.boss_ratio()
	var on_island := not _in_arena and not _in_fantasy and _on_island(_player.global_position)
	var watching: bool = net != null and net.rounds.is_client()  # the host runs the rounds: we show what it tells us
	var island_round: int = net.rounds.round_number if watching else _rounds.rules.number
	var island_fight: bool = net.rounds.fighting if watching else _rounds.rules.fighting()
	_player_hud.round_number = _director.wave_number() if _in_arena else (island_round if on_island else 0)
	_player_hud.round_of = _director.wave_count() if _in_arena else 0
	_player_hud.enemies_left = _director.enemies_left() if _in_arena else ((net.rounds.round_left if watching else _rounds.left()) if on_island and island_fight else -1)
	_player_hud.party = net.scores.others() if net != null and net.can_send() else []
	_scoreboard.my_name = _profile_name
	_scoreboard.title = "" if _player_hud.round_number <= 0 else ("Wave %d / %d" % [_director.wave_number(), _director.wave_count()] if _in_arena else "Round %d" % _player_hud.round_number)
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
	layer.add_child(_scoreboard)
	layer.add_child(_game_over)
	layer.add_child(_chat)
	add_child(layer)
