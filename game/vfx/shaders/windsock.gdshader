shader_type spatial;
// Windsack (Stoffschlauch, konisch) – die komplette Form entsteht im Vertex-Shader aus einem Roh-Schlauch
// (UV.x = Umfang 0..1, UV.y = Laenge 0..1). Lokale Achse: +Z = windabwaerts, +Y = oben, Ursprung = Mitte
// des vorderen Rings. Die Windfahne (Node) dreht nur das Gestell um die Hochachse; Fuellung, Durchhang,
// Einfallen und Flattern kommen hier aus der Instanz-Uniform "fill" (0 = Flaute, 1 = steht waagerecht).
// Streifen: 5 Baender rot/weiss (rot an Ein- und Austritt), Doppelnaehte an den Bandgrenzen, Laengsnaht
// unten, Saum am Ring, Rip-Stop-Gewebe als feine Normalstruktur, etwas Schmutz zum Ende hin.
render_mode cull_disabled, depth_draw_opaque;

uniform float sock_len = 2.4;
uniform float r0 = 0.25;              // Radius am Ring
uniform float r1 = 0.11;              // Radius am Ende
uniform float frame_frac = 0.2;       // vorderer Teil ueber starrem Bugelgestell
uniform vec3 col_a : source_color = vec3(0.70, 0.07, 0.04);
uniform vec3 col_b : source_color = vec3(0.86, 0.86, 0.83);
uniform vec3 col_hem : source_color = vec3(0.10, 0.10, 0.11);
uniform float bands = 5.0;
uniform float glow = 0.0;             // Grundleuchten fuer Nachtlesbarkeit (0 = rein physikalisch)

instance uniform float fill = 0.5;
instance uniform float phase = 0.0;

