# Purpose: decides the islands' weather for a round (pure rules, no nodes, no rendering): which stage a round number
# falls in, how thick its fog has grown, and what a boss round lays over it. The answer is a small table of plain
# numbers and colours that game/island_weather.gd blends and shows.
# Dependencies: none. Data: data/island_weather.json, passed to setup().
extends RefCounted

# What "no weather" is: nothing added, nothing dimmed. Every answer has exactly these keys.
const CLEAR := {
	"stage": "clear", "weight": 0.0, "density": 0.0, "fog_color": Color.WHITE, "sky_tint": Color.WHITE,
	"sky_cover": 0.0, "sun": 1.0, "sun_color": Color.WHITE, "rain": 0.0, "bed": "",
}

var cfg: Dictionary

var _stages: Array = []  # sorted by from_round


func setup(config: Dictionary) -> void:
	cfg = config
	_stages = (config.get("stages", []) as Array).duplicate()
	_stages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["from_round"]) < int(b["from_round"]))


# What is wrong with the data, as lines for a check log (empty = fine).
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if _stages.is_empty():
		found.append("no stages")
	var seen := {}
	for stage: Dictionary in _stages:
		var id := String(stage.get("id", ""))
		if id == "" or seen.has(id):
			found.append("stage id missing or twice: '%s'" % id)
		seen[id] = true
		if int(stage.get("from_round", 0)) < 1:
			found.append("stage %s: from_round must be 1 or more" % id)
		for key: String in ["density", "density_per_round", "density_max"]:
			if float(stage.get(key, 0.0)) < 0.0 or float(stage.get(key, 0.0)) > 0.2:
				found.append("stage %s: %s out of range" % [id, key])
		for key: String in ["sky_cover", "sun", "rain"]:
			if float(stage.get(key, 0.5)) < 0.0 or float(stage.get(key, 0.5)) > 1.0:
				found.append("stage %s: %s must be 0..1" % [id, key])
		for key: String in ["fog_color", "sky_tint", "sun_color"]:
			if stage.has(key) and not Color.html_is_valid(String(stage[key])):
				found.append("stage %s: %s is not a colour" % [id, key])
	var boss: Dictionary = cfg.get("boss", {})
	for key: String in ["fog_color", "sky_tint", "sun_color"]:
		if boss.has(key) and not Color.html_is_valid(String(boss[key])):
			found.append("boss: %s is not a colour" % key)
	var rain: Dictionary = cfg.get("rain", {})
	for tier: String in ["potato", "low", "medium", "high", "ultimate"]:
		if not (rain.get("drops", {}) as Dictionary).has(tier):
			found.append("rain drops: tier %s missing" % tier)
	return found


# The stage a round is in ("clear" before round 1 and when no stage is reached).
func stage_of(number: int) -> Dictionary:
	var found := {}
	for stage: Dictionary in _stages:
		if number >= int(stage["from_round"]):
			found = stage
	return found


# The weather of a round. `kind` is the round's kind while it is being fought ("boss" lays the boss look over it).
func of_round(number: int, kind: String) -> Dictionary:
	var weather := CLEAR.duplicate()
	var stage := stage_of(number)
	if number >= 1 and not stage.is_empty() and stage.size() > 2:  # a stage with only id and from_round is clear weather
		weather["stage"] = String(stage["id"])
		weather["weight"] = 1.0
		var grown := float(stage.get("density", 0.0)) + float(stage.get("density_per_round", 0.0)) * float(number - int(stage["from_round"]))
		weather["density"] = minf(grown, float(stage.get("density_max", grown)))
		weather["fog_color"] = Color.html(String(stage.get("fog_color", "#ffffff")))
		weather["sky_tint"] = Color.html(String(stage.get("sky_tint", "#ffffff")))
		weather["sky_cover"] = float(stage.get("sky_cover", 0.0))
		weather["sun"] = float(stage.get("sun", 1.0))
		weather["sun_color"] = Color.html(String(stage.get("sun_color", "#ffffff")))
		weather["rain"] = float(stage.get("rain", 0.0))
		weather["bed"] = String(stage.get("bed", ""))
	var boss: Dictionary = cfg.get("boss", {})
	if number >= 1 and kind == "boss" and not boss.is_empty():
		weather["weight"] = 1.0
		weather["density"] = float(weather["density"]) + float(boss.get("density_add", 0.0))
		weather["fog_color"] = Color.html(String(boss.get("fog_color", "#ffffff")))
		weather["sky_tint"] = Color.html(String(boss.get("sky_tint", "#ffffff")))
		weather["sky_cover"] = maxf(float(weather["sky_cover"]), float(boss.get("sky_cover", 0.0)))
		weather["sun"] = float(weather["sun"]) * float(boss.get("sun", 1.0))
		weather["sun_color"] = Color.html(String(boss.get("sun_color", "#ffffff")))
	return weather


# Drops drawn on a graphics tier at full rain.
func drops_for(tier: String) -> int:
	return int(((cfg.get("rain", {}) as Dictionary).get("drops", {}) as Dictionary).get(tier, 0))
