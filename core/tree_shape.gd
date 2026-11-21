# Purpose: (polish1 D4b / D4c) the plain numbers of a giant tree's trunk, shared by the builder (game/giant_trees.gd)
# and the treetop rules (core/treetop_rules.gd): how wide the trunk is at a height, which way it leans, where its
# axis is at a height. Pure: no nodes, no drawing.
# Dependencies: none.
extends RefCounted

const FLARE := 0.55  # the foot is this much wider than the trunk ...
const FLARE_FALL := 1.4  # ... fading over about this many metres up
const TOP_SHARE := 0.78  # the trunk proper ends at this share of the tree's height (the crown above)


# How wide the trunk is at height y (from the ground) for a tree of this height and girth (radius).
static func radius_at(y: float, height: float, girth: float) -> float:
	return girth * (1.0 - 0.45 * clampf(y / height, 0.0, 1.0)) * (1.0 + FLARE * exp(-maxf(y, 0.0) / FLARE_FALL))


# The tree's seed from where it stands (world-plan metres): the same tree everywhere.
static func seed_of(at: Vector2) -> int:
	return int(absf(at.x * 7.0 + at.y * 13.0))


# Which way and how far the trunk leans at its top (the first three draws of the tree's own random numbers).
static func lean_of(at: Vector2) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_of(at)
	return Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.4, 1.2)


# The trunk's middle at height y (plan position), leaning more the higher.
static func axis_at(at: Vector2, y: float, height: float) -> Vector2:
	var t := clampf(y / (height * TOP_SHARE), 0.0, 1.0)
	return at + lean_of(at) * t * t
