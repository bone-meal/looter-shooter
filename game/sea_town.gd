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
const IsleGround = preload("res://game/isle_ground.gd")
const TownWindow = preload("res://game/town_window.gd")
const StoreWindow = preload("res://game/store_window.gd")
const TownStore = preload("res://core/sea/town_store.gd")
const NEAR := 900.0  # m from the plaza: the town is built when the player comes this close
const PLAZA := Vector2(-80.0, 6640.0)

var rules: TownRules
var window := TownWindow.new()
var store_window := StoreWindow.new()
var own_chest := TownStore.new()  # this player's chest at the storehouse (saved with him)
var crew_chest := TownStore.new()  # the crew's chest of the host's world (the storehouse's top level)
var picked := {}  # picks id -> unix time this player last picked there (saved with him)
var built := false
var said := ""  # the last answer (shown in the window)
var waiting := ""  # a plot whose upgrade we asked the host for

var _sea: Node3D
var _player: CharacterBody3D
var _plots := {}  # id -> {"holder": Node3D, "model": Node3D, "shown": String, "sign": Node3D, "label": Label3D}
var _houses: Array = []  # [{"holder": Node3D, "model": Node3D, "shown": String}] in data order (nearest the plaza first)
var _paving := -1
var _station_seen := false
var _reach := 3.0


func setup(sea_world: Node3D, player: CharacterBody3D, layer: CanvasLayer) -> void:
	_sea = sea_world
	_player = player
	rules = TownRules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/town.json")))
	_reach = float(rules.cfg.get("reach", 3.0))
	window.town = self
	layer.add_child(window)
	store_window.town = self
	layer.add_child(store_window)


func session() -> Node:
	return get_tree().get_first_node_in_group("game_session")


func net_sea() -> Node:
	return get_tree().get_first_node_in_group("net_sea")


func _process(delta: float) -> void:
	_hook_skills()
	if not bool(_sea.get("inside")) and not built:
		return
	_rest(delta)
	if not built:
		var here: Vector3 = _sea.call("local_of", _player.global_position)
		if Vector2(here.x, here.z).distance_to(PLAZA) < NEAR:
			_build_all()
		return
	var changed := false
	for id: String in _plots:  # a level that changed (here or from the host) rebuilds that plot
		if String(_plots[id]["shown"]) != rules.model(id):
			_show(id, true)
			changed = true
	if changed or _paving < 0:
		_grow_town()


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
	for h: Dictionary in rules.cfg.get("houses", []):
		var holder := Node3D.new()
		add_child(holder)
		holder.position = Vector3(float(h["at"][0]), float(h.get("y", 0.0)), float(h["at"][1]))
		holder.rotation.y = deg_to_rad(float(h.get("yaw", 0.0)))
		_houses.append({"holder": holder, "model": null, "shown": ""})
	_grow_town()


# The residents' houses and the streets follow the town's growth (director: streets + houses that appear as the town
# grows): more houses stand, each rebuilt in newer styles, and the streets go from dirt to cobbles to flagstones.
func _grow_town() -> void:
	var g := rules.growth()
	var paving := int(rules.paving())
	if paving != _paving:
		_paving = paving
		IsleGround.set_paving(String(rules.cfg.get("island", "start")), paving)
	for i in _houses.size():
		var entry: Dictionary = _houses[i]
		var want := rules.house_model(i, g)
		if String(entry["shown"]) == want:
			continue
		var was_up := String(entry["shown"]) != ""
		if entry["model"] != null:
			(entry["model"] as Node).queue_free()
		entry["model"] = null
		entry["shown"] = want
		if want == "":
			continue
		var made := FantasyModels.scene("../sea/town/" + want)
		if made == null:
			continue
		(entry["holder"] as Node3D).add_child(made)
		entry["model"] = made
		for found in made.find_children("*", "MeshInstance3D", true, false):
			(found as MeshInstance3D).create_trimesh_collision()
		if was_up or _paving >= 0:
			FxKit.burst(self, (entry["holder"] as Node3D).global_position + Vector3(0, 2.0, 0), Color(0.75, 0.68, 0.55, 0.8), 14, 1.4, 0.5, 2.5, -1.0)


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


