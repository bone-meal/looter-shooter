# Purpose: online session (WebRTC through the Tube addon): host or join by session ID, host checks each joiner's profile, roster, position sync, remote-player ghosts.
# Dependencies: addons/tube (+ webrtc-native GDExtension), core/join_check.gd, core/item_db.gd, core/data_store.gd, game/profile_io.gd, game/character_models.gd, data/net.json.
# Model: the host is the server. Clients send only their own position; the host validates and rebroadcasts. The shared boss, spirits and PvP live in net_boss/net_spirits/net_pvp.
# Host migration: when the host drops mid-game, the lowest remaining peer id hosts a new session whose ID is derived from the old one; the others rejoin it.
extends Node3D

const JoinCheck = preload("res://core/join_check.gd")
const ItemDb = preload("res://core/item_db.gd")
const DataStore = preload("res://core/data_store.gd")
const ProfileIO = preload("res://game/profile_io.gd")
const ProgressState = preload("res://core/progress_state.gd")
const AppearanceData = preload("res://game/appearance_data.gd")
const RemotePlayer = preload("res://game/remote_player.gd")
const NetBoss = preload("res://game/net_boss.gd")
const NetSpirits = preload("res://game/net_spirits.gd")
const NetPvp = preload("res://game/net_pvp.gd")
const NetChat = preload("res://game/net_chat.gd")
const NetFantasy = preload("res://game/net_fantasy.gd")
const NetTrade = preload("res://game/net_trade.gd")
const NetTcg = preload("res://game/net_tcg.gd")
const NetMusic = preload("res://game/net_music.gd")
const NetMixtape = preload("res://game/net_mixtape.gd")
const NetBeachBalls = preload("res://game/net_beachballs.gd")
const NetChase = preload("res://game/net_chase.gd")
const NetFire = preload("res://game/net_fire.gd")
const NetParty = preload("res://game/net_party.gd")
const GuestClaims = preload("res://core/guest_claims.gd")
const NetHub = preload("res://game/net_hub.gd")
const NetDrops = preload("res://game/net_drops.gd")
const NetScores = preload("res://game/net_scores.gd")
const NetRounds = preload("res://game/net_rounds.gd")
const NetSlots = preload("res://game/net_slots.gd")
const NetDarts = preload("res://game/net_darts.gd")
const NetPool = preload("res://game/net_pool.gd")
const NetPoker = preload("res://game/net_poker.gd")
const NetDowns = preload("res://game/net_downs.gd")
const NetSea = preload("res://game/net_sea.gd")

signal hosted(id: String)
signal joined
signal failed(message: String)
signal left(reason: String)
signal roster_changed(roster: Dictionary)
signal begin_play

var roster := {}  # peer id -> display name (host is id 1)
var looks := {}  # peer id -> appearance dictionary (validated by the host)
var cards := {}  # peer id -> public player card {callsign, title, level, emblem_def} (built by the host from validated progress)
var started := false
var session_id := ""

