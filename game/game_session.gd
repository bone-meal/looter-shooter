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
const CrosshairStyle = preload("res://core/crosshair_style.gd")
const CrosshairView = preload("res://game/crosshair_view.gd")
const PhotoMode = preload("res://game/photo_mode.gd")
const StatBook = preload("res://core/stat_book.gd")
const AchievementReader = preload("res://core/achievement_reader.gd")
const CombatReport = preload("res://game/combat_report.gd")
const CourseRules = preload("res://core/course_rules.gd")
const BhopCourse = preload("res://game/bhop_course.gd")
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
const CardTable = preload("res://game/tcg/card_table.gd")
const CardShop = preload("res://game/tcg/card_shop.gd")
const PlayerTable = preload("res://game/tcg/player_table.gd")
const TcgStats = preload("res://core/tcg/tcg_stats.gd")
const CardCollection = preload("res://core/tcg/collection.gd")
const CardDb = preload("res://core/tcg/card_db.gd")
const ChatBox = preload("res://game/chat_box.gd")
const ChatCommand = preload("res://core/chat_command.gd")
const AdminCommands = preload("res://game/admin_commands.gd")
const FantasyWorld = preload("res://game/fantasy_world.gd")
const TradeScreen = preload("res://game/trade_screen.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ScoreCard = preload("res://core/score_card.gd")
const KnifeModels = preload("res://game/knife_models.gd")
const IslandRounds = preload("res://game/island_rounds.gd")
const PowerupRules = preload("res://core/powerup_rules.gd")
const Archipelago = preload("res://core/archipelago.gd")
const WallBuy = preload("res://game/wall_buy.gd")
const Shelters = preload("res://game/shelters.gd")
const PerkState = preload("res://core/perk_state.gd")
const NetRounds = preload("res://game/net_rounds.gd")
const PowerState = preload("res://core/power_state.gd")
const PerkMachine = preload("res://game/perk_machine.gd")
const PowerStation = preload("res://game/power_station.gd")
const MysteryBox = preload("res://core/mystery_box.gd")
const MysteryBoxNode = preload("res://game/mystery_box_node.gd")
const TrapState = preload("res://core/trap_state.gd")
const Traps = preload("res://game/traps.gd")
const IslandWeather = preload("res://game/island_weather.gd")
const BuildState = preload("res://core/build_state.gd")
const BuildSite = preload("res://game/build_site.gd")
const BoatRules = preload("res://core/boat_rules.gd")
const ColosseumRules = preload("res://core/colosseum_rules.gd")
const ColosseumBoard = preload("res://game/colosseum_board.gd")
const CigaretteState = preload("res://core/cigarette_state.gd")
const QuestState = preload("res://core/quest_state.gd")
const QuestThings = preload("res://game/quest_things.gd")
const SongBook = preload("res://core/song_book.gd")
const SongFloats = preload("res://game/song_floats.gd")
const Jukebox = preload("res://game/jukebox.gd")
const MusicLibrary = preload("res://game/music_library.gd")
const TextBook = preload("res://core/text_book.gd")
const Boat = preload("res://game/boat.gd")
const PowerupField = preload("res://game/powerup_field.gd")
const DroppedPack = preload("res://game/dropped_pack.gd")
const GameOverScreen = preload("res://game/game_over_screen.gd")
const BankState = preload("res://core/bank_state.gd")
const BankBox = preload("res://game/bank_box.gd")
const Scoreboard = preload("res://game/scoreboard.gd")
const HubRoom = preload("res://game/hub_room.gd")
const HubHud = preload("res://game/hub_hud.gd")
const InkBlackout = preload("res://game/ink_blackout.gd")

const HUD_REFRESH := 0.25
const ARENA_SPAWN := Vector3(0, 0.1, 10)
const JUKEBOX_AT := Vector3(-8.8, 0.0, 0.3)  # in the club, from its middle: by the left wall, between the bar and the front wall
const JUKEBOX_YAW := -PI * 0.5  # its front (-Z) toward the middle of the room
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
const CLUB_NEAR := 150.0  # metres from the club's middle within which its inside is built and runs (was 300: the boat at the islands' east edge came within 267 m and built the club under a loading picture)

signal look_changed(look: Dictionary)
signal table_event(op: String, args: Array)  # our blackjack table actions, sent to other players so they can watch
signal card_changed(progress: Dictionary)  # level, achievements or card edited: main.gd sends it to the other players

var settings: SettingsState  # set before add_child
var net: Node3D  # game/net_session.gd, set before add_child (idle when playing alone)
var loading: Control  # game/loading_screen.gd, set before add_child (may be null in test scenes)
var player_name := ""  # set before add_child when playing online (the lobby name)
var _save_key := ""  # which save file (the typed name)
var _profile_name := ""  # saved with the inventory (see game/profile_io.gd)
var run_note := ""  # why we went along with the last run or not (developer checks)
var no_save := false  # scripted developer runs (tools/dev_boot.gd) leave the save file alone

var _player: Player
var _director: WaveDirector
var _hud := Label.new()
var _overlay := DebugOverlay.new()
var _scope := ScopeOverlay.new()
var _player_hud := PlayerHud.new()
var _bars := EnemyBars.new()
var _cross := CrosshairView.new()  # the player's crosshair (Settings > Crosshair)
var _cross_styles := CrosshairStyle.new()
var _photo := PhotoMode.new()  # F10: free camera and pictures into the Pictures folder
var _stats := StatBook.new()  # everything this character has done (the Combat Report on the card; saved as "stats")
var _last_wave := 0  # the colosseum wave last seen (a higher one = the one before was cleared)
var _stat_from := Vector3.INF  # where the player stood last frame (distance travelled)
var _ach_wait := 2.0  # seconds to the next reading of the stat achievements
var _course := CourseRules.new()  # the hop course in the sky (data/course.json): clock, checkpoints, best time
var _course_root: Node3D  # built on the first trip there
var _course_door := Vector3.ZERO  # the arch on Home Sand
var _course_spot := Vector2.ZERO
var _on_course := false
const COURSE_DOOR_REACH := 2.6
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
var _hub_room: HubRoom  # the safe hub every Start / Load lands in (diary/DECISIONS_HUB.md); null in test scenes without a net
var _hub_hud := HubHud.new()
var _ink := InkBlackout.new()  # the hub's travel effect
var _hub_dark := false  # the player stands in the hub: the sky's light is off, the hub's own candles light it
var _hub_tick := -1  # the last countdown second ticked
var _hub_painting := Vector3.INF
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
var _land: Archipelago  # the islands: where they are, which debris is cleared (core/archipelago.gd)
var _debris: Array = []  # game/debris_pile.gd, one per bridge
var _perks: PerkState  # the perks our player carries (lost on going down)
var _perk_spots := {}  # perk id -> Vector2 (its machine, metres from the spawn island's middle)
var _perk_machines := {}  # perk id -> game/perk_machine.gd
var _power: PowerState  # the switch: parts found, on or off (the whole party's)
var _power_cfg: Dictionary  # data/power.json
var _power_station := PowerStation.new()
var _part_spots: Array[Vector2] = []
var _bench_spot := Vector2.ZERO
var _box: MysteryBox  # the mystery box: where it stands, spinning, offering (the party's; the host decides)
var _box_node := MysteryBoxNode.new()
var _box_spots: Array[Vector2] = []
var _box_owner := 0  # who spun it (a peer id; 1 alone)
var _box_gun := {}  # the gun on offer
var _upgrade_cfg: Dictionary  # data/upgrade_machine.json
var _upgrade_spot := Vector2.ZERO
var _upgrade_node := PerkMachine.new()
var _traps: TrapState
var _trap_cfg: Dictionary  # data/traps.json
var _trap_nodes := Traps.new()
var _weather := IslandWeather.new()  # fog, storm and red sky by round (data/island_weather.json)
var _builds: BuildState  # the shield and the boat: parts found, things built (data/buildables.json)
var _build_cfg: Dictionary
var _build_site := BuildSite.new()
var _build_parts: Array = []  # per thing: Array[Vector2], where its parts lie (metres from the land's middle)
var _build_benches: Array[Vector2] = []  # per thing: its bench
var _boat: BoatRules  # the buildable boat (data/boat.json): where it is, who sits in it
var _boat_node := Boat.new()
var _boat_thing := -1  # its number among the buildables
var _boat_start := Vector2.ZERO  # where it floats once built, and the way its bow points there
var _boat_start_yaw := 0.0
var _seat := -1  # our seat aboard (0 = the tiller), -1 = not aboard
var _helm_keys := Vector2.ZERO  # hosting: throttle (x) and rudder (y) of a client at the tiller
var _boat_tell := 0.0  # seconds to the next boat message (host: its state; client at the tiller: its keys)
var _boat_goal := Vector3.ZERO  # as a client: x, z and yaw the host last told, glided toward
var _ashore_until := 0.0  # as a client: until then the host's list may still name us in the seat we just left
var _trap_centres: Array[Vector2] = []
var _trap_levers: Array[Vector2] = []
var _trap_shown: Array[bool] = []
var _trap_tick := 0.0
var _second_wind_used := false  # alone: the one self-revive of this run is spent
var _self_revive_at := -1.0  # alone with Second Wind: when we get back up (-1 = not lying)
var _shelters := Shelters.new()  # the huts and their window boards
var _nail_at := 0.0  # as a client: when we may next ask the host to nail a board
var _last_isle := 0  # the island we last stood on (where the sea carries us back to)
var _powerups: PowerupRules  # the islands' power-ups: what an enemy leaves and which effects are running
var _power_field := PowerupField.new()  # ... and the ones lying around
var _power_id := 0  # the last one dropped here (alone or hosting)
var _blasting := false  # the nuke is killing: what dies of it leaves nothing
var _watched := 0  # online, out of the round: the teammate our camera follows (0 = nobody)
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
var _tcg := CardTable.new()  # the card game table on the club beach (built with the club)
var _cards := CardCollection.new()  # the card game collection (saved in extra "tcg")
var _shop := CardShop.new()  # the card vending machine in the casino (built with the club)
var _tcg_mats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/mats.json"))  # for the card game's achievement readings
var _ptables := PlayerTable.new()  # the three card tables where players play each other online (built with the club)
var _colosseum: ColosseumRules  # tickets, tougher waves, the loot by wave (data/colosseum.json)
var _board := ColosseumBoard.new()  # the ticket board at the painting
var _run_ticket := 0  # the ticket of the colosseum run we are in
var _run_mods := PackedStringArray()  # and its modifiers
var _quest := QuestState.new()  # the islands' main quest (data/zombies/quest.json + writing/quest.txt)
var _quest_things := QuestThings.new()
var _quest_text_problems := PackedStringArray()  # shown once the HUD exists
var _quest_spots := {}  # step id -> Vector2 on the land's map (use, kills and boss steps)
var _lamp_spots: Array[Vector3] = []  # the shoot step's lamps, world positions (their tops)
var _songs := SongBook.new()  # the hidden songs (data/zombies/songs.json)
var _song_floats := SongFloats.new()
var _song_spots: Array = []  # [secret][thing] -> world position
var music_box: Node  # game/music_box.gd (made by game/main.gd, set before add_child): the jukebox, hidden songs
var music_menu: Control  # game/music_menu.gd (main's): the jukebox window
var _jukebox_open := false  # we opened music_menu from a jukebox (controls come back when it closes)
var _jukebox: Node3D  # in the club, made with its inside
var _smoke := CigaretteState.new()  # the burn of the cigarette being smoked (data/cigarette.json)
var _run_fx := {}  # what those modifiers change (core/colosseum_rules.gd `effects`), {} outside a run
var _fuse_wave := 0  # Short Fuse: the wave whose clock runs, the seconds it has left, and whether its late pack came
var _fuse_left := 0.0
var _fuse_late := false
var _still := 0.0  # Toxic Sand: seconds we have stood still
var _ring: MultiMeshInstance3D  # Closing Ring: its flames (made on the first run that has it)
var _ring_radius := 0.0
var _ring_tick := 0.0
var _torch: SpotLight3D  # Blackout: the light on our head
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
	_smoke.setup(DataStore.load_json("res://data/cigarette.json"))
	LoadClock.mark("sky and light")
	var first_gun_side := get_child_count()
	var gates := Colosseum.build(self)
	LoadClock.mark("colosseum")
	_land = Archipelago.new(DataStore.load_json("res://data/archipelago.json"))
	_perks = PerkState.new(DataStore.load_json("res://data/perks.json"))
	for id: String in _perks.ids():
		_perk_spots[id] = _land.on_island(String(_perks.cfg["perks"][id]["island"]), _perks.cfg["perks"][id]["at"])
		_land.keep_clear.append(_perk_spots[id])
	_power_cfg = DataStore.load_json("res://data/power.json")
	_power = PowerState.new(_power_cfg)
	for part: Dictionary in _power_cfg["parts"]:
		_part_spots.append(_land.on_island(String(part["island"]), part["at"]))
	_bench_spot = _land.on_island(String(_power_cfg["bench"]["island"]), _power_cfg["bench"]["at"])
	_land.keep_clear.append_array(_part_spots)
	_land.keep_clear.append(_bench_spot)
	_course.setup(DataStore.load_json("res://data/course.json"))
	_course_spot = _land.on_island(String(_course.cfg["door"]["island"]), _course.cfg["door"]["at"])
	_course_door = _flat(_course_spot)
	_land.keep_clear.append(_course_spot)
	_build_cfg = DataStore.load_json("res://data/buildables.json")
	_builds = BuildState.new(_build_cfg)
	for thing: Dictionary in _build_cfg["things"]:
		var lying: Array[Vector2] = []
		for part: Dictionary in thing["parts"]:
			lying.append(_land.on_island(String(part["island"]), part["at"]))
		_build_parts.append(lying)
		_build_benches.append(_land.on_island(String(thing["bench"]["island"]), thing["bench"]["at"]))
		_land.keep_clear.append_array(lying)
	_land.keep_clear.append_array(_build_benches)
	var boat_cfg: Dictionary = DataStore.load_json("res://data/boat.json")
	_boat = BoatRules.new(boat_cfg)
	_boat_thing = _builds.index_of("boat")
	_boat_start = _land.on_island(String(boat_cfg["start"]["island"]), boat_cfg["start"]["at"])
	_boat_start_yaw = _toward_middle(_boat_start)  # that turns -Z, the bow, away from the island
	_boat.place(_boat_start, _boat_start_yaw)
	_boat_node.setup(boat_cfg)
	_quest.setup(DataStore.load_json("res://data/zombies/quest.json"), TextBook.read_files(PackedStringArray(["res://data/zombies/writing/quest.txt"])))
	for entry: Dictionary in _quest.steps():
		if entry.has("at"):
			_quest_spots[String(entry["id"])] = _land.on_island(String(entry["island"]), entry["at"])
			_land.keep_clear.append(_quest_spots[String(entry["id"])])
		for lamp: Dictionary in entry.get("spots", []):
			var foot := _land.on_island(String(lamp["island"]), lamp["at"])
			_land.keep_clear.append(foot)
			_lamp_spots.append(_flat(foot) + Vector3(0, float(lamp["height"]), 0))
	var song_cfg: Dictionary = DataStore.load_json("res://data/zombies/songs.json")
	_songs.setup(song_cfg)
	for secret: Dictionary in song_cfg["secrets"]:
		var row: Array = []
		for thing: Dictionary in secret["things"]:
			var foot := _land.on_island(String(thing["island"]), thing["at"])
			_land.keep_clear.append(foot)
			row.append(_flat(foot) + Vector3(0, 0.12, 0))
		_song_spots.append(row)
	_songs.set_files(PackedStringArray(MusicLibrary.scan().map(func(s: Dictionary) -> String: return String(s["file"]))))  # song n = the n-th file of our Music folder
	var box_cfg: Dictionary = DataStore.load_json("res://data/mystery_box.json")
	_box = MysteryBox.new(box_cfg, _rng)
	for place: Dictionary in box_cfg["spots"]:
		_box_spots.append(_land.on_island(String(place["island"]), place["at"]))
	_land.keep_clear.append_array(_box_spots)
	_upgrade_cfg = DataStore.load_json("res://data/upgrade_machine.json")
	_upgrade_spot = _land.on_island(String(_upgrade_cfg["island"]), _upgrade_cfg["at"])
	_land.keep_clear.append(_upgrade_spot)
	_trap_cfg = DataStore.load_json("res://data/traps.json")
	_traps = TrapState.new(_trap_cfg["traps"])
	for trap: Dictionary in _trap_cfg["traps"]:
		if String(trap["kind"]) == "fire":
			var pit := _land.on_island(String(trap["island"]), trap["at"])
			var inland: Vector2 = ((_land.islands[_land.island_near(pit.x, pit.y)]["at"] as Vector2) - pit).normalized()
			_trap_centres.append(pit)
			_trap_levers.append(pit + inland * (float(trap["radius"]) + 1.5))
			_land.keep_clear.append(pit)
		else:  # a coil on a hut: its lever stands inside, beside the door
			var hut: Dictionary = _land.shelters[int(trap["hut"])]
			var yaw := float(hut["yaw"])
			_trap_centres.append(hut["at"])
			_trap_levers.append((hut["at"] as Vector2) + Vector2(2.3 * cos(yaw) + 1.9 * sin(yaw), -2.3 * sin(yaw) + 1.9 * cos(yaw)))
	var island := Island.build(self, _land)
	_debris = island["debris"]
	BhopCourse.build_door(self, _course_door, _toward_middle(_course_spot))
	for id: String in _perk_spots:
		var machine := PerkMachine.new()
		machine.title = _perks.name_of(id)
		machine.price = _perks.price(id)
		machine.tint = _perks.color_of(id)
		machine.position = _flat(_perk_spots[id])
		machine.rotation.y = _toward_middle(_perk_spots[id])
		add_child(machine)
		_perk_machines[id] = machine
	var parts: Array[Vector3] = []
	for spot: Vector2 in _part_spots:
		parts.append(_flat(spot))
	_power_station.setup(parts, _flat(_bench_spot), _toward_middle(_bench_spot))
	add_child(_power_station)
	_show_power()
	var sites: Array = []
	for thing in _builds.ids.size():
		var spots: Array[Vector3] = []
		for spot: Vector2 in _build_parts[thing]:
			spots.append(_flat(spot))
		sites.append({"id": _builds.ids[thing], "parts": spots, "bench": _flat(_build_benches[thing]), "yaw": _toward_middle(_build_benches[thing])})
	_build_site.setup(sites)
	add_child(_build_site)
	var quest_places := {"lamps": _lamp_spots}
	for id: String in ["log", "jars", "bell"]:
		if _quest_spots.has(id):
			quest_places[id] = _flat(_quest_spots[id])
	_quest_things.setup(quest_places, _on_lamp_shot)
	add_child(_quest_things)
	_song_floats.setup(_song_spots, _on_float_shot)
	add_child(_song_floats)
	for problem: String in _quest.text_problems():  # the writers' file: say what it is missing
		push_warning(problem)
		_quest_text_problems.append(problem)
	add_child(_boat_node)
	_show_builds()
	add_child(_box_node)
	_box_node.stand(_flat(_box_spots[0]))
	_upgrade_node.title = "Re-forge"
	_upgrade_node.price = int(_upgrade_cfg["reroll"])
	_upgrade_node.tint = Color(0.75, 0.35, 0.95)
	_upgrade_node.position = _flat(_upgrade_spot)
	_upgrade_node.rotation.y = _toward_middle(_upgrade_spot)
	add_child(_upgrade_node)
	add_child(_trap_nodes)
	for i in _trap_centres.size():
		_trap_nodes.add(String(_trap_cfg["traps"][i]["kind"]), _flat(_trap_centres[i]), _flat(_trap_levers[i]), float(_trap_cfg["traps"][i]["radius"]))
		_trap_shown.append(false)
	_shelters.setup(_land.shelters, _land.cfg["windows"])
	_shelters.tore.connect(_on_board_torn)
	add_child(_shelters)
	for board: Dictionary in _land.wall_buys:
		var stand := WallBuy.new()
		stand.gun = String(board["gun"])
		stand.price = int(board["price"])
		stand.position = Island.CENTER + Vector3((board["at"] as Vector2).x, 0.0, (board["at"] as Vector2).y)
		stand.rotation.y = float(board["yaw"])
		add_child(stand)
	LoadClock.mark("island")
	_painting = island["painting"]
	_painting_fantasy = island["painting_fantasy"]
	_island_spawn = island["spawn"]
	_loot_tables = DataStore.load_json("res://data/loot_tables.json")["tables"]
	_rng.randomize()
	if net != null:
		_hub_room = HubRoom.new()
		_hub_room.cfg = net.hub.cfg
		add_child(_hub_room)
		var hung: Array = _hub_room.painting_spot()
		_hub_painting = hung[0]
		Island.build_painting(self, _hub_painting, PaintingArt.wheat_texture(), float(hung[1]))
		LoadClock.mark("hub")
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
	_weather.setup(DataStore.load_json("res://data/island_weather.json"), _render_style, _sounds)
	add_child(_weather)
	_explosives.sounds = _sounds
	add_child(_skill_fx)
	LoadClock.mark("crows, lifeguard, effects")
	_build_hud()
	LoadClock.mark("hud")

	_player = Player.new()
	_player.settings = settings
	_player.position = island["spawn"]
	if _hub_room != null:  # every Start / Load lands in the hub (a joiner whose group already left goes on at once)
		_player.position = _hub_room.spawn(_hub_place())
	add_child(_player)
	LoadClock.mark("player (body, guns)")
	add_child(_photo)
	_photo.setup(_player, settings)
	_numbers.shown.connect(func(amount: float) -> void: _stats.add("damage_dealt", amount))
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
	_card_screen.report = _combat_report
	_card_screen.cards = _cards
	_card_screen.card_db = CardDb.from_files()
	_card_screen.stats = _stats
	_card_screen.changed.connect(_on_card_changed)
	_card_screen.closed.connect(_on_card_closed)
	custom_layer.add_child(_card_screen)
	custom_layer.add_child(_slot_screen)
	custom_layer.add_child(_trade_screen)
	_colosseum = ColosseumRules.new(DataStore.load_json("res://data/colosseum.json"))
	_board.rules = _colosseum
	_board.tier_name = func(tier: String) -> String: return String(_player.gun_db.tier(tier)["name"])
	_board.chosen.connect(_on_ticket_chosen)
	_board.closed.connect(_close_board)
	custom_layer.add_child(_board)
	_trade_screen.setup(_player.inventory, _player.items, _player.gun_db)
	_trade_screen.set_cards(_cards, _card_screen.card_db)
	_slot_screen.setup(_slot_data)
	_slot_screen.spin_requested.connect(_on_slot_spin)
	_slot_screen.closed.connect(_close_slots)
	_games.round_finished.connect(save_profile)
	_games.left.connect(save_profile)
	add_child(_games)
	_tcg.finished.connect(save_profile)
	add_child(_tcg)
	_shop.bought.connect(save_profile)
	add_child(_shop)
	_ptables.finished.connect(save_profile)
	add_child(_ptables)
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
	_director.wave_stats = func(stats: Dictionary, wave: int) -> Dictionary: return _colosseum.wave_stats(stats, wave, _director.run_fx)
	_director.wave_list = func(waves: Array, count: int) -> Array: return _colosseum.run_waves(waves, count, _director.run_fx)
	_rounds.director = _director
	_rounds.land = _land
	_rounds.shelters = _shelters
	_player.perks = _perks
	_player_hud.perks = _perks
	_rounds.bodies = _island_bodies
	_rounds.rules.alive_cap = int((_rounds.config()["alive_cap"] as Dictionary).get(settings.graphics, 24))
	_rounds.round_started.connect(_on_round_started)
	_rounds.round_ended.connect(_on_round_ended)
	add_child(_rounds)
	_powerups = PowerupRules.new(DataStore.load_json("res://data/powerups.json"))
	_power_field.setup(_powerups.cfg)
	_power_field.bodies = _island_bodies
	_power_field.touched.connect(_on_power_touched)
	_power_field.expired.connect(_on_power_expired)
	add_child(_power_field)
	_rounds.one_blow = func() -> bool: return _powerups.is_on("insta_kill", _time)
	_player_hud.powerups = _powerups
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
		net.rounds.power_dropped.connect(_on_power_dropped)
		net.rounds.power_gone.connect(_power_field.remove)
		net.rounds.power_taken.connect(_apply_power)
		net.rounds.land = _land
		net.rounds.debris_opened.connect(_on_debris_opened)
		net.rounds.debris_billed.connect(_on_debris_billed)
		net.rounds.shelters = _shelters.rules
		net.rounds.power = _power
		net.rounds.power_near = _power_thing_at
		net.rounds.power_bits.connect(_on_power_bits)
		net.rounds.builds = _builds
		net.rounds.build_near = _build_thing_at
		net.rounds.build_bits.connect(_on_build_bits)
		net.rounds.boat_near = _near_boat
		net.rounds.quest = _quest
		net.rounds.quest_near = _quest_fits
		net.rounds.quest_asked.connect(func(_peer: int, action: String, index: int) -> void: _quest_do(action, index))
		net.rounds.quest_told.connect(_on_quest_told)
		net.rounds.painting_near = func(at: Vector3) -> bool: return at.distance_to(_painting) <= PAINTING_RANGE + 1.5
		net.rounds.run_asked.connect(func(peer: int, ticket: int, mods: PackedStringArray) -> void:
			_start_run(ticket, mods, peer)
			net.rounds.tell_run(ticket, mods, peer))
		net.rounds.run_started.connect(_start_run)
		net.rounds.in_run = func() -> bool: return _in_arena
		net.rounds.seat_asked.connect(_on_seat_asked)
		net.rounds.helm_input.connect(func(peer: int, throttle: float, rudder: float) -> void:
			if _boat.helm() == peer:
				_helm_keys = Vector2(throttle, rudder))
		net.rounds.boat_state.connect(_on_boat_state)
		net.rounds.box_near = func(at: Vector3) -> bool: return _box.state != "moving" and Vector2(at.x - Island.CENTER.x, at.z - Island.CENTER.z).distance_to(_box_spots[_box.spot]) <= float(_box.cfg["reach"]) + 1.0
		net.rounds.box_asked.connect(_on_box_asked)
		net.rounds.box_state.connect(_on_box_state)
		net.rounds.trap_near = _trap_at
		net.rounds.trap_asked.connect(_start_trap)
		net.rounds.trap_started.connect(_on_trap_started)
		net.rounds.window_set.connect(_on_window_set)
		net.rounds.nail_paid.connect(_on_nail_paid)
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
		_player.shield_broke.connect(func() -> void: _player_hud.notice("Your %s broke. Take a new one at its bench." % String(_player.shield.cfg["name"])))
		if net.is_active():
			_build_fantasy()
	if _hub_room != null:
		net.hub.reset()
		net.hub.my_pos = func() -> Vector3: return _player.global_position
		net.hub.view_changed.connect(_on_hub_view)
		net.hub.go.connect(_on_hub_go)
		_hub_hud.red_last = float(net.hub.cfg["red_last"])
		_hub_hud.names = func(peer: int) -> String: return String(net.roster.get(peer, _profile_name)) if net.can_send() else _profile_name
	apply_settings()
	_show_quest()
	for problem: String in _quest_text_problems:  # the writers' quest file is missing something: say what
		_chat.add_line(problem, Color(1.0, 0.6, 0.4))


func apply_settings() -> void:
	_player.apply_settings()
	_render_style.apply(settings.graphics, settings.shaders, settings.picks)
	if _hub_dark:
		_darken_for_hub()  # before the weather reads the look's light as its base
	_weather.look_changed(settings.graphics, _island_side())
	if _in_fantasy:
		_fantasy_detail()
		_fantasy.enter(_player.global_position)
	_overlay.visible = settings.show_debug
	_player_hud.show_speed = settings.show_debug
	_cross.show_style(_cross_styles.clean(settings.crosshair) if not settings.crosshair.is_empty() else _cross_styles.preset(0))


func _place_crow(at: Vector3, facing: Vector3) -> Node3D:
	var crow := CrowModel.build()
	add_child(crow)
	crow.position = at
	crow.look_at(Vector3(facing.x, at.y, facing.z), Vector3.UP)
	return crow


func _unhandled_input(event: InputEvent) -> void:
	if _customizer.visible or _slot_screen.visible or _games.is_open() or _tcg.is_open() or _ptables.is_open() or _shop.is_open() or _card_screen.visible or _trade_screen.visible or _board.visible or (music_menu != null and music_menu.visible) or (_fantasy != null and _fantasy.panel_open()):
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
	elif event.is_action_pressed("photo_mode") and not _inventory_screen.visible and not _photo.active:
		_photo.enter(net == null or not net.can_send())  # alone the game stands still meanwhile
		get_viewport().set_input_as_handled()
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
	if _tcg.is_open():
		_tcg.request_close()
	elif _ptables.is_open():
		_ptables.request_close()
		return true
	if _shop.is_open():
		_shop.close()
		return true
	if _slot_screen.visible:
		_slot_screen.close()
		return true
	if _customizer.visible:
		_close_customizer()
		return true
	if _board.visible:
		_close_board()
		return true
	if music_menu != null and music_menu.visible:
		music_menu.call("close")
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


# The small line on the card banner: from the combat record (core/stat_book.gd).
func _card_line() -> String:
	_read_achievements()
	return "Kills %s  Bosses %s  Achievements %d/%d  Played %s" % [_short(_stats.total("kills")), _short(_stats.total("boss_kills")),
		(_progress.unlocked as Array).size(), _progress.achievement_defs().size(), StatBook.duration(_stats.total("seconds_played"))]


# 950 / 12.4k / 3.1M: short enough for the card banner.
static func _short(value: float) -> String:
	if value >= 1000000.0:
		return "%.1fM" % (value / 1000000.0)
	if value >= 10000.0:
		return "%.1fk" % (value / 1000.0)
	return str(floori(value))


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
	return "%d more slots: %d points (you have %d)" % [slots, int(cost["points"]), _score.points] if cost.has("points") else "%d more slots: %d casino chips (you have %d)" % [slots, int(cost["coins"]), _wallet.balance]


# The bank's upgrade button: the first upgrades cost points, the later ones casino chips.
func _on_bank_upgrade() -> void:
	var cost: Dictionary = _bank.next_upgrade()
	if cost.is_empty():
		return
	var paid: bool = _score.spend(int(cost["points"])) if cost.has("points") else _wallet.spend(int(cost["coins"]))
	if not paid:
		_player_hud.notice("Not enough %s for more bank slots." % ("points" if cost.has("points") else "casino chips"))
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


# Host: guns and armour (director, round 5) and card game cards (a real card or leader in a real finish).
func _legal_thing(thing: Dictionary) -> bool:
	if thing.has("gun"):
		return _legal_gun(thing["gun"])
	if thing.has("card"):
		return _legal_card(thing)
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
	var busy: bool = _customizer.visible or _slot_screen.visible or _games.is_open() or _tcg.is_open() or _ptables.is_open() or _shop.is_open() or _inventory_screen.visible or _trade_screen.visible or _chat.is_open()
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
func _legal_card(thing: Dictionary) -> bool:
	var db: RefCounted = _card_screen.card_db
	var id := String(thing.get("card", ""))
	if not CardCollection.FINISHES.has(String(thing.get("finish", ""))):
		return false
	if bool(thing.get("leader", false)):
		return (db.get("leaders") as Dictionary).has(id)
	return not db.card(id).is_empty() and String(db.card(id)["rarity"]) != "token"


func _finish_trade(gave: Array, got: Array) -> void:
	for ref: Variant in gave:
		if _trade_screen.offered_cards.has(int(ref)):  # a card from the collection
			var c: Dictionary = _trade_screen.offered_cards[int(ref)]
			_cards.remove(String(c["card"]), String(c["finish"]), 1, bool(c["leader"]))
			continue
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
		elif given.has("card") and _legal_card(given):
			_cards.add(String(given["card"]), String(given.get("finish", "")), 1, bool(given.get("leader", false)))
	_on_inventory_changed()
	save_profile()
	_player_hud.notice("Trade done: gave %d, got %d." % [gave.size(), got.size()])


func _on_inventory_changed() -> void:
	_player.refresh_held()
	_player.refresh_equipment()
	if _player.inventory.holster_count != _holsters_due():  # armour with a holster was put on or taken off
		_perks_changed(false)
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
	if place in ["island", "club", "arena", "course"]:
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
			_enter_arena(_colosseum.ticket_count() - 1, PackedStringArray())
		"course":
			_go_to_course()
		_:
			return "Unknown place %s. Places: island, club, arena, course, fantasy (inside it also: %s)." % [place, ", ".join(_fantasy.place_names()) if _fantasy != null else "its regions and towns"]
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
		_smoke.left = clampf(float(extra.get("cigarette_left", 0.0)), 0.0, _smoke.full())
		_songs.from_list(extra.get("songs"))
		_stats.from_dict(extra.get("stats"))
		_course.best = maxf(float(extra.get("course_best", 0.0)), 0.0) if (extra.get("course_best") is float or extra.get("course_best") is int) else 0.0
		_bank.from_dict(extra.get("bank"), _player.inventory)
		_cards.from_dict(extra.get("tcg"), CardDb.from_files())
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
	if _perks != null and _player.inventory.holster_count != _holsters_due():
		_perks_changed(false)
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
		var extra := {"coins": _wallet.balance, "jackpot": _jackpot, "progress": _progress.to_dict(), "score": _score.to_dict(), "ammo": _player.pools.to_dict(), "knife": _player.knife, "best_round": _best_round, "bank": _bank.to_dict(_player.inventory), "cigarette_left": _smoke.left, "songs": _songs.to_list(), "course_best": _course.best, "stats": _stats.to_dict(), "tcg": _cards.to_dict()}
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
	return not _in_arena and not _in_fantasy and (_near(_painting_fantasy, PAINTING_RANGE) or (_hub_painting.is_finite() and _near(_hub_painting, PAINTING_RANGE)))


func _near_fantasy_exit() -> bool:
	return _in_fantasy and _near(_fantasy_exit, PAINTING_RANGE)


# Text for the E prompt, or "" when nothing is in reach.
func _prompt() -> String:
	var key := InputSetup.label(settings, "interact")
	if _inventory_screen.visible or _customizer.visible or _card_screen.visible or _slot_screen.visible or _trade_screen.visible or _board.visible or (music_menu != null and music_menu.visible) or _games.is_open() or _tcg.is_open() or _ptables.is_open() or _shop.is_open() or _flight_t >= 0.0:
		return ""
	if _seat >= 0:
		if _seat == 0:
			return "At the tiller: %s / %s sail, %s / %s turn.  [%s] Get off" % [_key("move_forward"), _key("move_back"), _key("move_left"), _key("move_right"), key]
		return "Aboard the %s.  [%s] Get off" % [String(_boat.cfg["name"]), key]
	if _player.downed:
		if _out:
			return "Watching %s. You are back when the next round starts.  [%s] next player" % [net.roster.get(_watched, "the island"), InputSetup.label(settings, "shoot")]
		return "DOWN: a teammate can help you up (%d s)" % ceili(maxf(_down_until - _time, 0.0))
	if _revive_target != 0:
		return "[hold %s] Help %s up%s" % [key, net.roster.get(_revive_target, "your teammate"), "" if _revive_hold <= 0.0 else "  %d %%" % roundi(_revive_hold / float(_rounds.config()["downs"]["hold"]) * 100.0)]
	if _time < _trade_ask_until:
		return "[%s] Trade with %s  (ignore it to say no)" % [key, _trade_asker]
	if _hub_near_button():
		return "[%s] Press the big red button" % key
	if _pack != null and _near(_pack.global_position, DroppedPack.REACH):
		return "[%s] Take your things back (%d)" % [key, InventoryState.bundle_size(_pack.bundle)]
	if _quest_use_here() != "":
		return "[%s] %s" % [key, _quest.line(_quest_use_here(), "what") if _quest.step > 0 else "Look at the book in the sand"]
	if _jukebox != null and _near(_jukebox.global_position, Jukebox.REACH):
		return "[%s] The jukebox" % key
	if _boat_here():
		if _boat.aboard() >= _boat.seats.size():
			return "The %s is full." % String(_boat.cfg["name"])
		return "[%s] Climb aboard the %s%s" % [key, String(_boat.cfg["name"]), " and take the tiller" if _boat.helm() == 0 else ""]
	if _box_here():
		match _box.state:
			"idle":
				return "[%s] Mystery box (%d points)" % [key, int(_box.cfg["price"])]
			"offer":
				if _box_owner == _my_id():
					return "[%s] Take the %s" % [key, GunStats.display_name(_player.gun_db, _box_gun)]
				return "%s: for whoever spun the box" % GunStats.display_name(_player.gun_db, _box_gun)
			_:
				return "The box is spinning ..."
	if _at_upgrade():
		return _upgrade_prompt(key)
	var lever := _trap_at(_player.global_position) if _island_side() else -1
	if lever >= 0:
		var trap_name := String(_trap_cfg["traps"][lever]["name"])
		if not _power.on:
			return "%s: no power" % trap_name
		if _traps.running(lever, _time):
			return "%s is running (%d s)" % [trap_name, ceili(_traps.left(lever, _time))]
		if _traps.wait(lever, _time) > 0.0:
			return "%s cools down (%d s)" % [trap_name, ceili(_traps.wait(lever, _time))]
		return "[%s] Switch on the %s (%d points)" % [key, trap_name, int(_trap_cfg["traps"][lever]["price"])]
	var perk := _perk_here()
	if perk != "":
		if not _power.on:
			return "%s: no power. The switch is built on %s from %d parts lying on %s." % [_perks.name_of(perk), _land.islands[_land.island_near(_bench_spot.x, _bench_spot.y)]["name"], _part_spots.size(), _land.islands[_land.island_near(_part_spots[0].x, _part_spots[0].y)]["name"]]
		if _perks.has(perk):
			return "%s: you carry it" % _perks.name_of(perk)
		if perk == "second_wind" and _second_wind_used:
			return "%s: sold out for this run" % _perks.name_of(perk)
		if _perks.refusal(perk) == "limit":
			return "You carry %d perks already" % _perks.limit()
		return "[%s] %s (%d points): %s" % [key, _perks.name_of(perk), _perks.price(perk), _perks.desc(perk)]
	var thing := _power_thing_at(_player.global_position) if _island_side() else -1
	if thing == NetRounds.SWITCH:
		if _power.all_found():
			return "[%s] Build the switch and throw it" % key
		return "The power switch needs %d parts (%d found)." % [_part_spots.size(), _power.found_count()]
	if thing >= 0:
		return "[%s] Take the %s (part of the power switch)" % [key, _power_cfg["parts"][thing]["name"]]
	var piece := _build_thing_at(_player.global_position) if _island_side() else -1
	if piece >= 0:
		var what := BuildState.thing_of(piece)
		var built_name: String = _builds.names[what]
		if BuildState.part_of(piece) != BuildState.BENCH:
			return "[%s] Take the %s (part of the %s)" % [key, _build_cfg["things"][what]["parts"][BuildState.part_of(piece)]["name"], built_name]
		if _builds.built(what):
			return "[%s] Take a %s" % [key, built_name]
		if _builds.all_found(what):
			return "[%s] Build the %s" % [key, built_name]
		return "The %s needs %d parts (%d found)." % [built_name, _builds.part_count(what), _builds.found_count(what)]
	var window := _window_here()
	if window >= 0 and _shelters.rules.boards[window] < _shelters.rules.full():
		return "[hold %s] Nail a board back (%d of %d)" % [key, _shelters.rules.boards[window], _shelters.rules.full()]
	var board := _wall_buy_here()
	if board >= 0:
		var body := String(_land.wall_buys[board]["gun"])
		if not _holds_body(body):
			return "[%s] Buy the %s (%d points)" % [key, _player.items.item_name(body), int(_land.wall_buys[board]["price"])]
		if _player.pools.is_full(body):
			return "%s: your ammo is full" % _player.items.item_name(body)
		return "[%s] Ammo for the %s (%d points)" % [key, _player.items.item_name(body), _land.ammo_price(board)]
	var blocked := _debris_here()
	if blocked >= 0:
		return "[%s] Clear the way to %s (%d points)" % [key, _land.far_side(blocked, _player.global_position.x - Island.CENTER.x, _player.global_position.z - Island.CENTER.z), _land.price(blocked)]
	if not _in_arena and not _in_fantasy and _near(_bank_pos, BankBox.REACH):
		return "[%s] Open the bank: what is in it is safe when you go down (%d of %d slots used)" % [key, _bank.used(), _bank.capacity()]
	if _near(Lifeguard.POS, LIFEGUARD_RANGE):
		return "[%s] Talk to the lifeguard: change your look" % key
	var drop := _field.nearest(_player.global_position)
	if not drop.is_empty():
		return "[%s] Pick up %s" % [key, _player.items.item_name(String(drop["item"])) if drop.has("item") else GunStats.display_name(_player.gun_db, drop["gun"])]
	var partner := _trade_target()
	if partner != 0:
		return "[hold %s] Trade with %s" % [key, net.roster[partner]]
	var vendor := _vendor_near()
	if not vendor.is_empty():
		return "[%s] Buy a %s (%d chips) - a random rolled gun, %s or better" % [key, vendor["name"], int(vendor["price"]), vendor["min_tier"]]
	if _slot_near() != null:
		return "[%s] Play the slot machine (free chips)" % key
	var table := _games.spot_near(_player.global_position)
	if table != "":
		return "[%s] Sit at the %s table (free chips)" % [key, table]
	if _tcg.spot_near(_player.global_position):
		return "[%s] Play You got me Lobster? against the House Dealer (a win pays chips)" % key
	if _ptables.near(_player.global_position) >= 0:
		return "[%s] %s" % [key, _ptables.prompt(_ptables.near(_player.global_position))]
	if _shop.near(_player.global_position):
		return "[%s] Card machine: packs, boxes and starter decks" % key
	if _near_pachinko():
		return "[%s] Launch a pachinko ball (%d chips, hold to keep firing): fire when the marker is on the gold line" % [key, _pachinko.ball_cost()]
	var food: String = _crow_cfg["food_item"]
	var needed: int = int(_crow_cfg["worms_needed"])
	if _near(_crow_a_pos, CROW_RANGE):
		if _player.inventory.count_of(food) > 0:
			return "[%s] Feed the crow a %s (%d/%d)" % [key, _player.items.item_name(food), _fed, needed]
		return "The crow wants %s (%d/%d fed)" % [_player.items.item_name(food), _fed, needed]
	if _near(_crow_b_pos, CROW_RANGE):
		return "[%s] Ride the crow home" % key
	if _island_side() and _near(_course_door, COURSE_DOOR_REACH):
		return "[%s] The hop course%s" % [key, ("  (your best %s)" % CourseRules.clock(_course.best)) if _course.best > 0.0 else ""]
	if _course_exit_here():
		return "[%s] Back to the islands" % key
	if _near_painting():
		return "[%s] The colosseum: buy a ticket for the party" % key
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
	if _hub_near_button():
		net.hub.press_button()
	elif _seat >= 0:
		_leave_boat(false)
	elif _time < _trade_ask_until:
		_trade_ask_until = 0.0
		net.trade.answer(true)
	elif _quest_use_here() != "":
		_quest_try("use", 0)
	elif _jukebox != null and _near(_jukebox.global_position, Jukebox.REACH):
		_open_jukebox()
	elif _boat_here():
		_board_boat()
	elif _pack != null and _near(_pack.global_position, DroppedPack.REACH):
		_take_pack()
	elif _box_here():
		_use_box()
	elif _at_upgrade():
		_upgrade(false)
	elif _island_side() and _trap_at(_player.global_position) >= 0:
		_use_trap(_trap_at(_player.global_position))
	elif _perk_here() != "":
		_buy_perk(_perk_here())
	elif _island_side() and _power_thing_at(_player.global_position) >= 0:
		_use_power_thing(_power_thing_at(_player.global_position))
	elif _island_side() and _build_thing_at(_player.global_position) >= 0:
		_use_build_thing(_build_thing_at(_player.global_position))
	elif _island_side() and _near(_course_door, COURSE_DOOR_REACH):
		travel("course")
	elif _course_exit_here():
		travel("island")
	elif _wall_buy_here() >= 0:
		_buy_from_wall(_wall_buy_here())
	elif _debris_here() >= 0:
		_buy_debris(_debris_here())
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
	elif _tcg.spot_near(_player.global_position):
		_tcg.open()
	elif _ptables.near(_player.global_position) >= 0:
		_ptables.open(_ptables.near(_player.global_position))
	elif _shop.near(_player.global_position):
		_shop.open()
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
		_open_board()
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
		_player_hud.notice("The casino tops you up to %d free chips." % _wallet.balance)
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
		message = "You win %d chips!" % won
	if result["jackpot_won"]:
		big = true
		_progress.count("jackpots", 1)
		_progress_notices(0)
		_jackpot = _slot_math.jackpot_seed
		message = "JACKPOT!  +%d chips" % won
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
	var busy: bool = _customizer.visible or _slot_screen.visible or _games.is_open() or _tcg.is_open() or _ptables.is_open() or _shop.is_open() or _inventory_screen.visible
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
			_player_hud.notice("The casino tops you up to %d free chips." % _wallet.balance)
		else:
			_player_hud.notice("Not enough chips (a ball costs %d)." % cost)
		return
	if _pachinko.launch():
		_wallet.spend(cost)
		_coins_dirty = true
	else:
		_player_hud.notice("The board is full, wait for balls to land.")


func _on_pachinko_landed(_pocket: int, coins: int, pocket_name: String) -> void:
	if coins > 0:
		_wallet.add(coins)
		_player_hud.notice("%s: +%d chips" % [pocket_name, coins])
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
		_player_hud.notice("A %s costs %d chips (you have %d)." % [crate["name"], price, _wallet.balance])
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
	if drop.has("item"):  # a piece of armour, or worms from an island boss
		var id := String(drop["item"])
		var count := int(drop.get("count", 1))
		var left := int(_player.inventory.add(id, count))
		if left >= count:
			_player_hud.notice("Inventory full: make room first.")
			return
		_field.take(drop)
		if left > 0:  # what did not fit stays lying
			_field.spawn_item(id, _player.items.item_name(id), Color(1.0, 0.6, 0.7), _player.global_position + _player.global_basis.z * -1.0, left)
		save_profile()
		_player_hud.notice("Picked up %s%s" % [_player.items.item_name(id), "" if count - left <= 1 else " x%d" % (count - left)])
		return
	if _player.inventory.add_gun(drop["gun"]):
		var gun: Dictionary = _field.take(drop)
		_stats.add("guns_picked_up")
		_player.refresh_held()
		save_profile()
		_player_hud.notice("Picked up %s" % GunStats.display_name(_player.gun_db, gun))
	else:
		_player_hud.notice("Inventory full: make room first.")


# An enemy died: roll its gun drops (wave luck, elite and boss floors) and drop them where it fell.
func _on_enemy_killed(where: Vector3, enemy_id: String, elite: String, wave: int) -> void:
	_player.on_enemy_killed(elite, enemy_id)
	var lucky := _rng.randf() < _perks.num("double_kill_chance", 0.0)  # Lucky Strike: this kill pays double
	if lucky:
		_score.mult *= 2
	var by_gun := String(_score.blow) != "melee" and String(_score.blow) != "other" and _player.hand_index() >= 0  # (read before kill() resets nothing: the blow is still ours)
	if String(_score.blow) != "other":  # our kill (online somebody else's is "other"): the record
		_count_kill(enemy_id, elite, String(_score.blow))
	var paid := _score.kill()  # paid by how the blow landed (the player sets `blow` around its hits); nothing in Aurelind
	var in_hand_gun: Dictionary = _player.inventory.holster_gun(_player.hand_index()) if by_gun else {}
	if by_gun and paid > 0 and GunGen.count_kill(in_hand_gun):
		_player.refresh_wkills()  # W kills: the gun in hand counts it
		_stats.best("wkills_best", float(in_hand_gun["wkills"]))
	if lucky:
		_score.mult = maxi(_score.mult >> 1, 1)
	if paid > 0 and _player.hand_index() >= 0 and _rng.randf() < _perks.num("ammo_chance", 0.0):  # Scavenger: rounds for the gun in hand
		var in_hand: String = _player.inventory.holster_body(_player.hand_index())
		if in_hand != "":
			_player.pools.give(in_hand, ceili(float(_player.pools.size_of(in_hand)) * _perks.num("ammo_share", 0.0)))
	var kill_counters: Array = ["kills"]
	var xp_kind := "kill"
	if elite != "":
		kill_counters.append("elite_kills")
		xp_kind = "elite"
	if enemy_id == "boss" or enemy_id.begins_with("boss_"):
		kill_counters.append("boss_kills")
		xp_kind = "boss"
	var island_kill: bool = is_instance_valid(_director.last_killed) and _director.last_killed.has_meta("island")
	var arena_kill: bool = is_instance_valid(_director.last_killed) and _director.last_killed.has_meta("arena")  # one of a run's waves (ours, or the host's shown here)
	var guns: Array = []  # the fantasy world has its own drops; the island's enemies drop no guns
	if arena_kill or (_in_arena and not island_kill):
		if _in_arena:  # every player in the run rolls his own loot for every death he sees (a host who is not in the run: none)
			guns = _colosseum_drops(where, enemy_id, elite != "", wave)
	elif not _in_fantasy and not island_kill:
		guns = DropRules.roll_drops(_player.gun_db, _drops_cfg, _rng, enemy_id, elite != "", wave, _luck_mult())
	if not enemy_id.begins_with("boss") and DropRules.pony_roll(_drops_cfg, _rng):  # the one gun any trash anywhere can leave
		guns.append(GunGen.generate(_player.gun_db, _rng, 0.0, "", "pony"))
	if island_kill and _quest_host():  # the main quest: its boss, or a kill by the brine jars
		if _director.last_killed.has_meta("quest_boss") and _quest.boss_killed():
			_quest_advance()
		elif _quest.kind() == "kills" and Vector2(where.x - Island.CENTER.x, where.z - Island.CENTER.z).distance_to(_quest_spots[String(_quest.current()["id"])]) <= float(_quest.current()["radius"]):
			if _quest.killed_near():
				_quest_advance()
			else:
				_show_quest()
				if net != null:
					net.rounds.tell_quest(_quest.to_dict(), -1)
	if island_kill and enemy_id.begins_with("boss"):  # worms (data/island_rounds.json boss.drops): every machine that sees the boss die drops its player's own
		var row := 0
		for item_id: String in _rounds.rules.boss_drops():
			row += 1
			_field.spawn_item(item_id, _player.items.item_name(item_id), Color(1.0, 0.6, 0.7), where + Vector3(-0.8 * float(row), 0.0, 0.5), int(_rounds.rules.boss_drops()[item_id]))
	if island_kill and _rounds.active and (enemy_id.begins_with("boss") or not _blasting):  # alone or hosting: maybe a power-up, always from a boss
		var power := _powerups.roll_drop(_rng, enemy_id.begins_with("boss"), _perks.num("power_drop_mult", 1.0))
		if power != "":
			_drop_power(power, where)
	for i in guns.size():
		var gun: Dictionary = guns[i]
		_field.spawn(gun, where + Vector3(0.6 * float(i), 0.0, 0.0))
		var tier := String(gun["tier"])
		if tier == "rainbow" or tier == "pony":
			_player_hud.notice("%s DROP!" % String(_player.gun_db.tier(tier)["name"]).to_upper())
			kill_counters.append("rare_drops")
			_stats.add("rare_drops")
	_award(xp_kind, kill_counters)


# A kill in the colosseum: the guns it leaves by the wave's loot (core/colosseum_rules.gd); armour and the last
# boss's treasure are dropped here as well.
func _colosseum_drops(where: Vector3, enemy_id: String, elite: bool, wave: int) -> Array:
	var forced: bool = is_instance_valid(_director.last_killed) and _director.last_killed.has_meta("forced_elite")  # All Elite's trait is not an elite's drop
	var kind := "boss" if enemy_id.begins_with("boss") else ("elite" if (elite and not forced) else "trash")
	if _run_fx.has("death_blast_radius"):  # Bad Blood: it blows up where it fell
		_explosives.show_flash(where, float(_run_fx["death_blast_radius"]))
		if _player.global_position.distance_to(where) <= float(_run_fx["death_blast_radius"]):
			_player.struck_from = where
			_player.take_damage(float(_run_fx["death_blast_damage"]), "fire")
	var loot := _luck_mult() * _colosseum.loot_mult(_run_mods)
	var guns: Array = []
	for tier: String in _colosseum.kill_tiers(_rng, wave, kind, loot):
		guns.append(GunGen.generate(_player.gun_db, _rng, 0.0, "", tier))
	var things: Array[String] = []
	if _colosseum.armour_drops(_rng, kind, loot):
		var pieces := _player.items.armour_drops()
		var piece := pieces[_rng.randi_range(0, pieces.size() - 1)]
		var rare := "%s+%s" % [piece, String(_colosseum.cfg["loot"]["armour"]["slot_trait"])]
		things.append(rare if (_colosseum.armour_has_slot(_rng) and _player.items.has_item(rare)) else piece)
	var treasure := _colosseum.treasure(_rng, wave, kind, loot)
	if treasure != "":
		things.append(treasure)
		_player_hud.callout(_player.items.item_name(treasure), Color(1.0, 0.85, 0.3))
	for i in things.size():
		var tint: Array = _player.items.stats(things[i]).get("color", [0.8, 0.8, 0.82])
		_field.spawn_item(things[i], _player.items.item_name(things[i]), Color(tint[0], tint[1], tint[2]), where + Vector3(0.0, 0.0, 0.7 * float(i + 1)))
	return guns


# Gun luck multiplier from Fortune points and the Lucky Find trait.
func _luck_mult() -> float:
	return 1.0 + _progress.bonus("luck_pct") / 100.0


func _open_chest() -> void:
	_reward.open_chest()
	_award("chest", ["chests"])
	_stats.add("chests")
	var found: Array[String] = []
	var lost := false
	for drop in LootRoll.roll(_loot_tables["arena_chest"], _rng):
		var left: int = _player.inventory.add(drop["id"], drop["count"])
		lost = lost or left > 0
		found.append("%s x%d" % [_player.items.item_name(drop["id"]), drop["count"] - left])
	for tier: String in _colosseum.chest_tiers(int(_colosseum.ticket(_run_ticket)["waves"]), _run_mods):  # by the ticket: one tier above its last wave
		var gun := GunGen.generate(_player.gun_db, _rng, 0.0, "", tier)
		if _player.inventory.add_gun(gun):
			found.append(GunStats.display_name(_player.gun_db, gun))
		else:
			lost = true
	var waves := int(_colosseum.ticket(_run_ticket)["waves"])
	var smokes := _smoke.chest_count(waves, int(_colosseum.ticket(_colosseum.ticket_count() - 1)["waves"]))
	if smokes > 0:
		var left_over: int = _player.inventory.add(String(_smoke.cfg["item"]), smokes)
		lost = lost or left_over > 0
		if left_over < smokes:
			found.append("%s x%d" % [_player.items.item_name(String(_smoke.cfg["item"])), smokes - left_over])
	_player.refresh_held()
	save_profile()
	_player_hud.notice("Found: " + ", ".join(found) + ("  (inventory full, some was left behind)" if lost else ""))


# --- the colosseum: a run is bought at the painting (game/colosseum_board.gd), core/colosseum_rules.gd decides ---

func _open_board() -> void:
	_board.open(_score.points)
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_board() -> void:
	_board.close()
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# "Go in" on the board: the buyer pays and the whole party goes. Online the host sends everybody.
func _on_ticket_chosen(ticket: int, mods: PackedStringArray) -> void:
	var price := int(_colosseum.ticket(ticket)["price"])
	if not _score.can_afford(price):
		_player_hud.notice("That ticket costs %d points (you have %d)." % [price, _score.points])
		return
	_close_board()
	if net != null and net.rounds.is_client():
		net.rounds.ask_run(ticket, mods)
		return
	_start_run(ticket, mods, _my_id())
	if net != null:
		net.rounds.tell_run(ticket, mods, _my_id())


# The party goes into the colosseum: whoever bought the ticket pays; everybody on the islands and on his feet goes.
func _start_run(ticket: int, mods: PackedStringArray, buyer: int) -> void:
	if ticket < 0 or ticket >= _colosseum.ticket_count():
		return
	var entry: Dictionary = _colosseum.ticket(ticket)
	if buyer == _my_id():
		_score.spend(int(entry["price"]))
		save_profile()
	run_note = "arena %s, aurelind %s, down %s, flying %s, on the islands %s" % [_in_arena, _in_fantasy, _player.downed, _flight_t >= 0.0, _on_island(_player.global_position)]
	if _in_arena or _in_fantasy or _player.downed or _flight_t >= 0.0 or not _on_island(_player.global_position):
		if net != null and net.can_send() and net.is_host() and not _director.running():  # the run is the host's, also when the host stays out of it
			_run_ticket = ticket
			_run_mods = mods
			_director.run_fx = _colosseum.effects(mods)
			_director.shared_run = true
			_director.start(int(entry["waves"]))
		return  # not there to go along
	if _seat >= 0:
		_leave_boat(true)
	if _board.visible:
		_close_board()
	_stats.add("colosseum_runs")
	_enter_arena(ticket, mods)
	_player_hud.notice("%s: %d waves%s" % [String(entry["name"]), int(entry["waves"]), "" if buyer == _my_id() else " (%s bought the ticket)" % String(net.roster.get(buyer, "a teammate"))])


# Into the arena for a run of that ticket. Dying there sends you back to the island with nothing lost.
func _enter_arena(ticket: int, mods: PackedStringArray) -> void:
	_run_ticket = ticket
	_run_mods = mods
	_in_arena = true
	_player.pools.fill_all()  # every colosseum run starts with full pools
	_set_run_fx(_colosseum.effects(mods))
	var place := 0  # online the party stands side by side, not inside each other
	if net != null and net.can_send():
		var ids: Array = net.roster.keys()
		ids.sort()
		place = maxi(ids.find(_my_id()), 0)
	_player.teleport(ARENA_SPAWN + Vector3(float(place % 3 - 1) * 2.2, 0.0, float(floori(float(place) / 3.0)) * 2.2), 0.0)
	if net != null and net.rounds.is_client():
		_director.follow_run(int(_colosseum.ticket(ticket)["waves"]))  # online the run is the host's: its waves are shown here
	elif not (_director.running() and _director.shared_run):  # (a host already running the party's run just joins it)
		_director.shared_run = net != null and net.can_send()
		_director.start(int(_colosseum.ticket(ticket)["waves"]))
	_player_hud.play_fade()


# A run's modifiers take hold (or, with {}, let go): on us, on the HUD, on the arena's light and air. Enemies and
# waves read `_run_fx` through the wave director.
func _set_run_fx(fx: Dictionary) -> void:
	var had_look := _run_fx.has("fog") or _run_fx.has("blackout")
	_run_fx = fx
	_director.run_fx = fx
	_player.set_run_fx(fx)
	_player_hud.blind = fx.has("blind")
	_bars.visible = not fx.has("hide_bars")
	_fuse_wave = 0
	_still = 0.0
	if fx.has("ammo_start"):  # Dry Mags: part of every pool stays outside
		for body: String in _player.pools.bodies():
			_player.pools.take(body, floori(float(_player.pools.left(body)) * (1.0 - float(fx["ammo_start"]))))
	if had_look or fx.has("fog") or fx.has("blackout"):
		apply_settings()  # sky, fog and sun as the look has them (and the islands' weather lets go of them)
	if fx.has("fog"):
		_render_style.env.fog_enabled = true
		_render_style.env.fog_density = float(fx["fog"])
		_render_style.env.fog_light_color = Color(0.04, 0.04, 0.05) if fx.has("blackout") else Color(0.62, 0.6, 0.55)
		_render_style.env.fog_sky_affect = 1.0
		_render_style.env.fog_aerial_perspective = 0.0
	if fx.has("blackout"):
		_render_style.sun.light_energy *= 0.03
		_render_style.env.ambient_light_energy *= 0.08
		_render_style.env.background_energy_multiplier = 0.03
		if _torch == null:
			_torch = SpotLight3D.new()
			_torch.spot_range = 26.0
			_torch.spot_angle = 34.0
			_torch.light_energy = 6.0
			_torch.shadow_enabled = false
			_player.hand_parent().add_child(_torch)
	elif _render_style.env.background_energy_multiplier != 1.0:
		_render_style.env.background_energy_multiplier = 1.0
	if _torch != null:
		_torch.visible = fx.has("blackout")
	if _ring != null:
		_ring.visible = false
	_ring_radius = 0.0


# Every frame of a run with modifiers: the ones that need a clock (Short Fuse, Toxic Sand, Closing Ring).
# --- the colosseum run online: the host's wave director runs it for everybody (game/net_rounds.gd shows it) ---

const RUN_REACH := 90.0  # metres from the arena's middle (the world's origin) that count as being in the run
const RUN_EMPTY_SECONDS := 4.0
var _run_retarget := 0.0
var _run_empty := 0.0


# The bodies in the colosseum: ours while we are in the run, and the others' standing in the arena.
func _run_bodies() -> Array:
	var out: Array = []
	if _in_arena and not _player.downed and _player.health.hp > 0.0:
		out.append(_player)
	if net != null and net.can_send():
		for body: Node3D in net.target_nodes():
			if Vector2(body.global_position.x, body.global_position.z).length() < RUN_REACH:
				out.append(body)
	return out


# Hosting a run: every wave enemy goes after the nearest body in the arena; nobody left in it ends the run.
func _host_run(delta: float) -> void:
	if not _director.running() or not _director.shared_run or not _director.follow.is_empty() or net == null or not net.can_send() or not net.is_host():
		_run_empty = 0.0
		return
	_run_retarget -= delta
	if _run_retarget > 0.0:
		return
	_run_retarget = 0.5
	var bodies := _run_bodies()
	if bodies.is_empty():
		_run_empty += 0.5
		if _run_empty >= RUN_EMPTY_SECONDS and not _in_arena:
			_director.reset()  # everybody died or went home: the run is over
		return
	_run_empty = 0.0
	for enemy: Variant in (_director.enemy_list() as Array):
		if not is_instance_valid(enemy) or not (enemy as Node).has_meta("arena") or bool((enemy as Node).get("puppet")):
			continue
		var best: Node3D = bodies[0]
		for body: Node3D in bodies:
			if body.global_position.distance_squared_to((enemy as Node3D).global_position) < best.global_position.distance_squared_to((enemy as Node3D).global_position):
				best = body
		(enemy as Node3D).call("set_target", best)


func _run_modifiers(delta: float) -> void:
	var wave := _director.wave_number()
	if _run_fx.has("wave_seconds") and wave > 0 and _director.follow.is_empty():  # (online the host's machine sends the late pack in)
		if wave != _fuse_wave:
			_fuse_wave = wave
			_fuse_left = float(_run_fx["wave_seconds"])
			_fuse_late = false
		elif _director.enemies_left() > 0 and not _fuse_late:
			_fuse_left -= delta
			if _fuse_left <= 0.0:  # too slow: elites more, of whatever this wave is made of
				_fuse_late = true
				var pack: Array[String] = []
				var kinds: Array = (_director.enemy_list() as Array).filter(func(e: Variant) -> bool: return is_instance_valid(e) and not String((e as Node).get("enemy_id")).begins_with("boss"))
				for i in int(_run_fx.get("late_pack", 0)):
					pack.append(String((kinds[i % kinds.size()] as Node).get("enemy_id")) if not kinds.is_empty() else "chaser")
				_director.send_in(pack)
				_player_hud.notice("Too slow: %d more come in." % pack.size())
	if _run_fx.has("still_seconds"):
		_still = _still + delta if Vector2(_player.velocity.x, _player.velocity.z).length() < 0.5 else 0.0
		if _still >= float(_run_fx["still_seconds"]):
			_still -= 1.0  # and again every second we keep standing
			_player.status.apply(String(_run_fx["still_element"]), 0.0)
			_player_hud.notice("The sand poisons you: keep moving.")
	if _run_fx.has("ring_start") and wave > 0:
		var last := maxi(_director.wave_count() - 1, 1)
		var radius := lerpf(float(_run_fx["ring_start"]), float(_run_fx["ring_end"]), clampf(float(wave - 1) / float(last), 0.0, 1.0))
		if not is_equal_approx(radius, _ring_radius):
			_ring_radius = radius
			_show_ring(radius)
		_ring_tick += delta
		if _ring_tick >= 0.5:
			if Vector2(_player.global_position.x, _player.global_position.z).length() > radius:
				_player.take_damage(float(_run_fx["ring_dps"]) * _ring_tick, "fire")
			_ring_tick = 0.0


# The ring of fire at that radius round the arena's middle: 64 flame cones in one MultiMesh.
func _show_ring(radius: float) -> void:
	if _ring == null:
		var flame := CylinderMesh.new()
		flame.top_radius = 0.0
		flame.bottom_radius = 0.35
		flame.height = 1.6
		flame.radial_segments = 6
		flame.rings = 1
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.5, 0.12)
		flame.material = glow
		var flames := MultiMesh.new()
		flames.transform_format = MultiMesh.TRANSFORM_3D
		flames.mesh = flame
		flames.instance_count = 64
		_ring = MultiMeshInstance3D.new()
		_ring.multimesh = flames
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	for i in 64:
		var angle := TAU * float(i) / 64.0
		_ring.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(cos(angle) * radius, 0.8, sin(angle) * radius)))
	_ring.visible = true


