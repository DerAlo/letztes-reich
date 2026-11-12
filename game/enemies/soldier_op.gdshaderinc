// Operator-Gegner (assets/characters/soldier_op, "S.W.A.T. Operator - Remastered" von jeandiz, Sketchfab
// Standard License). Gemeinsamer Code fuer soldier_op.gdshader und soldier_op_hood.gdshader.
// Original-Texturen (2048) bleiben die Basis; Fraktionsfarbe kommt helligkeitserhaltend dazu:
//   mode 0 = Koerper (Stoff einheitlich grau ~0.177 sRGB = 0.027 linear): Oberteil/Hose getrennt (Ruhepose-Hoehe), Stiefel und
//            Handschuhe (Ruhepose-Naehe zu Fuss/Hand) bleiben original; ru/reich: Tarnmuster triplanar in der
//            RUHEPOSE (CUSTOM0/1 aus dem Bake -> kein Schwimmen); Armbinde wie soldier_mh_cloth.gdshader.
//   mode 1 = Weste/Helm/Kopf (ein Atlas): nur die untere Atlas-Haelfte (Ausruestung, v > 0.5), nur
//            unbunte, nicht-metallische Pixel -> Gesicht/Augen/Sturmhaube, Metallteile und Lichter bleiben.
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D camo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform int mode = 0;
uniform float ref_lum = 0.0269;          // mittlere Helligkeit des Stoffs (Textur-Mittelwert, LINEAR)
uniform float tint_amount = 1.0;
uniform vec3 col_top : source_color = vec3(0.177);
uniform vec3 col_trou : source_color = vec3(0.177);
uniform float belt_y = 0.97;
uniform bool use_camo = false;
uniform vec3 camo_mul : source_color = vec3(1.0);
uniform float camo_scale = 2.0;
uniform float camo_detail = 0.75;        // Anteil der Stoff-Helligkeit (Falten/Naehte) im Tarnmuster
uniform vec3 hand_l = vec3(0.18, 1.08, 0.21);
uniform vec3 hand_r = vec3(-0.19, 1.25, 0.26);
uniform float glove_r = 0.12;
uniform float boot_y = 0.3;
uniform float rough_mul = 1.0;
uniform float metal_mul = 1.0;
uniform float emission_energy = 2.0;

uniform bool arm_on = false;
uniform vec3 arm_col : source_color = vec3(0.8, 0.1, 0.1);
uniform sampler2D arm_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool arm_use_tex = false;
uniform vec3 arm_a_l = vec3(0.19, 1.45, 0.01);
uniform vec3 arm_b_l = vec3(0.27, 1.24, 0.1);
uniform vec3 arm_a_r = vec3(-0.18, 1.41, -0.04);
uniform vec3 arm_b_r = vec3(-0.28, 1.22, 0.07);
uniform float arm_t0 = 0.4;            // Mitte Oberarm (naeher an der Schulter knickt die Binde beim Anschlag)
uniform float arm_t1 = 0.57;
uniform float arm_r = 0.085;
uniform float arm_emis = 0.35;

#ifdef HIDE_HEAD
// Kopf unter einem geschlossenen Helm (gepanzerte Typen): Ellipsoid in der Ruhepose ausblenden
uniform vec3 hide_c = vec3(0.0, 1.66, 0.05);
uniform vec3 hide_r = vec3(0.16, 0.2, 0.2);
uniform float hide_up = 1.15;           // obere Haelfte weiter: Op-Helm ragt dort bis 1.09 x Panzerhelm hinaus
// Rueckentasche (Ruhepose z bis -0.29, y 0.95..1.22) ragt durch die Rueckenplatte / beim Hocken heraus: ausblenden
uniform vec4 hide_pack = vec4(-0.2, 0.93, 1.25, 0.16);   // z kleiner als x, y zwischen y/z, |x| kleiner als w
#endif

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
#ifdef HIDE_HEAD
	float hk = mix(1.0, hide_up, smoothstep(hide_c.y - 0.06, hide_c.y + 0.02, v_rp.y));
	if (length((v_rp - hide_c) / (hide_r * hk)) < 1.0) {
		discard;
	}
	if (mode == 0 && v_rp.z < hide_pack.x && v_rp.y > hide_pack.y && v_rp.y < hide_pack.z && abs(v_rp.x) < hide_pack.w) {
		discard;
	}
