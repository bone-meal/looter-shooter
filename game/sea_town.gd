# Purpose: the HOME PORT TOWN in the sea (sea step 7a): each plot of data/sea/town.json shows its building at its
# level (assets/models/sea/town/<building>_<level>.gltf, tools/blender/sea_town.py: level 0 = run down; director: a
# hamlet stands, the rest the crew repairs and grows; every upgrade visibly rebuilt from fishing shack to stone
# colonial), a sign post with the building's name and level, and the TOWN LEDGER on its lectern at the harbour
# master. The interact key at a sign or the ledger opens the town window (game/town_window.gd). The town's levels
# belong to the HOST's world (saved in its profile extra "sea_town"): a guest asks the host (game/net_sea.gd
# request_town), the host raises the level and everyone sees it; the payer pays from his own bag and purse when the
# host says yes. The harbour master's counter (the shop, money changer and ferry desk of game/sea_port.gd) is the
# model's "Counter" marker. The trophy hall and the gallery are walk-in (sea step 7b-4): game/town_hall.gd fills the
# hall (cabinets, collection cases, boss plinths, legend), game/town_gallery.gd hangs the paintings (portals); what is
# in them (cases filled, paintings bought) is the host's world too, asked for like an upgrade (net_sea request_act).
# Dependencies: core/sea/town_rules.gd, data/sea/town.json, game/fantasy_models.gd, game/fx_kit.gd,
# game/town_window.gd, game/town_hall.gd, game/town_gallery.gd, game/hub_hud.gd (the card of what is looked at in the
# hall); the sea world (world_of / local_of / skills), game/game_session.gd (doubloons, gallery_travel), net_sea.
extends Node3D