func _on_player_died() -> void:
	_progress.count("deaths", 1)
	_stats.add("deaths")
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
		_player.downed = _out  # out = untouchable and unseen until the next round starts, watching the others
		if _out:
			_watch_next()


# --- online: down, helped up, out (game/net_downs.gd keeps the party's states on the host) ---

# Asked by the player the moment its health runs out: true = lie down and wait for a teammate instead of dying.
func _goes_down() -> bool:
	if _in_arena or _in_fantasy or not _on_island(_player.global_position) or _island_round() <= 0:
		return false
	return (net != null and net.can_send()) or (_perks.has("second_wind") and not _second_wind_used)  # online; or alone with the one self-revive


func _island_round() -> int:
	return net.rounds.round_number if net != null and net.rounds.is_client() else _rounds.rules.number


func _on_went_down() -> void:
	_score.downs += 1
	_stats.add("downs")
	if net == null or not net.can_send():  # alone with Second Wind: up again by ourselves in a moment, this once
		_second_wind_used = true
		_self_revive_at = _time + _perks.num("self_revive_seconds", 3.0)
		_down_until = INF
		_lose_perks()
		_player_hud.notice("Second Wind: hold on ...")
		return
	_lose_perks()
	_down_until = _time + float(_rounds.config()["downs"]["seconds"])
	net.downs.report("down")


