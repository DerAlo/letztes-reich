shader_type spatial;
// Triplanares Basis-Material (Weltkoordinaten) mit Schneeauflage auf nach oben zeigenden Flaechen.
// Fuer Boden, Daecher, Sandsaecke, Fahrzeuge und Kiefern im Nachtlevel.

uniform bool use_base_tex = true;
uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float base_scale = 0.3;
uniform float base_roughness = 1.0;
uniform float base_metallic = 0.0;
uniform float color_noise = 0.0;      // Helligkeitsvariation ohne Textur (z. B. Nadeln)

uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 snow_tint : source_color = vec3(0.82, 0.87, 0.96);
uniform float snow_scale = 0.35;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.5;
uniform float snow_sharp = 7.0;
uniform float noise_amp = 0.6;
uniform float noise_scale = 0.18;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos * base_scale;
	float nz = texture(noise_tex, wpos.xz * noise_scale + wpos.y * 0.07).r;
	float nz2 = texture(noise_tex, wpos.xz * noise_scale * 4.1 + vec2(0.37, 0.71)).r;
	vec3 alb = tint.rgb;
	float rough = base_roughness;
	float ao = 1.0;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (use_base_tex) {
		alb *= tri(base_albedo, p, w).rgb;
		vec3 arm = tri(base_arm, p, w).rgb;
		ao = arm.r;
		rough = arm.g * base_roughness;
		nm = tri(base_normal, p, w).rgb;
	}
	alb *= 1.0 + (nz2 - 0.5) * color_noise * 2.0;
	float s = clamp((n.y - (1.0 - snow_amount) + (nz - 0.5) * noise_amp) * snow_sharp, 0.0, 1.0);
	vec3 sp = wpos * snow_scale;
	vec3 salb = tri(snow_albedo, sp, w).rgb * snow_tint;
	ALBEDO = mix(alb, salb, s);
	ROUGHNESS = mix(rough, 0.62, s);
	METALLIC = mix(base_metallic, 0.0, s);
	AO = mix(ao, 1.0, s);
	AO_LIGHT_AFFECT = 0.3;
	NORMAL_MAP = mix(nm, tri(snow_normal, sp, w).rgb, s);
	SPECULAR = mix(0.5, 0.65, s);
	EMISSION = emission_color.rgb * emission_energy;
}