const TownRules = preload("res://core/sea/town_rules.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const FxKit = preload("res://game/fx_kit.gd")
const IsleGround = preload("res://game/isle_ground.gd")
const TownWindow = preload("res://game/town_window.gd")
const StoreWindow = preload("res://game/store_window.gd")
const TownStore = preload("res://core/sea/town_store.gd")
const TownPeople = preload("res://game/town_people.gd")
const BeachTable = preload("res://game/tcg/beach_table.gd")
const StaffCrew = preload("res://game/staff_crew.gd")
const TownHall = preload("res://game/town_hall.gd")
const TownGallery = preload("res://game/town_gallery.gd")
const HubHud = preload("res://game/hub_hud.gd")
const NEAR := 900.0  # m from the plaza: the town is built when the player comes this close
const PLAZA := Vector2(-80.0, 6640.0)

var rules: TownRules
var window := TownWindow.new()
var store_window := StoreWindow.new()
var own_chest := TownStore.new()  # this player's chest at the storehouse (saved with him)
var crew_chest := TownStore.new()  # the crew's chest of the host's world (the storehouse's top level)
var picked := {}  # picks id -> unix time this player last picked there (saved with him)
var people := TownPeople.new()
var hall := TownHall.new()
var gallery := TownGallery.new()
var card_hud := HubHud.new()  # the card of the trophy, case or plinth looked at in the hall
var arrive := ""  # a painting id: put this player before that painting in the gallery once the town is up (a return trip)
var heard_at := -1e9  # when this player last heard a rumour at the tavern (seconds, this session)
var _cards := {}  # the tavern's card table: {card_table, card_dealer, crew} once the tavern has one
var _beacon: Node3D = null
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
	people.town = self
	add_child(people)
	hall.town = self
	add_child(hall)
	gallery.town = self
	add_child(gallery)
	layer.add_child(card_hud)
	card_hud.visible = false


func session() -> Node:
	return get_tree().get_first_node_in_group("game_session")


func net_sea() -> Node:
	return get_tree().get_first_node_in_group("net_sea")


func _process(delta: float) -> void:
	_hook_skills()
	if not bool(_sea.get("inside")) and not built:
		return
	_rest(delta)
	_boons(delta)
	if built:
		_harbour(delta)
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
	if arrive != "":
		_arrive()
	var eye := get_viewport().get_camera_3d()
	card_hud.trophy = hall.look(eye.global_position, -eye.global_basis.z) if eye != null and bool(_sea.get("inside")) and not window.visible else {}
	card_hud.visible = not card_hud.trophy.is_empty()


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
	people.refresh()
	_card_table()


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
	if id == "trophy_hall":
		hall.fit(made, rules.level(id), rules.cfg.get("hall", {}))
	elif id == "gallery":
		gallery.fit(made, rules.level(id), rules.cfg.get("paintings", {}))
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


# The tavern's card table with its House Dealer (from level 2), registered with the session's card game once.
func _card_table() -> void:
	if not _plots.has("tavern"):
		return
	var lv := rules.level("tavern")
	var spots: Array = rules.plot("tavern").get("effects", {}).get("card_at", [])
	if lv < 2 or spots.size() < lv:
		if not _cards.is_empty():
			(_cards["card_table"] as Node3D).visible = false
			(_cards["crew"] as Node3D).visible = false
		return
	var holder: Node3D = _plots["tavern"]["holder"]
	var spot: Array = spots[lv - 1]
	var yaw := float((rules.plot("tavern")["effects"].get("card_yaw", [0, 0, 0, 0, 0]) as Array)[lv - 1])
	if _cards.is_empty():
		var table := BeachTable.new()
		table.indoor = true  # no beach parasol on the tavern's terrace
		holder.add_child(table)
		var crew := StaffCrew.new()
		holder.add_child(crew)
		var dealer: Node3D = crew.add("sit", StaffCrew.look("chef", "curly", "#553322", "smirk", 2), Vector3.ZERO, 0.0, null, "")
		_cards = {"card_table": table, "card_dealer": dealer, "crew": crew}
		var s := session()
		if s != null and s.has_method("add_card_place"):
			s.call("add_card_place", _cards)
	var t: Node3D = _cards["card_table"]
	t.visible = true
	(_cards["crew"] as Node3D).visible = true
	t.position = Vector3(float(spot[0]), 0.05, -float(spot[1]))  # model space x, f -> holder space (f = -z)
	t.rotation_degrees.y = yaw
	(_cards["card_dealer"] as Node3D).position = t.position + Vector3(0, 0, 0.85).rotated(Vector3.UP, deg_to_rad(yaw))
	(_cards["card_dealer"] as Node3D).rotation_degrees.y = yaw


# Drinks and rooms that give health back over time (boon regen_pct).
func _boons(delta: float) -> void:
	var regen := float(_player.call("boon", "regen_pct"))
	if regen <= 0.0:
		return
	var hp: Variant = _player.get("health")
	if hp != null:
		(hp as Object).call("heal", float((hp as Object).get("max_hp")) * regen * delta)


# The dock: moorings (a ship anchored at one of the berths its level gives); from level 4 a moored ship is mended at
# the quay (the host does it: the fleet is his), from level 5 the harbour light shines at night.
func moored() -> Array:
	var out: Array = []
	var count := int(rules.effect("dock", "berths", 0))
	var spots: Array = rules.cfg.get("berths", [])
	var fleet: Variant = _sea.get("ships")
	if fleet == null:
		return out
	for ship: Node in (fleet as Node).get("ships"):
		var st: Dictionary = ship.get("state")
		if not bool(st.get("anchored", false)):
			continue
		for k in mini(count, spots.size()):
			if Vector2(float(st["x"]), float(st["z"])).distance_to(Vector2(float(spots[k][0]), float(spots[k][1]))) <= float(rules.cfg.get("berth_reach", 12.0)):
				out.append(ship)
				break
	return out


func _harbour(delta: float) -> void:
	var mend := float(rules.effect("dock", "quay_repair", 0.0))
	var ns := net_sea()
	if mend > 0.0 and not (ns != null and bool(ns.call("is_client"))):
		var hulls: Node = (_sea.get("ships") as Node).get("hull_part")
		for ship: Node in moored():
			var st: Dictionary = ship.get("state")
			var most := float(hulls.get("hull").call("max_hull", String(st["ship"])))
			st["hull"] = minf(float(st["hull"]) + most * mend * delta, most)
			var leaks: Array = st["leaks"]
			for i in leaks.size():
				leaks[i] = maxf(float(leaks[i]) - 0.05 * delta, 0.0)
	_light(int(rules.effect("dock", "beacon", 0)) == 1)


func _light(on: bool) -> void:
	var look: Variant = _sea.get("look")
	var night := false
	if look != null:
		var clock: RefCounted = (look as RefCounted).get("clock")
		night = clock != null and float(clock.call("daylight", clock.call("day_part", float(_sea.call("seconds"))))) < 0.3
	if not on or not _plots.has("dock"):
		if _beacon != null:
			_beacon.visible = false
		return
	if _beacon == null:
		_beacon = Node3D.new()
		(_plots["dock"]["holder"] as Node3D).add_child(_beacon)
		_beacon.position = Vector3(0.0, 8.8, -35.5)  # the harbour light's lantern room on the granite quay (dock_5)
		var lamp := MeshInstance3D.new()  # a glowing lamp, no real light: an OmniLight doubled the town's draws at night (Compatibility)
		var ball := SphereMesh.new()
		ball.radial_segments = 16
		ball.rings = 8
		ball.radius = 0.9
		ball.height = 1.8
		lamp.mesh = ball
		var lit := StandardMaterial3D.new()
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lit.albedo_color = Color(1.0, 0.88, 0.6)
		lit.disable_fog = true
		lamp.material_override = lit
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beacon.add_child(lamp)
		var beam := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.radial_segments = 16
		cone.rings = 1
		cone.top_radius = 0.4
		cone.bottom_radius = 9.0
		cone.height = 260.0
		beam.mesh = cone
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		glow.disable_fog = true
		glow.albedo_color = Color(1.0, 0.85, 0.5, 0.12)
		beam.material_override = glow
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.rotation_degrees.x = 90.0
		beam.position = Vector3(0, 0, -130.0)
		var turn := Node3D.new()
		turn.name = "Turn"
		turn.add_child(beam)
		_beacon.add_child(turn)
	_beacon.visible = night
	if night:
		(_beacon.get_node("Turn") as Node3D).rotate_y(0.35 * get_process_delta_time())


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
	var who := people.resident_near(me)  # a resident first: they stand by their sign and door
	if who != "":
		return ["resident", who]
	var ledger := marker("harbour_master", "Ledger")
	if ledger != null and ledger.global_position.distance_to(me) <= _reach:
		return ["ledger", ""]
	for id: String in _plots:
		var post: Node3D = _plots[id]["sign"]
		if post != null and post.global_position.distance_to(me) <= _reach:
			return ["sign", id]
	var case_id := hall.case_near(me)
	if case_id != "":
		return ["case", case_id]
	var plinth := hall.plinth_near(me, _player.call("view_forward"))  # (sea step 10) a boss trophy's plinth, the one he faces
	if plinth > 0:
		return ["plinth", str(plinth)]
	var art := gallery.painting_near(me)
	if not art.is_empty():
		return ["painting", String(art[0])]
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
	if spot[0] == "resident":
		var r: Dictionary = rules.cfg.get("residents", {}).get(id, {})
		return "[%s] Talk to %s (%s)" % [key, String(r.get("name", "")), String(r.get("trade", ""))]
	if spot[0] == "case":
		if hall.cases.has(id):
			return ""
		var trophy := "trophy_" + id
		return ("[%s] Put the %s in its case" % [key, item_name(trophy)]) if have(trophy) > 0 else "%s: complete the collection, then bring its trophy here" % item_name(trophy)
	if spot[0] == "plinth":
		var trophy := hall.plinth_trophy(int(id))
		if hall.plinths.has(id) or trophy == "":
			return ""
		return ("[%s] Set the %s on its plinth" % [key, item_name(trophy)]) if have(trophy) > 0 else "%s: beat %s and bring it here" % [item_name(trophy), hall.plinth_boss(int(id))]
	if spot[0] == "painting":
		var p: Dictionary = rules.cfg.get("paintings", {}).get(id, {})
		if gallery.bought.has(id):
			return "[%s] Step into the painting: %s" % [key, String(p.get("name", id))]
		return "%s: buy it at the gallery's door (%d doubloons)" % [String(p.get("name", id)), int(p.get("doubloons", 0))]
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
	if spot[0] == "case":
		if not hall.cases.has(String(spot[1])) and have("trophy_" + String(spot[1])) > 0:
			_notice(place_case(String(spot[1])))
		return true
	if spot[0] == "plinth":
		var t := hall.plinth_trophy(int(spot[1]))
		if t != "" and not hall.plinths.has(String(spot[1])) and have(t) > 0:
			_notice(place_plinth(String(spot[1])))
		return true
	if spot[0] == "painting":
		if gallery.bought.has(String(spot[1])):
			var s := session()
			if s != null:
				_notice(String(s.call("gallery_travel", String(spot[1]))))
		return true
	open(String(spot[1]) if spot[0] != "ledger" else "harbour_master", spot[0] == "ledger")
	if spot[0] == "resident":
		said = people.line_of(String(spot[1]))
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
	if kind.begins_with("drink:"):
		var drink: Dictionary = rules.cfg.get("drinks", {}).get(kind.trim_prefix("drink:"), {})
		if not _spend(int(drink.get("doubloons", 0))):
			return "Not enough doubloons"
		_give_boons(drink)
		return "%s: %s for %d minutes" % [String(drink.get("name", "")), _boon_words(drink), int(drink.get("minutes", 10))]
	if kind == "rest":
		var room: Dictionary = rules.cfg.get("rest_room", {})
		if not _spend(int(room.get("doubloons", 0))):
			return "Not enough doubloons"
		var hp: Variant = _player.get("health")
		if hp != null:
			(hp as Object).call("heal", 99999.0)
		if _player.has_method("clear_dread"):  # Dread (sea step 10) clears with a rest at a port
			_player.call("clear_dread")
		_give_boons(room)
		return "Rested: full health, well rested for %d minutes" % int(room.get("minutes", 10))
	if kind == "feast":
		var feast: Dictionary = rules.cfg.get("feast", {})
		if not _spend(int(feast.get("doubloons", 0))):
			return "Not enough doubloons"
		var ns := net_sea()
		if ns != null and bool(ns.call("active")):
			ns.call("tell_feast")
		feast_here()
		return "A feast for the whole crew: %s for %d minutes" % [_boon_words(feast), int(feast.get("minutes", 30))]
	if kind == "rumour":
		return rumour()
	if kind == "cards":
		return "The card table is outside the tavern: sit down there (F) to play the house"
	if kind.begins_with("paint:"):
		return buy_painting(kind.trim_prefix("paint:"))
	return "?"


# --- the trophy hall's cases and the gallery's paintings (sea step 7b-4): the host's world, asked for like upgrades ---

func lore_of(collection: String) -> String:
	var skills: Variant = _sea.get("skills")
	if skills == null:
		return ""
	return String(((skills as Node).get("data") as Dictionary)["text"].get("lore", {}).get("collection_" + collection, {}).get("text", ""))


func my_name() -> String:
	var s := session()
	return String(s.get("_profile_name")) if s != null else "Me"


func place_case(collection: String) -> String:
	var trophy := "trophy_" + collection
	if hall.cases.has(collection):
		return "That case is already filled"
	if have(trophy) <= 0:
		return "You have no %s" % item_name(trophy)
	var ns := net_sea()
	if ns != null and bool(ns.call("is_client")):
		ns.call("request_act", "case", collection)
		return "Asked the harbour master..."
	act_done("case", collection, 0, my_name(), 0)
	if ns != null and bool(ns.call("active")):
		ns.call("tell_act", "case", collection, my_name())
	return "The %s is on show in the trophy hall" % item_name(trophy)


func place_plinth(region: String) -> String:
	var trophy := hall.plinth_trophy(int(region))
	if trophy == "" or hall.plinths.has(region):
		return "That plinth is already taken"
	if have(trophy) <= 0:
		return "You have no %s" % item_name(trophy)
	var ns := net_sea()
	if ns != null and bool(ns.call("is_client")):
		ns.call("request_act", "plinth", region)
		return "Asked the harbour master..."
	act_done("plinth", region, 0, my_name(), 0)
	if ns != null and bool(ns.call("active")):
		ns.call("tell_act", "plinth", region, my_name())
	return "The %s stands on its plinth in the trophy hall" % item_name(trophy)


func buy_painting(id: String) -> String:
	var p: Dictionary = rules.cfg.get("paintings", {}).get(id, {})
	if p.is_empty():
		return "?"
	if gallery.bought.has(id):
		return "%s already hangs in the gallery" % String(p.get("name", id))
	if doubloons() < int(p.get("doubloons", 0)):
		return "Not enough doubloons (%d)" % int(p.get("doubloons", 0))
	var ns := net_sea()
	if ns != null and bool(ns.call("is_client")):
		ns.call("request_act", "paint", id)
		return "Asked the harbour master..."
	act_done("paint", id, 0, my_name(), 0)
	if ns != null and bool(ns.call("active")):
		ns.call("tell_act", "paint", id, my_name())
	return "%s hangs in the gallery: step into it to travel" % String(p.get("name", id))


# The host may let it happen (the case still empty, the painting not yet bought and its wall built).
func can_act(kind: String, arg: String) -> bool:
	if kind == "case":
		for c: Dictionary in rules.cfg.get("hall", {}).get("collections", []):
			if String(c["id"]) == arg:
				return rules.level("trophy_hall") >= 2 and not hall.cases.has(arg)
		return false
	if kind == "plinth":
		return rules.level("trophy_hall") >= 3 and hall.plinth_trophy(int(arg)) != "" and not hall.plinths.has(arg)
	if kind == "paint":
		var order: Array = rules.cfg.get("paintings", {}).get("order", [])
		return order.has(arg) and not gallery.bought.has(arg) and rules.level("gallery") > order.find(arg)
	return false


# It happened (here, or the host said so): the one who did it pays (a trophy from his bag, or doubloons); everyone
# sees it. asker / me = network ids (0 = alone or the host's own act).
func act_done(kind: String, arg: String, asker: int, who: String, me: int) -> void:
	var mine := asker == me
	if kind == "case" and not hall.cases.has(arg):
		hall.cases[arg] = who
		if mine:
			var b := bag()
			if b != null:
				b.call("take_all", {"trophy_" + arg: 1})
		hall.show_cases()
	elif kind == "plinth" and not hall.plinths.has(arg):
		hall.plinths[arg] = who
		if mine:
			var bp := bag()
			if bp != null:
				bp.call("take_all", {hall.plinth_trophy(int(arg)): 1})
		hall.show_plinths()
		_notice("%s's trophy stands in the trophy hall" % hall.plinth_boss(int(arg)))
	elif kind == "paint" and not gallery.bought.has(arg):
		gallery.bought.append(arg)
		if mine:
			_spend(int(rules.cfg.get("paintings", {}).get(arg, {}).get("doubloons", 0)))
		gallery.show_bought()
		_notice("%s now hangs in the gallery" % String(rules.cfg.get("paintings", {}).get(arg, {}).get("name", arg)))
	if mine and asker != 0:
		said = "Done"
		window.queue_redraw()


func extra_dict() -> Dictionary:
	return {"cases": hall.cases.duplicate(), "paintings": gallery.bought.duplicate(), "plinths": hall.plinths.duplicate()}


# The host's cases and paintings (sent now and then): a guest's town follows them.
func load_extra(got: Variant) -> void:
	if not got is Dictionary:
		return
	var cases: Variant = (got as Dictionary).get("cases", {})
	var art: Variant = (got as Dictionary).get("paintings", [])
	var changed := false
	if cases is Dictionary and cases.size() <= 16 and str(cases) != str(hall.cases):
		hall.cases.clear()
		for k: Variant in cases:
			hall.cases[String(k).left(24)] = String(cases[k]).left(24)
		hall.show_cases()
		changed = true
	var stands: Variant = (got as Dictionary).get("plinths", {})
	if stands is Dictionary and stands.size() <= 8 and str(stands) != str(hall.plinths):
		hall.plinths.clear()
		for k: Variant in stands:
			hall.plinths[String(k).left(2)] = String(stands[k]).left(24)
		hall.show_plinths()
		changed = true
	if art is Array and art.size() <= 8 and str(art) != str(gallery.bought):
		gallery.bought.clear()
		for a: Variant in art:
			gallery.bought.append(String(a).left(24))
		gallery.show_bought()
		changed = true
	if changed:
		window.queue_redraw()


# Coming home through a return painting: stand before that painting in the gallery once its model is up.
func _arrive() -> void:
	var spot := gallery.arrival(arrive)
	if spot.is_empty():
		spot = gallery.arrival(String(gallery.order()[0])) if not gallery.order().is_empty() else []
	if spot.is_empty():
		return
	arrive = ""
	_player.call("teleport", spot[0], 0.0)
	_player.call("look_at_point", spot[1])


func _spend(doubloons_needed: int) -> bool:
	var s := session()
	var purse: RefCounted = s.call("doubloons") if s != null else null
	return doubloons_needed <= 0 or (purse != null and bool(purse.call("spend", doubloons_needed)))


func _give_boons(spec: Dictionary) -> void:
	var boons: Dictionary = spec.get("boons", {})
	for key: String in boons:
		_player.call("give_boon", key, float(boons[key]), float(spec.get("minutes", 10)) * 60.0)


func _boon_words(spec: Dictionary) -> String:
	var words := PackedStringArray()
	var names := {"speed_pct": "faster", "damage_pct": "more damage", "reload_pct": "faster reloads", "cooldown_pct": "faster skills", "regen_pct": "health back"}
	var boons: Dictionary = spec.get("boons", {})
	for key: String in boons:
		words.append(("+%d%% %s" % [int(boons[key]), String(names.get(key, key))]) if key != "regen_pct" else "%s over time" % String(names[key]))
	return ", ".join(words)


# A feast was ordered (here or by a crewmate online): everyone near the tavern eats.
func feast_here() -> void:
	if not _plots.has("tavern"):
		return
	var feast: Dictionary = rules.cfg.get("feast", {})
	if _player.global_position.distance_to((_plots["tavern"]["holder"] as Node3D).global_position) <= float(feast.get("reach", 80.0)):
		_give_boons(feast)
		_notice("A feast at the tavern: %s" % _boon_words(feast))


# The tavern's talk: an unfound salvage spot pinned on this player's chart, with where it lies.
func rumour() -> String:
	var now := Time.get_ticks_msec() / 1000.0
	var wait := float(rules.cfg.get("rumour_minutes", 20)) * 60.0 - (now - heard_at)
	if wait > 0.0:
		return "Nothing new tonight: come back in %d min" % ceili(wait / 60.0)
	var salvage: Node = _sea.get("salvage")
	var chart: RefCounted = _sea.get("chart")
	var here: Vector3 = _sea.call("local_of", _player.global_position)
	var best: Dictionary = {}
	var best_d := INF
	for spot: Dictionary in salvage.get("cfg")["spots"]:
		if bool(salvage.call("_taken", spot)):
			continue
		var at := Vector2(float(spot["at"][0]), float(spot["at"][1]))
		var pinned := false
		for pin: Vector2 in chart.get("pins"):
			pinned = pinned or pin.distance_to(at) < 30.0
		var d := at.distance_to(Vector2(here.x, here.z))
		if not pinned and d < best_d:
			best_d = d
			best = spot
	if best.is_empty():
		return "The old salts have nothing you have not heard"
	heard_at = now
	var at := Vector2(float(best["at"][0]), float(best["at"][1]))
	chart.call("toggle_pin", at)
	var way := at - Vector2(here.x, here.z)
	var dirs := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var dir := String(dirs[posmod(roundi((atan2(way.x, -way.y) / TAU) * 8.0), 8)])
	return "Rumour: something lies on the sea bed %d m to the %s (pinned on your chart)" % [roundi(best_d), dir]


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
	out.merge(extra_dict())
	return out


func load_world(saved: Variant) -> void:
	rules.from_dict(saved)
	crew_chest.from_list((saved as Dictionary).get("chest", []) if saved is Dictionary else [])
	load_extra(saved)


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
