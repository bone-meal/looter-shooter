# Purpose: developer check helper. game/main.gd adds it when the game is started with the user argument --autostart
# (done by tools/game_boot_check.tscn). It lets the real game session run, switches the player to third person, saves a
# picture and the frame cost per stage into res://tools/userdata/boot_<renderer>*, then quits. User argument
# --cmd=<chat line>;<chat line> types those lines into the chat first (commands included). Not part of exports.
# Dependencies: the running game (finds the player by its set_third_person method).
extends Node

const OUT := "res://tools/userdata/"

var _lines := PackedStringArray()
var _counting := false  # !fight has hooked the ward's signal
var _wards := [0, 0]  # blows the ward stopped: [held, just in time]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_physics_steps_per_frame = 60  # a slow machine still walks at full speed during a scripted run
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var renderer := "forward_plus" if RenderingServer.get_rendering_device() != null else "compatibility"
	_lines.append("renderer=%s adapter=%s" % [renderer, RenderingServer.get_video_adapter_name()])
	_lines.append("the game was ready to play %d ms after the program started" % Time.get_ticks_msec())
	await _stage(renderer, "first_person", 3.0)
	for arg in OS.get_cmdline_user_args():  # --cmd=/tp club;/give unique all  runs chat lines, then one more picture
		if arg.begins_with("--cmd="):
			var session := _find_with(get_tree().root, "run_chat")
			session.set("no_save", true)  # a scripted run must never change the player's real save
			(session.get("settings") as RefCounted).set("dev_commands", true)  # the steps are chat commands
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
# !state (fantasy bag, levels and quests into the log), !fight [note] (health, mana, ward and nearby creatures into the log), !face (turn to the nearest creature), !where [note] (the player's map position into the log), !photo <name> (a HUD-less picture for the loading screens).
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
		"sounds":  # opens the Sounds page of the settings (as Settings > Sounds does); "!sounds off" closes it
			get_parent().call("_show_only", null if words.size() > 1 else get_parent().get("_sound_menu"))
		"loading":  # shows the loading picture as a session start does; "!loading off" lets it fade
			get_parent().get("_loading").call("finish" if words.size() > 1 else "begin", 4)
		"where":  # fantasy world: the player's spot in map metres, for the log
			var here: Vector3 = session.call("fantasy").call("player_local")
			_lines.append("at %.1f %.1f (height %.1f) %s" % [here.x, here.z, here.y, " ".join(words.slice(1))])
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
	for i in 30:
		await RenderingServer.frame_post_draw
	var ms := float(Time.get_ticks_usec() - started) / 30000.0
	get_viewport().get_texture().get_image().save_jpg(OUT + "boot_%s_%s.jpg" % [renderer, stage], 0.9)
	_lines.append("%s frame_ms=%.2f draws=%d tris=%d video_mb=%.0f" % [stage, ms,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


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
