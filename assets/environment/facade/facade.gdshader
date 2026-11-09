shader_type spatial;
// Fassadenmaterial (triplanar in Weltkoordinaten, korrekt orientierte Normalen je Projektion):
// PBR-Grundtextur (diffuse/normal/arm), feine Detail-Normal, grossflaechige Farbvariation,
// Schmutz/Feuchte nach unten (Sockelzone), senkrechte Schmutzschlieren, Russflecken und
// optional leichte Naesse. Fuer Gebaeudewaende, Gesimse und Mauern.

uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float base_scale = 0.3;           // Kacheln pro Meter
uniform float rough_mul = 1.0;
uniform float normal_strength = 1.0;
uniform float detail_scale = 1.9;
uniform float detail_strength = 0.35;
uniform float variation = 0.18;           // grossflaechige Helligkeitsflecken
uniform float base_y = 0.0;               // Bodenhoehe fuer den Sockelschmutz
uniform float grime_height = 1.8;
uniform float grime_amount = 0.55;
uniform vec4 grime_color : source_color = vec4(0.2, 0.18, 0.15, 1.0);
uniform float streaks = 0.35;             // senkrechte Schlieren auf Waenden
uniform float soot = 0.0;                 // Anteil verrusster Flaechen (Brand)
uniform float wetness = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack_n(vec3 c) {
	return c * 2.0 - 1.0;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	float sx = n.x >= 0.0 ? 1.0 : -1.0;
	float sz = n.z >= 0.0 ? 1.0 : -1.0;
	vec3 p = wpos * base_scale;
	// Projektionen so, dass das Bild von aussen betrachtet aufrecht und nicht gespiegelt ist
	vec2 uvx = vec2(-sx * p.z, -p.y);
	vec2 uvz = vec2(sz * p.x, -p.y);
	vec2 uvy = p.xz;
	vec3 alb = texture(base_albedo, uvx).rgb * w.x + texture(base_albedo, uvy).rgb * w.y + texture(base_albedo, uvz).rgb * w.z;
	vec3 arm = texture(base_arm, uvx).rgb * w.x + texture(base_arm, uvy).rgb * w.y + texture(base_arm, uvz).rgb * w.z;
	// Normalen je Projektion in Weltkoordinaten (Tangente/Binormale passend zur UV-Richtung)
	vec3 tnx = unpack_n(texture(base_normal, uvx).rgb);
	vec3 tny = unpack_n(texture(base_normal, uvy).rgb);
	vec3 tnz = unpack_n(texture(base_normal, uvz).rgb);
	vec3 dnx = unpack_n(texture(detail_normal, uvx * detail_scale).rgb);
	vec3 dny = unpack_n(texture(detail_normal, uvy * detail_scale).rgb);
	vec3 dnz = unpack_n(texture(detail_normal, uvz * detail_scale).rgb);
	tnx.xy = tnx.xy * normal_strength + dnx.xy * detail_strength;
	tny.xy = tny.xy * normal_strength + dny.xy * detail_strength;
	tnz.xy = tnz.xy * normal_strength + dnz.xy * detail_strength;
	vec3 px = vec3(0.0, tnx.y, -sx * tnx.x);
	vec3 pz = vec3(sz * tnz.x, tnz.y, 0.0);
	vec3 py = vec3(tny.x, 0.0, -tny.y);
	vec3 wn = normalize(n + px * w.x + py * w.y + pz * w.z);

	alb *= tint.rgb;
	float rough = clamp(arm.g * rough_mul, 0.0, 1.0);
	float ao = arm.r;

	// Grossflaechige Variation (Verwitterung, ungleich verblasste Farbe)
	float big = texture(noise_tex, wpos.xz * 0.011 + wpos.y * 0.017).r;
	float mid = texture(noise_tex, vec2(wpos.x + wpos.z, wpos.y) * 0.045).r;
	alb *= 1.0 + (big - 0.5) * variation * 2.0 + (mid - 0.5) * variation;

	float vert = 1.0 - abs(n.y);
	float along = dot(wpos.xz, vec2(abs(n.z), abs(n.x)));
	// Senkrechte Schlieren (Regenwasser, Russ unter Gesimsen)
	if (streaks > 0.0 && vert > 0.5) {
		float s = texture(noise_tex, vec2(along * 0.55, wpos.y * 0.012)).r;
		float s2 = texture(noise_tex, vec2(along * 1.7 + 3.1, wpos.y * 0.03)).r;
		float st = smoothstep(0.55, 0.78, s * 0.65 + s2 * 0.35) * streaks * vert;
		alb = mix(alb, alb * vec3(0.62, 0.6, 0.57), st);
		rough = mix(rough, min(rough + 0.1, 1.0), st);
	}

	// Sockelzone: Spritzwasser, Strassenschmutz, aufsteigende Feuchte
	float gn = texture(noise_tex, vec2(along, wpos.y) * 0.21).r;
	float gh = (wpos.y - base_y) + (gn - 0.5) * 0.9;
	float g = (1.0 - smoothstep(0.0, grime_height, gh)) * grime_amount;
	alb = mix(alb, alb * grime_color.rgb * 2.2, clamp(g, 0.0, 1.0));
	ao *= 1.0 - g * 0.25;
	rough = mix(rough, 0.95, g * 0.4);

	// Russ (Brandspuren), fleckig und nach oben ausfransend
	if (soot > 0.0) {
		float sn = texture(noise_tex, vec2(along, wpos.y * 0.8) * 0.06 + 0.37).r;
		float sn2 = texture(noise_tex, vec2(along, wpos.y) * 0.31).r;
		float sm = smoothstep(1.0 - soot, 1.0 - soot + 0.18, sn * 0.75 + sn2 * 0.25);
		alb = mix(alb, vec3(0.025, 0.022, 0.02), sm * 0.92);
		rough = mix(rough, 1.0, sm);
	}

	// Naesse: dunkler und glatter, Wasser sammelt sich unten
	if (wetness > 0.0) {
		float wt = wetness * mix(0.6, 1.0, big) * mix(1.0, 1.35, g);
		wt = clamp(wt, 0.0, 1.0);
		alb *= mix(1.0, 0.6, wt);
		rough = mix(rough, rough * 0.35 + 0.06, wt);
	}

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	SPECULAR = 0.45;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
