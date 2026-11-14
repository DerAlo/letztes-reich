shader_type spatial;
// Nadelbaum (NightProps.spruce_mesh): EIN Material fuer Stamm und Zweigkarten (Atlas, ein Draw-Call).
// Atlas: u 0..0.5 = Zweigspray mit Alpha (Spitze oben), u 0.5..1 = Rinde (kachelnd ueber fract).
// COLOR: r = Position entlang des Astes (0 Stamm .. 1 Spitze, fuer das Wippen), g = Verschattung
// (innen/unten dunkler), b = 1 Rinde / 0 Nadeln.
// Wind: ganzer Baum schwankt (quadratisch mit der Hoehe), Astspitzen wippen; Phase je Instanz.
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D atlas_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 needle_tint : source_color = vec3(1.0);
uniform vec3 bark_tint : source_color = vec3(0.55, 0.5, 0.46);
uniform float alpha_cut = 0.42;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_tint : source_color = vec3(0.8, 0.85, 0.94);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tree_height = 12.0;     // Bezugshoehe (Objektraum) fuer das Schwanken
uniform float sway = 0.12;            // Auslenkung der Spitze in m
uniform float flutter = 0.05;         // Wippen der Astspitzen in m
uniform float wind_speed = 0.8;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float translucency = 0.35;
// Nadeln naeher als x m an der Kamera verschwinden, ab y m voll (gegen "Kamera im Baum").
uniform vec2 near_fade = vec2(0.5, 1.6);
// true: Farb-/Schneerauschen am Baum (Objektraum + Instanz) statt an der Weltposition -
// fuer Baeume, die mit der Landschaft mitbewegt werden (Nachtzug), sonst wandert das Muster.
uniform bool noise_local = false;

varying vec3 wpos;
varying vec3 npos;
varying float v_bark;
varying float v_ao;

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	float iid = float(INSTANCE_ID);
	npos = mat3(MODEL_MATRIX) * VERTEX + vec3(fract(iid * 0.6180339) * 97.0, 0.0, fract(iid * 0.3819660) * 89.0);
	float ph = dot(org.xz, vec2(0.37, 0.21));
	float hy = clamp(VERTEX.y / tree_height, 0.0, 1.2);
	float t = TIME * wind_speed;
	float w = sin(t + ph) * 0.7 + sin(t * 2.13 + ph * 1.7) * 0.3;
	VERTEX.xz += wind_dir * w * sway * hy * hy;
	float br = COLOR.r * (1.0 - COLOR.b);
	VERTEX.y += sin(t * 2.9 + ph + VERTEX.x * 0.9 + VERTEX.z * 0.7) * flutter * br * br;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (!noise_local) {
		npos = wpos;
	}
	v_bark = COLOR.b;
	v_ao = COLOR.g;
}

void fragment() {
	vec2 uv = UV;
	vec4 a;
	vec3 nm;
	if (v_bark > 0.5) {
		// Rinde kachelt: fract im rechten Atlasfeld, Ableitungen vom ungebrochenen UV (keine Naht)
		vec2 tuv = vec2(0.5 + fract(uv.x) * 0.5, fract(uv.y));
		vec2 dx = dFdx(uv) * vec2(0.5, 1.0);
		vec2 dy = dFdy(uv) * vec2(0.5, 1.0);
		a = textureGrad(atlas_albedo, tuv, dx, dy);
		nm = textureGrad(atlas_normal, tuv, dx, dy).rgb;
		a.rgb *= bark_tint;
		a.a = 1.0;
	} else {
		a = texture(atlas_albedo, uv);
		nm = texture(atlas_normal, uv).rgb;
		// Alpha in den kleinen Mipmaps anheben, damit ferne Kronen nicht ausduennen
		vec2 ts = vec2(textureSize(atlas_albedo, 0));
		vec2 d = max(abs(dFdx(uv * ts)), abs(dFdy(uv * ts)));
		float lod = max(log2(max(d.x, d.y)), 0.0);
		a.a *= 1.0 + lod * 0.28;
		a.rgb *= needle_tint;
		// Kamera dicht am Baum: Zweigkarten vor dem Auge ausduennen (Alpha-Scissor -> loechrig statt
		// bildfuellender Nadelflaeche), wie Aeste, die man beim Durchgehen zur Seite drueckt.
		a.a *= smoothstep(near_fade.x, near_fade.y, length(VERTEX));
	}
	float nz = texture(noise_tex, npos.xz * 0.21 + npos.y * 0.05).r;
	vec3 alb = a.rgb * (0.85 + (nz - 0.5) * 0.4);
	alb *= mix(0.45, 1.0, v_ao);
	// Schnee auf den Oberseiten (Weltnormale inkl. Nadel-Relief)
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = wn.y;   // NORMAL ist auf Rueckseiten bereits umgedreht
	float s = clamp((up - (1.0 - snow_amount) + (nz - 0.5) * 1.1) * 4.0, 0.0, 1.0) * snow_amount;
	s *= mix(1.0, 0.25, v_bark);
	s *= smoothstep(0.25, 0.75, v_ao + 0.2);
	ALBEDO = mix(alb, snow_tint * (0.9 + nz * 0.15), s);
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), s * 0.6);
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(mix(0.78, 0.92, v_bark), 0.62, s);
	SPECULAR = 0.35;
	AO = mix(0.6, 1.0, v_ao);
	AO_LIGHT_AFFECT = 0.25;
	BACKLIGHT = (1.0 - v_bark) * (1.0 - s) * translucency * alb;
}
