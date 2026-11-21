# Purpose: developer check of skinned knives (polish1 D5b): rolls follow the tier odds and are always legal, every
# finish's power text resolves, levels climb with kills (1 -> 30), the locker drops bad save rows and keeps the carried
# one right, chase patterns exist for every finish's family. Prints KNIFE_CHECK lines; run headless:
# --script res://tools/knife_check.gd
# Dependencies: core/knife_skins.gd, core/knife_locker.gd, core/data_store.gd.
extends SceneTree

const KnifeSkins = preload("res://core/knife_skins.gd")
const KnifeLocker = preload("res://core/knife_locker.gd")
const DataStore = preload("res://core/data_store.gd")
const KnifeFx = preload("res://core/knife_fx.gd")

var problems := 0


# Every power answers: what each finish's knife does on slashes, stabs and kills (at level 30), and the passive ones.
func _powers(r: KnifeSkins) -> void:
	var expect := {"whetstone": "refill_mag", "second_breath": "heal", "spark_shower": "burn_area", "meltdown": "delayed_blast", "anvil_drop": "slam",
		"living_metal": "pool", "undertow": "pull_loot", "salt_wound": "vulnerable", "drag_down": "freeze", "party_ammo": "party_ammo", "deep_light": "cast",
		"the_bite": "bite", "venom": "venom", "northern_step": "reset_dodge", "party_revive": "revive_near", "lightning": "cast", "spirit_pack": "cast",
		"lucky_stub": "chips", "party_popper": "blind", "club_lights": "marks", "snowman": "snowman", "slot_roll": "slot"}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var missing := []
	for f: Dictionary in r.cfg["finishes"]:
		var fx := KnifeFx.new(r)
		fx.carry({"finish": f["id"], "type": "combat", "pattern": 1, "wear": 0.1, "strength": 1.0, "kills": 1450})
		var seen := {}
		var t := 100.0
		for k in 40:
			t += 0.3
			for a: Dictionary in fx.on_hit("slash", false, false, t) + fx.on_hit("stab", false, false, t + 0.1) + fx.on_kill(t + 0.2, rng):
				seen[String(a["do"])] = true
		var want := String(expect.get(fx.power, ""))
		if want != "" and not seen.has(want):
			missing.append("%s/%s" % [f["id"], fx.power])
	say("every power fires its action %s" % str(missing), missing.is_empty())
	var fx2 := KnifeFx.new(r)
	fx2.carry({"finish": "temper_line", "type": "combat", "pattern": 1, "wear": 0.1, "strength": 1.0, "kills": 1450})
	fx2.on_kill(10.0, rng)
	say("Hardened: 30 %% less damage for 6 s, then none", is_equal_approx(fx2.incoming(100.0, 11.0, 0.9), 70.0) and is_equal_approx(fx2.incoming(100.0, 17.0, 0.9), 100.0))
	var fx3 := KnifeFx.new(r)
	fx3.carry({"finish": "prism_melt", "type": "combat", "pattern": 1, "wear": 0.1, "strength": 1.0, "kills": 1450})
	fx3.on_hit("slash", false, false, 10.0)
	say("Refraction: a low roll misses for 4 s", fx3.incoming(50.0, 11.0, 0.1) == 0.0 and fx3.incoming(50.0, 11.0, 0.5) == 50.0 and fx3.incoming(50.0, 15.0, 0.1) == 50.0)
	var fx4 := KnifeFx.new(r)
	fx4.carry({"finish": "jesters_grin", "type": "combat", "pattern": 1, "wear": 0.1, "strength": 1.0, "kills": 0})
	var first := fx4.would_down(10.0)
	var again := fx4.would_down(11.0)
	var untouch := fx4.incoming(80.0, 11.5, 0.9) == 0.0
	for k in 30:
		fx4.on_kill(20.0 + float(k), rng)
	say("Last Laugh: saves once, untouchable a moment, ready again after 30 knife kills", first and not again and untouch and fx4.would_down(60.0))
	var fx5 := KnifeFx.new(r)
	fx5.carry({"finish": "christmas_bells", "type": "combat", "pattern": 1, "wear": 0.1, "strength": 1.0, "kills": 0})
	var snow := fx5.on_hit("stab", false, false, 10.0)
	var cooled := fx5.on_hit("stab", false, false, 12.0)
	var boss := fx5.on_hit("stab", false, true, 31.0)
	say("Snowman: a stab freezes 5 s, 20 s cooldown, bosses 2 s", snow.size() == 1 and float(snow[0]["freeze"]) == 5.0 and cooled.is_empty() and boss.size() == 1 and float(boss[0]["freeze"]) == 2.0)
	var fx6 := KnifeFx.new(r)
	fx6.carry({"finish": "candy_cane", "type": "combat", "pattern": 1, "wear": 0.1, "strength": 1.0, "kills": 0})
	fx6.on_kill(10.0, rng)
	say("Sugar Rush at level 1: +8 %% fire rate (40 %% of 20)", is_equal_approx(fx6.rate_mult(11.0), 1.08) and is_equal_approx(fx6.rate_mult(15.0), 1.0))


