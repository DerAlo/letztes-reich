shader_type spatial;
// Uniform/Helm der realistischen Gegner-Soldaten (MakeHuman-Modell, assets/characters/soldier_mh).
// Ein Satz Texturen fuer alle Fraktionen: die Stofftextur (suit.jpg) ist eine Detailkarte
//   R = Stoff-Helligkeit (0.5 = Mittelwert, Falten/Naehte/AO), G = Hosen-Maske.
// Farbe kommt zur Laufzeit dazu: Tarnmuster (ru/reich, triplanar in der RUHEPOSE ueber CUSTOM0/CUSTOM1,
// beim Bake geschrieben -> kein "Schwimmen" bei Animation) oder Fraktions-Grundfarben (Oberteil/Hose).
// mode 0 = Uniform, 1 = Helm (Detail = helmet.jpg, gleiche Logik, kein Hosenanteil).
render_mode cull_back, depth_draw_opaque;

uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D camo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform int mode = 0;
uniform bool use_camo = false;
uniform vec3 col_top : source_color = vec3(0.3, 0.32, 0.24);
uniform vec3 col_trou : source_color = vec3(0.26, 0.28, 0.21);
uniform vec3 camo_mul : source_color = vec3(1.0);
uniform float camo_scale = 2.0;
uniform float shade_strength = 1.0;
uniform float normal_depth = 1.0;
uniform float rough = 0.88;
uniform float metal = 0.0;
uniform vec3 dirt_col : source_color = vec3(0.2, 0.17, 0.12);
uniform float dirt_height = 0.55;
uniform float dirt_amount = 0.45;

// Armbinde (nur Uniform): Band zwischen arm_t0..arm_t1 entlang Schulter->Ellbogen (Ruhepose), Radius < arm_r
uniform bool arm_on = false;
uniform vec3 arm_col : source_color = vec3(0.8, 0.1, 0.1);
uniform sampler2D arm_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool arm_use_tex = false;
uniform vec3 arm_a_l = vec3(0.17, 1.42, 0.0);
uniform vec3 arm_b_l = vec3(0.24, 1.15, 0.0);
uniform vec3 arm_a_r = vec3(-0.17, 1.42, 0.0);
uniform vec3 arm_b_r = vec3(-0.24, 1.15, 0.0);
uniform float arm_t0 = 0.3;
uniform float arm_t1 = 0.47;
uniform float arm_r = 0.07;
uniform float arm_emis = 0.35;

varying vec3 v_rp;
varying vec3 v_rn;

void vertex() {
	v_rp = CUSTOM0.xyz;
	v_rn = CUSTOM1.xyz;
	if (dot(v_rn, v_rn) < 0.01) {
		v_rp = VERTEX;
		v_rn = NORMAL;
	}
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec3 tri_camo(vec3 p, vec3 w) {
	return texture(camo_tex, p.zy).rgb * w.x + texture(camo_tex, p.xz).rgb * w.y + texture(camo_tex, p.xy).rgb * w.z;
}

void fragment() {
	vec4 d = texture(detail_tex, UV);
	float shade = mix(1.0, d.r * 2.0, shade_strength);
	float trou = mode == 0 ? d.g : 0.0;
	vec3 base;
	if (use_camo) {
		vec3 w = tri_w(normalize(v_rn));
		// Hose: gleiches Muster, leicht versetzt (getrennte Stoffbahnen) und etwas dunkler
		vec3 p = v_rp * camo_scale + vec3(0.37, 0.11, 0.53) * trou;
		base = tri_camo(p, w) * camo_mul * (1.0 - 0.06 * trou);
	} else {
		base = mix(col_top, col_trou, trou);
	}
	vec3 alb = base * shade;
	float h = v_rp.y;
	float dirt = (1.0 - smoothstep(0.05, dirt_height, h)) * dirt_amount * trou;
	alb = mix(alb, dirt_col * shade, clamp(dirt, 0.0, 1.0));
	if (arm_on && mode == 0) {
		for (int sd = 0; sd < 2; sd++) {
			vec3 a = sd == 0 ? arm_a_l : arm_a_r;
			vec3 ab = (sd == 0 ? arm_b_l : arm_b_r) - a;
			float t = dot(v_rp - a, ab) / dot(ab, ab);
			vec3 dv = v_rp - (a + ab * t);
			float band = smoothstep(arm_t0 - 0.006, arm_t0, t) * (1.0 - smoothstep(arm_t1, arm_t1 + 0.006, t)) * step(length(dv), arm_r);
			if (band > 0.0) {
				vec3 ax = normalize(ab);
				vec3 e1 = normalize(cross(ax, vec3(0.0, 0.0, 1.0)));
				vec3 e2 = cross(ax, e1);
				float u = atan(dot(dv, e2), dot(dv, e1)) / 6.2832 + 0.25;
				float v = (t - arm_t0) / (arm_t1 - arm_t0);
				vec3 ac = arm_use_tex ? texture(arm_tex, vec2(u, v)).rgb : arm_col;
				vec3 ba = ac * mix(1.0, shade, 0.6);
				alb = mix(alb, ba, band);
				EMISSION = ac * arm_emis * band;
			}
		}
	}
	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = clamp(rough * (1.08 - 0.16 * d.r) + dirt * 0.08, 0.05, 1.0);
	METALLIC = metal;
	SPECULAR = 0.4;
}
