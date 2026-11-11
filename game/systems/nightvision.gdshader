shader_type canvas_item;
// Nachtsichtgeraet (Restlichtverstaerker): liegt ueber Welt, Waffe und PostFx (Layer 3), unter dem HUD.
// Verstaerkt das Bild, faerbt es phosphorgruen, legt Rauschen, Zeilenflimmern und eine Roehrenvignette
// darueber. Helle Stellen ueberstrahlen (Bloom aus den Mip-Stufen); "glare" blendet bei direktem
// Lampenlicht ins Objektiv das ganze Bild aus.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float fade = 0.0;            // 0 = aus, 1 = voll an (Einblenden)
uniform float gain = 9.0;            // Verstaerkung
uniform float glare = 0.0;           // 0..1 Blendung durch Lampen
uniform float noise = 0.16;          // Rauschstaerke
uniform float flicker = 0.0;         // Batterie schwach: Helligkeitsflackern
uniform float power_on = 0.0;        // 1 -> 0 kurzer Einschaltblitz
uniform vec3 tint = vec3(0.32, 1.0, 0.42);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
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
		float l = luma(mix(src, soft, 0.45));
		// Verstaerkung mit weicher Saettigung (Lichter laufen aus, statt hart zu clippen)
		float g = gain * (1.0 + glare * 1.5);
		float amp = 1.0 - exp(-l * g);
		// Bloom: helle Bereiche aus groben Mip-Stufen ueberstrahlen
		float b1 = luma(textureLod(screen_tex, uv, 3.5).rgb);
		float b2 = luma(textureLod(screen_tex, uv, 5.5).rgb);
		float bloom = max(b1 * g - 0.55, 0.0) * 0.55 + max(b2 * g - 0.4, 0.0) * 0.8;
		amp += bloom * (0.6 + glare * 2.5);
		// Blendung: Bild laeuft weiss aus, Kontrast bricht ein
		amp = mix(amp, 0.75 + amp * 0.6, glare * 0.8);
		// Rauschen: im Dunkeln staerker, grob (Roehrenkorn)
		vec2 gp = floor(uv / px / 1.5);
		float n = hash(gp + fract(t * 37.0) * 311.0) - 0.5;
		amp += n * noise * (1.25 - amp * 0.6);
		// Funkeln einzelner Punkte (Szintillation)
		float sp = step(0.9985, hash(gp * 0.37 + floor(t * 24.0)));
		amp += sp * 0.5;
		// Zeilenflimmern und langsames Pumpen
		amp *= 0.965 + 0.035 * sin(uv.y / px.y * 1.7 + t * 40.0);
		amp *= 1.0 - 0.04 * sin(t * 2.3) * sin(t * 7.1);
		amp *= 1.0 - flicker * (0.5 + 0.5 * step(0.5, hash(vec2(floor(t * 18.0), 3.0))));
		// Roehrenvignette (rund, harter Rand)
		vec2 d = (uv - 0.5) * vec2(aspect, 1.0);
		float r = length(d);
		float tube = 1.0 - smoothstep(0.86, 1.0, r);
		float vig = 1.0 - smoothstep(0.2, 0.95, r) * 0.6;
		amp = max(amp, 0.0) * vig;
		vec3 c = tint * amp + vec3(0.85, 1.0, 0.85) * max(amp - 1.0, 0.0) * 0.6;
		c = mix(vec3(0.0, 0.012, 0.004), c, tube);
		c += vec3(0.8, 1.0, 0.8) * power_on;
		COLOR = vec4(mix(src, c, fade), 1.0);
	}
}