var _client: Node
var _config: Dictionary
var _items: ItemDb
var claims := {}  # host: peer -> core/guest_claims.gd made from the profile he joined with (sea step 12c)
var claims_refused := 0  # dev / checks: guest claims the host refused as impossible
var _claim_cfg: Dictionary
var _skilling: Dictionary
var _fantasy_items: Dictionary  # data/fantasy/gear.json items (what may be put in a chest or a hold)
var _bag_items: Array = []
var _local_name := ""
var _joined_signalled := false
var _migrating := false
var _mig_ok := false  # set when the new session accepted us
var _mig_err := false
var _my_peer := 0  # our peer id in the current session, kept for migration
var _pending := {}  # host: peer id -> seconds since connecting without a profile
var _ghosts := {}  # peer id -> {"node": Node3D, "pos": Vector3, "yaw": float}
var _world: Node3D
var _player: Node3D
var _send_timer := 0.0
var _boss: Node
var _spirits: Node
var _pvp: Node
var chat: Node  # text chat and command permissions (game/net_chat.gd)
var fantasy: Node  # the fantasy world's creatures and party quests (game/net_fantasy.gd)
var trade: Node  # trading between players (game/net_trade.gd)
var tcg: Node  # the card game's player tables (game/net_tcg.gd)
var music: Node  # the jukebox online (game/net_music.gd)
var mixtape: Node  # the Mixtape chase gun's songs online (game/net_mixtape.gd)
var beach_balls: Node  # Beach Ball Bombardier's balls online (game/net_beachballs.gd)
var chase: Node  # the other chase guns' effects online (game/net_chase.gd)
var fire: Node  # other players' gunfire seen and heard (game/net_fire.gd, sea step 12b)
var party: Node  # party effects that reach teammates (game/net_party.gd, sea step 12d)
var hub: Node  # the safe hub's countdown and ready-up (game/net_hub.gd; also alone)
var drops: Node  # guns players drop for each other (game/net_drops.gd)
var scores: Node  # the party's scoreboard rows (game/net_scores.gd)
var rounds: Node  # the island's shared rounds and enemies (game/net_rounds.gd)
var slots: Node  # the lobby's shared slot jackpot (game/net_slots.gd)
var darts: Node  # darts matches between players (game/net_darts.gd)
var pool: Node  # 8-ball matches between players (game/net_pool.gd)
var poker: Node  # the casino's poker table, the host dealing (game/net_poker.gd)
var downs: Node  # who is down or out on the islands, revives, the party's game over (game/net_downs.gd)
var sea: Node  # the sea's fleet, helms, decks, swimmers and ropes (game/net_sea.gd)
var space: Node = null  # the sea world (game/sea_world.gd) once built: its floating origin turns positions to and from shared ones


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps syncing while the pause menu is open
	_config = DataStore.load_json("res://data/net.json")
	_items = ItemDb.new(DataStore.load_json("res://data/items.json"))
	_claim_cfg = DataStore.load_json("res://data/guest_claims.json")
	_skilling = DataStore.load_json("res://data/fantasy/skilling.json")
	_fantasy_items = DataStore.load_json("res://data/fantasy/gear.json").get("items", {})
	for item: String in _fantasy_items:
		if String((_fantasy_items[item] as Dictionary).get("kind", "")) == "backpack":
			_bag_items.append(item)
	# child nodes with fixed names, so their RPC paths match on every machine
	_boss = NetBoss.new()
	_boss.name = "Boss"
	_boss.net = self
	add_child(_boss)
	_spirits = NetSpirits.new()
	_spirits.name = "Spirits"
	_spirits.net = self
	add_child(_spirits)
	_pvp = NetPvp.new()
	_pvp.name = "Pvp"
	_pvp.net = self
	add_child(_pvp)
	chat = NetChat.new()
	chat.name = "Chat"
	chat.net = self
	add_child(chat)
	fantasy = NetFantasy.new()
	fantasy.name = "Fantasy"
	fantasy.net = self
	add_child(fantasy)
	trade = NetTrade.new()
	trade.name = "Trade"
	trade.net = self
	add_child(trade)
	tcg = NetTcg.new()
	tcg.name = "Tcg"
	tcg.net = self
	add_child(tcg)
	music = NetMusic.new()
	music.name = "Music"
	music.net = self
	add_child(music)
	roster_changed.connect(func(_r: Dictionary) -> void: music.call("joined", 0))
	mixtape = NetMixtape.new()
	mixtape.name = "Mixtape"
	mixtape.net = self
	add_child(mixtape)
	beach_balls = NetBeachBalls.new()
	beach_balls.name = "BeachBalls"
	beach_balls.net = self
	add_child(beach_balls)
	party = NetParty.new()
	party.name = "Party"
	party.net = self
	add_child(party)
	fire = NetFire.new()
	fire.name = "Fire"
	fire.net = self
	add_child(fire)
	chase = NetChase.new()
	chase.name = "Chase"
	chase.net = self
	add_child(chase)
	roster_changed.connect(func(_r: Dictionary) -> void: mixtape.call("joined", 0))
	hub = NetHub.new()
	hub.name = "Hub"
	hub.net = self
	add_child(hub)
	drops = NetDrops.new()
	drops.name = "Drops"
	drops.net = self
	add_child(drops)
	scores = NetScores.new()
	scores.name = "Scores"
	scores.net = self
	add_child(scores)
	rounds = NetRounds.new()
	rounds.name = "Rounds"
	rounds.net = self
	add_child(rounds)
	slots = NetSlots.new()
	slots.name = "Slots"
	slots.net = self
	add_child(slots)
	darts = NetDarts.new()
	darts.name = "Darts"
	darts.net = self
	add_child(darts)
	pool = NetPool.new()
	pool.name = "Pool"
	pool.net = self
	add_child(pool)
	poker = NetPoker.new()
	poker.name = "Poker"
	poker.net = self
	add_child(poker)
	downs = NetDowns.new()
	downs.name = "Downs"
	downs.net = self
	add_child(downs)
	sea = NetSea.new()
	sea.name = "Sea"
	sea.net = self
	add_child(sea)


