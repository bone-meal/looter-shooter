# Purpose: checks core/guest_claims.gd (sea step 12c) without a scene: levels a guest may claim over time, bags by
# Crafting, recipe needs, puts. Run: godot --headless --script tools/claims_check.gd. Prints CLAIMS CHECK problems=n.
# Dependencies: core/guest_claims.gd, data/guest_claims.json, data/fantasy/skilling.json.
extends SceneTree

const GuestClaims = preload("res://core/guest_claims.gd")
var problems := 0


func _ok(what: String, cond: bool) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		problems += 1


func _init() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_claims.json"))
	var skilling: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/fantasy/skilling.json"))
	var fresh := GuestClaims.new(cfg, skilling, {}, 0.0)
	_ok("fresh: Sailing 50 at join refused", not fresh.level_ok("sailing", 50, 0.0))
	_ok("fresh: Sailing 1 at join allowed", fresh.level_ok("sailing", 1, 0.0))
	_ok("fresh: Sailing 25 after 30 min allowed (%d)" % fresh.allowed_level("sailing", 1800.0), fresh.level_ok("sailing", 25, 1800.0))
	_ok("fresh: no bags", fresh.bags_allowed(["satchel", "rucksack", "pack_frame"]) == 0)
	var c40 := 30 * int(pow(39.0, 2.2)) + 200
	var crafter := GuestClaims.new(cfg, skilling, {"crafting": c40, "carpentry": 30 * int(pow(24.0, 2.2)) + 200}, 0.0)
	_ok("Crafting 40: two bags (%d)" % crafter.bags_allowed(["satchel", "rucksack", "pack_frame"]), crafter.bags_allowed(["satchel", "rucksack", "pack_frame"]) == 2)
	_ok("brig needs Carpentry 25", crafter.recipe_need("ship_brig") == ["carpentry", 25])
	_ok("Carpentry 25 at join may build a brig now", crafter.level_ok("carpentry", 25, 0.0))
	_ok("Carpentry 25 at join may not claim galleon (45) now", not crafter.level_ok("carpentry", 45, 0.0))
	_ok("unknown item put refused", not crafter.put_ok(false, 1))
	_ok("put of 10000 refused", not crafter.put_ok(true, 10000))
	_ok("put of a 600 stack allowed", crafter.put_ok(true, 600))
	_ok("put of 20 allowed", crafter.put_ok(true, 20))
	print("CLAIMS CHECK problems=%d" % problems)
	quit()