#endif
	vec3 tex = texture(albedo_tex, UV).rgb;
	vec4 orm = texture(orm_tex, UV);
	float metal = orm.b * metal_mul;
	float lum = dot(tex, vec3(0.2126, 0.7152, 0.0722));
	float shade = lum / ref_lum;
	vec3 alb = tex;
	if (mode == 0) {
		float glove = 1.0 - smoothstep(glove_r * 0.8, glove_r, min(distance(v_rp, hand_l), distance(v_rp, hand_r)));
		float boot = 1.0 - smoothstep(boot_y - 0.03, boot_y, v_rp.y);
		float keep = max(glove, boot);
		float trou = 1.0 - smoothstep(belt_y - 0.02, belt_y + 0.02, v_rp.y);
		vec3 base;
		if (use_camo) {
			vec3 w = tri_w(normalize(v_rn));
			vec3 p = v_rp * camo_scale + vec3(0.37, 0.11, 0.53) * trou;
			base = tri_camo(p, w) * camo_mul * (1.0 - 0.06 * trou) * mix(1.0, shade, camo_detail);
		} else {
			base = mix(col_top, col_trou, trou) * shade;
		}
		alb = mix(tex, base, tint_amount * (1.0 - keep));
		if (arm_on) {
			for (int sd = 0; sd < 2; sd++) {
				vec3 a = sd == 0 ? arm_a_l : arm_a_r;
				vec3 ab = (sd == 0 ? arm_b_l : arm_b_r) - a;
				float t = dot(v_rp - a, ab) / dot(ab, ab);
				vec3 dv = v_rp - (a + ab * t);
				float band = smoothstep(arm_t0 - 0.006, arm_t0, t) * (1.0 - smoothstep(arm_t1, arm_t1 + 0.006, t)) * step(length(dv), arm_r)
					* smoothstep(0.1, 0.3, dot(normalize(v_rn), dv / max(length(dv), 1e-4)));   // nur Aermel (Normale vom Arm weg), nicht Rumpf an der Achsel
				if (band > 0.0) {
					vec3 ax = normalize(ab);
					vec3 e1 = normalize(cross(ax, vec3(0.0, 0.0, 1.0)));
					vec3 e2 = cross(ax, e1);
					float u = atan(dot(dv, e2), dot(dv, e1)) / 6.2832 + 0.25;
					float v = (t - arm_t0) / (arm_t1 - arm_t0);
					vec3 ac = arm_use_tex ? texture(arm_tex, vec2(u, v)).rgb : arm_col;
					alb = mix(alb, ac * mix(1.0, shade, 0.6), band);
					EMISSION = ac * arm_emis * band;
				}
			}
		}
	} else {
		float sat = max(tex.r, max(tex.g, tex.b)) - min(tex.r, min(tex.g, tex.b));
		float gear = smoothstep(0.49, 0.51, UV.y) * (1.0 - smoothstep(0.05, 0.12, sat)) * (1.0 - clamp(metal * 2.0, 0.0, 1.0));
		vec3 base = col_top * shade;
		if (use_camo) {
			vec3 w = tri_w(normalize(v_rn));
			base = tri_camo(v_rp * camo_scale, w) * camo_mul * mix(1.0, shade, camo_detail);
		}
		alb = mix(tex, base, tint_amount * gear);
		EMISSION = texture(emission_tex, UV).rgb * emission_energy;
	}
	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = clamp(orm.g * rough_mul, 0.04, 1.0);
	METALLIC = metal;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.3;
}
