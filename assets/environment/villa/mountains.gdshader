shader_type spatial;
// fog_disabled: der Szenennebel (0.0006/m) machte die Berge in 2-6 km zu flachen Nebel-Silhouetten;
// die Luftperspektive kommt hier im Shader hoehenabhaengig (Fuss dunstig, Grate plastisch).
render_mode diffuse_burley, specular_schlick_ggx, fog_disabled;
// Berge rund um den Traunsee (Hoehenfeld-Mesh): Wald, Almwiesen, Fels (Hangneigung/Hoehe) und
// Schneereste in Mulden. Fels triplanar aus Poly-Haven-Textur, Wald als fleckige Kronenstruktur.
// Zusaetzlicher Dunst nach Entfernung (Luftperspektive) zum eingebauten Nebel.

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float rock_scale = 0.012;
uniform float treeline = 900.0;
uniform float snowline = 1250.0;
uniform vec3 forest_color : source_color = vec3(0.05, 0.075, 0.04);
uniform vec3 meadow_color : source_color = vec3(0.17, 0.21, 0.09);
uniform vec3 rock_tint : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 snow_color : source_color = vec3(0.86, 0.88, 0.93);
uniform vec3 haze_color : source_color = vec3(0.36, 0.4, 0.52);
uniform vec3 haze_sun_color : source_color = vec3(0.95, 0.6, 0.42);  // Dunst Richtung Abendsonne (warm)
uniform vec3 sun_dir = vec3(-0.66, 0.06, -0.75);                      // Richtung zur Sonne (Welt)
uniform float haze_k = 0.0006;
uniform float haze_h = 1300.0;      // Dunst sitzt unten: Dichte faellt mit exp(-y / haze_h)
uniform float haze_energy = 1.05;
uniform float relief = 1.0;        // Staerke der Detail-Normalen (Rinnen, Rippen, Felsbaender)

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Hoehendetail aus der Rauschtextur (Meter): grobe Rippen + Rinnen (ridged), feine Felsbaender
float detail_h(vec2 p) {
	float a = texture(noise_tex, p * 0.0019 + 0.17).r;
	float b = texture(noise_tex, p * 0.0062 + 0.53).r;
	float c = texture(noise_tex, p * 0.019 + 0.91).r;
	float ra = 1.0 - abs(a * 2.0 - 1.0);
	float rb = 1.0 - abs(b * 2.0 - 1.0);
	return ra * ra * 70.0 + rb * 24.0 + c * 7.0;
}

void fragment() {
	vec3 n0 = normalize(wnrm);
	// Detail-Normale: Gradient des Hoehendetails, nur an Haengen (Wiesen/Ufer bleiben ruhig)
	float e = 6.0;
	float h0 = detail_h(wpos.xz);
	vec2 g = vec2(detail_h(wpos.xz + vec2(e, 0.0)) - h0, detail_h(wpos.xz + vec2(0.0, e)) - h0) / e;
	float steep = smoothstep(0.08, 0.35, 1.0 - n0.y) * smoothstep(20.0, 160.0, wpos.y);
	vec3 n = normalize(n0 - vec3(g.x, 0.0, g.y) * relief * steep * 1.6);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float slope = 1.0 - mix(n0.y, n.y, 0.3);   // Bewuchs nach der Grossform, Detail nur leicht
	float big = texture(noise_tex, wpos.xz * 0.00045).r;
	float mid = texture(noise_tex, wpos.xz * 0.0031 + 0.3).r;
	float fine = texture(noise_tex, wpos.xz * 0.027 + 0.7).r;
	float fine2 = texture(noise_tex, wpos.xz * 0.11).r;

	// Fels triplanar
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos * rock_scale;
	vec3 rock = texture(rock_albedo, p.zy).rgb * w.x + texture(rock_albedo, p.xz).rgb * w.y + texture(rock_albedo, p.xy).rgb * w.z;
	rock = rock * rock_tint * (0.75 + mid * 0.5);

	// Wald: fleckige Kronen, an der Baumgrenze lichter
	vec3 forest = forest_color * (0.6 + fine * 0.5 + fine2 * 0.35);
	vec3 meadow = meadow_color * (0.8 + fine * 0.4);
	float hh = wpos.y + (mid - 0.5) * 220.0;
	float mw = smoothstep(0.6, 0.72, mid * 0.7 + big * 0.3) * (1.0 - smoothstep(0.35, 0.55, slope));
	mw = max(mw, smoothstep(treeline - 150.0, treeline + 80.0, hh) * (1.0 - smoothstep(0.4, 0.6, slope)));
	mw = max(mw, (1.0 - smoothstep(2.0, 14.0, wpos.y)) * 0.8); // Uferstreifen
	float rw = max(smoothstep(0.5, 0.7, slope + (fine - 0.5) * 0.18), smoothstep(treeline + 60.0, treeline + 320.0, hh));
	vec3 col = mix(forest, meadow, mw);
	col = mix(col, rock, clamp(rw, 0.0, 1.0));
	float sn = smoothstep(snowline, snowline + 140.0, wpos.y + (big - 0.5) * 300.0 + (fine - 0.5) * 120.0);
	sn *= 1.0 - smoothstep(0.45, 0.7, slope + (fine2 - 0.5) * 0.2);
	col = mix(col, snow_color * (0.9 + fine2 * 0.1), sn);

	// Luftperspektive: Grundfarbe verblasst, Dunst leuchtet (Abenddaemmerung)
	// Hoehenabhaengig: Hangfuss verschwimmt im Seedunst, Grate und Gipfel bleiben plastisch.
	vec3 vd = wpos - CAMERA_POSITION_WORLD;
	float d = length(vd);
	float hz = 1.0 - exp(-d * haze_k * exp(-max(wpos.y, 0.0) / haze_h));
	// Rinnen/Rippen leicht abdunkeln bzw. aufhellen (Umgebungsverdeckung im Grossen)
	col *= 0.82 + 0.36 * smoothstep(20.0, 80.0, h0) * steep + 0.18 * (1.0 - steep);
	float sunf = pow(max(dot(vd / max(d, 1.0), normalize(sun_dir)), 0.0), 3.0);
	vec3 hc = mix(haze_color, haze_sun_color, sunf);
	ALBEDO = col * (1.0 - hz * 0.85);
	EMISSION = hc * hz * haze_energy;
	ROUGHNESS = mix(0.95, 0.6, sn);
	SPECULAR = mix(0.15, 0.4, sn);
}
