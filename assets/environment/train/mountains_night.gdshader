shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, fog_disabled;
// Nachtzug-Variante (Kopie von villa/mountains.gdshader, ohne Szenennebel: der dichte Talnebel
// wuerde die Hoehenzuege heller als den Nachthimmel faerben; Dunst kommt nur aus haze_*).
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
uniform vec3 rock_tint : source_color = vec3(0.62, 0.6, 0.57);
uniform vec3 snow_color : source_color = vec3(0.86, 0.88, 0.93);
uniform vec3 haze_color : source_color = vec3(0.36, 0.4, 0.52);
uniform float haze_k = 0.00028;
uniform float haze_energy = 0.32;
// Talnebel-Band: der Hangfuss geht in den (vom Szenennebel aufgehellten) Bodendunst ueber, damit
// der Hoehenzug nicht als dunkle "Hoehlendecke" ueber grauem Nebel schwebt. Gipfel bleiben dunkel.
uniform vec3 valley_color : source_color = vec3(0.0);
uniform float valley_lo = 40.0;
uniform float valley_hi = 260.0;
uniform float valley_strength = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float slope = 1.0 - n.y;
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
	float rw = max(smoothstep(0.42, 0.62, slope + (fine - 0.5) * 0.18), smoothstep(treeline + 60.0, treeline + 320.0, hh));
	vec3 col = mix(forest, meadow, mw);
	col = mix(col, rock, clamp(rw, 0.0, 1.0));
	float sn = smoothstep(snowline, snowline + 140.0, wpos.y + (big - 0.5) * 300.0 + (fine - 0.5) * 120.0);
	sn *= 1.0 - smoothstep(0.45, 0.7, slope + (fine2 - 0.5) * 0.2);
	col = mix(col, snow_color * (0.9 + fine2 * 0.1), sn);

	// Luftperspektive: Grundfarbe verblasst, Dunst leuchtet (Abenddaemmerung)
	float d = length(wpos - CAMERA_POSITION_WORLD);
	float hz = 1.0 - exp(-d * haze_k);
	hz *= mix(1.0, 0.9, smoothstep(0.0, 1400.0, wpos.y));
	float vf = valley_strength * (1.0 - smoothstep(valley_lo, valley_hi, wpos.y + (mid - 0.5) * 60.0));
	ALBEDO = col * (1.0 - hz * 0.85) * (1.0 - vf);
	EMISSION = mix(haze_color * hz * haze_energy, valley_color, vf);
	ROUGHNESS = mix(0.95, 0.6, sn);
	SPECULAR = mix(0.15, 0.4, sn);
}
