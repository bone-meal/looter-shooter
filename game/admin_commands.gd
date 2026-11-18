# Purpose: runs chat commands (data/commands.json) for testing without grinding: give guns and items, travel, heal,
# god mode, flight, levels, spawn and remove enemies, plus the fantasy world's skills, spells, gear and quests.
# `run` returns the lines to show the person who typed the command. Who may run what is decided by the caller
# (game/game_session.gd): "self" commands run on the typist's machine, "world" commands on the host.
# Dependencies: core/chat_command.gd, core/gun_gen.gd, core/gun_stats.gd, core/armour_gen.gd, core/armour_stats.gd, core/data_store.gd, game/player.gd, game/game_session.gd
# (`session`: local_player, director, progress, wallet, travel, fantasy, refresh_after_command).
extends Node

const ChatCommand = preload("res://core/chat_command.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const ArmourGen = preload("res://core/armour_gen.gd")
const ArmourStats = preload("res://core/armour_stats.gd")
const LootPool = preload("res://core/loot_pool.gd")
const DataStore = preload("res://core/data_store.gd")
const Player = preload("res://game/player.gd")
const KnifeModels = preload("res://game/knife_models.gd")

const ENEMY_FILES := ["res://data/enemies.json", "res://data/fantasy/enemies.json"]
const SPAWN_MAX := 20

var session: Node3D
var table: Array = DataStore.load_json("res://data/commands.json")["commands"]

var _rng := RandomNumberGenerator.new()
var _enemy_stats := {}


func _ready() -> void:
	_rng.randomize()
	for file: String in ENEMY_FILES:
		if FileAccess.file_exists(file):
			_enemy_stats.merge(DataStore.load_json(file)["enemies"])


func scope_of(text: String) -> String:
	var entry := ChatCommand.find(table, String(ChatCommand.parse(text).get("name", "")))
	return String(entry.get("scope", ""))


# `near` = the player the command is about (the typist's own body, or on the host the body of the client who sent it).
func run(text: String, near: Node3D) -> PackedStringArray:
	var parsed := ChatCommand.parse(text)
	if parsed.is_empty():
		return PackedStringArray()
	var args: Array = parsed["args"]
	var entry := ChatCommand.find(table, String(parsed["name"]))
	if entry.is_empty():
		return PackedStringArray(["Unknown command /%s. Type /help." % parsed["name"]])
	var out := PackedStringArray()
	match String(parsed["name"]):
		"help":
			out = ChatCommand.help(table, String(args[0]) if args.size() > 0 else "")
		"give":
			out.append(_give(args))
		"tp":
			out.append(_tp(args))
		"hub":
			out.append(session.back_to_hub())
		"heal":
			var player: Player = session.local_player()
			player.health.reset()
			player.status.clear()
			if session.fantasy() != null:
				session.fantasy().refill()
			out.append("Healed.")
		"god":
			session.local_player().cheat_god = not session.local_player().cheat_god
			out.append("God mode %s." % ("on" if session.local_player().cheat_god else "off"))
		"fly":
			session.local_player().cheat_fly = not session.local_player().cheat_fly
			out.append("Flight %s. You move where you look." % ("on" if session.local_player().cheat_fly else "off"))
		"speed":
			if args.size() < 1 or not String(args[0]).is_valid_float():
				out.append(String(entry["usage"]))
			else:
				session.local_player().cheat_speed = clampf(String(args[0]).to_float(), 0.2, 10.0)
				out.append("Speed x%.1f." % session.local_player().cheat_speed)
		"level":
			out.append(_level(args, String(entry["usage"])))
		"xp":
			if args.size() < 1 or not String(args[0]).is_valid_int():
				out.append(String(entry["usage"]))
			else:
				session.progress().add_xp(maxi(String(args[0]).to_int(), 0))
				session.refresh_after_command()
				out.append("Level %d now." % session.progress().level())
		"spawn":
			out.append(_spawn(args, near, String(entry["usage"])))
		"round":
			if args.is_empty() or not String(args[0]).is_valid_int() or String(args[0]).to_int() < 1:
				out.append(String(entry["usage"]))
			elif not session.rounds().active:
				out.append("Only the host runs the island's rounds.")
			else:
				session.rounds().skip_to(String(args[0]).to_int())
				out.append("Round %d starts in a moment (stand on the island)." % String(args[0]).to_int())
		"wave":
			if args.is_empty() or not String(args[0]).is_valid_int() or session.director().wave_count() == 0:
				out.append("%s  (only during a colosseum run)" % String(entry["usage"]))
			else:
				session.director().skip_to(String(args[0]).to_int())
				out.append("Wave %d comes in a moment." % clampi(String(args[0]).to_int(), 1, session.director().wave_count()))
		"power":
			out.append(String(session.call("drop_power", String(args[0]) if not args.is_empty() else "", near)))
		"switch":
			out.append(String(session.call("cheat_power")))
		"build":
			out.append(String(session.call("cheat_build", String(args[0]) if not args.is_empty() else "")))
		"perk":
			out.append(String(session.call("cheat_perk", String(args[0]) if not args.is_empty() else "")))
		"kill":
			var gone := 0
			for enemy: Node in session.director().enemy_list().duplicate():
				session.director().despawn(enemy)
				gone += 1
			out.append("Removed %d enemies." % gone)
		"skill", "spells", "slots", "gear", "quest":
			if session.fantasy() == null:
				out.append("Enter the fantasy world first (/tp fantasy).")
			else:
				out = session.fantasy().command(String(parsed["name"]), args, String(entry["usage"]))
		_:
			out.append(String(entry["usage"]))
	return out


func _give(args: Array) -> String:
	var player: Player = session.local_player()
	var what := String(args[0]) if args.size() > 0 else ""
	match what:
		"gun":
			var tier := String(args[1]) if args.size() > 1 else ""
			var body := String(args[2]) if args.size() > 2 else ""
			if tier != "" and player.gun_db.tier_index(tier) < 0:
				return "Unknown tier %s." % tier
			if body != "" and not player.gun_db.bodies.has(body):
				return "Unknown gun body %s. Bodies: %s" % [body, ", ".join(player.gun_db.bodies.keys())]
			var level := int(args[3]) if args.size() > 3 and String(args[3]).is_valid_int() else 1  # item level
			var gun := GunGen.generate(player.gun_db, _rng, 0.0, body, tier, "", level)
			return _hand_over(gun)
		"unique":
			var id := String(args[1]) if args.size() > 1 else ""
			if id == "all":
				var given := 0
				for unique_id: String in player.gun_db.uniques:
					if player.inventory.add_gun(GunGen.unique(player.gun_db, unique_id)):
						given += 1
				session.refresh_after_command()
				return "Gave %d pony uniques." % given
			if not player.gun_db.uniques.has(id):
				return "Uniques: %s, or all." % ", ".join(player.gun_db.uniques.keys())
			return _hand_over(GunGen.unique(player.gun_db, id))
		"pool":  # one kill of a loot pool's source (a sea boss, raid, the Vault): everything it drops goes into the bag
			var pool_id := String(args[1]) if args.size() > 1 else ""
			if not player.gun_db.pools.has(pool_id):
				return "Pools: %s." % ", ".join(player.gun_db.pools.keys())
			var level := int(args[2]) if args.size() > 2 and String(args[2]).is_valid_int() else 1
			var names := PackedStringArray()
			for gun: Dictionary in LootPool.roll(player.gun_db, _rng, pool_id, level):
				if player.inventory.add_gun(gun):
					names.append(GunStats.display_name(player.gun_db, gun))
			session.refresh_after_command()
			return "%s dropped: %s." % [String(player.gun_db.pools[pool_id].get("name", pool_id)), ", ".join(names) if not names.is_empty() else "nothing"]
		"armour", "armor":  # a rolled piece: /give armour [tier] [item level] [item id] [set id | none]
			var tier := String(args[1]) if args.size() > 1 else "purple"
			if not (player.items.armour["tiers"] as Dictionary).has(tier):
				return "Tiers: %s." % ", ".join((player.items.armour["tiers"] as Dictionary).keys())
			var level := clampi(int(args[2]), 1, int(player.items.armour["max_level"])) if args.size() > 2 and String(args[2]).is_valid_int() else 1
			var base := String(args[3]) if args.size() > 3 else ""
			if base != "" and not player.items.rollable(base):
				return "Not an armour piece that rolls: %s." % base
			var set_id := String(args[4]) if args.size() > 4 else "auto"
			if set_id == "none":
				set_id = ""
			elif set_id != "auto" and not (player.items.armour["sets"] as Dictionary).has(set_id):
				return "Sets: %s, none." % ", ".join((player.items.armour["sets"] as Dictionary).keys())
			var piece := ArmourGen.generate(player.items, _rng, tier, level, base, set_id)
			if not player.inventory.add_armour(piece):
				return "No room in the backpack."
			session.refresh_after_command()
			return "Gave %s (item level %d)." % [ArmourStats.display_name(player.items, piece, String(player.gun_db.tier(tier)["name"])), level]
		"item":
			var item := String(args[1]) if args.size() > 1 else ""
			if not player.items.has_item(item):
				return "Unknown item %s." % item
			var count := maxi(String(args[2]).to_int(), 1) if args.size() > 2 else 1
			var left: int = player.inventory.add(item, count)
			session.refresh_after_command()
			return "Gave %d x %s." % [count - left, player.items.item_name(item)]
		"coins", "chips":
			if args.size() < 2 or not String(args[1]).is_valid_int():
				return "/give chips <amount>"
			session.wallet().add(maxi(String(args[1]).to_int(), 0))
			return "You have %d chips." % session.wallet().balance
		"ammo":
			player.pools.fill_all()
			return "Every ammo pool is full."
		"knife":
			var knives: RefCounted = KnifeModels.db()
			if args.size() < 2 or not knives.has(String(args[1])):
				return "Knives: %s." % ", ".join(knives.ids())
			player.set_knife(String(args[1]))
			session.save_profile()
			return "Your knife is now the %s." % knives.name_of(player.knife)
		"points":
			if args.size() < 2 or not String(args[1]).is_valid_int():
				return "/give points <amount>"
			session.score().give(maxi(String(args[1]).to_int(), 0))
			return "You have %d points." % session.score().points
	return String(ChatCommand.find(table, "give")["usage"])


func _hand_over(gun: Dictionary) -> String:
	var player: Player = session.local_player()
	if not player.inventory.add_gun(gun):
		return "Your inventory is full."
	session.refresh_after_command()
	return "Gave %s." % GunStats.display_name(player.gun_db, gun)


# /tp the Minecraft way (director): /tp <x> <y> <z> (~ = where you are, ~5 = 5 from it; at sea the sea's own
# coordinates) | /tp <player> (to him, in whatever world he is) | /tp <who> <player> | /tp <who> <x> <y> <z>, who = a
# name or @s @p @r @a; moving others needs the host or an operator (they move on their own machines) | /tp <place>.
func _tp(args: Array) -> String:
	if args.is_empty():
		return String(ChatCommand.find(table, "tp")["usage"])
	var here: Vector3 = session.world_coords(session.local_player().global_position)
	if args.size() == 3 and _coords(args, here).is_finite():
		session.tp_to({"kind": "pos", "world": session.my_world(), "at": _coords(args, here)})
		return "Moved to %s." % _said(_coords(args, here))
	var who: Array = session.players_matching(String(args[0]))
	if who.is_empty() or (args.size() != 1 and args.size() != 2 and args.size() != 4):
		return session.travel(" ".join(PackedStringArray(args)).to_lower())  # a place (names may have spaces)
	var target := {}
	if args.size() == 1:  # /tp <player>: me to him
		target = {"kind": "player", "id": int(who[0])}
		who = session.players_matching("@s")
	elif args.size() == 2:
		var to: Array = session.players_matching(String(args[1]))
		if to.size() != 1:
			return "No player called %s." % args[1]
		target = {"kind": "player", "id": int(to[0])}
	else:
		var at := _coords(args.slice(1), here)
		if not at.is_finite():
			return String(ChatCommand.find(table, "tp")["usage"])
		target = {"kind": "pos", "world": session.my_world(), "at": at}
	var me: int = session.players_matching("@s")[0]
	var moved := PackedStringArray()
	for id: int in who:
		if target.get("kind") == "player" and int(target["id"]) == id:
			continue  # (not onto himself)
		if id == me:
			session.tp_to(target)
		elif session.net != null and session.net.can_send():
			session.net.chat.ask_tp(id, target)
		moved.append(session.player_label(id))
	if moved.is_empty():
		return "Nobody to move."
	var dest: String = session.player_label(int(target["id"])) if target.get("kind") == "player" else _said(target["at"])
	return "Teleported %s to %s." % [", ".join(moved), dest]


# x y z words with Minecraft's ~ (relative to `base`); Vector3.INF when they are not coordinates.
static func _coords(words: Array, base: Vector3) -> Vector3:
	if words.size() < 3:
		return Vector3.INF
	var out := Vector3.ZERO
	for i in 3:
		var w := String(words[i])
		if w.begins_with("~"):
			var rest := w.substr(1)
			if rest != "" and not rest.is_valid_float():
				return Vector3.INF
			out[i] = base[i] + (rest.to_float() if rest != "" else 0.0)
		elif w.is_valid_float():
			out[i] = w.to_float()
		else:
			return Vector3.INF
	return out


static func _said(at: Vector3) -> String:
	return "%.1f %.1f %.1f" % [at.x, at.y, at.z]


func _level(args: Array, usage: String) -> String:
	if args.size() < 1 or not String(args[0]).is_valid_int():
		return usage
	var progress: RefCounted = session.progress()
	var wanted := clampi(String(args[0]).to_int(), 1, 50)
	if wanted < progress.level():
		progress.xp = 0
		progress.add_xp(0)
	for _i in 400:
		if progress.level() >= wanted or progress.xp_for_level() <= 0:
			break
		progress.add_xp(maxi(progress.xp_for_level() - progress.xp_into_level(), 1))
	session.refresh_after_command()
	return "Level %d now." % progress.level()


func _spawn(args: Array, near: Node3D, usage: String) -> String:
	var id := String(args[0]) if args.size() > 0 else ""
	if not _enemy_stats.has(id):
		return "%s  Enemies: %s" % [usage, ", ".join(_enemy_stats.keys())]
	var count := clampi(String(args[1]).to_int(), 1, SPAWN_MAX) if args.size() > 1 else 1
	var forward := -near.global_transform.basis.z
	if near.has_method("look_yaw"):
		forward = Basis(Vector3.UP, float(near.call("look_yaw"))) * Vector3.FORWARD
	for i in count:
		var side := (float(i) - float(count - 1) / 2.0) * 2.0
		var at := near.global_position + forward * 8.0 + forward.cross(Vector3.UP) * side + Vector3(0, 0.5, 0)
		if session.fantasy() != null and session.fantasy().spawn_creature(id, near):
			continue  # the fantasy world places its own creatures (they pay experience, drops and quest progress)
		session.director().spawn_custom(id, _enemy_stats[id], at)
	return "Spawned %d x %s." % [count, id]
