shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Fensterscheibe mit Interior Mapping: hinter jeder Scheibe wird ein Raum (Rueckwand, Seitenwaende,
// Boden, Decke, Moebel-Silhouetten) per Strahlschnitt in eine virtuelle Box gezeichnet. Vorhaenge
// oder Jalousien je nach Zufallswert, Licht an/aus mit warm/kalt-Variation, zerbrochene Scheiben
// (nur Scherben am Rand, keine Spiegelung). Die Scheibe selbst spiegelt ueber Fresnel/SSR.
//
// Vertexdaten (siehe facade_kit.gd WindowBatch):
//   UV     0..1 ueber die Scheibe (v = 0 unten)
//   UV2    Scheibengroesse in Metern (Breite, Hoehe)
//   COLOR  r = Lichtstaerke, g = Waerme (1 warm, 0 kalt), b = Zufallswert, a = zerbrochen (1)

uniform float interior_ambient = 0.1;     // Grundhelligkeit dunkler Raeume (Tag hoeher als Nacht)
uniform float lamp_energy = 2.2;
uniform vec4 warm_color : source_color = vec4(1.0, 0.7, 0.42, 1.0);
uniform vec4 cool_color : source_color = vec4(0.72, 0.84, 1.0, 1.0);
uniform float glass_rough = 0.05;
uniform float dirt = 0.5;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vdata;
varying vec2 vsize;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vdata = COLOR;
	vsize = UV2;
}

