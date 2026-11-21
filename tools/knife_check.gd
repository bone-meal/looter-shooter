# Purpose: developer check of skinned knives (polish1 D5b): rolls follow the tier odds and are always legal, every
# finish's power text resolves, levels climb with kills (1 -> 30), the locker drops bad save rows and keeps the carried
# one right, chase patterns exist for every finish's family. Prints KNIFE_CHECK lines; run headless:
# --script res://tools/knife_check.gd
# Dependencies: core/knife_skins.gd, core/knife_locker.gd, core/data_store.gd.
extends SceneTree

const KnifeSkins = preload("res://core/knife_skins.gd")
const KnifeLocker = preload("res://core/knife_locker.gd")
const DataStore = preload("res://core/data_store.gd")

var problems := 0


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
	print("KNIFE_CHECK_DONE problems=%d" % problems)
	quit()
