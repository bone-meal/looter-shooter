# Purpose: the fantasy painting world Aurelind as a whole: owns its rules (terrain, layout, bag, skills, quests,
# spells) and its parts on screen (streamed land, scatter, places). It keeps the look the player chose in the settings
# and lays each region's weather over it (sky colour, haze, sun colour), eased as the player walks,
# hands out experience, items and quest rewards, and saves all of it in the player's profile. Everything in here lives
# at OFFSET, far from the island; positions called "local" are the world's own map metres (x east, z south).
# Dependencies: core/fantasy_data.gd (rules + writers' text), core/fantasy_terrain.gd, core/fantasy_layout.gd, core/fantasy_bag.gd, core/skill_levels.gd, core/quest_log.gd,
# core/spell_book.gd, game/fantasy_land.gd, game/fantasy_scatter.gd, game/gather_nodes.gd, game/fantasy_places.gd,
# game/fantasy_work.gd, game/staff_caster.gd, game/spell_effects.gd, game/fantasy_spawner.gd, game/fantasy_hud.gd,
# game/element_box.gd, game/fantasy_panel.gd, game/render_style.gd (the sky). The session (game/game_session.gd) builds it the
# first time the player steps into the painting.
extends Node3D

const SkillPerks = preload("res://core/skill_perks.gd")
const FantasyData = preload("res://core/fantasy_data.gd")
const FantasyTerrain = preload("res://core/fantasy_terrain.gd")
const FantasyLayout = preload("res://core/fantasy_layout.gd")
const FantasyBag = preload("res://core/fantasy_bag.gd")
const SkillLevels = preload("res://core/skill_levels.gd")
const QuestLog = preload("res://core/quest_log.gd")
const SpellBook = preload("res://core/spell_book.gd")
const FantasyLand = preload("res://game/fantasy_land.gd")
const FantasyScatter = preload("res://game/fantasy_scatter.gd")
const GatherNodes = preload("res://game/gather_nodes.gd")
const FantasyPlaces = preload("res://game/fantasy_places.gd")
const FantasyWork = preload("res://game/fantasy_work.gd")
const Snares = preload("res://game/snares.gd")
const Agility = preload("res://game/agility.gd")
const ArmourGen = preload("res://core/armour_gen.gd")
const StaffCaster = preload("res://game/staff_caster.gd")
const SpellEffects = preload("res://game/spell_effects.gd")
const CombatTools = preload("res://game/combat_tools.gd")
const GroundMarks = preload("res://game/ground_marks.gd")
const SquadCommand = preload("res://game/squad_command.gd")
const FantasySpawner = preload("res://game/fantasy_spawner.gd")
const BossMoves = preload("res://game/boss_moves.gd")
const FantasySounds = preload("res://game/fantasy_sounds.gd")
const FantasyMap = preload("res://game/fantasy_map.gd")
const FantasyInteriors = preload("res://core/fantasy_interiors.gd")
const FantasyRooms = preload("res://game/fantasy_rooms.gd")
const LoadClock = preload("res://game/load_clock.gd")
const EnemyBody = preload("res://game/enemy.gd")
const FantasyHud = preload("res://game/fantasy_hud.gd")
const ElementBox = preload("res://game/element_box.gd")
const FantasyPanel = preload("res://game/fantasy_panel.gd")

const OFFSET := Vector3(20000.0, 0.0, 0.0)
const SAVE_VERSION := 1
const GOOD := Color(0.6, 1.0, 0.6)
const GOLD := Color(1.0, 0.85, 0.4)
const WALK_LAND := 0
const WALK_SWIM := 1
const WALK_FLY := 2

signal ship_built(ship_id: String)  # the shipyard launched a ship (game/sea_ships.gd build)
signal ship_part_made(part: String)  # the shipyard made a ship's part, e.g. "crane" (game/sea_ships.gd fit_part)
signal notice(text: String)  # big line in the middle of the screen
signal toast(text: String, color: Color)  # small rising line: experience
signal picked(item: String, count: int)  # (polish1 item 99) something came into the bag: the HUD's loot list
signal skill_up(skill: String, level: int, opened: PackedStringArray)  # (polish1 item 104) the HUD's manuscript banner
signal said(text: String, color: Color)  # a line for the chat box (quest text)
signal boss_move(text: String, color: Color)  # a boss starts one of its special attacks (the HUD flashes its name)
signal vanquished(creature: String, phantom: bool, won: Array)  # (polish1 E4) a great creature fell: the HUD's page, what this player won
signal fade  # the screen should fade (a door was used)
signal changed  # bag, skills or quests changed: the HUD redraws, the session saves
signal spell_cast(spell_name: String, mix: String)  # a spell left the staff (the session counts it: core/stat_book.gd)
signal worked(skill: String, item: String, count: int, made: bool)  # gathered (made false) or crafted (made true)

var trophy_gift := Callable()  # (polish1 E4) func(boss id, phantom, odds) -> lines: the session's boss trophies (game/boss_trophy_keeper.gd)
var spell_uses := Callable()  # func(group "spells" | "spell_mixes", id) -> times cast (set by the session; the Spells page shows it)
var data: Dictionary  # everything core/fantasy_data.gd loaded: world, quests, gear, skilling, spells, enemies, layouts, props, text
var terrain: FantasyTerrain
var layout: FantasyLayout  # where every house, prop, tree and fishing spot stands (drawing, colliders and creatures all ask it)
var bag: FantasyBag
var town_finer := 0.0  # set while a station of the home port's top-level workshop is open (sea step 7b): master work
var skills: SkillLevels
var quests: QuestLog
var spells: SpellBook
var skilling: Dictionary  # data/fantasy/skilling.json
var land := FantasyLand.new()
var scatter := FantasyScatter.new()
var gather := GatherNodes.new()
var places := FantasyPlaces.new()
var work := FantasyWork.new()
var snares := Snares.new()  # Hunting: snares set from the bag and the trails that tracks lay
var agility := Agility.new()  # course obstacles and the cliff shortcuts
var _craft_rng := RandomNumberGenerator.new()  # Crafting's gun-side pieces roll their bonuses
var caster := StaffCaster.new()
var effects := SpellEffects.new()
var combat := CombatTools.new()  # dodge, ward, staff strike
var marks := GroundMarks.new()  # what spells leave on the ground
var squads := SquadCommand.new()  # the creatures' orders: who presses, who circles, who shoots from where
var spawner := FantasySpawner.new()
var moves := BossMoves.new()
var panel := FantasyPanel.new()
var map := FantasyMap.new()
var interiors: FantasyInteriors  # what is inside which building
var rooms := FantasyRooms.new()  # doors, rooms and containers
var found := {}  # ids of the regions and places the player has been to (the map names only these)
var inside := false
var hud_node: Control  # game/fantasy_hud.gd (its compass)
var mana := 0.0
var sounds: Node  # game/fantasy_sounds.gd
var party: Node  # game/net_fantasy.gd while playing online (null alone): quest events go through the host

