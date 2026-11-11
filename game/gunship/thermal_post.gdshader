shader_type canvas_item;
// Waermebild-Sensor: Polaritaet (weiss-heiss / schwarz-heiss), Ueberstrahlen heisser Ziele, leichte Unschaerfe,
// Sensorrauschen, Spalten-Muster, Zeilenstruktur, Vignette, Stoerungen (Treffer, NUC-Kalibrierung).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float black_hot = 0.0;
uniform float gain = 1.38;
uniform float level = 0.11;
uniform float grain = 0.075;
uniform float scan = 0.05;
uniform float bloom = 0.55;
uniform float vignette = 0.55;
uniform float glitch = 0.0;      // 0..1 Bildstoerung
uniform float freeze = 0.0;      // 0..1 Kalibrier-Blitz (Bild wird flach/grau)
uniform vec2 jitter = vec2(0.0); // Bildwackeln in UV

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV + jitter;
	float t = floor(TIME * 30.0);
	if (glitch > 0.0) {
		float line = floor(uv.y * 70.0);
		float r = hash(vec2(line, floor(TIME * 24.0)));
		if (r < glitch * 0.6) {
			uv.x += (r - glitch * 0.3) * 0.08 * glitch;
		}
	}
	float v = textureLod(screen_tex, uv, 0.0).r;
	float b1 = textureLod(screen_tex, uv, 1.5).r;
	float b2 = textureLod(screen_tex, uv, 3.5).r;
	float b3 = textureLod(screen_tex, uv, 5.5).r;
	// Sensor-Optik: minimal weich, heisse Ziele bluten aus
	v = mix(v, b1, 0.22);
	float hot = max(b1 - 0.62, 0.0) * 0.6 + max(b2 - 0.5, 0.0) * 0.9 + max(b3 - 0.42, 0.0) * 0.9;
	v += hot * bloom;
	v = (v - level) * gain;
	v = mix(v, 0.5, freeze);
	if (black_hot > 0.5) {
		v = 1.0 - v;
	}
	// Rauschen: zeitlich (Korn) + fest (Spalten/Zeilen des Detektors)
	float n = hash(floor(uv * res) + vec2(t * 7.13, t * 3.71));
	float n_b = hash(floor(uv * res * 0.5) + vec2(t * 1.7, t * 9.3));
	v += ((n - 0.5) * 0.7 + (n_b - 0.5) * 0.5) * grain;
	v += (hash(vec2(floor(uv.x * res.x), 3.0)) - 0.5) * 0.018;
	v += (hash(vec2(7.0, floor(uv.y * res.y * 0.5))) - 0.5) * 0.01;
	v += glitch * (hash(vec2(floor(uv.y * res.y * 0.25), t)) - 0.5) * 0.35;
	v *= 1.0 - scan * (0.5 + 0.5 * sin(uv.y * res.y * 3.14159));
	vec2 c = SCREEN_UV - 0.5;
	v *= 1.0 - dot(c, c) * vignette;
	v = clamp(v, 0.0, 1.0);
	COLOR = vec4(v * 0.97, v, v * 0.985, 1.0);
}