func is_active() -> bool:
	return _client != null


func is_migrating() -> bool:
	return _migrating


# True while the connection to the other machines is up (false during migration).
func can_send() -> bool:
	if _client == null:
		return false
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return _client != null and _client.is_server


func config(key: String) -> Variant:
	return _config[key]


func local_name() -> String:
	return _local_name


func world() -> Node3D:
	return _world


func local_player() -> Node3D:
	return _player


# Other players' bodies (the shared boss chooses its victim among these and the local player).
# Where every player this machine knows of is right now, itself included: peer id -> world position.
func positions() -> Dictionary:
	var out := {}
	for id in _ghosts:
		out[id] = _ghosts[id]["pos"]
	if _player != null and is_instance_valid(_player):
		out[my_id()] = _player.global_position
	return out


# Where the other players are right now (world positions): enough to know which worlds are in use.
func other_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for id in _ghosts:
		out.append(_ghosts[id]["pos"])
	return out


func target_nodes() -> Array:
	var out: Array = []
	for id in _ghosts:
		if is_instance_valid(_ghosts[id]["node"]):
			out.append(_ghosts[id]["node"])
	return out


# The body that stands for a player on this machine: our own for our id, a ghost for anyone else (null if unknown).
func player_node(id: int) -> Node3D:
	if id == my_id():
		return _player
	if _ghosts.has(id) and is_instance_valid(_ghosts[id]["node"]):
		return _ghosts[id]["node"]
	return null


func my_id() -> int:
	return multiplayer.get_unique_id() if _client != null else 1


# --- start / stop ---

func host(player_name: String) -> void:
	if not _make_client(player_name):
		return
	_client.session_created.connect(_on_session_created)
	_client.create_session()


func join(id: String, player_name: String) -> void:
	if id.strip_edges().is_empty():
		failed.emit("Enter a session ID first.")
		return
	if not _make_client(player_name):
		return
	session_id = id.strip_edges()  # the lobby code, shown in the pause menu and on the scoreboard (a host's comes from Tube)
	_client.session_joined.connect(_on_session_joined)
	_client.join_session(id.strip_edges())


func _drop_client() -> void:
	if _client == null:
		return
	var old := _client
	_client = null
	old.session_left.disconnect(_on_session_left)
	old.leave_session()  # closes the session; the host closing it ends it for everyone
	old.queue_free()


func leave(reason: String = "") -> void:
	var was_active := _client != null or _migrating
	if poker != null:
		poker.after_host_lost()
	_migrating = false
	_drop_client()
	unbind_world()
	roster = {}
	looks = {}
	cards = {}
	started = false
	session_id = ""
	_pending.clear()
	_joined_signalled = false
	if was_active:
		left.emit(reason)


# The host presses Start: everyone (now and later joiners) enters the world.
func start_for_all() -> void:
	if not is_host():
		return
	started = true
	_begin.rpc()
	begin_play.emit()


# The game session calls this once the world and the local player exist.
func bind_world(world_node: Node3D, player: Node3D, director: Node3D) -> void:
	_world = world_node
	_player = player
	_boss.bind_director(director)
	_spirits.director = director


func _clear_remote() -> void:
	_spirits.clear_all()
	for id in _ghosts:
		if is_instance_valid(_ghosts[id]["node"]):
			_ghosts[id]["node"].queue_free()
	_ghosts.clear()


func unbind_world() -> void:
	_boss.unbind()
	fantasy.unbind()
	rounds.unbind()
	_spirits.director = null
	_clear_remote()
	_world = null
	_player = null


# --- setup ---