var _player: Node3D
var _style: Node  # game/render_style.gd
var _env: Environment
var _sun: DirectionalLight3D
var _photo := false  # the look has a photo sky: regions tint it instead of swapping it for a painted one
var _tint := Color.WHITE
var _sky := Sky.new()
var _sky_colors := ProceduralSkyMaterial.new()
var _caster: Dictionary  # data/fantasy/spells.json "caster"
var _region := ""
var _place := ""
var _reach_told := {}  # "quest:step" reach steps already reported from where we stand
var _area := ""  # (polish1 item 129) the named area the player is in
var _timer := 0.0
var _buff := {}  # potion in effect: {"power", "armor", "until"}
var _regen_until := 0.0  # healing spells: health returns until this engine time
var _regen_rate := 0.0
var _hurt_at := -100.0  # (polish1 item 120) engine time of the last damage taken
var _last_hp := 0.0
var _in_safe := false  # inside a town / village / farm border (core/safe_places.gd)
var _mood := {}  # the sky, fog and light the current spot asks for (looked up twice a second, eased every frame)
var _busy := false  # true while rewards are being handed out (stops quest checks from nesting)
var _claimed := {}  # not the host: "quest:step" already reported as passed


func setup(player: Node3D, director: Node3D, style: Node, hud_layer: CanvasLayer, numbers: Node, settings: RefCounted) -> void:
	_player = player
	_style = style
	_env = style.get("env")
	_sun = style.get("sun")
	position = OFFSET
	data = FantasyData.load_all()
	LoadClock.mark("fantasy: data and writing files")
	for problem: String in data["problems"]:
		push_warning("Fantasy text: " + problem)
	terrain = FantasyTerrain.new(data["world"])
	bag = FantasyBag.new(data["gear"])
	skilling = data["skilling"]
	gather.cfg.merge(skilling.get("spots", {}), true)  # (polish1 item 114)
	skills = SkillLevels.new(skilling)
	quests = QuestLog.new(data["quests"])
	var spell_data: Dictionary = data["spells"]
	spells = SpellBook.new(spell_data)
	layout = FantasyLayout.new(terrain, data["layouts"], data["props"], skilling["nodes"])
	interiors = FantasyInteriors.new(data["interiors"], data["props"])
	layout.interiors = interiors
	_caster = spell_data["caster"]
	_sky.sky_material = _sky_colors
	sounds = FantasySounds.new()
	add_child(sounds)
	sounds.call("setup", data["sounds"])
	add_child(land)
	land.setup(terrain)
	LoadClock.mark("fantasy: rules, sounds, land set up")
	add_child(gather)
	add_child(scatter)
	scatter.setup(terrain, layout, land, gather, skilling)
	LoadClock.mark("fantasy: scatter set up")
	add_child(places)
	var folk := {}
	for region: Dictionary in terrain.regions:
		folk[String(region["id"])] = region["folk"]
	folk["guard"] = data["world"]["guard_folk"]
	places.setup(terrain, layout, folk)
	LoadClock.mark("fantasy: every place laid out")
	mana = max_mana()
	add_child(work)
	work.setup(self)
	add_child(snares)
	snares.setup(self)
	add_child(agility)
	agility.setup(self)
	add_child(rooms)
	rooms.setup(self, player)
	rooms.faded.connect(func() -> void: fade.emit())
	rooms.station_opened.connect(func(kind: String) -> void: _open_panel(func() -> void: panel.open_station(kind)))
	effects.source = director
	effects.numbers = numbers
	effects.caster = player
	effects.weakness = data["combat"]["weakness"]
	effects.words = data["combat"]["words"]
	effects.healed.connect(func(amount: float) -> void: _player.health.heal(amount))
	effects.landed.connect(_on_spell_landed)
	add_child(effects)
	add_child(marks)
	marks.source = director
	marks.effects = effects
	marks.setup(data["ground"])
	effects.touched.connect(marks.touch)
	add_child(squads)
	squads.source = director
	squads.setup(self, player, data["squad"])
	squads.safe.setup(terrain.places, data["squad"]["safe"])
	add_child(caster)
	caster.setup(self, player, effects)
	caster.cast_done.connect(_on_cast)
	caster.sequence_changed.connect(func(sequence: String) -> void:
		if sequence != "":
			sound("element_" + sequence.right(1).to_lower()))
	caster.refused.connect(func(_why: String) -> void: sound("refuse"))
	add_child(combat)
	combat.source = director
	combat.numbers = numbers
	combat.setup(self, player, data["combat"])
	caster.swung.connect(combat.strike)
	add_child(spawner)
	spawner.setup(self, director, player)
	LoadClock.mark("fantasy: work, rooms, spells, spawner")
	spawner.notice.connect(func(text: String) -> void: notice.emit(text))
	spawner.slain.connect(_on_slain)
	add_child(moves)
	moves.setup(self, player)
	moves.bodies = spawner.bodies
	moves.reach_m = float(data["enemies"]["spawn"]["boss_leash_m"])
	spawner.boss_woke.connect(moves.watch)
	spawner.armed.connect(moves.watch)
	moves.allies = Callable(director, "enemy_list")
	spawner.boss_woke.connect(func(boss: Node3D, _moves: Array) -> void: sound("boss_wake", boss.global_position))
	moves.started.connect(_on_move_started)
	moves.summoned.connect(func(id: String, x: float, z: float) -> void: spawner.spawn_local(id, x, z, _player))
	var hud := FantasyHud.new()
	hud_node = hud
	hud.world = self
	hud.work = work
	hud.spawner = spawner
	hud.settings = settings
	hud_layer.add_child(hud)
	var box := ElementBox.new()
	box.caster = caster
	box.world = self
	box.settings = settings
	hud_layer.add_child(box)
	map.world = self
	map.settings = settings
	hud_layer.add_child(map)
	panel.world = self
	panel.work = work
	hud_layer.add_child(panel)
	panel.closed.connect(func() -> void: _player.set("controls_enabled", true))
	work.talk_opened.connect(func(person: Dictionary) -> void: _open_panel(func() -> void: panel.open_talk(person)))
	panel.closed.connect(func() -> void: sound("ui_close"))
	work.station_opened.connect(func(kind: String) -> void: _open_panel(func() -> void: panel.open_station(kind)))


func _open_panel(how: Callable) -> void:
	sound("ui_open")
	_player.set("controls_enabled", false)
	how.call()


func panel_open() -> bool:
	return panel.is_open()


