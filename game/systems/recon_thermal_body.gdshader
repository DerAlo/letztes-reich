shader_type spatial;
// Waermebild-Material der Aufklaerungsdrohne (game/systems/recon_drone.gd) fuer warme Ziele (Wachen, Personen).
// Ersetzt im Waermebild die normalen Materialien der Figur JE OBERFLAECHE, damit die Temperatur stimmt:
// Haut (Gesicht, Haende) am waermsten, Uniform darunter (Beine kuehler als Rumpf), Weste/Taschen deutlich
// kuehler (isolieren), Helm fast Umgebung, getragene Waffe/Metall auf Umgebungstemperatur.
// heat = Sensorwert 0..1 nach dem Overlay recon_drone_thermal.gdshader (0.97 Haut .. 0.17 Umgebung);
// die Drohnenkamera rendert linear mit Belichtung `exposure` -> ALBEDO so, dass im Bildschirm (sRGB) genau heat ankommt.
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform float heat = 0.74;
// 0 = einheitlich, 1 = Koerperstoff in der Ruhepose (Beine kuehler, Stiefel kalt, Handschuhe/Haende warm),
// 2 = Operator-Atlas Weste/Helm/Kopf (obere Atlas-Haelfte = Gesicht/Sturmhaube warm, untere = Ausruestung)
uniform int region = 0;
uniform float exposure = 0.42;
uniform vec3 hand_l = vec3(0.18, 1.08, 0.21);
uniform vec3 hand_r = vec3(-0.19, 1.25, 0.26);
uniform float hand_heat = 0.9;
uniform float boot_y = 0.3;
uniform float face_heat = 0.93;
uniform float gear_heat = 0.5;

varying vec3 v_rp;

void vertex() {
	v_rp = CUSTOM0.xyz;
	if (dot(CUSTOM1.xyz, CUSTOM1.xyz) < 0.01) {
		v_rp = VERTEX;
	}
}

float to_linear(float s) {
	return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4);
}

void fragment() {
	float h = heat;
	if (region == 1) {
		// Rumpf am waermsten, Oberschenkel/Waden etwas kuehler (Kleidung steht ab, weniger Durchblutung)
		h *= mix(0.86, 1.0, smoothstep(0.45, 1.05, v_rp.y));
		// Stiefel: dickes Leder/Gummi -> nahe Umgebung
		h = mix(h, gear_heat * 0.8, 1.0 - smoothstep(boot_y - 0.05, boot_y + 0.03, v_rp.y));
		// Haende/Handschuhe: duenn, stark durchblutet -> fast Hauttemperatur
		float dh = min(distance(v_rp, hand_l), distance(v_rp, hand_r));
		h = mix(h, hand_heat, 1.0 - smoothstep(0.07, 0.13, dh));
	} else if (region == 2) {
		h = UV.y < 0.5 ? face_heat : gear_heat;
	}
	// flacher Blickwinkel: geringerer Emissionsgrad -> Silhouettenkanten etwas kuehler (Koerper wirkt rund)
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	h *= 1.0 - 0.16 * pow(1.0 - ndv, 2.0);
	ALBEDO = vec3(to_linear(clamp(h, 0.0, 1.0)) / exposure);
}
