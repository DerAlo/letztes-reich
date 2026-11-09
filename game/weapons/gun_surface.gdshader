shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Waffen-Oberflaeche (GunModels): objektraum-triplanare Mikrostruktur ohne UVs/Tangenten,
// Kantenabnutzung aus der Vertexfarbe (COLOR.r = Kante/Fase, COLOR.g = Hohlraum/AO),
// Rauheits- und Farbvariation (Griffspuren, Staub). Funktioniert fuer Viewmodel und Pickups.

uniform vec4 base_color : source_color = vec4(0.06, 0.062, 0.06, 1.0);
uniform vec4 wear_color : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.16, 0.14, 0.11, 1.0);
uniform float metallic_base = 0.0;
uniform float metallic_wear = 0.0;
uniform float roughness_base = 0.6;
uniform float roughness_wear = 0.4;
uniform float roughness_var = 0.18;
uniform float wear_amount = 0.5;     // 0 = neu, 1 = stark abgenutzt
uniform float dirt_amount = 0.25;
uniform float color_var = 0.12;
uniform float micro_scale = 9.0;     // Wiederholungen pro Meter / 10
uniform float bump_strength = 0.35;
uniform float ao_strength = 0.6;
uniform float specular_level = 0.5;
uniform float clearcoat_amount = 0.0;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 o_pos;
varying vec3 o_nrm;

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 1e-4);
}

float tri_noise(vec3 p, vec3 w, float s) {
	return texture(noise_tex, p.zy * s).r * w.x + texture(noise_tex, p.xz * s).r * w.y
		+ texture(noise_tex, p.xy * s).r * w.z;
}

void fragment() {
	vec3 n = normalize(o_nrm);
	vec3 w = tri_w(n);
	float s = micro_scale * 10.0;
	float n_hi = tri_noise(o_pos, w, s * 0.37);
	float n_lo = tri_noise(o_pos + vec3(3.1, 1.7, 0.9), w, s * 0.045);
	float n_md = tri_noise(o_pos + vec3(0.7, 5.3, 2.2), w, s * 0.12);
	float edge = COLOR.r;
	float cav = COLOR.g;
	// Kantenabnutzung: Fasen + Rauschen, an Hohlraeumen nicht
	float wmask = edge * (0.35 + 1.1 * n_md) * wear_amount * 1.6;
	wmask += smoothstep(0.78, 0.95, n_md) * wear_amount * 0.25;
	wmask = smoothstep(0.45, 0.75, wmask) * cav;
	// Schmutz in Hohlraeumen / unten
	float dmask = clamp((1.0 - cav) * 0.8 + smoothstep(0.55, 0.85, n_lo) * 0.35, 0.0, 1.0) * dirt_amount;
	vec3 col = base_color.rgb * (1.0 + (n_lo - 0.5) * color_var * 2.0 + (n_hi - 0.5) * color_var);
	col = mix(col, dirt_color.rgb, dmask * 0.6);
	col = mix(col, wear_color.rgb, wmask);
	float ao = mix(1.0, cav, ao_strength);
	ALBEDO = col;
	METALLIC = mix(metallic_base, metallic_wear, wmask);
	float r = roughness_base + (n_lo - 0.5) * roughness_var * 2.0 + (n_hi - 0.5) * roughness_var;
	r = mix(r, roughness_wear, wmask);
	r = mix(r, 0.9, dmask * 0.5);
	ROUGHNESS = clamp(r, 0.04, 1.0);
	SPECULAR = specular_level;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	CLEARCOAT = clearcoat_amount * (1.0 - wmask);
	CLEARCOAT_ROUGHNESS = 0.35;
	// Triplanare Normalen (Whiteout-Blend) im Objektraum -> View-Space
	vec2 uvx = o_pos.zy * s;
	vec2 uvy = o_pos.xz * s;
	vec2 uvz = o_pos.xy * s;
	vec3 tx = texture(noise_nrm, uvx).xyz * 2.0 - 1.0;
	vec3 ty = texture(noise_nrm, uvy).xyz * 2.0 - 1.0;
	vec3 tz = texture(noise_nrm, uvz).xyz * 2.0 - 1.0;
	float bs = bump_strength * (1.0 - wmask * 0.6);
	tx.xy *= bs; ty.xy *= bs; tz.xy *= bs;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 nb = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	NORMAL = normalize(mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * nb));
}
