# Purpose: SHIP'S HOLDS (sea step 8b-2; director: real holds below deck on the brig, galleon and junk). The hold itself is
# modelled with the ship (tools/blender/sea_ships.py, node "Hold") and solid by game/sea_ship.gd; this node does the
# rest for the whole fleet: the sea is kept out of every near hold (game/sea_ocean.gd dry boxes), the interior is drawn
# only near the camera, the lantern lights while this player is below, flood water rises inside with the ship's water,
# and the CARGO CHEST: goods of the fantasy bag (bars, logs, planks, potions...) stowed aboard, as many kinds as the
# hold's slots (data/sea/ships.json hold.slots). Cargo belongs to the host's world fleet (saved with her, lost when she
# sinks); online a player asks the host to stow or take (game/net_sea.gd request_cargo), as at the crew's chest.
# Dependencies: core/sea/town_store.gd, game/store_window.gd, data/sea/ships.json "hold", the fleet (game/sea_ships.gd:
# ships, rules, ship_aboard, _net), the sea world (ocean, skills, notice), the player.
extends Node3D

const TownStore = preload("res://core/sea/town_store.gd")
const StoreWindow = preload("res://game/store_window.gd")
const CHEST_REACH := 1.7
const SHOW_WITHIN := 45.0  # m from the camera: a hold's insides are drawn
const DRY_WITHIN := 160.0  # m: holds that keep the sea out (four at most)

var window := StoreWindow.new()
var open_ship: Node3D = null  # the ship whose hold window is open
var store_title := "SHIP'S HOLD"
var lost := 0  # dev / checks: cargoes that went down with their ship
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _layer := CanvasLayer.new()
var _stores := {}  # ship -> TownStore (built from ship.state["cargo"])
var _extras := {}  # ship -> {"lamp": OmniLight3D, "water": MeshInstance3D}


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	_layer.layer = 6
	add_child(_layer)
	window.town = self
	_layer.add_child(window)


func _net() -> Node:
	return _fleet.call("_net")


func _host() -> bool:
	var net := _net()
	return net == null or not bool(net.call("is_client"))


static func has_hold(ship: Node3D) -> bool:
	return not (ship.get("spec") as Dictionary).get("hold", {}).is_empty()


# --- the cargo ---

func chest_of(ship: Node3D) -> RefCounted:
	var store: RefCounted = _stores.get(ship)
	if store == null:
		store = TownStore.new()
		_stores[ship] = store
	var st: Dictionary = ship.get("state")
	store.call("from_list", st.get("cargo", []))
	store.set("capacity", int((ship.get("spec") as Dictionary)["hold"].get("slots", 24)))
	return store


func _keep(ship: Node3D, store: RefCounted) -> void:
	(ship.get("state") as Dictionary)["cargo"] = store.call("to_list")


# The store window asks these (same names as the town's storehouse).
func chest() -> RefCounted:
	return chest_of(open_ship) if is_instance_valid(open_ship) else TownStore.new()


func chest_shared() -> bool:
	return true


func bag() -> RefCounted:
	var skills: Variant = _sea.get("skills")
	return (skills as Node).get("bag") if skills != null else null


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


func item_def(item: String) -> Dictionary:
	var b := bag()
	return b.call("def", item) if b != null else {}


func item_name(item: String) -> String:
	var b := bag()
	return String(b.call("item_name", item)) if b != null else item


func put(item: String, n: int) -> String:
	var b := bag()
	n = mini(n, int(b.call("count", item)) if b != null else 0)
	if n <= 0 or not is_instance_valid(open_ship):
		return "You have none"
	var store := chest_of(open_ship)
	if not bool(store.call("can_put", item)):
		return "The hold is full"
	if not _host():
		_net().call("request_cargo", (_fleet.get("ships") as Array).find(open_ship), "put", item, n)
		return "..."
	var went := int(store.call("put", item, n))
	b.call("remove", item, went)
	_keep(open_ship, store)
	_told(open_ship)
	return "Stowed %d %s" % [went, item_name(item)]


func take(item: String, n: int) -> String:
	var b := bag()
	if not is_instance_valid(open_ship) or b == null:
		return "None in the hold"
	var store := chest_of(open_ship)
	n = mini(n, int(store.call("count", item)))
	if n <= 0:
		return "None in the hold"
	if not _host():
		_net().call("request_cargo", (_fleet.get("ships") as Array).find(open_ship), "take", item, n)
		return "..."
	var got := int(store.call("take", item, n))
	(_sea.get("skills") as Node).call("give", item, got)
	_keep(open_ship, store)
	_told(open_ship)
	return "Took %d %s" % [got, item_name(item)]


# Host: a player's ask from another machine (game/net_sea.gd checks he stands in that hold). Returns how many.
func host_cargo(ship: Node3D, op: String, item: String, n: int) -> int:
	var store := chest_of(ship)
	var did := int(store.call("put" if op == "put" else "take", item, n))
	_keep(ship, store)
	_told(ship)
	return did


# Client: the host did it; our bag follows now.
func cargo_done(op: String, item: String, n: int) -> void:
	var b := bag()
	if n <= 0 or b == null:
		window.said = "The hold is full" if op == "put" else "None in the hold"
		return
	if op == "put":
		b.call("remove", item, n)
		window.said = "Stowed %d %s" % [n, item_name(item)]
	else:
		(_sea.get("skills") as Node).call("give", item, n)
		window.said = "Took %d %s" % [n, item_name(item)]


func _told(ship: Node3D) -> void:
	var net := _net()
	if net != null and bool(net.call("active")) and bool(net.call("is_host")):
		net.call("tell_cargo", (_fleet.get("ships") as Array).find(ship), (ship.get("state") as Dictionary).get("cargo", []))


