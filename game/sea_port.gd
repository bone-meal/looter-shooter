# Purpose: the sea's ports (sea step 6): the harbour master's stall at each port of data/sea/port.json (model
# assets/models/sea/harbour_stall.gltf, tools/blender/sea_port.py; it stands in for the port's buildings until the
# home port town of step 7), whose interact key opens the port window (game/port_shop_window.gd: buy, sell, change
# chips into doubloons, ferry), and the DOUBLOONS counter shown at sea. Doubloons and chips are the character's own
# (game/game_session.gd doubloons() / wallet(), saved with him), so trading at a stall needs no host; a crane bought
# here is fitted by the host (game/sea_ships.gd fit_part). A ferry moves only the player (locked: ships, ore and bars
# do not travel by ferry).
# Dependencies: core/sea/port_rules.gd, data/sea/port.json, game/port_shop_window.gd, game/ui_skin.gd; the sea world.
extends Node3D

const PortRules = preload("res://core/sea/port_rules.gd")
const ShopWindow = preload("res://game/port_shop_window.gd")
const UiSkin = preload("res://game/ui_skin.gd")
const MODEL := "res://assets/models/sea/harbour_stall.gltf"
const REACH := 3.2

var rules: PortRules
var window := ShopWindow.new()
var counter := Control.new()  # the doubloons at sea, top right
var _sea: Node3D
var _player: CharacterBody3D
var _stalls := {}  # port id -> Node3D (in the sea root)
var _font: Font = ThemeDB.fallback_font
var _shown_doubloons := -1


func setup(sea_world: Node3D, player: CharacterBody3D, layer: CanvasLayer) -> void:
	_sea = sea_world
	_player = player
	rules = PortRules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/port.json")))
	window.port = self
	layer.add_child(window)
	counter.set_anchors_preset(Control.PRESET_FULL_RECT)
	counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counter.draw.connect(_draw_counter)
	layer.add_child(counter)


func session() -> Node:
	return get_tree().get_first_node_in_group("game_session")


func doubloons() -> RefCounted:
	var s := session()
	return s.call("doubloons") if s != null else null


func chips() -> RefCounted:
	var s := session()
	return s.call("wallet") if s != null else null


func _process(_delta: float) -> void:
	var inside := bool(_sea.get("inside"))
	counter.visible = inside and not window.visible
	if not inside:
		return
	var purse := doubloons()
	var now := int(purse.get("balance")) if purse != null else 0
	if now != _shown_doubloons:
		_shown_doubloons = now
		counter.queue_redraw()
	var here: Vector3 = _sea.call("local_of", _player.global_position)
	for port: Dictionary in rules.cfg["ports"]:  # stalls stand once their island is near
		var id := String(port["id"])
		var at := Vector2(float(port["stall"][0]), float(port["stall"][1]))
		if not _stalls.has(id) and at.distance_to(Vector2(here.x, here.z)) < 600.0 and ResourceLoader.exists(MODEL):
			_stalls[id] = _build_stall(port)


func _build_stall(port: Dictionary) -> Node3D:
	var stall := (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(stall)  # this node hangs in the sea root: its space is sea coordinates
	var x := float(port["stall"][0])
	var z := float(port["stall"][1])
	stall.position = Vector3(x, _ground(x, z), z)
	stall.rotation.y = deg_to_rad(float(port["yaw"]))
	for found in stall.find_children("*", "MeshInstance3D", true, false):
		(found as MeshInstance3D).create_trimesh_collision()
	return stall


# The land's height at a sea position (a ray down; 1 m when nothing is under it yet).
func _ground(x: float, z: float) -> float:
	var top: Vector3 = _sea.call("world_of", Vector3(x, 200.0, z))
	var ray := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -260.0, 0))
	ray.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return (_sea.call("local_of", hit["position"]) as Vector3).y if not hit.is_empty() else 1.0


# The port whose stall this player stands at ("" = none).
func port_here() -> String:
	for id: String in _stalls:
		if (_stalls[id] as Node3D).global_position.distance_to(_player.global_position) <= REACH:
			return id
	return ""


func prompt(key: String) -> String:
	var id := port_here()
	return "[%s] Harbour master: buy, sell, change chips, ferry" % key if id != "" and not window.visible else ""


func interact() -> bool:
	var id := port_here()
	if id == "":
		return false
	open(id)
	return true