# Esc: closes the menu panel if it is open. Returns true if it did.
func close_panel() -> bool:
	if map.is_open() and not panel.is_open():
		map.close()
		return true
	if not panel.is_open():
		return false
	panel.close_panel()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not inside or caster.channelling:
		return
	if event.is_action_pressed("map") and not panel.is_open():
		map.toggle()
		get_viewport().set_input_as_handled()
		return
	for page: String in ["skills", "quests"]:
		if event.is_action_pressed(page):
			if panel.is_open():
				panel.close_panel()
			else:
				_open_panel(func() -> void: panel.open(page.capitalize()))
			get_viewport().set_input_as_handled()


# The interact prompt and key (the session asks when nothing of its own is in reach).
func prompt(key: String) -> String:
	if panel.is_open():
		return ""
	var ours := rooms.prompt(key)
	return ours if ours != "" or rooms.inside() else work.prompt(key)


func interact() -> void:
	if not panel.is_open() and not rooms.interact():
		work.interact()


func _on_cast(spell: Dictionary, sequence: String, origin: Vector3, aim: Vector3) -> void:
	panel.note_cast(spell, sequence)
	spell_cast.emit(String(spell.get("name", "")), String(spell.get("substance", "")))
	squads.note_cast(sequence)
	sound("cast_" + String((spell.get("look", {}) as Dictionary).get("shape", "puff")), origin)
	if String(spell.get("secret", "")) != "":
		sound("cast_big", origin)
	if party != null:
		party.call("send_cast", sequence, origin, aim)


# A pure fire spell that lands near the caster lights the best log in the bag.
func _on_spell_landed(_kind: String, at: Vector3, spell: Dictionary) -> void:
	sound("impact", at)
	if String(spell.get("substance", "")) == "F":  # a fire spell landing on laid logs lights them (polish1 item 107)
		var pile: int = places.pile_near(local_of(at), 3.0)
		if pile >= 0:
			var laid: Dictionary = places.take_pile(pile)
			light_fire(String(laid["log"]), laid["at"])


func _on_move_started(boss: Node3D, index: int, at: Vector3, roll: int) -> void:
	show_move(boss, index)
	if party != null and not party.call("is_client"):
		party.call("send_move", boss, index, at, roll)


# The name of a boss's special attack flashes on the HUD in the attack's own colour.
func show_move(boss: Node3D, index: int) -> void:
	var list: Array = spawner.stats_of(String(boss.get("enemy_id"))).get("moves", [])
	if index >= 0 and index < list.size() and bool(spawner.stats_of(String(boss.get("enemy_id"))).get("boss", false)):  # only a boss's attack is announced by name
		var c: Array = list[index].get("color", [1.0, 0.6, 0.3])
		boss_move.emit(String(list[index]["name"]), Color(c[0], c[1], c[2]))


# Plays one of the world's sounds (data/fantasy/sounds.json) at a world position, or flat when no position is given.
func sound(id: String, at: Vector3 = Vector3.INF) -> void:
	if sounds != null:
		sounds.call("play", id, at)


func _on_slain(enemy_id: String, where: Vector3) -> void:
	sound("creature_fall", where)
	if inside:
		spawner.pay(enemy_id)
	var at := local_of(where)
	report({"type": "kill", "enemy": String(spawner.stats_of(enemy_id).get("phantom_of", enemy_id)), "areas": terrain.areas_at(at.x, at.z)})  # (polish1 E4) an echo counts as its boss
	if party != null and not party.call("is_client"):
		party.call("send_slain", enemy_id)


# Hunting: tracks followed at `at` lay a trail of prints onward, away from the player, to where the animal is met
# (25-35 m on). Online a party member's animal is put there by the host.
func follow_tracks(animal: String, at: Vector3) -> void:
	var from := player_local()
	var way := Vector2(at.x - from.x, at.z - from.z)
	way = way.normalized() if way.length() > 0.3 else Vector2.from_angle(randf() * TAU)
	way = way.rotated(randf_range(-0.5, 0.5))
	var reach := randf_range(25.0, 35.0)
	var end := Vector3(at.x + way.x * reach, 0.0, at.z + way.y * reach)
	snares.show_trail(at, end, animal in ["boar"])
	if party != null and party.call("is_client"):
		party.call("send_event", {"type": "track", "animal": animal, "x": end.x, "z": end.z})
	else:
		meet_animal(animal, end.x, end.z)


func meet_animal(animal: String, x: float, z: float) -> void:
	if String(spawner.stats_of(animal).get("skill", "")) != "hunting":
		return
	spawner.spawn_local(animal, x, z, _player)


# Command /spawn inside this world: a creature that counts for experience, drops and quests.
func spawn_creature(id: String, near: Node3D) -> bool:
	return spawner.spawn_at(id, near)


# Where a fallen player wakes up: the nearest town, farm or camp.
func haven_world() -> Vector3:
	return world_of(places.haven_near(player_local()))


# --- where things are ---

func local_of(world: Vector3) -> Vector3:
	return world - OFFSET


func world_of(local: Vector3) -> Vector3:
	return local + OFFSET


func player_local() -> Vector3:
	return _player.global_position - OFFSET


# A point of the map standing on the ground, as a world position.
func ground_world(x: float, z: float) -> Vector3:
	return world_of(Vector3(x, terrain.height(x, z) + 0.3, z))


# The land's own height under a WORLD x, z (sea beds included: the player's automatic unstuck, game/unstuck.gd).
func land_height(x: float, z: float) -> float:
	return terrain.height(x - OFFSET.x, z - OFFSET.z)


# (polish1 item 159) The ground as it is DRAWN and collides (the chunk meshes, cell by cell) under a WORLD x, z: on a
# bumpy hill the smooth terrain rule can stand 0.5 m over the mesh between its vertices, so the automatic unstuck
# took a player walking on the mesh for one buried in the hill and lifted him (up and down = the rubber band).
func drawn_height(x: float, z: float) -> float:
	var g := land.ground(x - OFFSET.x, z - OFFSET.z)
	return g.x if not is_nan(g.x) else land_height(x, z)


# Land height under a WORLD x, z (creatures walk on this; never below the shallows).
func ground_height(x: float, z: float) -> float:
	return maxf(terrain.height(x - OFFSET.x, z - OFFSET.z), terrain.sea - 0.5)


func spawn_world() -> Vector3:
	var spawn: Array = terrain.data["spawn"]
	return ground_world(float(spawn[0]), float(spawn[1]))


func farm_world() -> Vector3:
	var farm := terrain.place("hale_farm")
	return ground_world(float(farm["pos"][0]) - 6.0, float(farm["pos"][1]) - 4.0)


