shader_type spatial;
// Rasen/Wiese der Villa (Boden-Boxen): Poly-Haven-Gras in Weltkoordinaten, zwei Massstaebe gegen
// Kachelmuster, grossflaechige Farbvariation. Im Grundstueck gemaehter Rasen mit Maehstreifen, ausserhalb
// wilde Wiese mit trockenen Flecken. Seitenflaechen der Boxen triplanar.

uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float base_scale = 0.55;
uniform vec4 estate = vec4(-32.0, -44.0, 34.0, 30.0);   // xmin, zmin, xmax, zmax (gemaehter Rasen)
uniform vec3 lawn_tint : source_color = vec3(0.62, 0.72, 0.5);
uniform vec3 meadow_tint : source_color = vec3(0.7, 0.72, 0.48);
uniform vec3 dry_tint : source_color = vec3(0.82, 0.74, 0.5);
uniform float stripe_width = 1.9;
uniform float stripe_amount = 0.09;
uniform float normal_strength = 0.7;

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
	vec2 p = wpos.xz * base_scale;
	// zwei gedrehte Abtastungen, ueber Rauschen gemischt (bricht das Kachelraster)
	float ca = 0.8253;
	float sa = 0.5646;
	vec2 p2 = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) * 0.61 + vec2(0.37, 0.71);
	float bl = smoothstep(0.35, 0.65, texture(noise_tex, wpos.xz * 0.021).r);
	vec3 alb = mix(texture(base_albedo, p).rgb, texture(base_albedo, p2).rgb, bl);
	vec3 arm = mix(texture(base_arm, p).rgb, texture(base_arm, p2).rgb, bl);
	vec3 tn = mix(unpack_n(texture(base_normal, p).rgb), unpack_n(texture(base_normal, p2).rgb), bl);

	// Seiten (Boeschungskanten): einfache Projektion, Normale ohne Map
	float side = 1.0 - smoothstep(0.55, 0.8, abs(n.y));
	if (side > 0.0) {
		vec2 ps = (abs(n.x) > abs(n.z) ? wpos.zy : wpos.xy) * base_scale;
		alb = mix(alb, texture(base_albedo, ps).rgb * vec3(0.7, 0.62, 0.5), side);
	}

	float big = texture(noise_tex, wpos.xz * 0.0065).r;
	float mid = texture(noise_tex, wpos.xz * 0.043 + 0.5).r;
	float sml = texture(noise_tex, wpos.xz * 0.19 + 0.2).r;

	// Maske gemaehter Rasen (weicher Rand)
	float ex = min(wpos.x - estate.x, estate.z - wpos.x);
	float ez = min(wpos.z - estate.y, estate.w - wpos.z);
	float lawn = smoothstep(-1.5, 1.5, min(ex, ez));

	vec3 tint = mix(meadow_tint, lawn_tint, lawn);
	// trockene Flecken (Wiese mehr, Rasen kaum)
	float dry = smoothstep(0.52, 0.75, big * 0.6 + mid * 0.4) * mix(0.75, 0.25, lawn);
	tint = mix(tint, dry_tint, dry);
	alb *= tint;
	alb *= 0.86 + (big - 0.5) * 0.32 + (mid - 0.5) * 0.22 + (sml - 0.5) * 0.12;
	// Maehstreifen (abwechselnd gegen/mit dem Strich, im Licht heller/dunkler)
	float st = sin(wpos.x * 3.14159 / stripe_width);
	float stripe = smoothstep(-0.25, 0.25, st) * 2.0 - 1.0;
	alb *= 1.0 + stripe * stripe_amount * lawn;

	vec3 py = vec3(tn.x, 0.0, -tn.y) * normal_strength;
	vec3 wn = normalize(n + py * (1.0 - side));
	ALBEDO = alb;
	ROUGHNESS = clamp(arm.g * 1.05, 0.6, 1.0);
	AO = mix(1.0, arm.r, 0.7);
	AO_LIGHT_AFFECT = 0.2;
	SPECULAR = 0.22;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