# The fantasy world's crafting asks the town (a ship recipe needs the shipyard's level, a grand shipyard builds for
# less); the master work bonus is only on while a station opened here is open.
func _hook_skills() -> void:
	var skills: Variant = _sea.get("skills")
	if skills == null:
		return
	var work: Object = (skills as Node).get("work")
	if work != null and not (work.get("town_lock") as Callable).is_valid():
		work.set("town_lock", rules.recipe_lock)
		work.set("town_share", func(recipe: Dictionary) -> float: return float(rules.effect("shipyard", "build_share", 1.0)) if recipe.get("town") is Dictionary and String(recipe["town"].get("plot", "")) == "shipyard" else 1.0)
	var panel: Variant = (skills as Node).get("panel")
	if panel == null or float((skills as Node).get("town_finer")) <= 0.0:
		return
	if bool((panel as CanvasItem).visible):
		_station_seen = true
	elif _station_seen:  # the station opened here was closed: the master work bonus ends
		_station_seen = false
		(skills as Node).set("town_finer", 0.0)


# The walled garden's fountain: standing still by it heals (data effects rest_heal, share of max health a second).
func _rest(delta: float) -> void:
	var heal := float(rules.effect("garden", "rest_heal", 0.0))
	if heal <= 0.0 or not _plots.has("garden"):
		return
	var rest: Dictionary = rules.cfg.get("rest", {})
	var at: Vector3 = (_plots["garden"]["holder"] as Node3D).global_position
	if _player.global_position.distance_to(at) > float(rest.get("reach", 12.0)) or _player.velocity.length() > float(rest.get("still_speed", 0.6)):
		return
	var hp: Variant = _player.get("health")
	if hp != null:
		(hp as Object).call("heal", float((hp as Object).get("max_hp")) * heal * delta)


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
	for id: String in _plots:  # a building's door: what it offers
		var door := marker(id, "Door")
		if door != null and door.global_position.distance_to(me) <= _reach and not rules.services(id).is_empty():
			return ["door", id]
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
	if spot[0] == "door":
		var open_now := 0
		for pair: Array in rules.services(id):
			open_now += 1 if bool(pair[1]) else 0
		return "[%s] %s: %s" % [key, String(rules.plot(id)["name"]), "use" if open_now > 0 else "repair it first"]
	var lv := rules.level(id)
	var verb := "Repair" if lv == 0 else ("Upgrade" if lv < rules.top(id) else "See")
	return "[%s] %s: %s" % [key, String(rules.plot(id)["name"]), verb]


func interact() -> bool:
	var spot := spot_here()
	if spot.is_empty():
		return false
	open(String(spot[1]) if spot[0] != "ledger" else "harbour_master", spot[0] == "ledger")
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


# --- what the buildings offer (sea step 7b; director: the levels give what the ledger says) ---

# The town window's service button. Returns what happened (shown in the window).
func use(id: String, kind: String) -> String:
	if not rules.has_service(id, kind):
		return "Not yet: repair or upgrade the %s first" % String(rules.plot(id)["name"])
	if kind == "shop":
		close()
		var port: Node = _sea.get("port")
		port.call("open", "home")
		return "Shop"
	if kind.begins_with("station:"):
		var skills: Variant = _sea.get("skills")
		if skills == null:
			return "Nothing to work with"
		close()
		(skills as Node).set("town_finer", float(rules.effect("workshop", "finer", 0.0)) if id == "workshop" else 0.0)
		((skills as Node).get("work") as Object).emit_signal("station_opened", kind.trim_prefix("station:"))
		return _service_name(id, kind).capitalize()
	if kind == "store":
		close()
		open_store()
		return "Store"
	if kind.begins_with("pick:"):
		return pick(kind.trim_prefix("pick:"))
	return "?"


func _service_name(id: String, kind: String) -> String:
	for pair: Array in rules.services(id):
		if String(pair[0]["kind"]) == kind:
			return String(pair[0]["name"]).to_lower()
	return kind


# Picking in the garden: its goods once every few minutes per player.
func pick(what: String) -> String:
	var spec: Dictionary = rules.cfg.get("picks", {}).get(what, {})
	if spec.is_empty():
		return "Nothing grows there"
	var now := Time.get_unix_time_from_system()
	var wait := float(spec.get("minutes", 10)) * 60.0 - (now - float(picked.get(what, 0.0)))
	if wait > 0.0:
		return "Picked clean: ripe again in %d min" % ceili(wait / 60.0)
	var skills: Variant = _sea.get("skills")
	if skills == null:
		return "Nothing to carry it in"
	picked[what] = now
	var got := PackedStringArray()
	for item: String in spec["items"]:
		(skills as Node).call("give", item, int(spec["items"][item]))
		got.append("%d %s" % [int(spec["items"][item]), item_name(item)])
	return "Picked " + ", ".join(got)