# Host: every hold's cargo (sent every few seconds: a late joiner sees what is aboard).
func all_cargo() -> Array:
	var out: Array = []
	var ships: Array = _fleet.get("ships")
	for i in ships.size():
		if has_hold(ships[i]):
			out.append([i, (ships[i].get("state") as Dictionary).get("cargo", [])])
	return out


# --- the chest's prompt and window ---

func in_hold_of(ship: Node3D) -> bool:
	return has_hold(ship) and bool(_fleet.get("rules").call("in_hold", String(ship.get("state")["ship"]), ship.global_transform.affine_inverse() * _player.global_position))


func _at_chest(ship: Node3D) -> bool:
	var spot: Array = (ship.get("spec") as Dictionary)["hold"]["chest"]
	var local := ship.global_transform.affine_inverse() * _player.global_position
	return in_hold_of(ship) and Vector2(local.x - float(spot[0]), local.z - float(spot[1])).length() <= CHEST_REACH


func prompt(key: String, ship: Node3D) -> String:
	if ship == null or not has_hold(ship) or (ship.get("state") as Dictionary).has("foe") or not _at_chest(ship):
		return ""
	var store := chest_of(ship)
	return "[%s] Open the hold's cargo chest (%d / %d)" % [key, (store.get("slots") as Array).size(), int(store.get("capacity"))]


func interact(ship: Node3D) -> bool:
	if prompt("F", ship) == "":
		return false
	open_ship = ship
	window.open()
	_player.set("controls_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


func close_store() -> void:
	window.close()
	open_ship = null
	_player.set("controls_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- every frame: the sea kept out, insides near the camera, the lantern, flood water, sunk cargo ---

func _process(_delta: float) -> void:
	if not bool(_sea.call("running")):
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else _player.global_position
	var dry: Array = []
	var near: Array = []
	for ship: Node3D in _fleet.get("ships"):
		if not has_hold(ship):
			continue
		var d := ship.global_position.distance_to(eye)
		var parts: Dictionary = ship.get("_parts")
		if parts.has("Hold"):
			(parts["Hold"] as Node3D).visible = d < SHOW_WITHIN
		if d < DRY_WITHIN:
			near.append([d, ship])
		_extras_follow(ship, d)
		var st: Dictionary = ship.get("state")
		if _host() and bool(st.get("sinking", false)) and not (st.get("cargo", []) as Array).is_empty():
			st["cargo"] = []  # her cargo goes down with her
			lost += 1
			_told(ship)
			if in_hold_of(ship) or ship == _fleet.call("ship_aboard"):
				_sea.emit_signal("notice", "Her cargo went down with her")
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for pair: Array in near.slice(0, 4):
		dry.append(_dry_box(pair[1]))
	var ocean: Variant = _sea.get("ocean")
	if ocean != null:
		(ocean as Node).call("set_dry", dry)
	if window.visible and (not is_instance_valid(open_ship) or not _at_chest(open_ship)):
		close_store()


# The hold's inside as a unit box in the scene (the sea is not drawn in it).
func _dry_box(ship: Node3D) -> Transform3D:
	var spec: Dictionary = ship.get("spec")
	var hold: Dictionary = spec["hold"]
	var y0 := float(hold["floor"]) - 0.4
	var y1 := float(spec["deck"]) - 0.13
	var centre := Vector3(0.0, (y0 + y1) * 0.5, (float(hold["from"]) + float(hold["to"])) * 0.5)
	var half := Vector3(float(hold["hw"]) + 0.15, (y1 - y0) * 0.5, (float(hold["to"]) - float(hold["from"])) * 0.5 + 0.15)
	return ship.global_transform * Transform3D(Basis.from_scale(half), centre)


func _extras_follow(ship: Node3D, d: float) -> void:
	var spec: Dictionary = ship.get("spec")
	var hold: Dictionary = spec["hold"]
	if not _extras.has(ship):
		if d > SHOW_WITHIN:
			return
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.75, 0.45)
		lamp.light_energy = 1.6
		lamp.omni_range = 7.0
		lamp.shadow_enabled = false
		lamp.position = Vector3(float(hold["lamp"][0]), float(spec["deck"]) - 0.55, float(hold["lamp"][1]))
		ship.add_child(lamp)
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(float(hold["hw"]) * 2.0, float(hold["to"]) - float(hold["from"]))
		water.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.3, 0.32, 0.82)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.1
		water.material_override = mat
		water.position = Vector3(0.0, float(hold["floor"]), (float(hold["from"]) + float(hold["to"])) * 0.5)
		ship.add_child(water)
		_extras[ship] = {"lamp": lamp, "water": water}
	var e: Dictionary = _extras[ship]
	(e["lamp"] as OmniLight3D).visible = in_hold_of(ship) or d < 6.0
	var flood := float(ship.get("state").get("water", 0.0))
	var w: MeshInstance3D = e["water"]
	w.visible = flood > 0.02 and d < SHOW_WITHIN
	w.position.y = float(hold["floor"]) + flood * (float(spec["deck"]) - float(hold["floor"])) * 0.85


func forget(ship: Node3D) -> void:
	_stores.erase(ship)
	_extras.erase(ship)
	if open_ship == ship:
		close_store()


func status() -> String:
	var parts := PackedStringArray()
	var ships: Array = _fleet.get("ships")
	for i in ships.size():
		if has_hold(ships[i]):
			var store := chest_of(ships[i])
			parts.append("%d %s %d/%d%s" % [i, String(ships[i].get("state")["ship"]), (store.get("slots") as Array).size(), int(store.get("capacity")), " (you below)" if in_hold_of(ships[i]) else ""])
	return "holds [%s], lost %d" % [", ".join(parts), lost]