# Nobody helped in time.
func _bleed_out() -> void:
	_out = true
	net.downs.report("out")
	_player.finish_off()  # -> _on_player_died: the backpack is left and we watch the others
	_player_hud.notice("Nobody came. You are out until the next round.")


# Out of the round: the camera goes to the next teammate who is still standing on the islands (to nobody when there
# is none: then we look out from the spawn).
func _watch_next() -> void:
	var ids: Array = []
	for id: int in net.roster:
		var body: Node3D = net.player_node(id)
		if id != net.my_id() and body != null and net.downs.state_of(id) == "up" and _on_island(body.global_position):
			ids.append(id)
	ids.sort()
	if ids.is_empty():
		_watched = 0
		_player.watch(null)
		return
	var at := ids.find(_watched)
	_watched = ids[(at + 1) % ids.size()]
	_player.watch(net.player_node(_watched))


func _on_revived(share: float) -> void:
	if _player.downed and not _out:
		_player.revive(share)
		_hurt_at = _time
		_player_hud.notice("You are back on your feet.")


func _on_gave_revive() -> void:
	_score.revives += 1
	_stats.add("revives")
	_player_hud.notice("You helped a teammate up.")


# The host ended the run for the whole party: nobody on the islands was left standing.
func _on_party_over(reached: int) -> void:
	var was_there := _player.downed or _out or (not _in_arena and not _in_fantasy and _on_island(_player.global_position))
	var lying := _player.downed and not _out
	var at := _player.global_position
	if _player.downed:
		_player.revive(1.0)
	_out = false
	_player.watch(null)
	if lying:
		_player.teleport(_island_spawn, 0.0)
	if was_there:
		_end_run(reached, at, lying)
	else:
		_player_hud.notice("The party's run on the islands ended in round %d." % reached)
		if _rounds.active:
			_rounds.stop()
		_clear_powers()
		_close_debris()