float h11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 n = normalize(wnrm);
	// Bei cull_disabled von innen gesehen: nichts Sinnvolles, einfach dunkel
	vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), n));
	float W = max(vsize.x, 0.2);
	float H = max(vsize.y, 0.2);
	float seed = vdata.b;
	float light = vdata.r;
	float broken = vdata.a;
	vec2 uv = UV;

	vec3 v = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 d = vec3(dot(v, t), v.y, dot(v, -n));
	d.z = max(d.z, 0.02);
	vec3 p0 = vec3(uv.x * W, uv.y * H, 0.0);

	// Raumabmessungen aus dem Zufallswert
	float mx = 0.5 + h11(seed + 0.1) * 1.1;
	float sill = 0.9;
	float top = 0.35 + h11(seed + 0.2) * 0.25;
	float D = 3.0 + h11(seed + 0.3) * 2.5;
	float x0 = -mx;
	float x1 = W + mx;
	float y0 = -sill;
	float y1 = H + top;
	float tx = d.x > 0.0 ? (x1 - p0.x) / d.x : (x0 - p0.x) / min(d.x, -1e-4);
	float ty = d.y > 0.0 ? (y1 - p0.y) / d.y : (y0 - p0.y) / min(d.y, -1e-4);
	float tz = (D - p0.z) / d.z;
	float th = min(tx, min(ty, tz));
	vec3 hp = p0 + d * th;

	// Raumfarben
	float s1 = h11(seed + 1.7);
	vec3 wallc = mix(vec3(0.56, 0.5, 0.41), vec3(0.4, 0.43, 0.46), s1);
	wallc = mix(wallc, vec3(0.42, 0.46, 0.38), step(0.8, h11(seed + 2.3)));
	vec3 floorc = mix(vec3(0.17, 0.11, 0.07), vec3(0.24, 0.23, 0.22), step(0.6, h11(seed + 3.1)));
	vec3 ceilc = vec3(0.62, 0.6, 0.57);
	vec3 col;
	float face_shade;
	vec2 fuv;   // Koordinate auf der getroffenen Flaeche fuer Kantenabdunklung
	vec2 fsz;
	if (th == tz) {
		col = wallc;
		face_shade = 0.85;
		fuv = vec2(hp.x - x0, hp.y - y0);
		fsz = vec2(x1 - x0, y1 - y0);
		// Moebel an der Rueckwand: Schrank/Sofa, Bild, Tuer
		float fx = x0 + h11(seed + 4.0) * (x1 - x0) * 0.6;
		float fw = 0.8 + h11(seed + 4.5) * 1.4;
		float fh = 0.5 + h11(seed + 5.0) * 1.4;
		if (hp.x > fx && hp.x < fx + fw && hp.y < y0 + fh) {
			col = mix(vec3(0.08, 0.06, 0.05), vec3(0.2, 0.18, 0.16), h11(seed + 5.5));
		}
		float px = x0 + 0.3 + h11(seed + 6.0) * (x1 - x0 - 1.2);
		if (hp.x > px && hp.x < px + 0.6 && hp.y > y0 + 1.5 && hp.y < y0 + 1.95 && h11(seed + 6.5) > 0.4) {
			col = vec3(0.12, 0.1, 0.08) + vec3(0.25, 0.2, 0.15) * h11(seed + 7.0);
		}
		float dx = x1 - 1.1 - h11(seed + 7.5) * 0.6;
		if (h11(seed + 8.0) > 0.55 && hp.x > dx && hp.x < dx + 0.9 && hp.y < y0 + 2.1) {
			col *= 0.25;   // offene Tuer in einen dunklen Flur
		}
	} else if (th == ty) {
		if (d.y < 0.0) {
			col = floorc;
			face_shade = 0.65;
			// Teppich
			if (abs(hp.x - W * 0.5) < W * 0.4 && hp.z > 1.0 && hp.z < D - 0.6 && h11(seed + 9.0) > 0.5) {
				col = mix(vec3(0.3, 0.1, 0.08), vec3(0.15, 0.17, 0.24), h11(seed + 9.5));
			}
		} else {
			col = ceilc;
			face_shade = 1.0;
		}
		fuv = vec2(hp.x - x0, hp.z);
		fsz = vec2(x1 - x0, D);
	} else {
		col = wallc * 0.92;
		face_shade = 0.75;
		fuv = vec2(hp.z, hp.y - y0);
		fsz = vec2(D, y1 - y0);
		// Regal/Schrank an der Seitenwand
		float sz0 = 0.6 + h11(seed + 10.0) * (D - 2.0);
		if (h11(seed + 10.5) > 0.45 && hp.z > sz0 && hp.z < sz0 + 1.0 && hp.y < y0 + 1.9) {
			col = vec3(0.1, 0.075, 0.06);
		}
	}
	// Kantenabdunklung (Ecken)
	vec2 e = min(fuv, fsz - fuv);
	float edge = smoothstep(0.0, 0.7, min(e.x, e.y));
	col *= face_shade * mix(0.45, 1.0, edge);

	// Licht: Deckenleuchte in Raummitte, Abfall mit Abstand
	float warm = vdata.g;
	vec3 lc = mix(cool_color.rgb, warm_color.rgb, warm);
	vec3 lpos = vec3(W * 0.5, y1 - 0.2, D * 0.5);
	float ld = length(hp - lpos);
	float lamp = light * lamp_energy / (1.0 + ld * ld * 0.22);
	// Tiefe: hinten dunkler (weniger Tageslicht)
	float depth_fall = exp(-hp.z * 0.32);
	vec3 interior = col * (interior_ambient * (0.35 + 0.65 * depth_fall) + lc * lamp);
	if (broken > 0.5) {
		interior *= 0.35;   // ausgebrannt/verrusst
	}

	// Vorhaenge/Jalousien kurz hinter der Scheibe
	float ctype = h11(seed + 11.0);
	float cz = 0.12;
	vec3 cp = p0 + d * (cz / d.z);
	float cu = cp.x / W;
	float cv = cp.y / H;
	if (broken < 0.5 && cu > -0.2 && cu < 1.2 && cv > -0.1 && cv < 1.1) {
		vec3 ccol = mix(vec3(0.5, 0.42, 0.32), vec3(0.35, 0.12, 0.1), step(0.6, h11(seed + 12.0)));
		ccol = mix(ccol, vec3(0.55, 0.55, 0.52), step(0.82, h11(seed + 12.5)));
		float cover = 0.0;
		if (ctype < 0.4) {
			float cl = 0.12 + h11(seed + 13.0) * 0.3;
			float cr = 0.12 + h11(seed + 13.5) * 0.3;
			cover = step(cu, cl) + step(1.0 - cr, cu);
			if (h11(seed + 14.0) > 0.75) {
				cover = 1.0;   // ganz zugezogen
			}
			float fold = 0.75 + 0.25 * sin(cu * W * 26.0 + seed * 40.0);
			ccol *= fold;
		} else if (ctype < 0.62) {
			float down = 0.2 + h11(seed + 15.0) * 0.75;
			cover = step(1.0 - down, cv);
			float slat = 0.7 + 0.3 * step(0.5, fract(cv * H * 12.0));
			ccol = vec3(0.6, 0.58, 0.54) * slat;
		}
		cover = clamp(cover, 0.0, 1.0);
		vec3 cl_col = ccol * (interior_ambient * 0.9 + lc * light * lamp_energy * 0.32);
		interior = mix(interior, cl_col, cover);
		// Gardine (halbtransparent) bei einigen Fenstern
		if (ctype > 0.82) {
			vec3 sheer = vec3(0.7, 0.68, 0.64) * (interior_ambient * 1.2 + lc * light * lamp_energy * 0.25);
			interior = mix(interior, sheer, 0.55);
		}
	}

	// Glas: Schmutz, leichte Unebenheit, zerbrochene Scheiben
	vec2 pm = vec2(uv.x * W, uv.y * H);
	float gn = vnoise(pm * 3.0 + seed * 31.0);
	float rough = glass_rough + dirt * gn * 0.16 + dirt * (1.0 - smoothstep(0.0, 0.35, pm.y)) * 0.15;
	float spec = 0.5;
	vec3 alb = vec3(0.012, 0.014, 0.016);
	float em_mul = 1.0;
	if (broken > 0.5) {
		// Scherbenrand: zackiger Abstand vom Rahmen
		float ed = min(min(pm.x, W - pm.x), min(pm.y, H - pm.y));
		float ang = atan(pm.y - H * 0.5, pm.x - W * 0.5);
		float jag = 0.04 + 0.32 * vnoise(vec2(ang * 3.5 + seed * 17.0, seed * 5.0)) * vnoise(vec2(ang * 11.0, seed * 3.0) + 2.0);
		if (ed < jag) {
			rough = 0.08 + gn * 0.1;
			alb = vec3(0.02);
			em_mul = 0.6;
		} else {
			rough = 1.0;
			spec = 0.0;
			alb = vec3(0.0);
		}
	}
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = spec;
	EMISSION = interior * em_mul;
}
