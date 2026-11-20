# Purpose: (polish1 item 71) pool table physics, pure and in 2D (metres, seen from above: x along the table, y across):
# 16 balls (0 = the cue ball, 1-7 solids, 8, 9-15 stripes) that slide and roll on the cloth, collide, bounce off the
# cushions (with the pocket jaws as round ends), drop into 6 pockets. A shot = aim angle, power and where the cue tip
# hits the cue ball (spin: x = left / right english, y = draw / follow). Each ball keeps the velocity its contact
# point "wants" (`roll`): a centre hit slides first and then rolls, a high hit runs on after the object ball (follow),
# a low hit comes back (draw), side english changes the angle off a cushion. The shot's events (first ball hit,
# pocketed balls with their pocket, cushions after the first contact) are what core/pool_rules.gd judges.
# Dependencies: data/pool.json (table, physics numbers) passed in. No nodes.
extends RefCounted

const BALLS := 16
const STEP := 1.0 / 240.0

var length := 2.54
var width := 1.27
var r := 0.028575  # ball radius
var max_speed := 7.0  # cue ball speed at full power, m/s
var slide := 2.0  # sliding friction deceleration (mu * g), m/s^2
var rolling := 0.13  # rolling deceleration, m/s^2
var side_decay := 0.6  # english lost each second while moving
var ball_e := 0.94  # ball on ball restitution
var cushion_e := 0.78
var english_effect := 0.35  # how much side spin bends a cushion bounce
var corner_mouth := 0.07  # cushion stops this far from a corner (along each rail)
var side_mouth := 0.062  # half the side pocket's gap
var corner_r := 0.072  # a ball whose centre gets this close to a corner pocket's middle drops
var side_r := 0.062

var pos := PackedVector2Array()
var vel := PackedVector2Array()
var roll := PackedVector2Array()  # velocity of the contact point's "wish": roll == vel is natural rolling
var side := PackedFloat32Array()  # side english, m/s at the equator (+ = right english)
var on_table := PackedByteArray()  # 1 = on the cloth
var spin_angle := PackedFloat32Array()  # for drawing: how far each ball has rolled (radians), with its axis below
var pockets: Array[Vector2] = []
var rails: Array = []  # [from, to] segments of the cushion noses (ball centres keep r away from them)

# events of the current shot
var first_hit := -1
var pocketed: Array = []  # [ball, pocket index] in order
var rail_after_contact := false
var cue_rails := 0
var moving := false
var clicks := 0  # ball on ball knocks so far (for sounds: the count only grows)
var bumps := 0  # cushion knocks so far
var _left := 0.0


func _init(data: Dictionary = {}) -> void:
	var t: Dictionary = data.get("table", {})
	length = float(t.get("length", length))
	width = float(t.get("width", width))
	r = float(t.get("ball_radius", r))
	corner_mouth = float(t.get("corner_mouth", corner_mouth))
	side_mouth = float(t.get("side_mouth", side_mouth))
	corner_r = float(t.get("corner_capture", corner_r))
	side_r = float(t.get("side_capture", side_r))
	var ph: Dictionary = data.get("physics", {})
	max_speed = float(ph.get("max_speed", max_speed))
	slide = float(ph.get("slide", slide))
	rolling = float(ph.get("rolling", rolling))
	side_decay = float(ph.get("side_decay", side_decay))
	ball_e = float(ph.get("ball_restitution", ball_e))
	cushion_e = float(ph.get("cushion_restitution", cushion_e))
	english_effect = float(ph.get("english", english_effect))
	pos.resize(BALLS)
	vel.resize(BALLS)
	roll.resize(BALLS)
	side.resize(BALLS)
	on_table.resize(BALLS)
	spin_angle.resize(BALLS)
	var hx := length * 0.5
	var hy := width * 0.5
	var cd := 0.02  # corner pocket middles sit a little outside the corner
	pockets = [Vector2(-hx - cd, -hy - cd), Vector2(0, -hy - 0.04), Vector2(hx + cd, -hy - cd), Vector2(-hx - cd, hy + cd), Vector2(0, hy + 0.04), Vector2(hx + cd, hy + cd)]
	var c := corner_mouth
	var s := side_mouth
	rails = [
		[Vector2(-hx + c, -hy), Vector2(-s, -hy)], [Vector2(s, -hy), Vector2(hx - c, -hy)],  # near long rail (y -)
		[Vector2(-hx + c, hy), Vector2(-s, hy)], [Vector2(s, hy), Vector2(hx - c, hy)],  # far long rail (y +)
		[Vector2(-hx, -hy + c), Vector2(-hx, hy - c)],  # head rail (x -)
		[Vector2(hx, -hy + c), Vector2(hx, hy - c)]]  # foot rail (x +)


