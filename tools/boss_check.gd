# Purpose: check of the sea super boss rules (sea step 10) on Abbot Shellback's data: party health and adds, phases by
# health, armour / weak shares, the barnacles cracking the shell and growing back, the rising tide and the enrage,
# the bell stun only after the shell is shed, the wipe rule, Dread. Prints BOSS CHECK problems=n.
# Run: godot --headless --path . --script res://tools/boss_check.gd
# Dependencies: core/sea/boss_rules.gd, data/sea/bosses.json, data/sea/dungeons.json (the arena exists).
extends SceneTree

const BossRules = preload("res://core/sea/boss_rules.gd")
const DungeonRules = preload("res://core/sea/dungeon_rules.gd")

var problems := 0


func _ok(what: String, cond: bool) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		problems += 1


func _init() -> void:
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/bosses.json"))
	var boss: Dictionary = all["bosses"]["abbot_shellback"]
	var r := BossRules.new()
	r.setup(boss, all, 1, 1.0)
	_ok("solo health = base", is_equal_approx(r.max_hp, 18000.0))
	r.setup(boss, all, 6, 1.0)
	_ok("6 players: health x4.75", is_equal_approx(r.max_hp, 18000.0 * 4.75))
	_ok("6 players: 2 adds become 4", r.adds_now().size() == 4)
	r.setup(boss, all, 1, 1.0)
	_ok("starts in phase 1, dry", r.phase == 0 and r.tide_step == -1)
	_ok("shell armoured (10 %)", is_equal_approx(r.body_share(), 0.1))
	_ok("eye stalk x2 through the armour", is_equal_approx(r.weak_share("eye_l"), 2.0))
	_ok("no stun before the shell is off", not r.try_stun())
	_ok("barnacles not breakable in phase 1", r.hit_part("barnacle_1", 5000.0) == "")
	_ok("75 % still phase 1", not r.advance(0.75) and r.phase == 0)
	_ok("65 % -> phase 2, tide step 1", r.advance(0.65) and r.phase == 1 and r.tide_step == 1)
	_ok("attack picked from phase 2", r.pick_attack(RandomNumberGenerator.new()) in ["burrow", "spout", "bell_toll"])
	_ok("barnacle broke", r.hit_part("barnacle_1", 1000.0) == "broke" and r.broken("barnacle_1"))
	r.hit_part("barnacle_2", 1000.0)
	r.hit_part("barnacle_3", 1000.0)
	_ok("last barnacle cracks the shell", r.hit_part("barnacle_4", 1000.0) == "crack" and r.cracked())
	_ok("cracked shell takes full damage", is_equal_approx(r.body_share(), 1.0))
	var changed := false
	for i in 12:
		changed = r.tick(1.0) or changed
	_ok("after crack_s it closes and the barnacles grow back", not r.cracked() and not r.broken("barnacle_1") and is_equal_approx(r.body_share(), 0.1))
	for i in 40:
		r.tick(1.0)
	_ok("the tide rose to step 3 and stops there", r.tide_step == 3)
	_ok("phase 3 at 30 %: shed, full damage, tide back to step 0", r.advance(0.3) and r.shed() and is_equal_approx(r.body_share(), 1.0) and r.tide_step == 0)
	_ok("no barnacles once shed", r.breakables().is_empty())
	_ok("bell stuns", r.try_stun() and r.stunned())
	_ok("not again until the cooldown", not r.try_stun())
	r.tick(21.0)
	_ok("stun again after 20 s", r.try_stun())
	_ok("shed: faster and harder", r.speed_mult() > 1.0 and r.damage_mult() > 1.0)
	r.tick(800.0)
	_ok("enraged at 12 min, tide over the pillars", r.enraged and r.tide_step == 4)
	_ok("never back to an earlier phase", not r.advance(0.9) and r.phase == 2)
	r.set_state(2, "down")
	_ok("one down, one up: no wipe", not r.wiped([1, 2]))
	r.set_state(1, "out")
	_ok("all down / out: wipe", r.wiped([1, 2]))
	_ok("nobody there: no wipe", not r.wiped([]))
	r.set_state(2, "up")
	_ok("revived = up", r.state_of(2) == "up")
	_ok("dread x2: 80 % health, 84 % damage", is_equal_approx(BossRules.dread_health(2, all["dread"]), 0.8) and is_equal_approx(BossRules.dread_damage(2, all["dread"]), 0.84))
	_ok("dread capped at 5", is_equal_approx(BossRules.dread_health(9, all["dread"]), 0.5))
	# the arena and the temple door exist and agree
	var dcfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/dungeons.json"))
	_ok("arena dungeon exists", dcfg["dungeons"].has(String(boss["arena"])))
	if dcfg["dungeons"].has(String(boss["arena"])):
		var a := DungeonRules.new(String(boss["arena"]), dcfg["dungeons"][boss["arena"]], float(dcfg["tile"]))
		_ok("arena has the boss tide", a.things.has(String(boss["tide_thing"])) and (a.things[boss["tide_thing"]]["tide"] as Array).size() == 5)
		_ok("arena has an arrive and an exit", not a.of_kind("arrive").is_empty() and not a.of_kind("exit").is_empty())
		_ok("arena has 6 hook rings on pillars", a.of_kind("ring").size() == 6)
		for c: Array in boss["adds_at"]:
			_ok("add spot %s is floor" % str(c), a.passable(Vector2i(int(c[0]), int(c[1]))))
	var t := DungeonRules.new(String(boss["temple"]), dcfg["dungeons"][boss["temple"]], float(dcfg["tile"]))
	_ok("temple's sealed door names this boss", t.things.has(String(boss["door"])) and String(t.things[boss["door"]].get("boss", "")) == "abbot_shellback")
	print("BOSS CHECK problems=%d" % problems)
	quit()