# Where a creature at `from` ends up after trying to move by `step` (both world space). Land creatures go around
# houses, walls, trees and deep water, swimmers cross water, fliers cross everything `hover` metres up. No physics is
# involved, so the host can run creatures where it has no colliders loaded and every machine agrees.
func walk_world(from: Vector3, step: Vector3, pad: float, mode: int, hover: float) -> Vector3:
	var x := from.x - OFFSET.x
	var z := from.z - OFFSET.z
	if mode == WALK_FLY:
		x += step.x
		z += step.z
		return Vector3(x + OFFSET.x, maxf(terrain.height(x, z), terrain.sea) + hover, z + OFFSET.z)
	var to := layout.walk(x, z, step.x, step.z, pad, mode == WALK_SWIM)
	var ground := terrain.height(to.x, to.y)
	if mode != WALK_SWIM and ground - from.y > 0.9 * Vector2(to.x - x, to.y - z).length() + 0.02:
		# steeper than a creature can run up: it scrambles, at a third of its pace
		to = Vector2(x, z).lerp(to, 0.35)
		ground = terrain.height(to.x, to.y)
	return Vector3(to.x + OFFSET.x, maxf(ground, terrain.sea - 0.5), to.y + OFFSET.z)


# The sky photo takes the region's colour. Changing it re-lights the scene from the sky, so it moves in a few steps
# (twice a second while it still differs), not every frame.
func _set_tint(k: float) -> void:
	if not _photo:
		return
	var horizon: Color = _mood["sky_horizon"]
	var top: Color = _mood["sky_top"]
	var peak := maxf(maxf(horizon.r, horizon.g), maxf(horizon.b, 0.05))
	var bright := clampf((top.r + top.g + top.b) / 1.35 + 0.35, 0.45, 1.1)
	var want := Color.WHITE.lerp(Color(horizon.r / peak, horizon.g / peak, horizon.b / peak), 0.55) * bright
	if absf(want.r - _tint.r) + absf(want.g - _tint.g) + absf(want.b - _tint.b) < 0.02 and k < 1.0:
		return
	_tint = _tint.lerp(want, k)
	_style.call("set_sky_tint", _tint)


func exit_world() -> Vector3:
	var at: Array = terrain.data["exit_painting"]
	return ground_world(float(at[0]), float(at[1])) - Vector3(0.0, 0.3, 0.0)


# --- coming and going ---

# Loads the land around a point (behind the fade) and switches the sky and light to this world's.
func enter(world_pos: Vector3) -> void:
	inside = true
	rooms.reset()
	var local := local_of(world_pos)
	land.load_now(local)
	LoadClock.mark("fantasy: ground under the player")
	scatter.follow(land.key_at(local))
	LoadClock.mark("fantasy: trees and grass")
	places.follow(local)
	LoadClock.mark("fantasy: places near the player")
	_photo = bool(_style.call("has_photo_sky"))
	if not _photo:  # a look without a photo sky (toon, vivid ...): this world's own plain sky
		_env.background_mode = Environment.BG_SKY
		_env.sky = _sky
		_env.sky_rotation = Vector3.ZERO
		_env.fog_sky_affect = 0.08
	_env.fog_enabled = true
	_mood = terrain.mood(local.x, local.z)
	_blend_mood(1.0)
	_set_tint(1.0)
	_region = ""
	_place = ""
	apply_stats()
	refresh_marks()
	combat.set_active(true)
	if party == null or not party.call("is_client"):
		spawner.start()  # online only the host runs creatures (game/net_fantasy.gd)


func leave() -> void:
	inside = false
	snares.clear()
	_player.set("skill_speed_pct", 0.0)
	if party == null:
		spawner.stop()  # online the host keeps running them for whoever is still in there
	effects.clear()
	marks.clear()
	squads.clear()
	moves.clear()
	combat.set_active(false)
	rooms.reset()
	sounds.call("set_region", "")
	sounds.call("set_town", false)
	panel.close_panel()
	_style.call("set_sky_tint", Color.WHITE)
	_player.set("guns_locked", false)
	_player.call("set_world_bonus", 0.0, 1.0)


# Graphics tier: how much land, trees and grass are kept around the player.
# Lower tiers give up detail and movement step by step. `motion`: 0 nothing moves on its own, 1 creatures' limbs and
# windmill sails, 2 people breathe too, 3 grass sways and the staff's ring turns as well. `bits`: share of spell bits.
# `plain_buildings`: 1 = towns are built from the plain building models (a place already standing keeps the models
# it was built with until the player has been away from it).
func set_detail(detail: Dictionary) -> void:
	land.radius = int(detail.get("chunks", 4))
	scatter.tree_radius = int(detail.get("trees", 3))
	scatter.tuft_radius = int(detail.get("grass", 2))
	scatter.tuft_scale = float(detail.get("blades", 1.0))
	places.show_at = float(detail.get("places_m", 240.0))
	places.prop_share = float(detail.get("props", 1.0))
	places.folk_share = float(detail.get("folk", 1.0))
	places.small_m = float(detail.get("small_m", 100.0))
	places.plain = int(detail.get("plain_buildings", 0)) > 0
	rooms.prop_share = float(detail.get("props", 1.0))
	rooms.real_views = int(detail.get("views", 1)) > 0
	var motion := int(detail.get("motion", 3))
	places.motion = motion
	EnemyBody.limbs_move = motion >= 1
	scatter.set_wind(motion >= 3)
	caster.ring_turns = motion >= 3
	effects.motes.share = float(detail.get("bits", 1.0))


