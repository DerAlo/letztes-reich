shader_type canvas_item;
// TV-/Monitor-Filter fuer das Intro: Zeilensprung, Scanlines, leichte Unschaerfe, Farbsaum,
// Rauschen, Vignette und Bildstoerung (glitch) fuer harte Schnitte.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float blur : hint_range(0.0, 3.0) = 0.9;
uniform float lines = 540.0;
uniform float noise_amt = 0.07;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float saturation = 0.8;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	float line = floor(uv.y * lines);
	// Zeilensprung: Halbbilder abwechselnd leicht versetzt
	float field = mod(floor(t * 50.0), 2.0);
	float odd = mod(line, 2.0);
	uv.x += (odd == field ? 0.0007 : -0.0007) * strength;
	// leichtes Bandwackeln + Stoerstreifen
	uv.x += sin(uv.y * 23.0 + t * 3.1) * 0.0007 * strength;
	float band = step(0.82, hash(vec2(floor(uv.y * 24.0), floor(t * 18.0))));
	uv.x += (hash(vec2(line, floor(t * 30.0))) - 0.5) * 0.09 * glitch * band;
	uv.y += glitch * 0.03 * sin(t * 40.0);
	float ca = (0.0012 + glitch * 0.01) * strength;
	vec3 col;
	col.r = textureLod(screen_tex, uv + vec2(ca, 0.0), blur * strength).r;
	col.g = textureLod(screen_tex, uv, blur * strength).g;
	col.b = textureLod(screen_tex, uv - vec2(ca, 0.0), blur * strength).b;
	// Saettigung / Farbton
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, mix(1.0, saturation, strength)) * mix(vec3(1.0), tint, strength);
	// Scanlines
	float s = 0.5 + 0.5 * sin(SCREEN_UV.y * lines * 3.14159265);
	col *= mix(1.0, 0.74 + 0.26 * s, strength);
	// Rauschen
	float n = hash(floor(SCREEN_UV * vec2(640.0, 360.0)) + vec2(fract(t * 7.13) * 91.0, fract(t * 3.71) * 37.0));
	col += (n - 0.5) * noise_amt * strength;
	col = mix(col, vec3(n * 0.9), clamp(glitch * 0.9, 0.0, 1.0) * (0.55 + 0.45 * band));
	// Vignette
	vec2 d = SCREEN_UV - 0.5;
	col *= 1.0 - dot(d, d) * 1.1 * strength;
	COLOR = vec4(col, 1.0);
}
