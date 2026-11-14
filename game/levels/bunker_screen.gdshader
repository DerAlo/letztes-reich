shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Bildschirme im Regierungsbunker (bunker.gd, _screen()): Glasfront mit echtem Glanz (lit, dunkles Albedo),
// Bildinhalt nur als gedaempfte Emission. Kein flaches Leuchtrechteck mehr, sondern Phosphor-Inhalt:
//   mode 0 Lagekarte (Gitter, Hoehenlinien, Spree, Einheitsmarker)
//   mode 1 Statustext (Kopfzeile, scrollende Zeichenzeilen, Balkenanzeige, Cursor)
//   mode 2 Radar (Ringe, Fadenkreuz, Sweep mit Nachleuchten, Echos)
//   mode 3 Alarm/Zuendung (Warnstreifen, blinkender 7-Segment-Countdown, Warnzeilen)
//   mode 4 Papier-Lagekarte (Kartentisch, nicht leuchtend)
// Allen Leuchtmodi gemeinsam: Zeilenraster, Rauschen, Flimmern, Vignette (Roehrenrand).

uniform int mode = 0;
uniform vec3 tint : source_color = vec3(0.35, 1.0, 0.55);
uniform float energy = 1.0;
instance uniform float seed = 0.0;
instance uniform float aspect = 1.6;   // Breite / Hoehe der Bildflaeche
// Papierstruktur (ambientCG Paper003, CC0) fuer mode 4: Knitter-Normalen, Rauheit, leichte Faserung
uniform sampler2D paper_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D paper_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paper_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool paper_textured = false;
uniform float paper_tiles = 2.0;   // Wiederholungen der Papierstruktur ueber die Hoehe der Flaeche

