shader_type spatial;
// Waermebild-Material fuer alle Objekte der Gunship-Mission ("Waechter").
// Vertex-Farbe: r = Temperatur (0 kalt .. 1 heiss, >1 gluehend), g = Rausch-Variation, b = Formschattierung.
// Ausgabe ist ein Grauwert (Temperatur); Polaritaet, Korn und Kontrast macht thermal_post.gdshader.
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 0.13;
uniform float haze_k = 0.00022;      // atmosphaerische Daempfung pro Meter
uniform float haze_heat = 0.24;      // Temperatur, zu der der Dunst hin mischt
uniform float custom_heat_amt = 0.0; // MultiMesh: (INSTANCE_CUSTOM.r - 0.5) als Waerme-Versatz
uniform float custom_scale = 0.0;    // MultiMesh: INSTANCE_CUSTOM.g skaliert die Temperatur
instance uniform float heat_add = 0.0;   // pro Objekt: Brand, Abwaerme
instance uniform float heat_mul = 1.0;   // pro Objekt: Auskuehlen (Tote, Wracks)

varying vec3 wpos;
varying vec3 wn;
varying float inst_heat;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	inst_heat = (INSTANCE_CUSTOM.r - 0.5) * custom_heat_amt;
	inst_heat += COLOR.r * (INSTANCE_CUSTOM.g - 0.5) * custom_scale;
}

void fragment() {
	float heat = COLOR.r * heat_mul + heat_add + inst_heat;
	vec3 bw = abs(wn);
	bw /= (bw.x + bw.y + bw.z + 1e-4);
	float n = texture(noise_tex, wpos.zy * noise_scale).r * bw.x
		+ texture(noise_tex, wpos.xz * noise_scale).r * bw.y
		+ texture(noise_tex, wpos.xy * noise_scale).r * bw.z;
	float n2 = texture(noise_tex, wpos.xz * noise_scale * 6.7 + vec2(wpos.y * 3.1)).r;
	heat += (n - 0.5) * COLOR.g * 2.0 + (n2 - 0.5) * COLOR.g * 0.7;
	// Form: Dachflaechen strahlen in den Nachthimmel ab (kuehler), Suedwaende halten Tageswaerme
	heat += (-wn.y * 0.035 + dot(wn, normalize(vec3(-0.35, 0.0, 0.94))) * 0.05) * COLOR.b;
	// flacher Blickwinkel: geringerer Emissionsgrad -> Kanten etwas kuehler
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	heat -= fres * fres * 0.07 * COLOR.b;
	float d = length(VERTEX);
	heat = mix(heat, haze_heat, 1.0 - exp(-d * haze_k));
	ALBEDO = vec3(pow(max(heat, 0.0), 2.2));
}
