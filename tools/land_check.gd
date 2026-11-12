# Purpose: developer check of the islands' land rules (core/archipelago.gd with data/archipelago.json): the islands do
# not touch, every bridge runs shore to shore over water, heights, which island a spot belongs to, washing up, where
# enemies may come out of the sea, debris prices and what clearing them opens, the things that stand on the islands.
# Log tools/land_check.log (ends LAND_CHECK_DONE problems=n).
# Dependencies: core/archipelago.gd, core/data_store.gd.
extends Node

const Archipelago = preload("res://core/archipelago.gd")
const DataStore = preload("res://core/data_store.gd")
const ShelterRules = preload("res://core/shelter_rules.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var land := Archipelago.new(DataStore.load_json("res://data/archipelago.json"))
	var names := PackedStringArray()
	var apart := true
	for i in land.islands.size():
		names.append("%s r%.0f" % [land.islands[i]["name"], float(land.islands[i]["radius"])])
		for j in range(i + 1, land.islands.size()):
			var gap := (land.islands[i]["at"] as Vector2).distance_to(land.islands[j]["at"]) - float(land.islands[i]["radius"]) - float(land.islands[j]["radius"])
			apart = apart and gap > 8.0
	_say("%d islands (%s), none nearer than 8 m to another" % [land.islands.size(), ", ".join(names)], apart and land.islands.size() >= 2 and land.islands.size() <= 4)
	var ways := PackedStringArray()
	var ways_fine := land.bridges.size() >= 1
	var last_price := 0
	for i in land.bridges.size():
		var entry: Dictionary = land.bridges[i]
		var a: Vector2 = entry["a"]
		var b: Vector2 = entry["b"]
		var mid: Vector2 = entry["mid"]
		ways.append("%s-%s %.0f m %d" % [land.islands[int(entry["from"])]["id"], land.islands[int(entry["to"])]["id"], a.distance_to(b), land.price(i)])
		ways_fine = ways_fine and land.on_land(a.x, a.y) and land.on_land(b.x, b.y) and not land.on_land(mid.x, mid.y) and land.height_at(mid.x, mid.y) < land.sea_level - 1.5
		ways_fine = ways_fine and land.deck_at(mid.x, mid.y) == i and land.price(i) > last_price and not land.is_open(i)
		last_price = land.price(i)
	_say("ways: %s; each from dry sand to dry sand over deep water, dearer each time" % ", ".join(ways), ways_fine)

	var home: Dictionary = land.islands[0]
	_say("the spawn island's middle is flat ground (0), its waterline is at the sea's height", is_zero_approx(land.height_at(0.0, 0.0)) and absf(land.height_at(float(home["radius"]), 0.0) - land.sea_level) < 0.12)
	var second: Vector2 = land.islands[1]["at"]
	_say("a spot on the second island belongs to it, and so does the water just off it", land.island_near(second.x + 3.0, second.y) == 1 and land.island_near(second.x, second.y - float(land.islands[1]["radius"]) - 5.0) == 1)
	var dry := land.wash_up(5.0, 5.0)
	var wet := land.wash_up(second.x, second.y - float(land.islands[1]["radius"]) - 9.0)
	var forced := land.wash_up(second.x, second.y, 0)
	_say("washing up: dry land stays (%s), a spot in the sea comes 1.5 m inside the nearest shore (%s), a named island wins (%s)" % [dry, wet, forced],
		dry.is_equal_approx(Vector3(5, land.height_at(5, 5), 5)) and absf(Vector2(wet.x, wet.z).distance_to(second) - (float(land.islands[1]["radius"]) - 1.5)) < 0.01 and land.on_land(wet.x, wet.z)
		and absf(Vector2(forced.x, forced.z).length() - (float(home["radius"]) - 1.5)) < 0.01)
	_say("the islands' area: the middle of the farthest island counts, a spot 400 m away does not", land.within((land.islands[2]["at"] as Vector2).x, (land.islands[2]["at"] as Vector2).y) and land.within(0.0, 0.0) and not land.within(400.0, 0.0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var found := 0
	var bad := 0
	for isle in land.islands.size():
		for _n in 400:
			var spot: Vector3 = land.sea_spot(isle, rng)
			if not spot.is_finite():
				continue
			found += 1
			var from_shore := Vector2(spot.x, spot.z).distance_to(land.islands[isle]["at"]) - float(land.islands[isle]["radius"])
			if spot.y > land.sea_level - 0.6 or from_shore < float(land.cfg["spawn_ring"][0]) - 0.01 or from_shore > float(land.cfg["spawn_ring"][1]) + 0.01 or land.island_near(spot.x, spot.z) != isle or land.deck_at(spot.x, spot.z) >= 0:
				bad += 1
	_say("1600 asks for a place to come out of the sea: %d found, %d of them wrong (dry, off the ring, at a bridge)" % [found, bad], found > 1500 and bad == 0)
	var toward := (second - (home["at"] as Vector2)).angle()
	var near_bearing := 0
	for _n in 200:
		var spot: Vector3 = land.sea_spot(0, rng, toward + 1.2, 0.5)
		if spot.is_finite() and absf(angle_difference(Vector2(spot.x, spot.z).angle(), toward + 1.2)) < 0.55:
			near_bearing += 1
	_say("a swimmer comes up on the side it is asked for (%d of 200)" % near_bearing, near_bearing > 170)

	_say("on the big island enemies come up within %.0f degrees of their prey's side, on a small one within %.0f" % [rad_to_deg(land.arc_of(0)), rad_to_deg(land.arc_of(1))], land.arc_of(0) < 1.0 and land.arc_of(1) > land.arc_of(0) and land.arc_of(1) <= PI)
	_say("left behind = on another island and far: not on the same island however far, not on a neighbour's near shore", land.left_behind(second.x, second.y, 0.0, 0.0) and not land.left_behind(-38.0, 0.0, 38.0, 0.0) and not land.left_behind(42.0, -38.0, 30.0, -27.0))
	var mid: Vector2 = land.bridges[0]["mid"]
	var before: Vector2 = mid + ((land.bridges[0]["a"] as Vector2) - mid).normalized() * 2.5
	_say("standing 2.5 m before the first debris: it is the one near, and it leads to %s" % land.far_side(0, before.x, before.y), land.debris_near(before.x, before.y) == 0 and land.far_side(0, before.x, before.y) == String(land.islands[1]["name"]) and land.debris_near(0.0, 0.0) == -1)
	_say("before anything is cleared only the spawn island can be reached", land.reachable() == ([true, false, false, false] as Array[bool]))
	_say("clearing the first debris opens the second island; clearing it twice does nothing", land.open(0) and not land.open(0) and land.reachable() == ([true, true, false, false] as Array[bool]) and land.debris_near(before.x, before.y) == -1 and land.open_list() == PackedInt32Array([0]))
	land.open(3)
	_say("the dearest debris joins the last island straight to the spawn island", land.reachable() == ([true, true, false, true] as Array[bool]))
	land.close_all()
	_say("game over closes every way again", land.open_list().is_empty() and land.reachable() == ([true, false, false, false] as Array[bool]))

	var arena: Dictionary = land.place_of("painting_arena")
	var fantasy: Dictionary = land.place_of("painting_fantasy")
	var spawn: Dictionary = land.place_of("spawn")
	var arena_at: Vector2 = arena["at"]
	_say("the colosseum painting stands on the second island's flat ground facing the way from the spawn island; the Aurelind painting and the spawn are on the spawn island",
		land.island_near(arena_at.x, arena_at.y) == 1 and is_zero_approx(land.height_at(arena_at.x, arena_at.y)) and Vector2(sin(float(arena["yaw"])), cos(float(arena["yaw"]))).dot((home["at"] as Vector2) - arena_at) > 0.0
		and land.island_near((fantasy["at"] as Vector2).x, (fantasy["at"] as Vector2).y) == 0 and is_zero_approx(land.height_at((spawn["at"] as Vector2).x, (spawn["at"] as Vector2).y)))

	var weapons: Dictionary = DataStore.load_json("res://data/weapons.json")["weapons"]
	var chalk: Dictionary = DataStore.load_json("res://data/chalk_guns.json")["cells"]
	var boards := PackedStringArray()
	var boards_fine := land.wall_buys.size() == weapons.size()
	for i in land.wall_buys.size():
		var board: Dictionary = land.wall_buys[i]
		var at: Vector2 = board["at"]
		boards.append("%s %d on %s" % [board["gun"], int(board["price"]), land.islands[int(board["island"])]["id"]])
		boards_fine = boards_fine and weapons.has(String(board["gun"])) and chalk.has(String(board["gun"])) and int(board["price"]) > 0 and is_zero_approx(land.height_at(at.x, at.y)) and land.island_near(at.x, at.y) == int(board["island"])
		boards_fine = boards_fine and land.wall_buy_near(at.x + 1.0, at.y, 2.8) == i and land.ammo_price(i) == roundi(float(board["price"]) * 0.5)
		for j in i:
			boards_fine = boards_fine and at.distance_to(land.wall_buys[j]["at"]) > 8.0
	_say("wall buys: %s; each gun once, on flat ground of its island, apart from the others, ammo at half price" % ", ".join(boards), boards_fine and land.wall_buy_near(0.0, 0.0, 2.8) == -1)

	# shelters
	var huts := ShelterRules.new(land.cfg["windows"], land.shelters)
	var huts_fine := huts.huts.size() == land.shelters.size() and huts.windows.size() == huts.huts.size() * 3 and huts.doors.size() == huts.huts.size()
	for hut in huts.huts.size():
		var at: Vector2 = huts.huts[hut]["at"]
		var isle := int(land.shelters[hut]["island"])
		var door: Dictionary = huts.doors[hut]
		huts_fine = huts_fine and is_zero_approx(land.height_at(at.x, at.y)) and land.island_near(at.x, at.y) == isle and huts.hut_of(at.x, at.y) == hut
		huts_fine = huts_fine and huts.hut_of((door["step"] as Vector2).x, (door["step"] as Vector2).y) == -1 and huts.hut_of((door["in"] as Vector2).x, (door["in"] as Vector2).y) == hut
		huts_fine = huts_fine and (door["step"] as Vector2).distance_to(land.islands[isle]["at"]) < at.distance_to(land.islands[isle]["at"])  # the door looks inland
		for board: Dictionary in land.wall_buys:
			huts_fine = huts_fine and at.distance_to(board["at"]) > 8.0
		for id: String in ["spawn", "painting_arena", "painting_fantasy"]:
			huts_fine = huts_fine and at.distance_to(land.place_of(id)["at"]) > 9.0
	for i in huts.windows.size():
		var opening: Dictionary = huts.windows[i]
		var hut := int(opening["hut"])
		huts_fine = huts_fine and huts.hut_of((opening["out"] as Vector2).x, (opening["out"] as Vector2).y) == -1 and huts.hut_of((opening["in"] as Vector2).x, (opening["in"] as Vector2).y) == hut
		huts_fine = huts_fine and is_zero_approx(land.height_at((opening["out"] as Vector2).x, (opening["out"] as Vector2).y)) and huts.window_near((opening["in"] as Vector2).x, (opening["in"] as Vector2).y) == i and huts.boards[i] == huts.full()
	_say("%d huts with a door looking inland and three boarded windows each, on flat ground, clear of boards and paintings" % huts.huts.size(), huts_fine and huts.huts.size() >= 1)
	var prey: Vector2 = huts.huts[0]["at"]
	var first: Dictionary = huts.windows[0]
	var far_out: Vector2 = (first["out"] as Vector2) + ((first["out"] as Vector2) - (first["mid"] as Vector2)) * 6.0
	var at_window: Vector2 = first["out"]
	var clock := 100.0
	_say("both in the open: straight at the prey; prey inside: to the nearest window", huts.guide(far_out.x, far_out.y, far_out.x + 3.0, far_out.y, clock).is_empty() and huts.guide(far_out.x, far_out.y, prey.x, prey.y, clock).get("goal") == at_window)
	var torn := 0
	var early := huts.guide(at_window.x, at_window.y, prey.x, prey.y, clock).has("tore")
	var hopped := false
	var seconds := 0.0
	while seconds < 30.0 and not hopped:
		seconds += 0.5
		var move: Dictionary = huts.guide(at_window.x, at_window.y, prey.x, prey.y, clock + seconds)
		if move.has("tore"):
			torn += 1
		hopped = move.has("hop") and move["hop"] == first["in"]
	_say("at the window: nothing torn on arrival, then %d boards one by one, then it climbs in after %.1f s in all" % [torn, seconds], not early and torn == huts.full() and hopped and huts.boards[0] == 0 and seconds >= float(huts.full()) * float(land.cfg["windows"]["tear_seconds"]))
	var door0: Dictionary = huts.doors[0]
	huts.set_boards(1, 0)
	var second_window: Vector2 = huts.windows[1]["out"]
	_say("a full hut lets nobody else climb in; with room the next one does", not huts.guide(second_window.x, second_window.y, prey.x, prey.y, clock + 60.0, 1.4, false).has("hop") and huts.guide(second_window.x, second_window.y, prey.x, prey.y, clock + 60.0, 1.4, true).has("hop"))
	huts.board_all()
	huts.set_boards(0, 0)
	var steps_out: Dictionary = huts.guide((door0["in"] as Vector2).x, (door0["in"] as Vector2).y, far_out.x, far_out.y, clock)
	_say("inside with the prey gone outside: to the door, then set down outside it, the next one a moment later", huts.guide(prey.x, prey.y, far_out.x, far_out.y, clock).get("goal") == door0["in"] and steps_out.get("hop") == door0["step"]
		and huts.guide((door0["in"] as Vector2).x, (door0["in"] as Vector2).y, far_out.x, far_out.y, clock + 0.1).get("goal") == door0["in"] and huts.guide(prey.x, prey.y, prey.x + 1.0, prey.y, clock).is_empty())
	clock = 200.0
	var pays := huts.nail(0, clock)
	var too_soon := huts.nail(0, clock + 0.1)
	var paid_total := pays
	var nailed := 1
	for n in 40:
		clock += 1.0
		if huts.boards[0] >= huts.full():
			huts.set_boards(0, 0)  # torn down again
		var got := huts.nail(0, clock)
		if got >= 0:
			nailed += 1
			paid_total += got
	huts.board_all()
	huts.set_boards(0, 0)
	_say("nailing: a board pays %d, not twice within %.1f s; %d boards in a round paid %d in all (the first %d are paid)" % [pays, float(land.cfg["windows"]["repair_seconds"]), nailed, paid_total, int(land.cfg["windows"]["paid_per_round"])],
		pays == int(land.cfg["windows"]["repair_points"]) and too_soon == -1 and nailed == 41 and paid_total == int(land.cfg["windows"]["paid_per_round"]) * pays)
	huts.new_round()
	huts.set_boards(0, 0)
	_say("a new round pays again; a full window takes no board; the carpenter makes every window whole", huts.nail(0, clock + 5.0) == pays and huts.nail(1, clock + 5.0) == -1 and huts.boards[0] == 1)
	huts.board_all()
	_say("... all whole", huts.boards.count(huts.full()) == huts.boards.size())

	_lines.append("LAND_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/land_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