func _make_client(player_name: String) -> bool:
	if _client != null:
		failed.emit("Already in a session.")
		return false
	var client_script: Script = load("res://addons/tube/tube_client.gd")
	var context_script: Script = load("res://addons/tube/tube_context.gd")
	if client_script == null or context_script == null:
		failed.emit("Online play is not set up: the Tube addon is missing or not loaded (open the project in the editor once).")
		return false
	var context = context_script.new()
	var trackers: Array[String] = []
	for url in _config["trackers"]:
		trackers.append(String(url))
	var stun: Array[String] = []
	for url in _config["stun"]:
		stun.append(String(url))
	context.set("app_id", String(_config["app_id"]))
	context.set("trackers_urls", trackers)
	context.set("stun_servers_urls", stun)
	_local_name = ProfileIO.current(player_name)["name"]
	_client = client_script.new()
	_client.set("peer_signaling_timeout", float(_config.get("signaling_timeout_seconds", 2.0)))
	_client.set("peer_signaling_max_attempts", int(_config.get("signaling_attempts", 3)))
	_client.set("context", context)
	_client.set("multiplayer_root_node", self)
	add_child(_client)
	_client.error_raised.connect(_on_error)
	_client.session_left.connect(_on_session_left)
	_client.peer_connected.connect(_on_peer_connected)
	_client.peer_disconnected.connect(_on_peer_disconnected)
	return true


# Tube's errors (addons/tube/tube_client.gd SessionError). Only failing to create or join a session ends it. The
# others (a kick that found no peer, a tracker lost, local signaling) leave the session open: before 2026-11-13 any
# of them made the HOST leave, which closed the lobby for everybody whenever one joiner's connection failed.
const FATAL_ERRORS := [0, 1]  # CREATE_SESSION_FAILED, JOIN_SESSION_FAILED


func _on_error(code: int, message: String) -> void:
	if _migrating:
		_mig_err = true
		return
	if not FATAL_ERRORS.has(code):
		push_warning("online: %s (the session stays open)" % message)
		return
	failed.emit(message)
	if _client != null:
		leave()


func _on_session_created() -> void:
	session_id = _client.session_id
	roster = {1: _local_name}
	var mine := ProfileIO.current(_local_name)
	looks = {1: mine["look"]}
	cards = {1: _make_card(mine["progress"])}
	roster_changed.emit(roster)
	if _migrating:
		_mig_ok = true
		return
	hosted.emit(session_id)


func _on_session_joined() -> void:
	_my_peer = _client.peer_id
	# Connected to the host: show it who we are. The host decides whether we may stay.
	# The data channel can still be opening at this moment, so wait for it.
	var tries := 0
	while not can_send() and tries < 100:
		await get_tree().create_timer(0.1).timeout
		tries += 1
	if not can_send():
		return
	_submit_profile.rpc_id(1, ProfileIO.current(_local_name))


func _on_session_left() -> void:
	if _client == null:
		return
	if started and _joined_signalled and not is_host() and roster.size() > 1:
		_migrate.call_deferred()  # the host is gone but others remain: carry on without it
		return
	leave("The host closed the session." if _joined_signalled else "")


func _on_peer_connected(id: int) -> void:
	if is_host():
		_pending[id] = 0.0


func _on_peer_disconnected(id: int) -> void:
	_pending.erase(id)
	claims.erase(id)
	if is_host() and roster.has(id):
		roster.erase(id)
		looks.erase(id)
		cards.erase(id)
		_broadcast_roster()
	_remove_ghost(id)
	_spirits.remove_owner(id)


# --- host migration ---

# The old host is gone. Candidates are the remaining peers in id order; candidate N hosts a session
# whose ID every machine derives the same way, the rest rejoin it. A dead candidate is skipped.
func _migrate() -> void:
	if _client == null or _migrating:
		return
	_migrating = true
	poker.after_host_lost()  # (polish1 item 167) the old host dealt the poker table: seated players get their table chips back
	_freeze_sea(true)
	var old_session := session_id
	var me := _my_peer
	var charset := String(_client.context.get("session_id_characters_set"))
	var order: Array = roster.keys()
	order.erase(1)
	order.sort()
	_drop_client()
	_clear_remote()
	roster = {}
	looks = {}
	cards = {}
	_pending.clear()
	for attempt in order.size():
		var wanted := _next_session_id(old_session, attempt, charset)
		await get_tree().create_timer(0.5).timeout
		if not _migrating:
			return
		var ok := false
		if order[attempt] == me:
			ok = await _become_host(wanted)
		else:
			ok = await _rejoin(wanted)
		if not _migrating:
			return
		if ok:
			_migrating = false
			session_id = wanted
			_boss.after_migration()
			sea.after_migration()
			_freeze_sea(false)
			return
		_drop_client()
	_freeze_sea(false)
	failed.emit("The host left and the session could not be recovered.")
	leave("The host left.")