# Other players lying down are shown lying down; those who are out are not shown at all until they are back.
func _show_downs() -> void:
	for id: int in net.roster:
		var body: Node3D = net.player_node(id)
		if id != net.my_id() and body != null and body.has_method("set_down"):
			body.call("set_down", net.downs.state_of(id) == "down")
			body.visible = net.downs.state_of(id) != "out"
	if _out and (_watched == 0 or net.downs.state_of(_watched) != "up"):
		_watch_next()  # whoever we were watching went down too


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
	if _revive_hold >= float(_rounds.config()["downs"]["hold"]) * _perks.num("revive_mult", 1.0):
		_revive_hold = 0.0
		net.downs.ask_revive(_revive_target)


# --- the island's rounds (game/island_rounds.gd runs them; core/round_rules.gd decides) ---

func _on_island(at: Vector3) -> bool:
	return _land.within(at.x - Island.CENTER.x, at.z - Island.CENTER.z)


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
	_stats.add("island_games_over")
	_game_over.show_run(reached, _best_round, record, PackedStringArray(["Kills %d        Points earned %d" % [_score.kills - _run_kills, _run_earned], "Everything you carried lies in a backpack where you went down." if (drop or _pack != null) else "You were still standing: you keep what you carry."]))
	if drop:
		_drop_pack(at)
	if _rounds.active:
		_rounds.stop()
	_clear_powers()
	_close_debris()
	if _island_side():
		_player.teleport(_island_spawn, 0.0)  # nobody is left behind a way that just closed
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
		var lies := _land.wash_up(at.x - Island.CENTER.x, at.z - Island.CENTER.z)  # went down in the water: it washes up on the sand
		if not _bridged(_land.island_near(lies.x, lies.z)):  # on an island only the boat reaches: the boat is gone with the run, so it washes up at the slipway
			lies = _land.wash_up(_build_benches[_boat_thing].x, _build_benches[_boat_thing].y)
		_place_pack(Island.CENTER + lies, bundle)
	for entry in DataStore.load_json("res://data/player.json")["starting_items"]:
		_player.inventory.add(String(entry[0]), int(entry[1]))
	_player.refresh_held()
	_player.refresh_equipment()
	_inventory_screen.in_hand = _player.hand_index()


