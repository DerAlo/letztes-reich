shader_type spatial;
render_mode fog_disabled, cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
// Ferne Gipfelketten (Mission "Weisses Rauschen"): Schnee auf flacheren Flanken, dunkler Fels in Waenden,
// eigene Luftperspektive statt Szenen-Nebel (der Nebel wuerde Kulissen in 2-3 km komplett schlucken).
// haze_k / haze_color / haze_cap setzt alpenpass.gd laufend aus dem Wetter (Sturm -> komplett verhuellt).

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 snow_color : source_color = vec3(0.93, 0.95, 1.0);
uniform vec3 rock_color : source_color = vec3(0.34, 0.35, 0.38);
uniform vec3 haze_color : source_color = vec3(0.8, 0.84, 0.9);
uniform float haze_energy = 1.0;
uniform float haze_k = 0.0005;
uniform float haze_cap = 0.8;
uniform float haze_low = 0.5;      // Taeler/Fuesse zusaetzlich im Dunst

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float nz = texture(noise_tex, wpos.xz * 0.0035).r;
	float nz2 = texture(noise_tex, wpos.xz * 0.017 + vec2(0.37, 0.11)).r;
	// Schnee: flache Flanken und oben mehr; Rinnen/Waende Fels
	float snow = smoothstep(0.5, 0.72, n.y + (nz - 0.5) * 0.4 + (nz2 - 0.5) * 0.18 + smoothstep(150.0, 900.0, wpos.y) * 0.12);
	vec3 rock = rock_color * mix(0.7, 1.2, nz2);
	vec3 alb = mix(rock, snow_color * mix(0.92, 1.0, nz), snow);
	float dist = length(VERTEX);
	float haze = 1.0 - exp(-dist * haze_k);
	haze = mix(haze, 1.0, (1.0 - smoothstep(-120.0, 380.0, wpos.y)) * haze_low);
	haze = min(haze, haze_cap);
	ALBEDO = alb * (1.0 - haze);
	ROUGHNESS = mix(0.85, 0.6, snow);
	SPECULAR = 0.3;
	EMISSION = haze_color * haze * haze_energy;
}
