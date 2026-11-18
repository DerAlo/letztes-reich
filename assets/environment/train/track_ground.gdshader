shader_type spatial;
// Boden entlang der Nachtzug-Strecke (scrollt mit "scroll" unter dem stehenden Zug durch):
//  - Felder in 130-m-Kacheln mit unterschiedlicher Schneedecke: geschlossen, lueckig (Furchen/Altgras
//    schauen durch) oder fast frei; Poly-Haven-Texturen snow_02 (Schnee) und gravel_stones (Schotter), CC0.
//  - Gleisbett: Schotter mit Schneeresten, Schwellen alle 0.65 m, Randweg.
//  - Fahrtunschaerfe: Texturabtastung per textureGrad mit verlaengertem Fussabdruck in Fahrtrichtung
//    (blur 0..1 ~ Tempo), Schwellen-Streifen verwischen; sonst flimmern Schwellen/Schotter bei 33 m/s.

uniform float scroll = 0.0;
uniform float blur = 0.0;
uniform sampler2D snow_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ballast_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ballast_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 snow_tint : source_color = vec3(0.36, 0.37, 0.4);
uniform vec3 grass_col : source_color = vec3(0.16, 0.135, 0.085);   // Altgras (trocken, nachts)
uniform vec3 soil_col : source_color = vec3(0.075, 0.062, 0.05);
uniform float track2_x = -4.4;

varying vec3 wp;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vn(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(mod(i, per));
	float b = h21(mod(i + vec2(1.0, 0.0), per));
	float c = h21(mod(i + vec2(0.0, 1.0), per));
	float d = h21(mod(i + vec2(1.0, 1.0), per));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Textur mit Bewegungsunschaerfe in v (= Fahrtrichtung): Fussabdruck um k * blur verlaengert
vec4 tg(sampler2D t, vec2 uv, float k) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 b = vec2(0.0, blur * k);
	return textureGrad(t, uv, dx + b, dy + b);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wp.x, wp.z - scroll);
	// --- Felder
	vec2 cell = floor(p / 130.0);
	vec2 cm = mod(cell, 110.0);
	float h = h21(cm + 0.37);
	float cover = 0.35 + 0.6 * h21(cm + 4.1);              // Schneedecke je Feld
	float dirsel = step(0.5, h21(cm + 1.7));
	float furrow = sin((dirsel > 0.5 ? p.x : p.y) * 6.2832 / 1.3) * (h > 0.4 ? 1.0 : 0.15);
	float n1 = vn(p / 13.0, 1100.0);
	float n2 = vn(p / 2.6, 5500.0);
	float n3 = vn(p / 0.7, 20000.0);
	vec2 uv_s = p * 0.22;
	vec3 snow = tg(snow_alb, uv_s, 0.12).rgb * snow_tint * 2.2;
	vec3 grass = grass_col * (0.65 + 0.7 * n2) * (0.85 + 0.3 * n3);
	vec3 soil = soil_col * (0.8 + 0.4 * n2);
	vec3 bare = mix(grass, soil, smoothstep(0.3, 0.7, h21(cm + 9.3)) * (0.5 + 0.5 * furrow));
	// Schnee bleibt in den Furchen und Mulden, Grashorste/Kaemme schauen durch
	float sm = n1 * 0.55 + n2 * 0.3 + n3 * 0.15 - furrow * 0.12 * (1.0 - blur);
	float snow_w = smoothstep(1.0 - cover - 0.08, 1.0 - cover + 0.08, sm);
	// Feldraine: Altgrasstreifen ohne Schnee
	vec2 fp = fract(p / 130.0);
	float edge = min(min(fp.x, 1.0 - fp.x), min(fp.y, 1.0 - fp.y)) * 130.0;
	snow_w *= mix(0.25, 1.0, smoothstep(0.6, 2.8, edge));
	vec3 col = mix(bare, snow, snow_w);
	vec3 nrm = mix(vec3(0.5, 0.5, 1.0), tg(snow_nrm, uv_s, 0.12).rgb, snow_w);
	float rough = mix(0.97, 0.78, snow_w);
	// --- Gleisbett (beide Gleise): Schotter, Schwellen, Schneereste am Rand
	float dx0 = abs(wp.x);
	float dx1 = abs(wp.x - track2_x);
	float dmin = min(dx0, dx1);
	vec2 uv_b = p * 0.55;
	vec3 ballast = tg(ballast_alb, uv_b, 0.3).rgb * vec3(0.72, 0.7, 0.68);
	vec3 bn = tg(ballast_nrm, uv_b, 0.3).rgb;
	float s = fract(p.y / 0.65);
	float sl = (1.0 - step(0.38, s)) * (1.0 - step(1.3, dmin));
	vec3 sleeper_c = vec3(0.13, 0.125, 0.12) * (0.8 + 0.4 * n3);    // Betonschwelle, verschmutzt
	// verwischte Schwellen: bei Fahrt Richtung Mittelwert (38 % Deckung)
	float slw = mix(sl, 0.38 * (1.0 - step(1.3, dmin)), blur * 0.9);
	vec3 track = mix(ballast, sleeper_c, slw);
	// Schnee am Schotterrand und zwischen den Schwellen (Flugschnee)
	float tsn = smoothstep(1.6, 2.6, dmin) * 0.7 + (1.0 - sl) * 0.12 * step(dmin, 1.3);
	tsn *= smoothstep(0.3, 0.7, n2 + 0.2);
	track = mix(track, snow * 0.9, tsn);
	float tw = 1.0 - smoothstep(2.4, 3.2, dmin);
	col = mix(col, track, tw);
	nrm = mix(nrm, mix(bn, vec3(0.5, 0.5, 1.0), 0.3 + 0.5 * blur), tw);
	rough = mix(rough, 0.95, tw);
	ALBEDO = col;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = rough;
}
