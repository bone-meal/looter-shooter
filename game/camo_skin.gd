# Purpose: gun camos (polish1 D5a, DECISIONS_SKINS.md): one shader draws every camo of data/camos.json from the gun
# model's own 3D shape (model space, no UVs), so every body, part and attachment takes it with no seams and no
# per-gun work. Simple camos are 2D patterns projected on the face's main axis (woodland blobs, digital pixels,
# multicam, flecktarn dots, tiger stripes, hexes, splinter, brushstroke, chocolate chip, DPM ...); graphic ones (skulls,
# neon kanji, polka, zebra, neon hex, cracked earth, circuit) and the LEGENDARY / PONY ones are live (silver sweep, gold,
# diamond sparkles, phantom smoke, galaxy; neon oni, living coral, glitch, void serpent, carnival) and REACT to the
# player through `react()` (aiming, speed, shooting, reloading, kills, ammo, inspect). Wear scratches the paint to the
# metal; the pattern number shifts the pattern; the CHALLENGE version adds its accent / stronger effects.
# Dependencies: none (data passed in). `apply(model, camo, look)` / `clear(model)`; props (chase gun gimmicks), lenses,
# glows, maker bands and the W kills plate keep their own look.
extends RefCounted

const KINDS := ["blobs", "digital", "multicam", "fleck", "tiger", "hex", "spray", "solid", "splinter", "brush", "chip",
	"nightdots", "dpm", "skulls", "kanji", "polka", "zebra", "hexneon", "cracked", "circuit", "silver", "gold", "diamond",
	"phantom", "galaxy", "oni", "coral", "glitch", "serpent", "carnival"]
const SKIP := ["Lens", "Glow", "WKills", "Band", "Prop", "Unique", "Glass"]  # node name parts that keep their own material
const BARE := ["lens", "glow", "maker", "rubber", "warhead", "glass"]  # surfaces that stay as they are (barrels, bolts, glass, maker bands)

