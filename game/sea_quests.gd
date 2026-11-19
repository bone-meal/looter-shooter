# Purpose: the sea quests (sea step 13e; LOCKED: an own SEA QUEST LOG, progress in the HOST'S WORLD shared by the party,
# each quest ends with its person TAKING OVER A BUILDING at the home port). The quest people wait at their island spots
# (data/sea/quests.json "at"); [F] by one = they speak (game/bottle_note.gd) and a talk / bring step is asked of the
# host (a bring takes the things from the asker's bag once the host says yes). A dive step's thing lies at a salvage
# spot with "quest_item" (game/sea_salvage.gd shows it only at that step), a dungeon step ends when the host sees that
# fight cleared. Once done the person leaves the island and runs the building (game/town_people.gd resident_info), or
# (sea step 13 R2f, a quest with "runs") stands at an outpost's service spot (Lanternwick) and says their town lines.
# The quest log (key L at sea, game/sea_quest_window.gd) and marks on the chart (chart_marks) say where to go. The
# progress travels and is saved with the town's extra (game/sea_town.gd extra_dict "quests"); online the asks go
# through game/net_sea.gd request_quest / _quest_done.
# Dependencies: core/sea/sea_quest_rules.gd, data/sea/quests.json, data/sea/writing/quests_r1.txt + quests_r2.txt, game/npc_body.gd,
# game/body_motion.gd, game/bottle_note.gd, game/sea_quest_window.gd; the sea world (ships._net, town, dungeons,
# salvage, skills (the bag), local_of, world_of, notice).
extends Node3D

const QuestRules = preload("res://core/sea/sea_quest_rules.gd")
const NpcBody = preload("res://game/npc_body.gd")
const BodyMotion = preload("res://game/body_motion.gd")
const BottleNote = preload("res://game/bottle_note.gd")
const QuestWindow = preload("res://game/sea_quest_window.gd")

var rules: QuestRules
var note := BottleNote.new()
var log_window := QuestWindow.new()
var finished := 0  # dev / checks: steps finished here, asks sent, asks refused
var asked := 0
var refused := 0
var last := ""
var _sea: Node3D
var _player: CharacterBody3D
var _people := {}  # quest id -> {"node": Node3D, "y": float, "ray_t": float}
var _clock := 0.0
var _tick := 0.0


func setup(sea_world: Node3D, player: CharacterBody3D, layer: CanvasLayer) -> void:
	_sea = sea_world
	_player = player
	rules = QuestRules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/quests.json")), FileAccess.get_file_as_string("res://data/sea/writing/quests_r1.txt") + "\n" + FileAccess.get_file_as_string("res://data/sea/writing/quests_r2.txt"))
	note.events = self
	layer.add_child(note)
	log_window.quests = self
	layer.add_child(log_window)


func _net() -> Node:
	return (_sea.get("ships") as Node).call("_net")


func _host() -> bool:
	var net := _net()
	return net == null or not bool(net.call("is_client"))


func _my_id() -> int:
	var net := _net()
	return int(net.call("my_id")) if net != null and bool(net.call("active")) else 0


func _bag() -> Variant:
	var skills: Variant = _sea.get("skills")
	return (skills as Node).get("bag") if skills != null else null


# --- every frame: the people at their spots; the host watches dungeon steps ---

func _process(delta: float) -> void:
	if not bool(_sea.get("inside")):
		return
	_clock += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		if _host():
			for q: Dictionary in rules.quests():
				var id := String(q["id"])
				var st := rules.current(id)
				if String(st.get("kind", "")) == "dungeon" and _cleared(String(st["dungeon"]), String(st["fight"])):
					_host_finish(id, rules.step_of(id), 0)
	_place_people(delta)


func _cleared(dungeon: String, fight: String) -> bool:
	var spaces: Dictionary = (_sea.get("dungeons") as Node).get("spaces")
	if not spaces.has(dungeon):
		return false
	var r: RefCounted = (spaces[dungeon] as Node).get("rules")
	return bool(((r.get("state") as Dictionary).get("cleared", {}) as Dictionary).get(fight, false))


