shader_type spatial;
// Ausruestung der realistischen Gegner-Soldaten (soldier_mh_gear.gd), ohne UVs:
//   COLOR.rgb = Grundfarbe (linear), COLOR.a * 15 = Materialcode (siehe MAT_* in soldier_mh_gear.gd)
//   VERTEX    = Ruhepose-Raum (Meter) -> Gewebe/MOLLE/Tarnmuster haften an der Ausruestung
//   CUSTOM0   = (Abstand zur Kante, Laenge entlang der Kante, 1 = Naht vorhanden) fuer Naehte/Einfassung
// Feine Struktur (Gewebe, MOLLE-Gurtreihen, Strickrippen, Naehte, Lackkoernung) als Hoehenfeld,
// per Bildschirm-Ableitung in Normalen umgerechnet (bump mapping ohne Tangenten), mit Distanz-Ausblendung.
render_mode cull_back, depth_draw_opaque;

uniform sampler2D weave_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D camo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_camo = false;
uniform float camo_scale = 2.4;
uniform vec3 camo_mul : source_color = vec3(1.0);
uniform float paint_metal = 0.0;
uniform float paint_rough = 0.62;
uniform float bump_strength = 1.0;
uniform float wear = 0.5;

varying vec3 v_p;
varying vec3 v_n;
varying vec3 v_seam;

