shader_type spatial;
// Fahrzeuglack (Panzer/Hubschrauber): objektfestes Triplanar-Mapping, keine UVs noetig.
// Vertex-Farbe (siehe mesh_kit.gd): r = Lack, g = Gummi, b = Akzent, a = Helligkeit.
// CUSTOM0 = (y, z, Radius) -> Rad dreht im Vertex-Shader um die X-Achse (spin = Weg in m).
// Detail: Poly Haven "green_metal_rust" (CC0) fuer Rost, Normalen und AO; Tarnung aus vehicle_noise.png.
render_mode cull_back, depth_draw_opaque;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rust_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rust_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rust_arm : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec3 camo_a : source_color = vec3(0.25, 0.27, 0.18);   // Grundton
uniform vec3 camo_b : source_color = vec3(0.12, 0.13, 0.09);   // dunkle Flecken
uniform vec3 camo_c : source_color = vec3(0.33, 0.30, 0.22);   // helle Flecken
uniform float camo_scale = 0.11;                                // Kacheln pro Meter
uniform vec2 camo_split = vec2(0.34, 0.70);
uniform float camo_edge = 0.015;
uniform vec3 metal_col : source_color = vec3(0.17, 0.165, 0.155);
uniform vec3 rubber_col : source_color = vec3(0.035, 0.035, 0.033);
uniform vec3 accent_col : source_color = vec3(1.0, 0.62, 0.12);
uniform vec3 dirt_col : source_color = vec3(0.24, 0.205, 0.16);
uniform float detail_scale = 0.55;
uniform float rust_amount = 0.38;
uniform float chip_amount = 0.5;
uniform float dirt_height = 1.1;
uniform float dirt_amount = 0.85;
uniform float dust_amount = 0.35;
uniform float normal_strength = 0.7;
uniform float paint_rough = 0.66;
uniform float paint_metal = 0.0;
uniform float spin = 0.0;
uniform float snow_amount = 0.0;                                // Wracks im Schnee: Auflage auf waagrechten Flaechen
instance uniform float y_offset = 0.0;

varying vec3 v_pos;
varying vec3 v_n;
varying float v_ang;

