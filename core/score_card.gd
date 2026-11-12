# Purpose: one player's zombies-style points (saved with the character, spent on the islands) and the numbers of this
# session's scoreboard: kills, headshots, downs, revives. Pure rules: no nodes, no rendering.
# Dependencies: none. Award sizes and the cap come from data/points.json, passed to the constructor.
extends RefCounted

signal earned(amount: int)  # points were added (the HUD shows "+60")
signal spent(amount: int)

const ROW_KEYS := ["points", "kills", "headshots", "downs", "revives"]

var points := 0  # saved
var kills := 0  # this session only, like the three below
var headshots := 0
var downs := 0
var revives := 0
var blow := ""  # how the hit being dealt right now lands: "headshot", "melee", "" or "other" = not ours at all (set around the hit by whoever deals it)
var paused := false  # true = hits and kills pay and count nothing (Aurelind: its fights are not part of the points game)

var _awards: Dictionary
var _max: int


func _init(cfg: Dictionary) -> void:
	_awards = cfg["awards"]
	_max = int(cfg["max"])


# A hit that did not kill.
func hit() -> int:
	return 0 if paused else _add(int(_awards["hit"]))


# The killing blow: pays by how it landed (see `blow`) and counts the kill.
func kill() -> int:
	if paused or blow == "other":  # "other": somebody else's kill (online; whoever dealt the blow is paid by the host)
		return 0
	kills += 1
	if blow == "headshot":
		headshots += 1
		return _add(int(_awards["headshot_kill"]))
	if blow == "melee":
		return _add(int(_awards["melee_kill"]))
	return _add(int(_awards["kill"]))


# Points from anywhere else (a power-up, a command). Returns what was really added.
func give(amount: int) -> int:
	return _add(maxi(amount, 0))


func can_afford(price: int) -> bool:
	return price >= 0 and price <= points


# Pays `price`; false (and nothing changes) when there are not enough points.
func spend(price: int) -> bool:
	if not can_afford(price):
		return false
	points -= price
	if price > 0:
		spent.emit(price)
	return true


func _add(amount: int) -> int:
	var added := mini(amount, _max - points)
	if added > 0:
		points += added
		earned.emit(added)
	return maxi(added, 0)


# What the scoreboard shows of this player.
func row() -> Dictionary:
	return {"points": points, "kills": kills, "headshots": headshots, "downs": downs, "revives": revives}


# Turns whatever another machine sent as its row into five sane whole numbers (the host never shows raw input).
static func clean_row(raw: Variant, cap: int) -> Dictionary:
	var out := {}
	var from: Dictionary = raw if raw is Dictionary else {}
	for key: String in ROW_KEYS:
		var value: Variant = from.get(key, 0)
		var n := int(value) if (value is int or value is float) else 0
		out[key] = clampi(n, 0, cap if key == "points" else 999999)
	return out


func most_points() -> int:
	return _max


# Only the points are kept between sessions.
func to_dict() -> Dictionary:
	return {"points": points}


func from_dict(d: Variant) -> void:
	points = 0
	if d is Dictionary and (d.get("points") is int or d.get("points") is float):
		points = clampi(int(d["points"]), 0, _max)
