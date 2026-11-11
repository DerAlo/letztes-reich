shader_type spatial;
// Schwere Panzerplatten (gepanzerte Gegner, Juggernaut). MeshKit-Geometrie, Vertex-Farbe = Lackfarbe,
// COLOR.a = Kanal: 1 = lackierte Platte, ~0.5 = Gummi/Stoffkante, 0 = blankes Metall (Schrauben, Beschlaege).
// Alle Muster prozedural im Objektraum (= Skelett-Ruhepose, schwimmt nicht bei Animation):
// abgeplatzter Lack an Kanten/Flaechen, feine Kratzer, Schmutz unten, Einschussmarken (hits[]),
// Schaden (instance uniform) laesst den Lack weiter abplatzen und schwaerzt die Platte.
render_mode cull_back, depth_draw_opaque;

uniform vec3 steel_col : source_color = vec3(0.46, 0.46, 0.45);
uniform vec3 dirt_col : source_color = vec3(0.16, 0.14, 0.11);
uniform float chip_amount = 0.35;
uniform float scratch_amount = 0.55;
uniform float dirt_amount = 0.45;
uniform float paint_rough = 0.62;
uniform float paint_metal = 0.15;
uniform float noise_scale = 1.0;
uniform vec4 hits[8];   // xyz = Treffer im Objektraum, w = Radius (0 = leer)
instance uniform float damage = 0.0;

varying vec3 v_p;
varying vec3 v_n;

void vertex() {
	v_p = VERTEX;
	v_n = NORMAL;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
				   mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				   mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec3 p = v_p * noise_scale;
	vec3 base = COLOR.rgb;
	float chan = COLOR.a;
	float paint = step(0.75, chan);
	float rubber = step(0.25, chan) * (1.0 - paint);

	// Grossflaechige Farbvariation (Lackflecken, ausgeblichen)
	float blot = fbm(p * 7.0);
	vec3 alb = base * (0.82 + 0.36 * blot);
	// Abgeplatzter Lack: Kanten (Normale wechselt schnell) + Flaechenrauschen, waechst mit damage
	float edge = clamp(length(fwidth(v_n)) * 6.0, 0.0, 1.0);
	float chipn = fbm(p * 46.0 + vec3(4.0, 1.0, 7.0)) * 0.75 + vnoise(p * 140.0) * 0.25;
	float chip_th = 0.8 - chip_amount * 0.12 - damage * 0.22 - edge * 0.26;
	float chip = smoothstep(chip_th, chip_th + 0.02, chipn) * paint;
	// heller Grundierungsrand um abgeplatzte Stellen
	float primer = smoothstep(chip_th - 0.035, chip_th, chipn) * (1.0 - chip) * paint;
	// Feine Kratzer: gestreckte Rauschbaender in zwei Richtungen
	float s1 = abs(vnoise(vec3(p.x * 9.0 + p.z * 4.0, p.y * 260.0 + p.x * 40.0, p.z * 9.0)) * 2.0 - 1.0);
	float s2 = abs(vnoise(vec3(p.x * 220.0 + p.y * 60.0, p.y * 8.0, p.z * 220.0 - p.y * 30.0)) * 2.0 - 1.0);
	float mask = smoothstep(0.55, 0.7, fbm(p * 5.0 + vec3(2.0)));
	float scratch = (1.0 - smoothstep(0.0, 0.05, s1) + 1.0 - smoothstep(0.0, 0.035, s2)) * mask * scratch_amount * paint;
	scratch = clamp(scratch, 0.0, 1.0);

	alb = mix(alb, alb * 1.25 + vec3(0.04), primer * 0.6);
	vec3 steel = steel_col * (0.75 + 0.5 * vnoise(p * 90.0));
	float bare = max(chip, scratch * 0.8);
	alb = mix(alb, steel, bare);
	float metal = mix(paint_metal, 0.9, bare);
	float rough = mix(paint_rough + 0.15 * blot, 0.32, bare);
	if (chan < 0.25) {   // Beschlaege/Schrauben
		alb = base * (0.8 + 0.4 * vnoise(p * 60.0));
		metal = 0.85;
		rough = 0.38;
	}
	if (rubber > 0.5) {
		alb = base * (0.85 + 0.2 * blot);
		metal = 0.0;
		rough = 0.9;
	}

	// Einschussmarken: blanker Krater, dunkler Abbrand-Ring, Lack rundum weg
	for (int i = 0; i < 8; i++) {
		vec4 h = hits[i];
		if (h.w <= 0.0) {
			continue;
		}
		float d = length(v_p - h.xyz) / h.w;
		float jag = 0.75 + 0.5 * vnoise(v_p * 160.0 + float(i) * 3.1);
		float core = 1.0 - smoothstep(0.18 * jag, 0.3 * jag, d);
		float ring = (1.0 - smoothstep(0.3, 1.0 * jag, d)) * (1.0 - core);
		alb = mix(alb, steel_col * 0.35, ring * 0.75);
		alb = mix(alb, steel_col * 1.35, core);
		metal = mix(metal, 1.0, core);
		rough = mix(rough, 0.22, core);
		rough = mix(rough, 0.85, ring * 0.5);
	}

	// Schmutz/Russ: unten (Spritzer) + mit Schaden zunehmend schwarz
	float grime = (1.0 - smoothstep(0.0, 0.7, v_p.y)) * dirt_amount * (0.4 + 0.8 * fbm(p * 11.0));
	grime += damage * 0.45 * smoothstep(0.35, 0.7, fbm(p * 4.0 + vec3(5.0)));
	alb = mix(alb, dirt_col, clamp(grime, 0.0, 0.85));
	rough = mix(rough, 0.95, clamp(grime, 0.0, 1.0) * 0.6);

	ALBEDO = alb;
	METALLIC = metal;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.5;
}
