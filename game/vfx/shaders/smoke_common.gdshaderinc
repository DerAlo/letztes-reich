// Weicher, beleuchteter Rauch / Staub (Runde 2).
// - Flipbook 8x8 (assets/vfx/smoke_flipbook.png): A = Dichte, RG = Normale, B = Dicke.
//   Jedes Partikel startet bei einem zufaelligen Frame und blendet waehrend der Lebenszeit ueber
//   `frame_span` Folge-Frames (benachbarte Frames sind Schnitte durch dasselbe 3D-Noise -> Quellen).
// - Soft Particles (Tiefen-Fade gegen Geometrie, skaliert mit Partikelgroesse) + Kamera-Nah-Fade.
// - Beleuchtung: Half-Lambert + Vorwaertsstreuung (Gegenlicht leuchtet an duennen Raendern),
//   Schatten ueber ATTENUATION. Glut-Toenung von unten (Hoehe ueber Feuer) oder nach Alter (Explosion).
// - Farbe ueber die Lebenszeit von russig-dunkel nach hellgrau.
// Runde 4 (fx2): Flipbook 8x8 a 256 px (assets/vfx/gen_smoke.py) + animierte Detail-Schicht
//   (assets/vfx/smoke_detail.png: RG = Curl-Verzerrung, B = feines Billow-Noise): verwirbelt die
//   Flipbook-UVs leicht und zerfasert duenne Raender (2 Samples). Glut-Toenung im Hoehen-Modus jetzt
//   pro Fragment (Weltkoordinate) statt pro Partikel -> weicher Verlauf statt oranger Flecken.
//   Flipbook jetzt schlierig/ausgefranst (keine Watte-Kugeln), lineares Frame-Blending (gleichmaessiges
//   Quellen ohne Ruckeln), dezentere Streuung. Gedacht fuer viele, sehr transparente Partikel.
//   Seed pro Partikel ohne INSTANCE_ID (die wechselt bei Tiefensortierung -> war Hauptursache fuers Flimmern).
// Gemeinsamer Code fuer smoke_billboard (mit Schatten) und smoke_billboard_fast (ohne Schatten).

uniform sampler2D flipbook : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 1.35;      // Kacheln der Detail-Schicht pro Partikel
uniform float detail_distort = 0.03;    // UV-Verwirbelung (Anteil der Partikelbreite)
uniform float detail_erode = 0.3;       // Zerfaserung duenner Bereiche (waechst mit dem Alter)
uniform float detail_speed = 0.25;      // Scroll der Detail-Schicht ueber die Lebenszeit
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 smoke_color : source_color = vec3(0.07, 0.066, 0.062);      // jung (russig)
uniform vec3 smoke_color_end : source_color = vec3(0.3, 0.295, 0.29);    // alt (hellgrau)
uniform float color_shift = 0.8;        // Exponent fuer den Farbverlauf ueber die Lebenszeit
uniform float density = 1.0;
uniform float erosion = 0.3;            // Raender duennen mit dem Alter aus (weich, kein Dissolve)
uniform float frame_span = 6.0;         // Anzahl Flipbook-Frames ueber die Lebenszeit
uniform float soft_dist = 1.0;          // Mindest-Fade-Distanz gegen Geometrie (m)
uniform float soft_size_factor = 0.35;  // + Anteil der Partikelgroesse
uniform float near_fade = 1.2;          // Kamera-Nah-Fade (m)
uniform float close_cull = 0.9;         // Partikel naeher als close_cull*Groesse blenden aus und
                                        // werden unter 0.4*Groesse zu Null skaliert (Overdraw-Schutz)
uniform float self_shadow = 0.55;       // dichte Kerne dunkler
uniform float wrap = 0.6;               // Half-Lambert-Wrap
uniform float scatter = 1.3;            // Vorwaertsstreuung (Gegenlicht), dezent
uniform float scatter_power = 5.0;
uniform float normal_strength = 1.0;
uniform float point_light_scale = 0.6; // Punkt-/Spotlichter (z.B. Feuerschein) auf Rauch daempfen
uniform vec3 glow_color : source_color = vec3(1.0, 0.36, 0.08);
uniform float glow = 0.0;
uniform float glow_decay = 8.0;         // Alters-Modus: pow(1-life, glow_decay)
uniform float glow_height = 0.0;        // > 0: Hoehen-Modus (Feuer von unten), Abfall in m
uniform float glow_origin_y = 0.0;

varying float v_life;
varying float v_seed;
varying float v_y;
varying float v_size;
varying float v_thin;
varying float v_close;