func _place_people(delta: float) -> void:
	var me: Vector3 = _sea.call("local_of", _player.global_position)
	for q: Dictionary in rules.quests():
		var id := String(q["id"])
		var runs: Dictionary = q.get("runs", {})
		var moved := rules.done(id) and not runs.is_empty()  # (sea step 13 R2f) done: at the outpost's service spot
		var spot: Array = runs["at"] if moved else q["at"]
		var at := Vector2(float(spot[0]), float(spot[1]))
		var want := (not rules.done(id) or moved) and at.distance_to(Vector2(me.x, me.z)) < float(rules.cfg["show_m"])
		var p: Dictionary = _people.get(id, {})
		if p.is_empty() and (not rules.done(id) or moved):  # (sea step 13g) everyone is built on the first call, while the sea loads, and kept hidden till near: no hitch on the way
			var look: Array = q["look"]
			var node := NpcBody.build({"gender": String(look[1]), "height": 1.0, "weight": 1.0, "bust": 0.3, "glutes": 0.3, "skin": hash(id) % 6, "hair": String(look[2]),
				"hair_color": ["#2b1d14", "#553322", "#8a5a2b", "#c9a26b", "#1a1a1a"][hash(id + "h") % 5], "face": "gentle_smile", "outfit": String(look[0])})
			add_child(node)
			node.visible = false
			var plate := Label3D.new()
			plate.text = "%s\n(quest)" % rules.word(id, "person")
			plate.font_size = 30
			plate.pixel_size = 0.005
			plate.outline_size = 8
			plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			plate.position.y = 2.05
			node.add_child(plate)
			p = {"node": node, "y": 0.0, "ray_t": 0.0, "plate": plate}
			_people[id] = p
		if not want:
			if not p.is_empty():
				(p["node"] as Node3D).visible = false
			continue
		var body: Node3D = p["node"]
		body.visible = true
		if moved:
			(p["plate"] as Label3D).text = "%s\n%s" % [rules.word(id, "person"), rules.word(id, "trade")]
		p["ray_t"] = float(p["ray_t"]) - delta
		if moved and spot.size() > 2:  # indoors: the floor given (a ray from above would find the roof)
			p["y"] = float(spot[2])
		elif float(p["ray_t"]) <= 0.0:  # the island's ground under them (it is solid only near players)
			p["ray_t"] = 1.0
			var top: Vector3 = _sea.call("world_of", Vector3(at.x, 120.0, at.y))
			var ray := PhysicsRayQueryParameters3D.create(top, top + Vector3(0.0, -200.0, 0.0))
			ray.collision_mask = 1
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty():
				p["y"] = (_sea.call("local_of", hit["position"]) as Vector3).y
		body.global_position = _sea.call("world_of", Vector3(at.x, float(p["y"]), at.y))
		var to := Vector2(me.x - at.x, me.z - at.y)
		if to.length() < 12.0:
			body.rotation.y = atan2(to.x, to.y) + PI  # (bodies face -z): toward the player
		BodyMotion.animate(body, 0.0, 0.0, _clock + float(id.length()), false)


# --- the interact key ---

func person_near() -> String:
	if note.visible or log_window.visible:
		return ""
	for id: String in _people:
		var body: Node3D = _people[id]["node"]
		if body.visible and body.global_position.distance_to(_player.global_position) <= float(rules.cfg["talk_m"]):
			return id
	return ""


func prompt(key: String) -> String:
	var id := person_near()
	return "[%s] Talk to %s" % [key, rules.word(id, "person")] if id != "" else ""


func interact() -> bool:
	var id := person_near()
	if id == "":
		return false
	talk(id)
	return true


# Talking to quest `id`'s person: they speak; a talk step ends, a bring step ends if the things are in the bag. Done
# (and moved to an outpost): one of their town lines.
func talk(id: String) -> void:
	if rules.done(id):
		var lines := rules.word(id, "town").split("|")
		var line := lines[randi() % lines.size()].strip_edges() if not lines.is_empty() else ""
		_show(rules.word(id, "person"), "%s: \"%s\"" % [rules.word(id, "person"), line], rules.word(id, "trade"))
		return
	var k := rules.step_of(id)
	var st := rules.current(id)
	var kind := String(st.get("kind", ""))
	var foot := rules.goal(id)
	if kind == "talk" or kind == "bring":
		var ok := true
		if kind == "bring":
			var bag: Variant = _bag()
			for item: String in st["items"]:
				ok = ok and bag != null and int((bag as RefCounted).call("count", item)) >= int(st["items"][item])
		if ok:
			ask(id, k)
		elif kind == "bring":
			foot = "Still needed: %s" % _needs(st["items"])
	_show(rules.word(id, "title"), "%s: \"%s\"" % [rules.word(id, "person"), rules.word(id, "say%d" % k)], foot)


func _needs(items: Dictionary) -> String:
	var bag: Variant = _bag()
	var parts: PackedStringArray = []
	for item: String in items:
		var have := int((bag as RefCounted).call("count", item)) if bag != null else 0
		parts.append("%s %d / %d" % [String((bag as RefCounted).call("item_name", item)) if bag != null else item, have, int(items[item])])
	return ", ".join(parts)


