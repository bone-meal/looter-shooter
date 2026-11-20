# Purpose: pure rules of the colosseum's rotating BANNER tickets (polish1 item 58): which two banners are on the board
# at a real-world (UTC) time, how long until they change, which ticket a banner runs and with which modifiers, and its
# boosts. Every player's clock picks the same two, so nothing is sent online but the banner's id with the run.
# Dependencies: none. Data: data/colosseum_banners.json, passed to the constructor.
extends RefCounted

var cfg: Dictionary
var _list: Array


func _init(config: Dictionary) -> void:
	cfg = config
	_list = config["banners"]


func _period() -> int:
	return maxi(int(cfg.get("minutes", 15)), 1) * 60


# The two banners on the board at unix time `now` (seconds, UTC). Always two different ones.
func live(now: float) -> Array:
	return _pair(floori(now / float(_period())))


func _pair(slot: int) -> Array:
	var n := _list.size()
	if n < 2:
		return _list.duplicate()
	var a := posmod(slot * 7, n)
	var b := posmod(a + 1 + posmod(slot * 13, n - 1), n)
	return [_list[a], _list[b]]


# Seconds until the board shows the next pair.
func seconds_left(now: float) -> int:
	return _period() - posmod(floori(now), _period())


# Is this banner on the board now, or was it a moment ago (a run bought at the change still counts)?
func is_live(id: String, now: float) -> bool:
	var slot := floori(now / float(_period()))
	for banner: Dictionary in _pair(slot) + _pair(slot - 1):
		if String(banner["id"]) == id:
			return true
	return false


func find(id: String) -> Dictionary:
	for banner: Dictionary in _list:
		if String(banner["id"]) == id:
			return banner
	return {}


# The banner's own modifiers plus those the player ticked as well (no doubles).
func run_mods(banner: Dictionary, ticked: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray(banner.get("mods", []))
	for id: String in ticked:
		if not out.has(id):
			out.append(id)
	return out


# A boost of the banner (1.0 / "" when it has none): luck, armour, treasure, pony, chest_guns, maker, body.
func boost(banner: Dictionary, key: String, plain: Variant = 1.0) -> Variant:
	return (banner.get("boost", {}) as Dictionary).get(key, plain)


# Most guns of a maker / body banner come from it: the maker and body to roll a gun with ("" = any).
func gun_pick(banner: Dictionary, rng: RandomNumberGenerator) -> Array[String]:
	var boosts: Dictionary = banner.get("boost", {})
	if not (boosts.has("maker") or boosts.has("body")) or rng.randf() >= float(cfg.get("share", 0.7)):
		return ["", ""]
	return [String(boosts.get("maker", "")), String(boosts.get("body", ""))]


# What is wrong with the data (empty = fine): known modifiers, ticket lengths, makers, bodies and icons.
func problems(mod_ids: Array, waves: Array, makers: Array, bodies: Array, icons: Array) -> PackedStringArray:
	var found := PackedStringArray()
	var seen := {}
	for banner: Dictionary in _list:
		var id := String(banner.get("id", ""))
		if id == "" or seen.has(id):
			found.append("banner '%s': needs an id of its own" % id)
		seen[id] = true
		if not waves.has(int(banner.get("waves", 0))):
			found.append("banner %s: waves must be one of the tickets' %s" % [id, waves])
		for mod: String in banner.get("mods", []):
			if not mod_ids.has(mod):
				found.append("banner %s: unknown modifier %s" % [id, mod])
		var boosts: Dictionary = banner.get("boost", {})
		if boosts.has("maker") and not makers.has(String(boosts["maker"])):
			found.append("banner %s: unknown maker %s" % [id, boosts["maker"]])
		if boosts.has("body") and not bodies.has(String(boosts["body"])):
			found.append("banner %s: unknown gun %s" % [id, boosts["body"]])
		if not icons.has(String(banner.get("icon", ""))):
			found.append("banner %s: unknown icon %s" % [id, banner.get("icon", "")])
	if _list.size() < 2:
		found.append("the board needs at least two banners")
	return found
