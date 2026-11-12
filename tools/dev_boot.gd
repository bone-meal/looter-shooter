# Purpose: developer check helper. game/main.gd adds it when the game is started with the user argument --autostart
# (done by tools/game_boot_check.tscn). It lets the real game session run, switches the player to third person, saves a
# picture and the frame cost per stage into res://tools/userdata/boot_<renderer>*, then quits. User argument
# --cmd=<chat line>;<chat line> types those lines into the chat first (commands included). Not part of exports.
# Dependencies: the running game (finds the player by its set_third_person method).
extends Node

const OUT := "res://tools/userdata/"

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
# !state (fantasy bag, levels and quests into the log), !fight [note] (health, mana, ward and nearby creatures into the log), !face (turn to the nearest creature), !marks [note] (spikes, fire and water lying on the ground into the log), !squad [note] (every creature's squad order and where it stands into the log), !moves [note] (the special attacks creatures have used since the last !moves into the log), !usemove (the nearest creature starts its own attack now), !above name [height] [yaw] (a picture from the air), !heard [seconds] (the sounds audible in the last seconds into the log), !tier <id> (graphics tier potato / low / medium / high / ultimate for the rest of the run), !buildings full|plain (which building models places built from now on use), !where [note] (the player's map position into the log), !photo <name> (a HUD-less picture for the loading screens).
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
		"hold":  # keeps an action down until !release (what holding the mouse button or a key does)
			Input.action_press(words[1])
		"release":
			Input.action_release(words[1])
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
		"station":  # fantasy world: open the window of a station (fire, forge, workbench, cauldron) and pick a recipe
			var window: Control = session.call("fantasy").get("panel")
			window.call("open_station", words[1])
			if words.size() > 2:
				window.call("pick", words[2])
		"inv":  # the inventory window: "!inv" opens or shuts it, "!inv hover 5" puts the mouse on slot 5 (0-35), "!inv drop" presses the drop key, "!inv shift on|off" holds Shift, "!inv log" lists rolled guns and what lies on the ground
			var window: Control = session.get("_inventory_screen")
			match words[1] if words.size() > 1 else "":
				"hover":
					window.set("_mouse", (window.call("_slot_rect", int(words[2])) as Rect2).get_center())
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
		"slot":  # hold the gun in hotbar slot n (1-9)
			player.call("select_hotbar", int(words[1]) - 1)
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
			_lines.append("MEASURE %s: frame %.2f ms (worst %.1f); gpu %.2f; main thread %.2f = drawing %.2f + scripts and the rest %.2f; physics %.2f; draws %d, tris %d, nodes %d, objects drawn %d" % [" ".join(words.slice(1)),
				float(Time.get_ticks_usec() - began) / 90000.0, slowest, gpu_ms / 90.0, script_ms / 90.0, draw_cpu_ms / 90.0, maxf(script_ms - draw_cpu_ms, 0.0) / 90.0, physics_ms / 90.0,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
		"tier":  # "!tier low": the graphics tier for the rest of the run (the settings FILE is not touched)
			(session.get("settings") as RefCounted).set("graphics", words[1])
			session.call("apply_settings")
			_lines.append("graphics tier %s" % words[1])
		"pick":  # "!pick bounce_light off": one of the player's own graphics choices (data/graphics.json "options") for the rest of the run
			((session.get("settings") as RefCounted).get("picks") as Dictionary)[words[1]] = words[2]
			session.call("apply_settings")
			_lines.append("pick %s = %s" % [words[1], words[2]])
		"menu":  # "!menu settings" shows the settings page (for a picture), "!menu none" hides the menus again
			var main_scene: Node = session.get_parent()
			main_scene.call("_show_only", main_scene.get("_settings_menu") if words[1] == "settings" else null)
		"buildings":  # "!buildings full" / "!buildings plain": which building models places built from now on use, whatever the tier says (to measure one against the other)
			(session.call("fantasy").get("places") as Node).set("plain", words[1] == "plain")
			_lines.append("buildings %s" % words[1])
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
			if nearest != null:
				player.call("look_at_point", nearest.global_position + Vector3(0, float(nearest.call("head_height")) * 0.55, 0))
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