# True when a bridge or sandbar goes to this island (the spawn island counts): it can be walked to.
func _bridged(island: int) -> bool:
	if island == 0:
		return true
	for way: Dictionary in _land.bridges:
		if int(way["from"]) == island or int(way["to"]) == island:
			return true
	return false


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
	if _out:  # online: whoever bled out appears again when the next round starts
		_out = false
		_player.watch(null)
		_player.revive(1.0)
		_player.teleport(_island_spawn, 0.0)
		_player_hud.play_fade()
		net.downs.report("up")
		_player_hud.notice("You are back in.")
	_powerups.new_round()
	_shelters.rules.new_round()
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
	var parting := String(_powerups.cfg.get("special_round_end", ""))
	if kind == "special" and _rounds.active and _powerups.has(parting):  # the last one of a special round leaves this
		_drop_power(parting, _director.last_killed.global_position if is_instance_valid(_director.last_killed) else _island_spawn)
	_player_hud.notice("Round %d survived" % number)
	if _island_side():
		_stats.add("island_rounds")
	_sounds.call("play", "sting_round_end")
	save_profile()


# --- wall buys (data/archipelago.json wall_buys; game/wall_buy.gd is the board) ---

# The wall buy our player stands at, -1 = none.
func _wall_buy_here() -> int:
	if _in_arena or _in_fantasy or not _on_island(_player.global_position):
		return -1
	return _land.wall_buy_near(_player.global_position.x - Island.CENTER.x, _player.global_position.z - Island.CENTER.z, WallBuy.REACH)


# True when one of our ready guns is of this body (plain or looted).
func _holds_body(body: String) -> bool:
	for i in _player.inventory.holster_count:
		if _player.inventory.holster_body(i) == body:
			return true
	return false


# Interact at a wall buy: the plain gun with a full pool, or (holding that kind already) its pool refilled for less.
# A bought gun takes a free ready slot, else the place of the gun in hand, which goes into the backpack.
func _buy_from_wall(index: int) -> void:
	var body := String(_land.wall_buys[index]["gun"])
	var owned := _holds_body(body)
	var cost: int = _land.ammo_price(index) if owned else int(_land.wall_buys[index]["price"])
	if owned and _player.pools.is_full(body):
		return
	if not _score.can_afford(cost):
		_player_hud.notice("That costs %d points (you have %d)." % [cost, _score.points])
		return
	if not owned:
		var holster: int = _player.inventory.free_holster()
		if holster < 0:
			holster = maxi(_player.hand_index(), 0)  # knife out: the first gun makes room
			if not _player.inventory.stow_holster(holster):
				_player_hud.notice("Your backpack is full: make room for the gun in your hand first.")
				return
		_player.inventory.add(body, 1)
		_player.pools.fill(body)
		_player.refresh_held()  # it loads itself from the pool ...
		_player.pools.fill(body)  # ... and the pool is full on top of that
		_player.select_hand(holster)
		_inventory_screen.in_hand = _player.hand_index()
		_player_hud.notice("%s bought." % _player.items.item_name(body))
	else:
		_player.pools.fill(body)
		_player_hud.notice("%s: ammo refilled." % _player.items.item_name(body))
	_score.spend(cost)
	_stats.add("wall_buys")
	_sounds.call("play", "wall_buy")
	save_profile()


# --- the ways between the islands (core/archipelago.gd knows which debris is cleared; game/debris_pile.gd shows it) ---

# The closed debris our player stands at, -1 = none.
func _debris_here() -> int:
	if _in_arena or _in_fantasy or not _on_island(_player.global_position):
		return -1
	return _land.debris_near(_player.global_position.x - Island.CENTER.x, _player.global_position.z - Island.CENTER.z)


# Pays for a debris and clears it for everybody. Online the host decides (it checks we stand there) and bills us.
func _buy_debris(index: int) -> void:
	if not _score.can_afford(_land.price(index)):
		_player_hud.notice("Clearing this costs %d points (you have %d)." % [_land.price(index), _score.points])
		return
	if net != null and net.rounds.is_client():
		net.rounds.ask_debris(index)
		return
	_score.spend(_land.price(index))
	_stats.add("debris_cleared")
	_open_debris(index, true)
	if net != null:
		net.rounds.tell_debris(index)


func _open_debris(index: int, show_it: bool) -> void:
	if _land.open(index):
		(_debris[index] as Node).call("set_open", true, show_it)
		if show_it and _island_side():
			_sounds.call("play", "debris_clear")
			_player_hud.notice("The way to %s and back is clear." % _land.islands[int(_land.bridges[index]["to"])]["name"])


# As a client: the host cleared one (ours or somebody else's), or tells us what is open as we arrive.
func _on_debris_opened(index: int, show_it: bool) -> void:
	if index >= 0 and index < _debris.size():
		_open_debris(index, show_it)


# As a client: the host cleared the one we asked for; this is its price.
func _on_debris_billed(index: int) -> void:
	if index >= 0 and index < _debris.size():
		_score.spend(_land.price(index))


# Game over: every way is blocked again and every window is whole.
func _close_debris() -> void:
	_land.close_all()
	for pile: Variant in _debris:
		(pile as Node).call("set_open", false)
	_shelters.rules.board_all()
	_shelters.refresh()
	_power.reset()
	_show_power()
	_box.reset(_rng)
	_box_gun = {}
	_box_node.stand(_flat(_box_spots[0]))
	_traps.reset()
	_lose_perks()
	_second_wind_used = false
	_self_revive_at = -1.0
	_builds.reset()
	_quest.reset()
	_show_quest()
	if _seat >= 0:
		_put_ashore()
	_boat.empty()
	_boat.place(_boat_start, _boat_start_yaw)
	_show_builds()
	_player.shield.drop()
	_player.refresh_held()


# --- perks and the power switch (core/perk_state.gd, core/power_state.gd decide) ---

# A spot of the land as a world position on flat ground, and the way something standing there faces the middle of
# its island.
func _flat(spot: Vector2) -> Vector3:
	return Island.CENTER + Vector3(spot.x, 0.0, spot.y)


func _toward_middle(spot: Vector2) -> float:
	var off: Vector2 = spot - (_land.islands[_land.island_near(spot.x, spot.y)]["at"] as Vector2)
	return atan2(-off.x, -off.y)


# The perk whose machine our player stands at, "" = none.
func _perk_here() -> String:
	if not _island_side():
		return ""
	var at := Vector2(_player.global_position.x - Island.CENTER.x, _player.global_position.z - Island.CENTER.z)
	for id: String in _perk_spots:
		if at.distance_to(_perk_spots[id]) <= float(_perks.cfg["reach"]):
			return id
	return ""


func _buy_perk(id: String) -> void:
	if not _power.on or _perks.refusal(id) != "" or (id == "second_wind" and _second_wind_used):
		return
	if not _score.spend(_perks.price(id)):
		_player_hud.notice("%s costs %d points (you have %d)." % [_perks.name_of(id), _perks.price(id), _score.points])
		return
	_perks.add(id)
	_stats.add("perks_bought")
	_perks_changed(true)
	_sounds.call("play", "perk_buy")
	_player_hud.notice("%s: %s" % [_perks.name_of(id), _perks.desc(id)])


# How many ready gun slots we should have: two, one more with the Third Holster perk, one more with a piece of armour
# that has a holster (several such pieces still give one).
func _holsters_due() -> int:
	return 2 + int(_perks.num("extra_holsters", 0.0)) + (1 if (_player.armor["abilities"] as Array).has("extra_holster") else 0)


# The perks carried changed: everything that reads their numbers follows.
func _perks_changed(heal: bool) -> void:
	_player.pools.bonus_pct = _perks.num("pool_bonus_pct", 0.0)
	var homeless: Array = _player.inventory.set_holster_count(_holsters_due())
	if not homeless.is_empty():  # the extra ready gun found no room in the bag: it lies in a backpack at our feet
		var things: Array = []
		for stack: Dictionary in homeless:
			things.append(_player.inventory.stack_to_saved(stack))
		if _pack != null:
			(_pack.bundle["things"] as Array).append_array(things)
		else:
			_place_pack(_player.global_position, {"things": things})
		_player_hud.notice("No room for the gun of your extra slot: it lies in a backpack.")
	if _player.hand_index() >= _player.inventory.holster_count:
		_player.select_hand(0)
	_player.perks_changed(heal)
	_inventory_screen.in_hand = _player.hand_index()


# Going down or game over: every perk is gone.
func _lose_perks() -> void:
	if _perks.owned.is_empty():
		return
	_perks.clear()
	_perks_changed(false)
	_player_hud.notice("Your perks are gone.")


# What of the power switch lies at a world spot: a part's number, NetRounds.SWITCH at the workbench, -1 = nothing
# (parts already found and a switch already thrown do not count).
func _power_thing_at(at: Vector3) -> int:
	var spot := Vector2(at.x - Island.CENTER.x, at.z - Island.CENTER.z)
	var reach := float(_power_cfg["reach"])
	for i in _part_spots.size():
		if not _power.found[i] and spot.distance_to(_part_spots[i]) <= reach:
			return i
	return NetRounds.SWITCH if (not _power.on and spot.distance_to(_bench_spot) <= reach + 0.6) else -1


# Interact at a part or at the workbench. Online the host does it for the whole party.
func _use_power_thing(thing: int) -> void:
	if thing == NetRounds.SWITCH and not _power.all_found():
		return
	if net != null and net.rounds.is_client():
		net.rounds.ask_power(thing)
		return
	if _power.switch_on() if thing == NetRounds.SWITCH else _power.take(thing):
		_power_changed(thing)
		if net != null:
			net.rounds.tell_power_state(_power.to_bits())


# The power's state as the host says it (as a client; on the host after a client's ask).
func _on_power_bits(bits: int) -> void:
	var was_on := _power.on
	var had := _power.found_count()
	_power.set_bits(bits)
	_power_changed(NetRounds.SWITCH if (_power.on and not was_on) else (0 if _power.found_count() > had else -1))


# Shows the new state; `what` = what just happened (a part's number, SWITCH = it went on, -1 = nothing to tell).
func _power_changed(what: int) -> void:
	_show_power()
	if _power.on and _quest_host() and _quest.power_is_on(true):
		_quest_advance()
	if what < 0 or not _island_side():
		return
	if what == NetRounds.SWITCH:
		_sounds.call("play", "power_on")
		_player_hud.callout("Power on", Color(0.5, 0.95, 1.0))
	else:
		_sounds.call("play", "part_take")
		_player_hud.notice("Power switch: %d of %d parts found." % [_power.found_count(), _part_spots.size()])


# --- buildables: the shield and the boat (core/build_state.gd decides, game/build_site.gd shows) ---

# What of the buildables lies at a world spot, as BuildState.code_of(thing, part): a part not yet found, or a thing's
# bench (while there is something to do there: build it, or take a shield from it). -1 = nothing.
func _build_thing_at(at: Vector3) -> int:
	var spot := Vector2(at.x - Island.CENTER.x, at.z - Island.CENTER.z)
	var reach := float(_build_cfg["reach"])
	for thing in _builds.ids.size():
		var lying: Array = _build_parts[thing]
		for part in lying.size():
			if not _builds.found(thing)[part] and spot.distance_to(lying[part]) <= reach:
				return BuildState.code_of(thing, part)
		if spot.distance_to(_build_benches[thing]) <= reach + 0.6 and (not _builds.built(thing) or (_builds.ids[thing] == "shield" and not _player.shield.owned)):
			return BuildState.code_of(thing, BuildState.BENCH)
	return -1


# Interact at a part or a bench. Finding and building is for the whole party (online the host does it); taking a
# shield from the bench of a built one is each player's own.
func _use_build_thing(code: int) -> void:
	var thing := BuildState.thing_of(code)
	if BuildState.part_of(code) == BuildState.BENCH:
		if _builds.built(thing):
			if _builds.ids[thing] == "shield" and _player.shield.give():
				_sounds.call("play", "part_take")
				_player.refresh_held()
				_player_hud.notice("%s: on your back it stops hits from behind. [%s] holds it up: it stops hits from ahead and [%s] bashes." % [_builds.names[thing], _key("shield"), _key("shoot")])
			return
		if not _builds.all_found(thing):
			return
	if net != null and net.rounds.is_client():
		net.rounds.ask_build(code)
		return
	if _builds.apply(code):
		_builds_changed(code)
		if net != null:
			net.rounds.tell_build_state(_builds.to_bits())


# The buildables' state as the host says it (as a client; on the host after a client's ask).
func _on_build_bits(bits: int) -> void:
	var before := _builds.to_bits()
	_builds.set_bits(bits)
	var fresh := bits & ~before  # what is new: tell about the first new thing
	var at := 0
	var told := -1
	for thing in _builds.ids.size():
		for part in _builds.part_count(thing):
			if told < 0 and (fresh >> at) & 1 == 1:
				told = BuildState.code_of(thing, part)
			at += 1
		if (fresh >> at) & 1 == 1:
			told = BuildState.code_of(thing, BuildState.BENCH)
		at += 1
	_builds_changed(told)


# Shows the new state; `code` = what just happened (a part found, a thing built; -1 = nothing to tell).
func _builds_changed(code: int) -> void:
	_show_builds()
	for thing in _builds.ids.size():
		if _builds.built(thing) and _quest_host() and _quest.built(_builds.ids[thing]):
			_quest_advance()
	if code < 0 or not _island_side():
		return
	var thing := BuildState.thing_of(code)
	if BuildState.part_of(code) == BuildState.BENCH:
		_sounds.call("play", "build_done")
		_player_hud.callout("%s built" % _builds.names[thing], Color(1.0, 0.85, 0.45))
	else:
		_sounds.call("play", "part_take")
		_player_hud.notice("%s: %d of %d parts found." % [_builds.names[thing], _builds.found_count(thing), _builds.part_count(thing)])


func _show_builds() -> void:
	for thing in _builds.ids.size():
		_build_site.show_state(thing, _builds.found(thing), _builds.built(thing))
	_boat_node.visible = _builds.built(_boat_thing)
	if _boat_node.visible:
		_boat_node.show_at(Island.CENTER + Vector3(_boat.x, _land.sea_level, _boat.z), _boat.yaw, _time)


