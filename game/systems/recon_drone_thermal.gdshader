shader_type canvas_item;
// Bildschirm-Overlay der Aufklaerungsdrohne (game/systems/recon_drone.gd):
// thermal = 0: leicht gruenstichiges Kamerabild mit Zeilen und Rauschen,
// thermal = 1: Weiss-heiss-Waermebild. Die Drohnenkamera rendert im Waermebild mit eigener, dunkler
// Umgebung; warme Koerper tragen ein stark emittierendes Overlay-Material und landen so oben im Grauwert.
// signal_loss (0..1): Zeilenversatz und Schnee bei schwachem Funksignal.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float thermal : hint_range(0.0, 1.0) = 0.0;
uniform float signal_loss : hint_range(0.0, 1.0) = 0.0;
uniform float time_s = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float line = floor(uv.y * 260.0);
	float tear = step(0.82 - signal_loss * 0.5, hash(vec2(line * 0.37, floor(time_s * 9.0))));
	uv.x += (hash(vec2(line, floor(time_s * 24.0))) - 0.5) * 0.03 * signal_loss * tear;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// Waermebild: kalte Umgebung dunkel und flach, Heisses (emittierende Overlays, Lampen) weiss
	float hot = smoothstep(0.78, 1.05, max(c.r, max(c.g, c.b)));
	vec3 th = vec3(pow(clamp(l, 0.0, 1.0), 0.85) * 0.5 + 0.035);
	th = mix(th, vec3(1.0), hot);
	// leichter Halo um heisse Stellen
	float halo = 0.0;
	for (int i = 0; i < 4; i++) {
		float a = float(i) * 1.5708 + 0.785;
		vec2 o = vec2(cos(a), sin(a)) * 0.004;
		vec3 s = textureLod(screen_tex, uv + o, 1.5).rgb;
		halo += smoothstep(0.8, 1.1, max(s.r, max(s.g, s.b)));
	}
	th += vec3(halo * 0.06);
	vec3 feed = mix(vec3(l), c, 0.55) * vec3(0.9, 1.0, 0.93);
	vec3 col = mix(feed, th, thermal);
	// Zeilen, Rauschen, Vignette
	float n = hash(floor(uv * vec2(640.0, 360.0)) + floor(time_s * 30.0));
	col += (n - 0.5) * (0.035 + 0.035 * thermal + 0.35 * signal_loss);
	col *= 0.94 + 0.06 * sin(SCREEN_UV.y * 820.0 + time_s * 3.0);
	vec2 d = SCREEN_UV - 0.5;
	col *= 1.0 - dot(d, d) * 0.85;
	col = mix(col, vec3(n * 0.8), signal_loss * signal_loss * 0.65);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