func _process(delta: float) -> void:
	if not inside:
		return
	var local := rooms.anchor() if rooms.inside() else player_local()  # indoors the player counts as standing at the door
	land.follow(local)
	scatter.follow(land.key_at(local))
	_blend_mood(1.0 - exp(-1.5 * delta))
	var now := Time.get_ticks_msec() / 1000.0
	var near_fire := places.fire_near(local, float(skilling["fire"]["radius"]) * (1.0 + perk("firemaking", "fire_radius")))
	var fire_mult := float(skilling["fire"]["mana_regen_mult"]) * (1.0 + perk("firemaking", "fire_regen"))
	mana = minf(mana + mana_regen() * (fire_mult if near_fire else 1.0) * delta, max_mana())
	if now < _regen_until:
		_player.health.heal(_regen_rate * delta)
	var hp_now: float = _player.health.hp  # (polish1 item 120) health comes back by itself: slowly out of a fight, fast in a town or on a farm
	if hp_now < _last_hp - 0.01:
		_hurt_at = now
	_last_hp = hp_now
	var calm: Dictionary = data["combat"].get("regen", {})
	if now - _hurt_at >= float(calm.get("calm_s", 8.0)) and hp_now > 0.0:
		_player.health.heal(_player.health.max_hp * float(calm.get("safe_pct" if _in_safe else "out_pct", 1.0)) / 100.0 * delta)
		_last_hp = _player.health.hp
	_timer += delta
	if _timer < 0.5:
		return
	_timer = 0.0
	_mood = terrain.mood(local.x, local.z)
	_set_tint(0.3)
	places.follow(local)
	agility.follow(local)
	if not _buff.is_empty() and now >= float(_buff["until"]):
		_buff = {}
		apply_stats()
	_in_safe = squads.safe.place_at(Vector2(local.x, local.z)) >= 0
	sounds.call("set_town", _in_safe)
	var region := terrain.region_at(local.x, local.z)
	if String(region["id"]) != _region:
		_region = String(region["id"])
		sounds.call("set_region", _region)
		_find(_region)
		notice.emit("%s  (levels %d-%d)" % [region["name"], int(region["level"][0]), int(region["level"][1])])
	var here := ""
	for place: Dictionary in terrain.places:
		if Vector2(local.x - float(place["pos"][0]), local.z - float(place["pos"][1])).length() < float(place["flat"]):
			here = String(place["id"])
	if here != _place:
		_place = here
		if here != "":
			notice.emit(String(terrain.place(here)["name"]))
			_find(here)
			report({"type": "reach", "place": here})
	var area_here := ""  # (polish1 item 129) named areas: told on the way in, then named on the map and the compass
	for id: String in terrain.areas_at(local.x, local.z):
		area_here = id
	if area_here != _area:
		_area = area_here
		if area_here != "" and here == "":
			notice.emit(String(terrain.area_by_id(area_here)["name"]))
		if area_here != "":
			_find(area_here)


# The region's weather over the chosen look. With a photo sky only the haze, the sun's colour and the sky's tint
# change (the photo keeps lighting the shade); a plain look gets this world's own sky colours and ambient light.
func _blend_mood(k: float) -> void:
	var m := _mood
	_env.fog_light_color = _env.fog_light_color.lerp(m["fog"], k)
	_env.fog_density = lerpf(_env.fog_density, float(m["density"]), k)
	if _photo:
		_sun.light_color = _sun.light_color.lerp(Color.WHITE.lerp(m["sun"], 0.6), k)
		return
	_sky_colors.sky_top_color = _sky_colors.sky_top_color.lerp(m["sky_top"], k)
	_sky_colors.sky_horizon_color = _sky_colors.sky_horizon_color.lerp(m["sky_horizon"], k)
	_sky_colors.ground_horizon_color = _sky_colors.sky_horizon_color
	_sky_colors.ground_bottom_color = _sky_colors.sky_horizon_color.darkened(0.35)
	_env.ambient_light_color = _env.ambient_light_color.lerp((m["ambient"] as Color) * 0.72, k)
	_sun.light_color = _sun.light_color.lerp(m["sun"], k)


# --- the player's strength ---

func magic_level() -> int:
	return skills.level("magic")


func max_mana() -> float:
	return (float(_caster["mana_base"]) + float(_caster["mana_per_level"]) * float(magic_level() - 1) + float(bag.staff().get("mana", 0.0))) * (1.0 + perk("magic", "mana"))


func mana_regen() -> float:
	return (float(_caster["regen"]) + float(_caster["regen_per_level"]) * float(magic_level() - 1) + float(bag.robe().get("regen", 0.0))) * (1.0 + perk("magic", "regen"))


# How many elements one cast can hold: the staff's own, plus one for each pigment the story has returned.
func slots() -> int:
	return spells.slots(int(bag.staff().get("slots", 0)), quests.pigments(), magic_level())


# Spell damage after staff, Magic level and potions.
func spell_power(amount: float) -> float:
	return SpellBook.scaled(amount, float(bag.staff().get("power", 1.0)), magic_level(), float(_caster["damage_per_level"])) * float(_buff.get("power", 1.0)) * (1.0 + perk("magic", "power"))


# Pushes health, armour and the gun lock onto the player (call after anything that changes them).
func apply_stats() -> void:
	if not inside:
		return
	var hp := float(_caster["hp_per_level"]) * float(magic_level() - 1) + float(bag.robe().get("hp", 0.0))
	var armor := clampf(float(bag.robe().get("armor", 0.0)) + float(_buff.get("armor", 0.0)) + perk("magic", "armor"), 0.0, 0.8)
	_player.call("set_world_bonus", hp, 1.0 - armor)
	_player.set("skill_speed_pct", perk("agility", "run_speed"))  # Agility: quicker on your feet here (and at sea)
	_player.set("guns_locked", not quests.guns_unlocked())
	_player.call("refresh_held")
	mana = minf(mana, max_mana())


# Command /heal: full health and mana.
func refill() -> void:
	mana = max_mana()


func heal_over_time(per_second: float, seconds: float) -> void:
	_regen_rate = per_second
	_regen_until = Time.get_ticks_msec() / 1000.0 + seconds


# --- experience, items, quests ---

# (polish1 E4, item 131) This player's share of a great creature's fall (every machine pays its own player): the
# boss's relic the first time (any form), its trophies (the session), the vanquished page and its sound.
func boss_paid(enemy_id: String, stats: Dictionary) -> void:
	var phantom := stats.has("phantom_of")
	var boss := String(stats.get("phantom_of", enemy_id))
	var won: Array = []
	var relic := String(spawner.stats_of(boss).get("relic", ""))
	if relic != "" and bag.count(relic) <= 0:
		give(relic, 1)
		won.append("Relic: %s  (worn in your bag's relic slot)" % bag.item_name(relic))
	if trophy_gift.is_valid():
		won.append_array(trophy_gift.call(boss, phantom, data["enemies"].get("phantom", {})))
	sound("echo_fade" if phantom else "boss_fall")
	vanquished.emit(String(stats.get("name", boss)), phantom, won)


# The sum of one perk of `skill` at its current level (core/skill_perks.gd; 0 when none).
func perk(skill: String, key: String) -> float:
	return SkillPerks.total(skilling.get("unlocks", {}), skill, skills.level(skill), key) + bag.relic_perk(skill, key)  # (polish1 E4) the worn relic too


func gain_xp(skill: String, amount: int) -> void:
	if amount <= 0:
		return
	var before := skills.level(skill)
	skills.add_xp(skill, amount)
	var tint: Array = skilling["skills"][skill]["color"]
	toast.emit("+%d %s" % [amount, skills.skill_name(skill)], Color(tint[0], tint[1], tint[2]))
	if skills.level(skill) > before:
		var opened := PackedStringArray()
		for step: Dictionary in SkillPerks.reached(skilling.get("unlocks", {}), skill, before, skills.level(skill)):
			opened.append(String(step.get("name", "")))
		skill_up.emit(skill, skills.level(skill), opened)
		sound("level_up")
		apply_stats()
	_after_change()


