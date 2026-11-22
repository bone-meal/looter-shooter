# Purpose: builds a worn mask (polish1 D5c) for a character's head anchor: the baked game mesh from
# tools/blender/mask_bake.py (assets/masks/<id>/hi|lo.obj, made in the anchor's space) with one shader that reads its
# colour / normal / ORM / FX maps (FX = where the eyes glow: they flash the mask's Morse messages), a slight hat-brim
# sway and leather breathing, and the mask's own effects (Plague Doctor: green death mist and flies from the beak), all
# by the graphics tier (`tier`, set by the session: mesh level, texture size, how many particles). Meshes, textures
# and materials are shared between everyone wearing the same mask. A moving part (FX blue: Iron Reaper's jaw) turns about
# its hinge in the vertex shader; masks without Morse can pulse their glow. Per wearer `moving` (0 still .. 1 running,
# an instance uniform set by game/rigged_body.gd) quickens the pulse (move_pulse) or dims the glow (stillness); cracks
# in glow group G can open and heal (heal_every); ash puffs (fx ash) rise off the mask; the moving part can instead
# turn round an axis (fx spin); glow hues from the colour map (fx glow_from_col); haze puffs (fx haze); frost puffs only on the move / a quick turn (fx frost: MoveFx).
# Dependencies: core/mask_db.gd, core/data_store.gd, data/masks.json, assets/masks/<id>/.
extends RefCounted

const MaskDb = preload("res://core/mask_db.gd")
const DataStore = preload("res://core/data_store.gd")

const ROOT := "res://assets/masks/"
const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D col_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D fx_tex : hint_default_black, filter_linear_mipmap;
uniform sampler2D morse_tex : filter_nearest;
uniform int morse_len = 1;
uniform float morse_unit = 0.16;
uniform vec3 glow_color : source_color = vec3(0.35, 1.0, 0.3);
uniform float glow_strength = 6.0;
uniform float sway = 0.0;
uniform float breathe = 0.0;
uniform vec3 head_mid = vec3(0.0, 0.1, -0.02);
uniform float pulse_hz = 0.0;  // steady glow that pulses (masks without Morse)
uniform vec2 jaw_hinge = vec2(0.07, -0.056);  // the moving part (FX blue) turns about the X axis through (y, z)
uniform float jaw_angle = 0.0;  // radians at full grind
uniform float jaw_every = 5.0;  // seconds between grinds
uniform vec3 slide = vec3(0.0);  // instead of turning: the moving part slides out by this much (a tongue flick)
uniform float blink_every = 0.0;  // glow group R blinks shut, one side then the other (0 = never)
instance uniform float moving = 0.0;  // this wearer: 0 standing still .. 1 running (game/rigged_body.gd)
uniform float move_pulse = 0.0;  // the pulse quickens to pulse_hz + this while moving (Iron Reaper)
uniform vec2 stillness = vec2(1.0);  // glow x this when still / moving (Ashen King: embers brighter standing still)
uniform float heal_every = 0.0;  // glow group G = cracks that open and heal, along their length, every n seconds
uniform vec3 spin_at = vec3(0.0);  // the moving part turns round spin_axis through spin_at, spin_hz turns a second
uniform vec3 spin_axis = vec3(0.0, 0.0, 1.0);  // (Blood Eclipse: its forehead disc, the eclipse travelling round)
uniform float spin_hz = 0.0;
uniform vec4 mane = vec4(0.0);  // xyz = middle of a sunburst behind the head, w = how far its plates swell out and back (breathing)
uniform float glow_from_col = 0.0;  // 1 = glow group G takes each spot's own hue from the colour map (Gilded Tyrant's emeralds + sapphires; R keeps glow_color)
varying float side;

