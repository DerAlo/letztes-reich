shader_type spatial;
render_mode diffuse_lambert_wrap;
// Hochgebirgs-Gelaende (Mission "Weisses Rauschen"): heller, sauberer Schnee (Texturen nur als feine Variation),
// grossflaechige Verwehungen nur als Normalen, Fels (rock_face_03) nur an Steilstellen, festgefahrene
// Schneefahrbahn mit Spurrillen (road_mask aus alpenpass_terrain.gd), Glitzern im Nahbereich.
// Normalen werden in Weltkoordinaten gemischt (das Gelaende-Mesh hat keine Tangenten) und direkt gesetzt.

uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D drift_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D drift_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D road_mask : hint_default_black, filter_linear, repeat_disable;

uniform vec3 snow_color : source_color = vec3(0.93, 0.955, 1.0);
uniform vec3 cavity_tint : source_color = vec3(0.8, 0.87, 1.0);    // Mulden/Verwehungs-Lee leicht blaeulich
uniform vec3 rock_tint : source_color = vec3(0.6, 0.6, 0.62);
uniform vec3 road_color : source_color = vec3(0.8, 0.82, 0.86);
uniform vec3 rut_color : source_color = vec3(0.58, 0.58, 0.6);
uniform float snow_scale = 0.22;
uniform float snow_detail = 0.22;    // Anteil der Textur-Helligkeitsvariation
uniform float snow_bump = 0.55;
uniform float drift_scale = 0.012;
uniform float drift_strength = 0.4;
uniform float rock_scale = 0.06;
uniform float rock_bump = 0.9;
uniform float rock_lo = 0.48;        // normal.y: darunter Fels
uniform float rock_hi = 0.64;        // darueber Schnee
uniform float noise_amp = 0.16;
uniform float glitter = 1.8;
uniform float glitter_density = 34.0;
uniform float glitter_dist = 34.0;
uniform vec2 road_origin = vec2(-160.0, -720.0);
uniform vec2 road_size = vec2(321.0, 801.0);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec2 tn(sampler2D t, vec2 uv) {
	return texture(t, uv).xy * 2.0 - 1.0;
}