func _show(title: String, body: String, foot: String) -> void:
	note.show_note(title, _wrap(body, 70), foot)
	_player.set("controls_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func _wrap(text: String, width: int) -> String:
	var lines: PackedStringArray = []
	var line := ""
	for w: String in text.split(" "):
		if line.length() + w.length() + 1 > width and line != "":
			lines.append(line)
			line = w
		else:
			line = w if line == "" else line + " " + w
	lines.append(line)
	return "\n".join(lines)


func close_window() -> void:
	note.close()
	log_window.close()
	_player.set("controls_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_log() -> void:
	if log_window.visible:
		close_window()
	else:
		log_window.open()
		_player.set("controls_enabled", false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# Step `k` of quest `id` is done by this player (alone / host: at once; a client asks the host).
func ask(id: String, k: int) -> void:
	asked += 1
	if _host():
		var me: Vector3 = _sea.call("local_of", _player.global_position)
		if not host_ask(id, k, Vector2(me.x, me.z), _my_id()):
			refused += 1
		return
	_net().call("request_quest", id, k)


# The host: may this step end (it is the quest's step, a talk / bring one by the person, a dive one by anyone)?
func host_ask(id: String, k: int, at: Vector2, asker: int) -> bool:
	if not rules.can_finish(id, k):
		return false
	var kind := String(rules.current(id).get("kind", ""))
	var q := rules.quest(id)
	if kind == "talk" or kind == "bring":
		if at.distance_to(Vector2(float(q["at"][0]), float(q["at"][1]))) > float(rules.cfg["talk_m"]) + 4.0:
			return false
	elif kind != "dive":
		return false
	_host_finish(id, k, asker)
	return true


func _host_finish(id: String, k: int, asker: int) -> void:
	var net := _net()
	if net != null:
		net.call("tell_quest", id, k, asker)
	step_done(id, k, asker, _my_id())


# On every machine: step `k` of quest `id` is done (asker = who did it; the asker pays a bring step's things).
func step_done(id: String, k: int, asker: int, me: int) -> void:
	var st: Dictionary = (rules.quest(id).get("steps", []) as Array)[k] if k < (rules.quest(id).get("steps", []) as Array).size() else {}
	if not rules.finish(id, k):
		return
	finished += 1
	last = "%s step %d done" % [id, k]
	if asker == me and String(st.get("kind", "")) == "bring":
		var bag: Variant = _bag()
		if bag != null:
			(bag as RefCounted).call("take_all", st["items"])
	if rules.done(id):
		_notice("%s: \"%s\"" % [rules.word(id, "person"), rules.word(id, "done")])
		var runs_at: Dictionary = rules.quest(id).get("runs", {})
		var place := "the home port" if runs_at.is_empty() else String(runs_at.get("port", "the outpost")).capitalize()
		_notice("Quest done: %s. %s is now the %s at %s." % [rules.word(id, "title"), rules.word(id, "person"), rules.word(id, "trade").to_lower(), place])
		var town: Node = _sea.get("town")
		if town != null:
			(town.get("people") as Node).call("refresh")
	elif k == 0:
		_notice("New quest: %s" % rules.word(id, "title"))
	else:
		_notice(rules.goal(id))
	(_sea.get("salvage") as Node).call("refresh_found")
	log_window.queue_redraw()
	var s := get_tree().get_first_node_in_group("game_session")
	if s != null and s.has_method("save_profile"):
		s.call("save_profile")


func _notice(text: String) -> void:
	if bool(_sea.get("inside")) and text != "":
		_sea.emit_signal("notice", text)


# --- what others read: the dive spot's step, the building's runner, the chart's marks ---

# Is quest `id` at step `k` (a dive spot shows only then)?
func at_step(id: String, k: int) -> bool:
	return rules != null and not rules.done(id) and rules.step_of(id) == k


# The person running town plot `plot` because of a done quest ({} = its own resident): name, trade, outfit, gender,
# hair, say.
func resident_info(plot: String) -> Dictionary:
	var id := rules.runner_of(plot) if rules != null else ""
	if id == "":
		return {}
	var look: Array = rules.quest(id)["look"]
	var lines: Array = []
	for line: String in rules.word(id, "town").split("|"):
		lines.append(line.strip_edges())
	return {"name": rules.word(id, "person"), "trade": rules.word(id, "trade"), "outfit": look[0], "gender": look[1], "hair": look[2], "say": lines, "quest": id}


# [[sea Vector2, title]] for every quest not done: where its step happens.
func chart_marks() -> Array:
	var out: Array = []
	for q: Dictionary in rules.quests():
		var id := String(q["id"])
		if not rules.done(id):
			out.append([rules.where(id), rules.word(id, "title")])
	return out


# --- the host's world (carried in the town's extra, game/sea_town.gd) ---

func to_dict() -> Dictionary:
	return rules.to_dict() if rules != null else {}


func load_dict(saved: Variant) -> void:
	if str(saved) == str(rules.to_dict()) or not saved is Dictionary:
		return
	rules.from_dict(saved)
	var town: Node = _sea.get("town")
	if town != null:
		(town.get("people") as Node).call("refresh")
	(_sea.get("salvage") as Node).call("refresh_found")
	log_window.queue_redraw()


func adopt_as_host() -> void:
	pass  # (the progress is in the town's extra the new host already has)


func status() -> String:
	var parts: PackedStringArray = []
	for q: Dictionary in rules.quests():
		var id := String(q["id"])
		parts.append("%s %d%s" % [id, rules.step_of(id), " done" if rules.done(id) else ""])
	return "quests [%s], finished %d, asked %d, refused %d, last '%s', near '%s'" % [", ".join(parts), finished, asked, refused, last, person_near()]
