# Purpose: (polish1 D4c) developer check of the treetop village (core/treetop_rules.gd with data/treetops.json and
# data/archipelago.json): every deck can be reached from the ground, ways join what they say, bridges are short and
# level enough, ladders and lifts stand on dry flat ground (or on the deck below), stilts and way feet are clear of
# rocks, trees and the things placed on the islands, every way end is found where a player stands to use it.
# Run: godot --headless --path . --script res://tools/treetop_check.gd  (TREETOP lines, ends "problems n").
# Dependencies: core/treetop_rules.gd, core/archipelago.gd, core/data_store.gd.
extends SceneTree

const Archipelago = preload("res://core/archipelago.gd")
const DataStore = preload("res://core/data_store.gd")
const TreetopRules = preload("res://core/treetop_rules.gd")
const FILES := ["perks", "traps", "upgrade_machine", "power", "buildables", "mystery_box", "zombies/quest", "archipelago"]

var _problems := 0
var _land: Archipelago
var _spots: Array = []  # [Vector2, how near nothing may stand]


func _init() -> void:
	_land = Archipelago.new(DataStore.load_json("res://data/archipelago.json"))
	for f: String in FILES:
		_walk(DataStore.load_json("res://data/%s.json" % f), f)
	for wb: Dictionary in _land.wall_buys:
		_spots.append([wb["at"], 1.5])
	var tops := TreetopRules.new(DataStore.load_json("res://data/treetops.json"), _land)
	# reach: every deck from the ground
	var reached := {}
	var grew := true
	while grew:
		grew = false
		for w: Dictionary in tops.ways:
			var f := int(w["from"])
			var t := int(w["to"])
			if (f < 0 or reached.has(f)) and not reached.has(t):
				reached[t] = true
				grew = true
			if w["kind"] in ["bridge", "catwalk", "link", "stairs"] and reached.has(t) and f >= 0 and not reached.has(f):
				reached[f] = true
				grew = true
	for i in tops.decks.size():
		if not reached.has(i):
			_problem("deck %s cannot be reached from the ground" % tops.decks[i]["id"])
	for i in tops.ways.size():
		var w: Dictionary = tops.ways[i]
		var id := String(w["id"])
		if bool(w.get("free", false)):
			_check_free(tops, w)
			continue
		match String(w["kind"]):
			"bridge", "catwalk":
				var a: Vector3 = w["a"]
				var b: Vector3 = w["b"]
				var flat := Vector2(b.x - a.x, b.z - a.z).length()
				var longest := 30.0 if w["kind"] == "bridge" else 70.0
				if flat < 2.0 or flat > longest or absf(a.y - b.y) > flat * 0.15:
					_problem("%s %s: %.1f m long, rises %.1f m" % [w["kind"], id, flat, b.y - a.y])
				if w["kind"] == "catwalk":  # its pylons: on clear ground or in the sea, never in an island thing; no span over 24 m
					var last := Vector2(a.x, a.z)
					for p: Vector2 in (w["pylons"] as Array) + [Vector2(b.x, b.z)]:
						if p.distance_to(last) > 24.0:
							_problem("catwalk %s: a %.1f m span without a pylon" % [id, p.distance_to(last)])
						last = p
					for p: Vector2 in w["pylons"]:
						if _land.height_at(p.x, p.y) >= -0.05 and _why_not_clear(p, 0.8) != "":
							_problem("catwalk %s: a pylon at (%.1f, %.1f): %s" % [id, p.x, p.y, _why_not_clear(p, 0.8)])
			_:
				var foot: Vector3 = w["foot"]
				if int(w["from"]) < 0:
					var why := _why_not_clear(Vector2(foot.x, foot.z), 0.8)
					if why != "":
						_problem("%s %s: its foot at (%.1f, %.1f) is not on clear flat ground: %s" % [w["kind"], id, foot.x, foot.z, why])
				elif tops.deck_at(foot.x, foot.y, foot.z) != int(w["from"]):
					_problem("%s %s: its foot is not on its lower deck" % [w["kind"], id])
				else:
					var low: Dictionary = tops.decks[int(w["from"])]
					var behind := Vector2(foot.x, foot.z) - (w["face"] as Vector2) * 0.55  # where a climber stands behind it: still 0.5 m (a body) inside the railing
					if tops.deck_at(behind.x, foot.y, behind.y) != int(w["from"]) or (low["kind"] == "ring" and behind.distance_to(low["at"]) > float(low["outer"]) - 0.5):
						_problem("%s %s: no room to stand behind its foot on the lower deck" % [w["kind"], id])
		for e in 2:
			var stand: Vector3 = w["ends"][e]
			if tops.way_near(stand.x, stand.y, stand.z) != i:
				_problem("way %s end %d: standing there finds way %d" % [id, e, tops.way_near(stand.x, stand.y, stand.z)])
			var deck_here := tops.deck_at(stand.x, stand.y, stand.z)
			var want := int(w["to"]) if e == 1 else int(w["from"])
			if want >= 0 and deck_here != want:
				_problem("way %s end %d stands off its deck" % [id, e])
			if want < 0 and _why_not_clear(Vector2(stand.x, stand.z), 0.5) != "":
				_problem("way %s end %d (ground) at (%.1f, %.1f) is not clear flat ground: %s" % [id, e, stand.x, stand.z, _why_not_clear(Vector2(stand.x, stand.z), 0.5)])
	for d: Dictionary in tops.decks:  # the offshore decks with legs stand in open water, 8 m off every shore
		if d["kind"] == "rig" and bool(d["legs"]):
			var at_r: Vector2 = d["at"]
			var half_r: Vector2 = d["outer"]
			for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2.ZERO]:
				var q := at_r + corner * half_r
				for isle: Dictionary in _land.islands:
					if q.distance_to(isle["at"]) < float(isle["radius"]) + 8.0:
						_problem("deck %s: its corner (%.1f, %.1f) is within 8 m of %s's shore" % [d["id"], q.x, q.y, isle["id"]])
	for d: Dictionary in tops.decks:
		if d["kind"] != "stilts":
			continue
		var at: Vector2 = d["at"]
		var half: Vector2 = d["outer"]
		for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var p := at + corner * (half - Vector2(0.45, 0.45))
			var why_s := _why_not_clear(p, 0.6)
			if why_s != "":
				_problem("deck %s: a stilt at (%.1f, %.1f): %s" % [d["id"], p.x, p.y, why_s])
	# (part 3) the buys up high: each on its deck with room in front, guns once across the islands and up here, real perks
	var weapons: Dictionary = DataStore.load_json("res://data/weapons.json")["weapons"]
	var perks: Dictionary = DataStore.load_json("res://data/perks.json")["perks"]
	var guns := {}
	for wb: Dictionary in _land.wall_buys:
		guns[String(wb["gun"])] = true
	var reforges := 0
	for b: Dictionary in tops.buys:
		var at: Vector2 = b["at"]
		var y := float(b["y"])
		var front := at + Vector2(sin(float(b["yaw"])), cos(float(b["yaw"]))) * 1.8
		if tops.deck_at(at.x, y, at.y) != int(b["deck"]) or tops.deck_at(front.x, y, front.y) != int(b["deck"]):
			_problem("buy %s %s: it or the spot in front of it is off its deck" % [b["kind"], b["gun"] + b["perk"]])
		match String(b["kind"]):
			"wall":
				if not weapons.has(String(b["gun"])) or guns.has(String(b["gun"])) or int(b["price"]) <= 0:
					_problem("wall buy %s: unknown, priced %d, or a second board of that gun" % [b["gun"], int(b["price"])])
				guns[String(b["gun"])] = true
			"perk":
				if not perks.has(String(b["perk"])):
					_problem("perk %s up high does not exist" % b["perk"])
			"reforge":
				reforges += 1
	if reforges > 1:
		_problem("%d Re-forges up high (one machine)" % reforges)
	print("TREETOP %d buys up high, %d guns on boards in all" % [tops.buys.size(), guns.size()])
	var opened := 0
	for i in tops.ways.size():
		opened += 1 if tops.open(i) else 0
	var on_any := 0
	for w: Dictionary in tops.ways:
		if w["kind"] == "ladder":
			var mid: Vector3 = ((w["foot"] as Vector3) + (w["top"] as Vector3)) * 0.5
			on_any += 1 if tops.on_ladder(mid.x, mid.y, mid.z) else 0
	print("TREETOP %d villages, %d decks, %d ways (%d ladders climbable in the middle), all opened %d" % [(tops.cfg["villages"] as Array).size(), tops.decks.size(), tops.ways.size(), on_any, opened])
	print("TREETOP_DONE problems=%d" % _problems)
	quit()