float h11(float p) { return fract(sin(p * 127.1 + 311.7) * 43758.5453); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Antialiasierte Linie bei d == 0 (d in UV-Einheiten, w = halbe Breite in Pixeln)
float aline(float d, float w) {
	float fw = max(fwidth(d), 1e-5);
	return 1.0 - smoothstep(w * fw, (w + 1.0) * fw, abs(d));
}

float box(vec2 p, vec2 lo, vec2 hi) {
	vec2 fw = max(fwidth(p), vec2(1e-5));
	vec2 a = smoothstep(lo - fw, lo + fw, p) * (1.0 - smoothstep(hi - fw, hi + fw, p));
	return a.x * a.y;
}

// Pseudo-Schrift: Zeichenraster 3x5 Punkte je Zeichen, zufaellige Glyphen, Woerter mit Luecken.
// p: Position in Zeichenzellen (x = Spalte, y = Zeile), len: Zeilenlaenge in Zeichen
float glyphs(vec2 p, float row_id, float len) {
	float col = floor(p.x);
	if (col < 0.0 || col >= len) return 0.0;
	float word = h21(vec2(floor(col / 6.0), row_id));
	if (mod(col, 6.0) > 3.0 + floor(word * 3.0)) return 0.0;   // Wortabstand
	vec2 c = fract(p);
	vec2 cell = floor(vec2(c.x * 4.0, c.y * 7.0));   // 3x5 Punkte + Rand
	if (cell.x > 2.0 || cell.y < 1.0 || cell.y > 5.0) return 0.0;
	float bit = h21(vec2(col * 7.0 + cell.x + row_id * 31.0, cell.y + seed * 13.0));
	return step(0.42, bit);
}

// 7-Segment-Ziffer in q (0..1 x 0..1, y nach oben)
float seg7(vec2 q, int d) {
	// Segmente a b c d e f g als Bitmaske
	int m = 0;
	if (d == 0) m = 63; else if (d == 1) m = 6; else if (d == 2) m = 91; else if (d == 3) m = 79;
	else if (d == 4) m = 102; else if (d == 5) m = 109; else if (d == 6) m = 125; else if (d == 7) m = 7;
	else if (d == 8) m = 127; else m = 111;
	float t = 0.11;
	float v = 0.0;
	// waagrecht: a (oben), g (mitte), d (unten)
	if ((m & 1) != 0) v = max(v, box(q, vec2(0.15, 0.9 - t), vec2(0.85, 0.9)));
	if ((m & 64) != 0) v = max(v, box(q, vec2(0.15, 0.5 - t * 0.5), vec2(0.85, 0.5 + t * 0.5)));
	if ((m & 8) != 0) v = max(v, box(q, vec2(0.15, 0.1), vec2(0.85, 0.1 + t)));
	// senkrecht: f (oben links), b (oben rechts), e (unten links), c (unten rechts)
	if ((m & 32) != 0) v = max(v, box(q, vec2(0.1, 0.52), vec2(0.1 + t, 0.88)));
	if ((m & 2) != 0) v = max(v, box(q, vec2(0.9 - t, 0.52), vec2(0.9, 0.88)));
	if ((m & 16) != 0) v = max(v, box(q, vec2(0.1, 0.12), vec2(0.1 + t, 0.48)));
	if ((m & 4) != 0) v = max(v, box(q, vec2(0.9 - t, 0.12), vec2(0.9, 0.48)));
	return v;
}

float text_block(vec2 uv, float rows, float x0, float x1, float y0, float y1, float scroll) {
	if (uv.x < x0 || uv.x > x1 || uv.y < y0 || uv.y > y1) return 0.0;
	float rh = (y1 - y0) / rows;
	float cw = rh * 0.62 / aspect;
	vec2 p = vec2((uv.x - x0) / cw, (uv.y - y0) / rh);
	float row = floor(p.y);
	float rid = row + scroll + seed * 17.0;
	float len = floor(mix(6.0, (x1 - x0) / cw, h11(rid * 3.1)));
	return glyphs(vec2(p.x, fract(p.y) + 0.0), rid, len);
}

vec3 content_map(vec2 uv, vec2 sp) {
	// sp: Bildkoordinaten mit Seitenverhaeltnis (x 0..aspect, y 0..1)
	float v = 0.0;
	vec2 g = sp * 8.0;
	v += 0.18 * max(aline(fract(g.x + 0.5) - 0.5, 0.4), aline(fract(g.y + 0.5) - 0.5, 0.4));
	vec2 np = sp * 2.2 + vec2(seed * 3.7, seed * 1.3);
	float n = fbm(np);
	v += 0.28 * aline(fract(n * 9.0) - 0.5, 0.5) * step(0.38, n);
	// Fluss (Spree): gewundenes Band
	float ry = 0.45 + 0.16 * sin(sp.x * 3.1 + seed * 5.0) + 0.06 * sin(sp.x * 9.0 + 1.0);
	v += 0.55 * aline(sp.y - ry, 1.4);
	// Strassen
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float a = h11(seed * 7.0 + fi) * 3.14;
		vec2 o = vec2(h11(fi + seed) * aspect, h11(fi * 2.3 + seed));
		vec2 d = vec2(cos(a), sin(a));
		v += 0.22 * aline(dot(sp - o, vec2(-d.y, d.x)), 0.6);
	}
	// Einheitsmarker: Quadrate (eigene), Rauten (Gegner, blinkend)
	float mk = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i) + seed * 11.0;
		vec2 c = vec2(0.12 + 0.76 * h11(fi * 1.7) * aspect, 0.12 + 0.76 * h11(fi * 2.9));
		vec2 q = abs(sp - c);
		float s = 0.022;
		float sq = box(q, vec2(s * 0.75), vec2(s)) + box(q, vec2(0.0), vec2(s * 0.35));
		float di = aline(q.x + q.y - s * 1.2, 0.8) * step(0.5, fract(TIME * 0.8 + h11(fi)));
		mk += i < 4 ? sq : di;
	}
	v += mk;
	// Kopfzeile
	v += 0.9 * text_block(uv, 1.0, 0.03, 0.6, 0.03, 0.085, 0.0);
	v += 0.5 * box(uv, vec2(0.0, 0.1), vec2(1.0, 0.105));
	return vec3(v);
}

