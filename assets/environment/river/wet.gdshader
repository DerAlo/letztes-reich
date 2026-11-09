shader_type spatial;
// Triplanares PBR-Material (Weltkoordinaten) im Starkregen: nasse, dunklere Oberflaeche mit
// geringer Rauheit, Pfuetzen auf flachen Stellen (spiegelnd, mit Regentropfen-Ringen) und
// herablaufende Wasserschlieren an senkrechten Flaechen. Fuer Strasse, Bruecke, Haeuser, Stahl.

uniform bool use_base_tex = true;
uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float base_scale = 0.3;
uniform float base_roughness = 1.0;
uniform float base_metallic = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.8;
uniform float puddles : hint_range(0.0, 1.0) = 0.0;   // Anteil Pfuetzen auf Flaechen nach oben
uniform float puddle_scale = 0.07;
uniform float streaks = 0.6;                           // Wasserschlieren an Waenden
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

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 ripple(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 res = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			float rnd = hash12(c);
			vec2 center = c + vec2(hash12(c + 17.1), hash12(c + 3.7));
			float ph = fract(t * (1.0 + rnd * 0.7) + rnd);
			vec2 d = p - center;
			float dist = length(d);
			float r = ph * 0.6;
			float ring = sin(clamp((dist - r) * 24.0, -3.14159, 3.14159)) * (1.0 - ph);
			ring *= step(abs(dist - r), 0.13);
			res += ring * d / max(dist, 0.001);
		}
	}
	return res;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos * base_scale;
	vec3 alb = tint.rgb;
	float rough = base_roughness;
	float ao = 1.0;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float metal = base_metallic;
	if (use_base_tex) {
		alb *= tri(base_albedo, p, w).rgb;
		vec3 arm = tri(base_arm, p, w).rgb;
		ao = arm.r;
		rough = clamp(arm.g * base_roughness, 0.0, 1.0);
		metal = base_metallic * arm.b;
		nm = tri(base_normal, p, w).rgb;
	}
	// Nasse Oberflaeche: dunkler, glatter
	float nz = texture(noise_tex, wpos.xz * 0.05 + wpos.y * 0.03).r;
	float wet = wetness * mix(0.75, 1.0, nz);
	alb *= mix(1.0, 0.55, wet * (1.0 - metal * 0.5));
	rough = mix(rough, rough * 0.28 + 0.05, wet);

	// Schlieren an Waenden: senkrecht laufende Baender
	float vert = 1.0 - abs(n.y);
	if (streaks > 0.0 && vert > 0.5) {
		vec2 sp = vec2(dot(wpos.xz, vec2(abs(n.z), abs(n.x))) * 3.0, wpos.y * 0.15 + TIME * 0.35);
		float s = texture(noise_tex, vec2(sp.x * 0.35, sp.y * 0.6)).r;
		s = smoothstep(0.58, 0.8, s) * streaks * vert;
		rough = mix(rough, 0.05, s);
		alb *= 1.0 - s * 0.2;
	}

	// Pfuetzen auf Flaechen nach oben
	float pud = 0.0;
	if (puddles > 0.0 && n.y > 0.85) {
		float pn = texture(noise_tex, wpos.xz * puddle_scale).r * 0.7 + texture(noise_tex, wpos.xz * puddle_scale * 3.3 + 0.41).r * 0.3;
		pud = smoothstep(1.0 - puddles, 1.0 - puddles + 0.06, pn);
	}
	if (pud > 0.0) {
		vec2 rp = ripple(wpos.xz * 2.2, TIME * 1.6) + ripple(wpos.xz * 3.1 + 5.3, TIME * 1.9 + 0.3) * 0.6;
		vec3 pn3 = normalize(vec3(rp * 0.45, 1.0));
		nm = mix(nm, pn3 * 0.5 + 0.5, pud);
		rough = mix(rough, 0.015, pud);
		alb = mix(alb, alb * 0.45, pud);
		metal = mix(metal, 0.0, pud);
		ao = mix(ao, 1.0, pud);
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
	NORMAL_MAP = nm;
	SPECULAR = 0.5;
	EMISSION = emission_color.rgb * emission_energy;
}