# The sea world stands still while a new host is found (sea step 12).
func _freeze_sea(on: bool) -> void:
	var sea_node := get_tree().get_first_node_in_group("sea_world")
	if sea_node != null:
		sea_node.set("frozen", on)


# --- guest claims (sea step 12c, LOCKED: plausibility checks) ---

func _clock() -> float:
	return Time.get_ticks_msec() / 1000.0


# Host: may peer `id` really have `skill` at `level` now? (The host's own word is not checked; a guest without a
# record (joined before this host took over and not re-checked) passes.)
func claim_level_ok(id: int, skill: String, level: int) -> bool:
	if id == my_id() or not claims.has(id):
		return true
	var ok: bool = (claims[id] as GuestClaims).level_ok(skill, level, _clock())
	if not ok:
		claims_refused += 1
	return ok


# Host: the highest of `level` he may plausibly claim in `skill` now.
func claim_level_cap(id: int, skill: String, level: int) -> int:
	if id == my_id() or not claims.has(id):
		return level
	var cap: int = (claims[id] as GuestClaims).allowed_level(skill, _clock())
	if level > cap:
		claims_refused += 1
	return mini(level, cap)


# Host: could peer `id` have made `item` (the recipe's skill level within reach)?
func claim_can_make(id: int, item: String) -> bool:
	if id == my_id() or not claims.has(id):
		return true
	var need: Array = (claims[id] as GuestClaims).recipe_need(item)
	if need.is_empty():
		return true
	return claim_level_ok(id, String(need[0]), int(need[1]))


# Host: a put of `n` of `item` into a chest or a hold is believable.
func claim_put_ok(id: int, item: String, n: int) -> bool:
	if id == my_id():
		return true
	var ok := _fantasy_items.has(item) and n >= 1 and n <= int(_claim_cfg["max_put"])
	if not ok:
		claims_refused += 1
	return ok