vec3 content_text(vec2 uv) {
	float v = 0.0;
	// invertierte Kopfzeile
	float head = box(uv, vec2(0.02, 0.03), vec2(0.98, 0.11));
	float ht = text_block(uv, 1.0, 0.04, 0.7, 0.045, 0.1, 0.0);
	v += head * (0.75 - ht * 0.7);
	float scroll = floor(TIME * 0.7 + seed * 5.0);
	v += 0.85 * text_block(uv, 9.0, 0.04, 0.66, 0.16, 0.92, scroll);
	// Balkenanzeige rechts (Last/Spannung), leicht schwankend
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float x0 = 0.72 + fi * 0.065;
		float lvl = 0.35 + 0.45 * h11(fi + seed * 3.0) + 0.05 * sin(TIME * (1.0 + fi) + seed * 9.0);
		v += 0.12 * box(uv, vec2(x0, 0.2), vec2(x0 + 0.045, 0.9));
		v += 0.7 * box(uv, vec2(x0 + 0.005, 0.9 - lvl * 0.68), vec2(x0 + 0.04, 0.895));
	}
	// Cursor
	float cy = 0.16 + (0.76 / 9.0) * 8.0;
	v += step(0.5, fract(TIME * 1.1)) * box(uv, vec2(0.04, cy + 0.01), vec2(0.06, cy + 0.075));
	return vec3(v);
}

vec3 content_radar(vec2 uv, vec2 sp) {
	vec2 c = vec2(aspect * 0.36, 0.5);
	vec2 d = sp - c;
	float r = length(d) / 0.44;
	float v = 0.0;
	if (r < 1.0) {
		for (int i = 1; i <= 4; i++) {
			v += 0.25 * aline(r - float(i) * 0.25, 0.4);
		}
		v += 0.2 * (aline(d.x, 0.4) + aline(d.y, 0.4));
		float ang = atan(d.y, d.x);
		float sweep = mod(TIME * 1.3 + seed * 6.0, 6.28318);
		float lag = mod(sweep - ang, 6.28318);
		v += 0.55 * exp(-lag * 2.2) * (1.0 - r * 0.3);
		// Echos: leuchten nach, wenn der Sweep vorbeikommt
		for (int i = 0; i < 6; i++) {
			float fi = float(i) + seed * 7.0;
			float ba = h11(fi * 1.3) * 6.28318;
			float br = 0.2 + 0.7 * h11(fi * 2.1);
			vec2 bp = c + vec2(cos(ba), sin(ba)) * br * 0.44;
			float bl = mod(sweep - ba, 6.28318);
			v += 1.2 * exp(-bl * 1.1) * (1.0 - smoothstep(0.006, 0.014, length(sp - bp)));
		}
	}
	v += 0.9 * aline(r - 1.0, 0.7);
	// Datenspalte rechts
	v += 0.75 * text_block(uv, 7.0, 0.76, 0.97, 0.12, 0.85, floor(TIME * 0.4 + seed));
	return vec3(v);
}

vec3 content_alarm(vec2 uv, vec2 sp) {
	float v = 0.0;
	float blink = step(0.45, fract(TIME * 0.9));
	// Warnstreifen oben und unten
	float stripe = step(0.5, fract((sp.x + sp.y) * 7.0 - TIME * 0.4));
	float band = box(uv, vec2(0.02, 0.03), vec2(0.98, 0.13)) + box(uv, vec2(0.02, 0.87), vec2(0.98, 0.97));
	v += band * stripe * 0.6;
	// Rahmen um den Countdown
	vec2 lo = vec2(0.18, 0.24);
	vec2 hi = vec2(0.82, 0.66);
	float frame = box(uv, lo, hi) - box(uv, lo + vec2(0.012, 0.02), hi - vec2(0.012, 0.02));
	v += 0.7 * frame;
	// Countdown 00:47 (Zuendleitung gekappt: Zaehler steht und blinkt)
	vec2 q = (uv - vec2(0.24, 0.28)) / vec2(0.52, 0.34);
	if (q.x > 0.0 && q.x < 1.0 && q.y > 0.0 && q.y < 1.0) {
		float cx = q.x * 4.6;
		int idx = int(floor(cx));
		vec2 dq = vec2(fract(cx), 1.0 - q.y);
		int dig = idx == 0 ? 0 : (idx == 1 ? 0 : (idx == 3 ? 4 : 7));
		float on = 0.0;
		if (idx == 2) {
			on = box(dq, vec2(0.4, 0.25), vec2(0.6, 0.35)) + box(dq, vec2(0.4, 0.65), vec2(0.6, 0.75));
		} else if (idx <= 4) {
			on = seg7(dq, dig);
		}
		v += on * (0.35 + 0.85 * blink);
		v += 0.05 * seg7(dq, 8) * float(idx != 2);   // abgedunkelte Segmente
	}
	v += 0.8 * text_block(uv, 2.0, 0.18, 0.82, 0.7, 0.83, 0.0);
	return vec3(v);
}

