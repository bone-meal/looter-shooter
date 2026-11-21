# Purpose: the camos a player owns and has not used up (polish1 D5a, DECISIONS_SKINS.md): each unboxed camo is its
# own item {id, wear, seed, uses} in the CAMOS tab, applied to guns from there (green 3 guns, blue 2, purple and up 1),
# rolled from the crate's camo odds with a wear (Factory New .. Battle-Scarred) and a pattern number. Saved in the
# profile ("camos"); a save's rows are checked against the data (unknown ids, odd numbers dropped). Pure rules.
# Dependencies: none (data/camos.json passed in).
extends RefCounted

const MOST := 500  # camos kept at most

var cfg: Dictionary
var items: Array = []  # {"id", "wear", "seed", "uses"}
var _by_id := {}


func _init(config: Dictionary) -> void:
	cfg = config
	for row: Dictionary in cfg.get("camos", []):
		_by_id[String(row["id"])] = row


func look(id: String) -> Dictionary:
	return _by_id.get(id, {})


func uses_of(tier: String) -> int:
	return int((cfg.get("uses", {}) as Dictionary).get(tier, 1))


# A fresh camo out of a crate: the tier by the crate's odds, a camo of that tier, wear and pattern number.
func roll(rng: RandomNumberGenerator, crate_id: String) -> Dictionary:
	var odds: Dictionary = (cfg.get("crate_odds", {}) as Dictionary).get(crate_id, {"green": 1.0})
	var total := 0.0
	for tier: String in odds:
		total += float(odds[tier])
	var pick := rng.randf() * total
	var tier := "green"
	for t: String in odds:
		pick -= float(odds[t])
		if pick <= 0.0:
			tier = t
			break
	var pool: Array = []
	for row: Dictionary in cfg.get("camos", []):
		if String(row["tier"]) == tier:
			pool.append(row)
	if pool.is_empty():
		pool = cfg.get("camos", [])
	var row: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var wear := pow(rng.randf(), 1.6)  # more of the lighter wears
	return {"id": String(row["id"]), "wear": snappedf(wear, 0.0001), "seed": rng.randi_range(1, 1000), "uses": uses_of(String(row["tier"]))}


func add(item: Dictionary) -> bool:
	if items.size() >= MOST or look(String(item.get("id", ""))).is_empty():
		return false
	items.append(item)
	return true


# Takes one use of camo `index` for a gun: what goes on the gun ({id, wear, seed, challenge false}), {} when none.
# The last use takes the camo out of the locker.
func use(index: int) -> Dictionary:
	if index < 0 or index >= items.size():
		return {}
	var item: Dictionary = items[index]
	item["uses"] = int(item["uses"]) - 1
	var on_gun := {"id": String(item["id"]), "wear": float(item["wear"]), "seed": int(item["seed"]), "challenge": false}
	if int(item["uses"]) <= 0:
		items.remove_at(index)
	return on_gun


# A camo row as it may come in from elsewhere (a save, a trade): cleaned, or {} when it cannot be one.
func clean(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var d: Dictionary = item
	var row := look(String(d.get("id", "")))
	if row.is_empty():
		return {}
	var wear: Variant = d.get("wear", 0.1)
	var seed_n: Variant = d.get("seed", 1)
	var uses: Variant = d.get("uses", 1)
	if not (wear is float or wear is int) or not (seed_n is float or seed_n is int) or not (uses is float or uses is int):
		return {}
	return {"id": String(d["id"]), "wear": clampf(float(wear), 0.0, 1.0), "seed": clampi(int(seed_n), 1, 1000), "uses": clampi(int(uses), 1, uses_of(String(row["tier"])))}


func to_list() -> Array:
	return items.duplicate(true)


func from_list(data: Variant) -> void:
	items.clear()
	if not data is Array:
		return
	for row: Variant in data:
		var c := clean(row)
		if not c.is_empty() and items.size() < MOST:
			items.append(c)


# Sorted for the tab: rarest first, then by name.
func order() -> Array:
	var rank := ["pony", "gold", "purple", "blue", "green"]
	var idx: Array = range(items.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ta := rank.find(String(look(String(items[a]["id"]))["tier"]))
		var tb := rank.find(String(look(String(items[b]["id"]))["tier"]))
		if ta != tb:
			return ta < tb
		return String(look(String(items[a]["id"]))["name"]) < String(look(String(items[b]["id"]))["name"]))
	return idx