const CODE := """
shader_type spatial;
render_mode cull_back;
uniform int kind = 0;
uniform vec4 c0 : source_color = vec4(0.3, 0.35, 0.2, 1.0);
uniform vec4 c1 : source_color = vec4(0.4, 0.45, 0.25, 1.0);
uniform vec4 c2 : source_color = vec4(0.15, 0.12, 0.08, 1.0);
uniform vec4 c3 : source_color = vec4(0.5, 0.48, 0.35, 1.0);
uniform vec4 accent : source_color = vec4(0.6, 0.8, 0.3, 1.0);
uniform float challenge = 0.0;
uniform float wear = 0.1;
uniform float seed = 1.0;
uniform float size = 1.0;
uniform float aim = 0.0;
uniform float speed = 0.0;
uniform float shoot = 0.0;
uniform float reload = 0.0;
uniform float kill = 0.0;
uniform float ammo = 1.0;
uniform float inspect = 0.0;
uniform float body = 0.0;  // 1 on the gun's main body mesh: faces / the serpent are laid out on it
uniform vec3 mid = vec3(0.0);
uniform vec3 ext = vec3(0.1, 0.1, 0.5);
// (polish1 item 145) where this mesh sits in the WHOLE gun (set per mesh by apply()): rows of the mesh -> gun transform,
// the gun's middle and half size, gon = 1 when set. The serpent's board and the galaxy's spiral span every part.
instance uniform vec4 gx = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 gy = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 gz = vec4(0.0, 0.0, 1.0, 0.0);
instance uniform vec3 gmid = vec3(0.0);
instance uniform vec3 gext = vec3(0.1, 0.1, 0.5);
instance uniform float gon = 0.0;
varying vec3 lp;
varying vec3 ln;
varying vec3 np;
varying vec3 gp;  // gun space, in units of the gun's half height, from its middle
varying vec3 gnn;  // the normal in gun space
varying vec3 vdir;  // from the camera to this point, in this mesh's own space (parallax: a window into depth)

float h1(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 h22(vec2 p) { return vec2(h2(p), h2(p + 19.19)); }
float vn(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h1(i), h1(i + vec3(1,0,0)), f.x), mix(h1(i + vec3(0,1,0)), h1(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h1(i + vec3(0,0,1)), h1(i + vec3(1,0,1)), f.x), mix(h1(i + vec3(0,1,1)), h1(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { return vn(p) * 0.5 + vn(p * 2.07 + 7.1) * 0.28 + vn(p * 4.13 + 3.3) * 0.14 + vn(p * 8.3 + 1.7) * 0.08; }
// fbm stretched to roughly 0..1 with an even spread (plain fbm crowds round 0.5)
float field(vec3 p) { return clamp((fbm(p) - 0.5) * 2.6 + 0.5, 0.0, 1.0); }
vec3 warp(vec3 p, float k) { return p + (vec3(fbm(p), fbm(p + 5.2), fbm(p + 9.7)) - 0.5) * k; }
float ridge(vec3 p) { float r = 1.0 - abs(vn(p) * 2.0 - 1.0); float r2 = 1.0 - abs(vn(p * 2.1 + 3.0) * 2.0 - 1.0); return r * 0.65 + r2 * r * 0.35; }
float aa(float t, float x) { float w = max(fwidth(x), 0.0008); return smoothstep(t - w, t + w, x); }
vec3 vor(vec2 p) {  // x = nearest distance, y = edge distance, z = nearest cell's random
	vec2 i = floor(p); vec2 f = fract(p); float d1 = 8.0; float d2 = 8.0; float id = 0.0;
	for (int y = -1; y <= 1; y++) { for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y)); vec2 o = h22(i + g);
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; id = h2(i + g + 3.7); } else if (d < d2) { d2 = d; } } }
	return vec3(d1, d2 - d1, id);
}
vec4 hexc(vec2 p) {
	vec2 r = vec2(1.0, 1.732); vec2 hh = r * 0.5;
	vec2 a = mod(p, r) - hh; vec2 b = mod(p - hh, r) - hh;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	return vec4(g, p - g);
}
float hexedge(vec2 g) { vec2 q = abs(g); return 0.5 - max(dot(q, normalize(vec2(1.0, 1.732))), q.x); }
vec3 hsv(float h, float s, float v) { vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0); return v * mix(vec3(1.0), k, s); }
// a painted studio around the gun for its reflections (the low-end renderer has no reflection probes)
vec3 studio(vec3 r) {
	float up = r.y;
	vec3 col = mix(vec3(0.06, 0.06, 0.07), vec3(0.32, 0.33, 0.36), smoothstep(-0.4, 0.05, up));
	col = mix(col, vec3(0.75, 0.8, 0.88), smoothstep(0.05, 0.55, up));
	col += vec3(1.6) * smoothstep(0.86, 0.97, dot(normalize(r), normalize(vec3(-0.5, 0.65, 0.55))));  // a softbox
	col += vec3(0.9) * smoothstep(0.93, 0.99, dot(normalize(r), normalize(vec3(0.7, 0.2, 0.6))));
	col += vec3(0.5) * smoothstep(0.02, 0.0, abs(up - 0.02));  // the horizon line
	return col;
}
float skull(vec2 q) {
	float head = smoothstep(0.31, 0.29, length(q * vec2(1.0, 1.12) - vec2(0.0, 0.06)));
	float jaw = smoothstep(0.02, 0.0, max(abs(q.x) - 0.16, abs(q.y + 0.24) - 0.09));
	float eyes = smoothstep(0.085, 0.07, length(vec2(abs(q.x) - 0.12, q.y - 0.03)));
	float nose = smoothstep(0.01, 0.0, abs(q.x) * 1.6 + (q.y + 0.07) * 1.0 - 0.06) * step(-0.12, q.y);
	float teeth = step(abs(q.y + 0.2), 0.05) * step(0.75, fract(q.x * 16.0)) * step(abs(q.x), 0.15);
	return clamp(max(head, jaw) - eyes - nose - teeth, 0.0, 1.0);
}
float stroke(vec2 q, vec2 a, vec2 b, float w) {
	vec2 pa = q - a; vec2 ba = b - a; float hh = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * hh) - w * (1.0 - hh * 0.5);
}
float glyph(vec2 q, float r) {  // a made-up brush glyph: 3-5 tapered strokes
	float d = 9.0;
	for (int k = 0; k < 5; k++) {
		float rk = h2(vec2(r * 17.0, float(k)));
		if (k > 2 && rk < 0.4) { continue; }
		vec2 a = (h22(vec2(r, float(k) * 3.1)) - 0.5) * 0.7;
		vec2 b = a + (rk < 0.5 ? vec2(0.45 * sign(a.x + 0.01) * -1.0, 0.05) : vec2(0.05, -0.45 * sign(a.y + 0.01)));
		d = min(d, stroke(q, a, b, 0.055));
	}
	return d;
}
float face(vec2 q, float blink, float grin) {  // an oni / carnival face: horns, brows, eyes, fanged grin
	float d = 1.0;
	float outline = abs(length(q * vec2(1.0, 0.82)) - 0.42);
	d = min(d, outline - 0.012);
	vec2 e = vec2(abs(q.x) - 0.16, q.y - 0.08);
	d = min(d, length(e * vec2(1.0, 1.0 / max(blink, 0.08))) - 0.065);
	d = min(d, stroke(vec2(abs(q.x), q.y), vec2(0.07, 0.2), vec2(0.27, 0.15), 0.025));  // angry brows
	d = min(d, stroke(vec2(abs(q.x), q.y), vec2(0.25, 0.3), vec2(0.36, 0.62), 0.05));  // horns
	float m = abs(q.y + 0.18 + (0.09 - q.x * q.x * 1.8) * grin) - 0.02;
	d = min(d, max(m, abs(q.x) - 0.25));
	d = min(d, stroke(vec2(abs(q.x), q.y), vec2(0.12, -0.15 - 0.09 * grin), vec2(0.13, -0.27 - 0.04 * grin), 0.03));  // fangs
	return d;
}

// (polish1 item 145) the void serpent's board: a closed snake-game tour over a 12 x 3 grid of cells on the gun's side
// (row 0 left to right, a comb back through rows 1-2, down column 0), and a cell's spot in gun space (u along, v up)
vec2 tour_cell(float idx) {
	float w = 12.0;
	float n = mod(idx, 3.0 * w);
	if (n < w) { return vec2(n, 0.0); }
	n -= w;
	if (n < 2.0 * (w - 1.0)) {
		float c = floor(n * 0.5); float within = mod(n, 2.0);
		return vec2(w - 1.0 - c, mod(c, 2.0) < 0.5 ? 1.0 + within : 2.0 - within);
	}
	n -= 2.0 * (w - 1.0);
	return vec2(0.0, 2.0 - n);
}
vec2 board(vec2 cell, float ulen) { return vec2(-0.86 * ulen + cell.x * (1.72 * ulen / 11.0), 0.44 + cell.y * 0.15); }
vec2 tour_at(float f, float ulen) {
	float i = floor(f);
	return mix(board(tour_cell(i), ulen), board(tour_cell(i + 1.0), ulen), f - i);
}

void vertex() {
	lp = VERTEX * size * 30.0 + vec3(seed * 1.37, seed * 0.71, seed * 2.13);
	ln = NORMAL;
	np = (VERTEX - mid) / max(ext, vec3(0.001));
	vec3 g = vec3(dot(gx.xyz, VERTEX) + gx.w, dot(gy.xyz, VERTEX) + gy.w, dot(gz.xyz, VERTEX) + gz.w);
	gp = gon > 0.5 ? (g - gmid) / max(gext.y, 0.001) : np * vec3(ext.x / max(ext.y, 0.001), 1.0, ext.z / max(ext.y, 0.001));
	gnn = gon > 0.5 ? normalize(vec3(dot(gx.xyz, NORMAL), dot(gy.xyz, NORMAL), dot(gz.xyz, NORMAL))) : NORMAL;
	vdir = VERTEX - (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	vec3 an = abs(ln);
	vec2 p2 = an.x > an.y && an.x > an.z ? lp.zy : (an.y > an.z ? lp.xz : lp.xy);
	vec3 col = c0.rgb; float rough = 0.62; float metal = 0.0; vec3 glow = vec3(0.0); float edge = 0.0;
	float relief = 0.0;  // (polish1 item 145) a painted height: bumps the lighting so shapes stand off the gun (coral)
	float relief_k = 0.0;
	float gloss = 0.06;  // how much of the painted studio the surface shows
	float t = TIME;
	float ch = challenge;
	vec3 rv = reflect(-VIEW, NORMAL);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	if (kind == 0) {  // woodland blobs: warped, four colours, crisp anti-aliased edges
		vec3 w = warp(lp * 0.32, 1.4);
		float a = field(w); float b = field(w * 1.15 + 13.0); float c = field(w * 1.7 + 29.0);
		col = c0.rgb;
		col = mix(col, c1.rgb, aa(0.48, a));
		col = mix(col, c3.rgb, aa(0.7, c) * (1.0 - aa(0.48, a)));
		col = mix(col, c2.rgb, aa(0.62, b));
		edge = aa(0.6, b) - aa(0.64, b) + (aa(0.46, a) - aa(0.5, a)) * 0.6;
	} else if (kind == 1) {  // digital: two pixel sizes like real digital camo
		float px = 3.2;
		vec2 q = floor(p2 * px);
		vec2 qb = floor(p2 * px * 0.5);
		vec3 w = warp(vec3(q / px * 0.3, 0.0), 1.2);
		float a = field(w); float b = field(w * 1.2 + 9.0); float c = field(vec3(qb * 0.2, 4.0) + 21.0);
		col = c0.rgb;
		col = mix(col, c1.rgb, step(0.47, a));
		col = mix(col, c3.rgb, step(0.68, c) * step(a, 0.47));
		col = mix(col, c2.rgb, step(0.63, b));
		col = mix(col, c2.rgb, step(0.92, h2(q + 5.0)) * step(0.4, b));  // stray pixels
		vec2 f = fract(p2 * px);
		edge = (step(f.x, 0.08) + step(f.y, 0.08)) * step(0.55, h2(q * 1.3)) * step(0.47, a);
	} else if (kind == 2) {  // multicam: a soft gradient, soft blotches, small hard branches
		vec3 w = warp(lp * 0.2, 1.0);
		col = mix(c0.rgb, c3.rgb, smoothstep(0.3, 0.75, field(w)));
		float a = field(warp(lp * 0.55 + 5.0, 1.0));
		col = mix(col, c1.rgb, smoothstep(0.55, 0.62, a) * 0.85);
		float br = field(lp * vec3(1.1, 2.4, 1.1) + 15.0);
		col = mix(col, c2.rgb, aa(0.74, br));
		col = mix(col, mix(c1.rgb, c2.rgb, 0.5), aa(0.78, field(lp * 1.6 + 31.0)) * 0.8);
		edge = aa(0.72, br) - aa(0.74, br);
	} else if (kind == 3) {  // flecktarn: small dots, coloured by clusters, gaps between
		float cl = field(warp(lp * 0.28, 1.0));
		float cl2 = field(lp * 0.4 + 7.0);
		vec3 v = vor(p2 * 4.2);
		float r = v.z;
		float dotm = 1.0 - aa(0.3 + 0.1 * cl, v.x);
		col = c0.rgb;
		vec3 dc = cl2 > 0.62 ? c2.rgb : (cl > 0.55 ? c1.rgb : (r < 0.35 ? c3.rgb : c1.rgb * 0.85));
		col = mix(col, dc, dotm * step(0.32, cl + r * 0.3));
		vec3 v2 = vor(p2 * 7.0 + 3.0);
		col = mix(col, c2.rgb, (1.0 - aa(0.2, v2.x)) * step(0.66, cl2) * step(0.5, v2.z));
		col = mix(col, c3.rgb, (1.0 - aa(0.18, v2.x)) * step(cl, 0.35) * step(0.7, v2.z));
		edge = (aa(0.27 + 0.1 * cl, v.x) - aa(0.33 + 0.1 * cl, v.x));
	} else if (kind == 4) {  // tiger stripes: tapered horizontal brush strokes
		vec3 w = warp(lp * vec3(0.12, 0.35, 0.12), 0.9);
		float y = w.y * 2.2;
		float row = floor(y);
		float f = fract(y);
		float len = field(vec3(w.x * 0.4, row * 3.1, w.z * 0.9 + row));
		float taper = smoothstep(0.38, 0.8, len);
		float th = 0.32 * taper;
		float stripe = 1.0 - aa(th, abs(f - 0.5) * 1.1);
		col = mix(c0.rgb, c3.rgb, smoothstep(0.35, 0.8, field(lp * 0.25 + 9.0)));
		col = mix(col, c1.rgb, (1.0 - aa(th + 0.12, abs(f - 0.5))) * step(0.3, len));
		col = mix(col, c2.rgb, stripe);
		edge = (1.0 - aa(th + 0.04, abs(f - 0.5) * 1.1)) - stripe;
	} else if (kind == 5) {  // hex camo: tiles coloured by clusters, thin dark seams
		vec4 hx = hexc(p2 * 2.2);
		float a = field(vec3(hx.zw * 0.18, 1.0)); float b = field(vec3(hx.zw * 0.22 + 5.0, 2.0));
		col = mix(c0.rgb, c1.rgb, step(0.5, a));
		col = mix(col, c3.rgb, step(0.72, b));
		col = mix(col, c2.rgb, step(0.7, a) * step(0.4, b));
		float seam = 1.0 - aa(0.035, hexedge(hx.xy));
		col = mix(col, col * 0.55, seam);
		edge = seam;
		glow = accent.rgb * seam * ch * 0.6;
	} else if (kind == 6) {  // spray paint: soft overspray bands, speckles, drips
		vec3 w = warp(lp * 0.3, 1.2);
		float a = field(w); float b = field(w * 1.3 + 8.0);
		col = mix(c0.rgb, c1.rgb, smoothstep(0.44, 0.58, a));
		col = mix(col, c2.rgb, smoothstep(0.6, 0.7, b));
		float speck = step(0.9, h1(floor(lp * 30.0))) * smoothstep(0.3, 0.6, a);
		col = mix(col, c1.rgb, speck * 0.8);
		float side = step(an.y, 0.6);
		float col_id = floor(lp.z * 2.5 + lp.x * 2.5);
		float drip = side * step(0.86, h2(vec2(col_id, 1.0))) * (1.0 - aa(0.035, abs(fract(lp.z * 2.5 + lp.x * 2.5) - 0.5)))
			* step(fract(-lp.y * 0.25 + h2(vec2(col_id, 2.0))), 0.45 + 0.2 * h2(vec2(col_id, 3.0)));
		col = mix(col, c3.rgb, smoothstep(0.7, 0.78, field(lp * 0.9 + 2.0)) * 0.7);
		col = mix(col, ch > 0.5 ? accent.rgb : c2.rgb, drip);
		gloss = 0.1;
	} else if (kind == 7) {  // solid cerakote: a faint mottle and fine grain, satin
		col = mix(c0.rgb, c2.rgb, field(lp * 0.6) * 0.35);
		col *= 0.92 + 0.08 * vn(lp * 40.0);
		rough = 0.5; gloss = 0.12;
		edge = 0.0;
	} else if (kind == 8) {  // splinter: stretched voronoi shards with straight edges + rain lines
		vec2 q = p2 * 0.9;
		vec2 qr = vec2(q.x * 0.7 + q.y * 0.5, -q.x * 0.35 + q.y * 1.1);
		vec3 v = vor(qr * 0.9);
		col = v.z < 0.38 ? c0.rgb : (v.z < 0.66 ? c1.rgb : (v.z < 0.86 ? c3.rgb : c2.rgb));
		float rain = step(0.7, h2(vec2(floor(q.x * 9.0), 3.0))) * step(fract(q.y * 1.6 + h2(vec2(floor(q.x * 9.0), 4.0))), 0.55);
		col = mix(col, c2.rgb, rain * (1.0 - aa(0.25, abs(fract(q.x * 9.0) - 0.5))) * 0.85);
		edge = 1.0 - aa(0.03, v.y);
	} else if (kind == 9) {  // brushstroke: bold diagonal strokes, sun faded
		vec3 q = warp(lp * 0.4, 0.5);
		vec3 s1 = vec3(q.x * 0.6 + q.y * 0.5, q.y * 2.6 - q.z * 0.6, q.z * 0.6);
		col = c0.rgb;
		col = mix(col, c1.rgb, aa(0.56, field(s1)));
		col = mix(col, c2.rgb, aa(0.64, field(s1 * 1.1 + 13.0)));
		col = mix(col, c3.rgb, aa(0.7, field(s1 * 1.3 + 5.0)));
		col = mix(col, vec3(0.9, 0.85, 0.7), 0.08 + 0.1 * field(lp * 0.3) * ch);
		edge = aa(0.54, field(s1)) - aa(0.58, field(s1));
	} else if (kind == 10) {  // chocolate chip: sand, soft brown fields, rock clusters with white dots
		vec3 w = warp(lp * 0.25, 1.2);
		col = mix(c0.rgb, c1.rgb, smoothstep(0.5, 0.6, field(w)));
		vec3 v = vor(p2 * 3.0);
		float cluster = step(0.55, field(lp * 0.5 + 3.0));
		float rock = (1.0 - aa(0.22 + 0.08 * v.z, v.x)) * cluster;
		col = mix(col, c2.rgb, rock);
		vec3 v2 = vor(p2 * 6.0 + 0.5);
		col = mix(col, c3.rgb, (1.0 - aa(0.11, v2.x)) * rock * step(0.4, v2.z));
		edge = (1.0 - aa(0.27 + 0.08 * v.z, v.x)) * cluster - rock;
	} else if (kind == 11) {  // night dots: a jittered grid of dots over a mottle
		col = mix(c0.rgb, c1.rgb, smoothstep(0.45, 0.6, field(warp(lp * 0.3, 1.0))));
		col = mix(col, c3.rgb, smoothstep(0.65, 0.75, field(lp * 0.5 + 9.0)) * 0.6);
		vec2 g = p2 * 3.6; vec2 id = floor(g); vec2 f = fract(g) - 0.5 - (h22(id) - 0.5) * 0.25;
		float r = 0.1 + 0.06 * step(0.7, h2(id + 2.0));
		float d = 1.0 - aa(r, length(f));
		col = mix(col, c2.rgb, d);
		glow = accent.rgb * d * 0.7 * ch * (0.7 + 0.3 * sin(t * 1.5 + h2(id) * 6.0));
	} else if (kind == 12) {  // DPM / CCE: ragged brushy blobs, stretched sideways
		vec3 q = warp(lp * vec3(0.55, 0.36, 0.3), 0.6);
		q += (vec3(vn(lp * 3.0), vn(lp * 3.0 + 4.0), 0.0) - 0.5) * 0.25;
		float a = field(q); float b = field(q * 1.1 + 9.0); float c = field(q * 1.4 + 17.0);
		col = c0.rgb;
		col = mix(col, c1.rgb, aa(0.5, a));
		col = mix(col, c2.rgb, aa(0.63, b));
		col = mix(col, c3.rgb, aa(0.74, c));
		edge = aa(0.48, a) - aa(0.52, a);
	} else if (kind == 13) {  // skull field: tumbling skulls with shading over a dark mottle
		vec2 q = p2 * 1.15; vec2 id = floor(q); vec2 f = fract(q) - 0.5 + (h22(id) - 0.5) * 0.15;
		float an2 = (h2(id) - 0.5) * 1.6;
		f = mat2(vec2(cos(an2), sin(an2)), vec2(-sin(an2), cos(an2))) * f * (1.1 + 0.3 * h2(id + 4.0));
		float sk = skull(f) * step(0.12, h2(id + 9.0));
		col = mix(c0.rgb, c2.rgb, smoothstep(0.45, 0.6, field(lp * 0.4)));
		vec3 bone = mix(c1.rgb, c3.rgb, smoothstep(0.1, -0.25, f.y) * 0.7);
		col = mix(col, bone, sk);
		float eyes = (1.0 - aa(0.06, length(vec2(abs(f.x) - 0.12, f.y - 0.03)))) * step(0.12, h2(id + 9.0)) * step(0.55, h2(id + 5.0));
		glow = accent.rgb * eyes * ch * (1.2 + 0.6 * sin(t * 3.0 + h2(id) * 6.0));
		gloss = 0.1;
	} else if (kind == 14) {  // neon kanji graffiti: brush glyphs with glowing halos on dark concrete
		vec2 q = p2 * 0.95; vec2 id = floor(q); vec2 f = fract(q) - 0.5;
		float r = h2(id);
		float d = glyph(f, r);
		float on = step(0.25, h2(id + 2.0));
		vec3 neon = r < 0.33 ? c1.rgb : (r < 0.66 ? c2.rgb : c3.rgb);
		col = mix(c0.rgb, c0.rgb * 2.2, field(lp * 1.2) * 0.4);
		float core = (1.0 - aa(0.0, d)) * on;
		float halo = smoothstep(0.12, 0.0, d) * on;
		col = mix(col, mix(neon, vec3(1.0), 0.35), core);
		float pulse = 1.0 + 0.4 * sin(t * 2.0 + r * 6.0) * ch;
		glow = neon * (core * 1.6 + halo * 0.5) * pulse;
		float drip = core * 0.0;
		gloss = 0.05;
	} else if (kind == 15) {  // polka: glossy enamel dots
		vec2 q = p2 * 2.2; vec2 id = floor(q); vec2 f = fract(q) - 0.5;
		float rad = 0.27 + 0.07 * sin(t * 2.0 + h2(id) * 6.0) * ch;
		float d = 1.0 - aa(rad, length(f));
		col = mix(c0.rgb, c1.rgb, d);
		rough = 0.22; gloss = 0.22;
	} else if (kind == 16) {  // zebra: tapered organic stripes, satin
		vec3 w = warp(lp * vec3(0.3, 0.25, 0.3), 1.6);
		float s1 = w.z * 1.5 + w.y * 0.6 + t * 0.5 * inspect * ch;
		float wv = abs(fract(s1) - 0.5) * 2.0;
		float th = 0.45 + 0.2 * field(lp * 0.6 + 3.0);
		col = mix(c0.rgb, c1.rgb, 1.0 - aa(th, wv));
		rough = 0.45; gloss = 0.1;
	} else if (kind == 17) {  // neon hex grid: glass tiles lit from their edges
		vec4 hx = hexc(p2 * 1.8);
		float e = hexedge(hx.xy);
		float line = 1.0 - aa(0.04, e);
		float inner = smoothstep(0.2, 0.0, e) * 0.35;
		float pulse = 0.6 + 0.4 * sin(t * 2.5 - length(hx.zw) * 0.7) * (0.5 + ch * 0.5);
		vec3 neon = mix(c1.rgb, c2.rgb, smoothstep(0.3, 0.7, field(vec3(hx.zw * 0.2, 1.0))));
		col = mix(c0.rgb, neon * 0.5, inner);
		col = mix(col, neon, line);
		glow = neon * (line * 1.8 + inner * 0.6) * pulse;
		rough = 0.25; gloss = 0.15;
	} else if (kind == 18) {  // cracked earth: raised dried plates, deep cracks, magma in the big ones
		vec3 v = vor(p2 * 1.4 + (vec2(vn(lp * 2.0), vn(lp * 2.0 + 5.0)) - 0.5) * 0.3);
		float crack = 1.0 - smoothstep(0.02, 0.06 + 0.02 * ch, v.y);
		float plate = smoothstep(0.0, 0.25, v.y);
		col = mix(c0.rgb, c3.rgb, field(lp * 1.4) * 0.5);
		col *= 0.75 + 0.25 * plate;
		col = mix(col, c2.rgb, crack);
		float big = step(0.45, v.z);
		glow = accent.rgb * crack * big * ch * (1.6 + 0.6 * sin(t * 1.5 + v.z * 8.0));
		rough = 0.9;
	} else if (kind == 19) {  // circuit board: traces, pads, chips, light running along
		vec2 q = p2 * 3.0; vec2 id = floor(q); vec2 f = fract(q);
		float r = h2(id);
		float horiz = step(0.5, r);
		float tr = 1.0 - aa(0.06, horiz > 0.5 ? abs(f.y - 0.5) : abs(f.x - 0.5));
		tr *= step(0.22, h2(id + 9.0));
		float bend = (1.0 - aa(0.06, abs(f.x - 0.5))) * (1.0 - aa(0.06, abs(f.y - 0.5))) * 0.0;
		float pad = (1.0 - aa(0.16, length(f - 0.5))) * step(0.88, r);
		float hole = (1.0 - aa(0.06, length(f - 0.5))) * step(0.88, r);
		vec2 cq = p2 * 0.7; vec2 cid = floor(cq); vec2 cf = fract(cq) - 0.5;
		float chip = step(0.75, h2(cid)) * (1.0 - aa(0.0, max(abs(cf.x) - 0.28, abs(cf.y) - 0.18)));
		col = mix(c0.rgb, c2.rgb, field(lp * 0.6) * 0.5);
		col = mix(col, c1.rgb, max(tr, pad));
		col = mix(col, vec3(0.05), hole);
		col = mix(col, vec3(0.06, 0.06, 0.07), chip);
		float run = fract((horiz > 0.5 ? id.x + f.x : id.y + f.y) * 0.2 - t * (0.5 + 0.4 * ch));
		glow = c3.rgb * tr * smoothstep(0.9, 1.0, run) * (1.0 + 2.0 * ch) + c3.rgb * pad * 0.25;
		metal = max(tr, pad) * 0.7; rough = mix(0.6, 0.3, max(tr, pad)); gloss = 0.08;
	} else if (kind == 20) {  // silver: brushed metal with a painted studio in it and a moving sweep
		float brush = vn(lp * vec3(1.0, 1.0, 0.0) * 40.0 + vec3(0.0, 0.0, lp.z * 0.5)) * 0.5 + vn(lp * vec3(70.0, 70.0, 1.5)) * 0.5;
		vec3 r = rv; r.y += (brush - 0.5) * 0.18;
		col = min(studio(r), vec3(1.2)) * mix(c0.rgb, c2.rgb, 0.4) * (0.85 + 0.25 * brush);
		float sweep = smoothstep(0.1, 0.0, abs(fract(lp.z * 0.05 + lp.y * 0.03 - t * (0.22 + 0.3 * ch)) - 0.5));
		glow = vec3(0.8) * sweep * (0.35 + 0.5 * ch) + vec3(0.6, 0.8, 1.0) * reload * 0.7 * ch + vec3(0.15) * aim * ch;
		metal = 0.3; rough = 0.3; gloss = 0.0;
	} else if (kind == 21) {  // gold: polished, slowly moving reflections, engraved scrollwork
		vec2 q = p2 * 1.1; vec2 id = floor(q); vec2 f = fract(q) - 0.5;
		float ang = atan(f.y, f.x); float rad = length(f);
		float scroll = abs(fract(rad * 5.0 - ang / 6.2832 * (h2(id) > 0.5 ? 1.0 : -1.0)) - 0.5);
		float eng = (1.0 - aa(0.1, scroll)) * smoothstep(0.48, 0.3, rad) * (1.0 - aa(0.0, -rad + 0.06));
		vec3 r = rv; r.xz = mat2(vec2(cos(t * 0.15), sin(t * 0.15)), vec2(-sin(t * 0.15), cos(t * 0.15))) * r.xz;
		vec3 gold = mix(c3.rgb, c2.rgb, 0.5);
		col = min(studio(r), vec3(1.2)) * gold * 1.1 + c0.rgb * 0.12;
		col = mix(col, c3.rgb * 0.35, eng * 0.8);
		glow = c2.rgb * kill * 2.0 * ch + c0.rgb * 0.18 * step(0.99, ammo) * ch + c2.rgb * fres * 0.12;
		metal = 0.3; rough = 0.25; gloss = 0.0;
	} else if (kind == 22) {  // diamond: faceted crystal, every facet catching the light its own way, fire at the edges
		vec3 v = vor(p2 * 2.0);
		vec3 fn = normalize(vec3(h2(vec2(v.z, 1.0)) - 0.5, h2(vec2(v.z, 2.0)) - 0.5, 0.6));
		vec3 r = normalize(rv + fn * 0.9 + vec3(0.0, inspect * sin(t) * 0.3, 0.0));
		vec3 ice = mix(c1.rgb, c2.rgb, 0.5);
		col = mix(ice * 0.75, min(studio(r), vec3(1.3)) * ice * 1.3, 0.6) + c3.rgb * 0.1;
		float e = 1.0 - aa(0.04, v.y);
		vec3 fire = hsv(fract(v.z * 3.0 + dot(rv, vec3(1.0)) * 0.5 + t * 0.1), 0.7, 1.0);
		col = mix(col, fire, e * 0.6);
		float rate = 3.0 + 5.0 * ch + speed * 10.0 * ch;
		float sp = step(0.987 - 0.008 * ch - speed * 0.01 * ch, h1(floor(lp * 8.0) + floor(t * rate) * 0.37));
		glow = vec3(sp) * (2.0 + inspect * 2.0) + fire * e * 0.2 + c2.rgb * fres * (0.1 + 0.5 * inspect * ch);
		rough = 0.1; gloss = 0.0;
	} else if (kind == 23) {  // phantom: a dark smoky shell, ghost light in it, it fades at the edges
		vec3 q = lp * 0.4 + vec3(0.0, -t * 0.6, t * 0.25);
		float smoke = field(warp(q, 1.8));
		float wisp = smoothstep(0.52, 0.8, smoke);
		col = mix(c1.rgb, c2.rgb, smoke * 0.5);
		float solid = 0.62 + 0.4 * smoke - fres * 0.6 + aim * (0.35 + 0.35 * ch);
		float bayer = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
		if (bayer > solid) { discard; }
		glow = c3.rgb * (wisp * 1.4 + fres * 1.6 + smoke * 0.15) * (1.0 + ch * 0.6);
		col *= 0.6; rough = 0.4; gloss = 0.0;
	} else if (kind == 24) {  // galaxy (polish1 item 145): a WINDOW INTO DEEP SPACE: layers that move against each other as the
		// gun turns (parallax): far nebula clouds with dark dust lanes, a spiral galaxy turning slowly on the gun's side, near
		// stars of every size, the brightest with four spikes, a shooting star now and then. Challenge: colours shift with speed.
		vec3 vd = normalize(vdir);
		float shift = speed * 0.35 * ch;
		vec3 q1 = (lp + vd * 22.0) * 0.06 + vec3(t * 0.008, 0.0, t * 0.012);
		vec3 wq = warp(q1, 2.6);
		float neb = field(wq);
		float neb2 = field(wq * 1.7 + 11.0);
		float dust = smoothstep(0.52, 0.8, field(warp(q1 * 2.2 + 4.0, 1.8)));
		vec3 nc = mix(c1.rgb, c2.rgb, smoothstep(0.25, 0.75, fract(neb2 + shift)));
		nc = mix(nc, c3.rgb, smoothstep(0.82, 0.98, fract(neb + shift * 0.5)) * 0.7);
		float fil = ridge(wq * 2.3 + 2.0);  // thin glowing filaments through the clouds
		float dens = pow(smoothstep(0.64, 1.0, neb), 1.8) * (1.0 - dust * 0.95);
		col = c0.rgb * 0.35;
		glow = nc * (dens * 0.5 + pow(fil, 6.0) * dens * 0.8 + pow(fil, 12.0) * 0.08);
		// the spiral galaxy, deeper than the stars (gun space, on the sides)
		vec2 g = vec2(gp.z, gp.y) + vec2(vd.z, vd.y) * 0.5 - vec2(0.15 * gext.z / max(gext.y, 0.001), 0.45);
		float rr = length(g) / 1.25;
		float ang = atan(g.y, g.x) - t * 0.05;
		float arms = pow(0.5 + 0.5 * cos(2.0 * (ang + 2.4 * log(rr + 0.04))), 3.0) * (0.7 + 0.6 * vn(vec3(g * 9.0, 2.0)));
		float disc = exp(-rr * 2.4);
		float sidep = smoothstep(0.35, 0.6, abs(gnn.x));
		float spiral = (arms * disc * 0.8 + exp(-rr * rr * 90.0) * 1.8 + disc * 0.12) * sidep;
		float knots = 0.0;
		glow += mix(c3.rgb, vec3(1.0, 0.92, 0.8), smoothstep(0.3, 0.0, rr)) * spiral + vec3(0.9, 0.85, 1.0) * knots * 1.5;
		// near stars: small and many, twinkling (on the face's own plane, so none are sliced away)
		vec2 sq = (p2 + vec2(vd.z + vd.x, vd.y) * 4.0) * 1.3;
		vec2 cell = floor(sq);
		float st = h2(cell);
		float sd = length(fract(sq) - 0.5 - (h22(cell + 3.3) - 0.5) * 0.7);
		float tw = 0.6 + 0.4 * sin(t * (1.5 + 3.0 * ch) + st * 40.0);
		float star = step(0.55, st) * (1.0 - aa(0.04 + 0.07 * (st - 0.55), sd)) * tw;
		glow += mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), h2(cell + 8.0)) * star * 3.0;
		vec2 sq2 = (p2 + vec2(vd.z + vd.x, vd.y) * 9.0) * 2.6;  // a finer, fainter, deeper layer
		float st2 = h2(floor(sq2) + 21.0);
		glow += vec3(0.7, 0.75, 1.0) * step(0.6, st2) * (1.0 - aa(0.05, length(fract(sq2) - 0.5 - (h22(floor(sq2) + 7.0) - 0.5) * 0.7))) * 1.2;
		// bright stars with four spikes (the face's own plane)
		vec2 bq = (p2 + vec2(vd.z + vd.x, vd.y) * 1.5) * 0.35;
		vec2 bc = floor(bq); vec2 bf = fract(bq) - 0.5 - (h22(bc + 5.0) - 0.5) * 0.5;
		float bs = h2(bc + 9.0);
		float spike = (1.0 - aa(0.006, abs(bf.x))) * smoothstep(0.32, 0.0, abs(bf.y)) + (1.0 - aa(0.006, abs(bf.y))) * smoothstep(0.32, 0.0, abs(bf.x));
		glow += vec3(1.0, 0.97, 0.92) * step(0.9, bs) * (spike * 1.6 + (1.0 - aa(0.025, length(bf))) * 4.0) * (0.75 + 0.25 * sin(t * 2.0 + bs * 30.0));
		// a shooting star every 7 s, across the gun's side
		float ph = fract(t / 7.0 + seed * 0.13);
		vec2 mdir = normalize(vec2(1.0, -0.35));
		vec2 mh = vec2(mix(-1.3, 1.3, ph / 0.18) * gext.z / max(gext.y, 0.001), 0.9 - ph / 0.18 * 0.6);
		vec2 mrel = vec2(gp.z, gp.y) - mh;
		float along = dot(mrel, -mdir);
		float meteor = (1.0 - aa(0.008 + along * 0.004, abs(dot(mrel, vec2(-mdir.y, mdir.x))))) * step(0.0, along) * smoothstep(0.9, 0.0, along) * step(ph, 0.18) * sidep;
		glow += vec3(1.0, 0.95, 0.9) * meteor * 3.0;
		glow += nc * fres * 0.5;
		rough = 0.2; gloss = 0.12;
	} else if (kind == 25) {  // neon oni: black lacquer, flowing neon veins, an oni face on each side, embers
		col = c0.rgb; rough = 0.12; gloss = 0.35;
		vec3 w = warp(lp * 0.25 + vec3(0.0, 0.0, t * 0.08), 1.6);
		float vein = abs(fract(field(w) * 5.0) - 0.5);
		float line = 1.0 - aa(0.045, vein);
		vec3 neon = mix(c1.rgb, c3.rgb, 0.5 + 0.5 * sin(t * 0.6 + field(w) * 8.0));
		glow = neon * line * 1.4 + neon * smoothstep(0.15, 0.0, vein) * 0.25;
		vec2 fq = vec2(np.z * ext.z / ext.y * 0.42 + 0.1, np.y * 0.42) ;
		float blink = 1.0 - step(0.96, fract(t * 0.21)) * (0.5 + 0.5 * ch);
		float fd = face(fq, blink, 0.7 + 0.5 * ch);
		float fl = (1.0 - aa(0.0, fd)) * step(0.45, an.x) * body;
		col = mix(col, c1.rgb * 0.6, fl);
		glow += c1.rgb * fl * (1.6 + 2.5 * inspect) + c1.rgb * smoothstep(0.06, 0.0, fd) * step(0.45, an.x) * 0.4 * body;
		float ember = step(0.992 - 0.004 * ch, h1(floor(lp * 6.0 + vec3(0.0, t * 5.0, 0.0))));
		glow += c2.rgb * ember * 3.0;
	} else if (kind == 26) {  // living coral (polish1 item 145): a REEF: deep water behind (parallax) with light rippling down
		// in caustics, three kinds of coral side by side (branching coral with glowing polyp tips, brain coral domes with
		// meandering grooves, anemones whose tentacles wave), a few small fish swimming along the gun, bubbles rising.
		// Challenge / inspect: full bloom (polyps and anemones open and glow).
		vec3 vd = normalize(vdir);
		float bloom = clamp(inspect * (0.5 + 0.5 * ch) + ch * 0.25, 0.0, 1.0);
		vec2 dq = (p2 + vec2(vd.z + vd.x, vd.y) * 10.0) * 0.18;
		vec3 sea = mix(vec3(0.005, 0.03, 0.08), vec3(0.02, 0.16, 0.26), clamp(gp.y * 0.4 + 0.55, 0.0, 1.0));
		float rays = pow(vn(vec3(dq.x * 1.2 + dq.y * 0.5, t * 0.15, 3.0)), 3.0);
		sea += vec3(0.05, 0.2, 0.25) * rays;
		// caustics: bright wandering cell edges, two layers drifting apart
		vec2 cq = p2 * 0.3 + vec2(sin(t * 0.4 + p2.y * 0.3), cos(t * 0.33 + p2.x * 0.3)) * 0.6;
		float ca = (1.0 - smoothstep(0.0, 0.14, vor(cq + vec2(t * 0.11, t * 0.07)).y)) + (1.0 - smoothstep(0.0, 0.1, vor(cq * 1.4 - vec2(t * 0.09, -t * 0.05) + 7.0).y)) * 0.7;
		float up = smoothstep(0.2, 0.9, gnn.y) * 0.7 + 0.3;
		// which coral grows where
		float reg = field(lp * 0.06 + 3.0) * 0.4 + clamp(gp.z / max(gext.z / max(gext.y, 0.001), 0.001) * 0.5 + 0.5, 0.0, 1.0) * 0.6;  // muzzle: branches, middle: brain coral, stock: anemones (mixed by noise)
		float wb = smoothstep(0.44, 0.5, reg);  // branching -> brain
		float wa = smoothstep(0.58, 0.64, reg);  // brain -> anemones
		// 1 branching coral: thick main branches forking into thin twigs (two ridge nets), thick where a clump grows,
		// rounded lit tips, glowing polyps along them
		vec3 w = warp(lp * 0.26, 1.3);
		float clump = clamp(field(lp * 0.09 + 17.0) + (0.45 - gp.y) * 0.35, 0.0, 1.0);  // the reef thickens low on the gun
		float b1 = ridge(w * 1.0);
		float b2 = ridge(w * 2.6 + 9.0);
		float sway = 0.015 * sin(t * 0.6 + lp.y * 0.2);
		float m1 = smoothstep(0.88 - 0.12 * clump + sway, 0.9 - 0.12 * clump + sway, b1);
		float m2 = smoothstep(0.92 - 0.08 * clump, 0.94 - 0.08 * clump, b2) * smoothstep(0.8, 0.86, b1 + clump * 0.15);
		float coral = max(m1, m2) * smoothstep(0.12, 0.28, clump);
		float core = smoothstep(0.94 - 0.1 * clump, 1.0, b1);  // the lit middle of a branch
		vec3 bcol = mix(c1.rgb * 0.5, c1.rgb * 1.15, core);
		bcol = mix(bcol, c2.rgb * 1.1, m2 * (1.0 - m1) * 0.8);  // twigs lighter
		vec3 pv = vor(p2 * 4.0 + 5.0);
		float polyp = (1.0 - aa(0.14 + 0.1 * bloom, pv.x)) * step(0.5, pv.z) * coral;
		float shade = smoothstep(0.62, 0.9, b1 + clump * 0.1) * smoothstep(0.12, 0.28, clump) * (1.0 - coral);  // its shadow on the water behind
		vec3 c_branch = mix(sea * (1.0 - 0.55 * shade), bcol * (0.55 + 0.45 * core), coral);  // round: dark at the sides, lit along the middle
		c_branch = mix(c_branch, c3.rgb * 0.6 + 0.2, polyp * 0.7);
		float h_branch = coral * (0.35 + 0.65 * core) + polyp * 0.25;
		vec3 g_branch = c3.rgb * polyp * (0.6 + 2.2 * bloom) * (0.6 + 0.4 * sin(t * 2.0 + pv.z * 20.0)) + c1.rgb * coral * 0.08;
		// 2 brain coral (round domes with meandering grooves)
		vec3 dv = vor(p2 * 0.42 + 11.0);
		float dome = smoothstep(0.5, 0.38, dv.x) * step(0.45, dv.z);
		float mang = field(lp * 0.2 + 5.0) * 9.0;
		float mz = abs(sin(dot(p2, vec2(cos(mang), sin(mang))) * 7.0 + field(lp * 0.5) * 4.0));  // meandering parallel grooves
		float groove = (1.0 - aa(0.35, mz)) * dome;
		float rise = sqrt(max(1.0 - pow(dv.x / 0.5, 2.0), 0.0));  // a dome's height across it
		vec3 c_brain = mix(c_branch, mix(c2.rgb * 0.95, c2.rgb * 0.4 + c1.rgb * 0.15, groove) * (0.45 + 0.65 * rise), dome);
		c_brain = mix(c_brain, c_brain * 0.5, smoothstep(0.62, 0.5, dv.x) * (1.0 - dome));  // shadow round its foot
		float h_brain = mix(h_branch, rise * 0.9 - groove * 0.25, dome);
		vec3 g_brain = mix(g_branch, c2.rgb * groove * 0.12 * (1.0 + bloom), dome);
		// 3 anemones (tentacles waving round a mouth) on a rocky floor
		vec2 aq = p2 * 0.34; vec2 ac = floor(aq); vec2 af = fract(aq) - 0.5 - (h22(ac + 2.0) - 0.5) * 0.3;
		float ar = length(af); float aang = atan(af.y, af.x);
		float reach = 0.32 + 0.1 * bloom;
		float tent = abs(sin(aang * 8.0 + sin(t * 1.6 + ar * 9.0 + h2(ac) * 6.0) * 0.7));
		float anem = (1.0 - aa(0.18, tent * smoothstep(0.08, reach, ar) * 1.6)) * (1.0 - aa(reach, ar));
		float mouth = 1.0 - aa(0.07, ar);
		vec3 rock = mix(sea * 1.5, vec3(0.08, 0.07, 0.09), field(lp * 0.4) * 0.6);
		vec3 acol = mix(c1.rgb * 0.8, c3.rgb * 0.7, smoothstep(0.1, reach, ar));
		vec3 c_anem = mix(rock * (1.0 - 0.4 * (1.0 - aa(reach + 0.06, ar))), acol * (0.6 + 0.4 * smoothstep(0.1, reach, ar)), anem);
		c_anem = mix(c_anem, c2.rgb * 0.5, mouth);
		float h_anem = anem * (0.5 + 0.5 * smoothstep(reach, 0.1, ar)) + (1.0 - aa(0.12, ar)) * 0.4 - mouth * 0.3;
		vec3 g_anem = c3.rgb * anem * smoothstep(reach * 0.6, reach, ar) * (0.5 + 1.8 * bloom) * (0.7 + 0.3 * sin(t * 2.5 + h2(ac) * 9.0));
		col = mix(mix(c_branch, c_brain, wb), c_anem, wa);
		glow = mix(mix(g_branch, g_brain, wb), g_anem, wa);
		relief = mix(mix(h_branch, h_brain, wb), h_anem, wa) * 0.035;
		relief_k = 1.0;
		glow += c3.rgb * fres * 0.25 * smoothstep(0.1, 0.5, relief * 28.0);  // a soft rim on the coral against the deep
		col += vec3(0.25, 0.6, 0.65) * ca * up * 0.45;  // the light on everything
		glow += vec3(0.15, 0.5, 0.55) * ca * up * 0.4;
		// small fish along the gun's sides (gun space): striped orange bodies, a tail that beats
		float sidef = smoothstep(0.35, 0.6, abs(gnn.x));
		float ulen = gext.z / max(gext.y, 0.001);
		for (int k = 0; k < 5; k++) {
			float fk = float(k);
			float sp = 0.18 + 0.08 * h2(vec2(fk, 1.0));
			float fx = (fract(t * sp / ulen * 0.5 + h2(vec2(fk, 2.0))) * 2.4 - 1.2) * ulen;
			float fy = 0.2 + 0.55 * h2(vec2(fk, 3.0)) + 0.06 * sin(t * 1.3 + fk * 2.0);
			vec2 fl = vec2(gp.z, gp.y) - vec2(fx, fy);
			fl.x = -fl.x;  // they swim toward the muzzle
			float bodyf = 1.0 - aa(1.0, length(fl / vec2(0.075, 0.032)));
			float wag = sin(t * 9.0 + fk) * 0.012;
			vec2 tl = fl - vec2(0.085, wag);
			float tail = (1.0 - aa(0.0, abs(tl.y) - max(tl.x, 0.0) * 0.8 - 0.002)) * step(-0.01, tl.x) * step(tl.x, 0.04);
			float stripe = step(0.5, fract(fl.x * 22.0 + 0.25)) * 0.0 + (1.0 - aa(0.008, abs(fl.x + 0.01))) + (1.0 - aa(0.006, abs(fl.x - 0.035)));
			float fish = max(bodyf, tail) * sidef;
			vec3 fc = mix(vec3(1.0, 0.45, 0.08), vec3(1.0), clamp(stripe, 0.0, 1.0) * bodyf);
			col = mix(col, fc, fish);
			glow = mix(glow, fc * 0.25, fish);
			glow += vec3(0.0) * fish;
			float eye = (1.0 - aa(0.006, length(fl - vec2(-0.045, 0.006)))) * sidef;
			col = mix(col, vec3(0.0), eye);
		}
		// bubbles rising from the reef
		vec2 bq = vec2(p2.x * 0.9, p2.y * 0.9 - t * 0.9);
		vec2 bcell = floor(bq); vec2 bf2 = fract(bq) - 0.5 - (h22(bcell + 4.0) - 0.5) * 0.6;
		float bubble = step(0.86, h2(bcell + 1.7)) * (1.0 - aa(0.02, abs(length(bf2) - 0.09 - 0.05 * h2(bcell))));
		glow += vec3(0.6, 0.9, 1.0) * bubble * 0.8;
		rough = 0.55; gloss = 0.08;
	} else if (kind == 27) {  // glitch reality: a datamoshed surface, RGB split, scanlines, slipping blocks
		float g = 0.25 + shoot * (0.5 + 0.5 * ch) + reload * 0.4 + inspect * 0.7;
		float band = floor(lp.y * 2.5 + floor(t * 9.0) * 0.37);
		float off = (h2(vec2(band, floor(t * 11.0))) - 0.5) * g * 5.0 * step(0.6, h2(vec2(band, floor(t * 7.0))));
		vec2 q = vec2(lp.z + off, lp.y);
		vec2 cell = floor(q * vec2(1.5, 3.0));
		float r = h2(cell + floor(t * 4.0) * step(0.8, h2(cell)));
		col = mix(c0.rgb, c3.rgb * 0.5, step(0.75, r));
		col += c1.rgb * 0.15 * (1.0 - aa(0.04, min(fract(q.x * 3.0), fract(q.y * 6.0))));
		col = mix(col, mix(c1.rgb, c2.rgb, h2(cell + 7.0)) * 0.5, step(0.62, r) * step(r, 0.75));
		float rgb = step(0.5, fract(q.x * 2.0 + t * 0.7));
		float blk = step(0.88, r);
		glow = mix(c1.rgb, c2.rgb, rgb) * blk * 1.6;
		glow += c1.rgb * (1.0 - aa(0.05, abs(fract(q.x * 0.5 + 0.03) - 0.5))) * 0.4 + c2.rgb * (1.0 - aa(0.05, abs(fract(q.x * 0.5 - 0.03) - 0.5))) * 0.4;
		float scan = step(0.5, fract(FRAGCOORD.y * 0.25));
		col *= 0.85 + 0.15 * scan;
		glow += vec3(step(0.96, h2(vec2(floor(FRAGCOORD.y * 0.2), floor(t * 22.0))))) * g * 1.5;
		rough = 0.3; gloss = 0.12;
	} else if (kind == 28) {  // void serpent (polish1 item 145): a swirling void; a scaled serpent SLIDES round the gun's side
		// on a snake-game tour, head first (eyes, a flicking tongue), chasing small translucent orbs and EATING them (a flash,
		// a lump going down its body); the tour spans every part of the gun (gun space), parts in between hide it for a moment
		// the ground (director 2026-11-23): very dark grey with a repeating hexagon pattern a shade lighter, quiet so the
		// serpent and the orbs carry the eye
		vec4 bg = hexc(p2 * 1.1);
		float hex_line = 1.0 - aa(0.05, hexedge(bg.xy));
		col = mix(vec3(0.045, 0.045, 0.05), vec3(0.085, 0.085, 0.09), hex_line);
		glow = vec3(0.0);
		float side = smoothstep(0.35, 0.55, abs(gnn.x));
		float ulen = gext.z / max(gext.y, 0.001);
		vec2 q = vec2(gp.z, gp.y);
		float cw = 1.72 * ulen / 11.0;  // a cell along the gun
		float f = t * (1.7 + 1.6 * inspect * ch) + seed * 3.0;  // the head's place on the tour, in cells
		// the body: 16 joints half a cell apart behind the head
		float best = 9.0; float s_at = 0.0; vec2 dir = vec2(1.0, 0.0); float lat = 0.0;
		vec2 prev = tour_at(f, ulen);
		vec2 head = prev;
		vec2 hdir = normalize(tour_at(f, ulen) - tour_at(f - 0.2, ulen) + vec2(0.00001, 0.0));
		for (int k = 1; k <= 16; k++) {
			vec2 cur = tour_at(f - float(k) * 0.5, ulen);
			vec2 ba = prev - cur; vec2 pa = q - cur;
			float hh = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
			vec2 off = pa - ba * hh;
			float d = length(off);
			if (d < best) { best = d; s_at = float(k) * 0.5 - hh * 0.5; dir = normalize(ba + vec2(0.000001, 0.0)); lat = dot(off, vec2(-dir.y, dir.x)); }
			prev = cur;
		}
		// the last orb eaten: how many cells ago (its lump travels down the body)
		float eaten_n = floor((floor(f) - 2.0) / 4.0) * 4.0 + 2.0;
		float age = f - eaten_n;
		float lump = 1.0 + 0.55 * exp(-pow((s_at - age) * 2.2, 2.0)) * step(age, 8.0);
		float taper = 1.0 - 0.75 * pow(clamp(s_at / 8.0, 0.0, 1.0), 1.6);
		float bw = 0.056 * taper * lump * (s_at < 0.45 ? 1.0 + 0.75 * (1.0 - s_at / 0.45) : 1.0);
		float sbody = (1.0 - aa(bw, best)) * side;
		float across = clamp(lat / max(bw, 0.001), -1.0, 1.0);
		vec4 hs = hexc(vec2(s_at * 9.0, across * 1.6) * vec2(1.0, 1.0));
		float scale = 1.0 - aa(0.08, hexedge(hs.xy));
		float round_ = sqrt(max(1.0 - across * across, 0.0));
		vec3 skin = mix(c1.rgb * 0.5, c1.rgb * 1.9 + c2.rgb * 0.25, round_);
		skin = mix(skin, c3.rgb * 0.55, smoothstep(0.55, 1.0, -across) * 0.6);  // its pale belly
		float diamond = abs(across) * 1.3 + abs(fract(s_at * 2.2 + 0.25) - 0.5) * 1.6;  // dark diamonds down its back
		skin = mix(skin, c0.rgb * 1.5, (1.0 - aa(0.62, diamond)) * 0.85);
		skin += c2.rgb * 0.6 * (1.0 - aa(0.05, abs(diamond - 0.66)));  // their violet rims
		col = mix(col, mix(skin * 0.4, skin, scale), sbody);
		float wave = smoothstep(0.2, 0.0, abs(fract(s_at * 0.35 - t * 0.6) - 0.5));
		glow += c2.rgb * sbody * ((1.0 - scale) * (0.7 + 1.6 * wave) + 0.15);
		glow += c2.rgb * (1.0 - aa(bw + 0.03, best)) * (1.0 - sbody / max(side, 0.001)) * side * 0.6;  // a violet aura round it
		// the head: two glowing eyes, a forked tongue flicking out now and then
		vec2 hp = q - head;
		vec2 hn = vec2(-hdir.y, hdir.x);
		vec2 hl = vec2(dot(hp, hdir), dot(hp, hn));
		vec2 e1 = hl - vec2(0.022, 0.04); vec2 e2 = hl - vec2(0.022, -0.04);
		float eyes = (1.0 - aa(0.025, length(e1))) + (1.0 - aa(0.025, length(e2)));
		float pupil = (1.0 - aa(0.006, abs(e1.x) - 0.017 * (1.0 - smoothstep(0.0, 0.02, abs(e1.y))))) * (1.0 - aa(0.025, length(e1)))
			+ (1.0 - aa(0.006, abs(e2.x) - 0.017 * (1.0 - smoothstep(0.0, 0.02, abs(e2.y))))) * (1.0 - aa(0.025, length(e2)));  // slit pupils
		glow += mix(vec3(1.0, 0.95, 0.4), c3.rgb, 0.3) * eyes * (1.0 - pupil) * side * (4.0 + 5.0 * inspect);
		glow += c2.rgb * side * (1.0 - aa(0.05, length(e1))) * (1.0 - eyes) * 0.8 + c2.rgb * side * (1.0 - aa(0.05, length(e2))) * (1.0 - eyes) * 0.8;  // eye glow round them
		col = mix(col, vec3(0.0), eyes * side);
		float flick = step(0.7, fract(t * 0.8));
		float tongue = (1.0 - aa(0.006, abs(hl.y) - max(hl.x - 0.13, 0.0) * 0.5)) * step(0.075, hl.x) * step(hl.x, 0.17) * flick;
		col = mix(col, vec3(0.9, 0.2, 0.4), tongue * side);
		glow += vec3(1.0, 0.25, 0.5) * tongue * side * 1.5;
		// the orbs: on every 4th cell of the tour still ahead of the head this lap; translucent, each its own colour
		float lap = floor(f / 36.0);
		for (int k = 0; k < 9; k++) {
			float n = lap * 36.0 + float(k) * 4.0 + 2.0;
			if (n <= floor(f) + 0.5 && n < f) { continue; }
			vec2 o = board(tour_cell(n), ulen) + vec2(0.0, 0.012 * sin(t * 2.0 + float(k)));
			float r = 0.04;
			float od = length(q - o) / r;
			if (od < 1.6) {
				vec3 oc = hsv(h2(vec2(n, 3.1)), 0.65, 1.0);
				float inside = 1.0 - aa(1.0, od);
				col = mix(col, mix(col, oc * 0.5, 0.45), inside * side);  // you see the gun through it
				glow += oc * side * (inside * (0.35 + 0.9 * pow(od, 4.0)) + smoothstep(1.5, 1.0, od) * (1.0 - inside) * 0.35);
				glow += vec3(1.0) * side * (1.0 - aa(0.18, length(q - o - vec2(-0.3, 0.35) * r) / r));  // a highlight
			}
		}
		// the bite: a ring of light spreading from where the last orb was eaten
		vec2 eo = board(tour_cell(eaten_n), ulen);
		float ring = (1.0 - aa(0.012, abs(length(q - eo) - age * 0.06))) * smoothstep(1.4, 0.0, age);
		glow += hsv(h2(vec2(eaten_n, 3.1)), 0.65, 1.0) * ring * side * 2.0;
		rough = 0.3; gloss = 0.05;
	} else if (kind == 29) {  // carnival from hell: harlequin diamonds cycling colours, gold trim, grinning faces, confetti
		vec2 q = p2 * 0.9;
		vec2 dq = vec2(q.x + q.y, q.x - q.y) * 0.7071;
		vec2 did = floor(dq); vec2 df = fract(dq);
		float chk = mod(did.x + did.y, 2.0);
		float cyc = t * 0.12;
		vec3 a = hsv(fract(cyc + h2(did) * 0.15), 0.8, 0.62); vec3 b = c0.rgb * 1.2;
		col = mix(vec3(0.03, 0.01, 0.02), a, chk);
		float trim = 1.0 - aa(0.04, min(min(df.x, 1.0 - df.x), min(df.y, 1.0 - df.y)));
		col = mix(col, c2.rgb, trim);
		metal = trim * 0.8;
		vec2 fq = p2 * 0.18; vec2 fid = floor(fq); vec2 ff = fract(fq) - 0.5;
		float laugh = 0.5 + 0.5 * sin(t * (2.0 + 7.0 * inspect));
		float fd = face(ff * 1.05, 1.0, laugh * (1.0 + ch));
		float on = step(0.4, h2(fid));
		float fl = (1.0 - aa(0.0, fd)) * on;
		col = mix(col, vec3(0.95, 0.92, 0.85), (1.0 - aa(0.0, length(ff * vec2(1.0, 0.82)) - 0.42)) * on * 0.85);  // a white clown face
		col = mix(col, vec3(0.04), fl);
		glow = c2.rgb * trim * 0.25 + c1.rgb * fl * (0.8 + inspect * 2.0);
		float conf = step(0.992 - 0.004 * ch - 0.01 * inspect, h1(floor(lp * 6.0) + floor(t * 6.0)));
		glow += hsv(h1(floor(lp * 6.0)), 0.9, 1.0) * conf * 2.5;
		rough = 0.35; gloss = 0.15;
	}
	// the challenge version's accent along the pattern's edges (simple camos)
	if (kind < 13) { col = mix(col, accent.rgb, clamp(edge, 0.0, 1.0) * ch * 0.9); }
	// paint grain so it reads as paint, not flat colour; a little relief in the coat
	col *= 0.94 + 0.06 * vn(lp * 25.0);
	NORMAL = normalize(NORMAL + (vec3(vn(lp * 18.0), vn(lp * 18.0 + 3.1), vn(lp * 18.0 + 6.7)) - 0.5) * 0.08);
	if (relief_k > 0.0) {  // bump from the painted height (surface gradient from screen derivatives, no UVs needed)
		vec3 dpx = dFdx(VERTEX); vec3 dpy = dFdy(VERTEX);
		vec3 r1 = cross(dpy, NORMAL); vec3 r2 = cross(NORMAL, dpx);
		float det = dot(dpx, r1);
		vec3 grad = sign(det) * (dFdx(relief) * r1 + dFdy(relief) * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad * relief_k);
	}
	// hard edges rubbed through first (the face normal jumps there)
	float hard = smoothstep(0.08, 0.5, length(fwidth(ln)));
	float rub = hard * smoothstep(0.25, 0.75, fbm(lp * 0.9 + 60.0) + wear * 0.8) * (kind >= 20 && kind <= 24 ? 0.3 : 1.0);
	// wear: chips and scratches down to bare metal (more on long faces' edges of the pattern noise)
	float scr = fbm(lp * vec3(3.0, 11.0, 3.0));
	float chip = fbm(lp * 1.9 + 40.0);
	float worn = aa(1.0 - wear * 0.5, scr) + aa(1.0 - wear * 0.32, chip) + rub * (0.35 + wear);
	worn = clamp(worn, 0.0, 1.0);
	vec3 bare = studio(rv) * vec3(0.45, 0.46, 0.48) * 0.8 + vec3(0.12);
	col = mix(col, bare, worn);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.35, worn);
	METALLIC = metal;
	EMISSION = glow * (1.0 - worn) + studio(rv) * (gloss * (0.08 + fres * 0.6)) * (1.0 - worn);
}
"""