vec3 content_paper(vec2 uv, vec2 sp) {
	// Papier-Lagekarte: helles Papier, Gitter, Hoehenlinien, Fluss blau, rote Eintragungen
	float n = fbm(sp * 2.0 + vec2(seed * 2.0));
	vec3 paper = vec3(0.62, 0.62, 0.55) * (0.92 + 0.08 * vnoise(sp * 60.0));
	vec3 c = paper;
	vec2 g = sp * 6.0;
	float grid = max(aline(fract(g.x + 0.5) - 0.5, 0.3), aline(fract(g.y + 0.5) - 0.5, 0.3));
	c = mix(c, vec3(0.3, 0.32, 0.3), grid * 0.35);
	c = mix(c, vec3(0.45, 0.36, 0.25), aline(fract(n * 8.0) - 0.5, 0.4) * 0.5);
	float ry = 0.5 + 0.18 * sin(sp.x * 2.4 + 0.7) + 0.05 * sin(sp.x * 8.0);
	c = mix(c, vec3(0.2, 0.32, 0.45), aline(sp.y - ry, 2.5) * 0.8);
	return c;
}

void fragment() {
	vec2 uv = UV;
	vec2 sp = vec2(uv.x * aspect, uv.y);
	if (mode == 4) {
		vec3 alb = content_paper(uv, sp);
		ROUGHNESS = 0.85;
		SPECULAR = 0.3;
		if (paper_textured) {
			vec2 tuv = sp * paper_tiles;
			vec3 pt = texture(paper_albedo, tuv).rgb;
			float lum = dot(pt, vec3(0.333));
			alb *= clamp(pt / max(lum, 0.05), 0.85, 1.15) * (0.82 + 0.3 * lum);
			NORMAL_MAP = texture(paper_normal, tuv).rgb;
			NORMAL_MAP_DEPTH = 0.8;
			ROUGHNESS = clamp(0.78 + 0.25 * texture(paper_rough, tuv).r, 0.82, 1.0);   // mattes Papier, kein Glanzfleck unter der Deckenlampe
			SPECULAR = 0.2;
		}
		ALBEDO = alb;
	} else {
		vec3 c;
		if (mode == 0) c = content_map(uv, sp);
		else if (mode == 1) c = content_text(uv);
		else if (mode == 2) c = content_radar(uv, sp);
		else c = content_alarm(uv, sp);
		float v = clamp(c.r, 0.0, 1.4);
		// Phosphor: Grundschleier, Zeilenraster, Rauschen, Flimmern, Roehrenrand
		float lines = 0.8 + 0.2 * sin(uv.y * 900.0);
		float grain = 0.85 + 0.3 * h21(floor(uv * vec2(420.0 * aspect, 420.0)) + floor(TIME * 24.0));
		float flick = 0.96 + 0.04 * sin(TIME * 37.0 + seed * 10.0);
		vec2 e = uv * (1.0 - uv);
		float vig = clamp(pow(e.x * e.y * 18.0, 0.35), 0.0, 1.0);
		float roll = 0.06 * exp(-pow(fract(uv.y - TIME * 0.07 + seed) - 0.5, 2.0) * 300.0);
		vec3 em = tint * (0.035 + v * 0.75 + roll) * lines * grain * flick * vig;
		ALBEDO = vec3(0.012, 0.014, 0.014);
		ROUGHNESS = 0.16;
		SPECULAR = 0.5;
		EMISSION = em * energy;
	}
}
