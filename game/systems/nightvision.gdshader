shader_type canvas_item;
// Nachtsichtgeraet (Restlichtverstaerker, Gen-3-Roehre): liegt ueber Welt, Waffe und PostFx (Layer 3),
// unter dem HUD. Verstaerkt das Bild, faerbt es phosphorgruen, legt Korn, Zeilenflimmern und eine
// Roehrenvignette darueber.
// Realismus wie bei echten Roehren:
// - Automatische Helligkeitsregelung (ABC): die Verstaerkung richtet sich nach der mittleren
//   Szenenhelligkeit (grobe Mip-Stufe). Dunkle Gaenge werden stark, helle Raeume kaum verstaerkt.
// - Bright Source Protection: Lichter laufen weich in eine Schulter unter Weiss (Phosphor wird
//   nie weiss, nur hellgruen) und erzeugen nur einen kleinen Halo, keine Bildflaeche.
// - "glare" (Lampe direkt ins Objektiv) regelt die Verstaerkung herunter und legt einen leichten
//   Schleier ueber das Bild, statt alles weiss auszublenden.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float fade = 0.0;            // 0 = aus, 1 = voll an (Einblenden)
uniform float gain = 9.0;            // maximale Verstaerkung (stockdunkel)
uniform float gain_min = 1.2;        // minimale Verstaerkung (helle Szene)
uniform float target = 0.42;         // angestrebte mittlere Bildhelligkeit (0..1)
uniform float peak = 0.86;           // hellster Phosphorwert (bleibt gruen, nie weiss)
uniform float glare = 0.0;           // 0..1 Blendung durch Lampen
uniform float noise = 0.14;          // Rauschstaerke bei voller Verstaerkung
uniform float flicker = 0.0;         // Batterie schwach: Helligkeitsflackern
uniform float power_on = 0.0;        // 1 -> 0 kurzer Einschaltblitz
uniform vec3 tint = vec3(0.30, 1.0, 0.40);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Mittlere Szenenhelligkeit (ABC-Messung): 4x3 Messpunkte auf grober Mip-Stufe, Mitte staerker
// gewichtet. Einzelne Lampen werden begrenzt, damit ein Lichtpunkt nicht das ganze Bild abdunkelt.
float scene_mean() {
	float s = 0.0;
	float w = 0.0;
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 3; j++) {
			vec2 p = vec2((float(i) + 0.5) / 4.0, (float(j) + 0.5) / 3.0);
			p = mix(vec2(0.5), p, 0.8);
			float wt = 1.0 - length(p - 0.5) * 0.9;
			s += min(luma(textureLod(screen_tex, p, 5.5).rgb), 0.45) * wt;
			w += wt;
		}
	}
	return s / max(w, 0.001);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec3 src = textureLod(screen_tex, uv, 0.0).rgb;
	if (fade <= 0.001) {
		COLOR = vec4(src, 1.0);
	} else {
		float t = TIME;
		// Leichte Unschaerfe der Roehre
		vec3 soft = textureLod(screen_tex, uv, 1.2).rgb;
		float l = luma(mix(src, soft, 0.4));
		// Automatische Verstaerkung: 1-exp(-m*g) = target  ->  g = -ln(1-target)/m
		float m = scene_mean();
		float g = clamp(-log(1.0 - target) / max(m, 0.0005), gain_min, gain);
		// Bright Source Protection: Blendung regelt die Roehre herunter
		g /= (1.0 + glare * 1.8);
		float amp = 1.0 - exp(-l * g);
		// Kleiner Halo um echte Lichtquellen (nur was schon im Rohbild hell ist, nicht verstaerkt)
		float b1 = luma(textureLod(screen_tex, uv, 3.0).rgb);
		float b2 = luma(textureLod(screen_tex, uv, 4.5).rgb);
		float halo = max(b1 - 0.6, 0.0) * 0.35 + max(b2 - 0.5, 0.0) * 0.25;
		amp += halo * (1.0 + glare);
		// Weiche Schulter: Lichter bleiben unter dem Maximum, Zeichnung in hellen Flaechen bleibt
		amp = peak * (1.0 - exp(-amp * 1.6)) / (1.0 - exp(-1.6));
		amp = min(amp, peak);
		// Schwarzpunkt: Roehrenbild hat satte Schatten (etwas mehr Kontrast gegen Schleier)
		amp = max(amp - 0.035, 0.0) * 1.04;
		// Blendung: leichter Schleier, Kontrast sinkt etwas
		amp = mix(amp, 0.28 + amp * 0.7, glare * 0.5);
		// Rauschen: bei hoher Verstaerkung (dunkel) staerker, grob (Roehrenkorn)
		float gk = clamp((g - gain_min) / max(gain - gain_min, 0.01), 0.0, 1.0);
		vec2 gp = floor(uv / px / 1.5);
		float n = hash(gp + fract(t * 37.0) * 311.0) - 0.5;
		amp += n * noise * (0.45 + 0.55 * gk) * (1.15 - amp * 0.6);
		// Funkeln einzelner Punkte (Szintillation), nur im Dunkeln deutlich
		float sp = step(0.9988, hash(gp * 0.37 + floor(t * 24.0)));
		amp += sp * 0.35 * gk;
		// Zeilenflimmern und langsames Pumpen
		amp *= 0.97 + 0.03 * sin(uv.y / px.y * 1.7 + t * 40.0);
		amp *= 1.0 - 0.03 * sin(t * 2.3) * sin(t * 7.1);
		amp *= 1.0 - flicker * (0.5 + 0.5 * step(0.5, hash(vec2(floor(t * 18.0), 3.0))));
		// Roehrenvignette (rund, harter Rand)
		vec2 d = (uv - 0.5) * vec2(aspect, 1.0);
		float r = length(d);
		float tube = 1.0 - smoothstep(0.86, 1.0, r);
		float vig = 1.0 - smoothstep(0.25, 0.95, r) * 0.5;
		amp = clamp(amp, 0.0, 1.0) * vig;
		// Phosphor: gruen, in den Spitzen leicht heller-gelbgruen, aber nie weiss
		vec3 c = tint * amp + vec3(0.12, 0.05, 0.1) * smoothstep(0.6, 0.9, amp) * amp;
		c = mix(vec3(0.0, 0.012, 0.004), c, tube);
		c += vec3(0.5, 0.8, 0.5) * power_on;
		COLOR = vec4(mix(src, c, fade), 1.0);
	}
}
