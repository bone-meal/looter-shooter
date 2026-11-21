# Purpose: developer check of the camos as items (polish1 D5a): core/camo_locker.gd rolls by the crate odds, uses run
# out by tier (3 / 2 / 1), saves round-trip and drop nonsense; core/gun_gen.gd accepts a gun wearing a camo (also a
# unique) and refuses a bad one. Prints CAMO_CHECK lines; run headless: --script res://tools/camo_check.gd
# and the per-gun camo challenges (core/camo_challenges.gd: ladder, counting, texts, shape check).
# Dependencies: core/camo_challenges.gd, core/camo_locker.gd, core/gun_gen.gd, core/gun_db.gd, core/data_store.gd.
extends SceneTree

const CamoLocker = preload("res://core/camo_locker.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunDb = preload("res://core/gun_db.gd")
const DataStore = preload("res://core/data_store.gd")
const CamoChallenges = preload("res://core/camo_challenges.gd")

var problems := 0


func _challenges(db: RefCounted, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var chal := CamoChallenges.new(DataStore.load_json("res://data/camo_challenges.json"), cfg)
	say("every camo has a challenge (%d)" % chal.total(), chal.total() == (cfg["camos"] as Array).size())
	var kinds: Dictionary = chal.cfg["kinds"]
	var bad := []
	for row: Dictionary in cfg["camos"]:
		if not kinds.has(String(chal.challenge(String(row["id"])).get("kind", ""))):
			bad.append(row["id"])
	say("every challenge kind has a text %s" % str(bad), bad.is_empty())
	var gun := GunGen.generate(db, rng, 0.0, "m16", "blue")
	say("a fresh gun: green open, blue shut", chal.is_open(gun, "green") and not chal.is_open(gun, "blue") and not chal.is_open(gun, "pony"))
	for i in 49:
		chal.count(gun, {"dist": 10.0})
	say("49 kills: woodland 49 / 50, not earned", chal.progress(gun, "woodland_classic") == 49 and not chal.done(gun, "woodland_classic"))
	var got := chal.count(gun, {"dist": 10.0, "head": true})
	say("the 50th kill earns woodland %s" % str(got), got.has("woodland_classic") and chal.done(gun, "woodland_classic"))
	say("a headshot counted on the headshot camo", chal.progress(gun, "digital_woodland") == 1)
	say("hip fire counted (not aiming) and close / long apart", chal.done(gun, "arctic_whiteout") and chal.progress(gun, "arctic_blue") == 0 and chal.progress(gun, "urban_gray") == 0)
	say("the text reads", chal.text("urban_digital") == "Get 15 kills from 25 m or further" and chal.text("flecktarn_brown") == "Get 10 kills within 1.5 s of another kill")
	chal.count(gun, {"dist": 30.0, "since": 0.5, "air": true, "health": 0.2, "streak": 5, "place": "arena", "aim": true})
	say("one kill: long, multi, air, low, streak, arena, aim all count", chal.progress(gun, "urban_digital") == 1 and chal.progress(gun, "flecktarn_brown") == 1 and chal.progress(gun, "tiger_green") == 1 and chal.progress(gun, "tiger_black") == 1 and chal.progress(gun, "hex_gray") == 1 and chal.progress(gun, "flecktarn_green") == 1 and chal.progress(gun, "arctic_blue") == 1)
	gun["chal_done"] = (chal.ids_of("green") as Array).slice(0, 14)
	say("14 greens: blue still shut", not chal.is_open(gun, "blue"))
	(gun["chal_done"] as Array).append(chal.ids_of("green")[14])
	say("15 greens: blue opens, purple shut", chal.is_open(gun, "blue") and not chal.is_open(gun, "purple"))
	gun["chal_done"] = (chal.ids_of("green") as Array) + (chal.ids_of("blue") as Array) + (chal.ids_of("purple") as Array) + (chal.ids_of("gold") as Array).slice(0, 4)
	say("4 legendaries: pony shut; 5: open", not chal.is_open(gun, "pony"))
	(gun["chal_done"] as Array).append(chal.ids_of("gold")[4])
	say("... 5 legendaries: pony open", chal.is_open(gun, "pony"))
	var c1 := CamoChallenges.camo_for(gun, "neon_oni")
	say("a challenge camo is Factory New with a fixed pattern", float(c1["wear"]) == 0.0 and bool(c1["challenge"]) and int(c1["seed"]) == int(CamoChallenges.camo_for(gun, "neon_oni")["seed"]))
	gun["camo"] = CamoChallenges.camo_for(gun, "gold")
	say("a gun with earned challenges and its camo is legal", GunGen.validate(db, gun) == "")
	gun["chal"] = {"x": -4}
	say("a negative challenge count is refused", GunGen.validate(db, gun) != "")


func say(text: String, ok: bool) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", text])
	if not ok:
		problems += 1


func _init() -> void:
	var cfg: Dictionary = DataStore.load_json("res://data/camos.json")
	var locker := CamoLocker.new(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tiers := {}
	for i in 4000:
		var c := locker.roll(rng, "gold")
		var t := String(locker.look(String(c["id"]))["tier"])
		tiers[t] = int(tiers.get(t, 0)) + 1
	say("gold crate tiers over 4000 rolls %s (pony about 3 %%)" % str(tiers), tiers.has("pony") and int(tiers["pony"]) > 60 and int(tiers["pony"]) < 200)
	locker.items.clear()
	locker.add({"id": "woodland_classic", "wear": 0.1, "seed": 5, "uses": 3})
	var a := locker.use(0)
	locker.use(0)
	var still := locker.items.size() == 1 and int(locker.items[0]["uses"]) == 1
	locker.use(0)
	say("a green camo goes on 3 guns, then is gone", still and locker.items.is_empty() and String(a["id"]) == "woodland_classic" and a.has("challenge"))
	locker.from_list([{"id": "galaxy", "wear": 0.2, "seed": 9, "uses": 9}, {"id": "nope", "wear": 0.1, "seed": 1, "uses": 1}, "junk", {"id": "zebra", "wear": "x", "seed": 1, "uses": 1}])
	say("a save keeps known camos only, uses capped by tier", locker.items.size() == 1 and int(locker.items[0]["uses"]) == 1)
	var db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"), DataStore.load_json("res://data/gun_uniques.json"))
	var gun := GunGen.generate(db, rng, 0.0, "ak47", "purple")
	gun["camo"] = {"id": "galaxy", "wear": 0.2, "seed": 9, "challenge": false}
	say("a rolled gun wearing a camo is legal", GunGen.validate(db, gun) == "")
	var trip: Dictionary = JSON.parse_string(JSON.stringify(gun))
	say("... also after a save / the wire", GunGen.validate(db, trip) == "")
	gun["camo"] = {"id": "galaxy", "wear": 3.0, "seed": 9, "challenge": false}
	say("a camo with wear 3 is refused", GunGen.validate(db, gun) != "")
	var ids: Array = db.uniques.keys()
	if not ids.is_empty():
		var u := GunGen.unique(db, String(ids[0]))
		u["camo"] = {"id": "gold", "wear": 0.0, "seed": 1, "challenge": true}
		say("a challenge camo not earned on the gun is refused", GunGen.validate(db, u) != "")
		u["chal_done"] = ["gold"]
		u["chal"] = {"silver": 12}
		say("a unique wearing an earned challenge camo is still that unique", GunGen.validate(db, u) == "")
	_challenges(db, cfg, rng)
	print("CAMO_CHECK_DONE problems=%d" % problems)
	quit()