void vertex() {
	v_pos = VERTEX;
	v_n = NORMAL;
	v_ang = 0.0;
	if (CUSTOM0.z > 0.001) {
		float a = -spin / CUSTOM0.z;
		v_ang = a;
		float c = cos(a);
		float s = sin(a);
		vec2 d = VERTEX.yz - CUSTOM0.xy;
		VERTEX.yz = CUSTOM0.xy + vec2(d.x * c - d.y * s, d.x * s + d.y * c);
		NORMAL.yz = vec2(NORMAL.y * c - NORMAL.z * s, NORMAL.y * s + NORMAL.z * c);
	}
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 tri_s(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	vec3 n0 = normalize(v_n);
	vec3 w = tri_w(n0);
	vec3 p = v_pos;
	float paint = COLOR.r;
	float rubber = COLOR.g;
	float accent = COLOR.b;

	float camo = tri_s(noise_tex, p * camo_scale, w).r;
	vec4 ng = tri_s(noise_tex, p * 0.42 + vec3(0.37, 0.11, 0.73), w);
	vec3 dp = p * detail_scale;
	vec3 d_alb = tri_s(rust_albedo, dp, w).rgb;
	vec3 arm = tri_s(rust_arm, dp, w).rgb;
	float lum = dot(d_alb, vec3(0.333));

	// Dreifarb-Tarnung mit leicht ausgefransten Kanten
	float cn = camo + (ng.b - 0.5) * 0.04;
	vec3 pc = camo_a;
	pc = mix(pc, camo_b, smoothstep(camo_split.x + camo_edge, camo_split.x - camo_edge, cn));
	pc = mix(pc, camo_c, smoothstep(camo_split.y - camo_edge, camo_split.y + camo_edge, cn));
	pc = mix(pc, accent_col, accent);
	pc *= 0.82 + 0.55 * lum;
	// Rost: rote Bereiche der Detailtextur, gebuendelt ueber das Schmutzrauschen
	float rustm = clamp((d_alb.r - d_alb.g) * 6.0 - 0.15, 0.0, 1.0);
	rustm *= rust_amount * smoothstep(0.25, 0.75, ng.g + 0.2);
	// Lackabplatzer
	float chip = smoothstep(0.86, 0.9, ng.b + (1.0 - chip_amount) * 0.1) * chip_amount;
	vec3 bare = metal_col * (0.65 + 0.9 * lum);
	vec3 painted = mix(pc, bare * 0.8, chip);
	painted = mix(painted, d_alb * vec3(0.85, 0.7, 0.6), rustm);
	vec3 metal = mix(bare, d_alb * vec3(1.0, 0.85, 0.75), rustm * 0.8);
	vec3 alb = mix(metal, painted, paint);
	alb = mix(alb, rubber_col * (0.8 + 0.5 * lum), rubber);
	alb *= COLOR.a;

	// Schmutz unten, Staub auf waagrechten Flaechen
	float h = v_pos.y + y_offset;
	float dirt = (1.0 - smoothstep(0.0, dirt_height, h)) * dirt_amount * (0.45 + 0.8 * ng.g);
	float dust = smoothstep(0.55, 0.95, n0.y) * dust_amount * smoothstep(0.3, 0.8, ng.g);
	alb = mix(alb, dirt_col, clamp(dirt, 0.0, 1.0));
	alb = mix(alb, dirt_col * 1.3, clamp(dust, 0.0, 1.0));
	alb *= mix(1.0, arm.r, 0.35);

	float rough = mix(0.42, paint_rough, paint);
	rough = mix(rough, 0.9, max(rubber, rustm));
	rough = mix(rough, 0.95, clamp(dirt + dust, 0.0, 1.0));
	rough = clamp(rough * (0.75 + 0.5 * arm.g), 0.05, 1.0);
	float metallic = mix(0.75, paint_metal, paint);
	metallic = mix(metallic, 0.65, chip * paint);
	metallic *= (1.0 - rubber) * (1.0 - rustm) * (1.0 - clamp(dirt + dust, 0.0, 1.0));
	if (snow_amount > 0.0) {
		// Schnee auf nach oben zeigenden Flaechen (Objektraum), Rand ausgefranst ueber das Rauschen
		float up = n0.y + (ng.r - 0.5) * 0.35;
		float snow = smoothstep(0.42, 0.7, up) * snow_amount;
		snow = max(snow, (1.0 - smoothstep(0.0, 0.35, h)) * snow_amount * 0.8);
		alb = mix(alb, vec3(0.78, 0.8, 0.84) * (0.9 + 0.2 * ng.b), snow);
		rough = mix(rough, 0.75, snow);
		metallic *= 1.0 - snow;
	}

	// Triplanare Normalen (Whiteout-Blend) im Objektraum
	vec3 tx = texture(rust_normal, dp.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(rust_normal, dp.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(rust_normal, dp.xy).xyz * 2.0 - 1.0;
	float ns = normal_strength * (1.0 - rubber * 0.5);
	tx.xy *= ns;
	ty.xy *= ns;
	tz.xy *= ns;
	tx = vec3(tx.xy + n0.zy, abs(tx.z) * n0.x);
	ty = vec3(ty.xy + n0.xz, abs(ty.z) * n0.y);
	tz = vec3(tz.xy + n0.xy, abs(tz.z) * n0.z);
	vec3 nb = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	if (v_ang != 0.0) {
		float c = cos(v_ang);
		float s = sin(v_ang);
		nb.yz = vec2(nb.y * c - nb.z * s, nb.y * s + nb.z * c);
	}
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(nb, 0.0))).xyz);

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metallic;
	AO = mix(1.0, arm.r, 0.5);
}
