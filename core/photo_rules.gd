# Purpose: pure photo-mode rules: how far the free camera may fly from the player, how the view angle steps, and the
# name of a picture file. No nodes, no files.
# Dependencies: data/photo_mode.json (handed in through setup).
extends RefCounted

var reach := 25.0
var fov_min := 15.0
var fov_max := 110.0
var fov_step := 5.0


func setup(cfg: Dictionary) -> void:
	reach = float(cfg.get("reach", reach))
	fov_min = float(cfg.get("fov_min", fov_min))
	fov_max = float(cfg.get("fov_max", fov_max))
	fov_step = float(cfg.get("fov_step", fov_step))


# Where the camera may be: `wanted`, pulled back onto the ball of `reach` metres round `anchor`.
func keep_near(anchor: Vector3, wanted: Vector3) -> Vector3:
	var away := wanted - anchor
	return anchor + away.limit_length(reach)


# The view angle after `clicks` wheel steps (positive = zoom in = narrower).
func zoomed(fov: float, clicks: int) -> float:
	return clampf(fov - float(clicks) * fov_step, fov_min, fov_max)


# "photo_2026-11-13_14-05-09.png" (a second number is added by the caller when two land in the same second).
func file_name(when: Dictionary, extra: int) -> String:
	var stamp := "%04d-%02d-%02d_%02d-%02d-%02d" % [int(when.get("year", 0)), int(when.get("month", 0)), int(when.get("day", 0)), int(when.get("hour", 0)), int(when.get("minute", 0)), int(when.get("second", 0))]
	return "photo_%s%s.png" % [stamp, ("_%d" % extra) if extra > 0 else ""]
