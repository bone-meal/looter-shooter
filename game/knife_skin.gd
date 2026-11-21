# Purpose: the look of a skinned knife (polish1 D5b, diary/DESIGN_KNIVES.md): one spatial shader paints the knife's
# BLADE surface (game/knife_models.gd names it "blade"; guard and grip keep theirs) with its finish's family pattern,
# laid out along the blade itself (u = guard to tip, v = edge to spine; no UVs needed): case hardened oxide patches
# (Bluegem = mostly blue), fades along the blade (by the pattern how far the colours reach), Prism / Venom Melt marbled
# swirls in four phases + their single-colour gems, Tidewater sea-glass bands (Rogue Wave), Ember Crack glowing cracks
# (Heartfire), Aurora moving ribbons (Full Corona), Mossback moss with flowers (In Bloom), Candy Cane twisted stripes
# (Perfect Twist), Jackpot slot symbols (777). The pattern number moves the pattern; wear scratches it back to steel;
# the cutting edge always shows bright steel. Gold and pony finishes glow / move a little more.
# Dependencies: core/knife_skins.gd, core/data_store.gd.
extends RefCounted

const KnifeSkins = preload("res://core/knife_skins.gd")
const DataStore = preload("res://core/data_store.gd")

const SHEET_MM := Vector2(2560.0 / 9.0, 384.0 / 9.0)  # a finish sheet's size in millimetres (tools/make_knife_sheets.py: 9 px a mm)
const KINDS := ["case", "fade", "prism", "venom", "tide", "ember", "aurora", "moss", "candy", "jackpot"]

static var _rules: KnifeSkins
static var _shader: Shader
static var _cache := {}  # look key -> ShaderMaterial
static var _bounds := {}  # mesh rid -> [min, max] of its blade surface


static func rules() -> KnifeSkins:
	if _rules == null:
		var weights := {}
		var knives: Dictionary = DataStore.load_json("res://data/knives.json").get("knives", {})
		for id: String in knives:
			weights[id] = float((knives[id] as Dictionary).get("weight", 1.0))
		_rules = KnifeSkins.new(DataStore.load_json("res://data/knife_skins.json"), weights)
	return _rules


# Paints the blade of a knife model (from game/knife_models.gd build) with a skinned knife item; {} = plain again.
static func apply(model: Node, item: Dictionary) -> void:
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			if (mi.mesh as ArrayMesh).surface_get_name(i) != "blade":
				continue
			mi.set_surface_override_material(i, null if item.is_empty() else material(item, _blade_bounds(mi.mesh as ArrayMesh, i)))


static func _blade_bounds(mesh: ArrayMesh, surface: int) -> Array:
	var key := mesh.get_rid()
	if not _bounds.has(key):
		var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v in verts:
			lo = lo.min(v)
			hi = hi.max(v)
		_bounds[key] = [lo, hi]
	return _bounds[key]