// Spurrillen-Profil ueber den Querabstand l (m): zwei Hauptspuren, zwei schwache Aussenspuren
float ruts(float l) {
	float a = exp(-pow((abs(l) - 0.95) / 0.28, 2.0));
	float b = exp(-pow((abs(l) - 2.25) / 0.32, 2.0)) * 0.45;
	return a + b;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	float nz = texture(noise_tex, wpos.xz * 0.011).r;
	float nz2 = texture(noise_tex, wpos.xz * 0.053 + vec2(0.31, 0.77)).r;
	// Schneebedeckung: Fels nur an Steilstellen, Rauschen fuer ausgefranste Kanten
	// schmale Uebergangszone -> klare Felskanten statt weicher grauer Flecken; hochfrequentes Rauschen franst sie aus
	float nz3 = texture(noise_tex, wpos.xz * 0.19 + vec2(0.53, 0.29)).r;
	float rc = mix(rock_lo, rock_hi, 0.5);
	float s = smoothstep(rc - 0.025, rc + 0.025, n.y + (nz - 0.5) * noise_amp + (nz2 - 0.5) * 0.1 + (nz3 - 0.5) * 0.08);

	// --- Fels (triplanar, Normalen per UDN in Weltkoordinaten)
	vec3 rp = wpos * rock_scale;
	vec3 ralb = (texture(rock_albedo, rp.zy).rgb * w.x + texture(rock_albedo, rp.xz).rgb * w.y + texture(rock_albedo, rp.xy).rgb * w.z) * rock_tint;
	ralb *= mix(0.8, 1.15, texture(noise_tex, wpos.xz * 0.004).r);
	vec3 rarm = texture(rock_arm, rp.zy).rgb * w.x + texture(rock_arm, rp.xz).rgb * w.y + texture(rock_arm, rp.xy).rgb * w.z;
	vec2 rx = tn(rock_normal, rp.zy) * rock_bump;
	vec2 ry = tn(rock_normal, rp.xz) * rock_bump;
	vec2 rz = tn(rock_normal, rp.xy) * rock_bump;
	vec3 rn = normalize(n + vec3(0.0, rx.y, rx.x) * w.x + vec3(ry.x, 0.0, ry.y) * w.y + vec3(rz.x, rz.y, 0.0) * w.z);
	// kalter, entsaettigter Fels (kein Braun) + Schnee auf kleinen Leisten -> klare Felsbaender statt Flecken
	ralb = mix(vec3(dot(ralb, vec3(0.3, 0.5, 0.2))), ralb, 0.3) * vec3(0.95, 0.98, 1.05);
	s = max(s, smoothstep(0.78, 0.9, rn.y) * smoothstep(rock_lo - 0.2, rock_lo, n.y) * step(0.45, nz2));

	// --- Schnee: heller Grundton, snow_02 nur als feine Helligkeits-/Normalen-Variation, Verwehungen als Normalen
	vec2 sp = wpos.xz * snow_scale;
	float sl = dot(texture(snow_albedo, sp).rgb, vec3(0.333));
	float sm = dot(textureLod(snow_albedo, vec2(0.5), 10.0).rgb, vec3(0.333));
	vec2 sn = tn(snow_normal, sp) * snow_bump;
	vec2 dn = tn(drift_normal, wpos.xz * drift_scale) * drift_strength;
	vec2 dn2 = tn(drift_normal, wpos.xz * drift_scale * 3.7 + vec2(0.2, 0.6)) * drift_strength * 0.5;
	vec3 snw = normalize(n + vec3(sn.x + dn.x + dn2.x, 0.0, sn.y + dn.y + dn2.y));
	float var_l = clamp(1.0 + (sl - sm) * snow_detail * 2.0, 0.85, 1.08);
	float lee = clamp(1.0 - dot(snw - n, vec3(0.55, 0.0, 0.45)) * 1.6, 0.0, 1.0);  // Lee-Seite der Verwehungen
	vec3 snow_c = snow_color * var_l * mix(0.97, 1.02, nz);
	snow_c = mix(snow_c * cavity_tint, snow_c, mix(1.0, lee, 0.35));
	float s_rough = 0.62;

	// --- Fahrbahn: festgefahrener Schnee mit Spurrillen
	vec2 ruv = (wpos.xz - road_origin + 0.5) / road_size;
	float road = 0.0;
	if (ruv.x > 0.0 && ruv.y > 0.0 && ruv.x < 1.0 && ruv.y < 1.0) {
		vec2 rm = texture(road_mask, ruv).rg;
		road = rm.r * s;
		if (road > 0.01) {
			float l = (rm.g - 0.5) * 12.0;
			vec2 tx = vec2(1.0 / road_size.x, 0.0);
			vec2 tz = vec2(0.0, 1.0 / road_size.y);
			vec2 g = vec2(texture(road_mask, ruv + tx).g - texture(road_mask, ruv - tx).g,
				texture(road_mask, ruv + tz).g - texture(road_mask, ruv - tz).g) * 6.0;   // m pro m (Querrichtung)
			vec2 gd = length(g) > 0.001 ? normalize(g) : vec2(1.0, 0.0);
			float along = dot(wpos.xz, vec2(-gd.y, gd.x));
			float wob = (texture(noise_tex, vec2(along * 0.02, 0.5)).r - 0.5) * 0.35;
			float lw = l + wob;
			float rt = ruts(lw);
			float e = 0.04;
			float slope = (ruts(lw + e) - ruts(lw - e)) / (2.0 * e) * 0.09;
			vec2 fine = tn(snow_normal, wpos.xz * 0.9) * 0.18;
			vec3 road_n = normalize(n + vec3(gd.x * slope + fine.x, 0.0, gd.y * slope + fine.y));
			float dirt = texture(noise_tex, wpos.xz * 0.21).r;
			vec3 rc = mix(road_color * mix(0.95, 1.03, dirt), rut_color * mix(0.9, 1.08, dirt), clamp(rt, 0.0, 1.0));
			snow_c = mix(snow_c, rc, road);
			snw = normalize(mix(snw, road_n, road));
			s_rough = mix(s_rough, mix(0.5, 0.36, clamp(rt, 0.0, 1.0)), road);
		}
	}

	ALBEDO = mix(ralb, snow_c, s);
	ROUGHNESS = mix(rarm.g, s_rough, s);
	AO = mix(rarm.r, 1.0, s);
	AO_LIGHT_AFFECT = 0.2;
	SPECULAR = mix(0.4, 0.55, s);
	vec3 nw = normalize(mix(rn, snw, s));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// Glitzern: einzelne Eiskristalle, blickwinkelabhaengig, nur nah (gegen Flimmern), nicht auf der Fahrbahn
	float dist = length(VERTEX);
	if (glitter > 0.0 && dist < glitter_dist && s > 0.5) {
		vec3 cell = floor(wpos * glitter_density);
		float h = hash13(cell);
		float tw = fract(h * 17.3 + dot(normalize(VIEW), vec3(5.1, 3.7, 4.3)) * 1.6);
		float sp_on = step(0.985, h) * smoothstep(0.88, 1.0, tw);
		float fade = 1.0 - smoothstep(glitter_dist * 0.4, glitter_dist, dist);
		EMISSION = vec3(0.9, 0.95, 1.0) * sp_on * glitter * fade * s * (1.0 - road);
	}
}
