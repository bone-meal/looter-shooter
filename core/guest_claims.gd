# Purpose: the host's plausibility checks on what a guest claims (sea step 12c, LOCKED: plausibility, no ledger). Made
# from the profile the guest joined with: his skills' experience then and the time he joined. A level claimed later
# (Sailing at the helm, Carpentry for a ship) may be at most what that experience plus data xp_per_minute for each
# minute since reaches; a backpack's bags at most what his Crafting level at join can make; an item moved into a
# chest or a hold must exist and be at most max_put at once. Pure rules, no scene.
# Dependencies: core/skill_levels.gd, data/guest_claims.json, data/fantasy/skilling.json (recipes, curve).
extends RefCounted

const SkillLevels = preload("res://core/skill_levels.gd")

var cfg: Dictionary
var joined_at := 0.0  # seconds (the caller's clock) when he joined
var _skills: SkillLevels
var _recipes: Array = []


func _init(config: Dictionary, skilling: Dictionary, skills_xp: Variant, now: float) -> void:
	cfg = config
	_recipes = skilling.get("recipes", [])
	_skills = SkillLevels.new(skilling)
	_skills.from_dict(skills_xp)
	joined_at = now


func level_at_join(skill: String) -> int:
	return _skills.level(skill)


# The highest level of `skill` he can plausibly have `now`.
func allowed_level(skill: String, now: float) -> int:
	var minutes := maxf(now - joined_at, 0.0) / 60.0
	var reach := int(_skills.xp.get(skill, 0)) + roundi(float(cfg["xp_per_minute"]) * minutes + float(cfg["xp_spare"]))
	var at := 1
	while at < _skills.max_level() and reach >= _skills.xp_for(at + 1):
		at += 1
	return at


func level_ok(skill: String, claimed: int, now: float) -> bool:
	return claimed >= 1 and claimed <= allowed_level(skill, now)


# Bags (Crafting recipes that make a backpack bag) his Crafting level at join could have made.
func bags_allowed(bag_items: Array) -> int:
	var n := 0
	for r: Dictionary in _recipes:
		for out: String in (r.get("out", {}) as Dictionary):
			if bag_items.has(out) and int(r.get("level", 1)) <= _skills.level(String(r.get("skill", ""))):
				n += 1
	return n


# The skill and level the recipe making `item` needs ([] when no recipe makes it).
func recipe_need(item: String) -> Array:
	for r: Dictionary in _recipes:
		if (r.get("out", {}) as Dictionary).has(item):
			return [String(r.get("skill", "")), int(r.get("level", 1))]
	return []


func put_ok(item_known: bool, n: int) -> bool:
	return item_known and n >= 1 and n <= int(cfg["max_put"])
