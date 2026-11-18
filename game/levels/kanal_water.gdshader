shader_type spatial;
// Kanalisation (Optik 3): truebes Abwasser statt flacher dunkler Spiegelflaeche.
// Langsame Stroemung (Welt-z), feine Kraeuselung, treibende Schlamm-/Schaumfladen mit eigener
// Schlamm-Textur (Poly Haven brown_mud_02, CC0) und matter Oberflaeche. Opak wie zuvor.

uniform sampler2D mud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D scum_mask : filter_linear_mipmap, repeat_enable;
uniform vec3 water_col : source_color = vec3(0.035, 0.045, 0.03);
uniform vec3 scum_tint : source_color = vec3(0.42, 0.38, 0.3);
uniform float flow = 0.06;
uniform float scum_amount = 0.5;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wp.xz;
	vec2 f = vec2(0.0, TIME * flow);
	vec3 r1 = texture(ripple_nrm, uv * 0.45 + f).rgb;
	vec3 r2 = texture(ripple_nrm, uv * 0.8 - f * 0.6 + vec2(0.37, 0.11)).rgb;
	vec3 ripple = normalize(mix(r1, r2, 0.5) * 2.0 - 1.0);
	float m = texture(scum_mask, uv * 0.07 + f * 0.35).r;
	float scum = smoothstep(0.62 - scum_amount * 0.25, 0.78 - scum_amount * 0.25, m);
	vec2 muv = uv * 0.3 + f * 0.35;
	vec3 mud = texture(mud_tex, muv).rgb;
	vec3 mn = texture(mud_nrm, muv).rgb * 2.0 - 1.0;
	ALBEDO = mix(water_col, mud * scum_tint, scum * 0.85);
	ROUGHNESS = mix(0.05, 0.75, scum);
	SPECULAR = mix(0.7, 0.3, scum);
	METALLIC = 0.0;
	vec3 n = normalize(mix(vec3(ripple.xy * 0.35, 1.0), vec3(mn.xy * 0.8, 1.0), scum));
	NORMAL_MAP = n * 0.5 + 0.5;
}
