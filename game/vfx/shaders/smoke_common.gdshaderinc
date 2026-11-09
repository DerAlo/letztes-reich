// Weicher, beleuchteter Rauch / Staub (Runde 2).
// - Flipbook 8x8 (assets/vfx/smoke_flipbook.png): A = Dichte, RG = Normale, B = Dicke.
//   Jedes Partikel startet bei einem zufaelligen Frame und blendet waehrend der Lebenszeit ueber
//   `frame_span` Folge-Frames (benachbarte Frames sind Schnitte durch dasselbe 3D-Noise -> Quellen).
// - Soft Particles (Tiefen-Fade gegen Geometrie, skaliert mit Partikelgroesse) + Kamera-Nah-Fade.
// - Beleuchtung: Half-Lambert + Vorwaertsstreuung (Gegenlicht leuchtet an duennen Raendern),
//   Schatten ueber ATTENUATION. Glut-Toenung von unten (Hoehe ueber Feuer) oder nach Alter (Explosion).
// - Farbe ueber die Lebenszeit von russig-dunkel nach hellgrau.
// Gemeinsamer Code fuer smoke_billboard (mit Schatten) und smoke_billboard_fast (ohne Schatten).

uniform sampler2D flipbook : hint_default_white, filter_linear_mipmap, repeat_disable;
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
uniform float scatter = 2.2;            // Vorwaertsstreuung (Gegenlicht)
uniform float scatter_power = 5.0;
uniform float normal_strength = 1.0;
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
	// stabil ueber die Lebenszeit: anim_offset (zufaellig pro Spawn) + Slot-Index
	v_seed = fract(INSTANCE_CUSTOM.z * 7.31 + float(INSTANCE_ID) * 0.618034);
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
	float fr = v_seed * (63.0 - frame_span) + life * frame_span;
	float f0 = floor(fr);
	vec4 t = mix(frame_sample(f0, UV), frame_sample(f0 + 1.0, UV), smoothstep(0.0, 1.0, fr - f0));

	float e = erosion * life;
	float a = clamp((t.a - e) / max(1.0 - e, 0.05), 0.0, 1.0);
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
		g = exp(-max(v_y - glow_origin_y, 0.0) / glow_height);
	} else {
		g = pow(1.0 - life, glow_decay);
	}
	EMISSION = glow_color * glow * g * (0.3 + t.b * 1.2);

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
	DIFFUSE_LIGHT += (hl * hl + fwd) * ATTENUATION * LIGHT_COLOR / PI;
}
