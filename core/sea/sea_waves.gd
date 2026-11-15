# Purpose: pure maths of the sea's rolling waves (sea step 4), the same sum the ocean shader draws (game/sea_ocean.gd),
# so ships and swimmers ride exactly the surface on screen: a few long sine waves, each a share of the swell height,
# moving at deep-water speed for its length. The swell (metres) comes from the region and its weather.
# Dependencies: none (data/sea/world.json "waves" passed in).
extends RefCounted

const GRAVITY := 9.81

# Per wave: [dir x, dir z, wavenumber k, angular speed w, share] (pre-computed from the data).
var _waves: Array = []


func _init(cfg: Dictionary) -> void:
	for wave: Dictionary in cfg["list"]:
		var a := deg_to_rad(float(wave["dir"]))
		var k := TAU / float(wave["length"])
		_waves.append([cos(a), sin(a), k, sqrt(GRAVITY * k) * float(wave.get("speed", 1.0)), float(wave["share"])])


# The water's height (m above sea level) at a sea position and time, for a swell of `swell` metres (crest to mean).
func height_at(x: float, z: float, t: float, swell: float) -> float:
	var h := 0.0
	for w: Array in _waves:
		h += sin((x * float(w[0]) + z * float(w[1])) * float(w[2]) - float(w[3]) * t) * float(w[4])
	return h * swell


# The surface's upward normal at a sea position (from the height's slope), for tilting ships.
func normal_at(x: float, z: float, t: float, swell: float) -> Vector3:
	var dx := 0.0
	var dz := 0.0
	for w: Array in _waves:
		var c := cos((x * float(w[0]) + z * float(w[1])) * float(w[2]) - float(w[3]) * t) * float(w[4]) * float(w[2]) * swell
		dx += c * float(w[0])
		dz += c * float(w[1])
	return Vector3(-dx, 1.0, -dz).normalized()


# The waves as the shader's uniforms: four vec4 (dir x, dir z, k, w) and a vec4 of shares (unused waves are zero).
func shader_waves() -> Array:
	var out: Array = []
	var shares := Vector4.ZERO
	for i in 3:
		if i < _waves.size():
			var w: Array = _waves[i]
			out.append(Vector4(float(w[0]), float(w[1]), float(w[2]), float(w[3])))
			shares[i] = float(w[4])
		else:
			out.append(Vector4.ZERO)
	out.append(shares)
	return out