# --- the boat (core/boat_rules.gd decides; alone or hosting we sail it, a client shows what the host says) ---

# The boat in one line, and the sand nearest to it (test scripts).
func boat_note() -> String:
	var shore := _land.wash_up(_boat.x, _boat.z)
	return "built %s at %.1f %.1f yaw %.0f speed %.2f aground %s depth %.2f seats %s our seat %d carried %s | shore %.1f m away on %s" % [str(_builds.built(_boat_thing)), _boat.x, _boat.z, rad_to_deg(_boat.yaw), _boat.speed, str(_boat.aground), _water_depth(_boat.x, _boat.z), str(_boat.seats), _seat, str(_player.carried),
		Vector2(shore.x - _boat.x, shore.z - _boat.z).length(), String(_land.islands[_land.island_near(_boat.x, _boat.z)]["name"])]


func boat_shore() -> Vector3:
	return Island.CENTER + _land.wash_up(_boat.x, _boat.z) + Vector3(0.0, 0.1, 0.0)


# Metres of water at a spot of the land's map: 0 on land, under a bridge and beyond the islands' waters.
func _water_depth(x: float, z: float) -> float:
	if not _land.within(x, z) or _land.deck_at(x, z) >= 0:
		return 0.0
	return _land.sea_level - _land.height_at(x, z)


# True when a world spot is near enough to the built boat to climb aboard (the host asks this about a client).
func _near_boat(at: Vector3) -> bool:
	return _builds.built(_boat_thing) and Vector2(at.x - Island.CENTER.x - _boat.x, at.z - Island.CENTER.z - _boat.z).length() <= float(_boat.cfg["board_reach"])


func _boat_here() -> bool:
	return _seat < 0 and _island_side() and not _player.carried and _near_boat(_player.global_position)


# Interact beside the boat: the first free seat (the tiller first). Online the host seats us.
func _board_boat() -> void:
	if net != null and net.rounds.is_client():
		net.rounds.ask_seat(true)
	elif _boat.sit(_my_id()) < 0:
		_player_hud.notice("The %s is full." % String(_boat.cfg["name"]))
	else:
		_boat_tell = 0.0


# Interact aboard: off onto the nearest sand, when the boat lies close enough to it.
func _leave_boat(anyhow: bool) -> void:
	var shore := _land.wash_up(_boat.x, _boat.z)
	if not anyhow and Vector2(shore.x - _boat.x, shore.z - _boat.z).length() > float(_boat.cfg["land_reach"]):
		_player_hud.notice("Too far from the shore to get off.")
		return
	if net != null and net.rounds.is_client():
		net.rounds.ask_seat(false)
		_ashore_until = _time + 0.8
	_boat.leave(_my_id())
	_boat_tell = 0.0
	_put_ashore()


# We are no longer aboard: onto the sand nearest the boat.
func _put_ashore() -> void:
	_seat = -1
	_player.carried = false
	var shore := _land.wash_up(_boat.x, _boat.z)
	_player.teleport(Island.CENTER + shore + Vector3(0.0, 0.1, 0.0), _player.look_yaw())


# Hosting: a client wants a seat (the host checked that it stands by the boat) or gives its seat up.
func _on_seat_asked(peer: int, aboard: bool) -> void:
	if not _builds.built(_boat_thing):
		return
	if aboard:
		_boat.sit(peer)
	else:
		_boat.leave(peer)
	_boat_tell = 0.0


# As a client: the boat as the host runs it. A big jump (it was just built, or put back) is taken at once.
func _on_boat_state(x: float, z: float, yaw: float, speed: float, seats: PackedInt32Array) -> void:
	_boat_goal = Vector3(x, z, yaw)
	_boat.speed = speed
	if Vector2(x - _boat.x, z - _boat.z).length() > 15.0:
		_boat.place(Vector2(x, z), yaw)
		_boat.speed = speed
	for seat in mini(seats.size(), _boat.seats.size()):
		_boat.seats[seat] = 0 if (seats[seat] == _my_id() and _time < _ashore_until) else seats[seat]


# Every frame while the boat is built: sail it (alone or hosting) or follow the host, show it, and keep whoever of
# us is aboard in his seat. A helmsman's keys are the move keys.
func _run_boat(delta: float) -> void:
	if not _builds.built(_boat_thing):
		return
	var me := _my_id()
	var steering := _boat.helm() == me and _player.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var keys := Vector2(Input.get_axis("move_back", "move_forward"), Input.get_axis("move_left", "move_right")) if steering else Vector2.ZERO
	_boat_tell -= delta
	if net != null and net.rounds.is_client():
		var glide := minf(delta * 8.0, 1.0)
		_boat.x = lerpf(_boat.x, _boat_goal.x, glide)
		_boat.z = lerpf(_boat.z, _boat_goal.y, glide)
		_boat.yaw = lerp_angle(_boat.yaw, _boat_goal.z, glide)
		if _boat.helm() == me and _boat_tell <= 0.0:
			_boat_tell = 0.05
			net.rounds.send_helm(keys.x, keys.y)
	else:
		if _boat.helm() != me:
			keys = _helm_keys if _boat.helm() != 0 else Vector2.ZERO
		var was_aground := _boat.aground
		_boat.step(keys.x, keys.y, delta, _water_depth)
		if _boat.aground and not was_aground and _boat.seat_of(me) >= 0:
			_player_hud.notice("Aground.")
		if net != null and net.can_send() and _boat_tell <= 0.0:
			_boat_tell = 0.1 if (_boat.aboard() > 0 or absf(_boat.speed) > 0.05) else 1.0
			for seat in _boat.seats.size():  # somebody who left the game does not keep a seat
				if _boat.seats[seat] != 0 and _boat.seats[seat] != me and not net.roster.has(_boat.seats[seat]):
					_boat.leave(_boat.seats[seat])
			net.rounds.tell_boat(_boat.x, _boat.z, _boat.yaw, _boat.speed, PackedInt32Array(_boat.seats))
	_boat_node.show_at(Island.CENTER + Vector3(_boat.x, _land.sea_level, _boat.z), _boat.yaw, _time)
	var was := _seat
	_seat = _boat.seat_of(me)
	if _seat < 0:
		if was >= 0:
			_put_ashore()  # the host took our seat away
		return
	if _player.downed or _in_arena or _in_fantasy:
		_leave_boat(true)
		return
	var place := _boat.seat_place(_seat)
	_player.carried = true
	_player.global_position = Island.CENTER + Vector3(place.x, _land.sea_level + place.y, place.z)


# Admin command: a thing built without its parts ("" = all of them); the shield is also put on the typist's back.
func cheat_build(id: String) -> String:
	if net != null and net.rounds.is_client():
		return "Only the host can do that."
	if id != "" and _builds.index_of(id) < 0:
		return "Buildables: %s" % ", ".join(PackedStringArray(_builds.ids))
	for thing in _builds.ids.size():
		if id == "" or _builds.ids[thing] == id:
			for part in _builds.part_count(thing):
				_builds.take(thing, part)
			if _builds.build(thing):
				_builds_changed(BuildState.code_of(thing, BuildState.BENCH))
	if net != null:
		net.rounds.tell_build_state(_builds.to_bits())
	if (id == "" or id == "shield") and _player.shield.give():
		_player.refresh_held()
	return "Built: %s." % (id if id != "" else ", ".join(PackedStringArray(_builds.ids)))


# Admin commands: the power on without the parts; a perk (or all of them) for nothing.
func cheat_power() -> String:
	if net != null and net.rounds.is_client():
		return "Only the host can do that."
	for i in _part_spots.size():
		_power.take(i)
	_power.switch_on()
	_power_changed(NetRounds.SWITCH)
	if net != null:
		net.rounds.tell_power_state(_power.to_bits())
	return "The power is on."


func cheat_perk(id: String) -> String:
	if id != "all" and not _perks.known(id):
		return "Perks: %s" % ", ".join(PackedStringArray(_perks.ids()))
	for perk: String in (_perks.ids() if id == "all" else [id]):
		_perks.add(perk, true)
	_perks_changed(true)
	return "You carry: %s." % ", ".join(PackedStringArray(_perks.owned))


func _show_power() -> void:
	_power_station.show_state(_power.found, _power.on)
	for id: String in _perk_machines:
		(_perk_machines[id] as Node).call("set_powered", _power.on)
	if _upgrade_node.is_inside_tree():
		_upgrade_node.set_powered(_power.on)


# --- the mystery box, the upgrade machine and the traps ---

# Who we are among the players (1 when playing alone).
func _my_id() -> int:
	return net.my_id() if net != null and net.can_send() else 1


func _box_here() -> bool:
	if not _island_side() or _box.state == "moving":
		return false
	return Vector2(_player.global_position.x - Island.CENTER.x, _player.global_position.z - Island.CENTER.z).distance_to(_box_spots[_box.spot]) <= float(_box.cfg["reach"])


# Interact at the box: a spin, or the gun it offers us. Online the host does it.
func _use_box() -> void:
	var action := 0 if _box.state == "idle" else (1 if _box.state == "offer" and _box_owner == _my_id() else -1)
	if action < 0:
		return
	if action == 0 and not _score.can_afford(int(_box.cfg["price"])):
		_player_hud.notice("A spin costs %d points (you have %d)." % [int(_box.cfg["price"]), _score.points])
		return
	if action == 0:
		_stats.add("box_spins")
	if net != null and net.rounds.is_client():
		net.rounds.ask_box(action)
	else:
		_on_box_asked(_my_id(), action)


# Alone or hosting: somebody at the box spins it (0) or takes the gun that is theirs (1).
func _on_box_asked(peer: int, action: int) -> void:
	if action == 0 and _box.spin(_time):
		_box_owner = peer
		_box_gun = {}
		_box_changed("idle", false)
	elif action == 1 and _box.state == "offer" and peer == _box_owner:
		_box.take(_time, _rng)
		_box_changed("offer", true)


# The box does something new: show it, pay or take what is ours, tell the others. `before` = what it did until now.
func _box_changed(before: String, took: bool) -> void:
	var mine := _box_owner == _my_id()
	match _box.state:
		"spinning":
			_box_node.spin()
			if mine:
				_score.spend(int(_box.cfg["price"]))
			if _box_here():
				_sounds.call("play", "box_spin")
		"offer":
			_box_node.offer(String(_box_gun.get("body", "pistol_basic")))
		"moving":
			_box_node.fly_to(_flat(_box_spots[_box.spot]), float(_box.cfg["move_seconds"]))
			if _island_side():
				_sounds.call("play", "box_gull")
				_player_hud.notice("A seagull carries the box off to %s." % _land.islands[_land.island_near(_box_spots[_box.spot].x, _box_spots[_box.spot].y)]["name"])
		_:
			_box_node.stand(_flat(_box_spots[_box.spot]))
	if took and mine and before == "offer" and not _box_gun.is_empty():
		_keep_gun(_box_gun)
	if net != null:
		net.rounds.tell_box(_box.state, _box.spot, _box_owner, _box_gun, took)


# As a client: what the host's box does now.
func _on_box_state(state: String, spot: int, owner: int, gun: Dictionary, took: bool) -> void:
	var before := _box.state
	var offered := _box_gun
	_box.mirror(state, spot)
	_box_owner = owner
	if state == "offer" and GunGen.validate(_player.gun_db, gun) == "":
		_box_gun = gun
	if took:
		_box_gun = offered
	_box_changed(before, took)
	if state != "offer":
		_box_gun = {}


# A rolled gun becomes ours: into a free ready slot, else in place of the gun in hand (which goes to the backpack),
# else onto the ground at our feet.
func _keep_gun(gun: Dictionary) -> void:
	var holster: int = _player.inventory.free_holster()
	if holster < 0:
		holster = maxi(_player.hand_index(), 0)
		if not _player.inventory.stow_holster(holster):
			_field.spawn(gun, _player.global_position)
			_player_hud.notice("Your backpack is full: the gun lies at your feet.")
			return
	_player.inventory.add_gun(gun)
	_player.refresh_held()
	_player.select_hand(holster)
	_inventory_screen.in_hand = _player.hand_index()
	_player_hud.notice("%s" % GunStats.display_name(_player.gun_db, gun))
	save_profile()


func _at_upgrade() -> bool:
	return _island_side() and Vector2(_player.global_position.x - Island.CENTER.x, _player.global_position.z - Island.CENTER.z).distance_to(_upgrade_spot) <= float(_upgrade_cfg["reach"])


# What the upgrade machine can do with the gun in hand: {"why": text} when nothing, else "reroll" (points, -1 = not
# for this gun), "up" (points, -1 = no higher tier) and "to" (the higher tier's id).
func _upgrade_offer() -> Dictionary:
	if not _power.on:
		return {"why": "The upgrade machine has no power."}
	var hand := _player.hand_index()
	var body: String = _player.inventory.holster_body(hand) if hand >= 0 else ""
	if body == "":
		return {"why": "Upgrade machine: hold the gun you want worked on."}
	var gun: Dictionary = _player.inventory.holster_gun(hand)
	var db: RefCounted = _player.gun_db
	if gun.is_empty():
		return {"reroll": -1, "up": int(_upgrade_cfg["plain_to_first"]), "to": String(db.tiers[0]["id"])}
	if gun.has("unique"):
		return {"why": "Hand-made guns cannot be rolled anew."}
	var tier: int = db.tier_index(String(gun["tier"]))
	var higher: bool = tier < int(db.tier_index(String(_upgrade_cfg["top_tier"])))
	return {"reroll": int(_upgrade_cfg["reroll"]), "up": int(_upgrade_cfg["tier_up"]) * (tier + 1) if higher else -1, "to": String(db.tiers[tier + 1]["id"]) if higher else ""}


func _upgrade_prompt(key: String) -> String:
	var offer := _upgrade_offer()
	if offer.has("why"):
		return String(offer["why"])
	var parts := PackedStringArray()
	if int(offer["reroll"]) >= 0:
		parts.append("[%s] Roll it anew, same tier (%d points)" % [key, int(offer["reroll"])])
	if int(offer["up"]) >= 0:
		parts.append("[%s] Make it %s and roll it anew (%d points)" % [key if int(offer["reroll"]) < 0 else InputSetup.label(settings, "reload"), _player.gun_db.tier(String(offer["to"]))["name"], int(offer["up"])])
	return "    ".join(parts)


# The machine works on the gun in hand: `up` = one tier higher, else the same tier; everything else is rolled anew.
func _upgrade(up: bool) -> void:
	var offer := _upgrade_offer()
	if offer.has("why"):
		return
	if int(offer["reroll"]) < 0:
		up = true  # a plain gun can only become a rolled one
	var cost := int(offer["up"]) if up else int(offer["reroll"])
	if cost < 0:
		return
	if not _score.spend(cost):
		_player_hud.notice("That costs %d points (you have %d)." % [cost, _score.points])
		return
	var hand := _player.hand_index()
	var old: Dictionary = _player.inventory.holster_gun(hand)
	var made := GunGen.keep_wkills(old, GunGen.generate(_player.gun_db, _rng, 0.0, _player.inventory.holster_body(hand), String(offer["to"]) if up else String(old["tier"])))  # a W kills counter stays with it
	_player.inventory.set_holster_gun(hand, made)
	_stats.add("upgrades")
	_player.refresh_held()
	_sounds.call("play", "upgrade_done")
	_player_hud.notice("%s" % GunStats.display_name(_player.gun_db, made))
	save_profile()


# The trap whose lever stands at a world spot, -1 = none.
func _trap_at(at: Vector3) -> int:
	var spot := Vector2(at.x - Island.CENTER.x, at.z - Island.CENTER.z)
	for i in _trap_levers.size():
		if spot.distance_to(_trap_levers[i]) <= float(_trap_cfg["reach"]):
			return i
	return -1


func _use_trap(trap: int) -> void:
	if not _power.on or _traps.wait(trap, _time) > 0.0:
		return
	if not _score.can_afford(int(_trap_cfg["traps"][trap]["price"])):
		_player_hud.notice("That costs %d points (you have %d)." % [int(_trap_cfg["traps"][trap]["price"]), _score.points])
		return
	if net != null and net.rounds.is_client():
		net.rounds.ask_trap(trap)
	else:
		_start_trap(_my_id(), trap)


# Alone or hosting: `peer` switches a trap on (it pays when that is us).
func _start_trap(peer: int, trap: int) -> void:
	if not _power.on or not _traps.start(trap, _time):
		return
	if peer == _my_id():
		_score.spend(int(_trap_cfg["traps"][trap]["price"]))
	if net != null:
		net.rounds.tell_trap(trap, peer)


# As a client: the host says a trap runs.
func _on_trap_started(trap: int, by: int) -> void:
	if trap >= 0 and trap < _trap_levers.size() and _traps.start(trap, _time) and by == _my_id():
		_score.spend(int(_trap_cfg["traps"][trap]["price"]))