# --- the store chest ---

func chest_shared() -> bool:
	return int(rules.effect("storage", "shared", 0)) == 1


func chest() -> RefCounted:
	var c: RefCounted = crew_chest if chest_shared() else own_chest
	c.set("capacity", int(rules.effect("storage", "slots", 0)))
	return c


func open_store() -> void:
	store_window.open()
	_player.set("controls_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_store() -> void:
	store_window.close()
	_player.set("controls_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# The bag's stacks the chest can take: [[item, count], ...] (everything carried, staffs and robes worn excepted).
func bag_stacks() -> Array:
	var b := bag()
	var out: Array = []
	if b == null:
		return out
	for item: String in b.call("all_ids"):
		var n := int(b.call("count", item))
		if n > 0 and String(b.call("slot_of", item)) == "":
			out.append([item, n])
	return out


func put(item: String, n: int) -> String:
	var b := bag()
	var carried := int(b.call("count", item)) if b != null else 0
	n = mini(n, carried)
	if n <= 0:
		return "You have none"
	if not chest().call("can_put", item):
		return "The chest is full"
	var ns := net_sea()
	if chest_shared() and ns != null and bool(ns.call("is_client")):
		ns.call("request_store", "put", item, n)
		return "..."
	var went := int(chest().call("put", item, n))
	b.call("remove", item, went)
	_store_changed()
	return "Stored %d %s" % [went, item_name(item)]


func take(item: String, n: int) -> String:
	var b := bag()
	n = mini(n, int(chest().call("count", item)))
	if n <= 0 or b == null:
		return "None in the chest"
	var ns := net_sea()
	if chest_shared() and ns != null and bool(ns.call("is_client")):
		ns.call("request_store", "take", item, n)
		return "..."
	var got := int(chest().call("take", item, n))
	(_sea.get("skills") as Node).call("give", item, got)
	_store_changed()
	return "Took %d %s" % [got, item_name(item)]


func _store_changed() -> void:
	var ns := net_sea()
	if chest_shared() and ns != null and bool(ns.call("active")):
		ns.call("tell_store", crew_chest.to_list())


# Online (the crew's chest): the host did what this player asked; his bag follows now.
func store_done(op: String, item: String, n: int) -> void:
	var b := bag()
	if n <= 0 or b == null:
		store_window.said = "The chest is full" if op == "put" else "None in the chest"
		return
	if op == "put":
		b.call("remove", item, n)
		store_window.said = "Stored %d %s" % [n, item_name(item)]
	else:
		(_sea.get("skills") as Node).call("give", item, n)
		store_window.said = "Took %d %s" % [n, item_name(item)]


# --- saving: the town's levels and the crew's chest are the host's world; a player's own chest and picking times his ---

func world_dict() -> Dictionary:
	var out := rules.to_dict()
	out["chest"] = crew_chest.to_list()
	return out


func load_world(saved: Variant) -> void:
	rules.from_dict(saved)
	crew_chest.from_list((saved as Dictionary).get("chest", []) if saved is Dictionary else [])


func mine_dict() -> Dictionary:
	return {"chest": own_chest.to_list(), "picked": picked.duplicate()}


func load_mine(saved: Variant) -> void:
	if not saved is Dictionary:
		return
	own_chest.from_list((saved as Dictionary).get("chest", []))
	picked.clear()
	var got: Variant = (saved as Dictionary).get("picked", {})
	if got is Dictionary:
		for k: Variant in got:
			if (got[k] is float or got[k] is int) and String(k).length() <= 24:
				picked[String(k)] = float(got[k])


func status() -> String:
	var parts := PackedStringArray()
	for id: String in rules.ids():
		parts.append("%s %d/%d" % [id, rules.level(id), rules.top(id)])
	var standing := 0
	for h: Dictionary in _houses:
		if String(h["shown"]) != "":
			standing += 1
	return "town built %s growth %.2f paving %d houses %d/%d: %s" % [str(built), rules.growth(), _paving, standing, _houses.size(), ", ".join(parts)]