static var _shader: Shader
static var _cache := {}  # key -> material for camos that do not react
static var _cfg := {}  # data/camos.json, read on first use
static var _by_id := {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/camos.json"))
		for look: Dictionary in _cfg.get("camos", []):
			_by_id[String(look["id"])] = look
	return _cfg


static func look_of(id: String) -> Dictionary:
	cfg()
	return _by_id.get(id, {})


# A rolled gun's camo on its model (gun["camo"] = {"id", "wear", "seed", "challenge"}): the material, or null when the
# gun wears none (then nothing is changed).
static func dress(model: Node, gun: Dictionary) -> ShaderMaterial:
	var camo: Dictionary = gun.get("camo", {}) if gun.get("camo") is Dictionary else {}
	var look := look_of(String(camo.get("id", "")))
	if look.is_empty():
		clear(model)  # (a camo it wore before comes off)
		return null
	return apply(model, camo, look)


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	return _shader


# Kinds that move with the player's actions (each gun gets its own material, fed by react()).
static func reactive(look: Dictionary) -> bool:
	return String(look.get("tier", "")) in ["gold", "pony"] or String(look.get("kind", "")) in ["zebra", "polka"]


# The material for a camo: `camo` = the gun's {"id", "wear", "seed", "challenge"}, `look` = its row of data/camos.json.
# `hold` = the gun model's hold scale (models are built at different sizes), so a pattern is the same size on every gun.
static func material(camo: Dictionary, look: Dictionary, hold: float = 1.0) -> ShaderMaterial:
	var key := "%s|%.2f|%d|%s|%.2f" % [String(look.get("id", "")), float(camo.get("wear", 0.1)), int(camo.get("seed", 1)), str(camo.get("challenge", false)), hold]
	if not reactive(look) and _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	mat.set_shader_parameter("kind", maxi(KINDS.find(String(look.get("kind", "blobs"))), 0))
	var cols: Array = look.get("colors", [])
	for i in mini(cols.size(), 4):
		mat.set_shader_parameter("c%d" % i, Color(String(cols[i])))
	mat.set_shader_parameter("accent", Color(String(look.get("accent", "#ffffff"))))
	mat.set_shader_parameter("challenge", 1.0 if bool(camo.get("challenge", false)) else 0.0)
	mat.set_shader_parameter("wear", clampf(float(camo.get("wear", 0.1)), 0.0, 1.0))
	mat.set_shader_parameter("seed", float(int(camo.get("seed", 1)) % 1000) * 0.731)
	mat.set_shader_parameter("size", hold)
	if not reactive(look):
		_cache[key] = mat
	return mat


# Puts the camo on every mesh of the gun model (not props, lenses, glows, maker bands, the W kills plate). Returns the
# material (reactive camos: feed it with react()).
static func apply(model: Node, camo: Dictionary, look: Dictionary) -> ShaderMaterial:
	var mat := material(camo, look, (model as Node3D).scale.x if model is Node3D else 1.0)
	_put(model, mat)
	_gun_space(model, mat)
	var main := _biggest(model)  # the main body gets its own copy: faces and the serpent are laid out from its size
	if model is Node3D:
		_add_fx(model as Node3D, main, look)
	if main == null:
		return mat
	var box := main.mesh.get_aabb()
	var own := mat.duplicate() as ShaderMaterial
	own.set_shader_parameter("body", 1.0)
	own.set_shader_parameter("mid", box.get_center())
	own.set_shader_parameter("ext", box.size * 0.5)
	own.set_meta("pair", mat)
	for i in main.mesh.get_surface_count():
		if main.get_surface_override_material(i) == mat:
			main.set_surface_override_material(i, own)
	return own


# (polish1 item 145) Tells every camo'd mesh where it sits in the whole gun (instance uniforms gx / gy / gz / gmid /
# gext / gon), so a pattern can span the gun's parts: the serpent's board, the galaxy's spiral.
static func _gun_space(model: Node, mat: ShaderMaterial) -> void:
	var meshes: Array = []
	var box := AABB()
	var first := true
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		if mi.mesh == null:
			continue
		var uses := false
		for i in mi.mesh.get_surface_count():
			uses = uses or mi.get_surface_override_material(i) == mat
		if not uses:
			continue
		var place := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != model:
			if walk is Node3D:
				place = (walk as Node3D).transform * place
			walk = walk.get_parent()
		meshes.append([mi, place])
		var b := place * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	for pair: Array in meshes:
		var mi: MeshInstance3D = pair[0]
		var t: Transform3D = pair[1]
		mi.set_instance_shader_parameter("gx", Vector4(t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x))
		mi.set_instance_shader_parameter("gy", Vector4(t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y))
		mi.set_instance_shader_parameter("gz", Vector4(t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z))
		mi.set_instance_shader_parameter("gmid", box.get_center())
		mi.set_instance_shader_parameter("gext", box.size * 0.5)
		mi.set_instance_shader_parameter("gon", 1.0)


# Particles on the gun for the moving camos (embers, sparkles, smoke, motes, pixels, void wisps, confetti): [colour
# index or -1 for many colours, amount, lifetime, upward speed, size, additive]. In world space so they trail the gun.
const FX := {"diamond": [2, 18, 0.9, 0.02, 0.02, true], "phantom": [3, 30, 1.8, 0.12, 0.09, true], "galaxy": [2, 14, 1.5, 0.0, 0.018, true],
	"oni": [2, 24, 1.1, 0.35, 0.022, true], "coral": [3, 22, 2.4, 0.12, 0.02, true], "glitch": [1, 20, 0.35, 0.0, 0.02, true],
	"serpent": [2, 10, 1.4, 0.05, 0.04, true], "carnival": [-1, 30, 1.6, -0.15, 0.016, false]}


static func _add_fx(model: Node3D, main: MeshInstance3D, look: Dictionary) -> void:
	var old := model.get_node_or_null("CamoFx")
	if old != null:
		old.queue_free()
	var row: Array = FX.get(String(look.get("kind", "")), [])
	if row.is_empty() or main == null:
		return
	var box := main.mesh.get_aabb()
	var fx := CPUParticles3D.new()
	fx.name = "CamoFx"
	fx.local_coords = false
	fx.amount = int(row[1])
	fx.lifetime = float(row[2])
	fx.preprocess = float(row[2])
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fx.emission_box_extents = box.size * 0.5 * main.scale
	fx.position = main.position + box.get_center() * main.scale
	fx.direction = Vector3.UP
	fx.spread = 180.0
	fx.initial_velocity_min = 0.0
	fx.initial_velocity_max = 0.06
	fx.gravity = Vector3(0.0, float(row[3]), 0.0)
	fx.scale_amount_min = 0.6
	fx.scale_amount_max = 1.4
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.2, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	fx.scale_amount_curve = fade
	var cols: Array = look.get("colors", [])
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(row[4]) * 0.5  # world metres (held guns sit right in front of the eye)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	if bool(row[5]):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if String(look.get("kind", "")) not in ["glitch", "carnival"]:  # soft round dots (glitch pixels and confetti stay square)
		mat.albedo_texture = _soft_dot()
	quad.material = mat
	fx.mesh = quad
	if int(row[0]) < 0:  # confetti: every colour
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color(1, 0.2, 0.2), Color(1, 0.85, 0.2), Color(0.2, 1, 0.4), Color(0.3, 0.6, 1), Color(1, 0.3, 0.9)])
		ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		fx.color_initial_ramp = ramp
		fx.angular_velocity_min = -360.0
		fx.angular_velocity_max = 360.0
	else:
		var c := Color(String(cols[int(row[0])])) if int(row[0]) < cols.size() else Color.WHITE
		fx.color = Color(c.r, c.g, c.b, 0.55 if not bool(row[5]) else 1.0)
	model.add_child(fx)