void vertex() {
	v_p = VERTEX;
	v_n = NORMAL;
	v_seam = CUSTOM0.xyz;
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

float tri_tex(vec3 p, vec3 w) {
	return texture(weave_tex, p.zy).r * w.x + texture(weave_tex, p.xz).r * w.y + texture(weave_tex, p.xy).r * w.z;
}

vec3 tri_camo(vec3 p, vec3 w) {
	return texture(camo_tex, p.zy).rgb * w.x + texture(camo_tex, p.xz).rgb * w.y + texture(camo_tex, p.xy).rgb * w.z;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	// billiges Wertrauschen (2 Ebenen gemischt) fuer Abnutzung/Schmutz
	vec2 a = p.xy + p.z * 0.71;
	vec2 i = floor(a);
	vec2 f = fract(a);
	f = f * f * (3.0 - 2.0 * f);
	float n00 = hash12(i);
	float n10 = hash12(i + vec2(1.0, 0.0));
	float n01 = hash12(i + vec2(0.0, 1.0));
	float n11 = hash12(i + vec2(1.0, 1.0));
	return mix(mix(n00, n10, f.x), mix(n01, n11, f.x), f.y);
}

void fragment() {
	int code = int(round(COLOR.a * 15.0));
	vec3 n = normalize(v_n);
	vec3 w = tri_w(n);
	vec3 p = v_p;
	vec3 base = COLOR.rgb;
	float h = 0.0;          // Hoehe in Metern (positiv = nach aussen)
	float rough = 0.85;
	float metal = 0.0;
	float spec = 0.4;
	float shade = 1.0;
	// Fein-Gewebe (Leinen-Karte als Hoehe), Massstab ~ 4 cm je Kachel
	float wv = tri_tex(p * 24.0, w);
	// Pixelgroesse in Metern -> feine Strukturen ausblenden, bevor sie flimmern
	float px = length(fwidth(p));
	float fine = 1.0 - smoothstep(0.0012, 0.004, px);
	float mid = 1.0 - smoothstep(0.004, 0.012, px);
	// grossflaechige Abnutzung
	float lf = vnoise(p * 9.0) * 0.6 + vnoise(p * 23.0) * 0.4;

	bool molle = code == 3 || code == 10;
	bool nylon = code == 2 || code == 3 || code == 9 || code == 10;
	if ((code == 9 || code == 10) && use_camo) {
		base = tri_camo(p * camo_scale, w) * camo_mul;
	}
	if (nylon) {
		h += (wv - 0.5) * 0.0006 * fine;
		shade *= 0.9 + 0.2 * wv;
		rough = 0.86;
		shade *= 0.92 + 0.16 * lf;
	}
	if (molle && abs(n.y) < 0.65) {
		// PALS: 25 mm Gurtband, Reihen alle 50 mm, Riegel alle 38 mm
		float u = abs(n.z) > abs(n.x) ? p.x : p.z;
		float rv = fract(p.y / 0.05 + 0.25);
		float band = smoothstep(0.02, 0.06, rv) * (1.0 - smoothstep(0.46, 0.5, rv));
		float bt = smoothstep(0.86, 0.92, abs(fract(u / 0.038) - 0.5) * 2.0);
		h += band * 0.0014 * mid;
		h -= band * bt * 0.0007 * mid;
		// Gurtband: Laengsrippen, etwas dunkler und glatter
		float rib = sin(p.y * 6.2832 / 0.0016) * 0.5 + 0.5;
		h += band * rib * 0.00015 * fine;
		shade *= mix(1.0, 0.82 - 0.08 * bt, band * mid);
		shade *= 1.0 - (1.0 - band) * 0.12 * mid;   // Spalt zwischen den Reihen im Schatten
		rough = mix(rough, 0.72, band);
	}
	if (code == 4) {
		// Gurtband/Riemen: Rippen quer zur Laufrichtung (unbekannt) -> zwei Richtungen leicht gemischt
		float rib = sin((p.x + p.y + p.z) * 6.2832 / 0.0018) * 0.5 + 0.5;
		h += rib * 0.0002 * fine + (wv - 0.5) * 0.0003 * fine;
		shade *= 0.88 + 0.12 * wv;
		rough = 0.74;
	} else if (code == 5) {
		// Strick: senkrechte Maschenrippen (Umfangsrichtung aus der Normalen)
		float u = abs(n.z) > abs(n.x) ? p.x : p.z;
		float rib = abs(sin(u * 6.2832 / 0.0045));
		float st = abs(sin(p.y * 6.2832 / 0.003 + rib));
		h += (rib * 0.00028 + st * 0.00012) * fine;
		shade *= 0.95 + 0.06 * rib * fine + 0.08 * (wv - 0.5);
		rough = 0.97;
	} else if (code == 6) {
		// Jute: faserig, sehr rau
		float fib = tri_tex(p * vec3(60.0, 6.0, 60.0), w);
		h += (fib - 0.5) * 0.0012 * mid;
		shade *= 0.75 + 0.5 * fib;
		rough = 1.0;
	} else if (code == 0) {
		// Lack mit feiner Koernung (Helmschale), Kanten abgegriffen
		h += (wv - 0.5) * 0.00025 * fine;
		shade *= 0.93 + 0.1 * lf;
		rough = paint_rough * (0.9 + 0.2 * lf);
		metal = paint_metal;
		spec = 0.5;
	} else if (code == 1) {
		rough = 0.5;
		spec = 0.5;
		shade *= 0.95 + 0.1 * wv;
	} else if (code == 7) {
		rough = 0.82;
		spec = 0.35;
		h += (wv - 0.5) * 0.0002 * fine;
	} else if (code == 8) {
		rough = 0.06;
		metal = 0.6;
		spec = 0.9;
	} else if (code == 11) {
		rough = 0.38;
		spec = 0.55;
		h += (wv - 0.5) * 0.0002 * fine;
		shade *= 0.92 + 0.12 * lf;
	} else if (code == 12) {
		h += (wv - 0.5) * 0.0003 * fine;
		shade *= 0.9 + 0.14 * wv;
		rough = 0.95;
	} else if (code == 13) {
		rough = 0.3;
		metal = 0.85;
		spec = 0.6;
	}
	// Naehte und Kanteneinfassung (nur Stoffteile mit Kantendaten)
	if (v_seam.z > 0.5 && (nylon || code == 5 || code == 12)) {
		float d = v_seam.x;
		float bind = 1.0 - smoothstep(0.003, 0.0045, d);
		float sl = 1.0 - smoothstep(0.00035, 0.0008, abs(d - 0.0065));
		float dash = smoothstep(0.25, 0.4, fract(v_seam.y / 0.0042)) * (1.0 - smoothstep(0.75, 0.9, fract(v_seam.y / 0.0042)));
		h -= sl * 0.00045 * fine;
		h += sl * dash * 0.00035 * fine;
		shade *= 1.0 - bind * 0.12 * mid;
		shade *= 1.0 - sl * (1.0 - dash) * 0.25 * mid;
		h += bind * 0.0003 * mid;
	}
	// Kanten heller (Abrieb) auf Lack, Taschen unten etwas schmutziger
	float dirt = (1.0 - smoothstep(0.85, 1.2, p.y)) * 0.25 * wear * lf;
	vec3 alb = base * shade;
	alb = mix(alb, vec3(0.2, 0.17, 0.12) * shade, clamp(dirt, 0.0, 1.0));

	// Bildschirm-Ableitungs-Bump (Mikkelsen 2010)
	float hh = h * bump_strength * (1.0 - smoothstep(6.0, 18.0, -VERTEX.z));
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 N = normalize(NORMAL);
	vec3 r1 = cross(dpdy, N);
	vec3 r2 = cross(N, dpdx);
	float det = dot(dpdx, r1);
	float dhx = dFdx(hh);
	float dhy = dFdy(hh);
	vec3 g = sign(det) * (dhx * r1 + dhy * r2);
	if (abs(det) > 1e-14) {
		NORMAL = normalize(abs(det) * N - g);
	}
	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metal;
	SPECULAR = spec;
}
