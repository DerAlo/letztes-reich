shader_type spatial;
// Ausgebranntes Fahrzeug: objektfestes Triplanar-Mapping (keine UVs noetig), beidseitig.
// Vertex-Farbe wie vehicle_paint (mesh_kit/Marder): r = Lackflaeche, g = Gummi/Verkohlt, a = Helligkeit.
// Aufbau: orangebrauner Brandrost (Poly Haven rust_coarse_01) unten/innen, grau-weisse Ascheschicht
// (rusty_metal_04) oben, Russfahnen, Lackreste (paint_color) knapp ueber dem Boden, Asche-/Schmutzsaum unten.
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rust_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rust_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rust_arm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ash_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ash_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform float rust_scale = 0.9;            // Kacheln pro Meter
uniform float ash_scale = 0.55;
uniform vec3 rust_tint : source_color = vec3(0.7, 0.58, 0.5);
uniform vec3 ash_tint : source_color = vec3(0.78, 0.76, 0.73);
uniform vec3 soot_col : source_color = vec3(0.028, 0.026, 0.024);
uniform vec3 ground_col : source_color = vec3(0.12, 0.11, 0.1);
uniform float ash_amount = 0.95;
uniform float soot_amount = 0.7;
uniform float paint_amount = 0.6;
uniform float normal_strength = 0.9;
uniform float snow_amount = 0.0;
instance uniform vec4 paint_color : source_color = vec4(0.3, 0.3, 0.3, 1.0);
instance uniform float body_h = 1.4;       // Hoehe des Fahrzeugs (fuer Asche oben / Lackreste unten)
instance uniform float y_offset = 0.0;     // Knotenhoehe ueber dem Fahrzeugboden
instance uniform float seed = 0.0;

varying vec3 v_pos;
varying vec3 v_n;
varying vec3 v_wn;

void vertex() {
	v_pos = VERTEX;
	v_n = NORMAL;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 tri_s(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

vec3 tri_n(sampler2D t, vec3 p, vec3 w, vec3 n0, float s) {
	vec3 tx = texture(t, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(t, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(t, p.xy).xyz * 2.0 - 1.0;
	tx.xy *= s;
	ty.xy *= s;
	tz.xy *= s;
	tx = vec3(tx.xy + n0.zy, abs(tx.z) * n0.x);
	ty = vec3(ty.xy + n0.xz, abs(ty.z) * n0.y);
	tz = vec3(tz.xy + n0.xy, abs(tz.z) * n0.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

void fragment() {
	vec3 n0 = normalize(v_n);
	vec3 wn = normalize(v_wn);
	if (!FRONT_FACING) {
		n0 = -n0;
		wn = -wn;
	}
	vec3 w = tri_w(n0);
	vec3 p = v_pos + vec3(seed * 3.17, 0.0, seed * 1.93);
	float h = (v_pos.y + y_offset) / max(body_h, 0.3);
	float panel = COLOR.r;
	float charm = COLOR.g;

	vec4 ng = tri_s(noise_tex, p * 0.38, w);        // grosse Flecken
	vec4 nf = tri_s(noise_tex, p * 1.7 + vec3(0.31, 0.77, 0.13), w);   // feine Struktur
	vec3 dp = p * rust_scale;
	vec3 ap = p * ash_scale + vec3(0.5, 0.21, 0.37);
	vec3 rust = tri_s(rust_albedo, dp, w).rgb * rust_tint;
	vec3 arm = tri_s(rust_arm, dp, w).rgb;
	vec3 ash_t = tri_s(ash_albedo, ap, w).rgb;
	// Zunder/Asche: entsaettigtes Grau mit etwas Rostfarbe der Textur
	float ash_l = dot(ash_t, vec3(0.333));
	vec3 ash = mix(vec3(ash_l) * 1.1, ash_t, 0.55) * ash_tint;
	float lum = dot(rust, vec3(0.333));

	// Asche/Zunder: oben und auf waagrechten Flaechen grau-weiss, an Kanten in Rost uebergehend
	float up = clamp(n0.y, 0.0, 1.0);
	float am = smoothstep(0.18, 0.62, h + (ng.r - 0.5) * 0.7 + up * 0.3);
	am = clamp(am * ash_amount * panel, 0.0, 1.0);
	am *= 0.75 + 0.25 * smoothstep(0.3, 0.6, ash_l);
	vec3 alb = mix(rust, ash, am);
	// Russfahnen (Fensterkanten, Innenraum) und schwarz verkohlte Gummi-/Kunststoffteile
	float soot = smoothstep(0.52, 0.78, ng.b + (1.0 - panel) * 0.3) * soot_amount;
	// Russfahnen ueber den Fensterkanten (oberer Karosseriebereich, senkrecht)
	soot = max(soot, smoothstep(0.55, 0.75, h) * (1.0 - smoothstep(0.75, 0.95, h)) * smoothstep(0.45, 0.7, nf.r + ng.b * 0.4) * (1.0 - up) * 0.8 * panel);
	soot = max(soot, charm * (0.75 + 0.25 * nf.r));
	// Lackreste knapp ueber dem Schweller, ausgefranst
	float pm = (1.0 - smoothstep(0.12, 0.34, h + (ng.g - 0.5) * 0.35)) * paint_amount * panel;
	pm *= smoothstep(0.35, 0.6, nf.b + 0.15) * (1.0 - up);
	vec3 pc = paint_color.rgb * (0.45 + 0.6 * lum) * vec3(0.8, 0.75, 0.7);
	alb = mix(alb, pc, clamp(pm, 0.0, 1.0));
	alb = mix(alb, soot_col * (0.7 + 0.8 * nf.r), clamp(soot, 0.0, 1.0));
	// Asche-/Schmutzsaum am Boden
	float grime = (1.0 - smoothstep(0.0, 0.22, h + (nf.g - 0.5) * 0.1)) * 0.7;
	alb = mix(alb, ground_col * (0.8 + 0.5 * ng.g), grime);
	alb *= COLOR.a;
	alb *= mix(1.0, arm.r, 0.4);

	float rough = mix(0.82, 0.95, am);
	rough = mix(rough, 0.97, max(soot, grime));
	rough = mix(rough, 0.6, pm * 0.6);
	float metallic = mix(0.18, 0.0, max(am, max(soot, grime)));

	if (snow_amount > 0.0) {
		float sup = wn.y + (ng.r - 0.5) * 0.35;
		float snow = smoothstep(0.42, 0.72, sup) * snow_amount;
		float hw = v_pos.y + y_offset;
		snow = max(snow, (1.0 - smoothstep(0.0, 0.3, hw)) * snow_amount * 0.7 * smoothstep(0.2, 0.5, wn.y + 0.6));
		alb = mix(alb, vec3(0.8, 0.82, 0.86) * (0.9 + 0.2 * nf.b), snow);
		rough = mix(rough, 0.72, snow);
		metallic *= 1.0 - snow;
	}

	vec3 nr = tri_n(rust_normal, dp, w, n0, normal_strength);
	vec3 na = tri_n(ash_normal, ap, w, n0, normal_strength * 0.7);
	vec3 nb = normalize(mix(nr, na, am));
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(nb, 0.0))).xyz);

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metallic;
	AO = mix(1.0, arm.r, 0.6);
}