func say(text: String, ok: bool) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", text])
	if not ok:
		problems += 1


func _init() -> void:
	var weights := {}
	var knives: Dictionary = DataStore.load_json("res://data/knives.json")["knives"]
	for id: String in knives:
		weights[id] = float(knives[id]["weight"])
	var r := KnifeSkins.new(DataStore.load_json("res://data/knife_skins.json"), weights)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tiers := {}
	var bad := 0
	for i in 20000:
		var k := r.roll(rng)
		if r.check(k) != "":
			bad += 1
		var t := String(r.finish(String(k["finish"]))["tier"])
		tiers[t] = int(tiers.get(t, 0)) + 1
	say("20000 rolls all legal (%d bad), tiers %s (pony about 400)" % [bad, str(tiers)], bad == 0 and int(tiers.get("pony", 0)) > 300 and int(tiers.get("pony", 0)) < 520)
	var no_text := []
	for f: Dictionary in r.cfg["finishes"]:
		var item := {"finish": f["id"], "type": "combat", "pattern": 1, "wear": 0.1, "strength": 1.0, "kills": 0}
		if r.power_text(item) == "" or r.power_text(item).contains("{"):
			no_text.append(f["id"])
	say("every finish has a power text %s" % str(no_text), no_text.is_empty())
	var k0 := {"finish": "christmas_bells", "type": "karambit", "pattern": 1, "wear": 0.1, "strength": 1.0, "kills": 0}
	var total := 0
	for n in range(1, 30):
		total += r.kills_for(n)
	k0["kills"] = total - 1
	var almost := r.level(k0)
	k0["kills"] = total
	say("level 29 at %d kills, 30 at %d" % [total - 1, total], almost == 29 and r.level(k0) == 30 and is_equal_approx(r.power_scale(k0), 1.0) and is_equal_approx(r.damage_mult(k0), 3.0))
	k0["kills"] = 0
	say("level 1: power 40 %%, damage x1", r.level(k0) == 1 and is_equal_approx(r.power_scale(k0), 0.4) and is_equal_approx(r.damage_mult(k0), 1.0))
	var lk := KnifeLocker.new(r)
	lk.from_dict({"items": [k0, {"finish": "nope", "type": "combat", "pattern": 1, "wear": 0.1, "strength": 1.0, "kills": 0}, {"finish": "quench", "type": "combat", "pattern": 5000, "wear": 0.1, "strength": 1.0, "kills": 0}, "x"], "on": 0})
	say("a save keeps legal knives only, the carried one too", lk.items.size() == 1 and lk.on == 0 and String(lk.carried()["finish"]) == "christmas_bells")
	var up := 0
	for i in r.kills_for(1):
		up = maxi(up, lk.count_kill())
	say("kills with the carried knife level it up (%d)" % up, up == 2)
	lk.add({"finish": "quench", "type": "bowie", "pattern": 29, "wear": 0.2, "strength": 0.95, "kills": 3})
	lk.equip(1)
	lk.remove(0)
	say("trading away another knife keeps the carried one carried", lk.on == 0 and String(lk.carried()["finish"]) == "quench")
	var no_chase := []
	for f: Dictionary in r.cfg["finishes"]:
		var found := false
		for p in 1000:
			if int(r.pattern_look({"finish": f["id"], "pattern": p})["variant"]) > 0:
				found = true
				break
		if not found:
			no_chase.append(f["id"])
	say("every finish has rollable chase patterns %s" % str(no_chase), no_chase.is_empty())
	_powers(r)
	print("KNIFE_CHECK_DONE problems=%d" % problems)
	quit()