static var _dot: GradientTexture2D


static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 32
		_dot.height = 32
	return _dot


static func _biggest(node: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var most := 0.0
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var m := found as MeshInstance3D
		if m.mesh == null:
			continue
		var v := m.mesh.get_aabb().get_volume()
		if v > most:
			most = v
			best = m
	return best


static func clear(model: Node) -> void:
	_put(model, null)
	var fx := model.get_node_or_null("CamoFx")
	if fx != null:
		fx.queue_free()


static func _put(node: Node, mat: ShaderMaterial) -> void:
	for word: String in SKIP:
		if String(node.name).contains(word):
			return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.material_override is ShaderMaterial and (mesh_node.material_override as ShaderMaterial).shader == _shader:
			mesh_node.material_override = null  # (an older camo / test override)
		if mesh_node.mesh != null:
			for i in mesh_node.mesh.get_surface_count():
				var own := mesh_node.mesh.surface_get_material(i)
				var named := own.resource_name.to_lower() if own != null else ""
				var bare := false
				for word: String in BARE:
					bare = bare or named.begins_with(word)
				mesh_node.set_surface_override_material(i, null if (mat == null or bare) else mat)
			if mat != null and mesh_node.material_override != null:
				mesh_node.material_override = null  # the tier's skin gives way to the camo
	for c in node.get_children():
		_put(c, mat)


# Feeds a reactive camo what the player is doing (0..1 each; shoot / reload / kill are short pulses that fade).
static func react(mat: ShaderMaterial, aim: float, speed: float, shoot: float, reload: float, kill: float, ammo: float, inspect: float) -> void:
	if mat == null:
		return
	if mat.has_meta("pair"):
		react(mat.get_meta("pair") as ShaderMaterial, aim, speed, shoot, reload, kill, ammo, inspect)
	mat.set_shader_parameter("aim", aim)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("shoot", shoot)
	mat.set_shader_parameter("reload", reload)
	mat.set_shader_parameter("kill", kill)
	mat.set_shader_parameter("ammo", ammo)
	mat.set_shader_parameter("inspect", inspect)


# "Field-Tested" for a wear value.
static func wear_name(wear: float) -> String:
	for row: Array in cfg().get("wear_names", []):
		if wear <= float(row[0]):
			return String(row[1])
	return "Battle-Scarred"
