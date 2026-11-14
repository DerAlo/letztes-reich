shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Stadtkulisse bei Nacht (funkturm): Wandtextur (Ziegel/Putz/Plattenbau-Beton) plus prozedurales Fensterraster.
// Jedes Fenster bekommt per Hash einen Zustand: dunkel (Glas, spiegelt matt), Vorhang, oder beleuchtet
// (warmes Gluehlampenlicht, vereinzelt kaltes Fernsehlicht, unterschiedlich hell). Ausgangssperre: nur wenige
// Fenster brennen, ganze Haeuser bleiben dunkel (Stromsperre). In der Ferne wird das Raster zum Mittelwert
// gefiltert, damit nichts flimmert.
//
// Vertexdaten (siehe funkturm_city.gd):
//   UV     Fassadenkoordinate in Metern (u entlang der Wand ab der linken Kante, v = Hoehe ueber Grund)
//   UV2    x = Zufallswert des Gebaeudes, y = Hoehe der Traufe (Wand); y < 0: Dach/Attika/Aufbau (keine Fenster)
//   COLOR  rgb = Farbton, a = Typ / 8 (0 Altbau Ziegel, 1 Altbau Putz, 2 Plattenbau, 3 Buero, 4 Halle)
// world_mode: Fassadenkoordinate aus der Weltposition (achsparallele Waende, z. B. Messehallen). Typ, Farbton
// und ein Fensterband (band_lo..band_hi) kommen dann aus Uniforms.

uniform sampler2D tex_brick : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_plaster : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_concrete : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_panel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float lit_ratio = 0.16;
uniform float emission_energy = 1.1;
uniform vec4 warm_a : source_color = vec4(1.0, 0.56, 0.24, 1.0);
uniform vec4 warm_b : source_color = vec4(1.0, 0.74, 0.46, 1.0);
uniform vec4 cool : source_color = vec4(0.55, 0.68, 1.0, 1.0);
uniform bool world_mode = false;
uniform float w_kind = 4.0;
uniform vec4 w_tint : source_color = vec4(1.0);
uniform float w_seed = 0.37;
uniform float band_lo = 6.4;
uniform float band_hi = 8.6;
uniform float base_y = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

