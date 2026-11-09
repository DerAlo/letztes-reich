shader_type spatial;
render_mode cull_disabled;
// Fluss "Welikaja": opakes Wasser (damit SSR spiegelt), Wellen im Vertex-Shader, scrollende
// Detail-Normalen in Fliessrichtung, Regentropfen-Ringe, Gischt an Brueckenpfeilern und Ufern.

uniform vec3 deep_color : source_color = vec3(0.025, 0.04, 0.042);
uniform vec3 shallow_color : source_color = vec3(0.07, 0.085, 0.075);
uniform vec3 foam_color : source_color = vec3(0.62, 0.66, 0.68);
uniform float roughness_base = 0.04;
uniform vec2 flow = vec2(1.1, 0.0);           // Fliessrichtung und -tempo (m/s)
uniform float wave_height = 0.22;
uniform float wave_scale = 0.09;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float normal_strength = 0.75;
uniform float rain_ripples = 1.0;             // 0 = aus
uniform vec4 piers[6];                        // xyz = Mitte, w = Radius (w <= 0: unbenutzt)
uniform float shore_z_a = -62.0;              // Uferlinien (z) fuer Ufergischt
uniform float shore_z_b = -192.0;
uniform float foam_boost = 0.0;               // Einsturz-/Absturzgischt (vom Level animiert)
uniform vec3 foam_boost_pos = vec3(0.0, 0.0, -100.0);
uniform float foam_boost_radius = 18.0;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float waves(vec2 p, float t) {
	float h = 0.0;
	h += sin(dot(p, vec2(0.62, 0.18)) * 1.0 - t * 1.3) * 0.5;
	h += sin(dot(p, vec2(-0.31, 0.77)) * 1.7 - t * 1.9) * 0.25;
	h += sin(dot(p, vec2(0.93, -0.41)) * 2.9 - t * 2.6) * 0.12;
	h += sin(dot(p, vec2(0.15, 0.99)) * 4.3 - t * 3.4) * 0.06;
	return h;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = (w.xz - flow * TIME * 0.6) * wave_scale * 6.0;
	float h = waves(p, TIME) * wave_height;
	float e = 0.15;
	float hx = waves(p + vec2(e, 0.0), TIME) * wave_height;
	float hz = waves(p + vec2(0.0, e), TIME) * wave_height;
	VERTEX.y += h;
	vec3 n = normalize(vec3(-(hx - h) / (e / (wave_scale * 6.0)), 1.0, -(hz - h) / (e / (wave_scale * 6.0))));
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(n, 0.0)).xyz);
	wpos = w;
	wpos.y += h;
}

// Ein Ring pro Zelle, zufaellig versetzt und zeitlich gestaffelt (Regentropfen).
vec2 ripple(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 res = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			float rnd = hash12(c);
			vec2 center = c + vec2(hash12(c + 17.1), hash12(c + 3.7));
			float ph = fract(t * (0.9 + rnd * 0.6) + rnd);
			vec2 d = p - center;
			float dist = length(d);
			float r = ph * 0.9;
			float ring = sin(clamp((dist - r) * 18.0, -3.14159, 3.14159)) * (1.0 - ph) * smoothstep(0.9, 0.0, dist);
			ring *= step(abs(dist - r), 0.18);
			res += ring * d / max(dist, 0.001);
		}
	}
	return res;
}

void fragment() {
	vec2 uvf = wpos.xz;
	float t = TIME;
	vec3 na = texture(normal_a, uvf * 0.045 - flow * t * 0.045).rgb * 2.0 - 1.0;
	vec3 nb = texture(normal_b, uvf * 0.11 + vec2(-flow.y, flow.x) * t * 0.02 - flow * t * 0.09).rgb * 2.0 - 1.0;
	vec3 nm = normalize(vec3((na.xy + nb.xy) * normal_strength, 1.0));
	if (rain_ripples > 0.0) {
		vec2 rp = ripple(uvf * 1.6, t * 1.4) + ripple(uvf * 2.3 + 11.3, t * 1.7 + 0.5) * 0.7;
		nm.xy += rp * 0.35 * rain_ripples;
		nm = normalize(nm);
	}
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Gischt: Pfeiler (Bugwelle + Kielwasser in Fliessrichtung), Ufer, Einsturzstelle
	float fn = texture(foam_noise, uvf * 0.08 - flow * t * 0.08).r;
	float fn2 = texture(foam_noise, uvf * 0.23 - flow * t * 0.14 + 0.37).r;
	float foam = 0.0;
	vec2 fdir = normalize(flow + vec2(0.0001));
	for (int k = 0; k < 6; k++) {
		vec4 pr = piers[k];
		if (pr.w <= 0.0) continue;
		vec2 d = wpos.xz - pr.xz;
		float along = dot(d, fdir);
		float side = abs(dot(d, vec2(-fdir.y, fdir.x)));
		float ring = smoothstep(pr.w + 2.2, pr.w + 0.2, length(d));
		float wake = smoothstep(pr.w * 1.6 + along * 0.12, 0.0, side) * smoothstep(0.0, 2.0, along) * smoothstep(45.0, 4.0, along);
		foam = max(foam, max(ring, wake * 0.75));
	}
	float shore = max(smoothstep(5.5, 0.0, abs(wpos.z - shore_z_a)), smoothstep(5.5, 0.0, abs(wpos.z - shore_z_b)));
	foam = max(foam, shore * 0.8);
	foam = max(foam, foam_boost * smoothstep(foam_boost_radius, foam_boost_radius * 0.2, distance(wpos.xz, foam_boost_pos.xz)));
	foam = clamp(foam * smoothstep(0.25, 0.75, fn * 0.6 + fn2 * 0.6), 0.0, 1.0);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 water = mix(deep_color, shallow_color, fn * 0.6) * (1.0 - fres * 0.5);
	ALBEDO = mix(water, foam_color, foam);
	ROUGHNESS = mix(roughness_base, 0.75, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