void vertex() {
	side = VERTEX.x;
	float jaw = textureLod(fx_tex, UV, 0.0).b;
	if (length(slide) > 0.0 && jaw > 0.5) {
		float ph = mod(TIME, jaw_every);
		float out_ = smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.35, 0.5, ph)) + smoothstep(0.55, 0.62, ph) * (1.0 - smoothstep(0.8, 0.95, ph));
		VERTEX += slide * (out_ - 1.0);  // drawn back into the mouth, out on the flick
	}
	if (jaw_angle > 0.0 && jaw > 0.5) {
		float ph = mod(TIME, jaw_every);
		float open = smoothstep(0.0, 0.25, ph) * (1.0 - smoothstep(0.9, 1.4, ph));
		float a = jaw_angle * open * (0.75 + 0.25 * sin(TIME * 47.0));
		vec2 q = VERTEX.yz - jaw_hinge;
		float c = cos(a), s = sin(a);
		VERTEX.yz = jaw_hinge + vec2(q.x * c + q.y * s, -q.x * s + q.y * c);
		NORMAL.yz = vec2(NORMAL.y * c + NORMAL.z * s, -NORMAL.y * s + NORMAL.z * c);
		VERTEX.x += sin(TIME * 31.0) * 0.0015 * open;
	}
	if (spin_hz > 0.0 && jaw > 0.5) {
		vec3 k = normalize(spin_axis);
		float a = TIME * 6.2832 * spin_hz;
		float c = cos(a), s = sin(a);
		vec3 q = VERTEX - spin_at;
		VERTEX = spin_at + q * c + cross(k, q) * s + k * dot(k, q) * (1.0 - c);
		NORMAL = NORMAL * c + cross(k, NORMAL) * s + k * dot(k, NORMAL) * (1.0 - c);
		TANGENT = TANGENT * c + cross(k, TANGENT) * s + k * dot(k, TANGENT) * (1.0 - c);
		BINORMAL = BINORMAL * c + cross(k, BINORMAL) * s + k * dot(k, BINORMAL) * (1.0 - c);
	}
	if (mane.w > 0.0) {  // the plates behind the head swell out and back
		vec2 m = VERTEX.xy - mane.xy;
		float plate = smoothstep(0.09, 0.12, length(m)) * smoothstep(0.0, 0.02, VERTEX.z - mane.z);
		VERTEX.xy += normalize(m) * sin(TIME * 1.6) * mane.w * plate;
	}
	vec3 rel = VERTEX - head_mid;
	float r = length(rel.xz);
	float brim = smoothstep(0.15, 0.21, r) * smoothstep(0.04, 0.07, rel.y);
	VERTEX.y += sin(TIME * 1.3 + VERTEX.x * 9.0) * sway * brim;
	float shell = (1.0 - smoothstep(0.1, 0.15, r)) * (1.0 - smoothstep(0.02, 0.08, rel.y));
	VERTEX += NORMAL * sin(TIME * 1.7) * breathe * shell;
}

