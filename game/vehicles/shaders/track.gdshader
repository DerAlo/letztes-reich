shader_type spatial;
// Panzerkette: Kettenglieder laufen ueber die lokale Z-Achse des Segments.
// scroll (Material, pro Seite) = zurueckgelegter Weg in m; instance dir = +1/-1 je nach Laufrichtung des Segments.
render_mode cull_back;

uniform float scroll = 0.0;
uniform float link_len = 0.17;
uniform vec3 steel : source_color = vec3(0.16, 0.15, 0.14);
uniform vec3 rust : source_color = vec3(0.24, 0.17, 0.11);
instance uniform float dir = 1.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float f = fract((v_local.z * dir + scroll) / link_len);
	// Spalt zwischen den Gliedern, Steg (Grouser) in der Mitte
	float gap = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.94, 1.0, f));
	float grouser = smoothstep(0.38, 0.45, f) * (1.0 - smoothstep(0.55, 0.62, f));
	float side = smoothstep(0.42, 0.5, abs(v_local.x) / 0.32);
	vec3 c = mix(rust, steel, 0.6 + 0.4 * grouser);
	c *= mix(0.25, 1.0, gap);
	c = mix(c, steel * 0.7, side * 0.5);
	ALBEDO = c;
	METALLIC = 0.7 * gap;
	ROUGHNESS = mix(0.85, 0.45, grouser);
	// leichte Normal-Variation fuer Relief
	NORMAL = normalize(NORMAL + (grouser - 0.5) * 0.25 * TANGENT);
}
