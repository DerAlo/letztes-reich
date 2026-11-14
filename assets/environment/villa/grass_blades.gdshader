shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Grashalme/Blumen als MultiMesh (keine Kollision). UV.y = Hoehe am Halm (0 Wurzel, 1 Spitze),
// UV.x > 1.5 = Bluetenkopf (Farbe aus INSTANCE_CUSTOM). Halme schrumpfen mit der Entfernung
// (fade_start..fade_end) und verschwinden in der Rasentextur. Wind als leichte Schwingung.

uniform vec3 root_color : source_color = vec3(0.05, 0.075, 0.03);
uniform vec3 tip_color : source_color = vec3(0.22, 0.3, 0.11);
uniform vec3 tip_dry : source_color = vec3(0.4, 0.38, 0.18);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float dry_amount = 0.3;
uniform float fade_start = 20.0;
uniform float fade_end = 36.0;
uniform float wind = 0.06;
uniform vec2 wind_dir = vec2(0.8, -0.6);

varying float h;
varying vec3 wroot;
varying vec3 wn;
varying vec4 head;

void vertex() {
	h = clamp(UV.y, 0.0, 1.0);
	wroot = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(wroot, (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float s = 1.0 - smoothstep(fade_start, fade_end, d);
	VERTEX.y *= s;
	VERTEX.xz *= mix(0.4, 1.0, s);
	// Wind in Weltrichtung, in Objektraum zurueckgedreht
	float ph = TIME * 1.6 + wroot.x * 0.31 + wroot.z * 0.23;
	float sw = sin(ph) * 0.7 + sin(ph * 2.3 + 1.7) * 0.3;
	vec3 woff = vec3(wind_dir.x, 0.0, wind_dir.y) * sw * wind * h * h * VERTEX.y;
	mat3 m = mat3(MODEL_MATRIX);
	float lx = max(length(m[0]), 1e-4);
	float lz = max(length(m[2]), 1e-4);
	VERTEX.x += dot(woff, m[0] / lx) / lx;
	VERTEX.z += dot(woff, m[2] / lz) / lz;
	// Normale: ueberwiegend nach oben (Halme wie Boden beleuchtet)
	vec3 nw = m * NORMAL;
	nw = dot(nw, nw) > 1e-8 ? normalize(nw) : vec3(0.0, 1.0, 0.0);
	wn = normalize(mix(nw, vec3(0.0, 1.0, 0.0), 0.7));
	head = UV.x > 1.5 ? vec4(INSTANCE_CUSTOM.rgb, 1.0) : vec4(0.0);
}

void fragment() {
	float n1 = texture(noise_tex, wroot.xz * 0.045).r;
	float n2 = texture(noise_tex, wroot.xz * 0.31 + 0.4).r;
	vec3 tip = mix(tip_color, tip_dry, smoothstep(0.45, 0.75, n1) * dry_amount * 2.0);
	vec3 col = mix(root_color, tip, pow(max(h, 0.001), 0.8)) * (0.8 + n2 * 0.4);
	col = mix(col, head.rgb, head.a);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.7, head.a);
	SPECULAR = 0.3;
	BACKLIGHT = mix(vec3(0.12, 0.16, 0.04) * h, head.rgb * 0.4, head.a);
	AO = mix(0.35, 1.0, h);
	AO_LIGHT_AFFECT = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