void fragment() {
	ALBEDO = texture(col_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	vec3 fx = texture(fx_tex, UV).rgb;
	float lens = max(fx.r, fx.g);
	ROUGHNESS = mix(orm.g, 0.06, lens);
	METALLIC = orm.b * (1.0 - lens);
	AO = orm.r;
	SPECULAR = mix(0.5, 0.9, lens);
	NORMAL_MAP = texture(nrm_tex, UV).rgb;
	int i = int(mod(TIME / morse_unit, float(max(morse_len, 1))));
	float on = texelFetch(morse_tex, ivec2(i, 0), 0).r;
	if (pulse_hz > 0.0) {
		float slow = 0.72 + 0.28 * sin(TIME * 6.2832 * pulse_hz);
		float fast = 0.8 + 0.2 * sin(TIME * 6.2832 * (pulse_hz + move_pulse));
		on = move_pulse > 0.0 ? mix(slow, fast, moving) : slow;
	}
	float shut = 0.0;
	if (blink_every > 0.0) {
		float ph = mod(TIME + (side > 0.0 ? 0.0 : blink_every * 0.37), blink_every);
		shut = smoothstep(0.0, 0.05, ph) * (1.0 - smoothstep(0.14, 0.22, ph)) * fx.r;
		ALBEDO = mix(ALBEDO, vec3(0.01, 0.02, 0.01), shut);
	}
	float g_lit = mix(0.1, 0.75, on);
	if (heal_every > 0.0) {
		float ph = sin(TIME * 6.2832 / heal_every + UV.x * 17.0 + UV.y * 11.0);
		g_lit = smoothstep(-0.25, 0.65, ph) * mix(0.5, 1.0, on);
	}
	vec3 base_col = texture(col_tex, UV).rgb;
	vec3 hue = base_col / max(max(base_col.r, max(base_col.g, base_col.b)), 0.001);
	vec3 lit = glow_color * fx.r * mix(0.22, 1.0, on) * (1.0 - shut) + mix(glow_color, hue, glow_from_col) * fx.g * g_lit;
	EMISSION = lit * glow_strength * mix(stillness.x, stillness.y, moving);
}
"""

# Mist puffs: billboards that fade in and out over their life (CPUParticles3D's colour ramp drew them black on the
# Compatibility renderer, so the fade is done here from the particle's age).
const PUFF_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D dot_tex : filter_linear;
uniform vec4 tint : source_color = vec4(0.4, 1.0, 0.3, 0.3);
varying float fade;

void vertex() {
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float life = INSTANCE_CUSTOM.y;
	fade = smoothstep(0.0, 0.18, life) * (1.0 - smoothstep(0.55, 1.0, life));
}

void fragment() {
	ALBEDO = tint.rgb * 1.3;
	ALPHA = texture(dot_tex, UV).a * tint.a * fade;
}
"""

static var tier := 3  # graphics tier: 0 potato .. 4 ultimate (data/masks.json "detail")
static var _db: MaskDb
static var _shader: Shader
static var _meshes := {}  # "id|hi" -> Mesh
static var _materials := {}  # "id|full" -> ShaderMaterial
static var _soft_dot: Texture2D
static var _puff_shader: Shader


static func db() -> MaskDb:
	if _db == null:
		_db = MaskDb.new(DataStore.load_json("res://data/masks.json"))
	return _db


# True when wearing `id` leaves the character's eyes, brows, hair and head wear off (a full mask / helmet).
static func covers_head(id: String) -> bool:
	return id != "" and db().has(id) and String(db().mask(id).get("covers", "")) == "full"


# Height over the head anchor above which the character's own head and neck are left off under mask `id` (data
# "neck_cut", metres): what shows of the neck stays under the mask's collar.
static func neck_cut(id: String) -> float:
	return float(db().mask(id).get("neck_cut", 0.0))


# The mask node for a head anchor, or null (unknown id / model not made yet).
static func build(id: String) -> Node3D:
	if not db().has(id):
		return null
	var detail: Dictionary = db().detail(tier)
	var mesh := _mesh(id, String(detail.get("mesh", "hi")))
	if mesh == null:
		return null
	var root := Node3D.new()
	root.name = "Mask"
	var mi := MeshInstance3D.new()
	mi.name = "MaskMesh"
	mi.mesh = mesh
	mi.material_override = _material(id, String(detail.get("tex", "full")))
	root.add_child(mi)
	var fx: Dictionary = db().mask(id).get("fx", {})
	var share := float(detail.get("fx", 1.0))
	if fx.get("mist") is Dictionary and share > 0.0:
		root.add_child(_mist(fx["mist"], share))
	if fx.get("ash") is Dictionary and share > 0.0:
		root.add_child(_mist(fx["ash"], share))
	if fx.get("haze") is Dictionary and share > 0.0:
		root.add_child(_mist(fx["haze"], share))
	if fx.get("frost") is Dictionary and share > 0.0:  # puffs only while the wearer moves or turns fast (game/rigged_body.gd)
		var frost := _mist(fx["frost"], share)
		frost.name = "MoveFx"
		frost.emitting = false
		root.add_child(frost)
	if fx.get("flies") is Dictionary and share > 0.0:
		root.add_child(_flies(fx["flies"], share))
	if fx.get("sparks") is Dictionary and share > 0.0:
		for at: Variant in (fx["sparks"] as Dictionary).get("at", []):
			root.add_child(_sparks(fx["sparks"], _vec(at, Vector3.ZERO), share))
	return root


static func _mesh(id: String, level: String) -> Mesh:
	var key := id + "|" + level
	if not _meshes.has(key):
		var path := ROOT + id + "/" + level + ".obj"
		if not ResourceLoader.exists(path):
			path = ROOT + id + "/hi.obj"
		_meshes[key] = load(path) as Mesh if ResourceLoader.exists(path) else null
	return _meshes[key]


static func _tex(id: String, name: String, size: String) -> Texture2D:
	var path := ROOT + id + "/" + name + ("_half" if size == "half" else "") + ".png"
	if not ResourceLoader.exists(path):
		path = ROOT + id + "/" + name + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _material(id: String, size: String) -> ShaderMaterial:
	var key := id + "|" + size
	if _materials.has(key):
		return _materials[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("col_tex", _tex(id, "col", size))
	m.set_shader_parameter("nrm_tex", _tex(id, "nrm", size))
	m.set_shader_parameter("orm_tex", _tex(id, "orm", size))
	m.set_shader_parameter("fx_tex", _tex(id, "fx", size))
	var fx: Dictionary = db().mask(id).get("fx", {})
	var units: Array = db().morse_loop(id)
	if units.is_empty():
		units = [false]
	var img := Image.create(units.size(), 1, false, Image.FORMAT_L8)
	for i in units.size():
		img.set_pixel(i, 0, Color.WHITE if bool(units[i]) else Color.BLACK)
	m.set_shader_parameter("morse_tex", ImageTexture.create_from_image(img))
	m.set_shader_parameter("morse_len", units.size())
	m.set_shader_parameter("morse_unit", float(fx.get("morse_unit", 0.16)))
	var g: Array = fx.get("glow", [0.35, 1.0, 0.3])
	m.set_shader_parameter("glow_color", Color(float(g[0]), float(g[1]), float(g[2])))
	m.set_shader_parameter("glow_strength", float(fx.get("glow_strength", 0.0)))
	m.set_shader_parameter("sway", float(fx.get("sway", 0.0)))
	m.set_shader_parameter("breathe", float(fx.get("breathe", 0.0)))
	m.set_shader_parameter("pulse_hz", float(fx.get("pulse_hz", 0.0)))
	m.set_shader_parameter("blink_every", float(fx.get("blink_every", 0.0)))
	m.set_shader_parameter("move_pulse", float(fx.get("move_pulse", 0.0)))
	var still: Array = fx.get("stillness", [1.0, 1.0])
	m.set_shader_parameter("stillness", Vector2(float(still[0]), float(still[1])))
	m.set_shader_parameter("heal_every", float(fx.get("heal_every", 0.0)))
	var mn: Dictionary = fx.get("mane", {})
	if not mn.is_empty():
		var mc := _vec(mn.get("at"), Vector3.ZERO)
		m.set_shader_parameter("mane", Vector4(mc.x, mc.y, mc.z, float(mn.get("amp", 0.004))))
	m.set_shader_parameter("glow_from_col", 1.0 if bool(fx.get("glow_from_col", false)) else 0.0)
	var spin: Dictionary = fx.get("spin", {})
	if not spin.is_empty():
		m.set_shader_parameter("spin_at", _vec(spin.get("at"), Vector3.ZERO))
		m.set_shader_parameter("spin_axis", _vec(spin.get("axis"), Vector3(0, 0, 1)))
		m.set_shader_parameter("spin_hz", float(spin.get("hz", 0.05)))
	var flick: Dictionary = fx.get("flick", {})
	if not flick.is_empty():
		m.set_shader_parameter("slide", _vec(flick.get("by"), Vector3.ZERO))
		m.set_shader_parameter("jaw_every", float(flick.get("every", 4.0)))
	var jaw: Dictionary = fx.get("jaw", {})
	if not jaw.is_empty():
		var h: Array = jaw.get("hinge", [0.07, -0.056])
		m.set_shader_parameter("jaw_hinge", Vector2(float(h[0]), float(h[1])))
		m.set_shader_parameter("jaw_angle", deg_to_rad(float(jaw.get("angle", 4.0))))
		m.set_shader_parameter("jaw_every", float(jaw.get("every", 5.0)))
	_materials[key] = m
	return m


static func _dot() -> Texture2D:
	if _soft_dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_dot = t
	return _soft_dot


static func _vec(a: Variant, fallback: Vector3) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() >= 3 else fallback


# Soft glowing cloud puffs that roll out of the beak, sink and fade (world space, so they trail when the head moves).
static func _mist(cfg: Dictionary, share: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "MaskMist"
	p.position = _vec(cfg.get("at"), Vector3.ZERO)
	p.amount = maxi(roundi(float(cfg.get("amount", 20)) * share), 3)
	p.lifetime = float(cfg.get("life", 2.8))
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = float(cfg.get("radius", 0.025))
	p.direction = _vec(cfg.get("dir"), Vector3(0, -0.35, -1))  # (ash: up)
	p.spread = 40.0
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.1
	p.gravity = Vector3(0, float(cfg.get("rise", -0.035)), 0)
	p.damping_min = 0.02
	p.damping_max = 0.05
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = grow
	var c: Array = cfg.get("color", [0.4, 1.0, 0.3, 0.3])
	var quad := QuadMesh.new()
	var size := float(cfg.get("size", 0.08))
	quad.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	if _puff_shader == null:
		_puff_shader = Shader.new()
		_puff_shader.code = PUFF_CODE
	mat.shader = _puff_shader
	mat.set_shader_parameter("dot_tex", _dot())
	mat.set_shader_parameter("tint", Color(float(c[0]), float(c[1]), float(c[2]), float(c[3])))
	quad.material = mat
	p.mesh = quad
	return p


# Small dark flies that leave the beak, wander and drop away.
static func _flies(cfg: Dictionary, share: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "MaskFlies"
	p.position = _vec(cfg.get("at"), Vector3.ZERO)
	p.amount = maxi(roundi(float(cfg.get("amount", 10)) * share), 2)
	p.lifetime = 3.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.04
	p.direction = Vector3(0, 0.2, -1)
	p.spread = 120.0
	p.initial_velocity_min = 0.06
	p.initial_velocity_max = 0.2
	p.gravity = Vector3(0, -0.06, 0)
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.tangential_accel_min = -0.4
	p.tangential_accel_max = 0.4
	p.radial_accel_min = -0.05
	p.radial_accel_max = 0.02
	var body := SphereMesh.new()
	body.radius = 0.0035
	body.height = 0.006
	body.radial_segments = 6
	body.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.025)
	mat.roughness = 0.3
	body.material = mat
	p.mesh = body
	return p


# Sparks and metal shavings that drop from a point (Iron Reaper's jaw and eyes): tiny glowing streaks, a few dark flakes.
static func _sparks(cfg: Dictionary, at: Vector3, share: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()  # ("drip": radius = falling drops instead: venom)
	p.name = "MaskSparks"
	p.position = at
	p.amount = maxi(roundi(float(cfg.get("amount", 8)) * share), 2)
	p.lifetime = float(cfg.get("life", 0.9))
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = float(cfg.get("radius", 0.015)) if not cfg.has("drip") else 0.002
	p.direction = _vec(cfg.get("dir"), Vector3(0, -0.4, -1)) if not cfg.has("drip") else Vector3(0, -1, 0)  # (embers: up)
	p.spread = 55.0 if not cfg.has("drip") else 5.0
	p.initial_velocity_min = 0.08 if not cfg.has("drip") else 0.0
	p.initial_velocity_max = 0.35 if not cfg.has("drip") else 0.05
	p.gravity = Vector3(0, -float(cfg.get("gravity", 2.2)), 0)
	p.randomness = 0.6
	var c: Array = cfg.get("color", [1.0, 0.55, 0.12])
	var box := BoxMesh.new()
	box.size = Vector3(0.0025, 0.012, 0.0025)  # long along Y: particle_flag_align_y turns it along its flight
	var bit: PrimitiveMesh = box
	if cfg.has("drip"):  # (venom) round drops that stretch as they fall
		var drop := SphereMesh.new()
		drop.radius = float(cfg.get("drip", 0.004))
		drop.height = drop.radius * 3.0
		drop.radial_segments = 8
		drop.rings = 4
		bit = drop
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = float(cfg.get("glow", 3.0))
	bit.material = mat
	p.mesh = bit
	p.particle_flag_align_y = true
	return p