# Every frame: the box's clock (where the rounds run), the upgrade machine's second key, and the traps: shown
# running or not, hurting enemies where the rounds run and our own player in a fire.
func _run_machines(delta: float) -> void:
	if _rounds.active:
		var before := _box.state
		var happened := _box.update(_time, _rng)
		if happened == "offer":
			_box_gun = GunGen.generate(_player.gun_db, _rng, _box.luck(_rounds.rules.number), "", "", String(_box.cfg["min_tier"]))
		if happened != "":
			_box_changed(before, false)
	if _at_upgrade() and Input.is_action_just_pressed("reload") and not _inventory_screen.visible:
		_upgrade(true)
	_trap_tick -= delta
	var tick := _trap_tick <= 0.0
	if tick:
		_trap_tick = float(_trap_cfg["tick"])
	for i in _trap_centres.size():
		var on := _traps.running(i, _time)
		if on != _trap_shown[i]:
			_trap_shown[i] = on
			_trap_nodes.show_running(i, on)
			if on and _near(_flat(_trap_centres[i]), 40.0):
				_sounds.call("play", "trap_zap" if String(_trap_cfg["traps"][i]["kind"]) == "electric" else "trap_fire")
		if not on or not tick:
			continue
		var trap: Dictionary = _trap_cfg["traps"][i]
		var fire := String(trap["kind"]) == "fire"
		var radius := float(trap["radius"])
		if fire and _island_side() and Vector2(_player.global_position.x - Island.CENTER.x, _player.global_position.z - Island.CENTER.z).distance_to(_trap_centres[i]) <= radius:
			_player.take_damage(float(_trap_cfg["fire"]["player_damage"]), "fire")
		if not _rounds.active:
			continue
		var blow := String(_score.blow)
		_score.blow = "other"  # a trap's kills pay nobody
		for enemy: Variant in _director.enemy_list().duplicate():
			if not is_instance_valid(enemy) or not (enemy as Node).has_meta("island"):
				continue
			var at := Vector2((enemy as Node3D).global_position.x - Island.CENTER.x, (enemy as Node3D).global_position.z - Island.CENTER.z)
			if at.distance_to(_trap_centres[i]) > radius:
				continue
			if fire:
				(enemy as Node).call("apply_burn", float(_trap_cfg["fire"]["burn_dps"]), float(_trap_cfg["fire"]["burn_seconds"]))
			elif _shelters.rules.hut_of(at.x, at.y) != int(trap["hut"]):  # the coil spares what is already inside
				var boss := String((enemy as Node).get("enemy_id")).begins_with("boss")
				(enemy as Node).call("on_hit", float((enemy as Node).get("health").max_hp) * float(_trap_cfg["electric"]["boss_share" if boss else "trash_share"]))
		_score.blow = blow


# --- shelter windows (core/shelter_rules.gd decides; game/shelters.gd shows the boards) ---

# The window our player can reach, -1 = none.
func _window_here() -> int:
	if _in_arena or _in_fantasy or not _on_island(_player.global_position):
		return -1
	return _shelters.rules.window_near(_player.global_position.x - Island.CENTER.x, _player.global_position.z - Island.CENTER.z)


# Interact held at a window that misses boards: one goes back every repair_seconds. Online the host nails it.
func _hold_nailing() -> void:
	var window := _window_here()
	if window < 0 or _player.downed or not Input.is_action_pressed("interact") or _shelters.rules.boards[window] >= _shelters.rules.full():
		return
	var now := Time.get_ticks_msec() / 1000.0  # the clock the rounds use for the boards
	if net != null and net.rounds.is_client():
		if now >= _nail_at:
			_nail_at = now + float(_land.cfg["windows"]["repair_seconds"])
			net.rounds.ask_nail(window)
		return
	var paid: int = _shelters.rules.nail(window, now)
	if paid < 0:
		return
	_shelters.refresh()
	_sounds.call("play", "board_fix")
	_score.give(paid * _score.mult)
	if net != null:
		net.rounds.tell_window(window, _shelters.rules.boards[window])


# Where the rounds run: an enemy tore a board off.
func _on_board_torn(window: int) -> void:
	if _near(_shelters.window_spot(window), 30.0):
		_sounds.call("play", "board_tear")
	if net != null:
		net.rounds.tell_window(window, _shelters.rules.boards[window])


# The host says what a window has now (as a client; on the host after a client nailed a board).
func _on_window_set(window: int, boards: int) -> void:
	if window < 0 or window >= _shelters.rules.boards.size():
		return
	var before: int = _shelters.rules.boards[window]
	_shelters.rules.set_boards(window, boards)
	_shelters.refresh()
	if _shelters.rules.boards[window] != before and _near(_shelters.window_spot(window), 30.0):
		_sounds.call("play", "board_fix" if _shelters.rules.boards[window] > before else "board_tear")


func _on_nail_paid(points: int) -> void:
	_score.give(points * _score.mult)
	_stats.add("boards_nailed")


# Nobody swims: a player wading deeper than data wade_depth is carried back to the island last stood on.
func _mind_the_sea() -> void:
	var at := _player.global_position - Island.CENTER
	if _land.on_land(at.x, at.z):
		_last_isle = _land.island_near(at.x, at.z)
	elif _land.deck_at(at.x, at.z) < 0 and at.y < _land.sea_level - float(_land.cfg["wade_depth"]) and not _player.carried and _flight_t < 0.0:
		_player.teleport(Island.CENTER + _land.wash_up(at.x, at.z, _last_isle) + Vector3(0, 0.1, 0), 0.0)
		_player_hud.play_fade()
		_player_hud.notice("The current carries you back to the shore.")


# --- power-ups (core/powerup_rules.gd decides; game/powerup_field.gd shows the ones lying around) ---

# A power-up appears where an enemy fell. Only the machine that runs the rounds does this; it tells the others.
func _drop_power(kind: String, where: Vector3) -> void:
	var at := Island.CENTER + _land.wash_up(where.x - Island.CENTER.x, where.z - Island.CENTER.z)  # it fell in the water: the power-up washes up on the sand
	_power_id += 1
	_power_field.drop(_power_id, kind, at)
	if _island_side():
		_sounds.call("play", "powerup_drop")
	if net != null:
		net.rounds.tell_power_drop(_power_id, kind, at)


# As a client: the host says one lies there.
func _on_power_dropped(id: int, kind: String, at: Vector3) -> void:
	if _powerups.has(kind):
		_power_field.drop(id, kind, at)
		if _island_side():
			_sounds.call("play", "powerup_drop")


# Alone or hosting: a player walked into one. The whole party has it.
func _on_power_touched(id: int, kind: String) -> void:
	if net != null:
		net.rounds.tell_power_gone(id)
		net.rounds.tell_power(kind)
	_apply_power(kind)


func _on_power_expired(id: int) -> void:
	if net != null:
		net.rounds.tell_power_gone(id)


# Somebody of the party took `kind`: what that does on this machine. The clocks run everywhere (the host's decides
# what one blow kills); the rest is only for a player who is on the islands.
func _apply_power(kind: String) -> void:
	if not _powerups.has(kind):
		return
	var entry: Dictionary = _powerups.cfg["kinds"][kind]
	_powerups.start(kind, _time, _perks.num("power_time_mult", 1.0))
	if _island_side():
		_stats.add_to("powerups", kind)
	if kind == "carpenter":
		_shelters.rules.board_all()
		_shelters.refresh()
	if kind == "nuke" and _rounds.active:
		var before := String(_score.blow)
		_score.blow = "other"  # nobody is paid for what the blast kills ...
		_blasting = true  # ... and none of it leaves a power-up (a boss it finishes still does)
		_rounds.blast(float(entry["boss_share"]))
		_blasting = false
		_score.blow = before
	if not _island_side():
		return
	_player_hud.callout(_powerups.name_of(kind), _powerups.color_of(kind))
	_sounds.call("play", "powerup_nuke" if kind == "nuke" else "powerup_grab")
	match kind:
		"max_ammo":
			_player.pools.fill_all()
		"nuke":
			_player_hud.flash_white()
			_score.give(int(entry["points"]) * _powerups.points_mult(_time))
		"carpenter":
			_score.give(int(entry["points"]) * _powerups.points_mult(_time))
		"perk":
			var got := _perks.give_random(_rng)
			if got != "":
				_perks_changed(true)
				_player_hud.notice("%s: %s" % [_perks.name_of(got), _perks.desc(got)])


# The run is over: no power-up lies around or runs any more.
func _clear_powers() -> void:
	_powerups.reset()
	_power_field.clear()


# --- the main quest (core/quest_state.gd decides; texts in data/zombies/writing/quest.txt) ---

# Alone or hosting: this machine decides the quest. A client tells the host and shows what it hears back.
func _quest_host() -> bool:
	return net == null or not net.rounds.is_client()


# The use step whose spot our player stands at ("" = none).
func _quest_use_here() -> String:
	if not _island_side() or _quest.kind() != "use":
		return ""
	var id := String(_quest.current()["id"])
	var spot := Vector2(_player.global_position.x - Island.CENTER.x, _player.global_position.z - Island.CENTER.z)
	return id if spot.distance_to(_quest_spots[id]) <= float(_quest.cfg["reach"]) else ""


# Host: does that spot fit a client's claim? (use: at the step's spot; lamp: within a long shot of it)
func _quest_fits(at: Vector3, action: String, index: int) -> bool:
	var spot := Vector2(at.x - Island.CENTER.x, at.z - Island.CENTER.z)
	if action == "use" and _quest.kind() == "use":
		return spot.distance_to(_quest_spots[String(_quest.current()["id"])]) <= float(_quest.cfg["reach"]) + 1.5
	if action == "lamp" and index >= 0 and index < _lamp_spots.size():
		return at.distance_to(_lamp_spots[index]) <= 120.0
	return false


# Something we did for the quest: decide it (alone / host) or ask the host.
func _quest_try(action: String, index: int) -> void:
	if _quest_host():
		_quest_do(action, index)
	else:
		net.rounds.ask_quest(action, index)


func _quest_do(action: String, index: int) -> void:
	match action:
		"use":
			if _quest.kind() == "use" and _quest.used(String(_quest.current()["id"])):
				_quest_advance()
		"lamp":
			if _quest.lamp_out(index):
				_quest_advance()
			else:
				_show_quest()
				if net != null:
					net.rounds.tell_quest(_quest.to_dict(), -1)


func _on_lamp_shot(index: int) -> void:
	if _island_side() and _quest.kind() == "shoot" and not _quest.shot[index]:
		_sounds.call("play", "secret_clink")
		_quest_try("lamp", index)


# Host: the step is done. Everybody hears of it.
func _quest_advance() -> void:
	var finished := _quest.step
	_quest.advance()
	_on_quest_told(_quest.to_dict(), finished)
	if net != null:
		net.rounds.tell_quest(_quest.to_dict(), finished)


# The quest as it now is; `news` = the step just finished (its done line, then the next step's lines), -1 = none.
func _on_quest_told(state: Dictionary, news: int) -> void:
	var was := _quest.step
	_quest.from_dict(state)
	_show_quest()
	if news < 0 or news >= _quest.steps().size() or not _island_side():
		return
	var old_id := String(_quest.steps()[news]["id"])
	_sounds.call("play", "quest_step")
	if news == 0:
		_player_hud.callout(_quest.quest_line("name"), Color(0.55, 0.85, 1.0))
	_player_hud.notice(_quest.line(old_id, "done"))
	if _quest.done():
		_quest_reward()
		return
	if was != _quest.step:
		var next := String(_quest.current()["id"])
		for said: String in _quest.says(next):
			var who := _quest.line(next, "who")
			_chat.add_line(said if who == "" else "%s: %s" % [who, said], Color(0.6, 0.85, 1.0))


# The quest is done: every player on the islands gets the reward on his own machine.
func _quest_reward() -> void:
	var reward: Dictionary = _quest.cfg.get("reward", {})
	_chat.add_line(_quest.quest_line("finished"), Color(1.0, 0.85, 0.45))
	_player_hud.callout(_quest.quest_line("name"), Color(1.0, 0.85, 0.45))
	_score.give(int(reward.get("points", 0)))
	_stats.add("main_quests")
	var which := String(reward.get("unique", ""))
	if which == "any":
		var ids: Array = _player.gun_db.uniques.keys()
		which = String(ids[_rng.randi_range(0, ids.size() - 1)]) if not ids.is_empty() else ""
	if which != "":
		var gun := GunGen.unique(_player.gun_db, which)
		if not gun.is_empty():
			_field.spawn(gun, _player.global_position + Vector3(0, 0, -1.2))
			_player_hud.notice("%s  %s" % [_quest.quest_line("reward"), GunStats.display_name(_player.gun_db, gun)])
	save_profile()


# Every frame: the boss step sends its enemy once somebody of the party stands near its spot (host).
func _run_quest() -> void:
	if _quest.kind() != "boss" or _quest.boss_out or not _quest_host() or not _rounds.active:
		return
	var id := String(_quest.current()["id"])
	var spot: Vector2 = _quest_spots[id]
	for body: Node3D in _island_bodies():
		if Vector2(body.global_position.x - Island.CENTER.x, body.global_position.z - Island.CENTER.z).distance_to(spot) < 14.0:
			_quest.boss_out = true
			_rounds.send_at(String(_quest.current()["enemy"]), _flat(spot) + Vector3(0, 0.2, 0), maxi(_island_round(), 1) + int(_quest.current().get("rounds_ahead", 0)))
			for said: String in _quest.says(id):
				var who := _quest.line(id, "who")
				_chat.add_line(said if who == "" else "%s: %s" % [who, said], Color(1.0, 0.5, 0.45))
			if net != null:
				net.rounds.tell_quest(_quest.to_dict(), -1)
			return


# The tracker line at the top left and the quest's things (jars, lamps). Hidden until the first step is done.
func _show_quest() -> void:
	var fill := 0.0
	if _quest.kind() == "kills":
		fill = float(_quest.count) / float(_quest.current()["count"])
	elif _quest.step > _quest_step_of("jars"):
		fill = 1.0
	var lamps: Array = _quest.shot if _quest.kind() == "shoot" else ([true, true, true] if _quest.step > _quest_step_of("lamps") else [])
	_quest_things.show_state(fill, lamps, _quest.kind() == "shoot")
	if _quest.step <= 0 or _quest.done():
		_player_hud.quest_text = ""
		return
	var id := String(_quest.current()["id"])
	var extra := ""
	if _quest.kind() == "kills":
		extra = "  (%d / %d)" % [_quest.count, int(_quest.current()["count"])]
	elif _quest.kind() == "shoot":
		extra = "  (%d / %d)" % [_quest.shot.count(true), _quest.shot.size()]
	_player_hud.quest_text = "%s: %s%s\n%s" % [_quest.quest_line("name"), _quest.line(id, "what"), extra, _quest.line(id, "where")]


func _quest_step_of(id: String) -> int:
	for i in _quest.steps().size():
		if String(_quest.steps()[i]["id"]) == id:
			return i
	return 99


# --- the hidden songs (core/song_book.gd decides; data/zombies/songs.json; the files in its folder) ---

func _on_float_shot(secret: int, thing: int) -> void:
	if _songs.is_shot(secret, thing):
		return
	_sounds.call("play", "secret_clink")
	if not _songs.shoot(secret, thing):
		_song_floats.show_shot(secret, thing, true)
		return
	_song_floats.show_secret(secret, false)
	_stats.add("songs_found")
	save_profile()
	_play_song(secret)


# Plays secret n's song (or says that its file is missing).
func _play_song(secret: int) -> void:
	var song := _songs.song(secret)
	if song.is_empty():
		_player_hud.notice("Hidden song %d found! (No song for it yet: put mp3 / ogg / wav files into your Music folder: main menu, music note.)" % (secret + 1))
		return
	if music_box == null or not bool(music_box.call("play_file", String(song["file"]))):
		_player_hud.notice("Hidden song %d: %s could not be read." % [secret + 1, String(song["file"])])
		return
	var artist := String(song["artist"])
	_player_hud.callout(String(song["title"]) if artist == "" else "%s - %s" % [artist, String(song["title"])], Color(0.65, 1.0, 0.75))


# A jukebox (the club's, the hub's trophy room): the jukebox window (game/music_menu.gd; online the host's songs).
func _open_jukebox() -> void:
	if music_menu == null:
		return
	if not music_menu.is_connected("closed", _close_jukebox):
		music_menu.connect("closed", _close_jukebox)
	_jukebox_open = true
	music_menu.call("open")
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_jukebox() -> void:
	if not _jukebox_open:
		return
	_jukebox_open = false
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- the cigarette (core/cigarette_state.gd decides; data/cigarette.json) ---

# Every frame: a worn cigarette burns while we are on the gun side (the islands, the colosseum; not the club, the
# casino or Aurelind); when it is done it turns into a butt in the mouth. The HUD shows what is left.
# --- the hop course (core/course_rules.gd decides, game/bhop_course.gd builds it; data/course.json) ---

func _go_to_course() -> void:
	if _course_root == null:
		_course_root = BhopCourse.build(self, _course)
	_course.reset()
	_put_on_course(_course.start_index())


func _put_on_course(index: int) -> void:
	var spot := _course.stand_on(index)
	_player.teleport(_course_root.position + (spot["at"] as Vector3) + Vector3(0, 0.1, 0), float(spot["yaw"]))


