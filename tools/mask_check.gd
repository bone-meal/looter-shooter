# Purpose: developer check of masks (polish1 D5c): data/masks.json is complete, Morse comes out right (SOS =
# ... --- ...), the locker keeps copies, drops unknown save rows and takes the worn mask off with the last copy, a look
# keeps only known masks, full masks cover the head, and every mask's game files exist. Prints MASK_CHECK lines; run
# headless: --script res://tools/mask_check.gd
# Dependencies: core/mask_db.gd, core/mask_locker.gd, core/data_store.gd, game/appearance_data.gd, game/mask_model.gd.
extends SceneTree

const MaskDb = preload("res://core/mask_db.gd")
const MaskLocker = preload("res://core/mask_locker.gd")
const DataStore = preload("res://core/data_store.gd")
const AppearanceData = preload("res://game/appearance_data.gd")
const MaskModel = preload("res://game/mask_model.gd")

var problems := 0


func say(text: String, ok: bool) -> void:
	print("MASK_CHECK %s %s" % ["ok  " if ok else "FAIL", text])
	if not ok:
		problems += 1


func _init() -> void:
	var db := MaskDb.new(DataStore.load_json("res://data/masks.json"))
	say("data problems %s" % str(db.problems()), db.problems().is_empty())
	var sos := MaskDb.morse_units("SOS")
	var bits := ""
	for u: bool in sos:
		bits += "1" if u else "0"
	say("SOS in Morse %s" % bits, bits.begins_with("10101000111011101110001010100"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var drops: Dictionary = db.cfg["drops"]
	var keep := float(drops["boss"])
	drops["boss"] = 1.0
	var sure := db.roll_drop("boss", "boss", rng)
	drops["boss"] = 0.0
	var never := db.roll_drop("boss", "boss", rng)
	drops["boss"] = keep
	var hits := 0
	for i in 20000:
		if db.roll_drop("boss", "boss", rng) != "":
			hits += 1
	say("drops: sure -> %s, none at 0, boss rate %.4f (data %.4f), no elite masks yet -> '%s'" % [sure, float(hits) / 20000.0, keep, db.roll_drop("elite", "elite", rng)], sure == "plague_doctor" and never == "" and absf(float(hits) / 20000.0 - keep) < 0.005)
	var lk := MaskLocker.new(db)
	var ok := lk.add("plague_doctor") and lk.add("plague_doctor") and not lk.add("no_such_mask")
	ok = ok and lk.wear("plague_doctor") and lk.remove("plague_doctor") and lk.worn == "plague_doctor" and lk.remove("plague_doctor") and lk.worn == ""
	say("locker copies / wear / last copy takes it off", ok)
	lk.from_dict({"owned": {"plague_doctor": 3, "fake": 2, "bad": "x"}, "worn": "fake"})
	say("save rows: unknown dropped, worn checked", lk.owned.size() == 1 and int(lk.owned["plague_doctor"]) == 3 and lk.worn == "")
	var look := AppearanceData.db().sanitize({"gender": "male", "mask": "plague_doctor"})
	var bad := AppearanceData.db().sanitize({"gender": "male", "mask": "../../evil"})
	say("look keeps a known mask only", String(look.get("mask", "")) == "plague_doctor" and not bad.has("mask"))
	say("plague doctor covers the head", MaskModel.covers_head("plague_doctor") and not MaskModel.covers_head(""))
	for id: String in db.ids():
		var missing := []
		for f in ["hi.obj", "lo.obj", "col.png", "nrm.png", "orm.png", "fx.png", "col_half.png", "nrm_half.png", "orm_half.png", "fx_half.png"]:
			if not FileAccess.file_exists("res://assets/masks/%s/%s" % [id, f]):
				missing.append(f)
		say("%s game files %s" % [id, "all there" if missing.is_empty() else str(missing)], missing.is_empty())
		var made := MaskModel.build(id)
		say("%s builds" % id, made != null)
		if made != null:
			made.free()
	print("MASK_CHECK_DONE problems=%d" % problems)
	quit()
