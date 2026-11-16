# Purpose: the HOME PORT TOWN in the sea (sea step 7a): each plot of data/sea/town.json shows its building at its
# level (assets/models/sea/town/<building>_<level>.gltf, tools/blender/sea_town.py: level 0 = run down; director: a
# hamlet stands, the rest the crew repairs and grows; every upgrade visibly rebuilt from fishing shack to stone
# colonial), a sign post with the building's name and level, and the TOWN LEDGER on its lectern at the harbour
# master. The interact key at a sign or the ledger opens the town window (game/town_window.gd). The town's levels
# belong to the HOST's world (saved in its profile extra "sea_town"): a guest asks the host (game/net_sea.gd
# request_town), the host raises the level and everyone sees it; the payer pays from his own bag and purse when the
# host says yes. The harbour master's counter (the shop, money changer and ferry desk of game/sea_port.gd) is the
# model's "Counter" marker.
# Dependencies: core/sea/town_rules.gd, data/sea/town.json, game/fantasy_models.gd, game/fx_kit.gd,
# game/town_window.gd; the sea world (world_of / local_of / skills), game/game_session.gd (doubloons), net_sea.
extends Node3D

const TownRules = preload("res://core/sea/town_rules.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const FxKit = preload("res://game/fx_kit.gd")
const TownWindow = preload("res://game/town_window.gd")
const NEAR := 900.0  # m from the plaza: the town is built when the player comes this close
const PLAZA := Vector2(-80.0, 6640.0)

var rules: TownRules
var window := TownWindow.new()
var built := false
var said := ""  # the last answer (shown in the window)
var waiting := ""  # a plot whose upgrade we asked the host for

var _sea: Node3D
var _player: CharacterBody3D
var _plots := {}  # id -> {"holder": Node3D, "model": Node3D, "shown": String, "sign": Node3D, "label": Label3D}
var _reach := 3.0


func setup(sea_world: Node3D, player: CharacterBody3D, layer: CanvasLayer) -> void:
	_sea = sea_world
	_player = player
	rules = TownRules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/town.json")))
	_reach = float(rules.cfg.get("reach", 3.0))
	window.town = self
	layer.add_child(window)


func session() -> Node:
	return get_tree().get_first_node_in_group("game_session")


func net_sea() -> Node:
	return get_tree().get_first_node_in_group("net_sea")


func _process(_delta: float) -> void:
	if not bool(_sea.get("inside")) and not built:
		return
	if not built:
		var here: Vector3 = _sea.call("local_of", _player.global_position)
		if Vector2(here.x, here.z).distance_to(PLAZA) < NEAR:
			_build_all()
		return
	for id: String in _plots:  # a level that changed (here or from the host) rebuilds that plot
		if String(_plots[id]["shown"]) != rules.model(id):
			_show(id, true)


func _build_all() -> void:
	built = true
	for p: Dictionary in rules.plots():
		var id := String(p["id"])
		var holder := Node3D.new()
		holder.name = "Plot_" + id
		add_child(holder)  # this node hangs in the sea root: its space is sea coordinates
		holder.position = Vector3(float(p["at"][0]), 0.0 if bool(p.get("sea_level", false)) else float(p.get("y", 0.0)), float(p["at"][1]))
		holder.rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
		_plots[id] = {"holder": holder, "model": null, "shown": "", "sign": null, "label": null}
		_show(id, false)


# Puts the plot's current model up (dust and a notice when it was just rebuilt).
func _show(id: String, rebuilt: bool) -> void:
	var entry: Dictionary = _plots[id]
	var holder: Node3D = entry["holder"]
	if entry["model"] != null:
		(entry["model"] as Node).queue_free()
	var made := FantasyModels.scene("../sea/town/" + rules.model(id))
	entry["shown"] = rules.model(id)
	entry["model"] = made
	if made == null:
		return
	holder.add_child(made)
	for found in made.find_children("*", "MeshInstance3D", true, false):
		(found as MeshInstance3D).create_trimesh_collision()
	_place_sign(id)
	if rebuilt:
		var at := holder.global_position + Vector3(0, 2.0, 0)
		for k in 3:
			FxKit.burst(self, at + holder.global_basis * Vector3(randf_range(-4, 4), 0, randf_range(-3, 3)), Color(0.75, 0.68, 0.55, 0.8), 18, 1.6, 0.6, 3.0, -1.0)
		var lv := rules.level(id)
		_notice("%s: %s (level %d)" % [String(rules.plot(id)["name"]), String(rules.entry(id, lv)["name"]), lv] if lv > 0 else "%s" % String(rules.plot(id)["name"]))


func _place_sign(id: String) -> void:
	var entry: Dictionary = _plots[id]
	var holder: Node3D = entry["holder"]
	var mark := marker(id, "Sign")
	if entry["sign"] == null:
		var post := FantasyModels.scene("../sea/town/town_sign")
		if post == null:
			post = Node3D.new()
		holder.add_child(post)
		var label := Label3D.new()
		label.font_size = 34
		label.pixel_size = 0.0024
		label.outline_size = 0
		label.modulate = Color(0.16, 0.1, 0.06)
		label.double_sided = true
		label.width = 400.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		post.add_child(label)
		label.position = Vector3(0.65, 1.77, 0.035)
		entry["sign"] = post
		entry["label"] = label
	var sign_node: Node3D = entry["sign"]
	sign_node.global_position = mark.global_position if mark != null else holder.global_position + holder.global_basis * Vector3(4, 0, -4)
	if bool(rules.plot(id).get("sea_level", false)):  # the dock's sign stands on the bank, not on the water
		sign_node.global_position.y = holder.global_position.y + 1.2
	var lv := rules.level(id)
	(entry["label"] as Label3D).text = "%s\n%s" % [String(rules.plot(id)["name"]), "Level %d of %d" % [lv, rules.top(id)] if lv > 0 else "Run down"]


# A marker of a plot's model ("Counter", "Ledger", "Sign", "Door"), or null.
func marker(id: String, mark: String) -> Node3D:
	if not _plots.has(id) or _plots[id]["model"] == null:
		return null
	return (_plots[id]["model"] as Node3D).find_child(mark, true, false) as Node3D


func _notice(text: String) -> void:
	if _sea.has_signal("notice"):
		_sea.emit_signal("notice", text)


# --- the interact key ---

# What the player stands at: ["ledger", ""] / ["sign", plot id] / [] (nothing).
func spot_here() -> Array:
	if not built:
		return []
	var me := _player.global_position
	var ledger := marker("harbour_master", "Ledger")
	if ledger != null and ledger.global_position.distance_to(me) <= _reach:
		return ["ledger", ""]
	for id: String in _plots:
		var post: Node3D = _plots[id]["sign"]
		if post != null and post.global_position.distance_to(me) <= _reach:
			return ["sign", id]
	return []


func prompt(key: String) -> String:
	if window.visible:
		return ""
	var spot := spot_here()
	if spot.is_empty():
		return ""
	if spot[0] == "ledger":
		return "[%s] Town ledger: repair and grow the port" % key
	var id := String(spot[1])
	var lv := rules.level(id)
	var verb := "Repair" if lv == 0 else ("Upgrade" if lv < rules.top(id) else "See")
	return "[%s] %s: %s" % [key, String(rules.plot(id)["name"]), verb]


func interact() -> bool:
	var spot := spot_here()
	if spot.is_empty():
		return false
	open(String(spot[1]) if spot[0] == "sign" else "harbour_master", spot[0] == "ledger")
	return true


func open(id: String, ledger: bool) -> void:
	said = ""
	window.open_at(id, ledger)
	_player.set("controls_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	window.close()
	_player.set("controls_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- paying and upgrading ---

func bag() -> RefCounted:
	var skills: Variant = _sea.get("skills")
	return (skills as Node).get("bag") if skills != null else null


func have(item: String) -> int:
	var b := bag()
	return int(b.call("count", item)) if b != null else 0


func doubloons() -> int:
	var s := session()
	var purse: RefCounted = s.call("doubloons") if s != null else null
	return int(purse.get("balance")) if purse != null else 0


func item_name(id: String) -> String:
	var b := bag()
	return String(b.call("item_name", id)) if b != null else id


func item_def(id: String) -> Dictionary:
	var b := bag()
	return b.call("def", id) if b != null else {}


func can_pay(id: String) -> bool:
	return rules.can_upgrade(id, have, doubloons())


# The window's button: on the host (or alone) the town rises at once; a guest asks the host first.
func upgrade(id: String) -> String:
	if rules.level(id) >= rules.top(id):
		return "Already as grand as it gets"
	if not can_pay(id):
		return "Not enough to pay for it"
	var ns := net_sea()
	if ns != null and bool(ns.call("is_client")):
		waiting = id
		ns.call("request_town", rules.index_of(id), rules.level(id) + 1)
		return "Asked the harbour master..."
	_pay(id)
	rules.upgrade(id)
	if ns != null and bool(ns.call("active")):
		ns.call("tell_town", rules.index_of(id), rules.level(id))
	return "%s: %s" % [String(rules.plot(id)["name"]), String(rules.entry(id, rules.level(id))["name"])]


func _pay(id: String) -> void:
	var c := rules.cost(id)
	var b := bag()
	var s := session()
	if s != null and int(c.get("doubloons", 0)) > 0:
		(s.call("doubloons") as RefCounted).call("spend", int(c["doubloons"]))
	var items: Dictionary = c.get("items", {})
	if b != null and not items.is_empty():
		b.call("take_all", items)


# The host raised a plot (online): the one who asked pays now; everyone gets the new level.
func host_done(plot_index: int, level: int, asker: int, me: int) -> void:
	var all := rules.ids()
	if plot_index < 0 or plot_index >= all.size():
		return
	var id := String(all[plot_index])
	if level != rules.level(id) + 1:
		if asker == me:
			waiting = ""
			said = "Someone else changed it first"
		return
	if asker == me:
		_pay(id)
		waiting = ""
		said = "%s: %s" % [String(rules.plot(id)["name"]), String(rules.entry(id, level)["name"])]
	rules.levels[id] = level
	window.queue_redraw()


func host_refused(_plot_index: int) -> void:
	waiting = ""
	said = "The harbour master said no"
	window.queue_redraw()


# The host's levels (sent now and then): a guest's town follows them.
func host_levels(list: Array) -> void:
	if rules.from_list(list):
		window.queue_redraw()


func status() -> String:
	var parts := PackedStringArray()
	for id: String in rules.ids():
		parts.append("%s %d/%d" % [id, rules.level(id), rules.top(id)])
	return "town built %s growth %.2f: %s" % [str(built), rules.growth(), ", ".join(parts)]
