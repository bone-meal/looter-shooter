# Purpose: a port's money rules as pure code (sea step 6; director: doubloons from the sea + selling loot at port
# shops, casino chips change into doubloons at a REALLY BAD rate, one way; chips also buy charts and supplies): what the
# stall pays for a backpack stack (a rolled gun by tier and item level, an armour piece a share of that, plain items
# nothing), the change for chips, and the stall's stock. Prices are data (data/sea/port.json).
# Dependencies: none (the port data and the stacks passed in).
extends RefCounted

var cfg: Dictionary


func _init(port_cfg: Dictionary) -> void:
	cfg = port_cfg


# Doubloons the stall pays for a gun-side backpack stack ({"gun": ...} or {"arm": ...}); 0 = not bought.
func sell_price(stack: Dictionary) -> int:
	var sell: Dictionary = cfg["sell"]
	var piece: Dictionary = stack.get("gun", stack.get("arm", {}))
	if piece.is_empty():
		return 0
	var base := float((sell["tier"] as Dictionary).get(String(piece.get("tier", "grey")), 1))
	var lvl := maxf(float(piece.get("lvl", 1)), 1.0)
	var price := base * (1.0 + float(sell["level_bonus"]) * lvl)
	if stack.has("arm"):
		price *= float(sell["armour_share"])
	return maxi(1, roundi(price))


# Doubloons for `chips` casino chips (rounded down: the rest stays chips).
func doubloons_for(chips: int) -> int:
	return floori(float(maxi(chips, 0)) / float(maxi(int(cfg["chips_per_doubloon"]), 1)))


func chips_for(doubloons: int) -> int:
	return maxi(doubloons, 0) * maxi(int(cfg["chips_per_doubloon"]), 1)


func stock() -> Array:
	return cfg["buy"]


func port(id: String) -> Dictionary:
	for p: Dictionary in cfg["ports"]:
		if String(p["id"]) == id:
			return p
	return {}


# The ports a ferry from `here` may take a player to: every other port whose island he has explored.
func ferry_to(here: String, explored: Dictionary) -> Array:
	var out: Array = []
	for p: Dictionary in cfg["ports"]:
		if String(p["id"]) != here and explored.has(String(p["island"])):
			out.append(p)
	return out