static func material(item: Dictionary, bounds: Array) -> ShaderMaterial:
	var r := rules()
	var fin := r.finish(String(item.get("finish", "")))
	var fam := r.family(item)
	var look := r.pattern_look(item)
	var key := "%s|%d|%.2f|%s|%s" % [String(item.get("finish", "")), int(item.get("pattern", 0)), float(item.get("wear", 0.0)), str(bounds[0]), str(bounds[1])]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	mat.set_shader_parameter("kind", maxi(KINDS.find(String(fam.get("kind", "case"))), 0))
	var cols: Array = fin.get("colors", [])
	for i in mini(cols.size(), 4):
		mat.set_shader_parameter("c%d" % i, Color(String(cols[i])))
	var p := int(item.get("pattern", 0))
	mat.set_shader_parameter("seed", Vector2(float((p * 37) % 101) * 0.731, float((p * 61) % 89) * 0.517))
	mat.set_shader_parameter("variant", int(look["variant"]))
	mat.set_shader_parameter("phase", int(look["phase"]))
	mat.set_shader_parameter("reach", 0.55 + 0.45 * float((p * 7919 + 13) % 1000) / 1000.0)  # fades: how far the colours reach down the blade
	mat.set_shader_parameter("wear", float(item.get("wear", 0.0)))
	mat.set_shader_parameter("lively", {"gold": 0.6, "pony": 1.0}.get(String(fin.get("tier", "")), 0.25))
	mat.set_shader_parameter("bmin", bounds[0])
	mat.set_shader_parameter("bmax", bounds[1])
	var sheet := "res://assets/knives/skins/%s_col.jpg" % String(item.get("finish", ""))
	if String(look["name"]) != "":  # a phase / gem with a sheet of its own (prism_melt_bloodmoon, venom_melt_phase_2 ...)
		var slug := ""
		for ch in String(look["name"]).to_lower():
			slug += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
		var own := "res://assets/knives/skins/%s_%s_col.jpg" % [String(item.get("finish", "")), slug.strip_edges().trim_prefix("_").trim_suffix("_")]
		if ResourceLoader.exists(own):
			sheet = own
	if ResourceLoader.exists(sheet):  # a designed sheet: the pattern number picks the window of it on this blade (CS style)
		mat.set_shader_parameter("use_sheet", true)
		mat.set_shader_parameter("col_tex", load(sheet))
		mat.set_shader_parameter("fx_tex", load(sheet.replace("_col.jpg", "_fx.png")))
		var size_mm: Vector3 = ((bounds[1] as Vector3) - (bounds[0] as Vector3)) * 1000.0
		var w := clampf(size_mm.x / SHEET_MM.x, 0.05, 1.0)
		var h := clampf(size_mm.y / SHEET_MM.y, 0.05, 1.0)
		var fx_ := fposmod(float(p) * 0.6180339, 1.0) * (1.0 - w)
		if int(look["variant"]) > 0:
			fx_ = 0.0  # a chase pattern: its sheet's special drawing starts at the left end (the guard)
		var fy_ := fposmod(float(p) * 0.3819660, 1.0) * (1.0 - h)
		mat.set_shader_parameter("window", Vector4(fx_, fy_, w, h))
	_cache[key] = mat
	return mat


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	return _shader


const CODE := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int kind = 0;
uniform vec4 c0 : source_color = vec4(0.2, 0.4, 0.9, 1.0);
uniform vec4 c1 : source_color = vec4(0.8, 0.6, 0.3, 1.0);
uniform vec4 c2 : source_color = vec4(0.5, 0.3, 0.7, 1.0);
uniform vec4 c3 : source_color = vec4(0.6, 0.62, 0.66, 1.0);
uniform vec2 seed = vec2(0.0);
uniform int variant = 0;
uniform int phase = 0;
uniform float reach = 0.8;
uniform float wear = 0.1;
uniform float lively = 0.25;
uniform vec3 bmin = vec3(0.0);
uniform vec3 bmax = vec3(0.2, 0.03, 0.01);
uniform bool use_sheet = false;
uniform sampler2D col_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D fx_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 window = vec4(0.0, 0.0, 0.6, 1.0);  // where on its sheet this blade lies: x, y, width, height

varying vec3 lp;
varying vec3 ln;

float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
vec2 h22(vec2 p) { float n = h21(p); return vec2(n, h21(p + n)); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + 17.1; a *= 0.5; } return s; }
float ridged(vec2 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0)); p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + 5.3; a *= 0.5; } return s; }
// F2 - F1 of a jittered grid: thin where two cells meet
float cells(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); float d1 = 8.0; float d2 = 8.0;
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 o = vec2(float(x), float(y)); vec2 r = o + h22(i + o) * 0.9 - f; float d = dot(r, r);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return sqrt(d2) - sqrt(d1);
}
vec3 hue(float h) { return clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0); }
float heart(vec2 p) { p.y -= 0.25; p.x = abs(p.x); return length(p - vec2(0.25, 0.25) * 0.7) < 0.28 ? -1.0 : (p.y > -0.6 + p.x * 1.1 && p.y < 0.2 ? -1.0 : 1.0); }
float sd_seven(vec2 p) {
	float top = max(abs(p.y - 0.33) - 0.09, abs(p.x) - 0.3);
	vec2 q = p - vec2(0.04, -0.08); float c = cos(0.42); float s = sin(0.42); q = vec2(c * q.x - s * q.y, s * q.x + c * q.y);
	return min(top, max(abs(q.x) - 0.085, abs(q.y) - 0.4));
}
float sd_flower(vec2 p, float r) { float a = atan(p.y, p.x); return length(p) - r * (0.62 + 0.38 * cos(a * 5.0)); }
// a photo studio seen in polished steel: dark floor, bright horizon, two soft boxes overhead
vec3 studio(vec3 r) {
	float y = r.y;
	vec3 c = mix(vec3(0.05, 0.05, 0.06), vec3(0.42, 0.44, 0.48), smoothstep(-0.35, 0.05, y));
	c = mix(c, vec3(0.18, 0.2, 0.24), smoothstep(0.1, 0.8, y));
	c += vec3(1.0) * 1.6 * smoothstep(0.06, 0.0, abs(y - 0.03)) * 0.6;
	float box1 = smoothstep(0.25, 0.1, length(vec2(r.x - 0.45, y - 0.62) * vec2(1.0, 2.2)));
	float box2 = smoothstep(0.3, 0.12, length(vec2(r.x + 0.5, y - 0.45) * vec2(1.6, 1.0)));
	return c + vec3(1.0, 0.98, 0.95) * (box1 * 1.8 + box2 * 1.1);
}