func give(item: String, count: int = 1) -> void:
	if count <= 0 or not bag.has_item(item):
		return
	if String(bag.def(item).get("kind", "")) == "gunside":  # Crafting made a piece for the gun side: into the backpack
		_make_gun_piece(bag.def(item), count)
		return
	if String(bag.def(item).get("kind", "")) == "ship_part":  # Carpentry made a ship's part (a crane): fitted to a ship
		ship_part_made.emit(String(bag.def(item)["part"]))
		sound("item")
		return
	if String(bag.def(item).get("kind", "")) == "ship":  # Carpentry built a ship at the slipway: it is launched into the sea
		ship_built.emit(String(bag.def(item)["ship"]))
		sound("item")
		return
	if String(bag.def(item).get("kind", "")) == "backpack":  # Crafting made a bag: the gun side's backpack grows
		var size := int(bag.def(item)["bag"])
		if int(_player.inventory.bags) < size:
			_player.inventory.set_bags(size)
			sound("item")
			toast.emit("Your backpack holds %d now" % int(_player.inventory.slot_count), Color.WHITE)
			_after_change()
		return
	var staff_before := String(bag.equipped.get("staff", ""))
	bag.add(item, count)
	sound("item")
	picked.emit(item, count)
	if String(bag.equipped.get("staff", "")) != staff_before:
		notice.emit("Now wielding: %s" % bag.item_name(String(bag.equipped["staff"])))
	apply_stats()
	_after_change()


# A Crafting piece for the gun side's gear: a rolled armour piece of the item's base at its tier and item level, or
# (perk "finer") one tier better, put straight into the gun side's backpack.
func _make_gun_piece(def: Dictionary, count: int) -> void:
	var tiers: Array = ["grey", "green", "blue", "purple", "gold"]
	for _i in count:
		var tier := String(def["tier"])
		if randf() < perk("crafting", "finer") + town_finer and tiers.find(tier) >= 0 and tiers.find(tier) < tiers.size() - 1:
			tier = String(tiers[tiers.find(tier) + 1])
		var piece := ArmourGen.generate(_player.items, _craft_rng, tier, int(def["lvl"]), String(def["base"]), "")
		if _player.inventory.add_armour(piece):
			sound("item")
			toast.emit("+%s (Lv %d) in your backpack" % [String(_player.items.item_name(String(def["base"]))), int(def["lvl"])], Color.WHITE)
		else:
			notice.emit("Your backpack is full.")
	_after_change()


# The bags the gun side's backpack has (0..3).
func gun_bags() -> int:
	return int(_player.inventory.bags)


# True while the gun side's backpack can take a crafted piece.
func gun_room() -> bool:
	return _player.inventory.has_room()


# Eats, drinks or lights an item from the bag. Returns what to tell the player ("" = done silently).
func use_item(item: String) -> String:
	var def := bag.def(item)
	match String(def.get("kind", "")):
		"food", "potion":
			if not bag.remove(item, 1):
				return "You have none."
			sound("drink")
			var boost := 1.0 + (perk("cooking", "heal") if String(def["kind"]) == "food" else perk("alchemy", "potency"))
			_player.health.heal(float(def.get("heal", 0.0)) * boost)
			mana = minf(mana + float(def.get("mana", 0.0)) * boost, max_mana())
			if def.has("buff"):
				_buff = (def["buff"] as Dictionary).duplicate()
				_buff["until"] = Time.get_ticks_msec() / 1000.0 + float(_buff["seconds"]) * boost
				apply_stats()
			_after_change()
			return ""
		"trap":
			var why := snares.place(player_local(), item)
			_after_change()
			return why
		"staff", "robe", "tool", "relic":
			bag.equip(item)
			apply_stats()
			_after_change()
			return ""
	if (skilling["fire"]["level"] as Dictionary).has(item):
		return lay_logs(item)
	return "Nothing to do with that."


# (polish1 item 107) Firemaking takes two acts: logs laid on the ground (using a log from the bag), then lit with a
# fire spell landing on them. Casting Ember anywhere no longer burns a log out of the bag.
func lay_logs(item: String) -> String:
	if skills.level("firemaking") < int(skilling["fire"]["level"][item]):
		return "Needs Firemaking %d." % int(skilling["fire"]["level"][item])
	if bag.count(item) <= 0:
		return "You have none."
	bag.remove(item, 1)
	places.lay_logs(player_local() - _player.global_basis.z * 1.2, item)
	_after_change()
	notice.emit("Logs laid. Light them with a fire spell.")
	return ""


# Firemaking: a laid pile of `item` logs at `local` catches fire (the log left the bag when it was laid; Kindler
# sometimes gives it back).
func light_fire(item: String, local: Vector3) -> String:
	var fire: Dictionary = skilling["fire"]
	if randf() < perk("firemaking", "save"):  # Kindler: sometimes the log is not used up
		bag.add(item, 1)
	places.light_fire(local, float(fire["seconds"]) * (1.0 + perk("firemaking", "fire_time")))
	sound("fire_light", world_of(local))
	gain_xp("firemaking", int(fire["xp_per_log"][item]))
	report({"type": "fire"})
	return ""


# The best log the player may burn right now ("" = none).
func best_log() -> String:
	var fire: Dictionary = skilling["fire"]
	var best := ""
	for item: String in fire["level"]:
		if bag.count(item) > 0 and skills.level("firemaking") >= int(fire["level"][item]):
			if best == "" or int(fire["level"][item]) > int(fire["level"][best]):
				best = item
	return best


# Something happened that quests may be waiting for (see core/quest_log.gd `note`). Online, the host keeps the log.
func report(event: Dictionary) -> void:
	if party != null and party.call("is_client"):
		party.call("send_event", event)
		return
	_apply(quests.note(event))


# Host: a party member's machine reported an event or says its own bag passes a step.
func host_event(event: Dictionary) -> void:
	if String(event["type"]) == "track":  # a party member followed tracks: their animal is met where the trail ends
		meet_animal(String(event.get("animal", "")), float(event.get("x", 0.0)), float(event.get("z", 0.0)))
		return
	_apply(quests.note(event))


func host_claim(quest_id: String, step: int) -> void:
	_apply(quests.claim(quest_id, step))


# Not the host: the party's quest log as the host has it.
func adopt_log(saved: Dictionary) -> void:
	var before := quests.active.keys()
	quests.from_dict(saved)
	for id: String in quests.active:
		if not before.has(id):
			notice.emit("New quest: %s" % quests.quest(id)["name"])
	_claimed.clear()
	refresh_marks()
	apply_stats()
	_after_change()


