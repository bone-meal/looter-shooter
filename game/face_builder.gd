# Purpose: draws a face expression (eyes, brows, mouth, extras like blush or tears) on the front of the head from flat boxes. Female characters also get eyelashes and colored lips.
# Dependencies: game/body_parts.gd, game/body_ctx.gd. The expression comes from data/expressions.json.
extends RefCounted

const P = preload("res://game/body_parts.gd")
const Ctx = preload("res://game/body_ctx.gd")

const INK := Color(0.08, 0.07, 0.09)
const WHITE := Color(0.97, 0.97, 0.97)
const PINK := Color(1.0, 0.55, 0.62)
const TONGUE := Color(0.95, 0.4, 0.5)
const LIP := Color(0.72, 0.2, 0.3)
const WATER := Color(0.45, 0.75, 1.0)
const GOLD := Color(1.0, 0.85, 0.2)


static var _rx := 0.12  # skull radii (see body_builder._head_shape); face boxes are placed on this curve
static var _ry := 0.128
static var _rz := 0.115


# Adds the face to c.head. `expr` is one entry of data/expressions.json.
static func build(c: Ctx, expr: Dictionary) -> void:
	_rx = c.head_w * 0.5
	_rz = c.head_d * 0.5
	var face := P.pivot(c.head, "Face", Vector3(0.0, 0.12, -c.head_d * 0.5 - 0.002))
	var ex := c.head_w * 0.22
	var eyes := String(expr["eyes"])
	var eye_group := P.pivot(face, "Eyes", Vector3(0.0, 0.02, 0.0))  # eyes + lashes live here so body_motion.gd can blink by scaling y
	for s: float in [-1.0, 1.0]:
		var style := eyes
		if eyes == "wink":
			style = "closed" if s > 0.0 else "open"
		var first := face.get_child_count()
		_eye(face, s * ex, 0.02, style, s)
		if c.female:
			_lash(face, s * ex, 0.02, s, style == "closed" or style == "happy")
		var moved: Array[Node] = []
		for i in range(first, face.get_child_count()):
			moved.append(face.get_child(i))
		for node in moved:
			face.remove_child(node)
			(node as Node3D).position -= eye_group.position
			eye_group.add_child(node)
		_brow(face, s * ex, String(expr["brows"]), s)
	_mouth(face, String(expr["mouth"]), c.female)
	_extra(face, String(expr["extra"]), c.head_w)


static func _b(face: Node3D, size: Vector2, x: float, y: float, color: Color, layer := 0, rot_z := 0.0, glow := false) -> void:
	# Sit on the skull's curve: push back by how far the surface curves away, and turn to face along its normal.
	var k := clampf(1.0 - (x * x) / (_rx * _rx) - (y * y) / (_ry * _ry), 0.05, 1.0)
	var zs := -_rz * sqrt(k)  # surface z relative to the skull centre
	var inset := _rz + zs
	var yaw := -rad_to_deg(atan2(x / (_rx * _rx), -zs / (_rz * _rz)))
	var pitch := rad_to_deg(atan2(y / (_ry * _ry), -zs / (_rz * _rz)))
	P.box(face, Vector3(size.x, size.y, 0.003), Vector3(x, y, -0.001 - layer * 0.003 + inset), P.mat(color, glow), Vector3(pitch, yaw, rot_z))


static func _eye(f: Node3D, x: float, y: float, style: String, s: float) -> void:
	match style:
		"open":
			_b(f, Vector2(0.05, 0.042), x, y, WHITE)
			_b(f, Vector2(0.026, 0.036), x, y, INK, 1)
		"wide":
			_b(f, Vector2(0.062, 0.062), x, y, WHITE)
			_b(f, Vector2(0.03, 0.03), x, y, INK, 1)
		"dot":
			_b(f, Vector2(0.024, 0.03), x, y, INK)
		"happy":
			_b(f, Vector2(0.03, 0.01), x - s * 0.012, y - 0.004, INK, 0, 35.0 * s * -1.0)
			_b(f, Vector2(0.03, 0.01), x + s * 0.012, y - 0.004, INK, 0, 35.0 * s)
		"closed":
			_b(f, Vector2(0.05, 0.009), x, y - 0.006, INK)
		"angry":
			_b(f, Vector2(0.05, 0.03), x, y - 0.004, WHITE)
			_b(f, Vector2(0.024, 0.028), x, y - 0.004, INK, 1)
		"sad":
			_b(f, Vector2(0.05, 0.042), x, y, WHITE)
			_b(f, Vector2(0.026, 0.026), x, y - 0.008, INK, 1)
		"star":
			_b(f, Vector2(0.05, 0.014), x, y, GOLD, 0, 0.0, true)
			_b(f, Vector2(0.014, 0.05), x, y, GOLD, 0, 0.0, true)
			_b(f, Vector2(0.036, 0.012), x, y, GOLD, 1, 45.0, true)
			_b(f, Vector2(0.036, 0.012), x, y, GOLD, 1, -45.0, true)
		"heart":
			_b(f, Vector2(0.022, 0.022), x - 0.011, y + 0.008, Color(0.95, 0.2, 0.35), 0, 0.0, true)
			_b(f, Vector2(0.022, 0.022), x + 0.011, y + 0.008, Color(0.95, 0.2, 0.35), 0, 0.0, true)
			_b(f, Vector2(0.026, 0.026), x, y - 0.006, Color(0.95, 0.2, 0.35), 0, 45.0, true)
		"x":
			_b(f, Vector2(0.044, 0.01), x, y, INK, 0, 45.0)
			_b(f, Vector2(0.044, 0.01), x, y, INK, 0, -45.0)
		"sleepy":
			_b(f, Vector2(0.05, 0.02), x, y - 0.004, WHITE)
			_b(f, Vector2(0.024, 0.016), x, y - 0.006, INK, 1)
			_b(f, Vector2(0.056, 0.008), x, y + 0.008, INK, 2)
		"half":
			_b(f, Vector2(0.05, 0.026), x, y - 0.004, WHITE)
			_b(f, Vector2(0.024, 0.024), x, y - 0.004, INK, 1)
			_b(f, Vector2(0.056, 0.008), x, y + 0.01, INK, 2)
		"side":
			_b(f, Vector2(0.05, 0.042), x, y, WHITE)
			_b(f, Vector2(0.024, 0.036), x + 0.012, y, INK, 1)