void vertex() { lp = VERTEX; ln = NORMAL; }

void fragment() {
	vec3 span = max(bmax - bmin, vec3(0.0001));
	vec3 n3 = (lp - bmin) / span;
	float u = n3.x;  // guard (0) to tip (1)
	float v = n3.y;  // edge (0) to spine (1)
	float len = span.x;
	vec2 mm = vec2(lp.x, lp.y) * 1000.0;  // millimetres on the blade's flat
	vec2 bp = mm / 20.0 + seed;  // ~2 cm cells, moved by the pattern number
	float t = TIME;
	// the GRIND: the bevel down to the cutting edge is ground bright and brushed; the flat above it carries the finish
	float grind_line = 0.035;  // only a hairline of sharpened steel at the very edge: the finish covers the blade
	float bevel = 1.0 - smoothstep(grind_line - 0.015, grind_line + 0.005, v);
	float blur = clamp(fwidth(mm.y) / 0.5, 0.0, 1.0);  // fine detail fades out where a pixel covers more than it (no glitter at a distance)
	vec3 col = c3.rgb;
	float coat = 0.0;  // 0 = bare metal finish, 1 = painted / lacquered / glassy finish (less mirror)
	float rough = 0.2;
	float height = 0.0;  // relief, for the light to catch
	vec3 glow = vec3(0.0);
	float sheet_metal = 0.0;
	if (use_sheet) {  // a designed sheet (tools/make_knife_sheets.py): colour + coat, height / glow / metal / glow phase
		vec2 suv = window.xy + vec2(u, 1.0 - v) * window.zw;
		vec4 cs = texture(col_tex, suv);
		vec4 fs = texture(fx_tex, suv);
		col = cs.rgb;
		coat = fs.a;
		height = texture(fx_tex, suv, 1.0).r * mix(1.6, 0.5, fs.b);  // relief from a softer mip (no glitter), less on polished metal
		sheet_metal = fs.b;
		rough = mix(0.12, 0.35, fs.a * (1.0 - fs.b) * 0.6);
		float phase_g = fract(suv.x * 7.0 + fs.r * 0.6);  // where along the glow's pulse this point is
		float pulse = 0.65 + 0.35 * sin(t * (1.6 + lively * 2.0) - phase_g * 6.2832);
		glow = col * fs.g * (0.9 + lively * 0.8) * pulse;
	} else if (kind == 0) {  // CASE HARDENED: heat-coloured oxide on grey steel: blue pools, gold / bronze clouds, violet seams
		vec2 w = bp * 1.1; w += (vec2(fbm(w * 0.7 + 2.0), fbm(w * 0.7 + 9.0)) - 0.5) * 2.4;
		float n = fbm(w);
		float m = fbm(w * 1.8 + 31.0);
		float blue_lvl = (variant == 1) ? 0.3 : 0.55;
		if (variant == 2) blue_lvl = mix(0.55, 0.25, smoothstep(0.45, 0.9, v));
		float blue = smoothstep(blue_lvl, blue_lvl + 0.06, n);
		float gold = smoothstep(0.42, 0.5, m) * (1.0 - blue);
		float seam = (1.0 - smoothstep(0.0, 0.025, abs(n - blue_lvl))) * 0.8;
		vec3 steel = mix(vec3(0.42, 0.43, 0.45), vec3(0.62, 0.62, 0.6), fbm(bp * 6.0));
		col = steel;
		col = mix(col, mix(c1.rgb * 0.75, c1.rgb * 1.1, fbm(w * 4.0)), gold * 0.85);
		col = mix(col, mix(c0.rgb * 0.55, c0.rgb * 1.15, fbm(w * 3.0 + 4.0)), blue);
		col = mix(col, c2.rgb, seam);
		rough = 0.16;
	} else if (kind == 1) {  // FADE: candy colours poured from the tip, over polished steel
		float g = clamp((u * 0.85 + v * 0.25 - (1.0 - reach) * 0.9) / max(reach, 0.2), 0.0, 1.0);
		if (variant == 1) g = clamp(u * 0.95 + v * 0.2 + 0.05, 0.0, 1.0);
		vec3 a = mix(c3.rgb, c2.rgb, smoothstep(0.05, 0.4, g));
		a = mix(a, c1.rgb, smoothstep(0.35, 0.7, g));
		col = mix(a, c0.rgb, smoothstep(0.65, 1.0, g));
		float base = smoothstep(0.0, 0.15, g);
		col = mix(vec3(0.6, 0.6, 0.62), col, base);
		if (c3.g > 0.5 && c3.r < 0.6) {  // confetti: flakes of every colour in the coat
			vec2 fi = floor(mm / 2.6); float f = step(0.9, h21(fi + seed)) * (1.0 - blur);
			col = mix(col, hue(h21(fi + 3.0)) * 1.1, f * base);
			height += f * 0.3;
		}
		coat = 0.35 * base; rough = 0.1;
	} else if (kind == 2 || kind == 3) {  // PRISM / VENOM MELT: liquid colour marbled through black chrome, sparkling
		vec2 w = bp * 1.3;
		for (int i = 0; i < 3; i++) { w += (vec2(fbm(w * 0.8 + float(i) * 3.7), fbm(w * 0.8 + float(i) * 5.1 + 9.0)) - 0.5) * 1.6; }
		float n = fbm(w);
		float ink = smoothstep(0.38, 0.62, n);
		vec3 a = c0.rgb; vec3 b = c1.rgb; vec3 c = c2.rgb;
		if (phase == 2) { a = c1.rgb; b = c2.rgb; c = c0.rgb; }
		if (phase == 3) { a = c2.rgb; b = c3.rgb; c = c1.rgb; }
		if (phase == 4) { a = c3.rgb; b = c0.rgb; c = c2.rgb; }
		vec3 liquid = mix(a, b, smoothstep(0.2, 0.55, fract(n * 2.3 + w.x * 0.05)));
		liquid = mix(liquid, c, smoothstep(0.6, 0.85, fbm(w * 2.0 + 7.0)));
		if (kind == 2 && variant == 1) liquid = mix(vec3(0.08, 0.03, 0.18), vec3(0.45, 0.25, 0.7), n) + hue(n * 1.5 + 0.55) * 0.15;
		if (kind == 2 && variant == 2) liquid = mix(vec3(0.0, 0.08, 0.45), vec3(0.15, 0.45, 1.0), n);
		if (kind == 2 && variant == 3) liquid = mix(vec3(0.45, 0.0, 0.03), vec3(1.0, 0.1, 0.15), n);
		if (kind == 3 && variant == 1) liquid = mix(vec3(0.0, 0.35, 0.1), vec3(0.2, 1.0, 0.45), n);
		col = mix(vec3(0.02, 0.02, 0.03), liquid, 0.25 + 0.75 * ink);
		float speck = step(0.9, fbm(bp * 3.0 + 4.0)) * (1.0 - ink * 0.5);
		col = mix(col, vec3(0.01), speck);
		vec2 si = floor(mm / 0.9);
		float star = step(0.985, h21(si + seed)) * pow(0.5 + 0.5 * sin(t * 3.0 + h21(si) * 40.0 + dot(VIEW, NORMAL) * 30.0), 6.0);
		glow += liquid * star * 1.5;
		if (c3.r + c3.g + c3.b < 0.2) glow += liquid * ink * (0.45 + 0.25 * sin(t * 1.6 + n * 9.0));
		rough = 0.06;
	} else if (kind == 4) {  // TIDEWATER: frosted sea glass in bands over a sea-blue core, caustic light moving through
		float wave = v * 6.0 + sin(u * 7.0 + seed.x) * 0.6 + (fbm(bp * 0.6) - 0.5) * 1.8;
		if (variant == 1) wave = (v - 0.5 - 0.3 * sin(u * 4.5 + 0.6) * smoothstep(0.0, 0.6, u)) * 6.0 + (fbm(bp * 0.8) - 0.5);
		float f = fract(wave * 0.5);
		float edgeb = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.92, 1.0, f));
		col = mix(c3.rgb, c1.rgb, smoothstep(0.05, 0.5, f));
		col = mix(col, c0.rgb, smoothstep(0.5, 0.85, f));
		col = mix(col, c2.rgb, (1.0 - edgeb) * 0.8);  // white foam where bands meet
		float frost = fbm(mm / 0.6);
		col *= 0.85 + 0.25 * frost;
		float caustic = pow(1.0 - abs(sin(fbm(bp * 1.4 + vec2(t * 0.25, t * 0.15)) * 9.0)), 6.0);
		glow += c2.rgb * caustic * (0.12 + 0.25 * lively);
		height += (1.0 - edgeb) * 0.4 + frost * 0.15;
		coat = 0.7; rough = 0.32;
	} else if (kind == 5) {  // EMBER CRACK: charred black steel splitting into thin glowing seams
		vec2 w = bp * 1.6 + (vec2(fbm(bp * 1.2), fbm(bp * 1.2 + 5.0)) - 0.5) * 1.6;
		float e = cells(w);
		float fine = cells(w * 2.7 + 11.0);
		float crack = 1.0 - smoothstep(0.0, 0.035, e);
		crack = max(crack, (1.0 - smoothstep(0.0, 0.02, fine)) * smoothstep(0.45, 0.7, fbm(bp * 2.0 + 3.0)));
		if (variant == 1) { vec2 hp = vec2((u - 0.2) * len, (v - 0.55) * span.y) * 1000.0 / 9.0; float hd = heart(hp); crack = max(crack, step(hd, 0.0) * (0.6 + 0.4 * fbm(hp * 3.0))); }
		float halo = 1.0 - smoothstep(0.0, 0.22, e);
		float pulse = 0.7 + 0.3 * sin(t * (1.2 + lively * 2.5) - u * 10.0 + fbm(bp * 0.5) * 6.0);
		vec3 char_c = mix(c0.rgb * 0.6, c3.rgb * 0.7, ridged(bp * 2.5) * 0.7);
		vec3 hot = mix(c1.rgb, c2.rgb, crack);
		col = mix(char_c, c1.rgb * 0.5, halo * 0.6);
		col = mix(col, hot, crack);
		glow = hot * crack * (1.2 + lively) * pulse + c1.rgb * halo * 0.25 * pulse;
		height = -crack * 0.8 + ridged(bp * 2.5) * 0.35;
		coat = 0.6; rough = 0.55;
	} else if (kind == 6) {  // AURORA: curtains of light rising off a night-blue blade, stars behind
		float base_y = 0.25 + 0.18 * sin(u * 5.0 + seed.x + t * 0.25) + 0.08 * sin(u * 13.0 - t * 0.4);
		float rise = v - base_y;
		float rays = 0.45 + 0.55 * smoothstep(0.2, 0.9, fbm(vec2(u * len * 1000.0 / 3.5, rise * 2.0 - t * 0.2) + seed));
		rays *= 0.6 + 0.4 * sin(u * 4.0 + seed.y + t * 0.2);
		float curtain = smoothstep(-0.03, 0.02, rise) * (1.0 - smoothstep(0.0, 0.55, rise)) * rays;
		if (variant == 1) curtain = max(curtain, smoothstep(0.65, 1.0, u) * (1.0 - smoothstep(0.0, 0.6, abs(v - 0.55))) * rays);
		vec3 aur = mix(c1.rgb, c2.rgb, smoothstep(0.0, 0.45, rise));
		aur = mix(aur, c3.rgb, smoothstep(0.3, 0.6, rise) * 0.6);
		vec2 si = floor(mm / 0.8);
		float star = step(0.975, h21(si + seed)) * (0.5 + 0.5 * sin(t * 2.0 + h21(si) * 30.0));
		col = mix(c0.rgb * 0.7, c0.rgb * 1.3, v) + aur * curtain * 0.9 + vec3(star) * 0.7;
		glow = aur * curtain * (0.5 + lively * 0.7) + vec3(star) * 0.5;
		rough = 0.12; coat = 0.2;
	} else if (kind == 7) {  // MOSSBACK: soft living moss in tufts, with small five-petal flowers
		float m = fbm(bp * 1.6);
		float tuft = mix(fbm(mm / 1.8), 0.5, blur);
		col = mix(c1.rgb * 0.6, c0.rgb, smoothstep(0.3, 0.65, m));
		col = mix(col, c2.rgb, smoothstep(0.6, 0.85, fbm(bp * 3.0 + 5.0)) * 0.6);
		col *= 0.7 + 0.45 * tuft;
		vec2 g = mm / 5.5 + seed; vec2 gi = floor(g); vec2 gf = fract(g) - 0.5 - (h22(gi) - 0.5) * 0.4;
		float share = (variant == 1) ? 0.6 : 0.16;
		float on = step(1.0 - share, h21(gi + 3.0));
		float petal = 1.0 - smoothstep(0.0, 0.04, sd_flower(gf, 0.26));
		float centre = 1.0 - smoothstep(0.06, 0.09, length(gf));
		col = mix(col, c3.rgb * (0.85 + 0.3 * h21(gi)), petal * on);
		col = mix(col, vec3(1.0, 0.85, 0.25), centre * on);
		height = tuft * 0.6 + m * 0.4 + petal * on * 0.3;
		coat = 1.0; rough = 0.85;
	} else if (kind == 8) {  // CANDY CANE: lacquered twisted stripes, rounded where they meet
		float tw = (variant == 1) ? 0.9 : 0.6 + 0.15 * sin(u * 3.0 + seed.y);
		float s = fract(mm.x / 13.0 + mm.y / 13.0 * tw + seed.x * 0.1);
		float aa = 0.03 + blur * 0.2;
		float red = smoothstep(0.02, 0.02 + aa, s) * (1.0 - smoothstep(0.48 - aa, 0.48, s));
		float green = smoothstep(0.6, 0.63, s) * (1.0 - smoothstep(0.7, 0.73, s));
		col = mix(c1.rgb, c0.rgb, red);
		col = mix(col, c2.rgb, green);
		height = sin(s * 6.2832) * 0.3;
		coat = 1.0; rough = 0.08;
		if (c3.r > 0.9 && c3.b < 0.5) {  // CHRISTMAS BELLS: little gold bells hung along the blade, twinkling
			vec2 bg = mm / 12.0 + seed * 0.2; vec2 bi = floor(bg); vec2 bf = fract(bg) - vec2(0.5, 0.45);
			float on = step(0.35, h21(bi + 7.0));
			float body = (1.0 - smoothstep(0.2, 0.24, length(bf * vec2(1.0, 0.8) - vec2(0.0, 0.03)))) * step(-0.17, bf.y);
			float lip = (1.0 - smoothstep(0.02, 0.04, abs(bf.y + 0.15))) * step(abs(bf.x), 0.28);
			float clap = 1.0 - smoothstep(0.04, 0.06, length(bf - vec2(0.0, -0.23)));
			float bell = max(max(body, lip), clap) * on;
			col = mix(col, c3.rgb * (0.7 + 0.6 * (0.6 - bf.y)), bell);
			height += bell * 0.6;
			glow += c3.rgb * bell * pow(0.5 + 0.5 * sin(t * 4.0 + h21(bi) * 20.0), 8.0) * 1.2;
		}
	} else {  // JACKPOT: an engraved gold reel plate: three columns of symbols in lacquer
		vec2 g = vec2(u * len * 1000.0 / 17.0, mm.y / 15.0) + vec2(0.0, seed.y);
		vec2 gi = floor(g); vec2 gf = fract(g) - 0.5;
		float which = h21(gi + floor(seed.x));
		if (variant == 1 && abs(gi.y - floor(0.5 * span.y * 1000.0 / 15.0 + seed.y)) < 0.5) which = 0.1;
		float d = 1.0;
		vec3 sc = c1.rgb;
		if (which < 0.25) { d = sd_seven(gf * 1.25); sc = c1.rgb; }
		else if (which < 0.5) { d = min(length(gf - vec2(-0.13, -0.1)) - 0.14, length(gf - vec2(0.13, -0.14)) - 0.14); d = min(d, max(abs(gf.x + gf.y * 0.3) - 0.02, abs(gf.y - 0.12) - 0.16)); sc = c1.rgb * 0.95; }
		else if (which < 0.75) { d = max(abs(gf.y) - 0.1, abs(gf.x) - 0.3); sc = c3.rgb; }
		else { d = sd_flower(gf, 0.26); sc = c2.rgb; }
		float sym = 1.0 - smoothstep(0.0, 0.03, d);
		float rim = (1.0 - smoothstep(0.0, 0.025, abs(d))) ;
		float frame = (1.0 - smoothstep(0.0, 0.035, 0.5 - abs(gf.x))) * 0.8 * (1.0 - blur);  // only the reel columns are engraved
		vec3 gold_c = c0.rgb * (0.75 + 0.3 * fbm(mm / 1.5));
		col = mix(gold_c, sc, sym);
		col = mix(col, gold_c * 0.5, rim * 0.6);
		col = mix(col, gold_c * 0.45, frame);
		height = -frame * 0.6 + sym * 0.35 - rim * 0.3;
		coat = sym * 0.8; rough = mix(0.18, 0.3, sym);
		glow = sc * sym * 0.12 * lively * (0.5 + 0.5 * sin(t * 3.0 + gi.x * 2.0 + gi.y));
	}
	// wear: fine scratches along the blade, then rubbed patches back to steel (the flat's high spots first)
	float scratch = smoothstep(1.0 - wear * 0.4, 1.02 - wear * 0.4, vnoise(vec2(mm.x / 9.0, mm.y / 0.35) + seed * 7.0)) * step(0.45, vnoise(mm / 4.0 + seed)) * (1.0 - blur);
	float rub = smoothstep(0.78 - wear * 0.5, 0.9, fbm(bp * 0.9 + 31.0)) * wear;
	float bare = max(scratch * 0.8, rub);
	bare = max(bare, bevel * 0.85);  // the sharpened edge shows bright steel
	float brushed = mix(vnoise(vec2(mm.x / 12.0, mm.y / 0.3)), 0.5, blur);  // lengthwise grinding marks
	vec3 steel = vec3(0.72, 0.73, 0.75) * (0.88 + 0.18 * brushed);
	col = mix(col, steel, bare);
	coat *= 1.0 - bare;
	rough = mix(rough, 0.22 + brushed * 0.08, bare);
	glow *= 1.0 - bare;
	height += bevel * 0.0 + brushed * 0.05 * bare;
	// relief: tilt the normal by the slope of the height
	vec3 dpx = dFdx(VERTEX); vec3 dpy = dFdy(VERTEX);
	float dhx = dFdx(height); float dhy = dFdy(height);
	vec3 r1 = cross(dpy, NORMAL); vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	vec3 nrm = normalize(abs(det) * NORMAL - grad * 0.0025);
	NORMAL = nrm;
	// polished metal shows a studio in it (painted in, so it reads without reflection probes, low end included)
	vec3 rv = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, nrm), 0.0)).xyz;
	float fres = pow(1.0 - clamp(dot(nrm, VIEW), 0.0, 1.0), 4.0);
	vec3 env = studio(normalize(rv));
	float mirror = (1.0 - coat) * (1.0 - rough * 1.6);
	if (use_sheet) mirror = max(mirror, sheet_metal * (1.0 - coat));
	vec3 metal_col = col * (0.45 + 0.75 * env);
	if (kind == 0) metal_col += hue(fres * 1.5 + dot(rv, vec3(0.3, 0.6, 0.1))) * 0.12 * (1.0 - bare);  // oxide shimmer
	vec3 lacquer = col + env * (0.04 + 0.5 * fres) * coat * (1.0 - rough);
	ALBEDO = mix(lacquer, metal_col, clamp(mirror, 0.0, 1.0));
	METALLIC = 0.35 * (1.0 - coat);
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.5 + 0.3 * coat;
	EMISSION = glow;
}
"""
