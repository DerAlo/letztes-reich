shader_type spatial;
// Uniform-/Ausruestungsstoff der Soldaten (SWAT-Modell ohne brauchbare UVs).
// CUSTOM0.xyz = Ruhepose-Position (Skelettraum, m), CUSTOM1.xyz = Ruhepose-Normale (soldier_gear.prepare_mesh):
// Tarnmuster und Stoffstruktur werden triplanar in der Ruhepose aufgebracht -> kein "Schwimmen" bei Animation.
// Detail: Poly Haven "rough_linen" (CC0) als Gewebe-Normal/AO; Tarnmuster aus gen_camo.py (CC0).
// mode: 0 = Tarnstoff, 1 = Ausruestung (einfarbiges Cordura), 2 = Haut.
render_mode cull_back, depth_draw_opaque;

uniform sampler2D camo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D weave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D weave_arm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform int mode = 0;
uniform vec3 base_col : source_color = vec3(0.12, 0.13, 0.09);
uniform vec3 dirt_col : source_color = vec3(0.2, 0.17, 0.12);
uniform float camo_scale = 2.0;        // Musterzyklen pro Meter (64 Zellen -> ~8 mm)
uniform float weave_scale = 7.0;       // Gewebe-Kacheln pro Meter
uniform float weave_strength = 0.55;
uniform float rough = 0.85;
uniform float metal = 0.0;
uniform float dirt_height = 0.45;      // Schmutz an Stiefeln/Hosenbeinen bis zu dieser Hoehe
uniform float dirt_amount = 0.55;

varying vec3 v_rp;
varying vec3 v_rn;
varying vec3 v_pn;

void vertex() {
	v_rp = CUSTOM0.xyz;
	v_rn = CUSTOM1.xyz;
	if (dot(v_rn, v_rn) < 0.01) {   // Mesh ohne Ruhepose-Daten: auf aktuelle Pose zurueckfallen
		v_rp = VERTEX;
		v_rn = NORMAL;
	}
	v_pn = NORMAL;
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 tri_s(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

// Dreht v um die kuerzeste Rotation, die a auf b abbildet (Rodrigues).
vec3 rot_to(vec3 v, vec3 a, vec3 b) {
	vec3 ax = cross(a, b);
	float s = length(ax);
	float c = dot(a, b);
	if (s < 1e-4) {
		return c > 0.0 ? v : -v;
	}
	ax /= s;
	return v * c + cross(ax, v) * s + ax * dot(ax, v) * (1.0 - c);
}

void fragment() {
	vec3 rn = normalize(v_rn);
	vec3 w = tri_w(rn);
	vec3 wp = v_rp * weave_scale;
	vec3 arm = tri_s(weave_arm, wp, w).rgb;
	vec3 arm2 = tri_s(weave_arm, v_rp * 1.3 + vec3(0.3, 0.7, 0.1), w).rgb;   // grobe Falten/Flecken

	vec3 alb;
	if (mode == 0) {
		alb = tri_s(camo_tex, v_rp * camo_scale, w).rgb;
		alb *= 0.8 + 0.35 * arm.r;
	} else if (mode == 1) {
		alb = base_col * (0.75 + 0.45 * arm.r) * (0.9 + 0.2 * arm2.r);
	} else {
		alb = base_col * (0.92 + 0.12 * arm2.r);
	}
	// Schmutz unten (Stiefel, Hosenbeine), Abrieb an Knien
	float h = v_rp.y;
	float dirt = (1.0 - smoothstep(0.0, dirt_height, h)) * dirt_amount * (0.5 + 0.7 * arm2.g);
	if (mode != 2) {
		alb = mix(alb, dirt_col, clamp(dirt, 0.0, 1.0));
	}

	// Gewebe-Normalen (Whiteout) in der Ruhepose, dann in die aktuelle Pose gedreht
	vec3 tx = texture(weave_normal, wp.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(weave_normal, wp.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(weave_normal, wp.xy).xyz * 2.0 - 1.0;
	tx.xy *= weave_strength;
	ty.xy *= weave_strength;
	tz.xy *= weave_strength;
	tx = vec3(tx.xy + rn.zy, abs(tx.z) * rn.x);
	ty = vec3(ty.xy + rn.xz, abs(ty.z) * rn.y);
	tz = vec3(tz.xy + rn.xy, abs(tz.z) * rn.z);
	vec3 nb = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	vec3 n_pose = rot_to(nb, rn, normalize(v_pn));
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(n_pose, 0.0))).xyz);

	ALBEDO = alb;
	ROUGHNESS = clamp(rough * (0.85 + 0.3 * arm.g) + dirt * 0.1, 0.05, 1.0);
	METALLIC = metal * (1.0 - clamp(dirt, 0.0, 1.0));
	AO = mix(1.0, arm.r, 0.6);
	AO_LIGHT_AFFECT = 0.25;
}