# Another player's spell, drawn here (their machine and the host decide what it hits).
func show_cast(sequence: String, origin: Vector3, aim: Vector3) -> void:
	var spell := spells.resolve(sequence)
	if not spell.is_empty():
		effects.cast(spell, origin, aim, origin + aim * 0.8, 0.0, 0.0, true)


func accept(quest_id: String) -> void:
	if party != null and party.call("is_client"):
		party.call("send_accept", quest_id)
		return
	if quests.start(quest_id):
		var quest := quests.quest(quest_id)
		notice.emit("New quest: %s" % quest["name"])
		sound("quest_accept")
		_after_change()
		_synced()


# (polish1 item 114) A node used up by this player. Alone it is decided here; the host decides and tells everyone; a
# party member hides it at once and asks the host, whose word (hibernation, a spot waking) comes back to all.
func gather_use(node: Dictionary, seconds: float) -> void:
	if party != null and party.call("is_client"):
		gather.spend(node, seconds)
		party.call("send_node_use", "%d:%d:%d" % [(node["key"] as Vector2i).x, (node["key"] as Vector2i).y, int(node["slot"])], seconds)
		return
	var change := gather.use(node, seconds)
	if party != null:
		party.call("send_node_change", change)


func _after_change() -> void:
	if party != null and party.call("is_client"):
		_claim_steps()
	elif not _busy:
		_apply(quests.check(bag.items.duplicate(), skills.levels()))
	_reach_here()
	changed.emit()


# (2026-11-23) A "reach" step that begins while we already stand in that place passes at once (entering is what
# reports it, and we are not entering: e.g. Warden Oska's quest starts with "reach Fernhollow" while we stand in it).
func _reach_here() -> void:
	if _place == "" or _busy:
		return
	for id: String in quests.active.keys():
		var step := quests.step(id)
		if String(step.get("type", "")) == "reach" and String(step["place"]) == _place:
			var tag := "%s:%d" % [id, int(quests.active[id]["step"])]
			if _reach_told.has(tag):
				continue
			_reach_told[tag] = true
			report({"type": "reach", "place": _place})
			return


# Not the host: tell the host when our own bag or skills pass the step a party quest is on (items handed in leave
# our bag here). Each step is claimed once; the host's next log update clears the list.
func _claim_steps() -> void:
	for id: String in quests.active:
		var step := quests.step(id)
		var tag := "%s:%d" % [id, int(quests.active[id]["step"])]
		if _claimed.has(tag):
			continue
		var passed := false
		if String(step["type"]) == "have" and bag.count(String(step["item"])) >= int(step["count"]):
			passed = true
			if bool(step.get("take", false)):
				bag.remove(String(step["item"]), int(step["count"]))
				notice.emit("Handed over %d %s" % [int(step["count"]), bag.item_name(String(step["item"]))])
		elif String(step["type"]) == "skill" and skills.level(String(step["skill"])) >= int(step["level"]):
			passed = true
		if passed:
			_claimed[tag] = true
			party.call("send_claim", id, int(quests.active[id]["step"]))


func _apply(changes: Array) -> void:
	if changes.is_empty():
		return
	_busy = true
	for change: Dictionary in changes:
		for item: String in change.get("take", {}):
			bag.remove(item, int(change["take"][item]))
			notice.emit("Handed over %d %s" % [int(change["take"][item]), bag.item_name(item)])  # (polish1 item 161) never silently
		if bool(change["finished"]):
			reward(String(change["quest"]))
			if party != null:
				party.call("send_reward", String(change["quest"]))
	_busy = false
	refresh_marks()
	_synced()
	_after_change()


func _synced() -> void:
	if party != null and not party.call("is_client"):
		party.call("send_log")


# Hands out a finished quest's rewards (online: every party member runs this for their own bag and skills).
func reward(quest_id: String) -> void:
	var quest := quests.quest(quest_id)
	var rewards: Dictionary = quest["rewards"]
	notice.emit("Quest complete: %s" % quest["name"])
	sound("quest_done")
	said.emit("%s: %s" % [places.person(String(quest["giver"])).get("name", "?"), quest["done"]], GOLD)
	for item: String in rewards.get("items", {}):
		bag.add(item, int(rewards["items"][item]))
		picked.emit(item, int(rewards["items"][item]))
	for skill: String in rewards.get("skill_xp", {}):
		gain_xp(skill, int(rewards["skill_xp"][skill]))
	gain_xp("magic", int(rewards.get("xp", 0)))
	if bool(rewards.get("pigment", false)):
		said.emit("A colour returns to Aurelind. Your staff now holds %d elements." % slots(), GOOD)
	if rewards.has("secret"):
		var secret := spells.secret_for_id(String(rewards["secret"]))
		said.emit("Learned %s: %s" % [secret["name"], spells.spell_out(String(secret["sequence"]))], GOOD)
	if bool(rewards.get("unlock_guns", false)):
		said.emit("The painting is whole again. Your guns work here now.", GOOD)
	apply_stats()


# "!" over people with a quest to give, "..." over people the open quests point at.
# The map: a region or place the player has now been to.
func _find(id: String) -> void:
	if not found.has(id):
		found[id] = true
		changed.emit()


# Where the map shows a quest mark: "!" someone there has a quest to give, "..." an active quest points there.
func map_marks() -> Array:
	var out: Array = []
	var seen := {}
	for id in quests.active:
		var step := quests.step(id)
		var where := ""
		match String(step.get("type", "")):
			"talk":
				where = String(places.person(String(step["npc"])).get("place", ""))
			"reach":
				where = String(step["place"])
			"kill":  # (polish1 item 129) a kill step bound to a named area points there
				if step.has("area"):
					var area := terrain.area_by_id(String(step["area"]))
					if not area.is_empty() and not seen.has(String(step["area"])):
						seen[String(step["area"])] = true
						out.append({"x": float(area["x"]), "z": float(area["z"]), "mark": "..."})
		if where != "" and not seen.has(where):
			seen[where] = true
			var p := terrain.place(where)
			out.append({"x": float(p["pos"][0]), "z": float(p["pos"][1]), "mark": "..."})
	var givers := {}  # (polish1 item 123) place -> names of the people there with a quest to give
	for npc: Dictionary in terrain.data["npcs"]:
		if not quests.offers(String(npc["id"])).is_empty():
			var at := String(npc["place"])
			givers[at] = (String(givers[at]) + ", " if givers.has(at) else "") + String(places.person(String(npc["id"])).get("name", ""))
	for where: String in givers:
		if not seen.has(where):
			seen[where] = true
			var p := terrain.place(where)
			out.append({"x": float(p["pos"][0]), "z": float(p["pos"][1]), "mark": "!", "who": String(givers[where])})
	return out


func player_yaw() -> float:
	return float(_player.call("look_yaw"))


