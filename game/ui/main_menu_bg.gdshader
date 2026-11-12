shader_type canvas_item;
// Hauptmenue-Hintergrund (game/ui/main_menu.gd): zwei gerenderte Level-Standbilder mit Ueberblendung,
// langsamem Ken-Burns-Zoom, kuehl-warmem Grading, weicher Unschaerfe hinter der Menuespalte (links),
// Abdunklung links/unten, Vignette und Filmkorn. Ein einziges Vollbild-Rechteck -> billig.

uniform sampler2D img_a : filter_linear, repeat_disable;
uniform sampler2D img_b : filter_linear, repeat_disable;
uniform float mix_ab = 0.0;
uniform float zoom_a = 1.05;
uniform float zoom_b = 1.05;
uniform vec2 pan_a = vec2(0.0);
uniform vec2 pan_b = vec2(0.0);
uniform float img_aspect = 1.7777778;
uniform float bright = 0.78;
uniform float sat = 0.62;
uniform float blur_px = 2.6;      // Unschaerfe links (in Bildpixeln bei 1920 Breite)
uniform float grain = 0.035;
uniform float dim = 0.0;         // Unterseiten (Listen, Rueckfragen): Bild zuruecknehmen fuer Lesbarkeit

vec2 cover_uv(vec2 uv, float zoom, vec2 pan, float scr_aspect) {
	vec2 p = uv - 0.5;
	if (scr_aspect > img_aspect) {
		p.y *= img_aspect / scr_aspect;
	} else {
		p.x *= scr_aspect / img_aspect;
	}
	return clamp(p / zoom + 0.5 + pan, vec2(0.001), vec2(0.999));
}

vec3 tap(sampler2D t, vec2 uv, float r) {
	if (r < 0.0002) {
		return texture(t, uv).rgb;
	}
	vec2 o = vec2(r, r * img_aspect);
	vec3 c = texture(t, uv).rgb * 0.2;
	c += texture(t, uv + vec2(o.x, 0.0)).rgb * 0.1;
	c += texture(t, uv - vec2(o.x, 0.0)).rgb * 0.1;
	c += texture(t, uv + vec2(0.0, o.y)).rgb * 0.1;
	c += texture(t, uv - vec2(0.0, o.y)).rgb * 0.1;
	c += texture(t, uv + o * 0.7071).rgb * 0.1;
	c += texture(t, uv - o * 0.7071).rgb * 0.1;
	c += texture(t, uv + vec2(o.x, -o.y) * 0.7071).rgb * 0.1;
	c += texture(t, uv + vec2(-o.x, o.y) * 0.7071).rgb * 0.1;
	return c;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float scr_aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = blur_px / 1920.0 * (1.0 - smoothstep(0.22, 0.55, uv.x));
	vec3 c = tap(img_a, cover_uv(uv, zoom_a, pan_a, scr_aspect), r);
	if (mix_ab > 0.001) {
		vec3 cb = tap(img_b, cover_uv(uv, zoom_b, pan_b, scr_aspect), r);
		c = mix(c, cb, mix_ab);
	}
	// Grading: entsaettigt, Schatten kuehl, Lichter warm (Feuerschein), etwas Kontrast
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, sat);
	c *= mix(vec3(0.82, 0.93, 1.0), vec3(1.1, 0.97, 0.82), smoothstep(0.08, 0.65, lum));
	c = (c - 0.5) * 1.08 + 0.5;
	c = max(c, vec3(0.0)) * bright;
	// Abdunklung hinter Menue (links) und Fusszeile (unten), leicht oben
	c *= mix(0.22, 1.0, smoothstep(0.04, 0.66, uv.x));
	c *= mix(0.42, 1.0, smoothstep(0.0, 0.3, 1.0 - uv.y));
	c *= mix(0.7, 1.0, smoothstep(0.0, 0.18, uv.y));
	// Ecke oben rechts (Statuszeile) und Unterseiten-Abdunklung
	c *= mix(0.55, 1.0, smoothstep(0.0, 0.3, length((uv - vec2(1.0, 0.0)) * vec2(1.0, 1.6))));
	c *= 1.0 - dim * 0.55;
	// Vignette
	vec2 d = (uv - vec2(0.56, 0.5)) * vec2(1.0, 0.82);
	c *= 1.0 - smoothstep(0.38, 0.92, length(d)) * 0.65;
	// Filmkorn + sehr dezente Zeilen
	float n = hash(floor(FRAGCOORD.xy * 0.75) + fract(TIME * 7.13) * 91.7);
	c += (n - 0.5) * grain;
	c *= 0.988 + 0.012 * sin(FRAGCOORD.y * 1.5708);
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