func head_spot() -> Vector2:
	return Vector2(-length * 0.25, 0.0)


func foot_spot() -> Vector2:
	return Vector2(length * 0.25, 0.0)


# A fresh rack: the cue ball on the head spot, the triangle's apex on the foot spot, the 8 in the middle of the third
# row, a solid and a stripe in the back corners, the rest shuffled.
func rack(rng: RandomNumberGenerator) -> void:
	var others: Array = [2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15]
	for i in range(others.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = others[i]
		others[i] = others[j]
		others[j] = tmp
	var order: Array = []  # by row: 1, 2, 3 (8 in the middle), 4, 5 (corners: a solid, a stripe)
	order.append(others.pop_back())
	order.append(others.pop_back())
	order.append(others.pop_back())
	order.append(others.pop_back())
	order.append(8)
	order.append(others.pop_back())
	for k in 4:
		order.append(others.pop_back())
	order.append(1 if rng.randf() < 0.5 else 9)
	for k in 3:
		order.append(others.pop_back())
	order.append(9 if int(order[10]) == 1 else 1)
	var gap := r * 2.0 + 0.0004
	var n := 0
	for row in 5:
		for k in row + 1:
			var ball: int = order[n]
			n += 1
			pos[ball] = foot_spot() + Vector2(float(row) * gap * 0.8660254, (float(k) - float(row) * 0.5) * gap)
	pos[0] = head_spot()
	for i in BALLS:
		vel[i] = Vector2.ZERO
		roll[i] = Vector2.ZERO
		side[i] = 0.0
		on_table[i] = 1
	moving = false


# A shot: angle (radians, 0 = +x), power 0..1, spin = tip offset (x right english, y follow / draw), length <= 1.
func shoot(angle: float, power: float, spin: Vector2) -> void:
	spin = spin.limit_length(1.0)
	var dir := Vector2(cos(angle), sin(angle))
	var speed := clampf(power, 0.0, 1.0) * max_speed
	vel[0] = dir * speed
	roll[0] = dir * speed * 1.25 * spin.y  # a tip half a radius off the middle gives 2.5 x 0.5 = 1.25 x the speed
	side[0] = speed * 1.25 * spin.x
	first_hit = -1
	pocketed.clear()
	rail_after_contact = false
	cue_rails = 0
	moving = true
	_left = 0.0


func step(dt: float) -> bool:
	_left += dt
	while _left >= STEP and moving:
		_left -= STEP
		_tick()
	return moving


# Plays the shot to the end (for the host and the AI's tries).
func run_to_rest(max_seconds := 25.0) -> void:
	var t := 0.0
	while moving and t < max_seconds:
		_tick()
		t += STEP
	if moving:
		for i in BALLS:
			vel[i] = Vector2.ZERO
			roll[i] = Vector2.ZERO
		moving = false


func _tick() -> void:
	var any := false
	for i in BALLS:
		if on_table[i] == 0:
			continue
		var v := vel[i]
		var w := roll[i]
		var rel := v - w
		var rl := rel.length()
		if rl > 0.002:  # sliding: friction pulls the ball and its spin toward rolling
			var dv := minf(slide * STEP, rl * 2.0 / 7.0)
			var d := rel / rl
			v -= d * dv
			w += d * dv * 2.5
		else:  # rolling
			var sp := v.length()
			if sp > 0.0:
				var ns := maxf(sp - rolling * STEP, 0.0)
				v *= ns / sp
			w = v
		side[i] *= 1.0 - side_decay * STEP
		vel[i] = v
		roll[i] = w
		if v.length_squared() > 1e-8:
			pos[i] += v * STEP
			spin_angle[i] += v.length() * STEP / r
			any = true
	for i in BALLS:  # balls on balls
		if on_table[i] == 0:
			continue
		for j in range(i + 1, BALLS):
			if on_table[j] == 0 or (vel[i] == Vector2.ZERO and vel[j] == Vector2.ZERO):
				continue
			var dvec := pos[j] - pos[i]
			var d2 := dvec.length_squared()
			var min_d := 2.0 * r
			if d2 >= min_d * min_d or d2 < 1e-12:
				continue
			var dist := sqrt(d2)
			var n := dvec / dist
			var push := (min_d - dist) * 0.5
			pos[i] -= n * push
			pos[j] += n * push
			var approach := (vel[i] - vel[j]).dot(n)
			if approach <= 0.0:
				continue
			var jimp := approach * (1.0 + ball_e) * 0.5
			if approach > 0.15:
				clicks += 1
			vel[i] -= n * jimp
			vel[j] += n * jimp
			if i == 0 and first_hit < 0:
				first_hit = j
			any = true
	for i in BALLS:  # cushions and pockets
		if on_table[i] == 0 or vel[i] == Vector2.ZERO:
			continue
		for k in pockets.size():
			var cap := corner_r if k != 1 and k != 4 else side_r
			if pos[i].distance_squared_to(pockets[k]) < cap * cap:
				on_table[i] = 0
				vel[i] = Vector2.ZERO
				roll[i] = Vector2.ZERO
				pocketed.append([i, k])
				break
		if on_table[i] == 0:
			continue
		for seg: Array in rails:
			_cushion(i, seg[0], seg[1])
		var hx := length * 0.5 + 0.12
		var hy := width * 0.5 + 0.12
		if absf(pos[i].x) > hx or absf(pos[i].y) > hy:  # jumped the table (should not happen): off, counts as pocketed nowhere
			on_table[i] = 0
			pocketed.append([i, -1])
	moving = any


func _cushion(i: int, a: Vector2, b: Vector2) -> void:
	var ab := b - a
	var t := clampf((pos[i] - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest := a + ab * t
	var dvec := pos[i] - closest
	var d := dvec.length()
	if d >= r or d < 1e-9:
		return
	var n := dvec / d
	pos[i] = closest + n * r
	var vn := vel[i].dot(n)
	if vn >= 0.0:
		return
	if vn < -0.2:
		bumps += 1
	var tangent := Vector2(-n.y, n.x)
	var vt := vel[i].dot(tangent)
	vt += side[i] * english_effect  # right english (counter-clockwise from above) throws the ball along +tangent
	vel[i] = tangent * vt - n * vn * cushion_e
	roll[i] = roll[i] - n * roll[i].dot(n) * (1.0 + cushion_e)
	side[i] *= 0.5
	if first_hit >= 0:
		rail_after_contact = true
	if i == 0:
		cue_rails += 1


# Puts a ball back (ball in hand, a re-spotted 8): returns false if it would overlap a ball or leave the cloth.
func place(ball: int, at: Vector2) -> bool:
	if absf(at.x) > length * 0.5 - r or absf(at.y) > width * 0.5 - r:
		return false
	for j in BALLS:
		if j != ball and on_table[j] == 1 and pos[j].distance_to(at) < 2.0 * r:
			return false
	pos[ball] = at
	vel[ball] = Vector2.ZERO
	roll[ball] = Vector2.ZERO
	side[ball] = 0.0
	on_table[ball] = 1
	return true


# The state for the network / a copy for the AI.
func to_dict() -> Dictionary:
	return {"pos": pos.duplicate(), "on": on_table.duplicate()}


func from_dict(d: Dictionary) -> void:
	var p: PackedVector2Array = d["pos"]
	var o: PackedByteArray = d["on"]
	for i in BALLS:
		pos[i] = p[i]
		on_table[i] = o[i]
		vel[i] = Vector2.ZERO
		roll[i] = Vector2.ZERO
		side[i] = 0.0
	moving = false


func copy() -> RefCounted:
	var c: RefCounted = get_script().new()
	for prop: String in ["length", "width", "r", "max_speed", "slide", "rolling", "side_decay", "ball_e", "cushion_e", "english_effect", "corner_mouth", "side_mouth", "corner_r", "side_r"]:
		c.set(prop, get(prop))
	c.set("pockets", pockets)
	c.set("rails", rails)
	c.call("from_dict", to_dict())
	return c