func _walk(v: Variant, where: String) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		if d.get("island") is String and d.get("at") is Array and _land.index_of(String(d["island"])) >= 0:
			_spots.append([_land.on_island(String(d["island"]), d["at"]), 7.5 if where.contains("shelters") else 1.5])
		for k: Variant in d:
			_walk(d[k], "%s.%s" % [where, str(k)])
	elif v is Array:
		for x: Variant in v:
			_walk(x, where)


# "" when a plan spot is dry, flat (hills count) and clear of rocks / tree trunks (a giant tree's low roots are fine)
# and of the things placed on the islands; else what is in the way.
func _why_not_clear(p: Vector2, margin: float) -> String:
	if _land.height_at(p.x, p.y) < -0.05:
		return "water"
	if not is_zero_approx(_land.height_at(p.x, p.y)):
		return "a slope"
	for b: Dictionary in _land.blocks:
		var reach := float(b["core"]) + 0.6 if String(b["kind"]) == "tree" else float(b["half_width"])
		var a: Vector2 = b["a"]
		var e: Vector2 = b["b"]
		var t := 0.0 if a.distance_squared_to(e) < 0.001 else clampf((p - a).dot(e - a) / a.distance_squared_to(e), 0.0, 1.0)
		if p.distance_to(a.lerp(e, t)) < reach + margin:
			return "a %s" % b["kind"]
	for s: Array in _spots:
		if (s[0] as Vector2).distance_to(p) < float(s[1]) + margin:
			return "a placed thing at %s" % str(s[0])
	return ""


