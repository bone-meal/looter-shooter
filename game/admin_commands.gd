# Purpose: runs chat commands (data/commands.json) for testing without grinding: give guns and items, travel, heal,
# god mode, flight, levels, spawn and remove enemies, plus the fantasy world's skills, spells, gear and quests.
# `run` returns the lines to show the person who typed the command. Who may run what is decided by the caller
# (game/game_session.gd): "self" commands run on the typist's machine, "world" commands on the host.
# Dependencies: core/chat_command.gd, core/gun_gen.gd, core/gun_stats.gd, core/data_store.gd, game/player.gd, game/game_session.gd
# (`session`: local_player, director, progress, wallet, travel, fantasy, refresh_after_command).
extends Node

const ChatCommand = preload("res://core/chat_command.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
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
		"power":
			out.append(String(session.call("drop_power", String(args[0]) if not args.is_empty() else "", near)))
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
			var gun := GunGen.generate(player.gun_db, _rng, 0.0, body, tier)
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
		"item":
			var item := String(args[1]) if args.size() > 1 else ""
			if not player.items.has_item(item):
				return "Unknown item %s." % item
			var count := maxi(String(args[2]).to_int(), 1) if args.size() > 2 else 1
			var left: int = player.inventory.add(item, count)
			session.refresh_after_command()
			return "Gave %d x %s." % [count - left, player.items.item_name(item)]
		"coins":
			if args.size() < 2 or not String(args[1]).is_valid_int():
				return "/give coins <amount>"
			session.wallet().add(maxi(String(args[1]).to_int(), 0))
			return "You have %d coins." % session.wallet().balance
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


func _tp(args: Array) -> String:
	if args.size() == 3 and String(args[0]).is_valid_float() and String(args[1]).is_valid_float() and String(args[2]).is_valid_float():
		session.local_player().teleport(Vector3(String(args[0]).to_float(), String(args[1]).to_float(), String(args[2]).to_float()), session.local_player().look_yaw())
		return "Moved."
	if args.is_empty():
		return String(ChatCommand.find(table, "tp")["usage"])
	return session.travel(" ".join(PackedStringArray(args)).to_lower())


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