void fragment() {
	vec3 n = normalize(wnrm);
	vec2 uv;
	float seed;
	float top;
	int kind;
	vec3 tint;
	if (world_mode) {
		float along = abs(n.z) > abs(n.x) ? wpos.x * sign(n.z) : -wpos.z * sign(n.x);
		uv = vec2(along, wpos.y - base_y);
		seed = w_seed;
		top = abs(n.y) > 0.5 ? -1.0 : band_hi;
		kind = int(w_kind + 0.5);
		tint = w_tint.rgb;
	} else {
		uv = UV;
		seed = UV2.x;
		top = UV2.y;
		kind = int(COLOR.a * 8.0 + 0.5);
		tint = COLOR.rgb;
	}

	// ---------------------------------------------------------------- Wand
	vec3 alb;
	float tex_s;
	if (kind == 0) {
		tex_s = 0.42;
		alb = texture(tex_brick, uv * tex_s).rgb;
	} else if (kind == 1) {
		tex_s = 0.28;
		alb = texture(tex_plaster, uv * tex_s).rgb;
	} else if (kind == 4) {
		tex_s = 0.25;
		alb = texture(tex_panel, uv * tex_s).rgb;
	} else {
		tex_s = 0.2;
		alb = texture(tex_concrete, uv * tex_s).rgb;
	}
	alb *= tint;
	// grossflaechige Verwitterung + Schlieren unter den Fenstern
	float big = texture(noise_tex, uv * 0.013 + seed * 7.0).r;
	float streak = texture(noise_tex, vec2(uv.x * 0.6, uv.y * 0.02) + seed * 3.0).r;
	alb *= 0.8 + big * 0.4;
	alb *= mix(1.0, 0.72, smoothstep(0.58, 0.8, streak));
	// Sockel dunkler (Spritzwasser, Strassenschmutz)
	alb *= mix(0.6, 1.0, smoothstep(0.0, 2.5, uv.y));
	float rough = 0.9;
	float spec = 0.35;
	vec3 emit = vec3(0.0);

	if (top < 0.0) {
		// Dach, Attika, Aufbauten: Bitumen/Beton, dunkler
		alb *= (top < -1.5) ? 0.75 : 0.45;
		ALBEDO = alb;
		ROUGHNESS = 0.95;
		SPECULAR = 0.3;
		EMISSION = vec3(0.0);
	} else {
		// ------------------------------------------------------------ Fensterraster je Typ
		vec2 cellsz;   // Achsabstand, Geschosshoehe
		vec2 wlo;      // Fenster-Unterkante/-Linkskante (Anteil der Zelle)
		vec2 whi;
		float ground = 0.0;   // Erdgeschosshoehe ohne Wohnfenster
		float lr = lit_ratio;
		if (kind <= 1) {
			cellsz = vec2(2.6, 3.4); wlo = vec2(0.27, 0.24); whi = vec2(0.73, 0.8); ground = 3.4;
		} else if (kind == 2) {
			cellsz = vec2(3.6, 2.8); wlo = vec2(0.2, 0.3); whi = vec2(0.72, 0.82); ground = 0.0;
		} else if (kind == 3) {
			cellsz = vec2(1.8, 3.6); wlo = vec2(0.06, 0.32); whi = vec2(0.94, 0.86); ground = 3.6; lr *= 0.5;
		} else {
			cellsz = vec2(1.6, band_hi - band_lo); wlo = vec2(0.05, 0.0); whi = vec2(0.95, 1.0); ground = band_lo; lr = 0.55;
		}
		vec2 cf = (uv - vec2(0.0, ground)) / cellsz;
		vec2 cell = floor(cf);
		vec2 f = fract(cf);
		vec2 fw = fwidth(cf) * 0.75;
		float in_band = step(ground, uv.y) * step(uv.y, top - (kind == 4 ? 0.0 : 1.3));
		if (kind == 4) {
			in_band *= step(uv.y, band_hi);
		}
		float mask = box_aa(f, wlo, whi, fw) * in_band;
		// Fensterbank/Sturz: helles Band direkt unter dem Fenster (Altbau, Plattenbau)
		float sill = box_aa(f, vec2(wlo.x - 0.03, wlo.y - 0.05), vec2(whi.x + 0.03, wlo.y), fw) * in_band;
		if (kind <= 2) {
			alb = mix(alb, alb * 1.35 + 0.02, sill * 0.7);
		}
		// Zustand des Fensters
		float bseed = floor(seed * 9973.0);
		float bld_lit = smoothstep(0.08, 0.5, fract(seed * 13.7)) * 1.6;   // manche Haeuser stockdunkel
		vec2 grp = vec2(floor(cell.x / 2.0), cell.y);                       // Wohnungen: 2 Fenster gleich
		float r_on = h21(grp + bseed * 0.37);
		float r_col = h21(grp * 1.7 + bseed);
		float r_win = h21(cell + bseed * 1.3);
		float on = step(r_on, lr * bld_lit);
		if (kind == 4) {
			on = step(r_on, lr);
		}
		vec3 lc = mix(warm_a.rgb, warm_b.rgb, r_col);
		if (r_col > 0.86) {
			lc = cool.rgb * 0.55;   // Fernseher / Leuchtstoff
		}
		float inten = mix(0.25, 1.0, r_win * r_win) * (0.75 + 0.25 * r_col);
		// Vorhang/Jalousie: senkrechter Verlauf im Fenster
		float curtain = mix(1.0, 0.55 + 0.45 * smoothstep(0.0, 1.0, (f.y - wlo.y) / (whi.y - wlo.y)), step(0.5, r_win));
		vec3 glass_alb = vec3(0.025, 0.027, 0.03) + vec3(0.04, 0.035, 0.03) * step(0.62, r_win);   // Vorhang hell
		vec3 win_emit = lc * inten * curtain * on * emission_energy;
		// Ferne: Raster ausfiltern (mittlere Helligkeit statt Flimmern)
		float far = smoothstep(0.35, 0.9, max(fw.x, fw.y) * 1.333);
		float area = (whi.x - wlo.x) * (whi.y - wlo.y);
		vec3 avg_emit = mix(warm_a.rgb, warm_b.rgb, 0.5) * 0.55 * lr * (kind == 4 ? 1.0 : bld_lit) * area * emission_energy * in_band;
		emit = mix(win_emit * mask, avg_emit, far);
		alb = mix(alb, glass_alb, mix(mask, area * in_band, far));
		rough = mix(rough, 0.18, mask * (1.0 - far));
		spec = mix(spec, 0.6, mask * (1.0 - far));
		ALBEDO = alb;
		ROUGHNESS = rough;
		SPECULAR = spec;
		EMISSION = emit;
	}
	METALLIC = 0.0;
}