void vertex() {
	v_life = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	// stabil ueber die Lebenszeit: NUR anim_offset (zufaellig pro Spawn, anim_speed = 0).
	// fx2-Fix: frueher + INSTANCE_ID - bei DRAW_ORDER_VIEW_DEPTH ist INSTANCE_ID aber der Index in der
	// jedes Frame neu sortierten Liste -> bei jedem Sortierwechsel sprang ein Partikel auf ein anderes
	// Flipbook-Frame/Detail-Offset = Flimmern.
	v_seed = fract(INSTANCE_CUSTOM.z * 7.31 + INSTANCE_CUSTOM.z * INSTANCE_CUSTOM.z * 3.17);
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_size = sc.x;
	v_y = MODEL_MATRIX[3].y;
	// Overdraw-Schutz: grosse Partikel direkt vor/um die Kamera fuellen sonst den ganzen Schirm
	float cd = length((VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz);
	v_close = smoothstep(sc.x * 0.4, sc.x * max(close_cull, 0.41), cd);
	sc *= step(0.001, v_close);
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]) * sc.x, normalize(INV_VIEW_MATRIX[1]) * sc.y, normalize(INV_VIEW_MATRIX[2]) * sc.z, MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	mw = mw * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
}

vec4 frame_sample(float f, vec2 uv) {
	vec2 cell = vec2(mod(f, 8.0), floor(f / 8.0));
	return texture(flipbook, (cell + uv) * 0.125);
}

void fragment() {
	float life = v_life;
	// Detail-Schicht: pro Partikel versetzt, langsam scrollend/aufsteigend
	vec2 doff = vec2(v_seed * 7.13, fract(v_seed * 3.71) * 5.0);
	vec4 dn = texture(detail_tex, UV * detail_scale + doff + vec2(0.0, life * detail_speed));
	vec2 duv = clamp(UV + (dn.rg * 2.0 - 1.0) * detail_distort * (0.6 + life), vec2(0.004), vec2(0.996));
	float fr = v_seed * (63.0 - frame_span) + life * frame_span;
	float f0 = min(floor(fr), 62.0);
	// lineares Blending: konstante "Quell"-Geschwindigkeit, kein Haken an Frame-Grenzen
	vec4 t = mix(frame_sample(f0, duv), frame_sample(f0 + 1.0, duv), clamp(fr - f0, 0.0, 1.0));

	// Alters-Erosion auf der GEGLAETTETEN Dichte (B): Wolke zieht sich weich zusammen und duennt aus,
	// ohne die feinen Strukturen in A hart abzuschneiden (sonst zerknitterte Papier-Kanten)
	float e = erosion * life;
	float k = clamp((t.b - 0.6 * e) / 0.45, 0.0, 1.0);
	float a = t.a * mix(1.0, k * k * (3.0 - 2.0 * k), min(e * 4.0, 1.0)) * (1.0 - 0.35 * e);
	// feine Zerfaserung: duenne Bereiche werden von feinem Noise multiplikativ ausgeduennt
	float fine = texture(detail_tex, UV * detail_scale * 2.7 + doff.yx - vec2(life * detail_speed * 1.6, 0.0)).b;
	a *= mix(1.0, clamp(fine * 1.5, 0.0, 1.0), detail_erode * (0.6 + 0.4 * life) * (1.0 - a));
	a = clamp(a * density * COLOR.a, 0.0, 1.0);
	if (a * v_close < 0.004) {
		discard; // leere Quad-Ecken: spart Beleuchtung/Blending (Overdraw)
	}

	// Normale: Textur-Normale + leichte Kugelwoelbung, im gedrehten Billboard-Raum
	vec2 p = UV * 2.0 - 1.0;
	vec2 nimg = (t.rg * 2.0 - 1.0) * normal_strength + p * 0.45;
	NORMAL = normalize(TANGENT * nimg.x - BINORMAL * nimg.y + NORMAL * 0.75);
	v_thin = 1.0 - clamp(t.b * 1.6, 0.0, 1.0);

	vec3 col = mix(smoke_color, smoke_color_end, pow(life, color_shift));
	col *= 1.0 - self_shadow * clamp(t.b * 1.4, 0.0, 1.0);
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = 1.0;

	float g = 0.0;
	if (glow_height > 0.0) {
		float wy = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		g = exp(-max(mix(v_y, wy, 0.75) - glow_origin_y, 0.0) / glow_height);
	} else {
		g = pow(1.0 - life, glow_decay);
	}
	EMISSION = glow_color * glow * g * (0.2 + t.b * 1.1);

	// Soft Particles + Kamera-Nah-Fade
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float soft = max(soft_dist, v_size * soft_size_factor);
	float fade = clamp((VERTEX.z - view.z) / soft, 0.0, 1.0);
	float dist = -VERTEX.z;
	float near = smoothstep(near_fade * 0.25, near_fade + v_size * 0.35, dist);
	ALPHA = a * fade * fade * (3.0 - 2.0 * fade) * near * v_close;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float hl = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float fwd = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), scatter_power) * scatter * (0.25 + v_thin);
	float ls = LIGHT_IS_DIRECTIONAL ? 1.0 : point_light_scale;
	DIFFUSE_LIGHT += (hl * hl + fwd) * ATTENUATION * LIGHT_COLOR * ls / PI;
}
