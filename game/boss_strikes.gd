# Purpose: what a sea super boss's attacks LOOK like on every machine (sea step 10): the warning marks on the floor
# while it winds up (a claw arc, a charge lane, the circle where it will burst up or land, the spots its spouts will
# hit) that fill as the blow comes, the bell toll's ring wave rolling out along the floor, and the water balls it lobs.
# One flat quad per mark drawn by a small shader (circle / ring / arc / lane), pooled; nothing is made per frame.
# Only drawing: damage is decided by game/sea_boss.gd on the host.
# Dependencies: game/fx_kit.gd (splashes). Lives under the arena's game/sea_dungeon.gd node (arena-local positions).
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")
const MARKS := 8
const BALLS := 8
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform int mode = 0;
uniform float radius = 3.0;
uniform float width = 1.0;
uniform float half_angle = 1.0;
uniform float len = 10.0;
uniform float fill = 0.0;
uniform vec4 col : source_color = vec4(1.0, 0.45, 0.12, 0.8);
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec2 p = lp.xz;
	float d = length(p);
	float inside = 0.0;
	float edge = 0.0;
	float grow = 0.0;
	if (mode == 0) {
		inside = step(d, radius);
		edge = step(radius - 0.18, d);
		grow = step(d, radius * fill);
	} else if (mode == 1) {
		inside = step(abs(d - radius), width * 0.5);
		edge = 1.0;
	} else if (mode == 2) {
		float ang = atan(p.x, -p.y);
		inside = step(d, radius) * step(abs(ang), half_angle);
		edge = max(step(radius - 0.2, d), step(half_angle - 0.03, abs(ang)));
		grow = step(d, radius * fill);
	} else {
		inside = step(0.0, -p.y) * step(-p.y, len) * step(abs(p.x), width * 0.5);
		edge = max(step(width * 0.5 - 0.15, abs(p.x)), step(len - 0.2, -p.y));
		grow = step(-p.y, len * fill);
	}
	ALBEDO = col.rgb;
	ALPHA = col.a * inside * clamp(0.22 + 0.33 * grow + 0.45 * edge, 0.0, 1.0);
}
"""

var _marks: Array = []  # MeshInstance3D (PlaneMesh + own ShaderMaterial)
var _balls: Array = []  # [MeshInstance3D, from, to, t, flight, splash radius]
var _shader: Shader
var _ball_mat: StandardMaterial3D


func _ready() -> void:
	_shader = Shader.new()
	_shader.code = SHADER
	for i in MARKS:
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2.0, 2.0)
		mi.mesh = plane
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_marks.append(mi)
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ball_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ball_mat.albedo_color = Color(0.55, 0.85, 1.0, 0.75)
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.45
	ball_mesh.height = 0.9
	ball_mesh.radial_segments = 12
	ball_mesh.rings = 6
	ball_mesh.material = _ball_mat
	for i in BALLS:
		var b := MeshInstance3D.new()
		b.mesh = ball_mesh
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false
		add_child(b)
		_balls.append([b, Vector3.ZERO, Vector3.ZERO, 0.0, 1.0, 1.0])


func clear() -> void:
	for mi: MeshInstance3D in _marks:
		mi.visible = false
	for b: Array in _balls:
		(b[0] as MeshInstance3D).visible = false


# One mark: mode 0 circle, 1 ring, 2 arc, 3 lane. at = arena-local floor point; yaw = facing (arcs, lanes).
func _mark(i: int, kind: int, at: Vector3, yaw: float, size: float, a: float, b: float, fill: float, color: Color) -> void:
	var mi: MeshInstance3D = _marks[i]
	var plane := mi.mesh as PlaneMesh
	var want := Vector2(size * 2.0, size * 2.0)
	if not plane.size.is_equal_approx(want):
		plane.size = want
	mi.position = at
	mi.rotation = Vector3(0.0, yaw, 0.0)
	var mat := mi.material_override as ShaderMaterial
	mat.set_shader_parameter("mode", kind)
	mat.set_shader_parameter("radius", a)
	mat.set_shader_parameter("width", b)
	mat.set_shader_parameter("half_angle", b)
	mat.set_shader_parameter("len", a)
	mat.set_shader_parameter("fill", fill)
	mat.set_shader_parameter("col", color)
	mi.visible = true


# Draws the marks for the move going on (called every frame by game/sea_boss.gd with the fight's state).
# mode: idle | windup | strike | recover | stunned; progress 0..1 through the windup; targets = arena-local points.
func show_move(attack: Dictionary, mode: String, progress: float, boss_at: Vector3, yaw: float, targets: Array, ring_r: float, floor_y: float) -> void:
	for mi: MeshInstance3D in _marks:
		mi.visible = false
	if attack.is_empty():
		return
	var warn := Color(1.0, 0.45, 0.12, 0.85)
	var shape := String(attack.get("shape", ""))
	var y := floor_y + 0.06
	var here := Vector3(boss_at.x, y, boss_at.z)
	if mode == "windup":
		match shape:
			"arc":
				_mark(0, 2, here, yaw, float(attack["reach"]), float(attack["reach"]), deg_to_rad(float(attack["deg"]) * 0.5), progress, warn)
			"charge":
				_mark(0, 3, here, yaw, float(attack["length"]), float(attack["length"]), float(attack["width"]), progress, warn)
			"ring":
				_mark(0, 0, here, 0.0, 2.5, 2.5, 0.0, progress, Color(0.4, 0.85, 1.0, 0.85))  # the bell swings: a glow round it
			"under", "leap", "lob":
				var col := Color(0.4, 0.85, 1.0, 0.85) if shape == "under" else warn
				for i in mini(targets.size(), MARKS):
					var t: Vector3 = targets[i]
					_mark(i, 0, Vector3(t.x, maxf(t.y, floor_y) + 0.06, t.z), 0.0, float(attack["radius"]), float(attack["radius"]), 0.0, progress, col)
	elif mode == "strike" and shape == "ring" and ring_r >= 0.0:
		_mark(0, 1, here, 0.0, float(attack["max_r"]) + 1.0, ring_r, float(attack["width"]), 1.0, Color(0.55, 0.9, 1.0, 0.9))


# The boss lobs water balls (spouts, bubbles): each flies to its spot in `flight` seconds and splashes there.
func lob(from: Vector3, targets: Array, flight: float, radius: float) -> void:
	for t: Vector3 in targets:
		for b: Array in _balls:
			var mi: MeshInstance3D = b[0]
			if mi.visible:
				continue
			b[1] = from
			b[2] = t
			b[3] = 0.0
			b[4] = maxf(flight, 0.2)
			b[5] = radius
			mi.position = from
			mi.visible = true
			break


func _process(delta: float) -> void:
	for b: Array in _balls:
		var mi: MeshInstance3D = b[0]
		if not mi.visible:
			continue
		b[3] = float(b[3]) + delta
		var k := clampf(float(b[3]) / float(b[4]), 0.0, 1.0)
		var from: Vector3 = b[1]
		var to: Vector3 = b[2]
		mi.position = from.lerp(to, k) + Vector3(0.0, sin(k * PI) * (4.0 + from.distance_to(to) * 0.25), 0.0)
		if k >= 1.0:
			mi.visible = false
			FxKit.burst(self, to_global(to + Vector3(0.0, 0.3, 0.0)), Color(0.6, 0.88, 1.0), 26, 0.9, 0.2, 2.0 + float(b[5]), -6.0)
