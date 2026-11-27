extends RefCounted
# Purpose: (polish1 F3, director 2026-11-27) countries are entered only at their crossings. A player who gets past a
# border ridge onto the neighbour's land (core/country_shape.gd away_at: well past the border line, so the crest and
# the passes at crossings stay free) is walked back to where they last stood in their own country.
# Each machine watches its own player; nothing is sent.
# Dependencies: core/country_shape.gd.

var _last := Vector3.ZERO  # where the player last stood on ground that is not a neighbour's
var _have := false


# The spot (map metres) to put the player back on when `local` lies on a neighbour's land; Vector3.INF when all is well.
func check(shape: RefCounted, local: Vector3) -> Vector3:
	if shape == null:
		return Vector3.INF
	if not bool(shape.call("away_at", local.x, local.z)):
		_last = local
		_have = true
		return Vector3.INF
	return _last if _have else Vector3.INF
