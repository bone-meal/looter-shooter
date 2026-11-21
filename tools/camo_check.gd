# Purpose: developer check of the camos as items (polish1 D5a): core/camo_locker.gd rolls by the crate odds, uses run
# out by tier (3 / 2 / 1), saves round-trip and drop nonsense; core/gun_gen.gd accepts a gun wearing a camo (also a
# unique) and refuses a bad one. Prints CAMO_CHECK lines; run headless: --script res://tools/camo_check.gd
# Dependencies: core/camo_locker.gd, core/gun_gen.gd, core/gun_db.gd, core/data_store.gd.
extends SceneTree

const CamoLocker = preload("res://core/camo_locker.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunDb = preload("res://core/gun_db.gd")
const DataStore = preload("res://core/data_store.gd")

var problems := 0


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
		say("a unique wearing a camo is still that unique", GunGen.validate(db, u) == "")
	print("CAMO_CHECK_DONE problems=%d" % problems)
	quit()