func _course_exit_here() -> bool:
	if not _on_course or not _player.is_on_floor():
		return false
	var local := _player.global_position - _course_root.position
	var under := _course.pad_at(local.x, local.z)
	return under >= 0 and under in [_course.start_index(), _course.finish_index()]


# Every frame: is the player on the course (everybody moves the same there), the clock, falls, checkpoints, the finish.
func _run_course(delta: float) -> void:
	var local := (_player.global_position - _course_root.position) if _course_root != null else Vector3(0, -1000, 0)
	var here := _course_root != null and Vector2(local.x, local.z).length() < 400.0 and local.y > -60.0
	if here != _on_course:
		_on_course = here
		_player.even_ground = here
		_player_hud.course_text = ""
		if here:
			_course.reset()
	if not here:
		return
	var under := _course.pad_at(local.x, local.z) if _player.is_on_floor() and local.y > -0.6 else -1
	var fallen := local.y < -float(_course.cfg.get("fall_below", 3.0))
	match _course.update(delta, under, fallen):
		"fell":
			_put_on_course(_course.checkpoint)
		"restart":
			_put_on_course(_course.start_index())
		"start":
			_sounds.call("play", "course_go")
		"checkpoint":
			_sounds.call("play", "course_checkpoint")
			_player_hud.notice("Checkpoint  %s" % CourseRules.clock(_course.time))
		"finish":
			_stats.add("course_runs")
			_sounds.call("play", "course_finish")
			_player_hud.callout("Finished  %s" % CourseRules.clock(_course.last), Color(0.95, 0.8, 0.35))
		"record":
			_stats.add("course_runs")
			_sounds.call("play", "course_finish")
			_player_hud.callout("New best  %s" % CourseRules.clock(_course.best), Color(1.0, 0.85, 0.3))
			save_profile()
	var best := ("   best %s" % CourseRules.clock(_course.best)) if _course.best > 0.0 else ""
	match _course.state:
		CourseRules.READY:
			_player_hud.course_text = "HOP COURSE  leave the start pad to start the clock (knife out is fastest)%s" % best
		CourseRules.RUNNING:
			_player_hud.course_text = "%s   %s   stage %d / %d%s" % [CourseRules.clock(_course.time), _course.stage_name(maxi(_course.checkpoint + 1, 1)), _course.stage_of(maxi(_course.checkpoint + 1, 1)), _course.stage_count(), best]
		_:
			_player_hud.course_text = "Finished in %s%s   walk back onto the start pad to go again" % [CourseRules.clock(_course.last), best]


# --- the record of everything (core/stat_book.gd; shown by game/combat_report.gd on the card) ---

# One of our kills: by what, of what, where.
func _count_kill(enemy_id: String, elite: String, blow: String) -> void:
	_stats.add("kills")
	_stats.add_to("kills_by_enemy", enemy_id)
	var weapon := "other"
	if blow == "melee":
		weapon = "knife:" + _player.knife
	elif _player.hand_index() >= 0:
		weapon = "gun:" + _player.inventory.holster_body(_player.hand_index())
	elif _in_fantasy:
		weapon = "staff"
	_stats.add_to("kills_by_weapon", weapon)
	if blow == "headshot":
		_stats.add("headshots")
	if elite != "":
		_stats.add("elite_kills")
	if enemy_id.begins_with("boss"):
		_stats.add("boss_kills")


# Every frame: time played, distance travelled, top speed, the colosseum's waves cleared.
func _run_stats(delta: float) -> void:
	_stats.tick(delta)
	if _player.shots_fired > 0 or _player.hurt_total > 0.0:  # what the player counted since the last frame
		_stats.add("shots_fired", float(_player.shots_fired))
		_stats.add("shots_hit", float(_player.shots_hit))
		_stats.add("damage_taken", _player.hurt_total)
		_player.shots_fired = 0
		_player.shots_hit = 0
		_player.hurt_total = 0.0
	var here := _player.global_position
	if _stat_from.is_finite() and not _player.carried and _flight_t < 0.0:
		var step := Vector2(here.x - _stat_from.x, here.z - _stat_from.z).length()
		if step < 3.0:  # (a teleport is not a walk)
			_stats.add("metres", step)
	_stat_from = here
	_stats.best("top_speed", float(_player.speed_units()))
	var wave := _director.wave_number() if _in_arena else 0
	if wave > _last_wave and _last_wave > 0:
		_stats.add("colosseum_waves", float(wave - _last_wave))  # (the last wave of a won run is counted with the win)
	_last_wave = wave
	_ach_wait -= delta
	if _ach_wait <= 0.0:
		_ach_wait = 2.0
		_read_achievements()


# Stat achievements (data/achievements.json "stat"): reads every key from the record and unlocks what reached its goal.
func _read_achievements() -> void:
	var extra := {"best_round": _best_round, "course_best": _course.best}
	if _fantasy != null:
		extra["quests_done"] = (_fantasy.quests.done as Array).size()
		var levels: Dictionary = _fantasy.skills.levels()
		var sum := 0
		for id: String in levels:
			extra["skill:" + id] = int(levels[id])
			sum += int(levels[id])
		extra["skill_total"] = sum
	extra.merge(TcgStats.readings(_cards, _card_screen.card_db, _tcg_mats), true)  # the card game's collection readings
	var values := {}
	for key: String in _progress.stat_keys():
		values[key] = AchievementReader.read(key, _stats, extra)
	_progress.read_stats(values)
	_progress_notices(0)


# The card's Combat Report: the record, with the names it needs.
func _combat_report() -> Dictionary:
	var knives := KnifeModels.db()
	var ctx := {
		"gun_name": func(body: String) -> String: return String(_player.gun_db.bodies[body]["name"]) if _player.gun_db.bodies.has(body) else body.capitalize(),
		"knife_name": func(kind: String) -> String: return String(knives.name_of(kind)),
		"item_name": func(id: String) -> String: return String(_fantasy.bag.item_name(id)) if _fantasy != null else id.replace("_", " ").capitalize(),
		"skill_name": func(id: String) -> String: return String(_fantasy.skills.skill_name(id)) if _fantasy != null else id.capitalize(),
		"enemy_name": func(id: String) -> String: return _enemy_name(id),
		"leader_name": func(id: String) -> String: return String(((_card_screen.card_db.get("leaders") as Dictionary).get(id, {}) as Dictionary).get("name", id.capitalize())),
		"tcg_record": _cards.record if _cards != null else {},
		"best_round": _best_round,
		"course_best": _course.best,
		"quests_done": (_fantasy.quests.done as Array).size() if _fantasy != null else 0,
		"level": _progress.level(),
	}
	var report := CombatReport.build(_stats, ctx)
	report["look"] = _player.appearance
	return report


func _enemy_name(id: String) -> String:
	var named: Dictionary = DataStore.load_json("res://data/combat_report.json").get("enemy_names", {})
	return String(named.get(id, id.replace("_", " ").capitalize()))


func _run_cigarette(delta: float) -> void:
	var worn: Dictionary = _player.inventory.equipment.get("mouth", {})
	if worn.is_empty() or String(worn["id"]) != String(_smoke.cfg["item"]):
		_player_hud.cigarette = -1.0
		return
	_smoke.light()  # one burnt out before: this is a fresh one
	if _smoke.tick(delta, _in_arena or _island_side()):
		_player.inventory.equipment["mouth"] = {"id": String(_smoke.cfg["burnt"]), "count": 1}
		_player.refresh_equipment()
		_player_hud.notice("Your cigarette burnt out. Reward chests in the colosseum hold fresh ones.")
		_stats.add("cigarettes")
		save_profile()
	_player_hud.cigarette = _smoke.share()
	_player_hud.cigarette_warn = _smoke.warning()


# The islands' weather follows the round (game/island_weather.gd); a boss round's red sky only while it is fought.
func _run_weather(delta: float) -> void:
	var here := _island_side()
	var watching: bool = net != null and net.rounds.is_client()
	var fought: bool = net.rounds.fighting if watching else _rounds.rules.fighting()
	var kind: String = net.rounds.round_kind if watching else _rounds.rules.kind
	var spot := _player.global_position - Island.CENTER
	_weather.update(delta, here, _island_round(), kind if fought else "normal", here and _shelters.rules.hut_of(spot.x, spot.z) >= 0)


# The weather on screen in one line (test scripts).
func weather_note() -> String:
	return _weather.describe()


# True while our player is on the islands (not in the colosseum, Aurelind or the club).
func _island_side() -> bool:
	return not _in_arena and not _in_fantasy and _on_island(_player.global_position)


# Admin command: a power-up a few steps in front of `near` ("" = any). Returns what to tell the typist.
func drop_power(kind: String, near: Node3D) -> String:
	if not _rounds.active:
		return "Only the host drops power-ups."
	var which := kind if kind != "" else _powerups.pick(_rng)
	if not _powerups.has(which):
		return "Power-ups: %s" % ", ".join(PackedStringArray(_powerups.kinds()))
	var forward := Basis(Vector3.UP, float(near.call("look_yaw"))) * Vector3.FORWARD if near.has_method("look_yaw") else -near.global_transform.basis.z
	_drop_power(which, near.global_position + forward * 4.0)
	return "Dropped %s." % _powerups.name_of(which)


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
	_fantasy.spell_cast.connect(func(spell_name: String, mix: String) -> void:
		_stats.add("spells_cast")
		_stats.add_to("spells", spell_name)
		_stats.add_to("spell_mixes", mix))
	_fantasy.worked.connect(func(skill: String, item: String, count: int, made: bool) -> void:
		_stats.add_to("skill_actions", skill)
		_stats.add_to("made" if made else "gathered", item, float(count)))
	_fantasy.spell_uses = func(group: String, id: String) -> float: return _stats.count_in(group, id)
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
	_tcg.setup(_wallet, _casino, _custom_layer, _player, _player_hud, _cards)
	_tcg.graphics = settings.graphics
	_tcg.stats = _stats
	_ptables.setup(_wallet, _casino, _custom_layer, _player, _player_hud, _cards, net.tcg if net != null else null)
	_ptables.graphics = settings.graphics
	_ptables.stats = _stats
	if net != null:  # the host's book learns where the player tables stand (walking away from one mid-match loses it)
		var spots: Array = []
		for t: Node3D in _casino.get("player_tables", []):
			spots.append(t.global_position)
		net.tcg.set_spots(spots)
	_shop.setup(_wallet, _cards, _casino, _custom_layer, _player)
	(_casino["blackjack"] as Node3D).connect("changed", func(op: String, args: Array) -> void: table_event.emit(op, args))
	_jukebox = Jukebox.new()
	_jukebox.position = ClubIsland.CENTER + JUKEBOX_AT
	_jukebox.rotation.y = JUKEBOX_YAW
	add_child(_jukebox)
	_club_parts.append(_jukebox)
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
	var run_fx := _director.run_fx
	_set_run_fx({})
	if _reward != null:
		_reward.queue_free()
	_reward = null
	_in_arena = false
	if _director.shared_run and _director.follow.is_empty() and not _run_bodies().is_empty():
		_director.run_fx = run_fx  # hosting a run the others are still in: it goes on (game over for it comes when nobody is left)
	else:
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
		if _out and Input.is_action_just_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_watch_next()
	_rest_in -= delta
	if _rest_in <= 0.0:
		_rest_worlds()
	if _fantasy_dirty and _time - _fantasy_saved_at > 20.0:
		_fantasy_dirty = false
		_fantasy_saved_at = _time
		save_profile()
	_power_field.deciding = _rounds.active
	_run_machines(delta)
	_run_hub()
	_run_weather(delta)
	_run_boat(delta)
	_run_cigarette(delta)
	_run_course(delta)
	_run_stats(delta)
	_run_quest()
	if _in_arena and not _run_fx.is_empty():
		_run_modifiers(delta)
	_host_run(delta)
	if _self_revive_at >= 0.0 and _time >= _self_revive_at:
		_self_revive_at = -1.0
		_player.revive(1.0)
		_player_hud.notice("You are back on your feet. That was your one Second Wind.")
	if _island_side():
		_mind_the_sea()
		_hold_nailing()
	_score.mult = _powerups.points_mult(_time) if _island_side() else 1
	_player_hud.power_now = _time
	var regen: Dictionary = _rounds.config()["regen"]  # the classic way: left alone for a moment, you get your breath back
	if not _in_arena and not _in_fantasy and _time - _hurt_at >= float(regen["delay"]) and _player.health.hp > 0.0 and _player.health.hp < _player.health.max_hp:
		_player.health.heal(float(regen["per_second"]) * delta)
	_player_hud.prompt_text = _prompt()
	_player_hud.coins = _wallet.balance if _pachinko != null and _near(_pachinko.global_position, 30.0) else -1
	if _coins_dirty and (_pachinko == null or _pachinko.balls_in_play() == 0):
		_coins_dirty = false
		save_profile()
	if _in_arena and _reward == null and _director.is_cleared():
		_reward = RewardArea.new()  # the run is won: the chest, then the door back to the island
		add_child(_reward)
		_stats.add("colosseum_won")
		_stats.add("colosseum_waves")
		_stats.best("colosseum_longest", float(_director.wave_count()))
		_player_hud.callout("Colosseum cleared", Color(1.0, 0.85, 0.4))
	var scope: float = _player.sight_amount()
	_scope.kind = _player.sight_kind()
	_scope.amount = scope
	_cross.visible = scope < ScopeOverlay.SHOW_FROM and not _run_fx.has("blind")
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
	_scoreboard.code = net.session_id if net != null and net.is_active() else ""
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


# THE SAFE HUB (diary/DECISIONS_HUB.md). Who is in it, on the stage and ready is decided by game/net_hub.gd (the host
# online); here: our F key, the dark and the candles, nothing hurts, the countdown's tick and the button's clunk, and
# leaving through the ink when the host says go.
func _in_hub() -> bool:
	return _hub_room != null and not _in_arena and not _in_fantasy and net.hub.inside(_player.global_position)


func _hub_place() -> int:
	if not net.can_send():
		return 0
	var ids: Array = net.roster.keys()
	ids.sort()
	return maxi(ids.find(net.my_id()), 0)


func _hub_near_button() -> bool:
	if not _in_hub() or bool(net.hub.view.get("button", false)):
		return false
	var p: Array = net.hub.cfg["pedestal"]
	var at := _hub_room.position + Vector3(float(p[0]), 0.0, float(p[1]))
	return Vector2(_player.global_position.x - at.x, _player.global_position.z - at.z).length() <= float(net.hub.cfg["button_reach"]) - 0.2


func _run_hub() -> void:
	if _hub_room == null:
		return
	var here := _in_hub()
	_player.safe = here
	if here != _hub_dark:
		_hub_dark = here
		apply_settings()
		_sounds.call("set_region", "hub" if here else "")
	_hub_hud.visible = here and not _ink.playing()
	_hub_hud.key = _key("interact")
	_hub_hud.me = net.hub.me()
	net.hub.hold(here and _player.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("interact"))


func _on_hub_view(v: Dictionary) -> void:
	_hub_hud.show_view(v)
	if not _in_hub():
		return
	if bool(v.get("button", false)) and not _hub_room.is_pressed():
		_hub_room.press()
		_sounds.call("play", "hub_button")
	if not bool(v.get("open", true)):  # the group already went (we joined late, or missed the word): follow it
		_on_hub_go()
		return
	var second := ceili(float(v.get("left", 0.0)))
	if not bool(v.get("button", false)) and int(v.get("total", 0)) > 0 and float(v.get("left", 0.0)) <= _hub_hud.red_last and second != _hub_tick and second > 0:
		_hub_tick = second
		_sounds.call("play", "hub_tick")


func _on_hub_go() -> void:
	if _in_hub() and not _ink.playing():
		_ink.play(func() -> void:
			if _in_hub():
				_player.teleport(_island_spawn, 0.0))


# /hub (operators): back to the hub, and a new ready-up there without a countdown.
func back_to_hub() -> String:
	if _hub_room == null:
		return "There is no hub here."
	if _in_arena:
		_leave_arena()
	elif _in_fantasy:
		_leave_fantasy()
	_player.teleport(_hub_room.spawn(_hub_place()), 0.0)
	net.hub.reopen()
	return "Back in the hub. Everyone here: hold %s on the stage to go." % _key("interact")


# In the hub only its own candles and the moon window light the room: no sky, no sun, a little dark fog that the
# endless stair fades into.
func _darken_for_hub() -> void:
	var env := _render_style.env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.008, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.21, 0.24)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.fog_enabled = true
	env.fog_density = 0.03
	env.fog_light_color = Color(0.02, 0.02, 0.03)
	env.fog_sky_affect = 1.0
	env.fog_aerial_perspective = 0.0
	_render_style.sun.light_energy = 0.0


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
	_cross_styles.setup(DataStore.load_json("res://data/crosshairs.json"))
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_cross)
	layer.add_child(_overlay)
	layer.add_child(_scoreboard)
	layer.add_child(_game_over)
	layer.add_child(_chat)
	_hub_hud.visible = false
	layer.add_child(_hub_hud)
	layer.add_child(_ink)
	add_child(layer)