static func _lash(f: Node3D, x: float, y: float, s: float, closed: bool) -> void:
	_b(f, Vector2(0.06, 0.009), x, y + (0.012 if not closed else 0.0), INK, 2)
	_b(f, Vector2(0.018, 0.009), x + s * 0.03, y + 0.02, INK, 2, 35.0 * s)


static func _brow(f: Node3D, x: float, style: String, s: float) -> void:
	var y := 0.075
	match style:
		"neutral":
			_b(f, Vector2(0.05, 0.01), x, y, INK)
		"raised":
			_b(f, Vector2(0.05, 0.01), x, y + 0.015, INK)
		"angry":
			_b(f, Vector2(0.054, 0.012), x, y - 0.008, INK, 0, 22.0 * s)
		"sad":
			_b(f, Vector2(0.05, 0.01), x, y, INK, 0, -22.0 * s)
		"tilt":
			if s < 0.0:
				_b(f, Vector2(0.05, 0.01), x, y + 0.02, INK)
			else:
				_b(f, Vector2(0.05, 0.01), x, y - 0.004, INK, 0, 15.0)


static func _mouth(f: Node3D, style: String, female: bool) -> void:
	var y := -0.07
	var ink := LIP if female else INK
	match style:
		"flat":
			_b(f, Vector2(0.06, 0.01), 0.0, y, ink)
		"smile":
			_smile(f, y, ink, 1.0)
		"frown":
			_smile(f, y, ink, -1.0)
		"grin":
			_b(f, Vector2(0.08, 0.04), 0.0, y, INK)
			_b(f, Vector2(0.066, 0.024), 0.0, y + 0.004, WHITE, 1)
		"teeth":
			_b(f, Vector2(0.08, 0.04), 0.0, y, INK)
			_b(f, Vector2(0.066, 0.024), 0.0, y + 0.004, WHITE, 1)
			_b(f, Vector2(0.004, 0.026), 0.0, y + 0.004, INK, 2)
			_b(f, Vector2(0.004, 0.026), 0.02, y + 0.004, INK, 2)
			_b(f, Vector2(0.004, 0.026), -0.02, y + 0.004, INK, 2)
		"o":
			_b(f, Vector2(0.03, 0.036), 0.0, y, INK)
		"open":
			_b(f, Vector2(0.056, 0.042), 0.0, y, INK)
			_b(f, Vector2(0.03, 0.014), 0.0, y - 0.014, TONGUE, 1)
		"tongue":
			_smile(f, y, ink, 1.0)
			_b(f, Vector2(0.026, 0.034), 0.004, y - 0.02, TONGUE, 1)
		"cat":
			_b(f, Vector2(0.03, 0.009), -0.014, y, ink, 0, -35.0)
			_b(f, Vector2(0.03, 0.009), 0.014, y, ink, 0, 35.0)
		"smirk":
			_b(f, Vector2(0.05, 0.01), 0.006, y, ink)
			_b(f, Vector2(0.016, 0.01), 0.04, y + 0.008, ink, 0, 40.0)
		"wobble":
			for i in 4:
				_b(f, Vector2(0.016, 0.01), -0.027 + i * 0.018, y + (0.006 if i % 2 == 0 else -0.006), ink)
		"pout":
			_b(f, Vector2(0.034, 0.012), 0.0, y, ink)
			_b(f, Vector2(0.026, 0.012), 0.0, y - 0.011, PINK, 1)
		"kiss":
			_b(f, Vector2(0.022, 0.024), 0.0, y, PINK, 0, 0.0, true)
			_b(f, Vector2(0.01, 0.01), 0.0, y, INK, 1)
		"small":
			_b(f, Vector2(0.026, 0.008), 0.0, y, ink)


static func _smile(f: Node3D, y: float, ink: Color, dir: float) -> void:
	_b(f, Vector2(0.036, 0.01), 0.0, y - 0.01 * dir, ink)
	_b(f, Vector2(0.018, 0.01), -0.03, y - 0.002 * dir, ink, 0, -30.0 * dir)
	_b(f, Vector2(0.018, 0.01), 0.03, y - 0.002 * dir, ink, 0, 30.0 * dir)


static func _extra(f: Node3D, style: String, head_w: float) -> void:
	match style:
		"blush":
			_b(f, Vector2(0.04, 0.02), -head_w * 0.3, -0.03, PINK)
			_b(f, Vector2(0.04, 0.02), head_w * 0.3, -0.03, PINK)
		"tear":
			_b(f, Vector2(0.012, 0.05), -head_w * 0.25, -0.03, WATER, 2)
			_b(f, Vector2(0.012, 0.05), head_w * 0.25, -0.03, WATER, 2)
		"sweat":
			_b(f, Vector2(0.016, 0.03), head_w * 0.38, 0.06, WATER, 2)
