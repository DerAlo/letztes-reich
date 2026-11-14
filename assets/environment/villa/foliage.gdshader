shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Laubkarten (Hecken, Laubbaeume, Straeucher) mit Alpha-Scissor. Die Vertex-Normalen zeigen von der
// Kronen-/Heckenmitte nach aussen (weiche, volumige Beleuchtung) und werden nicht pro Seite gespiegelt.
// COLOR.r = Biegsamkeit (Wind), COLOR.g = Farbvariation, COLOR.b = Verschattung innen (AO).

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(0.55, 0.62, 0.42);
uniform vec3 tint2 : source_color = vec3(0.68, 0.66, 0.38);
uniform vec3 backlight_color : source_color = vec3(0.35, 0.42, 0.12);
uniform float alpha_cut = 0.42;
uniform float wind = 0.05;
uniform float brightness = 1.0;
// Innen-Verschattung (COLOR.b = 0 -> Faktor) fuer Albedo und AO; Hecken setzen hoehere Werte, damit die
// Schattenseite nicht absaeuft (dichte Hecken streuen Licht durch das Laub).
uniform float shade_floor = 0.35;
uniform float ao_floor = 0.45;
// Weiche Himmels-Aufhellung der Schattenseite (Laub-Transluzenz / Streulicht), als linearer Anteil der
// Albedo (bewusst ohne source_color, sonst wird der Wert per sRGB-Kurve fast auf 0 gedrueckt).
uniform vec3 fill_color = vec3(0.0);

varying vec3 wn;
varying vec3 vc;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	vec3 off = vec3(sin(t * 1.3 + wp.x * 0.45 + wp.z * 0.3), sin(t * 1.9 + wp.z * 0.5) * 0.4,
			cos(t * 1.1 + wp.x * 0.3 - wp.z * 0.4)) * wind * COLOR.r;
	VERTEX += off;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vc = COLOR.rgb;
}

void fragment() {
	vec4 tx = texture(leaf_tex, UV);
	ALPHA = tx.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 c = tx.rgb * mix(tint, tint2, vc.g) * brightness;
	ALBEDO = c * mix(shade_floor, 1.0, vc.b);
	EMISSION = ALBEDO * fill_color * mix(0.6, 1.0, vc.b);
	ROUGHNESS = 0.72;
	SPECULAR = 0.3;
	BACKLIGHT = backlight_color * mix(0.3, 1.0, vc.b);
	AO = mix(ao_floor, 1.0, vc.b);
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