# The offshore complex's own stairs and links: they join the decks they say, a stair climbs no steeper than 35 deg.
func _check_free(tops: TreetopRules, w: Dictionary) -> void:
	if w["kind"] == "stairs":
		var s0: Vector3 = w["start"]
		var s1: Vector3 = w["end"]
		var run := Vector2(s1.x - s0.x, s1.z - s0.z).length()
		var rise := s1.y - s0.y
		if run < 1.0 or rad_to_deg(atan2(rise, run)) > 35.0:
			_problem("%s: rises %.1f m over %.1f m" % [w["id"], rise, run])
		if tops.deck_at(s0.x, s0.y, s0.z) != int(w["from"]):
			_problem("%s: starts off its lower deck" % w["id"])
	else:
		var a: Vector3 = w["a"]
		var b: Vector3 = w["b"]
		if tops.deck_at(a.x, a.y, a.z) != int(w["from"]) or tops.deck_at(b.x, b.y, b.z) != int(w["to"]) or absf(a.y - b.y) > 0.1:
			_problem("%s: its ends are not on its decks (or not level)" % w["id"])


func _crowded(p: Vector2, margin: float) -> bool:
	for s: Array in _spots:
		if (s[0] as Vector2).distance_to(p) < float(s[1]) + margin:
			return true
	return false


func _problem(text: String) -> void:
	_problems += 1
	print("TREETOP PROBLEM " + text)