func open(id: String) -> void:
	window.open_at(id)
	_player.set("controls_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	window.close()
	_player.set("controls_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- what the window does (all of it the player's own money and goods) ---

func buy(entry: Dictionary) -> String:
	var skills: Variant = _sea.get("skills")
	if skills == null:
		return "Nothing to carry it in"
	var purse: RefCounted = chips() if entry.has("chips") else doubloons()
	var price := int(entry.get("chips", entry.get("doubloons", 0)))
	if purse == null or not bool(purse.call("spend", price)):
		return "Not enough %s" % ("chips" if entry.has("chips") else "doubloons")
	(skills as Node).call("give", String(entry["item"]), int(entry.get("count", 1)))
	return "Bought %s" % item_name(String(entry["item"]))


func buy_crane() -> String:
	var purse := doubloons()
	var price := int(rules.cfg["crane"]["doubloons"])
	if purse == null or not purse.call("can_afford", price):
		return "Not enough doubloons"
	purse.call("spend", price)
	_sea.get("ships").call("fit_part", "crane")
	return "Crane ordered for the ship at the shipyard"


func sell(slot: int) -> String:
	var inv: RefCounted = _player.get("inventory")
	var stack: Dictionary = {"gun": inv.call("gun_at", slot)} if not (inv.call("gun_at", slot) as Dictionary).is_empty() else {"arm": inv.call("arm_at", slot), "id": inv.call("item_id", slot)}
	var price := rules.sell_price(stack)
	if price <= 0:
		return "The harbour master does not buy that"
	inv.call("take_slot", slot)
	doubloons().call("add", price)
	_player.call("refresh_held")
	return "Sold for %d doubloons" % price


func exchange(chip_count: int) -> String:
	var gets := rules.doubloons_for(chip_count)
	var cost := rules.chips_for(gets)
	var purse := chips()
	if gets <= 0 or purse == null or not bool(purse.call("spend", cost)):
		return "Not enough chips (%d chips for a doubloon)" % int(rules.cfg["chips_per_doubloon"])
	doubloons().call("add", gets)
	return "Changed %d chips into %d doubloons" % [cost, gets]


func ferry(port: Dictionary) -> String:
	var dock := Vector3(float(port["dock"][0]), 0.0, float(port["dock"][1]))
	dock.y = _ground(dock.x, dock.z) + 0.6
	close()
	_player.call("teleport", _sea.call("world_of", dock), 0.0)
	return "Ferried to %s" % String(port["name"])


func item_name(id: String) -> String:
	var skills: Variant = _sea.get("skills")
	return String((skills as Node).get("bag").call("item_name", id)) if skills != null else id


# Backpack stacks the stall would buy: [slot, stack, name, tier, price].
func sellable() -> Array:
	var inv: RefCounted = _player.get("inventory")
	var out: Array = []
	for slot in int(inv.get("slot_count")):
		var gun: Dictionary = inv.call("gun_at", slot)
		var arm: Dictionary = inv.call("arm_at", slot)
		if not gun.is_empty():
			out.append([slot, {"gun": gun}, String(load("res://core/gun_stats.gd").call("display_name", _player.get("gun_db"), gun)), String(gun.get("tier", "grey")), rules.sell_price({"gun": gun})])
		elif not arm.is_empty():
			var stack := {"id": inv.call("item_id", slot), "count": 1, "arm": arm}
			var tier := String(arm.get("tier", "grey"))
			out.append([slot, stack, String(load("res://core/armour_stats.gd").call("display_name", _player.get("items"), stack, String(_player.get("gun_db").call("tier", tier)["name"]))), tier, rules.sell_price(stack)])
	return out


func _draw_counter() -> void:
	var view := counter.get_viewport_rect().size
	var text := "%d doubloons" % maxi(_shown_doubloons, 0)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 46.0
	var r := Rect2(Vector2(view.x - w - 24.0, 92.0), Vector2(w, 30.0))
	UiSkin.panel(counter, r)
	counter.draw_circle(r.position + Vector2(17, 15), 8.0, Color(0.92, 0.72, 0.25))
	counter.draw_circle(r.position + Vector2(17, 15), 5.0, Color(0.75, 0.55, 0.15))
	counter.draw_string(_font, r.position + Vector2(32, 21), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT)
