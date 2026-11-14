shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Fernkulisse bei Tag/Daemmerung (far_city.gd): Wandtextur (PBR, Normalmap) plus prozedurales Fensterraster.
// Jedes Fenster hat eine Laibung (Parallaxe: die Scheibe sitzt ~0,25 m hinter der Wand, die Laibung wird je nach
// Blickwinkel sichtbar), Rahmen und Sprossen, Fensterbank und je nach Zufall Vorhang, Jalousie, dunklen Raum
// mit Rueckwand, Licht oder (bei Schaden) ausgebranntes Loch mit Russfahne darueber. Die Scheibe spiegelt
// (glatt, Fresnel) -> Fenster lesen sich nicht als schwarze Loecher. In der Ferne wird das Raster zum Mittelwert
// gefiltert, damit nichts flimmert.
//
// Vertexdaten (siehe far_city.gd):
//   UV       Fassadenkoordinate in Metern (u entlang der Wand, 0 = Wandmitte; -v = Hoehe ueber Gebaeudefuss)
//   UV2      x = halbe Breite der Fensterzone, y = Wandhoehe (Traufe) ueber dem Fuss
//   COLOR    rgb = Farbton der Wand (Dach: Dachfarbe), a = Typ / 16 (siehe KIND in far_city.gd)
//   CUSTOM0  x = Zufallswert des Gebaeudes, y = Bauteil (0 Wand, 1 Gesims/Attika, 2 Dach, 3 Sockel),
//            z = Schaden 0..1, w = Lichtfaktor

uniform sampler2D wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.3;            // Kacheln pro Meter
uniform float normal_strength = 0.9;
uniform float rough_mul = 1.0;
uniform float lit_ratio = 0.06;           // Anteil beleuchteter Fenster
uniform float emission_energy = 1.3;
uniform vec4 warm_a : source_color = vec4(1.0, 0.62, 0.3, 1.0);
uniform vec4 warm_b : source_color = vec4(1.0, 0.8, 0.55, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.62, 0.66, 0.74, 1.0);   // Grundfarbe der Spiegelung (Himmel/Gegenueber)
uniform float reflect_amt = 0.22;
uniform float reveal_depth = 0.26;        // Laibungstiefe in Metern
uniform float grime = 1.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 cdata;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cdata = CUSTOM0;
}

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Rechteckmaske mit Kantenglaettung ueber die Bildschirmableitung
float box_aa(vec2 f, vec2 lo, vec2 hi, vec2 fw) {
	vec2 a = smoothstep(lo - fw, lo + fw, f);
	vec2 b = 1.0 - smoothstep(hi - fw, hi + fw, f);
	return a.x * a.y * b.x * b.y;
}

float band(float x, float c, float w, float fw) {
	return 1.0 - smoothstep(w * 0.5 - fw, w * 0.5 + fw, abs(x - c));
}

