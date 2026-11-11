# Purpose: pachinko ball simulation: a small deterministic 2D physics run (balls fall through a peg lattice into pockets). Rendering only draws its state; payout comes from the same run. No Godot physics.
# Dependencies: none (data from data/pachinko.json passed in). Caller owns the seed.
extends RefCounted

const STEP := 1.0 / 120.0

var bins := 9
var bin_width := 1.0
var rows := 13
var row_gap := 0.85
var top := 1.5
var ball_radius := 0.17
var peg_radius := 0.09
var gravity := 14.0
var damping := 0.25
var restitution := 0.55
var bounce_jitter := 1.2
var launch_jitter := 0.35
var aim_min_x := 3.0
var aim_max_x := 6.0
var max_speed := 14.0
var max_age := 25.0
var max_balls := 40
var ball_cost := 2
var multipliers: Array = []

var width := 9.0
var floor_y := 12.4
var xs := PackedFloat32Array()
var ys := PackedFloat32Array()
var vxs := PackedFloat32Array()
var vys := PackedFloat32Array()
var ages := PackedFloat32Array()
var count := 0
var hit_pegs := PackedInt32Array()  # peg ids (row * 100 + column) touched during the last step() call

var _rng := RandomNumberGenerator.new()
var _left := 0.0


func _init(data: Dictionary, seed_value: int = 0) -> void:
	bins = int(data["bins"])
	bin_width = float(data["bin_width"])
	rows = int(data["rows"])
	row_gap = float(data["row_gap"])
	top = float(data["top"])
	ball_radius = float(data["ball_radius"])
	peg_radius = float(data["peg_radius"])
	gravity = float(data["gravity"])
	damping = float(data["damping"])
	restitution = float(data["restitution"])
	bounce_jitter = float(data["bounce_jitter"])
	launch_jitter = float(data["launch_jitter"])
	aim_min_x = float(data["aim_min_x"])
	aim_max_x = float(data["aim_max_x"])
	max_speed = float(data["max_speed"])
	max_age = float(data["max_age"])
	max_balls = int(data["max_balls"])
	ball_cost = int(data["ball_cost"])
	multipliers = data["pocket_multipliers"]
	width = float(bins) * bin_width
	floor_y = top + float(rows - 1) * row_gap + float(data["floor_extra"])
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	xs.resize(max_balls)
	ys.resize(max_balls)
	vxs.resize(max_balls)
	vys.resize(max_balls)
	ages.resize(max_balls)


# Peg position for a row/column (even rows have bins+1 pegs on the bin edges, odd rows bins pegs between them).
func peg_x(row: int, col: int) -> float:
	var off := 0.5 if row % 2 == 1 else 0.0
	return (float(col) + off) * bin_width


func peg_y(row: int) -> float:
	return top + float(row) * row_gap


func peg_count_in_row(row: int) -> int:
	return bins if row % 2 == 1 else bins + 1


func multiplier(pocket: int) -> float:
	return float(multipliers[pocket])


func payout(pocket: int) -> int:
	return floori(multiplier(pocket) * float(ball_cost) + 0.0001)


# aim 0..1 across the aim range (aim_min_x..aim_max_x) at the top of the board. Returns false when the board is full.
func launch(aim: float) -> bool:
	if count >= max_balls:
		return false
	var i := count
	count += 1
	xs[i] = clampf(lerpf(aim_min_x, aim_max_x, aim) + (_rng.randf() - 0.5) * launch_jitter, ball_radius, width - ball_radius)
	ys[i] = 0.3
	vxs[i] = (_rng.randf() - 0.5) * launch_jitter * 2.0
	vys[i] = 0.0
	ages[i] = 0.0
	return true


# Advance by dt; returns the pockets (0..bins-1) of balls that landed during this call.
func step(dt: float) -> Array[int]:
	var landed: Array[int] = []
	hit_pegs.clear()
	_left += dt
	while _left >= STEP:
		_left -= STEP
		_tick(landed)
	return landed


func _tick(landed: Array[int]) -> void:
	var i := 0
	while i < count:
		ages[i] += STEP
		var vx := vxs[i] * (1.0 - damping * STEP)
		var vy := vys[i] * (1.0 - damping * STEP) + gravity * STEP
		var speed := sqrt(vx * vx + vy * vy)
		if speed > max_speed:
			vx *= max_speed / speed
			vy *= max_speed / speed
		var x := xs[i] + vx * STEP
		var y := ys[i] + vy * STEP
		if x < ball_radius:
			x = ball_radius
			vx = absf(vx) * restitution
		elif x > width - ball_radius:
			x = width - ball_radius
			vx = -absf(vx) * restitution
		# pegs of the nearest rows only
		var row0 := roundi((y - top) / row_gap)
		for row in range(maxi(row0 - 1, 0), mini(row0 + 2, rows)):
			var off := 0.5 if row % 2 == 1 else 0.0
			var col0 := roundi(x / bin_width - off)
			var py := peg_y(row)
			for col in range(maxi(col0 - 1, 0), mini(col0 + 2, peg_count_in_row(row))):
				var px := peg_x(row, col)
				var dx := x - px
				var dy := y - py
				var reach := ball_radius + peg_radius
				var d2 := dx * dx + dy * dy
				if d2 < reach * reach:
					var d := sqrt(d2)
					var nx := 0.0
					var ny := -1.0
					if d > 0.0001:
						nx = dx / d
						ny = dy / d
					x = px + nx * reach
					y = py + ny * reach
					var vn := vx * nx + vy * ny
					if vn < 0.0:
						vx -= (1.0 + restitution) * vn * nx
						vy -= (1.0 + restitution) * vn * ny
						vx += (_rng.randf() - 0.5) * bounce_jitter
					hit_pegs.append(row * 100 + col)
		if y >= floor_y or ages[i] > max_age:
			landed.append(clampi(floori(x / bin_width), 0, bins - 1))
			count -= 1
			xs[i] = xs[count]
			ys[i] = ys[count]
			vxs[i] = vxs[count]
			vys[i] = vys[count]
			ages[i] = ages[count]
			continue
		xs[i] = x
		ys[i] = y
		vxs[i] = vx
		vys[i] = vy
		i += 1