func _next_session_id(old: String, attempt: int, charset: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/%d" % [old, attempt])
	var out := ""
	for _i in 5:
		out += charset[rng.randi() % charset.length()]
	return out


func _become_host(wanted: String) -> bool:
	if not _make_client(_local_name):
		return false
	_mig_ok = false
	_mig_err = false
	_client.forced_session_id = wanted
	_client.session_created.connect(_on_session_created)
	_client.create_session()
	for _i in 20:
		if _mig_ok or _mig_err:
			break
		await get_tree().create_timer(0.25).timeout
		if not _migrating:
			return false
	if _mig_ok:
		_boss.adopt_as_host()
		fantasy.adopt_as_host()
		rounds.adopt_as_host()
		sea.adopt_as_host()
	return _mig_ok


func _rejoin(wanted: String) -> bool:
	await get_tree().create_timer(3.0).timeout  # give the new host time to open the session
	for _try in 2:
		if not _migrating or not _make_client(_local_name):
			return false
		_mig_ok = false
		_mig_err = false
		_client.session_joined.connect(_on_session_joined)
		_client.join_session(wanted)
		for _i in 40:
			await get_tree().create_timer(0.25).timeout
			if not _migrating:
				return false
			if _mig_ok or _mig_err:
				break
		if _mig_ok:
			return true
		_drop_client()
		await get_tree().create_timer(0.5).timeout
	return false


# --- handshake and roster ---

@rpc("any_peer", "call_remote", "reliable")
func _submit_profile(profile: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		return
	var reason := ""
	if roster.size() >= int(_config["max_players"]):
		reason = "the session is full"
	else:
		reason = JoinCheck.check(profile, _items)
		if reason == "":
			reason = _check_progress(profile.get("progress", {}))
		if reason == "":
			var made := GuestClaims.new(_claim_cfg, _skilling, profile.get("skills", {}), _clock())
			var bags := int((profile.get("inv", {}) as Dictionary).get("bags", 0))
			if bags > made.bags_allowed(_bag_items):
				reason = "your backpack has more bags than your Crafting level can make"
			else:
				claims[id] = made
	if reason != "":
		_reject.rpc_id(id, reason)
		get_tree().create_timer(0.5).timeout.connect(_kick.bind(id))
		return
	_pending.erase(id)
	roster[id] = _unique_name(String(profile["name"]).strip_edges(), id)
	looks[id] = AppearanceData.db().sanitize(profile.get("look"))
	cards[id] = _make_card(profile.get("progress", {}))
	_broadcast_roster()
	if started:
		_begin.rpc_id(id)


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	failed.emit("The host refused you: " + reason)
	leave()


@rpc("authority", "call_remote", "reliable")
func _set_roster(new_roster: Dictionary, new_looks: Dictionary, new_cards: Dictionary) -> void:
	roster = new_roster
	looks = new_looks
	cards = new_cards
	for lid in looks:
		print("[look] roster update: peer %s outfit=%s height=%s ghost=%s" % [lid, looks[lid].get("outfit"), looks[lid].get("height"), _ghosts.has(lid)])
	roster_changed.emit(roster)
	for id in _ghosts:
		if looks.has(id):
			_ghosts[id]["node"].set_appearance(looks[id])
		if cards.has(id):
			_ghosts[id]["node"].set_card(cards[id])
	for id in _ghosts.keys():
		if not roster.has(id):
			_remove_ghost(id)
			_spirits.remove_owner(id)
	if _migrating and roster.has(multiplayer.get_unique_id()):
		_mig_ok = true
	if not _joined_signalled and roster.has(multiplayer.get_unique_id()):
		_joined_signalled = true
		joined.emit()


@rpc("authority", "call_remote", "reliable")
func _begin() -> void:
	started = true
	begin_play.emit()


func _broadcast_roster() -> void:
	roster_changed.emit(roster)
	for id in _ghosts:  # the host's own view of the other players
		if looks.has(id):
			_ghosts[id]["node"].set_appearance(looks[id])
		if cards.has(id):
			_ghosts[id]["node"].set_card(cards[id])
	_set_roster.rpc(roster, looks, cards)


# --- blackjack table spectating (view only: coins and results stay local) ---

signal table_event_received(peer: int, op: String, args: Array)


func send_table_event(op: String, args: Array) -> void:
	if not can_send() or not _table_event_ok(op, args):
		return
	if is_host():
		_table_broadcast.rpc(1, op, args)
	else:
		_table_to_host.rpc_id(1, op, args)


@rpc("any_peer", "call_remote", "reliable")
func _table_to_host(op: String, args: Array) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or not _table_event_ok(op, args):
		return
	table_event_received.emit(id, op, args)
	_table_broadcast.rpc(id, op, args)


@rpc("authority", "call_remote", "reliable")
func _table_broadcast(peer: int, op: String, args: Array) -> void:
	if _table_event_ok(op, args):
		table_event_received.emit(peer, op, args)


# Only well-formed blackjack table events pass: place [slot key, card 0..51, face up], reveal [slot key], clear [], bets [up to 2 amounts].
func _table_event_ok(op: String, args: Array) -> bool:
	match op:
		"place":
			return args.size() == 3 and _slot_key_ok(args[0]) and args[1] is int and int(args[1]) >= 0 and int(args[1]) < 52 and args[2] is bool
		"reveal":
			return args.size() == 1 and _slot_key_ok(args[0])
		"clear":
			return args.is_empty()
		"bets":
			if args.size() > 2:
				return false
			for a: Variant in args:
				if not (a is int) or int(a) < 0 or int(a) > 1000000:
					return false
			return true
	return false


func _slot_key_ok(key: Variant) -> bool:
	if not key is String:
		return false
	var parts := String(key).split(":")
	if parts.size() != 2 or not String(parts[1]).is_valid_int() or int(parts[1]) < 0 or int(parts[1]) > 7:
		return false
	return parts[0] == "d" or parts[0] == "p0" or parts[0] == "p1"


# Host check of a player's saved progress (levels, points, traits, achievements, card): "" when fine.
func _check_progress(progress: Variant) -> String:
	var rules := ProgressState.new(DataStore.load_json("res://data/progression.json"), DataStore.load_json("res://data/achievements.json"))
	var problem: String = rules.check(progress)
	return "" if problem == "" else "progress: " + problem


# The public card other players see, built from a progress dictionary that already passed _check_progress.
func _make_card(progress: Variant) -> Dictionary:
	var rules := ProgressState.new(DataStore.load_json("res://data/progression.json"), DataStore.load_json("res://data/achievements.json"))
	rules.from_dict(progress)
	var trophies := {}  # earned achievement id -> date ("" = before dates were kept): the hub's trophy cabinets
	for id: String in rules.unlocked:
		trophies[id] = String(rules.dates.get(id, ""))
	return {"callsign": rules.callsign, "title": rules.title_name(rules.title), "level": rules.level(), "emblem_def": rules.emblem_def(rules.emblem), "trophies": trophies, "played": rules.played, "shelves": rules.shelves, "bhop": rules.bhop}


# Our progress or card changed (level up, achievement, new emblem): tell everyone.
func send_card(progress: Dictionary) -> void:
	if not can_send():
		return
	if is_host():
		cards[1] = _make_card(progress)
		_broadcast_roster()
	else:
		_card_to_host.rpc_id(1, progress)


@rpc("any_peer", "call_remote", "reliable")
func _card_to_host(progress: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id):
		return
	var reason := _check_progress(progress)
	if reason != "":
		_reject.rpc_id(id, reason)
		get_tree().create_timer(0.5).timeout.connect(_kick.bind(id))
		return
	cards[id] = _make_card(progress)
	_broadcast_roster()


# Our look changed in the customization menu: tell everyone.
func send_look(look: Dictionary) -> void:
	print("[look] send_look host=%s can_send=%s outfit=%s height=%s weight=%s" % [is_host(), can_send(), look.get("outfit"), look.get("height"), look.get("weight")])
	if not can_send():
		return
	if is_host():
		looks[1] = AppearanceData.db().sanitize(look)
		_broadcast_roster()
	else:
		_look_to_host.rpc_id(1, look)


@rpc("any_peer", "call_remote", "reliable")
func _look_to_host(look: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	print("[look] host got look from %d (in roster: %s) outfit=%s height=%s" % [id, roster.has(id), look.get("outfit"), look.get("height")])
	if roster.has(id):
		looks[id] = AppearanceData.db().sanitize(look)
		_broadcast_roster()


func _unique_name(wanted: String, id: int) -> String:
	for other in roster.values():
		if other == wanted:
			return "%s#%d" % [wanted, id % 1000]
	return wanted


func _kick(id: int) -> void:
	if is_host() and _client != null:
		_client.kick_peer(id)


# --- position sync ---

func _process(delta: float) -> void:
	if is_host():
		for id in _pending.keys():
			_pending[id] += delta
			if _pending[id] > float(_config["join_timeout_seconds"]):
				_pending.erase(id)
				_kick(id)
	for id in _ghosts:
		var g: Dictionary = _ghosts[id]
		var node: Node3D = g["node"]
		var k := 1.0 - exp(-12.0 * delta)
		var deck: Variant = g.get("deck")
		if deck is Node3D and is_instance_valid(deck):  # on a ship: glides in the ship's own space and rides the hull
			g["shown"] = (g.get("shown", g["local"]) as Vector3).lerp(g["local"], k)
			node.global_position = (deck as Node3D).global_transform * (g["shown"] as Vector3)
		else:
			node.global_position = node.global_position.lerp(g["pos"], k)
		node.rotation.y = lerp_angle(node.rotation.y, g["yaw"], k)
	if not can_send() or not started or _player == null or not is_instance_valid(_player):
		return
	_send_timer += delta
	if _send_timer < 1.0 / float(_config["send_rate_hz"]):
		return
	_send_timer = 0.0
	if is_host():
		_state_broadcast.rpc(1, to_shared(_player.global_position), _player.look_yaw(), _player.held_id(), _player.smoking(), _player.emote_id())
	elif roster.has(multiplayer.get_unique_id()):
		_state_to_host.rpc_id(1, to_shared(_player.global_position), _player.look_yaw(), _player.held_id(), _player.smoking(), _player.emote_id())


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state_to_host(pos: Vector3, yaw: float, held: String, smoking: bool, emote: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or not pos.is_finite() or not is_finite(yaw) or pos.length() > 60000.0 or held.length() > 96 or emote.length() > 24:  # the fantasy world lies 20 km out; the sea's dungeon spaces (sea step 9) up to ~45 km (shared = -20 km anchor + sea x)
		return
	_apply_state(id, pos, yaw, held, smoking, emote)
	_state_broadcast.rpc(id, pos, yaw, held, smoking, emote)


@rpc("authority", "call_remote", "unreliable_ordered")
func _state_broadcast(id: int, pos: Vector3, yaw: float, held: String, smoking: bool, emote: String) -> void:
	_apply_state(id, pos, yaw, held, smoking, emote)


func _apply_state(id: int, pos: Vector3, yaw: float, held: String, smoking: bool, emote: String) -> void:
	if _world == null or id == multiplayer.get_unique_id() or not roster.has(id):
		return
	pos = from_shared(pos)
	if not _ghosts.has(id):
		_make_ghost(id, pos)
	_ghosts[id]["pos"] = pos
	_ghosts[id]["yaw"] = yaw
	_ghosts[id]["node"].set_held(held)
	_ghosts[id]["node"].set_smoking(smoking)
	_ghosts[id]["node"].set_emote(emote)


# --- the sea's floating origin (game/sea_world.gd): positions out at sea travel as SHARED positions (as if no machine
# had shifted), every machine turns them into its own scene positions ---

func _at_sea(pos: Vector3) -> bool:
	return space != null and is_instance_valid(space) and pos.x < float(space.call("anchor_x")) + 9000.0  # (the whole sea side: shared positions of the dungeon spaces, sea step 9, lie up to ~25 km past the anchor)


func to_shared(pos: Vector3) -> Vector3:
	return pos + (space.call("shift") as Vector3) if _at_sea(pos) else pos


func from_shared(pos: Vector3) -> Vector3:
	return pos - (space.call("shift") as Vector3) if _at_sea(pos) else pos


# The sea shifted under everything here: ghosts out at sea move with it.
func shift_ghosts(delta: Vector3) -> void:
	for id in _ghosts:
		var g: Dictionary = _ghosts[id]
		if _at_sea(g["pos"]):
			g["pos"] = (g["pos"] as Vector3) - delta
			if is_instance_valid(g["node"]):
				(g["node"] as Node3D).global_position -= delta


# The ship-space spots of the other players standing on `ship` who say they are trimming its sails (game/sea_ships.gd
# checks each is at a rigging spot).
func workers_on(ship: Node3D) -> Array:
	var out: Array = []
	for id in _ghosts:
		var g: Dictionary = _ghosts[id]
		if g.get("deck") == ship and bool(g.get("working", false)):
			out.append(g["local"])
	return out


# Dev: each other player as this machine shows him (scene position, on which deck, swimming).
func ghost_note() -> String:
	var out := PackedStringArray()
	for id in _ghosts:
		var g: Dictionary = _ghosts[id]
		var node: Node3D = g["node"]
		out.append("%d at %s deck %s local %s swim %s" % [id, str((node.global_position if is_instance_valid(node) else g["pos"]).snapped(Vector3.ONE * 0.1)),
			str(g.get("deck") != null), str((g.get("local", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.1)), str(node.get("_swimming") if is_instance_valid(node) else "?")])
	return "ghosts: " + ("none" if out.is_empty() else "; ".join(out))


# game/net_sea.gd: a player stands on a ship (ship-space point) or not (ship null); he swims or not.
func ghost_deck(id: int, ship: Node3D, local: Vector3, swimming: bool, working: bool = false) -> void:
	if not _ghosts.has(id):
		return
	var g: Dictionary = _ghosts[id]
	g["working"] = working and ship != null
	if ship == null:
		g.erase("deck")
		g.erase("shown")
	else:
		if g.get("deck") != ship:
			g["shown"] = local
		g["deck"] = ship
		g["local"] = local
	if is_instance_valid(g["node"]):
		g["node"].call("set_swimming", swimming)
		g["node"].set("deck_ship", ship)


# [ship, ship-space spot] of a player riding a deck (game/net_sea.gd), [] when he is not on one.
func deck_of(id: int) -> Array:
	var g: Dictionary = _ghosts.get(id, {})
	return [g["deck"], g["local"]] if g.get("deck") != null and is_instance_valid(g["deck"]) else []


func _make_ghost(id: int, pos: Vector3) -> void:
	var body := RemotePlayer.new()
	body.peer_id = id
	body.display_name = String(roster.get(id, "?"))
	body.appearance = AppearanceData.db().sanitize(looks.get(id, {}))
	body.card = cards.get(id, {})
	body.shot.connect(_on_ghost_shot.bind(id))
	_world.add_child(body)
	body.global_position = pos
	_ghosts[id] = {"node": body, "pos": pos, "yaw": 0.0}


func _on_ghost_shot(damage: float, id: int) -> void:
	_pvp.report_hit(id, damage)


func _remove_ghost(id: int) -> void:
	if _ghosts.has(id):
		if is_instance_valid(_ghosts[id]["node"]):
			_ghosts[id]["node"].queue_free()
		_ghosts.erase(id)