void fragment() {
	vec2 uv = vec2(UV.x, -UV.y);   // Mesh-UV.y zeigt nach unten (Bildkonvention), Fassade nach oben
	int kind = int(COLOR.a * 16.0 + 0.5);
	float seed = cdata.x;
	int part = int(cdata.y + 0.5);
	float dmg = cdata.z;
	float litk = cdata.w;
	vec3 n = normalize(wnrm);

	// ---------------------------------------------------------------- Wand-/Dachtextur
	vec2 tuv = UV * tex_scale + vec2(seed * 3.7, 0.0);
	vec3 alb = texture(wall_albedo, tuv).rgb;
	vec3 arm = texture(wall_arm, tuv).rgb;
	vec3 nm = texture(wall_normal, tuv).rgb;
	float rough = clamp(arm.g * rough_mul, 0.05, 1.0);
	float ao = arm.r;
	float spec = 0.4;
	vec3 emit = vec3(0.0);
	float nstr = normal_strength;

	if (part == 2) {
		// Dach: Bitumen/Blech, dunkel und matt
		float l = dot(alb, vec3(0.333));
		alb = COLOR.rgb * (0.55 + l * 0.9);
		rough = 0.88;
	} else {
		alb *= COLOR.rgb;
		if (part == 1) {
			alb *= 1.12;            // Gesimse/Attika: heller (Werkstein, frischer verwittert)
		} else if (part == 3) {
			alb *= 0.72;            // Sockel dunkler
		}
	}

	// grossflaechige Verwitterung + Schlieren
	float big = texture(noise_tex, uv * 0.013 + seed * 7.0).r;
	float streak = texture(noise_tex, vec2(uv.x * 0.6, uv.y * 0.02) + seed * 3.0).r;
	alb *= 0.84 + big * 0.32;
	if (part != 2) {
		alb *= mix(1.0, 0.74, smoothstep(0.6, 0.82, streak) * grime);
		// Sockelzone: Spritzwasser, Strassenschmutz
		alb *= mix(0.62, 1.0, smoothstep(0.0, 2.4, uv.y + (big - 0.5) * 0.8));
		// Kriegsschaeden: Russflaechen
		if (dmg > 0.0) {
			float sn = texture(noise_tex, uv * 0.045 + seed * 5.0).r;
			float sm = smoothstep(1.0 - dmg * 0.55, 1.12 - dmg * 0.55, sn);
			alb = mix(alb, vec3(0.035, 0.032, 0.03), sm * 0.85);
		}
	}

	float top = UV2.y;
	float hw = UV2.x;
	if (part == 0 && top > 0.0 && kind != 6) {
		// ------------------------------------------------------------ Fensterraster je Typ
		vec2 cs;           // Achsabstand, Geschosshoehe
		vec2 lo; vec2 hi;  // Fensteroeffnung als Anteil der Zelle
		float ground = 0.0;
		vec2 glo = vec2(0.12, 0.2); vec2 ghi = vec2(0.88, 0.86);   // Erdgeschoss (Laden/Tor)
		int style = 0;     // 0 Kreuzstock, 1 Einscheibe, 2 Plattenbau (Kippfluegel), 3 Sprossenraster (Halle)
		vec3 frame = vec3(0.86, 0.85, 0.8);
		float fr_h = h21(vec2(seed * 31.0, 7.0));
		if (kind == 0 || kind == 1) {
			cs = vec2(2.7, 3.6); lo = vec2(0.27, 0.2); hi = vec2(0.73, 0.8); ground = 4.4;
			frame = fr_h < 0.45 ? vec3(0.84, 0.82, 0.76) : (fr_h < 0.75 ? vec3(0.3, 0.22, 0.16) : vec3(0.2, 0.24, 0.2));
		} else if (kind == 2) {
			cs = vec2(3.0, 2.8); lo = vec2(0.2, 0.3); hi = vec2(0.8, 0.82); style = 2;
			frame = vec3(0.82, 0.82, 0.8);
		} else if (kind == 3) {
			cs = vec2(1.5, 3.7); lo = vec2(0.05, 0.3); hi = vec2(0.95, 0.94); ground = 4.6; style = 1;
			frame = vec3(0.16, 0.17, 0.18);
		} else if (kind == 4) {
			cs = vec2(1.6, min(5.0, top * 0.4)); lo = vec2(0.06, 0.04); hi = vec2(0.94, 0.96); style = 3;
			ground = max(top - cs.y - 1.6, 1.0);
			frame = vec3(0.2, 0.22, 0.22);
		} else {
			cs = vec2(3.4, 5.4); lo = vec2(0.3, 0.18); hi = vec2(0.7, 0.8); ground = 6.0;
			glo = vec2(0.32, 0.28); ghi = vec2(0.68, 0.74);
			frame = fr_h < 0.5 ? vec3(0.18, 0.22, 0.18) : vec3(0.32, 0.26, 0.2);
		}
		float nfl = floor((top - ground - 0.9) / cs.y);
		if (kind == 4) nfl = 1.0;
		bool is_ground = uv.y < ground && kind != 4 && kind != 2;
		vec2 cell_sz = is_ground ? vec2(cs.x, ground) : cs;
		float y0 = is_ground ? 0.0 : ground;
		vec2 wlo = is_ground ? glo : lo;
		vec2 whi = is_ground ? ghi : hi;
		vec2 cf = vec2(uv.x / cell_sz.x, (uv.y - y0) / cell_sz.y);
		vec2 cell = floor(cf);
		vec2 f = cf - cell;
		vec2 fw = fwidth(cf);
		float far_k = smoothstep(0.12, 0.4, max(fw.x, fw.y));   // Raster unter ~3 px -> Mittelwert
		vec2 fwa = fw * 0.75;
		float zone = step(abs(uv.x), hw) * step(cell.y, nfl - 1.0) * step(0.0, cell.y);
		if (is_ground) zone = step(abs(uv.x), hw);
		if (uv.y < y0) zone = 0.0;
		float bseed = floor(seed * 9973.0);
		float r_win = h21(cell + bseed * 1.3 + (is_ground ? 50.0 : 0.0));
		float r_st = h21(cell * 1.7 + bseed + 11.0);
		// Erdgeschoss: manche Achsen sind Hauseingaenge/Tore (hoeher, schmaler) oder vernagelt
		if (is_ground && kind <= 1 && r_win < 0.25) { wlo = vec2(0.3, 0.0); whi = vec2(0.7, 0.72); }
		vec2 sz = (whi - wlo) * cell_sz;   // Oeffnung in Metern

		// Laibung: Parallaxe der Scheibenebene
		vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
		vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), n));
		float vn = max(dot(vw, n), 0.18);
		vec2 par = -vec2(dot(vw, t), vw.y) / vn * reveal_depth;
		vec2 fg = f + par / cell_sz;
		float m_open = box_aa(f, wlo, whi, fwa) * zone;
		float m_glass = box_aa(fg, wlo, whi, fwa);
		// Fensterbank und Sturz (Altbau/Palais: Werkstein-Faschen + Verdachung)
		float surround = 0.0;
		if ((kind <= 1 || kind == 5) && !is_ground) {
			vec2 e = vec2(0.09) / cell_sz;
			surround = box_aa(f, wlo - e, whi + e, fwa) * (1.0 - box_aa(f, wlo, whi, fwa));
			surround += box_aa(f, vec2(wlo.x - 0.06, whi.y + e.y), vec2(whi.x + 0.06, whi.y + e.y * 2.6), fwa);
			surround = clamp(surround, 0.0, 1.0) * zone;
		}
		float sill = box_aa(f, vec2(wlo.x - 0.04, wlo.y - 0.045), vec2(whi.x + 0.04, wlo.y), fwa) * zone;
		if (kind == 2) {
			// Plattenbau: Fugen zwischen den Platten
			vec2 cf2 = vec2(uv.x / cs.x + 0.5, uv.y / cs.y);
			vec2 g = abs(fract(cf2) - 0.5);
			float joint = (1.0 - smoothstep(0.49 - fw.x, 0.495, g.x)) * (1.0 - smoothstep(0.49 - fw.y, 0.495, g.y));
			alb *= mix(0.7, 1.0, joint);
		}
		if (kind == 3 && !is_ground) {
			// Buerobau: Bruestungsbaender (glatte Paneele)
			float sp = (1.0 - step(lo.y, f.y)) * zone;
			alb = mix(alb, alb * 0.82 + vec3(0.03), sp * 0.6);
		}
		if (kind == 5) {
			// Palais: Pilaster zwischen den Achsen (heller) und Rustika-Fugen im Sockelgeschoss
			float pil = band(f.x, 0.0, 0.16, fwa.x) + band(f.x, 1.0, 0.16, fwa.x);
			alb = mix(alb, alb * 1.14, pil * step(ground, uv.y) * step(abs(uv.x), hw));
			if (uv.y < ground) {
				float rf = abs(fract(uv.y / 0.62) - 0.5);
				alb *= mix(0.62, 1.0, smoothstep(0.43, 0.38, rf));
			}
		}
		alb = mix(alb, alb * 1.25 + vec3(0.03), surround * 0.75);
		alb = mix(alb, alb * 1.3 + vec3(0.04), sill * 0.8);

		// Zustand des Fensters
		float burned = step(1.0 - dmg * 0.5, r_win);          // ausgebrannt: kein Glas, Russ darueber
		float boarded = step(0.93, r_st) * step(0.2, dmg) * (1.0 - burned);
		float lit = step(r_st, lit_ratio * litk) * (1.0 - burned);
		float curtain = step(0.42, r_st) * step(r_st, 0.74);
		float blind = step(0.74, r_st) * step(r_st, 0.88);
		// Raum hinter der Scheibe: Rueckwand (zweite Parallaxe), Boden dunkler, Decke etwas heller
		vec2 rf = f + par * (3.2 / reveal_depth) / cell_sz;
		float back = box_aa(rf, wlo + 0.08, whi - 0.08, fwa);
		float rh = clamp((fg.y - wlo.y) / max(whi.y - wlo.y, 0.01), 0.0, 1.0);
		vec3 room = mix(vec3(0.07, 0.065, 0.06), vec3(0.15, 0.14, 0.125), back) * (0.75 + rh * 0.45);
		room *= 0.8 + h21(cell + 3.0 + bseed) * 0.5;
		vec3 pane = room;
		float p_rough = 0.05 + h21(cell * 2.3 + bseed) * 0.14;
		if (curtain > 0.5) {
			float folds = 0.82 + 0.18 * sin(fg.x * cell_sz.x * 18.0 + r_win * 6.0);
			vec3 cc = mix(vec3(0.66, 0.62, 0.54), vec3(0.5, 0.46, 0.4), h21(cell + 9.0 + bseed));
			float cov = smoothstep(0.25, 0.35, abs(fg.x - (wlo.x + whi.x) * 0.5) / max(whi.x - wlo.x, 0.01) + h21(cell + 4.0) * 0.4);
			pane = mix(pane, cc * folds * 0.75, cov);
		} else if (blind > 0.5) {
			float slat = 0.75 + 0.25 * step(0.5, fract(fg.y * cell_sz.y * 9.0));
			float bl_h = mix(0.3, 1.0, h21(cell + 6.0 + bseed));
			pane = mix(pane, vec3(0.55, 0.55, 0.52) * slat * 0.8, step(1.0 - bl_h, rh));
		}
		if (lit > 0.5) {
			vec3 lc = mix(warm_a.rgb, warm_b.rgb, h21(cell * 3.1 + bseed));
			emit = lc * emission_energy * (0.55 + 0.45 * back) * (0.6 + 0.4 * h21(cell + 21.0));
			pane = mix(pane, lc * 0.5, 0.5);
		}
		// Rahmen + Sprossen (auf der Glasebene)
		vec2 rel = (fg - wlo) / max(whi - wlo, vec2(0.01));
		vec2 relm = rel * sz;    // Meter innerhalb der Oeffnung
		vec2 fwm = fwidth(relm) * 0.75;
		float fr_w = 0.065;
		float fmask = 1.0 - box_aa(relm, vec2(fr_w), sz - fr_w, fwm);
		if (style == 0) {
			fmask = max(fmask, band(relm.x, sz.x * 0.5, 0.07, fwm.x));
			fmask = max(fmask, band(relm.y, sz.y * 0.72, 0.07, fwm.y));
			if (is_ground && r_win >= 0.25) {
				fmask = max(fmask, band(relm.y, sz.y * 0.8, 0.09, fwm.y));
			}
		} else if (style == 2) {
			fmask = max(fmask, band(relm.x, sz.x * 0.62, 0.07, fwm.x));
		} else if (style == 3) {
			fmask = max(fmask, band(fract(relm.x / 0.4), 0.5, 0.06 / 0.4 * 2.0, fwm.x / 0.4));
			fmask = max(fmask, band(fract(relm.y / 0.5), 0.5, 0.05 / 0.5 * 2.0, fwm.y / 0.5));
		} else {
			fmask = max(fmask, band(relm.y, sz.y * 0.82, 0.06, fwm.y));
		}
		// Spiegelung: Himmel/Gegenueber, abhaengig vom Blickwinkel (Fresnel) und je Scheibe leicht verschieden
		float fres = pow(1.0 - clamp(dot(vw, n), 0.0, 1.0), 4.0);
		float rv = h21(cell * 5.7 + bseed);
		vec3 refl = sky_tint.rgb * (0.55 + rv * 0.6) * (reflect_amt + fres * 0.6);
		refl *= mix(1.0, 0.75, smoothstep(0.3, 0.9, rh));   // oben verschattet (Sturz/Rolladenkasten)
		vec3 glass = pane + refl;
		if (burned > 0.5) {
			glass = vec3(0.045, 0.038, 0.032) * (0.7 + back * 0.6);   // verkohlter Raum, kein Glas
			fmask *= step(0.6, h21(cell + 13.0));                    // Rahmen meist weggebrannt
			p_rough = 0.95;
			emit *= 0.0;
		}
		if (boarded > 0.5) {
			glass = vec3(0.3, 0.24, 0.17) * (0.8 + 0.2 * step(0.5, fract(relm.y * 3.0)));
			p_rough = 0.9;
		}
		vec3 win = mix(glass, frame, fmask * (1.0 - boarded));
		float win_rough = mix(p_rough, 0.6, fmask);
		// Laibung: Wandfarbe, oben verschattet, unten (Bank) heller
		vec3 rev = alb * (fg.y < wlo.y ? 0.95 : (fg.y > whi.y ? 0.42 : 0.62));
		vec3 open_col = mix(rev, win, m_glass);
		// Russfahne ueber ausgebrannten Fenstern (eigene Zelle und darueber)
		float r_below = h21(cell - vec2(0.0, 1.0) + bseed * 1.3);
		float burned_below = step(1.0 - dmg * 0.5, r_below) * (is_ground ? 0.0 : step(1.0, cell.y));
		float plume_here = burned * smoothstep(whi.y - 0.05, whi.y + 0.05, f.y) * (1.0 - smoothstep(whi.y, 1.0, f.y) * 0.4);
		float plume_up = burned_below * (1.0 - smoothstep(0.0, 0.7, f.y));
		float pn = texture(noise_tex, vec2(uv.x * 0.9, uv.y * 0.35) + seed).r;
		float wx = 1.0 - smoothstep(0.1, 0.32 + pn * 0.1, abs(f.x - 0.5));
		float plume = clamp(plume_here + plume_up, 0.0, 1.0) * wx * zone * smoothstep(0.25, 0.6, pn + 0.2);
		alb = mix(alb, vec3(0.03, 0.028, 0.026), plume * 0.85);
		// Mittelwert in der Ferne
		float cover = (whi.x - wlo.x) * (whi.y - wlo.y);
		vec3 avg_win = mix(vec3(0.16, 0.16, 0.17) + sky_tint.rgb * reflect_amt * 0.8, vec3(0.05), dmg * 0.4);
		float wm = mix(m_open, cover * zone, far_k);
		vec3 wcol = mix(open_col, avg_win, far_k);
		alb = mix(alb, wcol, wm);
		rough = mix(rough, mix(win_rough, 0.3, far_k), wm * m_glass);
		spec = mix(spec, 0.75, wm * m_glass * (1.0 - burned));
		nstr = mix(nstr, 0.0, m_open);
		ao = mix(ao, 1.0, wm);
		emit *= m_open * m_glass * (1.0 - far_k * 0.5);
		emit += warm_a.rgb * emission_energy * 0.25 * lit_ratio * litk * cover * zone * far_k;
	}

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.2;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = nstr;
	EMISSION = emit;
}