# The line in the quest card before anything has been started (writers' file, [world] first hint).
func first_hint() -> String:
	return String(terrain.data.get("first_hint", ""))


# The id of the place the player is in ("" = open country).
func place_here() -> String:
	return _place


# Indoors the sun does not reach: a room is lit by its own lamp.
func set_indoors(on: bool) -> void:
	_sun.visible = not on


func refresh_marks() -> void:  # (polish1 item 101) grey "?" in progress, gold "?" to be spoken to now, "!" a quest to give, nothing otherwise
	var over_heads := {}
	for id in quests.active:
		over_heads[String(quests.quest(id)["giver"])] = "?grey"
	for person: Dictionary in places.people:
		if not quests.offers(String(person["id"])).is_empty():
			over_heads[String(person["id"])] = "!"
	for id in quests.active:
		var step := quests.step(id)
		if String(step.get("type", "")) == "talk":
			over_heads[String(step["npc"])] = "?gold"
	places.set_marks(over_heads)


# --- travel and commands ---

# Moves the player to a named place or region. Returns what to say, or "" when the name is unknown.
func travel(target: String) -> String:
	for place: Dictionary in terrain.places:
		if String(place["id"]) == target:
			var x := float(place["pos"][0])
			var z := float(place["pos"][1])
			rooms.reset()
			layout.prepare(x, z)
			var free := layout.push_out(x, z + float(place["flat"]) * 0.5, 1.2)
			for i in 24:  # the first open spot near the middle, with room to look around (never inside a house)
				var a := TAU * float(i % 8) / 8.0
				var r := 9.0 if i < 8 else (14.0 if i < 16 else 5.0)
				if not layout.blocked(x + cos(a) * r, z + sin(a) * r, 2.5):
					free = Vector2(x + cos(a) * r, z + sin(a) * r)
					break
			_player.call("teleport", ground_world(free.x, free.y), 0.0)
			_player.call("look_at_point", ground_world(x, z) + Vector3(0.0, 1.6, 0.0))
			land.load_now(player_local())
			return "Moved to %s." % place["name"]
	for region: Dictionary in terrain.regions:
		if String(region["id"]) == target:
			_player.call("teleport", ground_world(float(region["center"][0]), float(region["center"][1])), 0.0)
			land.load_now(player_local())
			return "Moved to %s." % region["name"]
	return ""


func place_names() -> PackedStringArray:
	var out := PackedStringArray()
	for region: Dictionary in terrain.regions:
		out.append(String(region["id"]))
	for place: Dictionary in terrain.places:
		out.append(String(place["id"]))
	return out


# Admin commands that belong to this world (game/admin_commands.gd passes them on).
func command(command_name: String, args: PackedStringArray, usage: String) -> PackedStringArray:
	var out := PackedStringArray()
	match command_name:
		"skill":
			if args.size() < 2 or not (args[0] == "all" or skills.ids().has(args[0])) or not args[1].is_valid_int():
				return PackedStringArray([usage, "Skills: " + ", ".join(PackedStringArray(skills.ids()))])
			for id: String in skills.ids():
				if args[0] == "all" or args[0] == id:
					skills.set_level(id, clampi(int(args[1]), 1, skills.max_level()))
					out.append("%s is now level %d." % [skills.skill_name(id), skills.level(id)])
		"spells":
			for secret: Dictionary in spells.data["secrets"]:
				out.append("%s: %s" % [secret["name"], spells.spell_out(String(secret["sequence"]))])
			return out
		"slots":
			out.append("Each cast holds %d elements (staff %s, %d pigments)." % [slots(), bag.item_name(String(bag.equipped.get("staff", ""))), quests.pigments()])
			return out
		"gear":
			if args.is_empty() or not (args[0] in ["all", "list"] or bag.has_item(args[0])):
				return PackedStringArray([usage])
			if args[0] == "list":
				return PackedStringArray([", ".join(PackedStringArray(bag.all_ids()))])
			if args[0] == "all":
				for item: String in bag.all_ids():
					bag.add(item, 1 if bag.slot_of(item) != "" else 20)
				out.append("Every fantasy item is in your bag.")
			else:
				bag.add(args[0], int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 1)
				out.append("Added %s." % bag.item_name(args[0]))
		"quest":
			var what := args[0] if not args.is_empty() else ""
			var id := args[1] if args.size() > 1 else ""
			if what == "list":
				for open_id: String in quests.active:
					out.append("%s  %s: %s" % [open_id, quests.quest(open_id)["name"], quests.step_text(open_id)])
				out.append("Finished: %s" % ", ".join(PackedStringArray(quests.done)))
				return out
			elif what == "reset":
				quests.reset()
				out.append("All quests forgotten.")
			elif what == "start" and quests.ids().has(id):
				for needed: String in quests.quest(id)["requires"]:
					for change: Dictionary in quests.force_finish(needed):
						reward(String(change["quest"]))
				quests.start(id)
				out.append("Started %s." % quests.quest(id)["name"])
			elif what == "finish" and (id == "all" or quests.ids().has(id)):
				for each in quests.ids():
					if id == "all" or each == id:
						for change: Dictionary in quests.force_finish(each):
							reward(String(change["quest"]))
				out.append("Finished %s." % ("every quest" if id == "all" else quests.quest(id)["name"] + " and what it needed"))
			else:
				return PackedStringArray([usage, "Quests: " + ", ".join(PackedStringArray(quests.ids()))])
			_synced()
	apply_stats()
	refresh_marks()
	_after_change()
	return out


# --- saving ---

func to_dict() -> Dictionary:
	return {"v": SAVE_VERSION, "bag": bag.to_dict(), "skills": skills.to_dict(), "quests": quests.to_dict(), "found": found.keys(), "looted": _still_empty(), "repaired": agility.repaired_keys()}


# The containers that have not refilled yet (the others need no remembering).
func _still_empty() -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var out := {}
	for key: String in rooms.looted:
		if float(rooms.looted[key]) > now:
			out[key] = rooms.looted[key]
	return out


func from_dict(saved: Variant) -> void:
	if not (saved is Dictionary) or int((saved as Dictionary).get("v", 0)) != SAVE_VERSION:
		return
	bag.from_dict(saved.get("bag"))
	skills.from_dict(saved.get("skills"))
	quests.from_dict(saved.get("quests"))
	rooms.looted = {}
	var emptied: Variant = saved.get("looted", {})
	if emptied is Dictionary:
		for key: Variant in emptied:
			rooms.looted[String(key)] = float(emptied[key])
	agility.set_repaired(saved.get("repaired", []))  # ladders mended by Carpentry (older saves: none)
	found = {}
	for id: Variant in saved.get("found", []):  # older saves have none: the map starts blank
		found[String(id)] = true
	mana = max_mana()
