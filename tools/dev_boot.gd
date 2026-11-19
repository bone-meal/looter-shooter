# Purpose: developer check helper. game/main.gd adds it when the game is started with the user argument --autostart
# (done by tools/game_boot_check.tscn). It lets the real game session run, switches the player to third person, saves a
# picture and the frame cost per stage into res://tools/userdata/boot_<renderer>*, then quits. User argument
# --cmd=<chat line>;<chat line> types those lines into the chat first (commands included). Not part of exports.
# Dependencies: the running game (finds the player by its set_third_person method).
extends Node

const Threat = preload("res://core/sea/threat_rules.gd")
const DeckWalkDev = preload("res://core/sea/deck_walk.gd")

const ShortcutSpots = preload("res://core/shortcut_spots.gd")
const GunGen = preload("res://core/gun_gen.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const IsleWalker = preload("res://tools/isle_walker.gd")
const IsleRoutes = preload("res://core/sea/isle_routes.gd")

const OUT := "res://tools/userdata/"

var _ship_i := 0  # !ship use: which ship of the fleet the !ship steps act on
var _lines := PackedStringArray()
var _counting := false  # !fight has hooked the ward's signal
var _listening := false  # !moves has hooked the special attacks' signal
var _used := PackedStringArray()  # "creature:move" for every special attack started since the last !moves
var _wards := [0, 0]  # blows the ward stopped: [held, just in time]
var _msaa := -1  # the 3D anti-aliasing the game had set before "!fx msaa off"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_physics_steps_per_frame = 60  # a slow machine still walks at full speed during a scripted run
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var renderer := "forward_plus" if RenderingServer.get_rendering_device() != null else "compatibility"
	_lines.append("renderer=%s adapter=%s" % [renderer, RenderingServer.get_video_adapter_name()])
	for arg in OS.get_cmdline_user_args():  # tools/net_pair_check.tscn runs two copies: each names its own files
		if arg.begins_with("--boot-tag="):
			renderer = arg.get_slice("=", 1)
	_lines.append("the game was ready to play %d ms after the program started" % Time.get_ticks_msec())
	var screen: Variant = _find_with(get_tree().root, "run_chat").get("loading")
	while screen is Control and (screen as Control).visible:  # the first frames are drawn under the loading picture
		await get_tree().process_frame
	_lines.append("the loading picture was gone %d ms after the program started" % Time.get_ticks_msec())
	await _stage(renderer, "first_person", 3.0)
	for arg in OS.get_cmdline_user_args():  # --cmd=/tp club;/give unique all  runs chat lines, then one more picture
		if arg.begins_with("--cmd="):
			var session := _find_with(get_tree().root, "run_chat")
			session.set("no_save", true)  # a scripted run must never change the player's real save
			(session.get("settings") as RefCounted).set("dev_commands", true)  # the steps are chat commands
			_lines.append("his settings: graphics %s, lighting %s, window %s" % [str((session.get("settings") as RefCounted).get("graphics")), str((session.get("settings") as RefCounted).get("shaders")), str(DisplayServer.window_get_size())])
			for text in arg.substr(6).split(";", false):
				if text.begins_with("!"):
					await _dev(renderer, session, text.substr(1).split(" ", false))
				else:
					var began := Time.get_ticks_msec()
					session.call("run_chat", text)
					if Time.get_ticks_msec() - began > 50:
						_lines.append("  (that took %d ms)" % (Time.get_ticks_msec() - began))
				_lines.append("ran %s" % text)
			await _stage(renderer, "after_commands", 2.0)
	var player := _find_player(get_tree().root)
	_lines.append("player found = %s" % str(player != null))
	if player != null:
		player.call("set_third_person", true)
	await _stage(renderer, "third_person", 3.0)
	_lines.append("LOAD TIMES (where the waiting went):")
	_lines.append_array(load("res://game/load_clock.gd").get("marks"))
	_lines.append("BOOT_DONE")
	var f := FileAccess.open(OUT + "boot_%s.txt" % renderer, FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	get_tree().quit()


# Developer-only steps between chat lines: !wait <s>, !shot <name>, !look <yaw> <pitch> (degrees), !third,
# !key <action> (a short press), !hold <action> / !release <action>, !snap <name> (picture at once), !cast <elements> (a staff spell in the fantasy world, free of mana), !goto <x> <z>, !nearnode, !accept <quest>, !use <item>, !make <recipe>,
# !state (fantasy bag, levels and quests into the log), !neartrack [id start] (stand at the nearest animal tracks, or node whose id starts so), !nearclimb (stand at the foot of the nearest cliff shortcut), !sea time|weather|go|status (sea world), !isle routes [island] | walk [place|all] [island] (the island's generated paths: joined up? walked by the real player), !ship status|board|helm|letgo|anchor up|down|stage n|rudder r|off|wind deg|head deg (sea ships), !swim status|drop x z|spot n|take|ladder|climb|rope|stamina n|log (swimming, salvage), !animals [note|go|kill] (wild animals near and what they do; go = stand 6 m from the nearest, kill = it falls to you), !fight [note] (health, mana, ward and nearby creatures into the log), !face (turn to the nearest creature), !marks [note] (spikes, fire and water lying on the ground into the log), !squad [note] (every creature's squad order and where it stands into the log), !moves [note] (the special attacks creatures have used since the last !moves into the log), !usemove (the nearest creature starts its own attack now), !above name [height] [yaw] (a picture from the air), !heard [seconds] (the sounds audible in the last seconds into the log), !tier <id> (graphics tier potato / low / medium / high / ultimate for the rest of the run), !buildings full|plain (which building models places built from now on use), !where [note] (the player's map position into the log), !photo <name> (a HUD-less picture for the loading screens).
func _dev(renderer: String, session: Node, words: PackedStringArray) -> void:
	var player := _find_player(get_tree().root) as Node3D
	match words[0]:
		"wait":
			await get_tree().create_timer(float(words[1]), true, false, true).timeout
		"shot":
			await _stage(renderer, words[1], 0.2)
		"look":
			var yaw := deg_to_rad(float(words[1]))
			var pitch := deg_to_rad(float(words[2]))
			var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
			player.call("look_at_point", player.global_position + Vector3(0, 1.6, 0) + dir * 20.0)
		"third":
			player.call("set_third_person", true)
		"key":
			var press := InputEventAction.new()
			press.action = words[1]
			press.pressed = true
			Input.parse_input_event(press)
			await get_tree().create_timer(0.15, true, false, true).timeout
			var release := InputEventAction.new()
			release.action = words[1]
			Input.parse_input_event(release)
		"mixnet":  # "!mixnet <note>": the Mixtape online: songs held, what plays where, and each other player's body (gimmick shown, song heard)
			var link: Node = session.get("net").get("mixtape")
			var bodies := PackedStringArray()
			for body: Node in session.get("net").call("target_nodes"):
				var held: Node3D = body.get("_held_model")
				var speaker: AudioStreamPlayer3D = body.get("_speaker")
				bodies.append("%s held=%s mp3=%s playing=%s at=%.1f" % [body.name, String(body.get("_held_id")), str(held != null and held.find_child("Screen", true, false) != null),
					str(speaker != null and speaker.playing), speaker.get_playback_position() if speaker != null and speaker.playing else -1.0])
			_lines.append("MIXNET %s @%.1f: cache %d, playing %s, sending %d, uploading %s | %s" % [" ".join(words.slice(1)), fmod(Time.get_unix_time_from_system(), 1000.0), (link.get("cache") as Dictionary).size(), str((link.get("_playing") as Dictionary).keys()),
				(link.get("_sending") as Dictionary).size(), str(not (link.get("_uploading") as Dictionary).is_empty()), " ; ".join(bodies)])
		"readyunique":  # "!readyunique <id> [slot 1-4]": that unique goes straight into a ready slot (what was there is lost; dev runs never save)
			var slot := (int(words[2]) - 1) if words.size() > 2 else 1
			var made: Dictionary = GunGen.unique(player.get("gun_db"), words[1], 5)
			if made.is_empty():
				_lines.append("READYUNIQUE: unknown %s" % words[1])
			else:
				player.get("inventory").call("set_holster_gun", slot, made)
				player.call("refresh_held")
				_lines.append("READYUNIQUE %s in slot %d" % [words[1], slot + 1])
		"bagclear":  # "!bagclear [n]": empties up to n backpack slots that hold guns (room for a test; dev runs never save)
			var cleared := 0
			for i in InventoryState.SIZE:
				if cleared < (int(words[1]) if words.size() > 1 else 36) and not (player.get("inventory").call("gun_at", i) as Dictionary).is_empty():
					player.get("inventory").call("take_slot", i)
					cleared += 1
			player.call("refresh_held")
			_lines.append("BAGCLEAR %d" % cleared)
		"readygun":  # "!readygun <body> [tier] [slot 1-4]": a rolled gun of that body straight into a ready slot
			var gun_slot := (int(words[3]) - 1) if words.size() > 3 else 1
			var rolled: Dictionary = GunGen.generate(player.get("gun_db"), RandomNumberGenerator.new(), 0.0, words[1], words[2] if words.size() > 2 else "purple", "", 10)
			player.get("inventory").call("set_holster_gun", gun_slot, rolled)
			player.call("refresh_held")
			_lines.append("READYGUN %s in slot %d" % [words[1], gun_slot + 1])
		"fire":  # "!fire": one shot of the gun in hand through its own shot code (a held shoot key is ignored by a window without focus)
			var w: Variant = player.get("weapon")
			if w != null and int(w.get("ammo")) <= 0:  # an empty magazine reloads first (as holding shoot would)
				player.call("_reload")
				for _r in 80:
					await get_tree().create_timer(0.1, true, false, true).timeout
					if not bool(w.call("is_reloading")):
						break
			var fired := false
			for _f in 20:  # the gun may still be between shots (a reload's end, its fire rate): try for up to a second
				if w != null and bool(w.call("try_fire", Time.get_ticks_msec() / 1000.0)):
					fired = true
					break
				await get_tree().create_timer(0.05, true, false, true).timeout
			if fired:
				player.call("_shoot")
				var sig_f: Node = player.get("_sig_node")
				if sig_f != null and sig_f.has_method("on_fired"):
					sig_f.call("on_fired")  # as the real trigger does (Hot Potato heat)
				_lines.append("FIRE shot (%d left)" % int(w.get("ammo")))
			else:
				_lines.append("FIRE could not shoot: hand %d held %s ammo %s reloading %s paused %s" % [int(player.get("_hand")), String(player.call("held_id")), str(w.get("ammo")) if w != null else "-", str(w.call("is_reloading")) if w != null else "-", str(get_tree().paused)])
		"balls":  # "!balls <note>": beach balls on this machine (own / copies) and the net counts; "!balls wait" waits up to 40 s for a copy of somebody else's
			var pool: Node = get_tree().get_first_node_in_group("beach_balls")
			if words.size() > 1 and words[1] == "wait":
				for _w in 400:
					pool = get_tree().get_first_node_in_group("beach_balls")
					if pool != null and _copy_ball(pool) >= 0:
						break
					await get_tree().create_timer(0.1, true, false, true).timeout
			var live := PackedStringArray()
			if pool != null:
				for k in (pool.get("_life") as PackedFloat32Array).size():
					if (pool.get("_life") as PackedFloat32Array)[k] > 0.0:
						live.append("[%d] owner=%d their=%d volleys=%d at %s" % [k, (pool.get("_owner") as PackedInt32Array)[k], (pool.get("_their_slot") as PackedInt32Array)[k], (pool.get("_volleys") as PackedInt32Array)[k], str(((pool.get("_balls") as Array)[k] as Node3D).position.snapped(Vector3.ONE * 0.1))])
			var link: Node = session.get("net").get("beach_balls")
			_lines.append("BALLS %s @%.1f: %s | sent %d heard %d" % [" ".join(words.slice(1)), fmod(Time.get_unix_time_from_system(), 1000.0), ", ".join(live) if not live.is_empty() else "none", int(link.get("sent")), int(link.get("heard"))])
		"ballkick":  # "!ballkick": step into the first copy of somebody else's ball (the real kick path)
			var pool_k: Node = get_tree().get_first_node_in_group("beach_balls")
			var ck := _copy_ball(pool_k) if pool_k != null else -1
			if ck >= 0:
				var at: Vector3 = ((pool_k.get("_balls") as Array)[ck] as Node3D).position
				player.call("teleport", at + Vector3(-0.6, -1.0, 0.0), 0.0)
				_lines.append("BALLKICK stepped into copy [%d] at %s" % [ck, str(at.snapped(Vector3.ONE * 0.1))])
			else:
				_lines.append("BALLKICK no copy to kick")
		"ballshoot":  # "!ballshoot": a shot straight through the first copy of somebody else's ball
			var pool_s: Node = get_tree().get_first_node_in_group("beach_balls")
			var cs := _copy_ball(pool_s) if pool_s != null else -1
			if cs >= 0:
				var at_s: Vector3 = ((pool_s.get("_balls") as Array)[cs] as Node3D).position
				_lines.append("BALLSHOOT copy [%d] hit %s" % [cs, str(pool_s.call("shot_through", at_s - Vector3(3, 0, 0), Vector3(1, 0, 0), 10.0))])
			else:
				_lines.append("BALLSHOOT no copy to shoot")
		"chase":  # "!chase <note>": other players' chase-gun effects shown here (Croak's frog copies, Swamp Gas cloud copies) and our own clouds
			if words.size() > 1 and (words[1] == "wait_cloud" or words[1] == "wait_frog"):  # up to 60 s for a copy to show
				for _w in 600:
					var gas_w: Node = get_tree().get_first_node_in_group("swamp_gas")
					var seen := false
					if words[1] == "wait_cloud" and gas_w != null:
						for k in (gas_w.get("_life") as PackedFloat32Array).size():
							seen = seen or ((gas_w.get("_life") as PackedFloat32Array)[k] > 0.0 and (gas_w.get("_owner") as PackedInt32Array)[k] != 0)
					if words[1] == "wait_frog":
						for f: Variant in (session.get("net").get("chase").get("_frogs") as Dictionary).values():
							seen = seen or (is_instance_valid(f) and (f as Node3D).visible)
					if seen:
						break
					await get_tree().create_timer(0.1, true, false, true).timeout
			var link_c: Node = session.get("net").get("chase")
			var frogs := PackedStringArray()
			var frog_map: Dictionary = link_c.get("_frogs")
			for peer: int in frog_map:
				var f: Node3D = frog_map[peer]
				frogs.append("frog of %d %s at %s" % [peer, "shown" if is_instance_valid(f) and f.visible else "hidden", str(f.global_position.snapped(Vector3.ONE * 0.1)) if is_instance_valid(f) else "-"])
			var clouds := PackedStringArray()
			var gas: Node = get_tree().get_first_node_in_group("swamp_gas")
			if gas != null:
				for k in (gas.get("_life") as PackedFloat32Array).size():
					if (gas.get("_life") as PackedFloat32Array)[k] > 0.0:
						clouds.append("[%d] owner=%d" % [k, (gas.get("_owner") as PackedInt32Array)[k]])
			var bombs := 0
			for n: Node in get_tree().get_nodes_in_group("fire_sources"):
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("firebomb.gd"):
					bombs += 1
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("fire_geyser.gd"):
					bombs += 100  # (a geyser counts as 100 in "bombs")
			var penguins := 0
			for n: Node in get_tree().get_root().find_children("*", "Node3D", true, false):
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("potato_bomb.gd"):
					bombs += 10000  # (a flying Hot Potato counts as 10000)
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("penguin_slider.gd"):
					penguins += 1
			var snowballs := get_tree().get_nodes_in_group("snowballs").size()
			var kites := PackedStringArray()
			for k: Node in get_tree().get_nodes_in_group("kites"):
				kites.append("kite of %d%s%s" % [int(k.call("peer")), " diving" if bool(k.call("diving")) else "", " shown" if (k as Node3D).is_visible_in_tree() else " hidden"])
			for bm: Node in get_tree().get_nodes_in_group("lighthouse_beams"):
				kites.append("beam %s healed %d burned %d" % ["mine" if bool(bm.get("owned")) else "copy", int(bm.get("healed")), int(bm.get("burned"))])
			if not get_tree().get_nodes_in_group("treasure_xs").is_empty():
				kites.append("treasure Xs %d" % get_tree().get_nodes_in_group("treasure_xs").size())
			if not get_tree().get_nodes_in_group("golden_eggs").is_empty():
				kites.append("golden eggs %d" % get_tree().get_nodes_in_group("golden_eggs").size())
			kites.append("credited %d" % int(player.get("kills_credited")))
			var rounds_net: Variant = session.get("net").get("rounds") if session.get("net") != null else null
			if rounds_net != null and "taunts" in rounds_net:
				kites.append("taunts %d" % int(rounds_net.get("taunts")))
			var paper: Node = get_tree().get_first_node_in_group("paper_copies")
			if paper != null:
				kites.append("paper copies %d" % int(paper.call("count")))
			var marks := 0
			for n2: Node in get_tree().get_root().find_children("wanted_mark", "Label3D", true, false):
				marks += 1 if n2.is_inside_tree() else 0
			if marks > 0:
				kites.append("wanted marks %d" % marks)
			if not get_tree().get_nodes_in_group("whirlpools").is_empty():
				kites.append("whirlpools %d" % get_tree().get_nodes_in_group("whirlpools").size())
			for fl: Node in get_tree().get_nodes_in_group("gull_flocks"):
				kites.append("gulls of %d idle %d" % [int(fl.call("peer")), int(fl.call("idle_count"))])
			var lanterns := 0
			for n: Node in get_tree().get_nodes_in_group("lanterns"):
				var sw := (n as Node3D).find_child("Swing", true, false) as Node3D
				if n.has_meta("lantern_held") and sw != null and sw.visible and (n as Node3D).is_visible_in_tree():
					lanterns += 1
			_lines.append("CHASE %s @%.1f: %s | clouds %s | bombs %d, lit lanterns %d, penguins %d, snowballs %d | %s | sent %d heard %d" % [" ".join(words.slice(1)), fmod(Time.get_unix_time_from_system(), 1000.0), ", ".join(frogs) if not frogs.is_empty() else "no frogs", ", ".join(clouds) if not clouds.is_empty() else "none", bombs, lanterns, penguins, snowballs, ", ".join(kites) if not kites.is_empty() else "no kites / gulls", int(link_c.get("sent")), int(link_c.get("heard"))])
		"gasfire":  # "!gasfire": a fire for one second at the first copy of somebody else's gas cloud (the copy tells its owner)
			var gas_f: Node = get_tree().get_first_node_in_group("swamp_gas")
			var spot := Vector3.INF
			if gas_f != null:
				for k in (gas_f.get("_life") as PackedFloat32Array).size():
					if (gas_f.get("_life") as PackedFloat32Array)[k] > 0.0 and (gas_f.get("_owner") as PackedInt32Array)[k] != 0:
						spot = ((gas_f.get("_puffs") as Array)[k * 2] as Node3D).position
						break
			if spot == Vector3.INF:
				_lines.append("GASFIRE no copy")
			else:
				var fire := _DevFire.new()
				fire.at = spot
				add_child(fire)
				fire.add_to_group("fire_sources")
				_lines.append("GASFIRE lit at %s" % str(spot.snapped(Vector3.ONE * 0.1)))
				await get_tree().create_timer(1.0, true, false, true).timeout
				fire.queue_free()
		"kitecatch":  # "!kitecatch": the Kite Flyer in hand catches a lightning flash now (storms are rare in a test)
			var sig_c: Node = player.get("_sig_node")
			if sig_c != null and sig_c.has_method("catch_lightning"):
				sig_c.call("catch_lightning")
				_lines.append("KITECATCH caught %d" % int(sig_c.get("caught")))
			else:
				_lines.append("KITECATCH no kite gun in hand")
		"aimnear":  # "!aimnear": look at the nearest living enemy's chest (then !fire hits it)
			var src_a: Variant = player.get("explosives").get("source")
			var near_a: Node3D = null
			for e: Node3D in src_a.call("enemy_list"):
				if is_instance_valid(e) and not e.health.is_dead() and (near_a == null or e.global_position.distance_to(player.global_position) < near_a.global_position.distance_to(player.global_position)):
					near_a = e
			if near_a != null:
				player.call("look_at_point", near_a.global_position + Vector3(0, 1.1, 0))
			_lines.append("AIMNEAR %s" % (str(near_a.global_position.snapped(Vector3.ONE * 0.1)) if near_a != null else "nothing"))
		"tofriend":  # "!tofriend": stand 3 m from the first other player (two-copy tests)
			var spots: Dictionary = session.get("net").call("positions")
			var my: int = int(session.get("net").call("my_id"))
			for peer: int in spots:
				if peer != my:
					player.global_position = (spots[peer] as Vector3) + Vector3(3, 0.5, 0)
					_lines.append("TOFRIEND %d at %s" % [peer, str(player.global_position.snapped(Vector3.ONE * 0.1))])
					break
		"treasure":  # "!treasure": the Treasure Map in hand marks an X now and the player stands on it
			var sig_t: Node = player.get("_sig_node")
			var x_t: Node3D = sig_t.call("mark_new") if sig_t != null and sig_t.has_method("mark_new") else null
			if x_t != null:
				player.global_position = x_t.global_position + Vector3(0.5, 0.3, 0)
			_lines.append("TREASURE %s" % (str(x_t.global_position.snapped(Vector3.ONE * 0.1)) if x_t != null else "none"))
		"coin":  # "!coin f|i": the Split Decision's next shot is fire / ice
			var sig_c2: Node = player.get("_sig_node")
			if sig_c2 != null and "fire" in sig_c2:
				sig_c2.set("fire", words.size() > 1 and words[1] == "f")
			_lines.append("COIN %s" % (words[1] if words.size() > 1 else "?"))
		"pearl":  # "!pearl": the Clam Shell in hand fires a full pearl now (a held trigger cannot be held in a test window)
			var sig_p: Node = player.get("_sig_node")
			if sig_p != null and sig_p.has_method("release_pearl"):
				sig_p.call("release_pearl", 1.0)
			_lines.append("PEARL %s" % (str(sig_p.get("pearls")) if sig_p != null and "pearls" in sig_p else "no clam"))
		"charge":  # "!charge": the Spaghetti in hand is charged now (as if the scope had been held up)
			var sig_s2: Node = player.get("_sig_node")
			if sig_s2 != null and sig_s2.has_method("charge_now"):
				sig_s2.call("charge_now")
			_lines.append("CHARGE %s" % str(sig_s2 != null and sig_s2.has_method("charge_now")))
		"vanestorm":  # "!vanestorm": the Weathervane in hand acts as if it storms
			var sig_v: Node = player.get("_sig_node")
			if sig_v != null and "force_storm" in sig_v:
				sig_v.set("force_storm", true)
			_lines.append("VANESTORM %s" % str(sig_v != null and "force_storm" in sig_v))
		"signear":  # "!signear": the chase gun in hand's on_target_hit on the nearest living enemy (a hit, not a kill)
			var src_n: Variant = player.get("explosives").get("source")
			var near_n: Node3D = null
			for e: Node3D in src_n.call("enemy_list"):
				if is_instance_valid(e) and not e.health.is_dead() and (near_n == null or e.global_position.distance_to(player.global_position) < near_n.global_position.distance_to(player.global_position)):
					near_n = e
			var sig_n: Node = player.get("_sig_node")
			if near_n != null and sig_n != null and sig_n.has_method("on_target_hit"):
				sig_n.call("on_target_hit", near_n, near_n.global_position + Vector3(0, 1, 0), 10.0, false)
				_lines.append("SIGNEAR %s bolts %s" % [near_n.name, str(sig_n.get("bolts"))])
			else:
				_lines.append("SIGNEAR nothing")
		"sigkill":  # "!sigkill": kill the nearest enemy and tell the chase gun in hand it was its kill (Penguin Rescue: a penguin)
			var src_k: Variant = player.get("explosives").get("source")
			var near_k: Node3D = null
			for e: Node3D in src_k.call("enemy_list"):
				if is_instance_valid(e) and not e.health.is_dead() and (near_k == null or e.global_position.distance_to(player.global_position) < near_k.global_position.distance_to(player.global_position)):
					near_k = e
			var sig_k: Node = player.get("_sig_node")
			if near_k == null or sig_k == null or not sig_k.has_method("on_target_hit"):
				_lines.append("SIGKILL nothing")
			else:
				near_k.call("on_hit", 1000000.0, near_k.global_position + Vector3(0, 1, 0), Vector3.UP)
				sig_k.call("on_target_hit", near_k, near_k.global_position, 1000000.0, true)
				_lines.append("SIGKILL %s at %s" % [near_k.name, str(near_k.global_position.snapped(Vector3.ONE * 0.1))])
		"sauce":  # "!sauce": the chase gun in hand's on_target_hit 5 times on the nearest enemy (Volcano Sauce: an eruption)
			var src: Variant = player.get("explosives").get("source")
			var best: Node3D = null
			for e: Node3D in src.call("enemy_list"):
				if is_instance_valid(e) and (best == null or e.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
					best = e
			var sig_s: Node = player.get("_sig_node")
			if best == null or sig_s == null or not sig_s.has_method("on_target_hit"):
				_lines.append("SAUCE nothing to sauce")
			else:
				for _n in 5:
					sig_s.call("on_target_hit", best, best.global_position + Vector3(0, 1, 0), 10.0, false)
				_lines.append("SAUCE five hits on %s at %s" % [best.name, str(best.global_position.snapped(Vector3.ONE * 0.1))])
		"grilldrop":  # "!grilldrop": our Grillmaster food dropped 3 m in front of us (as a burning kill would)
			var food_d: Node = (load("res://game/signatures/grillmaster.gd") as GDScript).call("pool", player)
			food_d.call("drop", player.global_position + Vector3(0, 0, -3), 0.25, 20.0)
			_lines.append("GRILLDROP at %s" % str((player.global_position + Vector3(0, 0, -3)).snapped(Vector3.ONE * 0.1)))
		"grill":  # "!grill <note>|wait": food lying here (owner, slot) and our health; "wait" waits up to 40 s for food
			var food_g: Node = get_tree().get_first_node_in_group("grill_food")
			if words.size() > 1 and words[1] == "wait":
				for _w in 400:
					food_g = get_tree().get_first_node_in_group("grill_food")
					if food_g != null and int(food_g.call("active_count")) > 0:
						break
					await get_tree().create_timer(0.1, true, false, true).timeout
			var foods := PackedStringArray()
			if food_g != null:
				for k in (food_g.get("_life") as PackedFloat32Array).size():
					if (food_g.get("_life") as PackedFloat32Array)[k] > 0.0:
						foods.append("[%d] owner=%d their=%d at %s" % [k, (food_g.get("_owner") as PackedInt32Array)[k], (food_g.get("_their_slot") as PackedInt32Array)[k], str((food_g.get("_base") as PackedVector3Array)[k].snapped(Vector3.ONE * 0.1))])
			var hp: Variant = player.get("health")
			_lines.append("GRILL %s @%.1f: %s | hp %.0f/%.0f, eaten %d" % [" ".join(words.slice(1)), fmod(Time.get_unix_time_from_system(), 1000.0), ", ".join(foods) if not foods.is_empty() else "no food", float(hp.get("hp")), float(hp.get("max_hp")), int(food_g.get("eaten")) if food_g != null else 0])
		"grilleat":  # "!grilleat": walk onto the first food lying here (teleport onto it)
			var food_e: Node = get_tree().get_first_node_in_group("grill_food")
			var spot_e := Vector3.INF
			if food_e != null:
				for k in (food_e.get("_life") as PackedFloat32Array).size():
					if (food_e.get("_life") as PackedFloat32Array)[k] > 0.0:
						spot_e = (food_e.get("_base") as PackedVector3Array)[k]
						break
			if spot_e == Vector3.INF:
				_lines.append("GRILLEAT no food")
			else:
				player.call("teleport", spot_e, 0.0)
				_lines.append("GRILLEAT stepped onto %s" % str(spot_e.snapped(Vector3.ONE * 0.1)))
		"ghosttag":  # "!ghosttag <note>": what each other player holds and what his Fish Story tag reads on this copy
			var tags := PackedStringArray()
			for body: Node in session.get("net").call("target_nodes"):
				var label: Node = body.find_child("Record", true, false)
				var tool_n: Node = null
				for c: Node in body.find_children("Tool_*", "Node3D", true, false):
					tool_n = c
				tags.append("%s held=%s tag=%s tool=%s" % [body.name, String(body.get("_held_shown")), (label as Label3D).text.replace("\n", " ") if label is Label3D else "-",
					("%s on %s visible %s" % [tool_n.name, tool_n.get_parent().name, str((tool_n as Node3D).is_visible_in_tree())]) if tool_n != null else "-"])
			_lines.append("GHOSTTAG %s @%.1f: %s" % [" ".join(words.slice(1)), fmod(Time.get_unix_time_from_system(), 1000.0), " | ".join(tags)])
		"sighit":  # "!sighit <damage> [kill]": the chase gun in hand's behaviour hears one shot's damage (Fish Story: record, tag, told number)
			var sig_now: Node = player.get("_sig_node")
			if sig_now != null and sig_now.has_method("on_hit_total"):
				var told := float(sig_now.call("on_hit_total", player.global_position + Vector3(0, 1.6, -3), float(words[1]), words.size() > 2))
				_lines.append("SIGHIT %s -> shown %d, record %s" % [words[1], roundi(told), str(player.call("held_gun").get("record", "-"))])
		"sig":  # "!sig <note>": the chase gun in hand's red-text behaviour and (the Mixtape) what it plays
			var node: Node = player.get("_sig_node")
			_lines.append("SIG %s @%.1f: %s | %s" % [" ".join(words.slice(1)), fmod(Time.get_unix_time_from_system(), 1000.0), String(player.get("_sig_id")), String(node.call("playing_text")) if node != null and node.has_method("playing_text") else "-"])
			var inv_now: RefCounted = player.get("inventory")
			_lines.append("    hand %d, ready %s, held %s" % [int(player.get("_hand")), str([inv_now.call("holster_body", 0), inv_now.call("holster_body", 1)]), String(player.call("held_id"))])
		"skills":  # "!skills <q skill> [e skill]": the gun in hand gets these Q / E skills at best quality (a dev-only edit of a rolled gun)
			var hand := int(player.get("_hand"))
			var inv: RefCounted = player.get("inventory")
			if hand >= 0 and not (inv.call("holster_gun", hand) as Dictionary).is_empty():
				var picked: Array = []
				for w in words.slice(1):
					picked.append({"id": w, "q": 1.0})
				(inv.get("holsters")[hand]["gun"] as Dictionary)["skills"] = picked
				player.call("refresh_held")
			else:
				_lines.append("SKILLS: no rolled gun in hand")
		"hold":  # keeps an action down until !release (what holding the mouse button or a key does)
			Input.action_press(words[1])
		"release":
			Input.action_release(words[1])
		"where":  # "!where <note>": which world we are in and our place in its own coordinates (what /tp uses); "!where wait_jump <note>" first waits (up to 90 s) until we are moved 20 m+ at once (somebody's /tp)
			if words.size() > 1 and words[1] == "wait_jump":
				var from_j := player.global_position
				var until_j := Time.get_ticks_msec() + 90000
				while Time.get_ticks_msec() < until_j and player.global_position.distance_to(from_j) < 20.0:
					await get_tree().create_timer(0.2, true, false, true).timeout
			_lines.append("WHERE %s: %s at %s" % [" ".join(words.slice(1)), String(session.call("my_world")), str((session.call("world_coords", player.global_position) as Vector3).snapped(Vector3(0.1, 0.1, 0.1)))])
		"beast":  # sea step 8c: !beast open | swim [m] | shark [n] | serpent [m] | aim | finish | hitwyrm <n> | killwyrm | pause on|off | wait_bite | wait_surface | wait_hull | wait_lunge | wait_harvest | status <note>
			var sea_b2: Node = session.call("sea")
			var fleet_b2: Node = sea_b2.get("ships") if sea_b2 != null else null
			if fleet_b2 == null:
				_lines.append("beast: no sea")
			else:
				var enc_b: Node = fleet_b2.get("foes")
				var sharks_b: Node = enc_b.get("sharks")
				var wyrm_b: Node = enc_b.get("serpent")
				var ship_b: Node3D = (fleet_b2.get("ships") as Array)[clampi(_ship_i, 0, (fleet_b2.get("ships") as Array).size() - 1)]
				var nearest_b := func() -> Node3D:
					if sharks_b.has_meta("dev_held") and is_instance_valid(sharks_b.get_meta("dev_held")):
						return sharks_b.get_meta("dev_held")  # the one !beast hold put by the ship
					var best: Node3D = null
					for id_s: int in sharks_b.get("sharks"):
						var e_s: Node3D = sharks_b.get("sharks")[id_s]["enemy"]
						if is_instance_valid(e_s) and (best == null or e_s.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
							best = e_s
					return best
				match words[1] if words.size() > 1 else "status":
					"open":  # the ship in use out into open water (well clear of the home island), still, anchored
						var st_b: Dictionary = ship_b.get("state")
						st_b["x"] = 500.0
						st_b["z"] = 7800.0
						st_b["speed"] = 0.0
						st_b["anchored"] = true
					"swim":  # into the sea that far off the ship's starboard side
						var off_b := float(words[2]) if words.size() > 2 else 6.0
						player.call("teleport", ship_b.global_transform * Vector3(float(ship_b.get("spec")["outline"][3][1]) + off_b, -1.0, 0.0), 0.0)
					"shark":
						for _k in (int(words[2]) if words.size() > 2 else 1):
							sharks_b.call("_spawn_near", player)
					"serpent":
						var at_b: Vector3 = sea_b2.call("local_of", player.global_position)
						wyrm_b.call("spawn", at_b.x + (float(words[2]) if words.size() > 2 else 60.0), at_b.z)
					"pause":
						sharks_b.set("paused", words.size() < 3 or words[2] != "off")
					"aim":  # look at the nearest shark's middle
						var t_b: Node3D = nearest_b.call()
						if t_b != null:
							player.call("look_at_point", t_b.global_position + Vector3(0, 0.6, 0) - t_b.global_transform.basis.z * 0.3)
					"hold":  # the nearest shark held still 14 m off the starboard side, its back awash, and us at that rail (to harpoon it)
						var t_h: Node3D = nearest_b.call()
						if t_h != null:
							sharks_b.set_meta("dev_held", t_h)
							var beam_h := float(ship_b.get("spec")["outline"][3][1])
							var spot_h := ship_b.global_transform * Vector3(beam_h + 14.0, 0.0, 0.0)  # off her starboard side
							t_h.global_position = Vector3(spot_h.x, float(sea_b2.call("water_height", spot_h)) - 0.3, spot_h.z)
							var mine_h := ship_b.global_transform.affine_inverse() * player.global_position
							player.call("teleport", ship_b.global_transform * Vector3(beam_h - 0.8, mine_h.y + 0.2, 0.0), 0.0)
							for id_h: int in sharks_b.get("sharks"):
								if sharks_b.get("sharks")[id_h]["enemy"] == t_h:
									sharks_b.get("sharks")[id_h]["mode"] = "off"
					"bolts":  # where our last harpoons are (in flight or stuck in something), from the nearest shark
						var t_o: Node3D = nearest_b.call()
						var bolts_o: Node = session.get("_bolts")
						for shot_o: Dictionary in bolts_o.get("_shots"):
							if float(shot_o["life"]) > 0.0:
								_lines.append("  in flight at %s" % str((shot_o["node"] as Node3D).global_position.snapped(Vector3(0.1, 0.1, 0.1))))
						for lie_o: Dictionary in bolts_o.get("_lying"):
							var at_o := (lie_o["node"] as Node3D).global_position
							_lines.append("  stuck at %s, %.1f m from the shark" % [str(at_o.snapped(Vector3(0.1, 0.1, 0.1))), at_o.distance_to(t_o.global_position) if t_o != null else -1.0])
						if t_o != null:
							_lines.append("  shark at %s, we at %s, water %.2f" % [str(t_o.global_position.snapped(Vector3(0.1, 0.1, 0.1))), str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1))), float(sea_b2.call("water_height", t_o.global_position))])
					"aimwyrm":  # look at the wyrm's head
						if wyrm_b.get("wyrm") != null:
							player.call("look_at_point", (wyrm_b.get("wyrm") as Node3D).global_position)
					"finish":  # our blows finish the nearest shark (a harpoon in it = harvest)
						var t_f: Node3D = nearest_b.call()
						if t_f != null:
							if words.size() > 2 and words[2] == "harpoon":  # as if our harpoon had just gone in
								t_f.set_meta("harpooned_at", Time.get_ticks_msec() / 1000.0)
							_lines.append("  finishing a shark harpooned %s" % str(t_f.has_meta("harpooned_at")))
							session.get("_score").set("blow", "gun")
							t_f.call("on_hit", 99999.0, t_f.global_position + Vector3(0, 0.6, 0))
					"hitwyrm", "killwyrm":
						if wyrm_b.get("wyrm") != null:
							session.get("_score").set("blow", "gun")
							(wyrm_b.get("wyrm") as Node).call("on_hit", 999999.0 if words[1] == "killwyrm" else float(words[2]), (wyrm_b.get("wyrm") as Node3D).global_position)
					"wait_bite", "wait_dry", "wait_surface", "wait_hull", "wait_lunge", "wait_harvest", "wait_shark":  # (wait_bite online: a bite on us = our health drops)
						var until_b := Time.get_ticks_msec() + 90000
						var hp0_b := float(player.get("health").hp)
						while Time.get_ticks_msec() < until_b:
							if (words[1] == "wait_bite" and (int(sharks_b.get("bites")) > 0 or float(player.get("health").hp) < hp0_b - 0.5)) \
								or (words[1] == "wait_dry" and (sharks_b.call("swimmers") as Dictionary).is_empty()) or (words[1] == "wait_surface" and String(wyrm_b.get("mode")) == "surface") \
								or (words[1] == "wait_hull" and int(wyrm_b.get("hull_bites")) > 0) or (words[1] == "wait_lunge" and int(wyrm_b.get("lunges")) > 0) \
								or (words[1] == "wait_harvest" and int(sharks_b.get("harvested")) > 0) or (words[1] == "wait_shark" and not (sharks_b.get("sharks") as Dictionary).is_empty()):
								break
							await get_tree().create_timer(0.3).timeout
				_lines.append("BEAST %s: %s; %s; player hp %.0f, swimming %s; our ship hull %.0f" % [" ".join(words.slice(1)), String(sharks_b.call("status")), String(wyrm_b.call("status")), float(player.get("health").hp), str(player.get("swimming")), float(ship_b.get("state")["hull"])])
		"cargo":  # sea step 8b-2 holds, on ship n of "!ship use n": !cargo go | climb | down | put <item> <n> | take <item> <n> | look | status <note>
			var sea_c: Node = session.call("sea")
			var fleet_c: Node = sea_c.get("ships") if sea_c != null else null
			if fleet_c == null:
				_lines.append("cargo: no sea")
			else:
				var holds_c: Node = fleet_c.get("holds")
				if words.size() > 1 and words[1] == "wait":  # up to 90 s until a ship with a hold is in the fleet (online: the host's); the !ship / !cargo steps then use her
					var until_h := Time.get_ticks_msec() + 90000
					while Time.get_ticks_msec() < until_h and not (fleet_c.get("ships") as Array).any(func(sh: Node3D) -> bool: return not (sh.get("spec") as Dictionary).get("hold", {}).is_empty()):
						await get_tree().create_timer(0.5).timeout
					for i_h in (fleet_c.get("ships") as Array).size():
						if not ((fleet_c.get("ships") as Array)[i_h].get("spec") as Dictionary).get("hold", {}).is_empty():
							_ship_i = i_h
				var ship_c: Node3D = (fleet_c.get("ships") as Array)[clampi(_ship_i, 0, (fleet_c.get("ships") as Array).size() - 1)]
				var spec_c: Dictionary = ship_c.get("spec")
				var hold_c: Dictionary = spec_c.get("hold", {})
				var sub_c := words[1] if words.size() > 1 else "status"
				if hold_c.is_empty() and sub_c != "status":
					_lines.append("cargo: ship %d (%s) has no hold" % [_ship_i, String(ship_c.get("state")["ship"])])
				else:
					var st_c: Dictionary = hold_c.get("stair", {})
					var way_c := signf(float(st_c.get("high", 1.0)) - float(st_c.get("low", 0.0)))
					match sub_c:
						"go":  # stand in the hold by its chest
							var chest_c: Array = hold_c["chest"]
							player.call("teleport", ship_c.global_transform * Vector3(float(chest_c[0]) * 0.4, float(hold_c["floor"]) + 0.3, float(chest_c[1]) + 0.8), 0.0)
						"climb", "down":  # walk the companion stair up from its foot / down from the deck behind its head (the real move key)
							var foot_c := Vector3(float(st_c["x"]), float(hold_c["floor"]) + 0.3, float(st_c["low"]) - way_c * 0.9)
							var head_c := Vector3(float(st_c["x"]), float(spec_c["deck"]) + 0.3, float(st_c["high"]) + way_c * 1.4)
							var from_c := foot_c if sub_c == "climb" else head_c
							var to_c := head_c + Vector3(0, 0, way_c * 1.5) if sub_c == "climb" else foot_c - Vector3(0, 0, way_c * 1.5)
							player.call("teleport", ship_c.global_transform * from_c, 0.0)
							await get_tree().create_timer(0.4, true, false, true).timeout
							Input.action_press("move_forward")
							var began_c := Time.get_ticks_msec()
							while Time.get_ticks_msec() - began_c < 4000:
								player.call("look_at_point", ship_c.global_transform * (to_c + Vector3(0, 1.4, 0)))
								await get_tree().process_frame
							Input.action_release("move_forward")
							await get_tree().create_timer(0.4, true, false, true).timeout
							var local_c := ship_c.global_transform.affine_inverse() * player.global_position
							_lines.append("CARGO %s: now at ship-space (%.2f, %.2f, %.2f), in hold %s, aboard %s, swimming %s" % [sub_c, local_c.x, local_c.y, local_c.z, str(holds_c.call("in_hold_of", ship_c)), str(fleet_c.call("ship_aboard") == ship_c), str(player.get("swimming"))])
						"put", "take":
							holds_c.set("open_ship", ship_c)
							_lines.append("CARGO %s: %s" % [sub_c, String(holds_c.call(sub_c, words[2], int(words[3]) if words.size() > 3 else 1))])
							holds_c.set("open_ship", null)
						"look":  # face the cargo chest from where you stand
							var chest_l: Array = hold_c["chest"]
							player.call("look_at_point", ship_c.global_transform * Vector3(float(chest_l[0]), float(hold_c["floor"]) + 0.4, float(chest_l[1])))
				_lines.append("CARGO %s: %s; prompt '%s'" % [" ".join(words.slice(1)), String(holds_c.call("status")), String(fleet_c.call("prompt", "F"))])
		"snap":  # a picture right now (after one drawn frame), for things that are over quickly
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg(OUT + "boot_%s_%s.jpg" % [renderer, words[1]], 0.9)
		"cast":
			var world: Node = session.call("fantasy")
			if world != null:
				world.get("caster").call("_cast", words[1])
		"goto":  # fantasy world: stand at map metres x z
			var land: Node = session.call("fantasy")
			player.call("teleport", land.call("ground_world", float(words[1]), float(words[2])), 0.0)
		"nearnode":  # fantasy world: stand next to the nearest thing to gather
			var land: Node = session.call("fantasy")
			var node: Dictionary = land.get("gather").call("nearest", land.call("player_local"), 300.0)
			if not node.is_empty():
				player.call("teleport", land.call("ground_world", node["at"].x + 1.5, node["at"].z + 1.5), 0.0)
				player.call("look_at_point", land.call("world_of", node["at"]) + Vector3(0, 1.0, 0))
			_lines.append("nearest node: %s" % str(node.get("id", "none")))
		"neartrack":  # fantasy world: stand next to the nearest animal tracks (Hunting)
			var land: Node = session.call("fantasy")
			var here: Vector3 = land.call("player_local")
			var best := {}
			for key: Vector2i in land.get("gather").get("_nodes"):
				for node: Dictionary in land.get("gather").get("_nodes")[key]:
					var wanted := String(node["id"]).begins_with(words[1]) if words.size() > 1 else String(node["id"]).ends_with("_tracks")  # "!neartrack dig_" = the nearest dig
					if wanted and (best.is_empty() or here.distance_to(node["at"]) < here.distance_to(best["at"])):
						best = node
			if not best.is_empty():
				player.call("teleport", land.call("ground_world", best["at"].x + 1.0, best["at"].z + 1.0), 0.0)
				player.call("look_at_point", land.call("world_of", best["at"]))
			_lines.append("nearest tracks: %s" % str(best.get("id", "none")))
		"sea":  # sea world (step 4): !sea time <0..1> | weather <calm|rain|fog|storm|own> | go <x> <z> [y] | status
			var sea_world: Node = session.call("sea")
			if sea_world == null:
				_lines.append("sea: not built (use /tp sea first)")
			elif words.size() > 2 and words[1] == "time":
				sea_world.call("set_day_part", float(words[2]))
			elif words.size() > 2 and words[1] == "weather":
				sea_world.call("force_weather", "" if words[2] == "own" else words[2])
			elif words.size() > 3 and words[1] == "go":
				player.call("teleport", sea_world.call("world_of", Vector3(float(words[2]), float(words[4]) if words.size() > 4 else 25.0, float(words[3]))), 0.0)  # optional height: drop onto high ground
			else:
				_lines.append(String(sea_world.call("status")))
		"rbeast":  # sea step 8e: !rbeast spawn <kind> [m off] | kill [kind] | rail [port|starboard] | mid | onfire | hit <kind> <n> | wait <event> [n] | waitmode <mode> | status <note>
			var sea_r: Node = session.call("sea")
			var fleet_r: Node = sea_r.get("ships") if sea_r != null else null
			if fleet_r == null:
				_lines.append("rbeast: no sea")
			else:
				var mgr: Node = fleet_r.get("foes").get("beasts")
				var mine_r: Node3D = (fleet_r.get("ships") as Array)[clampi(_ship_i, 0, (fleet_r.get("ships") as Array).size() - 1)]
				var ms_r: Dictionary = mine_r.get("state")
				var spec_r: Dictionary = mine_r.get("spec")
				match words[1] if words.size() > 1 else "status":
					"spawn":
						mgr.call("spawn", words[2], float(ms_r["x"]) + (float(words[3]) if words.size() > 3 else 40.0), float(ms_r["z"]), int(words[4]) if words.size() > 4 else 1)
					"kill", "hit":
						for id_r: int in (mgr.get("beasts") as Dictionary).keys():
							var b_r: Dictionary = mgr.get("beasts").get(id_r, {})
							if b_r.is_empty() or (words.size() > 2 and String(b_r["kind"]) != words[2]):
								continue
							session.get("_score").set("blow", "gun")
							(b_r["enemy"] as Node).call("on_hit", 99999.0 if words[1] == "kill" else float(words[3]), (b_r["enemy"] as Node3D).global_position + Vector3(0.0, 0.5, 0.0))
					"rail", "mid":  # stand at her rail (starboard unless told port), amidships; or in her middle
						var side_r := -1.0 if words.size() > 2 and words[2] == "port" else 1.0
						var x_r := 0.0 if words[1] == "mid" else side_r * (float(DeckWalkDev.half_width(spec_r, 0.0)) - 0.7)
						player.call("teleport", mine_r.global_transform * Vector3(x_r, float(spec_r["deck"]) + 0.2, 0.0), 0.0)
					"byarm":  # stand on her deck where the first kraken arm smashes
						for b_a: Dictionary in (mgr.get("beasts") as Dictionary).values():
							if String(b_a["kind"]) == "kraken_arm":
								var x_a := float(b_a.get("side_i", 1)) * maxf(float(DeckWalkDev.half_width(spec_r, float(b_a.get("lz", 0.0)))) - 1.6, 0.3)
								player.call("teleport", mine_r.global_transform * Vector3(x_a, float(spec_r["deck"]) + 0.2, float(b_a.get("lz", 0.0))), 0.0)
								break
					"onfire":  # stand in the first fire on her deck
						for f_r: Array in mgr.get("fires"):
							if f_r[0] == mine_r:
								player.call("teleport", mine_r.global_transform * Vector3(float(f_r[1]), float(spec_r["deck"]) + 0.2, float(f_r[2])), 0.0)
								break
					"wait", "waitmode":
						var until_r := Time.get_ticks_msec() + 90000
						var hp_r := float(player.get("health").hp)
						while Time.get_ticks_msec() < until_r:
							if words[1] == "wait" and (int((mgr.get("counts") as Dictionary).get(words[2], 0)) >= (int(words[3]) if words.size() > 3 else 1) or (words[2] == "hurt" and float(player.get("health").hp) < hp_r - 0.5) or (words[2] == "swim" and bool(player.get("swimming")))):
								break
							if words[1] == "waitmode":
								var hit_m := false
								for id_m: int in mgr.get("beasts"):
									if String(mgr.get("beasts")[id_m]["mode"]) == words[2]:
										hit_m = true
								if hit_m:
									break
							await get_tree().create_timer(0.2, true, false, true).timeout
				_lines.append("RBEAST %s: %s; player hp %.0f swimming %s; our hull %.0f yaw %.1f tip %.1f at (%.1f, %.1f) speed %.1f" % [" ".join(words.slice(1)), String(mgr.call("status")), float(player.get("health").hp), str(player.get("swimming")), float(ms_r["hull"]), rad_to_deg(float(ms_r["yaw"])), float(mine_r.get("tip_deg")), float(ms_r["x"]), float(ms_r["z"]), float(ms_r["speed"])])
		"tool":  # sea step 9b: !tool give <id|all> | choose <id> | use | aim <cx> <cz> <y> (in the dungeon this player is in) | hold <action> on|off | status <note>
			var sea_t2: Node = session.call("sea")
			if sea_t2 == null:
				_lines.append("tool: no sea")
			else:
				var tm: Node = sea_t2.get("tools")
				var dmt: Node = sea_t2.get("dungeons")
				match words[1] if words.size() > 1 else "status":
					"give":
						for id_t: String in (tm.get("cfg")["order"] as Array) if words[2] == "all" else [words[2]]:
							tm.call("give", id_t)
					"choose":
						tm.set("chosen", words[2])
					"use":
						tm.call("use")
						await get_tree().create_timer(0.3, true, false, true).timeout
					"aim":
						var wt := String(dmt.get("where"))
						if wt != "":
							var sp_t: Vector3 = dmt.call("space_of", wt)
							player.call("look_at_point", sea_t2.call("world_of", sp_t + Vector3(float(words[2]), 0.0, float(words[3])) * float(dmt.get("cfg")["tile"]) + Vector3(0.0, float(words[4]) if words.size() > 4 else 1.0, 0.0)))
					"gun":  # a gun key: the tool goes away, the gun in hand comes back
						player.call("select_hand", int(player.get("_hand")))
					"third":  # third person on / off
						player.set("third_person", words.size() > 2 and words[2] == "on")
						player.call("_apply_view")
					"up":  # lifted that far into the air where he stands
						player.call("teleport", player.global_position + Vector3(0.0, float(words[2]), 0.0), float(player.call("look_yaw")))
					"hold":
						if words.size() > 3 and words[3] == "on":
							Input.action_press(words[2])
						else:
							Input.action_release(words[2])
				_lines.append("TOOL %s: held '%s', gun shown %s; %s; at %s; %s" % [" ".join(words.slice(1)), String(player.call("held_id")), str(bool(player.get("_holding"))), String(tm.call("status")), str((sea_t2.call("local_of", player.global_position) as Vector3).snapped(Vector3(0.1, 0.1, 0.1))), String(dmt.call("status"))])
		"dun":  # sea step 9: !dun gate [id] (stand before its island gate) | enter [id] | leave | stand <cx> <cz> [face cx cz] | use | prompt | reset | wait (state changes) | status <note>
			var sea_d: Node = session.call("sea")
			if sea_d == null:
				_lines.append("dun: no sea")
			else:
				var dm: Node = sea_d.get("dungeons")
				var did := words[2] if words.size() > 2 and words[1] in ["gate", "enter"] else (String(dm.get("where")) if String(dm.get("where")) != "" else "proving_vault")
				match words[1] if words.size() > 1 else "status":
					"gate":
						player.call("teleport", sea_d.call("world_of", dm.call("gate_front", did) + Vector3(0.0, 1.0, 0.0)), 0.0)
						await get_tree().create_timer(1.5, true, false, true).timeout
						player.call("look_at_point", (dm.get("gates")[did]["node"] as Node3D).global_position + Vector3(0.0, 2.5, 0.0))
					"enter":
						dm.call("enter", did)
					"leave":
						dm.call("leave")
					"stand":  # on that cell (its middle), looking at another cell (or the next one north)
						var sp: Vector3 = dm.call("space_of", did)
						var at_c := Vector3(float(words[2]), 0.0, float(words[3])) * float(dm.get("cfg")["tile"])
						at_c.y = float(dm.get("spaces")[did].get("rules").call("height_of", Vector2i(roundi(float(words[2])), roundi(float(words[3])))))  # (on a ledge: its top)
						player.call("teleport", sea_d.call("world_of", sp + at_c + Vector3(0.0, 0.4, 0.0)), 0.0)
						await get_tree().create_timer(0.3, true, false, true).timeout
						var fc := Vector3(float(words[4]), 0.0, float(words[5])) * float(dm.get("cfg")["tile"]) if words.size() > 5 else at_c + Vector3(0.0, 0.0, -3.0)
						player.call("look_at_point", sea_d.call("world_of", sp + fc + Vector3(0.0, 1.0, 0.0)))
					"go":  # !dun go <id> <cx> <cz>: stand on that cell of that dungeon / outdoor court (sea step 9d)
						var sp_g: Vector3 = dm.call("space_of", words[2])
						var cg := Vector2i(roundi(float(words[3])), roundi(float(words[4])))
						var h_g := float(dm.get("spaces")[words[2]].get("rules").call("height_of", cg))
						player.call("teleport", sea_d.call("world_of", sp_g + Vector3(float(words[3]) * float(dm.get("cfg")["tile"]), h_g + 0.4, float(words[4]) * float(dm.get("cfg")["tile"]))), 0.0)
						await get_tree().create_timer(0.6, true, false, true).timeout
					"slay":  # (host / alone) every fight foe in it struck down
						_lines.append("  slain %d" % int(dm.call("slay", did)))
						await get_tree().create_timer(0.6, true, false, true).timeout
					"fightwait":  # until the number of fight foes here changes (a wave comes, one falls), up to 60 s
						var until_f := Time.get_ticks_msec() + 60000
						var before_f := String(dm.call("status"))
						while Time.get_ticks_msec() < until_f and String(dm.call("status")).get_slice("foes [", 1).get_slice("]", 0).count("@") == before_f.get_slice("foes [", 1).get_slice("]", 0).count("@"):
							await get_tree().create_timer(0.25, true, false, true).timeout
					"reset":  # (host / alone) the dungeon as new
						var sp_r: Node3D = dm.get("spaces")[did]
						for f_ch: String in sp_r.get("rules").call("of_kind", "fight"):
							dm.call("drop_fight", did, f_ch)
						sp_r.get("rules").set("state", sp_r.get("rules").call("fresh"))
						sp_r.call("refresh", true)
						dm.set("_dirty", true)
					"wait":  # until this letter's thing has changed (door open, key / chest taken, lever pulled, block moved), up to 60 s (or `!dun wait <s>`)
						var until_d := Time.get_ticks_msec() + (int(float(words[2]) * 1000.0) if words.size() > 2 and words[2].is_valid_float() else 60000)
						var sp_w: Node3D = dm.get("spaces")[did]
						var before_w := JSON.stringify(sp_w.get("rules").get("state"))
						while Time.get_ticks_msec() < until_d and JSON.stringify(sp_w.get("rules").get("state")) == before_w:
							await get_tree().create_timer(0.25, true, false, true).timeout
					"use":
						_lines.append("  use: %s" % str(dm.call("interact")))
						await get_tree().create_timer(0.6, true, false, true).timeout
					"prompt":
						_lines.append("  prompt: '%s'" % String(dm.call("prompt", "F")))
				_lines.append("DUN %s: %s; prompt '%s'; indoor %s; at %s" % [" ".join(words.slice(1)), String(dm.call("status")), String(dm.call("prompt", "F")), str(sea_d.get("indoor")), str(sea_d.call("local_of", player.global_position).snapped(Vector3(0.1, 0.1, 0.1)))])
		"boss":  # sea step 10: !boss give (the offering) | door (stand at the temple's sealed door) | in (go through, once open) | hp <share> (host) | part <id> <damage> | face | hook (Grapple Hook at the shed bell) | kill (host) | wait <state|phase|mode|tide> <value> [s] | status <note>
			var sea_x: Node = session.call("sea")
			if sea_x == null:
				_lines.append("boss: no sea")
			else:
				var dmx: Node = sea_x.get("dungeons")
				var bx: Node = dmx.get("boss")
				var bid := "abbot_shellback"
				var bcfg: Dictionary = bx.call("boss_cfg", bid)
				match words[1] if words.size() > 1 else "status":
					"give":
						(sea_x.get("skills") as Node).call("give", String(bcfg["offering"]), int(words[2]) if words.size() > 2 else 1)
					"door":  # on the floor cell before the sealed door, half a cell from it, facing it
						var temple := String(bcfg["temple"])
						var rt: RefCounted = dmx.get("spaces")[temple].get("rules")
						var dc: Vector2i = rt.call("cell_of_thing", String(bcfg["door"]))
						for step_x: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
							var fc_x: Vector2i = dc + step_x
							if bool(rt.call("passable", fc_x)) and String(rt.call("char_at", fc_x)) != "#":
								var tile_x := float(dmx.get("cfg")["tile"])
								var spot_x := (Vector3(fc_x.x, 0.0, fc_x.y) - Vector3(step_x.x, 0.0, step_x.y) * 0.45) * tile_x  # (cells are centred on whole numbers)
								player.call("teleport", sea_x.call("world_of", (dmx.call("space_of", temple) as Vector3) + spot_x + Vector3(0.0, 0.4, 0.0)), 0.0)
								await get_tree().create_timer(0.4, true, false, true).timeout
								player.call("look_at_point", sea_x.call("world_of", (dmx.call("space_of", temple) as Vector3) + Vector3(dc.x, 0.0, dc.y) * tile_x + Vector3(0.0, 1.2, 0.0)))
								break
					"in":
						bx.call("use_door", bid)
						await get_tree().create_timer(1.0, true, false, true).timeout
					"hp":
						var ex: Node3D = bx.get("enemy")
						if ex != null:
							var hx: RefCounted = ex.get("health")
							hx.set("hp", float(hx.get("max_hp")) * float(words[2]))
					"part":
						bx.call("part_hit", words[2], float(words[3]))
					"face":
						var ef: Node3D = bx.get("enemy")
						if ef != null:
							player.call("look_at_point", ef.global_position + Vector3(0.0, 2.5, 0.0))
					"hook":  # look at the shed bell's clapper ring and use the Grapple Hook
						var ring_x: Node3D = bx.get("_bell_ring")
						if ring_x != null and is_instance_valid(ring_x):
							player.call("look_at_point", ring_x.global_position)
							await get_tree().create_timer(0.3, true, false, true).timeout
							var tmx: Node = sea_x.get("tools")
							tmx.set("chosen", "grapple")
							tmx.call("use")
							await get_tree().create_timer(0.5, true, false, true).timeout
						else:
							_lines.append("  no bell ring")
					"kill":
						var ek: Node3D = bx.get("enemy")
						if ek != null:
							ek.call("on_hit", 1.0e7)
					"wait":
						var until_x := Time.get_ticks_msec() + (int(float(words[4]) * 1000.0) if words.size() > 4 else 60000)
						while Time.get_ticks_msec() < until_x:
							var got_x := String(bx.get(words[2])) if words[2] in ["state", "mode", "attack"] else (str((bx.call("down_peers") as Array).size()) if words[2] == "down" else str(int(bx.get(words[2])) + (1 if words[2] == "phase" else 0)))
							if got_x == words[3]:
								break
							await get_tree().create_timer(0.2, true, false, true).timeout
				var hpp: RefCounted = player.get("health")
				var ex2: Node3D = bx.get("enemy")
				var gap_x := Vector2(ex2.global_position.x - player.global_position.x, ex2.global_position.z - player.global_position.z).length() if ex2 != null and is_instance_valid(ex2) else -1.0
				_lines.append("BOSS %s: %s; me hp %.0f/%.0f downed %s dread %d xp %d boss kills %d; boss %.1f m off; prompt '%s'; at %s" % [" ".join(words.slice(1)), String(bx.call("status")), float(hpp.get("hp")), float(hpp.get("max_hp")), str(player.get("downed")), int(player.get("dread")), int(session.get("_progress").get("xp")), int((session.get("_progress").get("counters") as Dictionary).get("boss_kills", 0)), gap_x, String(dmx.call("prompt", "F")), str(sea_x.call("local_of", player.global_position).snapped(Vector3(0.1, 0.1, 0.1)))])
		"uboat":  # sea step 8e-4: !uboat sight <surface|periscope> <none|torpedo_foe|torpedo_us|crate|chart> | near [m] (host: bring it close, broadside on) | cfg <key> <n> | look [torp] | pause on|off | wait <seen|gone|hit|deed> [n] | status <note>
			var sea_u: Node = session.call("sea")
			var fleet_u: Node = sea_u.get("ships") if sea_u != null else null
			if fleet_u == null:
				_lines.append("uboat: no sea")
			else:
				var ub: Node = fleet_u.get("foes").get("uboat")
				var ms_u: Dictionary = (fleet_u.get("ships") as Array)[clampi(_ship_i, 0, (fleet_u.get("ships") as Array).size() - 1)].get("state")
				match words[1] if words.size() > 1 else "status":
					"sight":
						ub.call("sight", words[2] if words.size() > 2 else "surface", words[3] if words.size() > 3 else "none")
					"near":
						var s_u: Dictionary = ub.get("sub")
						if not s_u.is_empty():
							var a_u := atan2(float(s_u["z"]) - float(ms_u["z"]), float(s_u["x"]) - float(ms_u["x"]))
							var m_u := float(words[2]) if words.size() > 2 else 90.0
							s_u["x"] = float(ms_u["x"]) + cos(a_u) * m_u
							s_u["z"] = float(ms_u["z"]) + sin(a_u) * m_u
							s_u["yaw"] = -a_u  # (broadside on, for a look)
					"cfg":  # a number of its data for this run
						(ub.get("cfg") as Dictionary)[words[2]] = float(words[3])
					"pause":
						ub.set("paused", words.size() < 3 or words[2] == "on")
					"look":  # face it (its conning tower) or its first torpedo
						var s_l: Dictionary = ub.get("sub")
						var t_l: Array = ub.get("torps")
						var at_l := Vector3(float(t_l[0]["x"]), 0.0, float(t_l[0]["z"])) if not t_l.is_empty() and words.size() > 2 else (Vector3(float(s_l["x"]), 3.0, float(s_l["z"])) if not s_l.is_empty() else Vector3.INF)
						if at_l.is_finite():
							player.call("look_at_point", sea_u.call("world_of", at_l))
					"wait":
						var until_u := Time.get_ticks_msec() + 90000
						var want_u := int(words[3]) if words.size() > 3 else 1
						while Time.get_ticks_msec() < until_u:
							var deeds_u := 0
							for k_u: String in ub.get("deeds"):
								deeds_u += int(ub.get("deeds")[k_u])
							if (words[2] == "seen" and not (ub.get("sub") as Dictionary).is_empty() and String(ub.get("sub").get("mode", "")) != "dive") or (words[2] == "gone" and (ub.get("sub") as Dictionary).is_empty()) \
								or (words[2] == "hit" and int(ub.get("torpedo_hits")) >= want_u) or (words[2] == "deed" and deeds_u >= want_u) or (words[2] == "torp" and not (ub.get("torps") as Array).is_empty()):
								break
							await get_tree().create_timer(0.2, true, false, true).timeout
				_lines.append("UBOAT %s: %s; our hull %.0f of %.0f; flotsam %s; chart pins %d" % [" ".join(words.slice(1)), String(ub.call("status")), float(ms_u["hull"]), float(ms_u.get("hull_max", 0.0)), String(fleet_u.get("foes").get("flotsam").call("status")), (sea_u.get("chart").get("pins") as Array).size()])
		"spook":  # sea step 8d: !spook fire (our nearest loaded gun at the newest ghost) | wait_solid | wait_faded | wait_gone | rise | wait_grab | wait_aboard | wait_risen <n> | killall | status <note>
			var sea_g: Node = session.call("sea")
			var fleet_g: Node = sea_g.get("ships") if sea_g != null else null
			if fleet_g == null:
				_lines.append("spook: no sea")
			else:
				var enc_g: Node = fleet_g.get("foes")
				var mine_g: Node3D = (fleet_g.get("ships") as Array)[clampi(_ship_i, 0, (fleet_g.get("ships") as Array).size() - 1)]
				var ghost_g: Node3D = null
				for ship_g: Node3D in enc_g.call("foes"):
					if bool(enc_g.get("rules").get("cfg")["kinds"].get(String(ship_g.get("state")["foe"]), {}).get("ghost", false)):
						ghost_g = ship_g
				var crews_g: Node = enc_g.get("crews")
				match words[1] if words.size() > 1 else "status":
					"fire":
						if ghost_g != null:
							var cannons_g: Node = fleet_g.get("cannons")
							var point_g: Vector3 = ghost_g.call("deck_spot", [0.0, 0.0], -0.8)
							for gun_g: Dictionary in cannons_g.call("guns_of", mine_g):
								if not bool(cannons_g.call("loaded", mine_g, int(gun_g["index"]))):
									continue
								var aim_g: Vector2 = cannons_g.call("aim_at", mine_g, int(gun_g["index"]), point_g)
								if not is_nan(aim_g.x) and bool(cannons_g.call("fire", mine_g, int(gun_g["index"]), aim_g.x, aim_g.y, true)):
									_lines.append("  fired gun %d at the ghost (phase %.2f)" % [int(gun_g["index"]), float(ghost_g.get("state").get("phase", 1.0))])
									break
					"rise":
						var ms_g: Dictionary = mine_g.get("state")
						enc_g.get("drowned").call("begin", mine_g, Vector2(float(ms_g["x"]), float(ms_g["z"])), int(words[2]) if words.size() > 2 else 1)
					"killall":
						for id_g: int in (crews_g.get("men") as Dictionary).keys():
							if (crews_g.get("men") as Dictionary).has(id_g) and String(crews_g.get("men")[id_g]["kind"]).begins_with(words[2] if words.size() > 2 else "sea_drowned"):
								session.get("_score").set("blow", "gun")
								var e_g: Node3D = crews_g.get("men")[id_g]["enemy"]
								e_g.call("on_hit", 99999.0, e_g.global_position + Vector3(0.0, 1.0, 0.0))
								await get_tree().create_timer(0.2).timeout
					"wait_solid", "wait_faded", "wait_gone", "wait_grab", "wait_aboard", "wait_risen":
						var until_g := Time.get_ticks_msec() + 90000
						while Time.get_ticks_msec() < until_g:
							var g_now: Node3D = null
							for ship_w: Node3D in enc_g.call("foes"):
								if bool(enc_g.get("rules").get("cfg")["kinds"].get(String(ship_w.get("state")["foe"]), {}).get("ghost", false)):
									g_now = ship_w
							var phase_w := float(g_now.get("state").get("phase", 0.0)) if g_now != null else -1.0
							var aboard_w := 0
							var undead_w := 0
							for id_w: int in crews_g.get("men"):
								var m_w: Dictionary = crews_g.get("men")[id_w]
								if String(m_w["kind"]).begins_with("sea_drowned"):
									undead_w += 1
									if is_instance_valid(m_w["enemy"]) and (m_w["enemy"] as Node).get_parent() == mine_g:
										aboard_w += 1
							if (words[1] == "wait_solid" and phase_w >= 0.95) or (words[1] == "wait_faded" and phase_w >= 0.0 and phase_w <= 0.05) or (words[1] == "wait_gone" and g_now == null) \
								or (words[1] == "wait_grab" and (int(enc_g.get("drowned").get("holds")) > 0 or bool(enc_g.get("drowned").call("held_here")))) or (words[1] == "wait_aboard" and aboard_w > 0) \
								or (words[1] == "wait_risen" and undead_w >= (int(words[2]) if words.size() > 2 else 1)):
								break
							await get_tree().create_timer(0.25, true, false, true).timeout
				var undead_s := 0
				var aboard_s := 0
				for id_s: int in crews_g.get("men"):
					var m_s: Dictionary = crews_g.get("men")[id_s]
					if String(m_s["kind"]).begins_with("sea_drowned"):
						undead_s += 1
						if is_instance_valid(m_s["enemy"]) and (m_s["enemy"] as Node).get_parent() == mine_g:
							aboard_s += 1
				_lines.append("SPOOK %s: %s; %s; drowned now %d (on our deck %d); %s; cannons fired %d hits %d through %d; player hp %.0f swimming %s, night %s; our hull %.0f" % [" ".join(words.slice(1)), String(enc_g.get("ghosts").call("status")), String(enc_g.get("drowned").call("status")), undead_s, aboard_s, String(crews_g.call("status")), int(fleet_g.get("cannons").get("fired")), int(fleet_g.get("cannons").get("hits")), int(fleet_g.get("cannons").get("passed")), float(player.get("health").hp), str(player.get("swimming")), str(enc_g.call("_night")), float(mine_g.get("state")["hull"])])
		"foe":  # sea step 8: !foe spawn <kind> [metres ahead] [degrees off the bow] | roll (a check with chance 1, out of the safe waters) | pause on|off | hit <n> | sink | spill | collect | wait_volley | status <note>
			# 8b crews: alongside [m] | board | aboard | crew | kill boarders|deck|all [n] | wait_crew | wait_board | wait_fallen <n> | wait_deck | takedeck
			var sea_f: Node = session.call("sea")
			var fleet_f: Node = sea_f.get("ships") if sea_f != null else null
			if fleet_f == null:
				_lines.append("foe: no sea")
			else:
				var enc: Node = fleet_f.get("foes")
				var mine: Node = (fleet_f.get("ships") as Array)[clampi(_ship_i, 0, (fleet_f.get("ships") as Array).size() - 1)]
				var ms: Dictionary = mine.get("state")
				var list_f: Array = enc.call("foes")
				match words[1] if words.size() > 1 else "status":
					"spawn":
						var far_f := float(words[3]) if words.size() > 3 else 160.0
						var off_f := deg_to_rad(float(words[4]) if words.size() > 4 else 0.0)
						var a_f := float(ms["yaw"]) + off_f
						var fx := float(ms["x"]) - sin(a_f) * far_f
						var fz := float(ms["z"]) - cos(a_f) * far_f
						enc.call("spawn_foe", words[2], fx, fz, rad_to_deg(atan2(-(float(ms["x"]) - fx), -(float(ms["z"]) - fz))))
					"roll":
						var keep_c := float(enc.get("rules").get("cfg")["base_chance"])
						enc.get("rules").get("cfg")["base_chance"] = 1.0
						enc.call("_roll")
						enc.get("rules").get("cfg")["base_chance"] = keep_c
					"pause":
						enc.set("paused", words.size() < 3 or words[2] != "off")
					"hit":  # a blow to the first foe's waist
						if not list_f.is_empty():
							fleet_f.get("hull_part").call("damage", list_f[0], Vector3(0.0, 0.0, 0.0), float(words[2]))
					"sink":
						if not list_f.is_empty():
							fleet_f.get("hull_part").call("damage", list_f[0], Vector3(0.0, 0.0, 0.0), 99999.0)
					"spill":  # cargo afloat 25 m ahead of the ship in use
						enc.get("flotsam").call("spill", float(ms["x"]) - sin(float(ms["yaw"])) * 25.0, float(ms["z"]) - cos(float(ms["yaw"])) * 25.0, "pirate_big", "region_2")
					"collect":  # the ship in use put on each floating piece in turn (as if sailed through it)
						for id_c: int in (enc.get("flotsam").get("pieces") as Dictionary).keys():
							if not (enc.get("flotsam").get("pieces") as Dictionary).has(id_c):
								continue
							var pc: Dictionary = enc.get("flotsam").get("pieces")[id_c]
							ms["x"] = float(pc["x"])
							ms["z"] = float(pc["z"])
							await get_tree().create_timer(0.6).timeout
					"wait_seen", "wait_flotsam":  # up to 90 s until a foe ship / floating cargo is here (online: the host's word)
						var until_s := Time.get_ticks_msec() + 90000
						while Time.get_ticks_msec() < until_s:
							if words[1] == "wait_seen" and not (enc.call("foes") as Array).is_empty():
								break
							if words[1] == "wait_flotsam" and not (enc.get("flotsam").get("pieces") as Dictionary).is_empty():
								break
							await get_tree().create_timer(0.5).timeout
					"swimto":  # swim to each floating piece in turn
						for id_w: int in (enc.get("flotsam").get("pieces") as Dictionary).keys():
							if not (enc.get("flotsam").get("pieces") as Dictionary).has(id_w):
								continue
							var node_w: Node3D = enc.get("flotsam").get("pieces")[id_w]["node"]
							player.call("teleport", node_w.global_position + Vector3(0.8, -0.6, 0.0), 0.0)
							await get_tree().create_timer(1.6).timeout
					"alongside":  # the newest foe laid abeam of our ship to starboard, same heading, that far (default 13 m)
						if not list_f.is_empty():
							var fs_a: Dictionary = list_f.back().get("state")
							var gap_a := float(words[2]) if words.size() > 2 else 13.0
							fs_a["yaw"] = float(ms["yaw"])
							fs_a["x"] = float(ms["x"]) + cos(float(ms["yaw"])) * gap_a
							fs_a["z"] = float(ms["z"]) - sin(float(ms["yaw"])) * gap_a
							fs_a["speed"] = float(ms["speed"])
					"board":  # the newest foe's boarders swing across to our ship now
						if not list_f.is_empty():
							enc.get("crews").call("board", list_f.back(), mine)
					"aboard":  # stand on the newest foe's deck, by her stern
						if not list_f.is_empty():
							var outline_a: Array = list_f.back().get("spec")["outline"]
							player.call("teleport", list_f.back().call("deck_spot", [0.0, float(outline_a[0][0]) - 2.0], 0.4), 0.0)
					"crew":  # every crewman: kind, ship index, ship-space spot, health, target
						var crews_c: Node = enc.get("crews")
						for id_m: int in crews_c.get("men"):
							var e_m: Node3D = crews_c.get("men")[id_m]["enemy"]
							if is_instance_valid(e_m):
								var t_m: Variant = e_m.get("_target")
								_lines.append("  crew %d %s on ship %d (swim %s) at %s hp %.0f/%.0f target %s puppet %s" % [id_m, String(crews_c.get("men")[id_m]["kind"]), (fleet_f.get("ships") as Array).find(e_m.get_parent()), str((crews_c.get("men")[id_m] as Dictionary).has("swim")), str(e_m.position.snapped(Vector3(0.1, 0.1, 0.1))), float(e_m.get("health").hp), float(e_m.get("health").max_hp), String((t_m as Node).name) if is_instance_valid(t_m) else "-", str(e_m.get("puppet"))])
					"kill":  # "!foe kill boarders|deck|all [n]": our blows on crewmen (online a client's go to the host)
						var crews_k: Node = enc.get("crews")
						var left_k := int(words[3]) if words.size() > 3 else 99
						for id_k: int in (crews_k.get("men") as Dictionary).keys():
							if left_k <= 0 or not (crews_k.get("men") as Dictionary).has(id_k):
								continue
							var e_k: Node3D = crews_k.get("men")[id_k]["enemy"]
							var on_k: Node = e_k.get_parent() if is_instance_valid(e_k) else null
							var which := words[2] if words.size() > 2 else "all"
							if on_k == null or (which == "boarders" and on_k != mine) or (which == "deck" and (list_f.is_empty() or on_k != list_f.back())):
								continue
							session.get("_score").set("blow", "gun")
							e_k.call("on_hit", 99999.0, e_k.global_position + Vector3(0.0, 1.2, 0.0))
							left_k -= 1
							await get_tree().create_timer(0.3).timeout
					"wait_crew", "wait_board", "wait_deck":  # up to 90 s until crewmen are here / one stands on our ship / a deck chest is here
						var until_c := Time.get_ticks_msec() + 90000
						var crews_w: Node = enc.get("crews")
						while Time.get_ticks_msec() < until_c:
							if words[1] == "wait_crew" and not (crews_w.get("men") as Dictionary).is_empty():
								break
							if words[1] == "wait_board" and (crews_w.get("men") as Dictionary).values().any(func(m: Dictionary) -> bool: return is_instance_valid(m["enemy"]) and (m["enemy"] as Node).get_parent() == mine):
								break
							if words[1] == "wait_deck" and (enc.get("flotsam").get("pieces") as Dictionary).values().any(func(p: Dictionary) -> bool: return p.has("ship")):
								break
							await get_tree().create_timer(0.5).timeout
					"look":  # face the newest foe (her masthead: "!foe look low" = her deck)
						if not list_f.is_empty():
							player.call("look_at_point", list_f.back().call("deck_spot", [0.0, 0.0], 1.0 if words.size() > 2 and words[2] == "low" else 9.0))
					"overboard":  # "!foe overboard [n]": n of the newest foe's deck crew thrown into the sea (host)
						var crews_o: Node = enc.get("crews")
						var left_o := int(words[2]) if words.size() > 2 else 1
						for id_o: int in (crews_o.get("men") as Dictionary).keys():
							var e_o: Node3D = crews_o.get("men")[id_o]["enemy"]
							if left_o > 0 and is_instance_valid(e_o) and not list_f.is_empty() and e_o.get_parent() == list_f.back():
								e_o.position.x = signf(e_o.position.x + 0.01) * 12.0  # well off her side
								crews_o.call("_overboard", e_o, "dev")
								left_o -= 1
					"wait_swim":  # up to 60 s until a crewman is in the water here (online: the host's word)
						var until_sw := Time.get_ticks_msec() + 60000
						var crews_sw: Node = enc.get("crews")
						while Time.get_ticks_msec() < until_sw and not (crews_sw.get("men") as Dictionary).values().any(func(m: Dictionary) -> bool: return m.has("swim")):
							await get_tree().create_timer(0.2).timeout
					"wait_climb", "wait_shots":  # up to 90 s until a swimmer climbed aboard / a musket has fired
						var until_o := Time.get_ticks_msec() + 90000
						var crews_wc: Node = enc.get("crews")
						while Time.get_ticks_msec() < until_o and int(crews_wc.get("climbed" if words[1] == "wait_climb" else "shots")) == 0:
							await get_tree().create_timer(0.5).timeout
					"wait_fallen":  # up to 60 s until n crewmen have fallen here
						var until_f := Time.get_ticks_msec() + 60000
						while Time.get_ticks_msec() < until_f and int(enc.get("crews").get("fallen")) < int(words[2]):
							await get_tree().create_timer(0.5).timeout
					"takedeck":  # walk up to each deck chest in turn
						for id_d: int in (enc.get("flotsam").get("pieces") as Dictionary).keys():
							var pd: Dictionary = enc.get("flotsam").get("pieces").get(id_d, {})
							if pd.has("ship"):
								player.call("teleport", (pd["node"] as Node3D).global_position + Vector3(0.0, 0.4, 0.0), 0.0)
								await get_tree().create_timer(1.6).timeout
					"wait_volley":  # up to 60 s until a foe has fired
						var until_v := Time.get_ticks_msec() + 60000
						while Time.get_ticks_msec() < until_v and int(enc.get("volleys")) == 0:
							await get_tree().create_timer(0.5).timeout
				_lines.append("FOE %s: %s; our ship %s hull %.0f/%.0f, doubloons %d" % [" ".join(words.slice(1)), String(enc.call("status")), String(ms["ship"]), float(ms["hull"]), float(ms["hull_max"]), int(session.call("doubloons").get("balance"))])
		"ship":  # sea ships (step 5a): !ship status | hit <n> <zone> | hull | patch <zone|off> | wait_hole | board | helm | letgo | anchor up|down | stage <n> | rudder <-1..1|off> | wind <degrees off> | head <compass degrees>
			var sea_now: Node = session.call("sea")
			var fleet: Node = sea_now.get("ships") if sea_now != null else null
			if fleet == null or (fleet.get("ships") as Array).is_empty():
				_lines.append("ship: no sea / no ships (use /tp sea first)")
			else:
				var first: Node = (fleet.get("ships") as Array)[clampi(_ship_i, 0, (fleet.get("ships") as Array).size() - 1)]
				var arg := words[2] if words.size() > 2 else ""
				match words[1] if words.size() > 1 else "status":
					"tospot":  # "!ship tospot 0": the ship anchored beside salvage spot n (her crane side towards it)
						var spot_node: Node3D = (sea_now.get("salvage").get("_spots") as Array)[clampi(int(arg), 0, (sea_now.get("salvage").get("_spots") as Array).size() - 1)]["node"]
						var at_sea: Vector3 = sea_now.call("local_of", spot_node.global_position)
						var st_t: Dictionary = first.get("state")
						st_t["x"] = at_sea.x - cos(float(st_t["yaw"])) * 6.0
						st_t["z"] = at_sea.z + sin(float(st_t["yaw"])) * 6.0
						st_t["speed"] = 0.0
						st_t["anchored"] = true
					"fresh":  # "!ship fresh <x> <z>": (sea step 8f tests) the ship anchored there, sound: full hull, no holes, dry
						var st_f: Dictionary = first.get("state")
						st_f["x"] = float(arg) if arg != "" else float(st_f["x"])
						st_f["z"] = float(words[3]) if words.size() > 3 else float(st_f["z"])
						st_f["speed"] = 0.0
						st_f["anchored"] = true
						st_f["hull"] = float(st_f["hull_max"])
						st_f["leaks"] = [0.0, 0.0, 0.0]
						st_f["water"] = 0.0
						st_f["sinking"] = false
					"sinktime":  # "!ship sinktime <cap s> <note>": how long until she goes down (no repairs), up to cap
						var began_s := Time.get_ticks_msec()
						var cap_s := float(arg) if arg != "" else 150.0
						var st_s: Dictionary = first.get("state")
						while Time.get_ticks_msec() - began_s < int(cap_s * 1000.0) and not bool(st_s.get("sinking", false)):
							await get_tree().create_timer(0.25, true, false, true).timeout
						_lines.append("SINKTIME %s: %s after %.1f s; hull %.0f / %.0f, leaks %s, water %.2f" % [" ".join(words.slice(3)), "SANK" if bool(st_s.get("sinking", false)) else "afloat", (Time.get_ticks_msec() - began_s) / 1000.0, float(st_s["hull"]), float(st_s["hull_max"]), str(st_s["leaks"]), float(st_s["water"])])
					"hit":  # "!ship hit 120 bow|waist|stern": a blow to the hull at that leak zone (host / alone)
						var zone_i := maxi(0, ["bow", "waist", "stern"].find(words[3] if words.size() > 3 else "waist"))
						var spot: Array = load("res://core/sea/hull_rules.gd").zones(first.get("spec"))[zone_i]
						fleet.get("hull_part").call("damage", first, Vector3(float(spot[0]), 0.0, float(spot[1])), float(arg))
					"hull":  # "!ship hull <note>": the hull, holes, water, sinking of the ship
						var st: Dictionary = first.get("state")
						_lines.append("HULL %s: %s hull %.0f / %.0f, leaks %s, water %.2f, sinking %s, anchored %s, at (%.0f, %.0f), prompt '%s'" % [" ".join(words.slice(2)), String(st["ship"]), float(st["hull"]), float(st["hull_max"]), str(st["leaks"]), float(st["water"]), str(st.get("sinking", false)), str(st["anchored"]), float(st["x"]), float(st["z"]), String(fleet.call("prompt", "F"))])
					"patch":  # "!ship patch bow|waist|stern": stand at that leak zone and hold interact (off: "!ship patch off")
						if arg == "off" or arg == "":
							fleet.set("dev_patch", false)
						else:
							var zone_p := maxi(0, ["bow", "waist", "stern"].find(arg))
							var spot_p: Array = load("res://core/sea/hull_rules.gd").zones(first.get("spec"))[zone_p]
							player.call("teleport", first.call("deck_spot", [float(spot_p[0]) * 0.8, float(spot_p[1])], 0.3), 0.0)
							fleet.set("dev_patch", true)
					"wait_hole", "wait_sink":  # "!ship wait_hole" / "wait_sink": wait (up to 60 s) for a hole / for her to go down (online: the host's word)
						var began_h := Time.get_ticks_msec()
						while Time.get_ticks_msec() - began_h < 60000:
							var st_w: Dictionary = first.get("state")
							if (words[1] == "wait_hole" and float(load("res://core/sea/hull_rules.gd").new({}).holes(st_w)) > 0.0) or (words[1] == "wait_sink" and bool(st_w.get("sinking", false))):
								break
							await get_tree().create_timer(0.5, true, false, true).timeout
					"lookzone":  # "!ship lookzone bow": face that leak zone of the ship
						var spot_l: Array = load("res://core/sea/hull_rules.gd").zones(first.get("spec"))[maxi(0, ["bow", "waist", "stern"].find(arg))]
						player.call("look_at_point", first.call("deck_spot", [float(spot_l[0]) * 0.8, float(spot_l[1])], 0.6))
					"board":
						player.call("teleport", first.call("deck_spot", [0.0, 1.5], 0.3), 0.0)
					"helm":  # stand at the wheel and take it (online: wait for the host's yes, up to 10 s)
						player.call("teleport", first.call("deck_spot", [float(first.get("spec")["helm"][0]), float(first.get("spec")["helm"][1]) + 1.0], 0.3), 0.0)
						await get_tree().create_timer(1.5, true, false, true).timeout
						fleet.call("take_helm", first)
						var asked := Time.get_ticks_msec()
						while fleet.get("helm_ship") == null and Time.get_ticks_msec() - asked < 10000:
							await get_tree().create_timer(0.25, true, false, true).timeout
						_lines.append("helm: %s" % str(fleet.get("helm_ship") != null))
					"wait_helmsman", "wait_free":  # waits (up to 60 s) until somebody steers the first ship / nobody does
						var began := Time.get_ticks_msec()
						while (int(fleet.call("helmsman_of", first)) != 0) != (words[1] == "wait_helmsman") and Time.get_ticks_msec() - began < 60000:
							await get_tree().create_timer(0.25, true, false, true).timeout
						_lines.append("%s: helmsman %d after %.1f s" % [words[1], int(fleet.call("helmsman_of", first)), (Time.get_ticks_msec() - began) / 1000.0])
					"letgo":
						fleet.call("let_go")
					"anchor":
						if bool(first.get("state")["anchored"]) != (arg == "down"):
							fleet.call("toggle_anchor", first)
					"stage":
						first.get("state")["stage"] = int(arg)
						fleet.set("wanted_stage", int(arg))
					"spawn":  # "!ship spawn brig 0 40": a new ship of that kind that far from the first ship (sea metres x z)
						var fs: Dictionary = first.get("state")
						fleet.call("spawn", arg, float(fs["x"]) + (float(words[3]) if words.size() > 3 else 0.0), float(fs["z"]) + (float(words[4]) if words.size() > 4 else 30.0), rad_to_deg(float(fs["yaw"])))
					"rig":  # "!ship rig 0": stand at rigging spot n of the ship
						var rig_at: Array = first.get("spec")["rigging"][int(arg) if arg != "" else 0]
						player.call("teleport", first.call("deck_spot", [float(rig_at[0]) * 0.92, float(rig_at[1])], 0.3), 0.0)
					"crew":  # what the ship's speed gets from the crew at the rigging now
						_lines.append("crew at rigging %d, working %s, speed share %.3f" % [int(fleet.call("_crew_at_rigging", first)), str(fleet.get("working")), float(fleet.call("_speed_pct", first))])
					"use":  # "!ship use 2": the !ship steps after this act on ship n of the fleet (0 = the first; "last" = the newest)
						_ship_i = (fleet.get("ships") as Array).size() - 1 if arg == "last" else int(arg)
					"rail":  # stand at the starboard rail, midships
						player.call("teleport", first.call("deck_spot", [float(first.get("spec")["outline"][3][1]) - 0.6, 0.0], 0.3), 0.0)
					"ghosts":  # online: where the other players stand on this machine (deck, swimming) and the fleet's packets
						_lines.append(String(session.get("net").call("ghost_note")) + " | net_sea sent %d heard %d" % [int(session.get("net").get("sea").get("sent")), int(session.get("net").get("sea").get("heard"))])
					"rudder":
						fleet.set("dev_rudder", NAN if arg == "off" else float(arg))
					"wind":
						fleet.call("dev_face_wind", first, float(arg))
					"head":  # compass heading: 0 north, 90 east
						first.get("state")["yaw"] = -deg_to_rad(float(arg))
					_:
						_lines.append(String(fleet.call("status")))
		"port":  # sea step 6: !port go | open | close | tab <n> | press <button text> | money <chips> <doubloons> | status <note>
			var sea_p: Node = session.call("sea")
			var port_p: Node = sea_p.get("port") if sea_p != null else null
			var sub_p := words[1] if words.size() > 1 else "status"
			if port_p == null:
				_lines.append("port: no sea")
			elif sub_p == "go":
				var home: Dictionary = port_p.get("rules").call("port", "home")
				player.call("teleport", sea_p.call("world_of", Vector3(float(home["dock"][0]), 30.0, float(home["dock"][1]))), 0.0)
			elif sub_p == "open":
				_lines.append("PORT open: here '%s', prompt '%s'" % [String(port_p.call("port_here")), String(port_p.call("prompt", "F"))])
				port_p.call("open", "home")
			elif sub_p == "close":
				port_p.call("close")
			elif sub_p == "tab":
				port_p.get("window").set("tab", int(words[2]))
				port_p.get("window").queue_redraw()
				await get_tree().process_frame
				await get_tree().process_frame
			elif sub_p == "press":
				var label := " ".join(words.slice(2))
				var ok_p: bool = port_p.get("window").call("press", label)
				_lines.append("PORT press '%s': %s -> '%s'" % [label, str(ok_p), String(port_p.get("window").get("said"))])
				await get_tree().process_frame
			elif sub_p == "money":
				session.call("wallet").set("balance", int(words[2]))
				session.call("doubloons").set("balance", int(words[3]))
			else:
				var inv_p: RefCounted = player.get("inventory")
				var guns_p := 0
				for slot_p in int(inv_p.get("slot_count")):
					if not (inv_p.call("gun_at", slot_p) as Dictionary).is_empty():
						guns_p += 1
				_lines.append("PORT %s: chips %d, doubloons %d, guns in the backpack %d, sellable %d, oak planks %d, crane on %d ships" % [" ".join(words.slice(2)), int(session.call("wallet").get("balance")), int(session.call("doubloons").get("balance")), guns_p, (port_p.call("sellable") as Array).size(), int(sea_p.get("skills").get("bag").call("count", "oak_plank")), (sea_p.get("ships").get("crane").get("_cranes") as Dictionary).size()])
		"town":  # sea step 7: !town use <plot> <kind> | store put|take <item> [all] | door <plot> | effects | view | grow <0..1> | go <plot> | ledger | look <plot> [mark] | open <plot> [ledger] | close | choose <plot> | press <key> | set <plot> <level> | stock (materials + doubloons) | wait_level <plot> <level> | status <note>
			var sea_t: Node = session.call("sea")
			var town_t: Node = sea_t.get("town") if sea_t != null else null
			var sub_t := words[1] if words.size() > 1 else "status"
			if town_t == null:
				_lines.append("town: no sea")
			elif sub_t in ["go", "ledger", "look"]:
				var id_t := words[2] if words.size() > 2 and sub_t != "ledger" else "harbour_master"
				var at_t: Node3D = town_t.call("marker", id_t, "Ledger") if sub_t == "ledger" else (town_t.get("_plots")[id_t]["sign"] if (town_t.get("_plots") as Dictionary).has(id_t) else null)
				if sub_t == "look":
					var holder_t: Node3D = town_t.get("_plots")[id_t]["holder"]
					var front_t: Vector3 = holder_t.global_basis * Vector3(0, 0, -1)
					var far_t := float(words[3]) if words.size() > 3 else 26.0
					player.call("teleport", holder_t.global_position + front_t * far_t + holder_t.global_basis * Vector3(far_t * 0.35, 0, 0) + Vector3(0, 3.0, 0), 0.0)
					await get_tree().create_timer(0.3).timeout
					player.call("look_at_point", holder_t.global_position + Vector3(0, 4.0, 0))
				elif at_t != null:
					var out_t: Vector3 = at_t.global_position + (at_t.global_basis * Vector3(0, 0, -1.6) if sub_t == "go" else Vector3.ZERO)
					player.call("teleport", out_t + Vector3(0, 1.0, 0), 0.0)
					await get_tree().create_timer(0.4).timeout
					_lines.append("TOWN at %s: prompt '%s', port '%s'" % [id_t if sub_t != "ledger" else "ledger", String(sea_t.call("prompt", "F")), String(sea_t.get("port").call("prompt", "F"))])
				else:
					_lines.append("TOWN %s: no such place yet (built %s)" % [id_t, str(town_t.get("built"))])
			elif sub_t == "counter":
				var c_t: Node3D = town_t.call("marker", "harbour_master", "Counter")
				if c_t != null:
					player.call("teleport", c_t.global_position + Vector3(0, 1.0, 0), 0.0)
					await get_tree().create_timer(0.4).timeout
				_lines.append("TOWN counter: port prompt '%s'" % String(sea_t.get("port").call("prompt", "F")))
			elif sub_t == "open":
				town_t.call("open", words[2] if words.size() > 2 else "harbour_master", words.size() > 3)
			elif sub_t in ["close", "close_store"]:
				town_t.call("close")
				town_t.call("close_store")
			elif sub_t == "choose":
				town_t.get("window").set("chosen", words[2])
				town_t.get("window").queue_redraw()
				await get_tree().process_frame
			elif sub_t == "press":
				town_t.get("window").queue_redraw()
				await get_tree().process_frame
				await get_tree().process_frame
				var ok_t: bool = town_t.get("window").call("press", " ".join(words.slice(2)))
				await get_tree().process_frame
				_lines.append("TOWN press '%s': %s -> '%s'" % [" ".join(words.slice(2)), str(ok_t), String(town_t.get("said"))])
			elif sub_t == "set":
				town_t.get("rules").get("levels")[words[2]] = int(words[3])
			elif sub_t == "use":  # !town use <plot> <service kind>
				_lines.append("TOWN use %s %s: %s" % [words[2], words[3], String(town_t.call("use", words[2], words[3]))])
				await get_tree().process_frame
			elif sub_t == "store":  # !town store put|take <item> [all]
				_lines.append("TOWN store %s: %s; chest %s, bag %s %d" % [" ".join(words.slice(2)), str(town_t.get("store_window").call("press", " ".join(words.slice(2)))) + " " + String(town_t.get("store_window").get("said")), str((town_t.call("chest") as RefCounted).call("to_list")), words[3], int(sea_t.get("skills").get("bag").call("count", words[3]))])
			elif sub_t == "door":  # stand at a building's door
				var door_t: Node3D = town_t.call("marker", words[2], "Door")
				if door_t != null:
					player.call("teleport", door_t.global_position + Vector3(0, 1.0, 0), 0.0)
					await get_tree().create_timer(0.4).timeout
				_lines.append("TOWN door %s: prompt '%s'" % [words[2], String(sea_t.call("prompt", "F"))])
			elif sub_t == "panel":  # what the fantasy window shows (a station opened in town), then shut it
				var sk_t: Node = sea_t.get("skills")
				var pn_t: Node = sk_t.get("panel")
				var gal: Dictionary = {}
				for rc: Dictionary in sk_t.get("skilling")["recipes"]:
					if String(rc["id"]) == "build_galleon":
						gal = rc
				_lines.append("TOWN panel: open %s station %s, recipes there %d, galleon '%s' cost %s, finer %.2f" % [str(pn_t.visible), String(pn_t.get("station")), (sk_t.get("work").call("recipes", String(pn_t.get("station"))) as Array).size(), String(sk_t.get("work").call("cannot_make", gal)), str(sk_t.get("work").call("cost_of", gal)), float(sk_t.get("town_finer"))])
				if words.size() > 2:
					sk_t.call("close_panel")
			elif sub_t == "people":
				var pc: Vector2i = town_t.get("people").call("counts")
				_lines.append("TOWN people: residents %d, townsfolk %d, moored %d, boons speed %.0f damage %.0f regen %.3f, card place %s, tcg near %s, beacon %s" % [pc.x, pc.y, (town_t.call("moored") as Array).size(), float(player.call("boon", "speed_pct")), float(player.call("boon", "damage_pct")), float(player.call("boon", "regen_pct")), str(not (town_t.get("_cards") as Dictionary).is_empty()), str(session.get("_tcg").call("spot_near", player.global_position)), str(town_t.get("_beacon") != null and (town_t.get("_beacon") as Node3D).visible)])
			elif sub_t == "talk":  # stand by a building's resident
				var rn: Variant = (town_t.get("people").get("_residents") as Dictionary).get(words[2])
				if rn != null:
					var body_r: Node3D = rn["node"]
					player.call("teleport", body_r.global_position + body_r.global_basis * Vector3(0, 1.0, -1.6), 0.0)
					await get_tree().create_timer(0.4).timeout
				_lines.append("TOWN talk %s: prompt '%s'" % [words[2], String(sea_t.call("prompt", "F"))])
			elif sub_t == "cards":  # stand at the tavern's card table
				var ct: Dictionary = town_t.get("_cards")
				if not ct.is_empty():
					player.call("teleport", (ct["card_table"] as Node3D).global_position + Vector3(0, 1.0, 1.4), 0.0)
					await get_tree().create_timer(0.4).timeout
					player.call("look_at_point", (ct["card_table"] as Node3D).global_position)
				_lines.append("TOWN cards: tcg near %s, prompt '%s'" % [str(session.get("_tcg").call("spot_near", player.global_position)), String(session.call("_prompt"))])
			elif sub_t == "moor":  # anchor ship n (default 0) at berth k
				var fl: Node = sea_t.get("ships")
				var sh: Node = (fl.get("ships") as Array)[int(words[3]) if words.size() > 3 else 0]
				var b: Array = (town_t.get("rules").get("cfg")["berths"] as Array)[int(words[2])]
				var st_m: Dictionary = sh.get("state")
				st_m["x"] = float(b[0])
				st_m["z"] = float(b[1])
				st_m["anchored"] = true
				st_m["hull"] = float(st_m["hull"]) * 0.5
				_lines.append("TOWN moor: ship hull %.0f" % float(st_m["hull"]))
			elif sub_t == "hull":
				var st_h: Dictionary = ((sea_t.get("ships").get("ships") as Array)[0] as Node).get("state")
				_lines.append("TOWN hull %s: %.0f" % [" ".join(words.slice(2)), float(st_h["hull"])])
			elif sub_t == "effects":
				var r_e: RefCounted = town_t.get("rules")
				_lines.append("TOWN effects: sell x%.2f, build share %.2f, mend x%.2f, finer %.2f, chest %d slots shared %d, rest %.2f; shop has %d goods; galleon lock '%s'" % [float(r_e.call("effect", "harbour_master", "sell_mult", 1.0)), float(r_e.call("effect", "shipyard", "build_share", 1.0)), float(r_e.call("effect", "shipyard", "mend_mult", 1.0)), float(r_e.call("effect", "workshop", "finer", 0.0)), int(r_e.call("effect", "storage", "slots", 0)), int(r_e.call("effect", "storage", "shared", 0)), float(r_e.call("effect", "garden", "rest_heal", 0.0)), (sea_t.get("port").call("stock") as Array).size(), String(r_e.call("recipe_lock", {"town": {"plot": "shipyard", "level": 4}}))])
			elif sub_t == "grow":  # every plot to this share of its top level
				var rules_t: RefCounted = town_t.get("rules")
				for id_g: String in rules_t.call("ids"):
					rules_t.get("levels")[id_g] = roundi(float(words[2]) * float(rules_t.call("top", id_g)))
			elif sub_t == "view":  # from the trophy hall's plot, up the hill, looking down the town to the harbour
				var th_t: Node3D = town_t.get("_plots")["trophy_hall"]["holder"]
				player.call("teleport", th_t.global_position + Vector3(-6.0, 4.0, -22.0), 0.0)
				await get_tree().create_timer(0.4).timeout
				player.call("look_at_point", th_t.global_position + Vector3(120.0, -6.0, 10.0))
			elif sub_t == "hall":  # !town hall: what the trophy hall holds; !town hall in: stand inside the door, looking in
				var hall_t: Node = town_t.get("hall")
				if words.size() > 2 and words[2] == "in":
					var hd_t: Node3D = town_t.call("marker", "trophy_hall", "Door")
					var hh_t: Node3D = town_t.get("_plots")["trophy_hall"]["holder"]
					var in_t: Vector3 = hh_t.global_position.lerp(hd_t.global_position, 0.3)
					player.call("teleport", Vector3(in_t.x, hd_t.global_position.y + 1.5, in_t.z), 0.0)
					await get_tree().create_timer(0.6).timeout
					player.call("look_at_point", hh_t.global_position + Vector3(0, 1.2, 0) - (hd_t.global_position - hh_t.global_position) * 0.6)
					await get_tree().create_timer(0.4).timeout
				var room_t: Variant = hall_t.get("room")
				_lines.append("TOWN hall: level %d, cabinets %d, cases %d filled %s, plinths %d, legend %s, lamps %d lit %s, prompt '%s', card '%s'" % [int(town_t.get("rules").call("level", "trophy_hall")), (room_t.get("_cabinets") as Array).size() if room_t != null else 0, (hall_t.get("_case_spots") as Array).size(), str(hall_t.get("cases")), (hall_t.get("_plinths") as Array).size(), str(hall_t.get("_legend") != null), (hall_t.get("_lamps") as Array).size(), str(not (hall_t.get("_lamps") as Array).is_empty() and (hall_t.get("_lamps")[0] as Node3D).visible), String(sea_t.call("prompt", "F")), String((town_t.get("card_hud").get("trophy") as Dictionary).get("title", ""))])
			elif sub_t == "case":  # !town case <collection>: given its trophy, stand at its case, put it in
				sea_t.get("skills").call("give", "trophy_" + words[2], 1)
				for spot_c: Array in town_t.get("hall").get("_case_spots"):
					if String(spot_c[0]) == words[2]:
						var jar_c: Node3D = spot_c[1]
						var side_c := jar_c.get_parent_node_3d().global_basis * Vector3(0, 0, signf(jar_c.position.z) * 1.0)  # stand on that row's side of the table
						player.call("teleport", jar_c.global_position + Vector3(0, 1.0, 0.0) + side_c.normalized() * 0.95, 0.0)
						await get_tree().create_timer(0.4).timeout
				var pr_c := String(sea_t.call("prompt", "F"))
				var ok_c: bool = sea_t.call("interact")
				_lines.append("TOWN case %s: prompt '%s', interact %s, cases %s, trophy left %d" % [words[2], pr_c, str(ok_c), str(town_t.get("hall").get("cases")), int(sea_t.get("skills").get("bag").call("count", "trophy_" + words[2]))])
			elif sub_t == "plinth":  # !town plinth <region n> [give]: stand before that boss plinth, looking at it, and set its trophy (give = put the trophy in the bag first)
				var hall_p: Node = town_t.get("hall")
				var tro_p := String(hall_p.call("plinth_trophy", int(words[2])))
				if words.size() > 3 and tro_p != "":
					sea_t.get("skills").call("give", tro_p, 1)
				for spot_p: Array in hall_p.get("_plinths"):
					if int(spot_p[0]) == int(words[2]):
						var pl_p: Node3D = spot_p[1]
						player.call("teleport", pl_p.global_position + pl_p.global_basis.z.normalized() * 1.0 + Vector3(0, 1.0, 0), 0.0)
						await get_tree().create_timer(0.4).timeout
						player.call("look_at_point", pl_p.global_position + Vector3(0, 1.3, 0))
				await get_tree().create_timer(1.0, true, false, true).timeout
				var spot_p: Array = town_t.call("spot_here")
				var near_p := int(hall_p.call("plinth_near", player.global_position, player.call("view_forward")))
				_lines.append("  plinth spot %s, near %d, window %s, climbing %s, town prompt '%s', dungeon prompt '%s'" % [str(spot_p), near_p, str((town_t.get("window") as CanvasItem).visible), str(sea_t.get("swim").call("climbing")), String(town_t.call("prompt", "F")), String(sea_t.get("dungeons").call("prompt", "F"))])
				var pr_p := String(sea_t.call("prompt", "F"))
				var ok_p: bool = sea_t.call("interact")
				await get_tree().create_timer(0.4).timeout
				_lines.append("TOWN plinth %s: prompt '%s', interact %s, plinths %s, trophy left %d, card '%s'" % [words[2], pr_p, str(ok_p), str(hall_p.get("plinths")), int(sea_t.get("skills").get("bag").call("count", tro_p)) if tro_p != "" else -1, String((town_t.get("card_hud").get("trophy") as Dictionary).get("title", ""))])
			elif sub_t == "gallery":  # !town gallery [slot]: stand before painting slot n, looking at it
				var gal_t: Node = town_t.get("gallery")
				var frames_t: Array = gal_t.get("_frames")
				var k_t := int(words[2]) if words.size() > 2 else 0
				if k_t < frames_t.size():
					var fr_t: Node3D = frames_t[k_t][1]
					player.call("teleport", fr_t.global_position + fr_t.global_basis.z.normalized() * 2.0 - Vector3(0, 1.2, 0), 0.0)
					await get_tree().create_timer(0.5).timeout
					player.call("look_at_point", fr_t.global_position)
					await get_tree().create_timer(0.3).timeout
				_lines.append("TOWN gallery: level %d, frames %d, bought %s, prompt '%s', doubloons %d" % [int(town_t.get("rules").call("level", "gallery")), frames_t.size(), str(gal_t.get("bought")), String(sea_t.call("prompt", "F")), int(session.call("doubloons").get("balance"))])
			elif sub_t == "hide":  # !town hide plots|houses|people|hall_room <on|off>: what costs what in a view (measuring)
				var on_h := words.size() < 4 or words[3] != "off"
				match words[2]:
					"plots":
						for id_h: String in town_t.get("_plots"):
							(town_t.get("_plots")[id_h]["holder"] as Node3D).visible = not on_h
					"houses":
						for e_h: Dictionary in town_t.get("_houses"):
							(e_h["holder"] as Node3D).visible = not on_h
					"people":
						(town_t.get("people") as Node3D).visible = not on_h
					"island":
						for n_h in sea_t.find_children("*isle_start*", "", true, false):
							(n_h as Node3D).visible = not on_h
					_:  # one plot by its id
						if (town_t.get("_plots") as Dictionary).has(words[2]):
							(town_t.get("_plots")[words[2]]["holder"] as Node3D).visible = not on_h
			elif sub_t == "tris":  # !town tris <plot>: the heaviest drawn pieces under that plot (measuring)
				var rows_t: Array = []
				for n_t in (town_t.get("_plots")[words[2]]["holder"] as Node).find_children("*", "GeometryInstance3D", true, false):
					var g_t := n_t as GeometryInstance3D
					var mesh_t: Mesh = null
					var count_t := 1
					if g_t is MeshInstance3D:
						mesh_t = (g_t as MeshInstance3D).mesh
					elif g_t is MultiMeshInstance3D and (g_t as MultiMeshInstance3D).multimesh != null:
						mesh_t = (g_t as MultiMeshInstance3D).multimesh.mesh
						count_t = (g_t as MultiMeshInstance3D).multimesh.visible_instance_count if (g_t as MultiMeshInstance3D).multimesh.visible_instance_count >= 0 else (g_t as MultiMeshInstance3D).multimesh.instance_count
					if mesh_t == null:
						continue
					var tri_t := 0
					for k_t in mesh_t.get_surface_count():
						var arr_t: Array = mesh_t.surface_get_arrays(k_t)
						var idx_t: Variant = arr_t[Mesh.ARRAY_INDEX]
						tri_t += floori(float((idx_t as PackedInt32Array).size() if idx_t != null else (arr_t[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3.0)
					rows_t.append([tri_t * count_t, str(g_t.get_path()).right(70), g_t.is_visible_in_tree()])
				rows_t.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
				_lines.append("TOWN tris %s: %s" % [words[2], str(rows_t.slice(0, 8))])
			elif sub_t == "up":  # !town up <plot>: the upgrade button (a guest asks the host)
				_lines.append("TOWN up %s: %s" % [words[2], String(town_t.call("upgrade", words[2]))])
			elif sub_t == "crew":  # the crew chest's goods and the hall / gallery as this copy sees them
				_lines.append("TOWN crew %s: chest %s, cases %s, paintings %s, doubloons %d, damage boon %.0f" % [" ".join(words.slice(2)), str((town_t.get("crew_chest") as RefCounted).call("to_list")), str(town_t.get("hall").get("cases")), str(town_t.get("gallery").get("bought")), int(session.call("doubloons").get("balance")), float(player.call("boon", "damage_pct"))])
			elif sub_t == "wait":  # !town wait case|paint|boon <id>: up to 60 s until it is so here
				var until_w := Time.get_ticks_msec() + 60000
				while Time.get_ticks_msec() < until_w:
					if words[2] == "case" and (town_t.get("hall").get("cases") as Dictionary).has(words[3]):
						break
					if words[2] == "paint" and (town_t.get("gallery").get("bought") as Array).has(words[3]):
						break
					if words[2] == "boon" and float(player.call("boon", words[3])) > 0.0:
						break
					if words[2] == "chest" and str((town_t.get("crew_chest") as RefCounted).call("to_list")).contains(words[3]):
						break
					await get_tree().create_timer(0.5).timeout
				_lines.append("TOWN wait %s %s: %s" % [words[2], words[3], "yes" if Time.get_ticks_msec() < until_w else "TIMED OUT"])
			elif sub_t == "nobars":  # empty the bag of ore and bars (they may not pass a painting)
				var bag_n: RefCounted = sea_t.get("skills").get("bag")
				for id_n: String in bag_n.call("all_ids"):
					if (id_n.ends_with("_ore") or id_n.ends_with("_bar")) and int(bag_n.call("count", id_n)) > 0:
						bag_n.call("remove", id_n, int(bag_n.call("count", id_n)))
			elif sub_t == "step":  # !town step: press interact where the player stands (a painting: the trip)
				var pr_s := String(sea_t.call("prompt", "F"))
				var ok_s: bool = sea_t.call("interact")
				await get_tree().create_timer(1.5).timeout
				_lines.append("TOWN step: prompt '%s', interact %s, in sea %s, in fantasy %s" % [pr_s, str(ok_s), str(session.get("_in_sea")), str(session.get("_in_fantasy"))])
			elif sub_t == "stock":
				for item_t in ["oak_plank", "palm_plank", "stormoak_plank", "iron_bar", "copper_bar", "skysteel_bar", "sailcloth", "cut_gem", "brilliant_gem"]:
					sea_t.get("skills").call("give", item_t, 600)
				session.call("doubloons").set("balance", 20000)
			elif sub_t == "wait_level":
				var until_t := Time.get_ticks_msec() + 30000
				while Time.get_ticks_msec() < until_t and int(town_t.get("rules").call("level", words[2])) < int(words[3]):
					await get_tree().create_timer(0.5).timeout
				_lines.append("TOWN wait %s >= %s: %d" % [words[2], words[3], int(town_t.get("rules").call("level", words[2]))])
			else:
				_lines.append("TOWN %s: %s, doubloons %d, oak planks %d" % [" ".join(words.slice(2)), String(town_t.call("status")), int(session.call("doubloons").get("balance")), int(sea_t.get("skills").get("bag").call("count", "oak_plank"))])
		"portart":  # sea step 7b-4: !portart go <island|aurelind> (stand before that return painting) | back (step in) | status
			var pp: Dictionary = session.get("_port_paintings")
			if words.size() > 2 and words[1] == "go" and pp.has(words[2]):
				var at_pp: Vector3 = pp[words[2]]
				player.call("teleport", at_pp + Vector3(0, 1.0, 3.0), 0.0)
				await get_tree().create_timer(0.5).timeout
				player.call("look_at_point", at_pp + Vector3(0, 2.0, 0))
			elif words.size() > 1 and words[1] == "back":
				session.call("port_travel")
				await get_tree().create_timer(3.0).timeout
			_lines.append("PORTART %s: hung %s, near '%s', prompt '%s', in sea %s, in fantasy %s" % [" ".join(words.slice(1)), str(pp.keys()), String(session.call("_port_painting_near")), String(session.call("_prompt")), str(session.get("_in_sea")), str(session.get("_in_fantasy"))])
		"chart":  # sea step 6: !chart open | close | pin <x> <z> | status <note>
			var sea_c2: Node = session.call("sea")
			if sea_c2 == null:
				_lines.append("chart: no sea")
			elif words.size() > 1 and words[1] in ["open", "close"]:
				if bool(sea_c2.get("chart_window").visible) != (words[1] == "open"):
					sea_c2.call("toggle_chart")
			elif words.size() > 3 and words[1] == "pin":
				sea_c2.get("chart").call("toggle_pin", Vector2(float(words[2]), float(words[3])))
			else:
				var ch: RefCounted = sea_c2.get("chart")
				var here_c: Vector3 = sea_c2.call("local_of", player.global_position)
				_lines.append("CHART %s: square %s, squares complete %d, explored %s, unfinished %s, pins %d, secrets shown %d, saved %d bytes" % [" ".join(words.slice(1)), String(ch.call("square_name", ch.call("square_of", here_c.x, here_c.z))), int(ch.call("complete_count")), str((ch.get("explored") as Dictionary).keys()), str((ch.call("unfinished") as Array).map(func(q: Vector2i) -> String: return String(ch.call("square_name", q)))), (ch.get("pins") as Array).size(), (sea_c2.call("chart_secrets") as Array).size(), JSON.stringify(ch.call("to_dict")).length()])
		"crane":  # sea step 5e: !crane post (stand at the crane of the ship in use) | use | status <note>
			var sea_k: Node = session.call("sea")
			var fleet_k: Node = sea_k.get("ships") if sea_k != null else null
			var crane_k: Node = fleet_k.get("crane") if fleet_k != null else null
			var sub_k := words[1] if words.size() > 1 else "status"
			if crane_k == null:
				_lines.append("crane: no sea")
			elif sub_k == "post":
				var ship_k: Node3D = (fleet_k.get("ships") as Array)[clampi(_ship_i, 0, (fleet_k.get("ships") as Array).size() - 1)]
				var spot_k: Array = load("res://game/sea_crane.gd").spot_of(ship_k.get("spec"))
				player.call("teleport", ship_k.call("deck_spot", [float(spot_k[0]) - signf(float(spot_k[0])) * 0.9, float(spot_k[1])], 0.3), 0.0)
				player.call("look_at_point", ship_k.global_transform * Vector3(float(spot_k[0]) * 3.0, 0.0, float(spot_k[1])))
			elif sub_k == "use":
				_lines.append("CRANE use: '%s'" % String(crane_k.call("prompt", "F")))
				crane_k.set("dev_use", true)
			else:
				var seen_k: Variant = session.get("net").get_node_or_null("Sea").get("crane_seen") if session.get("net") != null and session.get("net").get_node_or_null("Sea") != null else 0
				_lines.append("CRANE %s: %s; logbook found %d; others' hauls seen here %s" % [" ".join(words.slice(2)), String(crane_k.call("status")), (sea_k.get("salvage").get("book").get("found") as Dictionary).size(), str(seen_k)])
		"board":  # sea step 5d-3: !board rail <ship n> | do | status <note> | wait_lash | wait_plank | wait_none | cross
			var sea_b: Node = session.call("sea")
			var fleet_b: Node = sea_b.get("ships") if sea_b != null else null
			var board: Node = fleet_b.get("boarding") if fleet_b != null else null
			var sub_b := words[1] if words.size() > 1 else "status"
			if board == null:
				_lines.append("board: no sea")
			elif sub_b == "rail":  # stand at our ship's rail, on the side towards ship n
				var all_b: Array = fleet_b.get("ships")
				var ours: Node3D = all_b[clampi(_ship_i, 0, all_b.size() - 1)]
				var theirs_b: Node3D = all_b[clampi(int(words[2]) if words.size() > 2 else 1, 0, all_b.size() - 1)]
				var rail: Vector2 = board.call("rail_point", ours, ours.global_transform.affine_inverse() * theirs_b.global_position + Vector3(0, 0, float(words[3]) if words.size() > 3 else 0.0))  # "!board rail 1 3": 3 m further aft
				player.call("teleport", ours.call("deck_spot", [rail.x - signf(rail.x) * 0.7, rail.y], 0.3), 0.0)
				player.call("look_at_point", theirs_b.global_position + Vector3(0, 1.5, 0))
			elif sub_b == "do":
				_lines.append("BOARD do: '%s' -> %s" % [String(board.call("prompt", "F")), str(board.call("interact"))])
			elif sub_b.begins_with("wait_"):
				var began_b := Time.get_ticks_msec()
				while Time.get_ticks_msec() - began_b < 60000:
					var n_l := (board.get("lashes") as Array).size()
					var n_p := (board.get("planks") as Array).size()
					if (sub_b == "wait_lash" and n_l > 0) or (sub_b == "wait_plank" and n_p > 0) or (sub_b == "wait_none" and n_l == 0 and n_p == 0):
						break
					await get_tree().create_timer(0.5, true, false, true).timeout
			elif sub_b == "cross":  # walk over the first plank to the other ship (the real move keys)
				var plank_c: Array = board.get("planks")
				if plank_c.is_empty():
					_lines.append("BOARD cross: no plank")
				else:
					var p0: Dictionary = plank_c[0]
					var start_ship: Node3D = fleet_b.call("ship_aboard")
					var far_ship: Node3D = p0["b"] if start_ship == p0["a"] else p0["a"]
					var far_p: Vector2 = p0["pb"] if far_ship == p0["b"] else p0["pa"]
					var near_p: Vector2 = p0["pa"] if far_ship == p0["b"] else p0["pb"]
					player.call("teleport", board.call("ramp_foot", start_ship, near_p) + Vector3(0, 0.3, 0), 0.0)
					await get_tree().create_timer(0.3, true, false, true).timeout
					var began_x := Time.get_ticks_msec()
					var lowest := INF
					Input.action_press("move_forward")
					while Time.get_ticks_msec() - began_x < 12000 and fleet_b.call("ship_aboard") != far_ship:
						player.call("look_at_point", (board.call("ramp_foot", far_ship, far_p) as Vector3) + Vector3(0, 1.6, 0))
						lowest = minf(lowest, player.global_position.y - float(sea_b.call("water_height", player.global_position)))
						await get_tree().process_frame
					await get_tree().create_timer(0.6, true, false, true).timeout
					Input.action_release("move_forward")
					var arrived: bool = fleet_b.call("ship_aboard") == far_ship
					_lines.append("BOARD cross: %s after %.1f s, lowest %.1f m above the sea, swimming %s" % ["ON the other ship" if arrived else "NOT across", (Time.get_ticks_msec() - began_x) / 1000.0, lowest, str(player.get("swimming"))])
			else:
				var ships_b: Array = fleet_b.get("ships")
				var hold_b := PackedStringArray()
				for ship_b: Node in ships_b:
					hold_b.append("%s (%.0f, %.0f) yaw %.0f" % [String(ship_b.get("state")["ship"]), float(ship_b.get("state")["x"]), float(ship_b.get("state")["z"]), rad_to_deg(float(ship_b.get("state")["yaw"]))])
				var asks: Variant = session.get("net").get_node_or_null("Sea").get("board_log") if session.get("net") != null and session.get("net").get_node_or_null("Sea") != null else PackedStringArray()
				_lines.append("BOARD %s: %s; ships %s; aboard %d; host asks %s" % [" ".join(words.slice(2)), String(board.call("status")), ", ".join(hold_b), ships_b.find(fleet_b.call("ship_aboard")), str(asks)])
		"cannon":  # sea step 5d-2: !cannon target <ship n> (sit at the cannon facing it and aim) | fire | wait_ships <n> | status <note> | leave
			var sea_c: Node = session.call("sea")
			var fleet_c: Node = sea_c.get("ships") if sea_c != null else null
			var guns: Node = fleet_c.get("cannons") if fleet_c != null else null
			var sub := words[1] if words.size() > 1 else "status"
			if guns == null:
				_lines.append("cannon: no sea")
			elif sub == "wait_ships":
				var began_c := Time.get_ticks_msec()
				while Time.get_ticks_msec() - began_c < 60000 and (fleet_c.get("ships") as Array).size() < int(words[2]):
					await get_tree().create_timer(0.5, true, false, true).timeout
			elif sub == "target":
				var all: Array = fleet_c.get("ships")
				var mine: Node3D = all[clampi(_ship_i, 0, all.size() - 1)]
				var aim_at: Node3D = all[clampi(int(words[2]) if words.size() > 2 else 1, 0, all.size() - 1)]
				var best := -1
				var best_dot := -2.0
				var list_c: Array = (guns.get("_guns") as Dictionary).get(mine, [])
				for i in list_c.size():
					var holder: Node3D = list_c[i]["holder"]
					var outward := holder.global_transform.basis * (list_c[i]["m"] as Vector3)
					var dot := outward.normalized().dot((aim_at.global_position - holder.global_position).normalized())
					if dot > best_dot:
						best_dot = dot
						best = i
				if best >= 0:
					guns.call("sit", mine, best)
					player.call("teleport", mine.call("deck_spot", [float(list_c[best]["spot"][0]) - float(list_c[best]["side"]) * 1.3, float(list_c[best]["spot"][1])], 0.3), 0.0)
					player.call("look_at_point", aim_at.global_position + Vector3(0, 2.0, 0))
					var holder_b: Node3D = list_c[best]["holder"]
					guns.set("dev_target", aim_at)
					_lines.append("CANNON target ship %d: cannon %d (facing %.2f), %.0f m" % [all.find(aim_at), best, best_dot, aim_at.global_position.distance_to(holder_b.global_position)])
			elif sub == "fire":
				guns.set("dev_fire", true)
			elif sub == "leave":
				guns.call("stand_up")
			else:
				var hulls: Array = []
				for ship_c: Node in fleet_c.get("ships"):
					hulls.append("%s %.0f%s" % [String(ship_c.get("state")["ship"]), float(ship_c.get("state")["hull"]), " holed %s" % str(ship_c.get("state")["leaks"]) if float(load("res://core/sea/hull_rules.gd").new({}).holes(ship_c.get("state"))) > 0.0 else ""])
				_lines.append("CANNON %s: %s; hulls %s" % [" ".join(words.slice(2)), String(guns.call("status")), ", ".join(hulls)])
		"isle":  # island paths (director: every place reachable by a path that can be walked): !isle routes [island] | walk [place|all] [island] [snap] | ghosts | lookghost | wait_ghost [m]
			var sea_isle: Node = session.call("sea")
			if sea_isle == null:
				_lines.append("isle: no sea (use /tp sea first)")
			elif words.size() > 1 and words[1] in ["ghosts", "lookghost", "wait_ghost"]:  # online: the other players on the island as this machine shows them
				var bodies: Array = session.get("net").call("target_nodes") if session.get("net") != null else []
				if words[1] == "wait_ghost":  # "!isle wait_ghost 300": wait (up to 90 s) for another player within that many metres
					var began := Time.get_ticks_msec()
					var within := float(words[2]) if words.size() > 2 else 300.0
					while Time.get_ticks_msec() - began < 90000:
						bodies = session.get("net").call("target_nodes")
						if bodies.any(func(b: Node3D) -> bool: return b.global_position.distance_to(player.global_position) < within):
							break
						await get_tree().create_timer(0.5, true, false, true).timeout
				var island_at := Vector2.ZERO
				for island: Dictionary in sea_isle.get("islands").get("_cfg")["islands"]:
					if String(island["id"]) == "start":
						island_at = Vector2(float(island["pos"][0]), float(island["pos"][1]))
				var me: Vector3 = sea_isle.call("local_of", player.global_position)
				var notes := PackedStringArray(["me at island (%.0f, %.1f, %.0f)" % [me.x - island_at.x, me.y, me.z - island_at.y]])
				var nearest: Node3D = null
				for body: Node3D in bodies:
					var there: Vector3 = sea_isle.call("local_of", body.global_position)
					var down := PhysicsRayQueryParameters3D.create(body.global_position + Vector3(0, 2.0, 0), body.global_position + Vector3(0, -30.0, 0))
					down.exclude = [player.get_rid()]
					down.collision_mask = 1  # the ground only: ghosts are on layer 8 (shots only) and would be hit first
					var hit := player.get_world_3d().direct_space_state.intersect_ray(down)
					var gap := "no ground under" if hit.is_empty() else "%.2f m above the ground" % (body.global_position.y - (hit["position"] as Vector3).y)
					notes.append("other at island (%.0f, %.1f, %.0f), %.0f m from me, %s, swimming %s" % [there.x - island_at.x, there.y, there.z - island_at.y, body.global_position.distance_to(player.global_position), gap, str(body.get("_swimming"))])
					if nearest == null or body.global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position):
						nearest = body
				var shown: Dictionary = (sea_isle.get("islands").get("_shown") as Dictionary).get("start", {})
				if shown.get("full") != null and (shown["full"] as Node).has_node("Stream"):
					notes.append("start island chunks (all, solid, clutter) %s" % str((shown["full"] as Node).get_node("Stream").call("chunk_counts")))
				else:
					notes.append("start island not loaded here")
				_lines.append("ISLE GHOSTS " + "; ".join(notes))
				if words[1] == "lookghost" and nearest != null:
					player.call("look_at_point", nearest.global_position + Vector3(0, 1.2, 0))
			elif words.size() > 1 and words[1] == "walk":
				var walker := IsleWalker.new()
				add_child(walker)
				var pictures := func(shot: String) -> void:
					await _stage(renderer, shot, 0.2)
				await walker.walk(player as CharacterBody3D, sea_isle, words[3] if words.size() > 3 else "", words[2] if words.size() > 2 else "all", pictures if words.has("snap") else Callable())
				_lines.append_array(walker.lines)
				walker.queue_free()
			else:
				var wanted := words[2] if words.size() > 2 else "start"
				for island: Dictionary in sea_isle.get("islands").get("_cfg")["islands"]:
					if String(island["id"]) == wanted and island.has("props"):
						var routes := IsleRoutes.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/isles/%s.json" % String(island["props"]))))
						var found := routes.problems()
						_lines.append("ROUTES %s: %d places, %d path points, problems %d %s" % [wanted, routes.pois.size(), routes.points.size(), found.size(), "; ".join(found)])
		"swim":  # sea swimming (step 5b): !swim status | drop <x> <z> | spot <n> | take | ladder | rope | stamina <n> | log
			var sea_w: Node = session.call("sea")
			if sea_w == null:
				_lines.append("swim: no sea (use /tp sea first)")
			else:
				var swim_n: Node = sea_w.get("swim")
				var salv: Node = sea_w.get("salvage")
				var first_ship: Node = (sea_w.get("ships").get("ships") as Array)[0]
				match words[1] if words.size() > 1 else "status":
					"drop":
						player.call("teleport", sea_w.call("world_of", Vector3(float(words[2]), -1.0, float(words[3]))), 0.0)
					"spot":
						salv.call("dev_to_spot", int(words[2]) if words.size() > 2 else 0)
					"take":
						_lines.append("take: %s" % str(salv.call("interact")))
					"ladder":
						var foot: Vector3 = first_ship.global_transform * Vector3(float(first_ship.get("spec")["outline"][2][1]) + 1.2, -0.8, float(first_ship.get("spec")["ladder_z"]))
						player.call("teleport", foot, 0.0)
						_lines.append("ladder near: %s" % str(not (swim_n.call("ladder_near") as Dictionary).is_empty()))
					"climb":
						var spot: Dictionary = swim_n.call("ladder_near")
						if not spot.is_empty():
							swim_n.call("climb_ladder", spot)
						_lines.append("climb: %s" % str(not spot.is_empty()))
					"off":  # into the water this many metres off the first ship's starboard side, midships
						var away: Vector3 = first_ship.global_transform * Vector3(float(first_ship.get("spec")["outline"][3][1]) + float(words[2]), -0.8, 0.0)
						player.call("teleport", away, 0.0)
					"throw":  # the interact key at the rail: a rope to the nearest swimming player (tries for up to 25 s)
						var tried := Time.get_ticks_msec()
						var thrown := false
						while not thrown and Time.get_ticks_msec() - tried < 25000:
							thrown = bool(swim_n.call("interact"))
							if not thrown:
								await get_tree().create_timer(0.5, true, false, true).timeout
						_lines.append("throw: %s after %.1f s" % [str(thrown), (Time.get_ticks_msec() - tried) / 1000.0])
					"wait_aboard":  # waits (up to 30 s) until we stand on a ship again (hauled up by a rope)
						var began := Time.get_ticks_msec()
						while sea_w.get("ships").call("ship_aboard") == null and Time.get_ticks_msec() - began < 30000:
							await get_tree().create_timer(0.25, true, false, true).timeout
						_lines.append("wait_aboard: %s after %.1f s" % [str(sea_w.get("ships").call("ship_aboard") != null), (Time.get_ticks_msec() - began) / 1000.0])
					"rope":
						var hw := float(first_ship.get("spec")["outline"][3][1])
						swim_n.call("throw_rope", first_ship, Vector3(hw, float(first_ship.get("spec")["deck"]) + 0.75, 0.0), player.global_position + Vector3(0.8, 0.0, 0.0))
					"stamina":
						swim_n.set("stamina", float(words[2]))
					"log":
						sea_w.call("toggle_logbook")
					_:
						_lines.append("swim: swimming %s aboard %s climbing %s health %.0f y %.2f | %s" % [str(player.get("swimming")), str(sea_w.get("ships").call("ship_aboard") != null), str(swim_n.call("climbing")), float(player.get("health").get("hp")), player.global_position.y, String(salv.call("status"))])
		"nearclimb":  # fantasy world: stand at the foot of the nearest cliff shortcut (searches the cells round the player)
			var land: Node = session.call("fantasy")
			var here: Vector3 = land.call("player_local")
			var size := float(land.get("data")["agility"]["shortcuts"]["cell"])
			var best := {}
			for dx in range(-6, 7):
				for dz in range(-6, 7):
					var spot: Dictionary = ShortcutSpots.spot(land.get("terrain"), land.get("layout"), Vector2i(floori(here.x / size) + dx, floori(here.z / size) + dz), land.get("data")["agility"]["shortcuts"])
					if not spot.is_empty() and (best.is_empty() or here.distance_to(spot["base"]) < here.distance_to(best["base"])):
						best = spot
			if not best.is_empty():
				var dir: Vector2 = best["dir"]
				var stand: Vector3 = best["base"] - Vector3(dir.x, 0.0, dir.y) * 1.2
				player.call("teleport", land.call("world_of", stand) + Vector3(0, 0.3, 0), atan2(-dir.x, -dir.y))
				land.get("agility").call("follow", stand)
			_lines.append("nearest climb: %s" % ("none" if best.is_empty() else "%s at %s up %.1f m" % [best["kind"], str(best["base"].snapped(Vector3.ONE * 0.1)), best["top"].y - best["base"].y]))
		"animals":  # fantasy world: every wild animal near, with what it is doing, for the log
			var seen := PackedStringArray()
			for enemy: Variant in session.call("director").call("enemy_list"):
				if is_instance_valid(enemy) and (enemy as Node).has_meta("animal"):
					var e := enemy as Node3D
					seen.append("%s %.0f m hp %d moving %.1f m/s" % [String(e.get("enemy_id")), e.global_position.distance_to(player.global_position), int(e.get("health").hp), Vector2(e.get("velocity").x, e.get("velocity").z).length()])
			_lines.append("animals %s: [%s]" % [" ".join(words.slice(1)), ", ".join(seen)])
			var closest: Node3D = null
			for enemy: Variant in session.call("director").call("enemy_list"):
				if is_instance_valid(enemy) and (enemy as Node).has_meta("animal") and (closest == null or (enemy as Node3D).global_position.distance_to(player.global_position) < closest.global_position.distance_to(player.global_position)):
					closest = enemy
			if closest != null and words.size() > 1 and words[1] == "go":  # "!animals go": stand 6 m from the nearest one
				var off := (player.global_position - closest.global_position)
				off.y = 0.0
				player.call("teleport", closest.global_position + off.normalized() * 6.0 + Vector3(0, 0.5, 0), 0.0)
				player.call("look_at_point", closest.global_position)
			elif closest != null and words.size() > 1 and words[1] == "kill":  # "!animals kill": the nearest one falls to the player
				closest.call("on_hit", 99999.0)
		"neardoor":  # fantasy world: stand at the nearest door of a building that is entered into a room
			var doors: Array = session.call("fantasy").get("rooms").get("_doors")
			_lines.append("doors here: %d" % doors.size())
			if not doors.is_empty():
				var best: Dictionary = doors[0]
				var me: Vector3 = session.call("fantasy").call("player_local")
				for door: Dictionary in doors:
					if Vector2(me.x, me.z).distance_to(door["at"]) < Vector2(me.x, me.z).distance_to(best["at"]):
						best = door
				player.call("teleport", session.call("fantasy").call("ground_world", best["at"].x, best["at"].y), 0.0)
				_lines.append("door of a %s" % best["kind"])
		"nearbox":  # fantasy world: stand next to the first container of the room, or outdoors of the walk-in house here
			var land: Node = session.call("fantasy")
			if not bool(land.get("rooms").call("inside")):
				var chests: Array = land.get("rooms").get("_boxes")
				_lines.append("containers of walk-in houses here: %d" % chests.size())
				if not chests.is_empty():
					var spot: Vector3 = chests[0]["at"]
					player.call("teleport", land.call("ground_world", spot.x + 0.8, spot.z + 0.8) + Vector3(0, 0.2, 0), 0.0)
					player.call("look_at_point", land.call("world_of", spot) + Vector3(0, 0.5, 0))
				return
			var boxes: Array = land.get("rooms").get("_room_boxes")
			_lines.append("containers in the room: %d" % boxes.size())
			if not boxes.is_empty():
				player.call("teleport", (boxes[0]["at"] as Vector3) + Vector3(0.9, 0.2, -0.9), 0.0)
				player.call("look_at_point", (boxes[0]["at"] as Vector3) + Vector3(0, 0.6, 0))
		"roomexit":  # fantasy world, inside a room: stand at its door
			player.call("teleport", (session.call("fantasy").get("rooms").get("_exit") as Vector3) + Vector3(0, 0.2, 0.2), 0.0)
		"panel":  # fantasy world: open a page of the window (Skills, Bag, Quests, Spells) and pick the thing named after it
			var window: Control = session.call("fantasy").get("panel")
			window.call("open", words[1])
			if words.size() > 2:
				window.call("pick", words[2])
		"fgive":  # "!fgive oak_plank 40": items straight into the fantasy bag (also from the sea: the skills' world)
			session.get("_fantasy").call("give", words[1], int(words[2]) if words.size() > 2 else 1)
		"flevel":  # "!flevel carpentry 45": a skill's level (dev runs never save)
			session.get("_fantasy").get("skills").call("set_level", words[1], int(words[2]))
		"fmake":  # "!fmake build_sloop": make a recipe through the station code (needs its level and materials)
			var land_w: Node = session.get("_fantasy")
			for recipe: Dictionary in land_w.get("skilling")["recipes"]:
				if String(recipe["id"]) == words[1]:
					var why := String(land_w.get("work").call("make", recipe))
					_lines.append("make %s: %s" % [words[1], "made" if why == "" else why])
		"station":  # fantasy world: open the window of a station (fire, forge, workbench, cauldron) and pick a recipe
			var window: Control = session.call("fantasy").get("panel")
			window.call("open_station", words[1])
			if words.size() > 2:
				window.call("pick", words[2])
		"armour":  # "!armour [note]": worn armour totals (core/armor_math.gd) and max health into the log
			var worn: Dictionary = player.get("armor")
			_lines.append("ARMOUR %s: defense %.1f block %.2f resist %s bonus %s sets %s max health %d" % [" ".join(words.slice(1)), float(worn.get("defense", 0)), float(worn.get("block", 0)), str(worn.get("resist", {})), str(worn.get("bonus", {})), str(worn.get("sets", {})), roundi(float(player.get("health").max_hp))])
		"inv":  # the inventory window: "!inv" opens or shuts it, "!inv hover 5" puts the mouse on slot 5 (0-35), "!inv drop" presses the drop key, "!inv shift on|off" holds Shift, "!inv log" lists rolled guns and what lies on the ground, "!inv tab guns tier" picks a tab and sort
			var window: Control = session.get("_inventory_screen")
			match words[1] if words.size() > 1 else "":
				"bank":  # "!inv bank": the window as the bank opens it (the bank's slots on the left)
					session.call("_open_bank")
				"hoverarm":  # "!inv hoverarm [n]": the mouse on the n-th backpack slot holding a rolled armour piece (0 = first)
					var seen := 0
					for i in InventoryState.SIZE:
						if not (player.get("inventory").call("arm_at", i) as Dictionary).is_empty():
							if seen == (int(words[2]) if words.size() > 2 else 0):
								window.set("_mouse", (window.call("_slot_rect", i) as Rect2).get_center())
								break
							seen += 1
				"hovergear":  # "!inv hovergear head": the mouse on a gear slot
					window.set("_mouse", (window.call("_equip_rect", InventoryState.EQUIP_SLOTS.find(words[2])) as Rect2).get_center())
				"weararm":  # "!inv weararm": Wear on the first backpack slot holding a rolled armour piece
					for i in InventoryState.SIZE:
						if not (player.get("inventory").call("arm_at", i) as Dictionary).is_empty():
							window.set("_focus", i)
							window.call("_act", "wear")
							break
				"wear":  # "!inv wear 3": the card's Wear button on backpack slot 3 (a piece of armour)
					window.set("_focus", int(words[2]))
					window.call("_act", "wear")
				"tab":  # "!inv tab guns|gear|items|all [sort]": the header's tab and sort (slot, tier, level, type)
					window.set("tab", words[2])
					if words.size() > 3:
						window.set("sort_by", words[3])
				"hover":  # a backpack slot (0-35), a holster ("h0".."h3") or "knife"
					if words[2] == "knife":
						window.set("_mouse", (window.call("_holster_rect", int(player.get("inventory").get("holster_count"))) as Rect2).get_center())
					elif words[2].begins_with("h"):
						window.set("_mouse", (window.call("_holster_rect", int(words[2].substr(1))) as Rect2).get_center())
					else:
						window.set("_mouse", (window.call("_slot_rect", int(words[2])) as Rect2).get_center())
				"press":  # a REAL left mouse click through the window's own input: a backpack slot (0-35), a holster ("h0".."h3"), a bank slot ("b0".."b59") or "bankbutton"
					var spot := Rect2()
					if words[2] == "bankbutton":
						spot = window.call("_bank_button")
					elif words[2].begins_with("b"):
						spot = window.call("_bank_rect", int(words[2].substr(1)))
					elif words[2].begins_with("h"):
						spot = window.call("_holster_rect", int(words[2].substr(1)))
					else:
						spot = window.call("_slot_rect", int(words[2]))
					for down: bool in [true, false]:
						var click := InputEventMouseButton.new()
						click.button_index = MOUSE_BUTTON_LEFT
						click.pressed = down
						click.position = spot.get_center()
						click.global_position = spot.get_center()
						window.call("_gui_input", click)
				"click":  # a left click on a backpack slot (0-35) or a holster ("h0".."h3")
					if words[2].begins_with("h"):
						player.get("inventory").call("click_holster", int(words[2].substr(1)))
					else:
						player.get("inventory").call("click_slot", int(words[2]))
					session.call("_on_inventory_changed")
				"drop":
					var press := InputEventAction.new()
					press.action = "drop_item"
					press.pressed = true
					Input.parse_input_event(press)
				"shift":
					var key := InputEventKey.new()
					key.keycode = KEY_SHIFT
					key.physical_keycode = KEY_SHIFT
					key.pressed = words[2] == "on"
					Input.parse_input_event(key)
				"log":
					var guns := PackedStringArray()
					var bag: RefCounted = player.get("inventory")
					for i in 36:
						if not (bag.call("gun_at", i) as Dictionary).is_empty():
							guns.append("%d:%s" % [i, String((bag.call("gun_at", i) as Dictionary)["tier"])])
					_lines.append("rolled guns in slots %s; on the ground %d; shift %s  %s" % [", ".join(guns), int((session.get("_field") as Node).call("count")), str(Input.is_key_pressed(KEY_SHIFT)), " ".join(words.slice(2))])
				_:
					session.call("_toggle_inventory")
		"isle":  # "!isle 2 [dx dz]": stand on island n (0 = the spawn island), that far from its middle
			var land: RefCounted = session.get("_land")
			var mid: Vector2 = (land.get("islands") as Array)[int(words[1])]["at"]
			player.call("teleport", Vector3(500.0 + mid.x + (float(words[2]) if words.size() > 3 else 0.0), 0.2, mid.y + (float(words[3]) if words.size() > 3 else 3.0)), 0.0)
		"box":  # "!box goto": stand at the mystery box; "!box <note>": what it does, where, whose gun, what is in our hands
			var box: RefCounted = session.get("_box")
			var spot: Vector2 = (session.get("_box_spots") as Array)[int(box.get("spot"))]
			if words.size() > 1 and words[1] == "goto":
				player.call("teleport", Vector3(500.0 + spot.x + 1.3, 0.15, spot.y + 1.3), 0.0)
				player.call("look_at_point", Vector3(500.0 + spot.x, 0.9, spot.y))
			else:
				var bag: RefCounted = player.get("inventory")
				var held := PackedStringArray()
				for i in int(bag.get("holster_count")):
					var rolled: Dictionary = bag.call("holster_gun", i)
					held.append("%s%s" % [String(bag.call("holster_body", i)), "" if rolled.is_empty() else " (" + String(rolled["tier"]) + ")"])
				_lines.append("BOX %s: %s on spot %d, offers %s, ready [%s], points %d" % [" ".join(words.slice(1)), String(box.get("state")), int(box.get("spot")), str((session.get("_box_gun") as Dictionary).get("tier", "-")) + " " + str((session.get("_box_gun") as Dictionary).get("body", "")), ", ".join(held), int((session.call("score") as RefCounted).get("points"))])
		"upgrade":  # "!upgrade goto": stand at the upgrade machine
			var spot: Vector2 = session.get("_upgrade_spot")
			player.call("teleport", Vector3(500.0 + spot.x + 1.2, 0.15, spot.y + 1.2), 0.0)
			player.call("look_at_point", Vector3(500.0 + spot.x, 1.2, spot.y))
		"trap":  # "!trap goto 3": stand at trap n's lever; "!trap <note>": which run, the living enemies, health
			if words.size() > 2 and words[1] == "goto":
				var spot: Vector2 = (session.get("_trap_levers") as Array)[int(words[2])]
				var middle: Vector2 = (session.get("_trap_centres") as Array)[int(words[2])]
				player.call("teleport", Vector3(500.0 + spot.x, 0.15, spot.y), 0.0)
				player.call("look_at_point", Vector3(500.0 + middle.x, 1.0, middle.y))
			else:
				var timing: RefCounted = session.get("_traps")
				var on := PackedStringArray()
				for i in (session.get("_trap_levers") as Array).size():
					on.append("%d:%s" % [i, "runs %.0f s" % float(timing.call("left", i, float(session.get("_time")))) if bool(timing.call("running", i, float(session.get("_time")))) else ("waits %.0f s" % float(timing.call("wait", i, float(session.get("_time")))))])
				_lines.append("TRAP %s: %s | enemies %d | health %d | points %d" % [" ".join(words.slice(1)), ", ".join(on), (session.call("director").call("enemy_list") as Array).size(), roundi(float(player.get("health").hp)), int((session.call("score") as RefCounted).get("points"))])
		"perk":  # "!perk goto iron_gut": stand at that perk's machine; "!perk <note>": perks carried, health, holsters, power
			if words.size() > 2 and words[1] == "goto":
				var spot: Vector2 = (session.get("_perk_spots") as Dictionary)[words[2]]
				var mid: Vector2 = ((session.get("_land") as RefCounted).get("islands") as Array)[int((session.get("_land") as RefCounted).call("island_near", spot.x, spot.y))]["at"]
				var front := spot + (mid - spot).normalized() * 1.8
				player.call("teleport", Vector3(500.0 + front.x, 0.15, front.y), 0.0)
				player.call("look_at_point", Vector3(500.0 + spot.x, 1.3, spot.y))
			else:
				var power: RefCounted = session.get("_power")
				_lines.append("PERK %s: carried %s, health %d / %d, ready slots %d, power parts %d on %s, points %d" % [" ".join(words.slice(1)), str((session.get("_perks") as RefCounted).get("owned")), roundi(float(player.get("health").hp)), roundi(float(player.get("health").max_hp)),
					int((player.get("inventory") as RefCounted).get("holster_count")), int(power.call("found_count")), str(power.get("on")), int((session.call("score") as RefCounted).get("points"))])
		"power":  # "!power part 1": stand at power part n; "!power bench": stand at the workbench; "!power <note>": parts found and the switch
			if not (words[1] in ["bench", "part"]):
				var ps: RefCounted = session.get("_power")
				_lines.append("POWER %s: found %d, all %s, on %s" % [" ".join(words.slice(1)), int(ps.call("found_count")), str(ps.call("all_found")), str(ps.get("on"))])
				return
			var spot: Vector2 = session.get("_bench_spot") if words[1] == "bench" else (session.get("_part_spots") as Array)[int(words[2])]
			player.call("teleport", Vector3(500.0 + spot.x + 1.2, 0.15, spot.y + 1.2), 0.0)
			player.call("look_at_point", Vector3(500.0 + spot.x, 0.8, spot.y))
		"hut":  # "!hut in 0": stand inside hut n; "!hut window 4 [out]": stand at window n inside (or outside), looking at it; "!hut <note>": every window's boards, who is inside, points
			var huts: Node3D = session.get("_shelters")
			var hut_rules: RefCounted = huts.get("rules")
			if words.size() > 2 and words[1] == "in":
				var mid: Vector2 = (hut_rules.get("huts") as Array)[int(words[2])]["at"]
				player.call("teleport", Vector3(500.0 + mid.x, 0.15, mid.y), 0.0)
			elif words.size() > 2 and words[1] == "window":
				var opening: Dictionary = (hut_rules.get("windows") as Array)[int(words[2])]
				var side: Vector2 = ((opening["out"] as Vector2) - (opening["mid"] as Vector2)) * (1.3 if words.size() > 3 else -1.3)
				player.call("teleport", Vector3(500.0 + (opening["mid"] as Vector2).x + side.x, 0.15, (opening["mid"] as Vector2).y + side.y), 0.0)
				player.call("look_at_point", Vector3(500.0 + (opening["mid"] as Vector2).x, 1.5, (opening["mid"] as Vector2).y))
			else:
				var inside := 0
				for enemy: Variant in session.call("director").call("enemy_list"):
					if is_instance_valid(enemy) and int(hut_rules.call("hut_of", (enemy as Node3D).global_position.x - 500.0, (enemy as Node3D).global_position.z)) >= 0:
						inside += 1
				_lines.append("HUT %s: boards %s, player in hut %d, enemies inside huts %d of %d, points %d" % [" ".join(words.slice(1)), str(hut_rules.get("boards")), int(hut_rules.call("hut_of", player.global_position.x - 500.0, player.global_position.z)), inside,
					(session.call("director").call("enemy_list") as Array).size(), int((session.call("score") as RefCounted).get("points"))])
		"wall":  # "!wall goto 3": stand in front of wall buy n, looking at its board
			var land: RefCounted = session.get("_land")
			var board: Dictionary = (land.get("wall_buys") as Array)[int(words[2])]
			var at: Vector2 = board["at"]
			var front := Vector2(sin(float(board["yaw"])), cos(float(board["yaw"])))
			player.call("teleport", Vector3(500.0 + at.x + front.x * 2.2, 0.15, at.y + front.y * 2.2), 0.0)
			player.call("look_at_point", Vector3(500.0 + at.x, 1.5, at.y))
		"debris":  # "!debris goto 0": stand 2.5 m before debris n on its first island's side, looking at it; "!debris <note>": where we are and what is cleared
			var land: RefCounted = session.get("_land")
			if words.size() > 2 and words[1] == "goto":
				var way: Dictionary = (land.get("bridges") as Array)[int(words[2])]
				var before: Vector2 = (way["mid"] as Vector2) + ((way["a"] as Vector2) - (way["mid"] as Vector2)).normalized() * 2.5
				player.call("teleport", Vector3(500.0 + before.x, float(land.call("deck_height", int(words[2]))) + 0.15, before.y), 0.0)
				player.call("look_at_point", Vector3(500.0 + (way["mid"] as Vector2).x, 1.4, (way["mid"] as Vector2).y))
			else:
				var at: Vector3 = player.global_position - Vector3(500, 0, 0)
				_lines.append("DEBRIS %s: on island %d, y %.2f, land %s, deck %d, debris here %d, cleared %s, reachable %s, points %d" % [" ".join(words.slice(1)), int(land.call("island_near", at.x, at.z)), at.y,
					str(land.call("on_land", at.x, at.z)), int(land.call("deck_at", at.x, at.z)), int(session.call("_debris_here")), str(land.call("open_list")), str(land.call("reachable")), int((session.call("score") as RefCounted).get("points"))])
		"shield":  # "!shield <note>": whether a shield is carried, the hits it still takes, whether it is held up, our health
			var carried: RefCounted = player.get("shield")
			_lines.append("SHIELD %s: owned %s, hits %d of %d, in hand %s, hand %d, held '%s', health %.0f" % [" ".join(words.slice(1)), str(carried.get("owned")), int(carried.get("hits_left")), int(carried.call("max_hits")), str(int(player.call("hand_index")) == -2), int(player.call("hand_index")), String(player.call("held_id")), float((player.get("health") as RefCounted).get("hp"))])
		"build":  # "!build goto shield 1": stand at part 1 of the shield; "!build goto boat bench": at its bench; "!build <note>": what is found and built
			var state: RefCounted = session.get("_builds")
			if words.size() > 3 and words[1] == "goto":
				var which := int(state.call("index_of", words[2]))
				var to: Vector2 = (session.get("_build_benches") as Array)[which] if words[3] == "bench" else ((session.get("_build_parts") as Array)[which] as Array)[int(words[3])]
				player.call("teleport", Vector3(500.0 + to.x + 0.9, 0.15, to.y + 0.9), 0.0)
				player.call("look_at_point", Vector3(500.0 + to.x, 0.6, to.y))
			else:
				var told := PackedStringArray()
				for which in (state.get("ids") as Array).size():
					told.append("%s %d of %d%s" % [String((state.get("ids") as Array)[which]), int(state.call("found_count", which)), int(state.call("part_count", which)), " BUILT" if bool(state.call("built", which)) else ""])
				_lines.append("BUILD %s: %s | here %d" % [" ".join(words.slice(1)), ", ".join(told), int(session.call("_build_thing_at", player.global_position))])
		"boat":  # "!boat goto": stand on the sand nearest the boat, looking at it; "!boat <note>": where it is, its speed, who sits in it, our place; "!boat wait_other": wait until another player sits in it
			if words.size() > 1 and words[1] == "wait_other":  # "!boat wait_other": wait (up to 60 s) until another player sits in the boat
				var link: Node = session.get("net")
				var began := Time.get_ticks_msec()
				var seen := false
				while not seen and Time.get_ticks_msec() - began < 60000:
					var seats_line := String(session.call("boat_note")).get_slice("seats [", 1).get_slice("]", 0)
					for id: int in (link.get("roster") as Dictionary):
						if id != int(link.call("my_id")) and seats_line.contains(str(id)):
							seen = true
					await get_tree().create_timer(0.25, true, false, true).timeout
				return
			if words.size() > 1 and words[1] == "goto":
				player.call("teleport", session.call("boat_shore"), 0.0)
				var hull: Node3D = session.get("_boat_node")
				player.call("look_at_point", hull.global_position + Vector3(0, 0.6, 0))
			else:
				var me: Vector3 = player.global_position - Vector3(500, 0, 0)
				_lines.append("BOAT %s: %s | we are at %.1f %.1f %.1f" % [" ".join(words.slice(1)), String(session.call("boat_note")), me.x, me.y, me.z])
		"ticket":  # "!ticket goto": stand at the colosseum painting; "!ticket buy 1 [mod,mod]": choose that ticket (0 = the shortest) and those modifiers on the board and press Go in
			if words.size() > 1 and words[1] == "goto":
				var painting: Vector3 = session.get("_painting")
				player.call("teleport", painting + Vector3(1.5, 0.15, 1.5), 0.0)
				player.call("look_at_point", painting + Vector3(0, 1.6, 0))
			elif words.size() > 2 and words[1] == "buy":
				var board: Control = session.get("_board")
				var mods := PackedStringArray(words[3].split(",", false)) if words.size() > 3 else PackedStringArray()
				board.call("choose", int(words[2]), mods)
				board.emit_signal("chosen", int(words[2]), mods)
		"quest":  # "!quest goto <step id>": stand at that step's spot; "!quest lamp n": shoot lamp n; "!quest jump n": the quest is at step n (host); "!quest <note>": where it stands
			if words.size() > 2 and words[1] == "goto":
				var to: Vector2 = (session.get("_quest_spots") as Dictionary)[words[2]]
				player.call("teleport", Vector3(500.0 + to.x + 1.2, 0.15, to.y + 1.2), 0.0)
				player.call("look_at_point", Vector3(500.0 + to.x, 0.4, to.y))
			elif words.size() > 2 and words[1] == "lamp":
				session.call("_on_lamp_shot", int(words[2]))
			elif words.size() > 2 and words[1] == "jump":
				var quest: RefCounted = session.get("_quest")
				quest.call("from_dict", {"step": int(words[2])})
				session.call("_show_quest")
			else:
				var quest: RefCounted = session.get("_quest")
				_lines.append("QUEST %s: step %d (%s, %s), count %d, lamps %s, boss out %s, tracker '%s', points %d" % [" ".join(words.slice(1)), int(quest.get("step")), String((quest.call("current") as Dictionary).get("id", "done")), String(quest.call("kind")), int(quest.get("count")), str(quest.get("shot")), str(quest.get("boss_out")),
					String((session.get("_player_hud") as Node).get("quest_text")).replace("\n", " | "), int((session.call("score") as RefCounted).get("points"))])
		"song":  # "!song n": shoot all three floats of hidden song n (1-based); "!song <note>": unlocked songs, the files found, what plays
			var book: RefCounted = session.get("_songs")
			if words.size() > 1 and words[1].is_valid_int():
				for thing in 3:
					session.call("_on_float_shot", int(words[1]) - 1, thing)
			else:
				_lines.append("SONG %s: unlocked %s, files %s, playing %s" % [" ".join(words.slice(1)), str(book.get("unlocked")), str(book.get("files")), str((session.get("music_box") as Node).call("playing_id"))])
		"crosshair":  # "!crosshair menu": Settings > Crosshair over the game; "!crosshair n": click design n (1-based); "!crosshair code <code>": paste a share code; "!crosshair close"; "!crosshair <note>": what the HUD shows
			var main := _find_with(get_tree().root, "_show_only")
			var page: Node = main.get("_crosshair_menu")
			if words.size() > 1 and words[1] == "menu":
				main.call("_show_only", page)
			elif words.size() > 1 and words[1] == "close":
				main.call("_show_only", null)  # NOT main._close_controls: that writes the settings file, and a test must not change his crosshair
			elif words.size() > 2 and words[1] == "code":
				(page.get("_code") as LineEdit).text = words[2]
				page.call("_use_code")
			elif words.size() > 1 and words[1].is_valid_int():
				page.call("_pick", int(words[1]) - 1)
			else:
				var shown: Dictionary = (session.get("_cross") as Control).get("style")
				var styles: RefCounted = page.get("styles")
				_lines.append("CROSSHAIR %s: HUD '%s' (design %d), code %s, saved %s, note '%s'" % [" ".join(words.slice(1)), String(shown.get("name", "")), int(styles.call("preset_of", shown)) + 1, String(styles.call("code_of", shown)), str(not ((session.get("settings") as RefCounted).get("crosshair") as Dictionary).is_empty()), (page.get("_note") as Label).text])
		"inspect":  # "!inspect": the inspect key; "!inspect <note>": what is being looked over and the pose now
			if words.size() == 1:
				player.call("start_inspect")
			else:
				var pose: Array = player.call("inspect_pose")
				_lines.append("INSPECT %s: '%s', moved %s, turned %s" % [" ".join(words.slice(1)), String(player.call("inspecting")), str(pose[0]), str(pose[1])])
		"photo":  # "!photo on": photo mode (pictures go to tools/userdata/photos, not his Pictures folder); "!photo off"; "!photo take"; "!photo fly x y z" (metres in the view); "!photo zoom n"; "!photo <note>"
			var photo: Node = session.get("_photo")
			photo.set("folder_override", ProjectSettings.globalize_path(OUT + "photos"))
			if words.size() > 1 and words[1] == "on":
				photo.call("enter", true)
			elif words.size() > 1 and words[1] == "off":
				photo.call("leave")
			elif words.size() > 1 and words[1] == "take":
				photo.call("take")
				await get_tree().create_timer(0.5).timeout
			elif words.size() > 4 and words[1] == "fly":
				var cam: Camera3D = photo.get("_camera")
				cam.global_position += cam.global_basis * Vector3(float(words[2]), float(words[3]), float(words[4]))
				cam.global_position = (photo.get("rules") as RefCounted).call("keep_near", player.global_position + Vector3(0, 1.6, 0), cam.global_position)
			elif words.size() > 2 and words[1] == "zoom":
				var lens: Camera3D = photo.get("_camera")
				lens.fov = float((photo.get("rules") as RefCounted).call("zoomed", lens.fov, int(words[2])))
			else:
				_lines.append("PHOTO %s: on %s, paused %s, picture '%s' (%s), camera %.1f m from the head, fov %d, screens hidden %d" % [" ".join(words.slice(1)), str(photo.get("active")), str(get_tree().paused), String(photo.get("last_path")), str(FileAccess.file_exists(String(photo.get("last_path")))), ((photo.get("_camera") as Camera3D).global_position - player.global_position - Vector3(0, 1.6, 0)).length(), int((photo.get("_camera") as Camera3D).fov), (photo.get("_hidden") as Array).size()])
		"course":  # "!course goto n": stand on pad n of the hop course (0 = start); "!course run a b": a scripted hopper (sprint, forward, faces the next pad, perfect hops on small pads, no strafing) from pad a toward pad b; "!course <note>": clock, state, best
			var rules: RefCounted = session.get("_course")
			if words.size() > 2 and words[1] == "goto":
				if session.get("_course_root") == null:
					session.call("_go_to_course")
				session.call("_put_on_course", int(words[2]))
			elif words.size() > 3 and words[1] == "run":
				if session.get("_course_root") == null:
					session.call("_go_to_course")
				session.call("_put_on_course", int(words[2]))
				await get_tree().create_timer(0.5, true, false, true).timeout
				var root: Node3D = session.get("_course_root")
				var pads: Array = rules.get("pads")
				var last := int(words[2])
				var goal := int(words[3])
				var log_text := PackedStringArray()
				var began := Time.get_ticks_msec()
				var top := 0
				Input.action_press("move_forward")
				Input.action_press("sprint")
				while Time.get_ticks_msec() - began < 60000 and last < goal:
					var local: Vector3 = player.global_position - root.position
					if local.y < -2.0:
						log_text.append("FELL after pad %d" % last)
						break
					var flight: Vector3 = player.get("velocity")
					var speed := Vector2(flight.x, flight.z).length()
					top = maxi(top, int(player.call("speed_units")))
					var target: Dictionary = pads[mini(last + 1, pads.size() - 1)]
					var aim := Vector3(float(target["at"][0]), 0.0, float(target["at"][1]))
					if player.is_on_floor():
						var under := int(rules.call("pad_at", local.x, local.z))
						if under > last:
							last = under
							log_text.append("pad %d at %.2f s, %d u/s" % [under, float(Time.get_ticks_msec() - began) / 1000.0, int(player.call("speed_units"))])
							if last >= goal:
								break
							target = pads[mini(last + 1, pads.size() - 1)]
							aim = Vector3(float(target["at"][0]), 0.0, float(target["at"][1]))
						player.call("look_at_point", root.position + aim + Vector3(0, 1.6, 0))
						var here: Dictionary = pads[maxi(under, 0)]
						var small := maxf(float(here["size"][0]), float(here["size"][1])) <= 2.5 and String(here["kind"]) == "pad"
						var ahead := local + Vector3(flight.x, 0.0, flight.z) * 0.06
						var leaving := int(rules.call("pad_at", ahead.x, ahead.z)) != under
						var far := Vector2(aim.x - local.x, aim.z - local.z).length()
						if small or leaving or (far <= speed * 0.72 and far > 1.0):
							_tap("jump", true)
							await get_tree().process_frame
							_tap("jump", false)
					else:  # in the air: hold back while the flight would carry well past the target's middle (as a player brakes)
						var fall_left := (flight.y + sqrt(maxf(flight.y * flight.y + 2.0 * 20.32 * maxf(local.y, 0.0), 0.0))) / 20.32
						var landing := Vector2(local.x + flight.x * fall_left, local.z + flight.z * fall_left)
						var past := (landing - Vector2(aim.x, aim.z)).dot(Vector2(flight.x, flight.z).normalized()) if speed > 0.1 else 0.0
						if past > 0.8:
							Input.action_release("move_forward")
							Input.action_press("move_back")
						else:
							Input.action_release("move_back")
							Input.action_press("move_forward")
					await get_tree().process_frame
				Input.action_release("move_forward")
				Input.action_release("move_back")
				Input.action_release("sprint")
				_lines.append("COURSE RUN %s -> %s: reached pad %d, top %d u/s; %s" % [words[2], words[3], last, top, "; ".join(log_text)])
			else:
				_lines.append("COURSE %s: state %s, clock %.2f, checkpoint %d, best %.2f, last %.2f, on course %s, even ground %s, hud '%s'" % [" ".join(words.slice(1)), String(rules.get("state")), float(rules.get("time")), int(rules.get("checkpoint")), float(rules.get("best")), float(rules.get("last")), str(session.get("_on_course")), str(player.get("even_ground")), String((session.get("_player_hud") as Node).get("course_text"))])
		"net":  # "!net wait_guest": wait (up to 120 s) until a second player is in the session; "!net <note>": who is connected
			var link: Node = session.get("net")
			if words.size() > 1 and words[1] == "to_other":  # "!net to_other": stand 1 m from the other player, facing them
				for id: int in (link.get("roster") as Dictionary):
					var body: Node3D = link.call("player_node", id)
					if id != int(link.call("my_id")) and body != null:
						player.call("teleport", body.global_position + Vector3(0, 0.2, 1.0), 0.0)
						break
			if words.size() > 1 and words[1] == "leave":  # "!net leave": this player quits the session (a host leaving: the others migrate)
				link.call("leave", "")
				return
			if words.size() > 1 and words[1] == "wait_host":  # "!net wait_host [s]": wait until this machine hosts (after a migration)
				var began_h := Time.get_ticks_msec()
				while not (bool(link.call("is_host")) and bool(link.call("can_send")) and not bool(link.call("is_migrating"))) and Time.get_ticks_msec() - began_h < (int(words[2]) if words.size() > 2 else 60) * 1000:
					await get_tree().create_timer(0.5, true, false, true).timeout
			if words.size() > 1 and words[1] == "askbuild":  # "!net askbuild <ship>": ask the host to launch that ship (as the shipyard does after building it)
				(link.get("sea") as Node).call("request_build", words[2])
				return
			if words.size() > 1 and words[1] == "claims":  # "!net claims <note>": the host's guest-claim records (sea step 12c)
				var parts_c := PackedStringArray()
				var now_c := Time.get_ticks_msec() / 1000.0
				for pid: int in (link.get("claims") as Dictionary):
					var cl: RefCounted = link.get("claims")[pid]
					parts_c.append("%d: sailing %d (now up to %d), carpentry %d (now up to %d)" % [pid, int(cl.call("level_at_join", "sailing")), int(cl.call("allowed_level", "sailing", now_c)), int(cl.call("level_at_join", "carpentry")), int(cl.call("allowed_level", "carpentry", now_c))])
				var fl_c: Node = (session.call("sea") as Node).get("ships") if session.call("sea") != null else null
				_lines.append("CLAIMS %s: refused %d, ships %d | %s" % [" ".join(words.slice(2)), int(link.get("claims_refused")), (fl_c.get("ships") as Array).size() if fl_c != null else -1, "; ".join(parts_c)])
				return
			if words.size() > 1 and words[1] == "mig":  # "!net mig <note>": the sea as this machine holds it (sea step 12 migration checks)
				var sea_m: Node = session.call("sea")
				var fleet_m: Node = sea_m.get("ships") if sea_m != null else null
				var line_m := "no sea"
				if fleet_m != null:
					var foes_m: Node = fleet_m.get("foes")
					var men_m: Dictionary = (foes_m.get("crews") as Node).get("men")
					var puppets := 0
					for mid: int in men_m:
						if is_instance_valid(men_m[mid]["enemy"]) and bool((men_m[mid]["enemy"] as Node).get("puppet")):
							puppets += 1
					var ships_m: Array = fleet_m.get("ships")
					var foe_n := 0
					for sh: Node3D in ships_m:
						if (sh.get("state") as Dictionary).has("foe"):
							foe_n += 1
					var s0: Dictionary = (ships_m[0] as Node3D).get("state") if not ships_m.is_empty() else {}
					line_m = "ships %d (foes %d), ship 0 at %.0f %.0f speed %.1f hull %.0f, crews %d (puppets %d), flotsam %d, adopted %d, frozen %s, town %s" % [ships_m.size(), foe_n, float(s0.get("x", 0.0)), float(s0.get("z", 0.0)), float(s0.get("speed", 0.0)), float(s0.get("hull", 0.0)),
						men_m.size(), puppets, ((foes_m.get("flotsam") as Node).get("pieces") as Dictionary).size(), int(link.get("sea").get("adopted")), str(sea_m.get("frozen")), str((sea_m.get("town") as Node).call("world_dict").get("levels", "?"))]
				_lines.append("MIG %s: host %s, migrating %s, my id %d, roster %s | %s" % [" ".join(words.slice(2)), str(link.call("is_host")), str(link.call("is_migrating")), int(link.call("my_id")), str((link.get("roster") as Dictionary).keys()), line_m])
				return
			if words.size() > 1 and words[1] == "wait_guest":
				var began := Time.get_ticks_msec()
				while (link.get("roster") as Dictionary).size() < 2 and Time.get_ticks_msec() - began < 120000:
					await get_tree().create_timer(0.5, true, false, true).timeout
			var shared: Node = link.get("rounds")
			_lines.append("NET %s: can send %s, host %s, my id %d, roster %s, ghosts %d, net enemies %d, states seen %d, last run '%s'" % [" ".join(words.slice(1)), str(link.call("can_send")), str(link.call("is_host")), int(link.call("my_id")), str(link.get("roster")), (link.call("target_nodes") as Array).size(), (shared.get("_enemies") as Dictionary).size(), int(shared.get("states_seen")), String(session.get("run_note"))])
		"trade":  # online trading: "!trade ask <name>", "!trade yes" (answer an ask), "!trade gun" (offer the first rolled gun in the bag), "!trade card <id>" (offer one copy), "!trade ready", "!trade confirm", "!trade <note>"
			var ts: Control = session.get("_trade_screen")
			var inv: RefCounted = player.get("inventory")
			match words[1]:
				"ask":
					_lines.append("TRADE ask: %s" % String(session.call("_trade_by_name", words[2])))
				"yes":
					((session.get("net") as Node).get("trade") as Node).call("answer", true)
				"wait_ask", "wait_open":  # wait (up to 30 s) until somebody asks us / the trade window is open
					var began := Time.get_ticks_msec()
					while Time.get_ticks_msec() - began < 30000:
						if (words[1] == "wait_ask" and String(session.get("_trade_asker")) != "") or (words[1] == "wait_open" and bool(ts.call("is_open"))):
							break
						await get_tree().create_timer(0.25, true, false, true).timeout
				"gun":
					for slot in 36:
						var g: Dictionary = inv.call("gun_at", slot)
						if not g.is_empty():
							ts.offered.emit({"ref": slot, "gun": g})
							break
				"card":
					(ts.get("offered_cards") as Dictionary)[1000] = {"card": words[2], "finish": "", "leader": false}
					ts.offered.emit({"ref": 1000, "card": words[2], "finish": "", "leader": false})
				"ready":
					ts.ready_set.emit(true)
				"confirm":
					ts.confirmed.emit()
				_:
					var guns := 0
					for slot in 36:
						if not (inv.call("gun_at", slot) as Dictionary).is_empty():
							guns += 1
					var owned: RefCounted = session.get("_cards")
					_lines.append("TRADE %s: window open %s, rolled guns %d, harbor_gull %d, total cards %d" % [" ".join(words.slice(1)), str(ts.call("is_open")), guns, int(owned.call("count", "harbor_gull")), int(owned.call("total")) if owned.has_method("total") else -1])
		"hurt":  # "!hurt 40": we take that much damage (going down online needs it)
			player.call("take_damage", float(words[1]))
		"downs":  # "!downs <note>": who is down or out online, whether we lie down, our health; "!downs wait_down" waits (up to 60 s) until somebody is down, "!downs wait_up" until we are up again
			var dl: Node = session.get("net")
			if words.size() > 1 and words[1] in ["wait_down", "wait_up"]:
				var began := Time.get_ticks_msec()
				while Time.get_ticks_msec() - began < 60000:
					var lying: bool = (dl.get("downs") as Node).get("states").values().has("down")
					if (words[1] == "wait_down" and lying) or (words[1] == "wait_up" and not bool(player.get("downed"))):
						break
					await get_tree().create_timer(0.25, true, false, true).timeout
			_lines.append("DOWNS %s: states %s, me downed %s, hp %d, revives %d, downs %d" % [" ".join(words.slice(1)), str((dl.get("downs") as Node).get("states")), str(player.get("downed")), int(player.get("health").hp), int(session.call("score").get("revives")), int(session.call("score").get("downs"))])
		"go":  # "!go club": travel there without the chat command (a joiner may not use /tp)
			session.call("travel", words[1])
		"immortal":  # "!immortal": no damage taken, also on a joiner (where /god is the host's to give); "!immortal off" ends it
			player.set("cheat_god", not (words.size() > 1 and words[1] == "off"))
		"wkills":  # "!wkills 5": the rolled gun in hand gets the W kills counter at 5 (a plain gun becomes a rolled one first); "!wkills <note>": what it shows
			var hand_now := int(player.call("hand_index"))
			var bag: RefCounted = player.get("inventory")
			if words.size() > 1 and words[1].is_valid_int() and hand_now >= 0:
				var gun: Dictionary = bag.call("holster_gun", hand_now)
				if gun.is_empty():
					gun = load("res://core/gun_gen.gd").call("generate", player.get("gun_db"), RandomNumberGenerator.new(), 0.0, String(bag.call("holster_body", hand_now)), "purple")
					bag.call("set_holster_gun", hand_now, gun)
				gun["wkills"] = int(words[1])
				player.call("refresh_held")
			else:
				var held: Dictionary = bag.call("holster_gun", hand_now) if hand_now >= 0 else {}
				_lines.append("WKILLS %s: gun in hand '%s', counter %s" % [" ".join(words.slice(1)), String(load("res://core/gun_stats.gd").call("display_name", player.get("gun_db"), held)) if not held.is_empty() else "plain", str(held.get("wkills", "none"))])
		"card":  # "!card 4": the player card (P) open on tab 4 (0 = Card ... 4 = Combat Report); "!card close"; "!card <note>": the record's main numbers
			var screen: Control = session.get("_card_screen")
			if words.size() > 1 and words[1] == "close":
				screen.call("close")
			elif words.size() > 1 and words[1].is_valid_int():
				session.call("_open_card")
				await get_tree().process_frame
				(screen.get("_tabs") as TabContainer).current_tab = int(words[1])
			else:
				var book: RefCounted = session.get("_stats")
				_lines.append("CARD %s: totals %s | kills by enemy %s | by weapon %s | gathered %s | spells %s" % [" ".join(words.slice(1)), JSON.stringify(book.get("totals")), str(book.call("group", "kills_by_enemy")), str(book.call("group", "kills_by_weapon")), str(book.call("group", "gathered")), str(book.call("group", "spells"))])
		"mouse":  # "!mouse 300 400": the mouse moves to that window spot (tooltips show after their delay)
			var at := Vector2(float(words[1]), float(words[2]))
			get_viewport().warp_mouse(at)
			var motion := InputEventMouseMotion.new()
			motion.position = at
			motion.global_position = at
			motion.relative = Vector2(1, 0)
			get_viewport().push_input(motion)
		"record":  # "!record kills 500" / "!record kills_by_enemy:harvest_king 1": adds to the combat record (core/stat_book.gd)
			var book: RefCounted = session.get("_stats")
			if words[1].contains(":"):
				book.call("add_to", words[1].get_slice(":", 0), words[1].substr(words[1].find(":") + 1), float(words[2]))
			else:
				book.call("add", words[1], float(words[2]))
		"ach":  # "!ach <note>": reads the stat achievements now and lists what is unlocked; "!ach wear <emblem> <title>": puts them on the card
			session.call("_read_achievements")
			var progress: RefCounted = session.get("_progress")
			if words.size() > 3 and words[1] == "wear":
				progress.call("set_card", progress.get("callsign"), words[2], words[3])
			elif words.size() > 2 and words[1] == "grant":  # "!ach grant n": the first n achievements count as earned today (trophy room pictures)
				var all: Dictionary = (progress.get("_ach") as Dictionary)["achievements"]
				var n := 0
				for id: String in all:
					if n >= int(words[2]):
						break
					if not (progress.get("unlocked") as Array).has(id):
						progress.call("_unlock", id)
					n += 1
			_lines.append("ACH %s: %d unlocked %s | emblem %s title %s" % [" ".join(words.slice(1)), (progress.get("unlocked") as Array).size(), str(progress.get("unlocked")), str(progress.get("emblem")), str(progress.get("title"))])
		"jukebox":  # "!jukebox goto": stand in front of the club's jukebox
			var box: Node3D = session.get("_jukebox")
			if box != null:
				player.call("teleport", box.global_position + box.global_transform.basis.z * -1.8 + Vector3(0, 0.1, 0), 0.0)
				player.call("look_at_point", box.global_position + Vector3(0, 1.0, 0))
		"smoke":  # "!smoke 5": the cigarette being smoked has 5 s left; "!smoke <note>": what is in the mouth, seconds left, the HUD bar, whether the model shows
			var smoke: RefCounted = session.get("_smoke")
			if words.size() > 1 and words[1].is_valid_float():
				smoke.set("left", float(words[1]))
			else:
				var mouth: Dictionary = ((player.get("inventory") as RefCounted).get("equipment") as Dictionary).get("mouth", {})
				var hud: Node = session.get("_player_hud")
				_lines.append("SMOKE %s: mouth '%s', left %.1f s, bar %.3f%s, smoking %s, bag cigarettes %d, butts %d" % [" ".join(words.slice(1)), String(mouth.get("id", "")), float(smoke.get("left")), float(hud.get("cigarette")), " (red)" if bool(hud.get("cigarette_warn")) else "", str(player.call("smoking")),
					int((player.get("inventory") as RefCounted).call("count_of", "cigarette")), int((player.get("inventory") as RefCounted).call("count_of", "cigarette_butt"))])
		"wear":  # "!wear steel_chestplate+holster": that armour item is put on (as if dragged onto its slot)
			var bag: RefCounted = player.get("inventory")
			var slot := String((player.get("items") as RefCounted).call("equip_slot", words[1]))
			(bag.get("equipment") as Dictionary)[slot] = {"id": words[1], "count": 1}
			session.call("_on_inventory_changed")
		"pachinko":  # "!pachinko": stand in front of the casino's pachinko wall (the chips show at the top right there)
			var wall: Node3D = session.get("_pachinko")
			if wall != null:
				player.global_position = wall.global_position + wall.global_basis.z * 4.0
		"tcg":  # "!tcg tide [auto]": stand at the card table, sit, start a match with that starter (auto = the AI plays our side too); "!tcg esc" = press Esc there; "!tcg move" = our next move as a click; "!tcg shop [buy <item>]" = the card machine; "!tcg binder [decks]" = the binder; "!tcg look" = view of the tables; "!tcg put <card> [foe]" = a creature onto the mat; "!tcg mat <id>" = own and lay that play mat; "!tcg ptable <i> / pdeck / pmove / pnote" = the player tables online; "!tcg note" = the match in one line
			var tcg: Node = session.get("_tcg")
			if words[1] == "note":
				var m: RefCounted = tcg.get("match_state")
				if m == null:
					_lines.append("TCG: hovered %s" % str(get_viewport().gui_get_hovered_control()))
					_lines.append("TCG: no match, seated %s, chips %d" % [str(tcg.call("is_open")), int((session.get("_wallet") as RefCounted).get("balance"))])
				else:
					var sd: Array = m.get("sides")
					var hov := get_viewport().gui_get_hovered_control()
					_lines.append("TCG: hovered %s %s, viewport %s" % [str(hov), str(hov.get_path()) if hov != null else "", str(get_viewport().get_visible_rect())])
					_lines.append("TCG: phase %s turn %d current %d winner %d | me %s hp %d mana %d/%d hand %d board %d deck %d | dealer %s hp %d hand %d board %d deck %d | chips %d" % [m.get("phase"), int(m.get("turn")), int(m.get("current")), int(m.get("winner")),
						sd[0]["leader"], int(sd[0]["hp"]), int(sd[0]["mana"]), int(sd[0]["crystals"]), (sd[0]["hand"] as Array).size(), (sd[0]["board"] as Array).size(), (sd[0]["deck"] as Array).size(),
						sd[1]["leader"], int(sd[1]["hp"]), (sd[1]["hand"] as Array).size(), (sd[1]["board"] as Array).size(), (sd[1]["deck"] as Array).size(), int((session.get("_wallet") as RefCounted).get("balance"))])
			elif words[1] == "esc":
				tcg.call("request_close")
			elif words[1] == "shop":  # stand at the card vending machine and open it; "!tcg shop buy <item>" buys too
				var shop: Node = session.get("_shop")
				if words.size() > 2 and words[2] == "close":
					shop.call("close")
					return
				var machine: Node3D = (session.get("_casino") as Dictionary).get("card_vendor")
				player.call("teleport", machine.call("front") + Vector3(0, 0.1, 0), 0.0)
				player.call("look_at_point", machine.global_position + Vector3(0, 1.4, 0))
				shop.call("open")
				if words.size() > 3:
					shop.call("_on_buy", words[3])
					var owned: RefCounted = session.get("_cards")
					_lines.append("TCG SHOP %s: packs %d, box %s, chips %d" % [words[3], int(owned.call("pack_count")), str(owned.get("box")), int((session.get("_wallet") as RefCounted).get("balance"))])
			elif words[1] == "sit":  # "!tcg sit": sit at the House Dealer's table (the deck pick shows)
				var sit_table: Node3D = (session.get("_casino") as Dictionary).get("card_table")
				player.call("teleport", sit_table.global_position + Vector3(0, 0.1, -1.6), 0.0)
				tcg.call("open")
			elif words[1] == "look":  # "!tcg look": stand on the beach looking at the four card tables
				var house_table: Node3D = (session.get("_casino") as Dictionary).get("card_table")
				player.call("teleport", house_table.global_position + Vector3(-1.8, 0.1, -3.2), 0.0)
				player.call("look_at_point", house_table.global_position + Vector3(-1.8, 0.4, 1.5))
			elif words[1] == "binder":  # "!tcg binder [decks]": the player card's Binder tab (owning the Tide starter at least); "decks" = the builder on slot 1
				if words.size() > 2 and words[2] == "close":
					session.get("_card_screen").call("close")
					return
				var owned: RefCounted = session.get("_cards")
				if String(owned.get("starter")) == "":
					var starters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/starters.json"))["starters"]
					owned.call("give_starter", "tide", starters["tide"], "standard")
					owned.call("add", "harbor_gull", "rainbow")
				session.call("_open_card")
				var screen: Node = session.get("_card_screen")
				var tabs: TabContainer = screen.get("_tabs")
				tabs.current_tab = tabs.get_tab_count() - 1
				if words.size() > 2:
					screen.get("_binder").call("_open_slots")
			elif words[1] == "packs":  # "!tcg packs [half | tear | turn | all]": 3 more packs and the opening from the binder; then the drag / a click / Open all done for us
				var screen: Node = session.get("_card_screen")
				var binder: Node = screen.get("_binder")
				var opening: Node = binder.get("_opening") if binder != null else null
				if words.size() == 2:
					(session.get("_cards") as RefCounted).call("add_pack", "standard", 3)
					session.call("_open_card")
					var tabs: TabContainer = screen.get("_tabs")
					tabs.current_tab = tabs.get_tab_count() - 1
					binder = screen.get("_binder")
					binder.call("refresh")
					(binder.get("_open_button") as Button).pressed.emit()
				elif opening != null:
					opening.call("dev_step", words[2])
			elif words[1] == "mat":  # "!tcg mat <id>": own that play mat and lay it as ours
				var mb: GDScript = load("res://core/tcg/mat_book.gd")
				var mats_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/mats.json"))
				mb.call("give", session.get("_cards"), words[2])
				mb.call("choose", session.get("_cards"), mats_cfg, words[2])
				_lines.append("TCG MAT %s: now %s" % [words[2], mb.call("current", session.get("_cards"), mats_cfg)])
			elif words[1] == "foil":  # "!tcg foil <card> <rainbow|pony>": that card looks like that foil on our side of the House table
				((tcg.get("_screen") as Control).get("finishes")[0] as Dictionary)[words[2]] = words[3]
			elif words[1] == "put":  # "!tcg put <card> [foe]": a creature onto our side (or the dealer's) of the running match, then a redraw
				var m2: RefCounted = tcg.get("match_state")
				if m2 != null:
					m2.call("summon", 1 if words.size() > 3 and words[3] == "foe" else 0, words[2])
					tcg.call("_after_move")
			elif words[1] in ["ptable", "pdeck", "pmove", "pnote"]:  # player tables online: "!tcg ptable <i>" sit (0-1 the hub's, 2-4 the beach's), "pdeck" first deck slot, "pmove" the AI's move for us, "pnote" the state
				var pt: Node = session.get("_ptables")
				if words[1] == "ptable":
					var spot: Node3D = (pt.get("_tables") as Array)[int(words[2])]
					player.call("teleport", spot.global_position + spot.global_basis * Vector3(0, 0.1, -1.6), 0.0)
					pt.call("open", int(words[2]))
				elif words[1] == "pdeck":
					pt.call("_on_deck", "slot:0")
				elif words[1] == "pmove":
					var mir: RefCounted = pt.get("_mirror")
					if mir != null:
						var side := int(pt.get("_side"))
						if String(mir.get("phase")) == "mulligan":
							pt.call("_send", {"do": "mulligan", "indices": []})
						elif int(mir.get("current")) == side and String(mir.get("phase")) == "play":
							pt.call("_send", load("res://core/tcg/ai_player.gd").call("next_move", mir, side))
				else:
					var mir2: RefCounted = pt.get("_mirror")
					_lines.append("PTABLE %s: at %d watching %s side %d seats %s | %s" % [" ".join(words.slice(2)), int(pt.get("_at")), str(pt.get("_watching")), int(pt.get("_side")), str(pt.get("_seats")),
						"no match" if mir2 == null else "phase %s turn %d current %d winner %d hp %d/%d boards %d/%d" % [mir2.get("phase"), int(mir2.get("turn")), int(mir2.get("current")), int(mir2.get("winner")), int(mir2.get("sides")[0]["hp"]), int(mir2.get("sides")[1]["hp"]), (mir2.get("sides")[0]["board"] as Array).size(), (mir2.get("sides")[1]["board"] as Array).size()]])
					var rec: Dictionary = (session.get("_cards") as RefCounted).get("record")
					_lines.append("PTABLE record: wins %d losses %d vs %s, chips %d" % [int(rec["wins"]), int(rec["losses"]), str(rec["vs"]), int((session.get("_wallet") as RefCounted).get("balance"))])
			elif words[1] == "move":  # our side: the move the AI would make, sent as if clicked (or keep the opening hand)
				tcg.call("dev_move")
			else:
				var table: Node3D = (session.get("_casino") as Dictionary).get("card_table")
				player.call("teleport", table.global_position + Vector3(0, 0.1, -1.6), 0.0)
				tcg.call("dev_start", words[1], words.size() > 2 and words[2] == "auto")
		"take":  # "!take <item id>": walk onto the nearest lying drop of that item and pick it up; logs how many we carry after
			var field: Node = session.get("_field")
			for d: Dictionary in field.get("_drops"):
				if String(d.get("item", "")) == words[1]:
					player.global_position = (d["node"] as Node3D).global_position
					session.call("_pick_up", d)
					break
			var bag: RefCounted = player.get("inventory")
			_lines.append("TAKE %s: carrying %d" % [words[1], int(bag.call("count_of", words[1]))])
		"slay":  # every enemy takes a blow it cannot survive (real kills: points, drops, the wave goes on)
			for enemy: Variant in (session.call("director").call("enemy_list") as Array).duplicate():
				if is_instance_valid(enemy):
					(enemy as Node3D).call("on_hit", 1000000.0, (enemy as Node3D).global_position + Vector3(0, 1, 0), Vector3.UP)
		"arena":  # "!arena <note>": the run's wave, who is alive with how much health, what lies about, our points and ready slots
			var waves: Node = session.call("director")
			var alive := PackedStringArray()
			for enemy: Variant in waves.call("enemy_list"):
				if is_instance_valid(enemy):
					var hp: RefCounted = (enemy as Node).get("health")
					var marks := ("P" if bool((enemy as Node).get("puppet")) else "") + ("I" if (enemy as Node).has_meta("island") else "") + ("A" if (enemy as Node).has_meta("arena") else "") + ("#%d" % int((enemy as Node).get_meta("net_id")) if (enemy as Node).has_meta("net_id") else "")
					alive.append("%s%s %.0f/%.0f %s" % [String((enemy as Node).get("enemy_id")), "" if String((enemy as Node).get("elite")) == "" else "(" + String((enemy as Node).get("elite")) + ")", float(hp.get("hp")), float(hp.get("max_hp")), marks])
			var lying := PackedStringArray()
			for drop: Dictionary in (session.get("_field") as Node).get("_drops"):
				lying.append(String(drop["item"]) if drop.has("item") else String((drop["gun"] as Dictionary)["tier"]))
			_lines.append("ARENA %s: in arena %s, wave %d of %d, left %d, cleared %s | alive [%s] | lying [%s] | points %d, ready slots %d, mods %s" % [" ".join(words.slice(1)), str(session.get("_in_arena")), int(waves.call("wave_number")), int(waves.call("wave_count")), int(waves.call("enemies_left")), str(waves.call("is_cleared")),
				", ".join(alive), ", ".join(lying), int((session.call("score") as RefCounted).get("points")), int((player.get("inventory") as RefCounted).get("holster_count")), str(session.get("_run_mods"))])
		"weather":  # "!weather <note>": the islands' weather on screen now (stage, fog, sun, rain drops, the looping sound)
			_lines.append("WEATHER %s: %s" % [" ".join(words.slice(1)), String(session.call("weather_note"))])
		"powers":  # "!powers <note>": the power-ups lying around and running, and what points are multiplied by; "!powers goto": stand on the first one lying
			if words.size() > 1 and words[1] == "goto":
				var field: Node = session.get("_power_field")
				var ids: PackedInt32Array = field.get("_ids")
				for i in ids.size():
					if ids[i] != 0:
						player.call("teleport", (field.get("_holders")[i] as Node3D).global_position + Vector3(0, 0.2, 0), 0.0)
						break
				return
			var rules: RefCounted = session.get("_powerups")
			var running := PackedStringArray()
			for kind: String in rules.call("timed"):
				if bool(rules.call("is_on", kind, float(session.get("_time")))):
					running.append("%s %.0f s" % [kind, float(rules.call("left", kind, float(session.get("_time"))))])
			var card: RefCounted = session.call("score")
			_lines.append("POWERS %s: lying %d | running [%s] | points x%d = %d | enemies %d" % [" ".join(words.slice(1)), int((session.get("_power_field") as Node).call("count")), ", ".join(running), int(card.get("mult")), int(card.get("points")), (session.call("director").call("enemy_list") as Array).size()])
		"watch":  # "!watch": the camera follows the nearest enemy as it would a teammate while we are out of the round; "!watch off": back to our own eyes
			var seen: Node3D = null
			if words.size() < 2 or words[1] != "off":
				for enemy: Variant in session.call("director").call("enemy_list"):
					if is_instance_valid(enemy) and (seen == null or (enemy as Node3D).global_position.distance_to(player.global_position) < seen.global_position.distance_to(player.global_position)):
						seen = enemy
			player.call("watch", seen)
			_lines.append("WATCH %s" % ("off" if seen == null else "the nearest enemy, %.0f m away" % seen.global_position.distance_to(player.global_position)))
		"pack":  # "!pack <note>": is a backpack lying, where and with how much; what is in the holsters and the bag. "!pack goto": stand next to it
			var lying: Node3D = session.get("_pack")
			if words.size() > 1 and words[1] == "goto":
				if lying != null:
					player.call("teleport", lying.global_position + Vector3(0.8, 0.3, 0.0), 0.0)
			else:
				var bag: RefCounted = player.get("inventory")
				var in_bag := 0
				for i in 36:
					in_bag += 0 if String(bag.call("item_id", i)) == "" else 1
				var ready_now := PackedStringArray()
				for i in int(bag.get("holster_count")):
					ready_now.append(String(bag.call("holster_body", i)) if String(bag.call("holster_body", i)) != "" else "-")
				_lines.append("PACK %s: %s; holsters [%s], %d stacks in the bag, best round %d, downs %d, game-over screen %s" % [" ".join(words.slice(1)), "none lying" if lying == null else "lying %.0f m away with %d things" % [lying.global_position.distance_to(player.global_position), (lying.get("bundle")["things"] as Array).size()], ", ".join(ready_now), in_bag, int(session.get("_best_round")), int(session.call("score").get("downs")), "up" if (session.get("_game_over") as Control).visible else "gone"])
		"bank":  # "!bank goto" stand at the bank, "!bank click 3" a click on its slot 3, "!bank upgrade" its button, "!bank <note>" what is in it
			var vault: RefCounted = session.get("_bank")
			match words[1] if words.size() > 1 else "":
				"goto":
					player.call("teleport", (session.get("_bank_pos") as Vector3) + Vector3(-1.2, 0.2, 0.6), 0.0)
				"click":
					vault.call("click", int(words[2]), player.get("inventory"))
					session.call("_on_inventory_changed")
				"upgrade":
					session.call("_on_bank_upgrade")
				_:
					_lines.append("BANK %s: %d of %d slots used, next upgrade %s, points %d" % [" ".join(words.slice(1)), int(vault.call("used")), int(vault.call("capacity")), str(vault.call("next_upgrade")), int(session.call("score").get("points"))])
		"rounds":  # "!rounds <note>": the island's round, its kind, what is left and alive, and how far away and how deep the living are
			var island: Node = session.call("rounds")
			var rules: RefCounted = island.get("rules")
			var spots := PackedStringArray()
			for enemy: Variant in island.get("_alive"):
				if is_instance_valid(enemy):
					spots.append("%s %.0fm y%.1f hp%d%s" % [String(enemy.get("enemy_id")), (enemy as Node3D).global_position.distance_to(player.global_position), (enemy as Node3D).global_position.y, int(enemy.health.hp), " crawling" if bool(enemy.call("crawling")) else ""])
			var nr: Node = (session.get("net") as Node).get("rounds")
			_lines.append("ROUNDS %s: round %d %s, fighting %s, left %d, alive %d [%s], player hp %d | as told by the host: round %d left %d fighting %s, puppets %d" % [" ".join(words.slice(1)), int(rules.get("number")), String(rules.get("kind")), str(rules.call("fighting")), int(island.call("left")), int(island.call("alive")), ", ".join(spots.slice(0, 4)), int(player.get("health").hp),
				int(nr.get("round_number")), int(nr.get("round_left")), str(nr.get("fighting")), (nr.get("_enemies") as Dictionary).size()])
		"ammo":  # "!ammo <note>": what is in hand, the rounds in it and in its pool, every holster, the knife type
			var bag: RefCounted = player.get("inventory")
			var pools: RefCounted = player.get("pools")
			var ready_now := PackedStringArray()
			for i in int(bag.get("holster_count")):
				var body := String(bag.call("holster_body", i))
				ready_now.append("%d:%s loaded %d pool %d/%d" % [i + 1, body if body != "" else "-", int((bag.get("loaded") as Array)[i]), int(pools.call("left", body)), int(pools.call("size_of", body))])
			_lines.append("AMMO %s: in hand %s | %s | knife %s | %d u/s top" % [" ".join(words.slice(1)), String(player.call("held_id")), "; ".join(ready_now), String(player.get("knife")), roundi(float(player.get("_top_units")))])
		"slot":  # "!slot 2": take the gun of holster n (1-4) in hand; "!slot knife": the knife
			player.call("select_hand", -1 if words[1] == "knife" else int(words[1]) - 1)
		"closepanel":
			session.call("fantasy").call("close_panel")
		"accept":
			session.call("fantasy").call("accept", words[1])
		"use":  # fantasy world: eat, equip or light an item from the bag
			_lines.append("use %s -> '%s'" % [words[1], str(session.call("fantasy").call("use_item", words[1]))])
		"make":  # fantasy world: craft a recipe by id (as if standing at its station)
			var land: Node = session.call("fantasy")
			for recipe: Dictionary in land.get("skilling")["recipes"]:
				if String(recipe["id"]) == words[1]:
					_lines.append("make %s -> '%s'" % [words[1], str(land.get("work").call("make", recipe))])
		"above":  # a picture from the air: "!above name [height] [yaw degrees]" looks down at the player's spot from that height and side (no HUD)
			var was := get_viewport().get_camera_3d()
			var high := Camera3D.new()
			get_tree().root.add_child(high)
			var up := float(words[2]) if words.size() > 2 else 60.0
			var turn := deg_to_rad(float(words[3])) if words.size() > 3 else 0.0
			high.global_position = player.global_position + Vector3(sin(turn) * up * 1.3, up, cos(turn) * up * 1.3)
			high.look_at(player.global_position, Vector3.UP)
			high.fov = 60.0
			high.far = was.far
			high.current = true
			var layers: Array = []
			for found in get_tree().root.find_children("*", "CanvasLayer", true, false):
				if (found as CanvasLayer).visible:
					(found as CanvasLayer).visible = false
					layers.append(found)
			for i in 4:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg(OUT + "boot_%s_%s.jpg" % ["forward_plus" if RenderingServer.get_rendering_device() != null else "compatibility", words[1]], 0.9)
			for layer: CanvasLayer in layers:
				layer.visible = true
			was.current = true
			high.queue_free()
		"photo":  # a clean picture for the loading screens (no HUD, no held gun): assets/ui/loading/<name>.jpg, listed in data/loading.json
			var old := get_viewport().get_camera_3d()
			var eye := Camera3D.new()
			get_tree().root.add_child(eye)
			eye.global_transform = old.global_transform.translated_local(Vector3(0.0, 0.5, -2.5))  # ahead of the player: nothing of them in view
			eye.fov = 70.0
			eye.far = old.far
			eye.current = true
			var hidden: Array = []
			for found in get_tree().root.find_children("*", "CanvasLayer", true, false):
				if (found as CanvasLayer).visible:
					(found as CanvasLayer).visible = false
					hidden.append(found)
			for i in 4:
				await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/loading/"))
			get_viewport().get_texture().get_image().save_jpg("res://assets/ui/loading/%s.jpg" % words[1], 0.88)
			for layer: CanvasLayer in hidden:
				layer.visible = true
			old.current = true
			eye.queue_free()
			var listed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/loading.json"))
			if not (listed["pictures"] as Array).has(words[1]):
				(listed["pictures"] as Array).append(words[1])
				var list_file := FileAccess.open("res://data/loading.json", FileAccess.WRITE)
				list_file.store_string(JSON.stringify(listed, " "))
				list_file.close()
			_lines.append("photo %s" % words[1])
		"heard":  # which sounds were audible in the last seconds (default 3), for the log
			var board: GDScript = load("res://game/sound_board.gd")
			var list: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sound_list.json"))
			var lately := PackedStringArray()
			for group: Dictionary in list["groups"]:
				for sound: Dictionary in group["sounds"]:
					if bool(board.call("hearing", String(sound["id"]), Time.get_ticks_msec(), int(float(words[1]) * 1000.0) if words.size() > 1 and words[1].is_valid_float() else 3000)):
						lately.append(String(sound["id"]))
			_lines.append("heard %s: %s" % [" ".join(words.slice(1)), ", ".join(lately)])
		"sounds":  # opens the Sounds page of the settings (as Settings > Sounds does); "!sounds off" closes it
			get_parent().call("_show_only", null if words.size() > 1 else get_parent().get("_sound_menu"))
		"loading":  # shows the loading picture as a session start does; "!loading off" lets it fade
			get_parent().get("_loading").call("finish" if words.size() > 1 else "begin", 4)
		"uncap":  # no vsync and no frame cap for the rest of the run, so "!measure" reads what the machine can do
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			_lines.append("window %s, vsync and frame cap off" % str(DisplayServer.window_get_size()))
		"lighting":  # "!lighting realistic": the lighting preset for the rest of the run (the settings FILE is not touched)
			(session.get("settings") as RefCounted).set("shaders", words[1])
			session.call("apply_settings")
			_lines.append("lighting %s" % words[1])
		"fx":  # "!fx sdfgi off": one effect of the lighting off or on (ssao, sdfgi, ssr, ssil, fog, glow, msaa, shadows) to see what it costs or causes
			var look: Environment = (session.get("_render_style") as Object).get("env")
			var on := words[2] == "on"
			match words[1]:
				"ssao":
					look.ssao_enabled = on
				"sdfgi":
					look.sdfgi_enabled = on
				"ssr":
					look.ssr_enabled = on
				"ssil":
					look.ssil_enabled = on
				"fog":
					look.volumetric_fog_enabled = on
				"glow":
					look.glow_enabled = on
				"msaa":
					if _msaa < 0:
						_msaa = int(get_viewport().msaa_3d)
					get_viewport().msaa_3d = (_msaa if on else int(Viewport.MSAA_DISABLED)) as Viewport.MSAA
				"shadows":
					for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
						(light as DirectionalLight3D).shadow_enabled = on
			_lines.append("fx %s %s" % [words[1], words[2]])
		"sun":  # "!sun light_angular_distance 0": one property of every sun in the scene, for the rest of the run or until settings are applied again
			for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
				if words[2].contains("."):
					light.set(words[1], float(words[2]))
				else:
					light.set(words[1], int(words[2]))
			_lines.append("sun %s = %s" % [words[1], words[2]])
		"nodes":  # where the scene's nodes are: per part of the session and of the fantasy world, and the commonest kinds
			var kinds := {}
			_count_kinds(get_tree().root, kinds)
			var names: Array = kinds.keys()
			names.sort_custom(func(x: String, y: String) -> bool: return int(kinds[x]) > int(kinds[y]))
			var top := PackedStringArray()
			for kind: String in names.slice(0, 14):
				top.append("%s %d" % [kind, int(kinds[kind])])
			_lines.append("NODES by kind: " + ", ".join(top))
			for holder: Variant in [session, session.call("fantasy")]:
				if holder == null:
					continue
				var parts := PackedStringArray()
				for child in (holder as Node).get_children():
					var inside := child.find_children("*", "", true, false).size()
					if inside >= 20:
						parts.append("%s %d" % [child.name, inside])
				_lines.append("NODES under %s: %s" % [(holder as Node).name, ", ".join(parts)])
		"cut":  # "!cut places freeze|hide|off|on": one part of the fantasy world (a field of game/fantasy_world.gd, or "enemies") stops running, stops being drawn, both, or comes back: what does it cost?
			var targets: Array = []
			if words[1] == "enemies":
				targets = session.call("director").call("enemy_list")
			elif words[1] == "others":  # everything of the session that is not the fantasy world or the player: island, club, colosseum ...
				for child in session.get_children():
					if child is Node3D and child != session.call("fantasy") and child != player:
						targets.append(child)
			elif words[1] == "hud":
				targets = session.find_children("*", "CanvasLayer", true, false)
			else:
				targets = [session.call("fantasy").get(words[1])]
			for target: Variant in targets:
				if not is_instance_valid(target):
					continue
				var part := target as Node
				if words[2] == "freeze" or words[2] == "off":
					part.process_mode = Node.PROCESS_MODE_DISABLED
				if (words[2] == "hide" or words[2] == "off") and (part is Node3D or part is CanvasItem):
					part.set("visible", false)
				if words[2] == "on":
					part.process_mode = Node.PROCESS_MODE_INHERIT
					part.set("visible", true)
			_lines.append("cut %s %s (%d)" % [words[1], words[2], targets.size()])
		"gi":  # the bounce light's cost knobs: "!gi half on|off" (half resolution), "!gi rays 0-6", "!gi converge 0-5", "!gi update 0-4" (engine quality steps), "!gi cascades n", "!gi cell metres"
			var mood: Environment = (session.get("_render_style") as Object).get("env")
			match words[1]:
				"half":
					RenderingServer.gi_set_use_half_resolution(words[2] == "on")
				"rays":
					RenderingServer.environment_set_sdfgi_ray_count(int(words[2]) as RenderingServer.EnvironmentSDFGIRayCount)
				"converge":
					RenderingServer.environment_set_sdfgi_frames_to_converge(int(words[2]) as RenderingServer.EnvironmentSDFGIFramesToConverge)
				"update":
					RenderingServer.environment_set_sdfgi_frames_to_update_light(int(words[2]) as RenderingServer.EnvironmentSDFGIFramesToUpdateLight)
				"cascades":
					mood.sdfgi_cascades = int(words[2])
				"cell":
					mood.sdfgi_min_cell_size = float(words[2])
			_lines.append("gi %s %s" % [words[1], words[2]])
		"measure":  # "!measure note": 90 frames of this view into the log: whole frame, GPU, main thread split into drawing and the rest, physics
			var view := get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(view, true)
			for _i in 12:
				await RenderingServer.frame_post_draw
			var began := Time.get_ticks_usec()
			var before := began
			var slowest := 0.0
			var gpu_ms := 0.0
			var draw_cpu_ms := 0.0
			var script_ms := 0.0
			var physics_ms := 0.0
			for _i in 90:
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				slowest = maxf(slowest, float(now - before) / 1000.0)
				before = now
				gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(view)
				draw_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(view) + RenderingServer.get_frame_setup_time_cpu()
				script_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			# TIME_PROCESS is the whole main-thread frame, drawing included: what is left after the drawing is scripts, animation and node upkeep
			_lines.append("MEASURE %s: frame %.2f ms (worst %.1f); gpu %.2f; main thread %.2f = drawing %.2f + scripts and the rest %.2f; physics %.2f; draws %d, tris %d, nodes %d, objects drawn %d; video %.0f MB, ram %.0f MB" % [" ".join(words.slice(1)),
				float(Time.get_ticks_usec() - began) / 90000.0, slowest, gpu_ms / 90.0, script_ms / 90.0, draw_cpu_ms / 90.0, maxf(script_ms - draw_cpu_ms, 0.0) / 90.0, physics_ms / 90.0,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
		"tier":  # "!tier low": the graphics tier for the rest of the run (the settings FILE is not touched)
			(session.get("settings") as RefCounted).set("graphics", words[1])
			session.call("apply_settings")
			_lines.append("graphics tier %s" % words[1])
		"pick":  # "!pick bounce_light off": one of the player's own graphics choices (data/graphics.json "options") for the rest of the run
			((session.get("settings") as RefCounted).get("picks") as Dictionary)[words[1]] = words[2]
			session.call("apply_settings")
			_lines.append("pick %s = %s" % [words[1], words[2]])
		"menu":  # "!menu settings" / "!menu controls" shows that page (for a picture), "!menu none" hides the menus again
			var main_scene: Node = session.get_parent()
			main_scene.call("_show_only", main_scene.get("_settings_menu") if words[1] == "settings" else (main_scene.get("_controls_menu") if words[1] == "controls" else null))
		"buildings":  # "!buildings full" / "!buildings plain": which building models places built from now on use, whatever the tier says (to measure one against the other)
			(session.call("fantasy").get("places") as Node).set("plain", words[1] == "plain")
			_lines.append("buildings %s" % words[1])
		"ledge":  # "!ledge 0.3": a solid block of that height (4 m wide, 6 m deep) starting 1.3 m ahead of the player (does _step_up climb it or not?)
			var block := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(4.0, float(words[1]), 6.0)
			shape.shape = box
			block.add_child(shape)
			session.add_child(block)
			var forward: Vector3 = -player.global_transform.basis.z
			block.global_position = player.global_position + Vector3(forward.x, 0.0, forward.z).normalized() * 4.3 + Vector3.UP * (float(words[1]) * 0.5 - 0.05)
			_lines.append("ledge %s m ahead, player at height %.2f" % [words[1], player.global_position.y])
		"bind":  # "!bind jump 1 mouse:5": a binding for the rest of the run (slot 0-2; mouse:4 / mouse:5 = wheel up / down), not saved
			var InputSetup: GDScript = load("res://game/input_setup.gd")
			_lines.append("bind %s slot %s = %s (taken from \"%s\")" % [words[1], words[2], words[3], InputSetup.call("bind", session.get("settings"), words[1], int(words[2]), words[3])])
		"hud":  # "!hud round 7 [of 12]", "!hud left 9", "!hud party 3": what the HUD shows of rounds and other players, held for the rest of the run (for pictures before the mode that sets them exists)
			session.set("_hud_timer", -100000.0)  # the session stops refreshing these
			var hud: Control = session.get("_player_hud")
			match words[1]:
				"round":
					hud.set("round_number", int(words[2]))
					hud.set("round_of", int(words[4]) if words.size() > 4 else 0)
				"left":
					hud.set("enemies_left", int(words[2]))
				"party":
					var fake: Array = []
					for i in int(words[2]):
						fake.append({"name": ["Mara", "Okonkwo", "Jules", "Tessa", "Brandt"][i % 5], "points": 2350 - i * 410, "kills": 31 - i * 5, "headshots": 12 - i * 2, "downs": i, "revives": (i * 2) % 3})
					hud.set("party", fake)
		"score":  # "!score <note>": points and the session's kills and headshots into the log
			var card: RefCounted = session.call("score")
			_lines.append("SCORE %s: %s, held hp of nearest %s" % [" ".join(words.slice(1)), str(card.call("row")), str(session.call("director").call("enemy_count"))])
		"place":  # "!place x y z [yaw]": puts the player at a WORLD spot without starting anything (the empty colosseum floor is 0 0.1 10)
			player.call("teleport", Vector3(float(words[1]), float(words[2]), float(words[3])), deg_to_rad(float(words[4])) if words.size() > 4 else 0.0)
		"speed":  # "!speed <note>": ground speed in Source units, what is in hand, fatigue
			var rules: RefCounted = player.get("move")
			_lines.append("SPEED %s: %d u/s, in hand %s, on floor %s, stamina %.1f" % [" ".join(words.slice(1)), int(player.call("speed_units")), String(player.call("held_id")), str(player.is_on_floor()), float(rules.get("stamina"))])
		"jumptest":  # one jump on the spot: how high (units) and how long
			var rules: RefCounted = player.get("move")
			var ground := player.global_position.y
			var top := ground
			var began := Time.get_ticks_msec()
			if words.has("wheel"):  # "!jumptest <note> wheel": the jump comes from one tick of the wheel (down and up in the same frame)
				for pressed: bool in [true, false]:
					var roll := InputEventMouseButton.new()
					roll.button_index = MOUSE_BUTTON_WHEEL_DOWN
					roll.pressed = pressed
					Input.parse_input_event(roll)
			else:
				_tap("jump", true)
			var frames := 0
			while Time.get_ticks_msec() - began < 60000:
				await get_tree().process_frame
				frames += 1
				top = maxf(top, player.global_position.y)
				if player.is_on_floor() and frames > 3:
					break
			Input.action_release("jump")
			_lines.append("JUMP %s: %.1f units high, %.2f s" % [" ".join(words.slice(1)), (top - ground) / float(rules.get("unit")), float(Time.get_ticks_msec() - began) / 1000.0])
		"bhop":  # "!bhop 6 [late_ms] [strafe]": runs up, then hops with no keys held. late 0 = jump is tapped every other frame while falling (what scrolling the wheel does); late_ms = one tap that long after landing; strafe = holds strafe-right and keeps the view on the flight path (flawless air strafing). Logs the speed after each hop.
			var hops := int(words[1])
			var late := int(words[2]) if words.size() > 2 else 0
			var strafe := words.size() > 3
			Input.action_release("jump")
			Input.action_press("move_forward")
			await get_tree().create_timer(1.2, true, false, true).timeout
			var speeds := PackedStringArray([str(int(player.call("speed_units")))])
			_tap("jump", true)
			await get_tree().process_frame
			await get_tree().process_frame
			_tap("jump", false)
			Input.action_release("move_forward")
			if strafe:
				Input.action_press("move_right")
			for hop in hops:
				var began := Time.get_ticks_msec()
				while player.is_on_floor() and Time.get_ticks_msec() - began < 500:
					await get_tree().process_frame  # leaving the ground
				var down := false
				while not player.is_on_floor() and Time.get_ticks_msec() - began < 3000:
					var flight: Vector3 = player.get("velocity")
					if strafe and Vector2(flight.x, flight.z).length() > 0.5:
						player.call("look_at_point", player.global_position + Vector3(flight.x, 0.0, flight.z).normalized() * 20.0 + Vector3(0, 1.6, 0))
					if late == 0 and flight.y < 0.0:
						down = not down
						_tap("jump", down)
					await get_tree().process_frame
				if late > 0:
					await get_tree().create_timer(float(late) / 1000.0, true, false, true).timeout
					_tap("jump", true)
				await get_tree().process_frame
				await get_tree().process_frame
				_tap("jump", false)
				await get_tree().process_frame
				speeds.append(str(int(player.call("speed_units"))))
			Input.action_release("move_right")
			_lines.append("BHOP %s%s: run %s u/s, after each hop %s" % ["tapped while falling" if late == 0 else "%d ms late" % late, ", flawless strafing" if strafe else "", speeds[0], " ".join(speeds.slice(1))])
		"hub":  # the safe hub: "!hub note" = in it? its view in the log; "!hub at x z" = stand at hub metres (from its middle)
			var hub: Node = session.get("net").get("hub")
			if words.size() > 3 and words[1] == "at":
				player.call("teleport", (hub.get("center") as Vector3) + Vector3(float(words[2]), 0.1, float(words[3])), 0.0)
			elif words.size() > 1 and words[1] == "heavy":  # "!hub heavy": the session's children that still draw the most triangles
				var rows: Array = []
				for child: Node in session.get_children():
					var n := _tris_under(child)
					if n > 2000:
						rows.append([n, "%s %s at %s" % [child.name, child.get_class(), str((child as Node3D).global_position.round()) if child is Node3D else "-"]])
				rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
				for r: Array in rows.slice(0, 14):
					_lines.append("HEAVY %d %s" % [int(r[0]), String(r[1])])
			else:
				var style: Node = session.get("_render_style")
				var env: Environment = style.get("env")
				_lines.append("HUB %s: inside %s safe %s dark %s (background %d, ambient %s, sun %.2f, fog %.3f) view %s" % [" ".join(words.slice(1)), str(hub.call("inside", player.global_position)), str(player.get("safe")), str(session.get("_hub_dark")),
					env.background_mode, str(env.ambient_light_color), (style.get("sun") as DirectionalLight3D).light_energy, env.fog_density if env.fog_enabled else 0.0, str(hub.get("view"))])
				var hud: Control = session.get("_hub_hud")
				_lines.append("HUB HUD visible %s in tree %s size %s drawn view %s" % [str(hud.is_visible_in_tree()), str(hud.is_inside_tree()), str(hud.size), str(not (hud.get("view") as Dictionary).is_empty())])
		"where":  # the player's spot for the log: map metres in the fantasy world, world metres elsewhere
			var here: Vector3 = player.global_position
			if session.call("fantasy") != null:
				here = session.call("fantasy").call("player_local")
			_lines.append("at %.1f %.1f (height %.1f) %s" % [here.x, here.z, here.y, " ".join(words.slice(1))])
		"usemove":  # fantasy world: the nearest creature starts its own attack at the player right now (to picture its warning)
			var nearest_one: Node3D = null
			for enemy: Variant in session.call("director").call("enemy_list"):
				if is_instance_valid(enemy) and ((enemy as Node).get("_stats") as Dictionary).has("moves") and (nearest_one == null or (enemy as Node3D).global_position.distance_to(player.global_position) < nearest_one.global_position.distance_to(player.global_position)):
					nearest_one = enemy
			if nearest_one != null:
				session.call("fantasy").get("moves").call("_begin", nearest_one, ((nearest_one.get("_stats") as Dictionary)["moves"] as Array)[0], player.global_position, 7, false)
		"moves":  # fantasy world: which creatures have used their own attack since the last !moves (the first call only starts listening)
			var special: Node = session.call("fantasy").get("moves")
			if not _listening:
				_listening = true
				special.connect("started", func(who: Node3D, index: int, _at: Vector3, _roll: int) -> void:
					_used.append("%s:%s" % [String(who.get("enemy_id")), String(((who.get("_stats") as Dictionary)["moves"] as Array)[index]["id"])]))
			_lines.append("moves %s: %s" % [" ".join(words.slice(1)), ", ".join(_used)])
			_used.clear()
		"cross":  # sea step 11: !cross start | quest (host: the quest's last step done) | near (host: the boat 45 m short of the bank) | ready (boat built, me in its seat or asking for one) | sail (host: the boat into the fog bank) | painting | lectern (stand at the hub's sea painting / NG+ lectern) | back (host: our ship into the home fog) | wait_sea [s] | wait_island [s] | status <note>
			var cr: Node = session.get("_crossing")
			var ccfg_d: Dictionary = cr.get("cfg")
			match words[1] if words.size() > 1 else "status":
				"start":
					cr.call("start")
				"quest":  # (host) the island quest's last step finished the real way: everyone hears, the crossing starts
					var qs: RefCounted = session.get("_quest")
					qs.call("from_dict", {"step": (qs.call("steps") as Array).size() - 1})
					session.call("_quest_advance")
				"near":  # (host) the boat 45 m short of the fog bank, its bow toward it
					var fog_n := Vector2(float(ccfg_d["fog_at"][0]), float(ccfg_d["fog_at"][1]))
					var from_n := Vector2(float(ccfg_d["uboat_from"][0]), float(ccfg_d["uboat_from"][1]))
					var dir_n := (fog_n - from_n).normalized()
					var at_n := fog_n - dir_n * 45.0
					(session.get("_boat") as RefCounted).call("place", at_n, atan2(-dir_n.x, -dir_n.y))
				"ready":
					var bs: RefCounted = session.get("_builds")
					var bt := int(session.get("_boat_thing"))
					if not bool(bs.call("built", bt)):
						for part_n in int(bs.call("part_count", bt)):
							bs.call("take", bt, part_n)
						bs.call("build", bt)
						session.call("_show_builds")
						var link_b: Node = session.get("net")
						if link_b != null and bool(link_b.call("can_send")):
							(link_b.get("rounds") as Node).call("tell_build_state", int(bs.call("to_bits")))
					player.call("teleport", session.call("boat_shore"), 0.0)
					await get_tree().create_timer(0.5, true, false, true).timeout
					session.call("_board_boat")
					await get_tree().create_timer(1.0, true, false, true).timeout
				"sail":
					var boat_r: RefCounted = session.get("_boat")
					var fog_at := Vector2(float(ccfg_d["fog_at"][0]), float(ccfg_d["fog_at"][1]))
					boat_r.call("place", fog_at, 0.0)
				"painting", "lectern":
					var spot_c: Vector3 = session.get("_sea_painting" if words[1] == "painting" else "_ng_lectern")
					player.call("teleport", spot_c + Vector3(1.6, 0.15, 0.0), 0.0)
					await get_tree().create_timer(0.3, true, false, true).timeout
					player.call("look_at_point", spot_c + Vector3(0, 1.2, 0))
				"back":
					var sea_c: Node = session.call("sea")
					var ship_c: Node3D = (sea_c.get("ships") as Node).call("ship_aboard")
					if ship_c == null:
						_lines.append("CROSS back: not aboard a ship")
					else:
						var st_c: Dictionary = ship_c.get("state")
						st_c["x"] = float(ccfg_d["back"]["at"][0])
						st_c["z"] = float(ccfg_d["back"]["at"][1]) - float(ccfg_d["back"]["radius"]) * 0.5
						st_c["speed"] = 0.0
						await get_tree().create_timer(0.5, true, false, true).timeout
						if bool(session.get("_in_sea")):  # (not already sailed back by the ship carrying us in)
							player.call("teleport", ship_c.call("deck_spot", [0.0, -1.0], 0.4), float(st_c["yaw"]))
				"wait_sea", "wait_island":
					var want_sea := words[1] == "wait_sea"
					var began_c := Time.get_ticks_msec()
					while bool(session.get("_in_sea")) != want_sea and Time.get_ticks_msec() - began_c < (int(words[2]) if words.size() > 2 else 30) * 1000:
						await get_tree().create_timer(0.25, true, false, true).timeout
				_:
					var sea_s: Node = session.call("sea")
					var where_s := ""
					if sea_s != null and bool(session.get("_in_sea")):
						var loc: Vector3 = sea_s.call("local_of", player.global_position)
						var ship_s: Node3D = (sea_s.get("ships") as Node).call("ship_aboard")
						var bd: MeshInstance3D = session.get("_backdrop")
						where_s = "sea at %.0f %.0f, aboard %s, fog x%.2f, backdrop %s" % [loc.x, loc.z, "ship" if ship_s != null else "nothing", float((sea_s.get("look") as RefCounted).get("crossing_fog")),
							("alpha %.2f" % (bd.material_override as StandardMaterial3D).albedo_color.a) if bd != null and is_instance_valid(bd) else "none"]
					else:
						var me_c: Vector3 = player.global_position - Vector3(500, 0, 0)
						where_s = "island at %.1f %.1f, weather fog %.3f" % [me_c.x, me_c.z, float(((session.get("_weather") as Node).get("_bank")))]
					_lines.append("CROSS %s: %s | crossed %s, in sea %s, %s | quest step %d, boat built %s seats %s | NG+ %d" % [" ".join(words.slice(2)), String(cr.call("status")), str(session.get("_crossed")), str(session.get("_in_sea")), where_s,
						int((session.get("_quest") as RefCounted).get("step")), str((session.get("_builds") as RefCounted).call("built", int(session.get("_boat_thing")))), str((session.get("_boat") as RefCounted).get("seats")), int(Threat.ng)] + " | island wins %d" % int((session.get("_stats") as RefCounted).call("total", "island_wins")))
		"ng":  # sea step 11: !ng vault (the Vault counts as beaten here) | use (two [F]s at the lectern, wherever we stand) | set <n> | status <note>
			match words[1] if words.size() > 1 else "status":
				"vault":
					session.set("_vault_beaten", true)
				"use":
					session.call("_ng_use")
					session.call("_ng_use")
				"set":
					Threat.ng = int(words[2])
				_:
					var thr: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/encounters.json")) as Dictionary)["threat"]
					_lines.append("NG %s: NG+ %d, vault %s, enemy mult region 1 %.2f region 2 %.2f, sea loot level 20 -> %d, 70 -> %d, luck %.2f | prompt '%s'" % [" ".join(words.slice(2)), Threat.ng, str(session.get("_vault_beaten")),
						Threat.player_mult(thr, 1), Threat.player_mult(thr, 2), Threat.loot_level(20), Threat.loot_level(70), Threat.ng_luck(), String(session.call("_prompt"))])
		"gunfire":  # sea step 12b: !gunfire <note> = bursts sent / heard here and what the copies showed; !gunfire wait <n> [s] = wait until n shots of others were shown
			var nf: Node = get_tree().get_first_node_in_group("net_fire")
			if nf == null:
				_lines.append("GUNFIRE: no net")
			elif words.size() > 2 and words[1] == "wait":
				var began_f := Time.get_ticks_msec()
				while int((nf.get("copies") as Node).get("shown")) + int((nf.get("copies") as Node).get("slow_shown")) < int(words[2]) and Time.get_ticks_msec() - began_f < (int(words[3]) if words.size() > 3 else 40) * 1000:
					await get_tree().create_timer(0.25, true, false, true).timeout
			else:
				_lines.append("GUNFIRE %s: sent %d, heard %d, %s" % [" ".join(words.slice(1)), int(nf.get("sent")), int(nf.get("heard")), String((nf.get("copies") as Node).call("status"))])
		"squad":  # fantasy world: every creature's order, how far it is and where it stands round the player (0 = dead ahead, 180 = behind)
			var command: Node = session.call("fantasy").get("squads")
			var ahead: Vector3 = player.call("view_forward")
			var told := PackedStringArray()
			for enemy: Variant in session.call("director").call("enemy_list"):
				if is_instance_valid(enemy):
					var off: Vector3 = (enemy as Node3D).global_position - player.global_position
					told.append("%s [%s]%s %.0f m at %.0f deg" % [String((enemy as Node).get("enemy_id")), String(command.call("order_of", enemy)), " winding up" if float((enemy as Node).get("_strike_at")) > 0.0 else "", Vector2(off.x, off.z).length(), absf(rad_to_deg(Vector2(ahead.x, ahead.z).angle_to(Vector2(off.x, off.z))))])
			_lines.append("squad %s: %s" % [" ".join(words.slice(1)), "; ".join(told)])
		"marks":  # fantasy world: what lies on the ground, for the log
			var lying: Node = session.call("fantasy").get("marks")
			_lines.append("marks %s: spikes=%d fire=%d water=%d widest water %.1f m" % [" ".join(words.slice(1)), int(lying.call("count_of", "spikes")), int(lying.call("count_of", "fire")), int(lying.call("count_of", "water")), float(lying.call("widest", "water"))])
		"face":  # turn to the nearest creature
			var nearest: Node3D = null
			for enemy: Variant in session.call("director").call("enemy_list"):
				if is_instance_valid(enemy) and (nearest == null or (enemy as Node3D).global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position)):
					nearest = enemy
			if nearest != null and words.size() > 1 and words[1] == "away":  # "!face away" turns our back on it
				player.call("look_at_point", player.global_position * 2.0 - nearest.global_position + Vector3(0, 1.6, 0))
			elif nearest != null:  # "!face head" aims at its head
				player.call("look_at_point", nearest.global_position + Vector3(0, float(nearest.call("head_height")) * (0.93 if words.size() > 1 and words[1] == "head" else 0.55), 0))
		"fight":  # fantasy world: health, mana, ward and the creatures around, for the log
			var hub: Node = session.call("fantasy")
			if not _counting:  # from the first !fight on: how many blows the ward stopped, and how many it threw back
				_counting = true
				hub.get("combat").connect("warded", func(perfect: bool) -> void:
					_wards[1 if perfect else 0] += 1)
			var left := PackedStringArray()
			for enemy: Variant in session.call("director").call("enemy_list"):
				if is_instance_valid(enemy):
					left.append("%s %d (%.0f m)" % [String((enemy as Node).get("enemy_id")), int((enemy as Node).get("health").hp), (enemy as Node3D).global_position.distance_to(player.global_position)])
			_lines.append("fight %s: health=%d mana=%d warding=%s dodge_ready=%.2f blocked=%d thrown_back=%d creatures=[%s]" % [" ".join(words.slice(1)), int(player.get("health").hp), int(hub.get("mana")), str(hub.get("combat").get("warding")), float(hub.get("combat").call("dodge_ready")), _wards[0], _wards[1], ", ".join(left)])
		"state":  # fantasy world: what the player has, for the log
			var land: Node = session.call("fantasy")
			_lines.append("bag=%s levels=%s active=%s done=%s mana=%d slots=%d" % [str(land.get("bag").items), str(land.get("skills").levels()), str(land.get("quests").active), str(land.get("quests").done), int(land.get("mana")), int(land.call("slots"))])


# Lets the game run for a while, then measures 30 frames and saves a picture.
func _stage(renderer: String, stage: String, seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	var started := Time.get_ticks_usec()
	var last := started
	var worst := 0.0  # the longest single frame: tells a hitch from a steadily slow view
	for i in 30:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) / 1000.0)
		last = now
	var ms := float(Time.get_ticks_usec() - started) / 30000.0
	get_viewport().get_texture().get_image().save_jpg(OUT + "boot_%s_%s.jpg" % [renderer, stage], 0.9)
	_lines.append("%s frame_ms=%.2f worst_frame_ms=%.1f draws=%d tris=%d video_mb=%.0f" % [stage, ms, worst,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


func _tap(action: String, down: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	Input.parse_input_event(event)


func _count_kinds(node: Node, into: Dictionary) -> void:
	into[node.get_class()] = int(into.get(node.get_class(), 0)) + 1
	for child in node.get_children():
		_count_kinds(child, into)


func _find_player(node: Node) -> Node:
	return _find_with(node, "set_third_person")


func _find_with(node: Node, method: String) -> Node:
	if node.has_method(method):
		return node
	for child in node.get_children():
		var found := _find_with(child, method)
		if found != null:
			return found
	return null


# Triangles a node and its visible children draw (meshes and multimeshes; dev numbers only).
func _tris_under(node: Node) -> int:
	if node is Node3D and not (node as Node3D).visible:
		return 0
	var n := 0
	var mesh: Mesh = null
	var copies := 1
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		mesh = (node as MultiMeshInstance3D).multimesh.mesh
		copies = (node as MultiMeshInstance3D).multimesh.visible_instance_count if (node as MultiMeshInstance3D).multimesh.visible_instance_count >= 0 else (node as MultiMeshInstance3D).multimesh.instance_count
	if mesh != null:
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			n += floori(float((idx as PackedInt32Array).size() if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3.0) * copies
	for child: Node in node.get_children():
		n += _tris_under(child)
	return n


# The first live ball on this machine that is a copy of somebody else's (game/beach_balls.gd), or -1.
func _copy_ball(pool: Node) -> int:
	for k in (pool.get("_life") as PackedFloat32Array).size():
		if (pool.get("_life") as PackedFloat32Array)[k] > 0.0 and (pool.get("_owner") as PackedInt32Array)[k] != 0:
			return k
	return -1


# A dev fire for "!gasfire": answers fire_near like a fire pit (group "fire_sources").
class _DevFire extends Node:
	var at := Vector3.ZERO

	func fire_near(point: Vector3, reach: float) -> bool:
		return point.distance_to(at) <= 0.5 + reach