varying float v_s;        // 0..1 auf dem freien Teil
varying float v_lf;       // lokale Fuellung 0..1

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	float u = UV.x;
	float v = UV.y;
	float th = u * TAU;
	float f = clamp(fill, 0.0, 1.0);
	float t = TIME;
	float ff = frame_frac;
	float lfree = sock_len * (1.0 - ff);
	float s = clamp((v - ff) / max(1.0 - ff, 0.001), 0.0, 1.0);
	// Neigung gegen die Waagerechte: Flaute ~ haengt fast senkrecht, voller Wind ~ waagerecht.
	float a0 = mix(1.32, 0.03, pow(f, 0.85));
	float a1 = mix(1.52, 0.10, pow(f, 0.65));
	// Boeen-Pumpen: Sack hebt/senkt sich leicht
	float pump = sin(t * (1.3 + f) + phase) * 0.06 * (1.0 - f) * f * 4.0;
	a0 = clamp(a0 + pump, 0.0, 1.55);
	a1 = clamp(a1 + pump * 1.4, 0.0, 1.57);
	// Mittellinie integrieren (Gestell gerade, danach gekruemmt)
	vec3 c = vec3(0.0, 0.0, min(v, ff) * sock_len);
	float a = 0.0;
	const int STEPS = 10;
	for (int i = 0; i < STEPS; i++) {
		float s0 = float(i) / float(STEPS);
		if (s0 >= s) {
			break;
		}
		float s1 = min(s0 + 1.0 / float(STEPS), s);
		float am = mix(a0, a1, (s0 + s1) * 0.5);
		c += vec3(0.0, -sin(am), cos(am)) * (s1 - s0) * lfree;
	}
	a = v > ff ? mix(a0, a1, s) : 0.0;
	vec3 tng = vec3(0.0, -sin(a), cos(a));
	vec3 X = vec3(1.0, 0.0, 0.0);
	vec3 U = cross(tng, X);
	// Querschnitt: zum Ende hin faellt der Stoff bei wenig Wind ein (abgeflacht, Falten)
	float lf = clamp(0.25 + f * 1.5 - s * (1.1 - f * 0.6), 0.08, 1.0);
	lf = v <= ff ? 1.0 : lf;
	float r = mix(r0, r1, v);
	float rx = r * mix(1.25, 1.0, lf);
	float ry = r * mix(0.16, 1.0, lf);
	float wr = (1.0 - lf) * 0.10 * sin(th * 5.0 + s * 9.0 + phase) + 0.025 * s * sin(th * 3.0 - t * (9.0 + 8.0 * f) + s * 14.0 + phase);
	rx *= 1.0 + wr;
	ry *= 1.0 + wr;
	// Flattern: laufende Welle seitlich und vertikal, waechst zum Ende
	float wv = t * (3.5 + 7.0 * f) - s * 7.0 + phase;
	float amp = sock_len * (0.025 + 0.06 * f * (1.0 - 0.5 * f)) * s * s;
	vec3 off = X * sin(wv) * amp + U * sin(wv * 1.31 + 1.7) * amp * 0.45;
	// am Ring/Gestell kein Versatz
	off *= step(ff, v);
	VERTEX = c + off + X * cos(th) * rx + U * sin(th) * ry;
	NORMAL = normalize(X * cos(th) / max(rx, 0.001) + U * sin(th) / max(ry, 0.001));
	TANGENT = tng;
	BINORMAL = cross(NORMAL, tng);
	v_s = s;
	v_lf = lf;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	// Streifen
	float bpos = v * bands;
	float band = floor(bpos);
	vec3 base = mod(band, 2.0) < 0.5 ? col_a : col_b;
	// Saum am Ring (Stoff umgeschlagen + Gurtband) und am Ende
	float hem = 1.0 - smoothstep(0.018, 0.03, v);
	hem = max(hem, smoothstep(0.985, 0.995, v));
	base = mix(base, col_hem, hem);
	// Naehte: Doppelnaht an jeder Bandgrenze, Laengsnaht unten (u = 0.75 -> Unterseite)
	float circ = TAU * mix(r0, r1, v);
	float d_band = abs(fract(bpos + 0.5) - 0.5) / bands * sock_len;    // Meter zur Bandgrenze
	float seam = 1.0 - smoothstep(0.004, 0.012, d_band);
	float d_long = abs(fract(u - 0.75 + 0.5) - 0.5) * circ;
	float lseam = 1.0 - smoothstep(0.003, 0.009, d_long);
	float stitch = max(seam, lseam);
	// Rip-Stop-Gewebe: feine Rasterverstaerkung, nur wenn aufloesbar (sonst flimmerfrei abgeblendet)
	vec2 wuv = vec2(u * circ, v * sock_len) * 160.0;
	vec2 fw = fwidth(wuv);
	float res = 1.0 - smoothstep(0.35, 0.9, max(fw.x, fw.y));
	vec2 g = abs(fract(wuv / 7.0) - 0.5);
	float rip = (1.0 - smoothstep(0.0, 0.08, min(g.x, g.y))) * res;
	float weave = (sin(wuv.x * 3.14159) * sin(wuv.y * 3.14159)) * res;
	// Schmutz/Ausbleichen (Ende und Unterseite)
	float n = vnoise(vec2(u * 9.0, v * 14.0)) * 0.6 + vnoise(vec2(u * 31.0, v * 47.0)) * 0.4;
	float grime = clamp(v * 0.5 + (1.0 - abs(sin(u * TAU))) * 0.15, 0.0, 1.0) * (0.25 + 0.35 * n);
	vec3 albedo = base * (1.0 - grime * 0.45) * (1.0 - stitch * 0.28) * (1.0 - rip * 0.08);
	// Innenseite dunkler (kaum Licht im Schlauch)
	if (!FRONT_FACING) {
		albedo *= 0.45;
	}
	ALBEDO = albedo;
	ROUGHNESS = 0.62 + rip * 0.08 - stitch * 0.05;
	SPECULAR = 0.35;
	// Stoff-Normalen: Gewebe + Naehte (aufgeworfene Kante) + Falten bei eingefallenem Stoff
	float fold = (1.0 - v_lf) * sin(u * TAU * 5.0 + v_s * 9.0 + 0.5);
	vec3 nm = vec3(0.5 + weave * 0.05 + fold * 0.12, 0.5 + rip * 0.04 + seam * 0.12 * sign(fract(bpos + 0.5) - 0.5), 1.0);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0;
	// Duenner Stoff: Licht scheint durch
	BACKLIGHT = base * 0.35;
	EMISSION = base * glow * (1.0 - hem);
}
