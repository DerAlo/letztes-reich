shader_type spatial;
// Haut der realistischen Gegner-Soldaten (ersetzt das Bake-Material "Skin" zur Laufzeit):
//   - waermerer Hautton (skin_tint), etwas Subsurface
//   - Kurzhaar-Ansatz auf der Kopfhaut unter den Haar-Karten (Luecken/Fransen der Alpha-Karten zeigen Haar statt Haut)
//   - optional Halstuch/Gaiter (Sturmtruppe): Strickstoff direkt auf der Haut von Hals bis Nasenruecken,
//     Maske in der RUHEPOSE (CUSTOM0, beim Bake geschrieben) -> sitzt bei jeder Pose und Mimik, keine Durchdringung.
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 skin_tint = vec3(1.06, 0.94, 0.85);
uniform float skin_rough = 0.58;
uniform float sss = 0.25;
uniform vec3 head_off = vec3(0.0);           // Kopfknoten Variante - Kopfknoten Variante a
uniform bool buzz_on = true;
uniform vec3 buzz_col : source_color = vec3(0.03, 0.023, 0.017);
uniform bool gaiter_on = false;
uniform vec3 gaiter_col : source_color = vec3(0.1, 0.1, 0.1);

varying vec3 v_rp;

void vertex() {
	v_rp = CUSTOM0.xyz;
	if (dot(v_rp, v_rp) < 0.01) {
		v_rp = VERTEX;
	}
}

float gaiter_mask(vec3 p) {
	// p im Kopfraum der Variante a (Kopfknoten 1.548, Nase vorne bei z ~0.17)
	float ax = abs(p.x);
	float front = smoothstep(-0.01, 0.06, p.z);
	float top_f = 1.584 - 0.042 * smoothstep(0.022, 0.068, ax);
	float top = mix(1.522, top_f, front);
	float m = 1.0 - smoothstep(top - 0.0008, top + 0.0008, p.y);
	m *= step(1.36, p.y) * (1.0 - step(0.12, ax));
	return m;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Haaransatz (Hoehe im Kopfraum Variante a) ueber dem Azimut um die Kopfachse (0 = vorne)
float hairline(float ad) {
	float y = mix(1.632, 1.626, smoothstep(0.0, 30.0, ad));
	y = mix(y, 1.613, smoothstep(30.0, 55.0, ad));
	y = mix(y, 1.624, smoothstep(55.0, 75.0, ad));
	y = mix(y, 1.612, smoothstep(85.0, 110.0, ad));
	y = mix(y, 1.535, smoothstep(110.0, 150.0, ad));
	return mix(y, 1.515, smoothstep(150.0, 180.0, ad));
}

void fragment() {
	vec3 alb = texture(albedo_tex, UV).rgb * skin_tint;
	float rough = skin_rough;
	float sub = sss;
	float h = 0.0;
	if (buzz_on) {
		vec3 p = v_rp - head_off;
		float ad = degrees(abs(atan(p.x, p.z - 0.055)));
		float hl = hairline(ad);
		float jitter = (hash13(floor(p * 1400.0)) - 0.5) * 0.004;
		float dens = smoothstep(hl - 0.002, hl + 0.006, p.y + jitter) * step(1.45, p.y);
		float stub = hash13(floor(p * 2600.0));
		dens *= 0.86 + 0.14 * stub;
		alb = mix(alb, buzz_col * (0.8 + 0.4 * stub), dens);
		rough = mix(rough, 0.78, dens);
		sub = mix(sub, sss * 0.3, dens);
	}
	if (gaiter_on) {
		vec3 p = v_rp - head_off;
		float m = gaiter_mask(p);
		float px = length(fwidth(p));
		{
			float fine = 1.0 - smoothstep(0.0012, 0.004, px);
			// Strick: senkrechte Maschenrippen um den Hals (Umfangsrichtung aus Azimut)
			float u = atan(p.x, p.z - 0.04) * 0.07;
			float rib = abs(sin(u * 6.2832 / 0.0042));
			float st = abs(sin(p.y * 6.2832 / 0.0028 + rib * 1.5));
			h = (rib * 0.00025 + st * 0.0001) * fine;
			// Oberkante: umgeschlagener Rand (heller Wulst, darunter Schattenfuge)
			float ax = abs(p.x);
			float front = smoothstep(-0.01, 0.06, p.z);
			float top = mix(1.522, 1.584 - 0.042 * smoothstep(0.022, 0.068, ax), front);
			float dt = top - p.y;
			float roll = 1.0 - smoothstep(0.0, 0.007, dt);
			float fold = smoothstep(0.006, 0.008, dt) * (1.0 - smoothstep(0.008, 0.011, dt));
			h += roll * 0.0012 - fold * 0.0006;
			vec3 g = gaiter_col * (0.93 + 0.08 * rib * fine) * (1.0 - fold * 0.35) * (1.0 + roll * 0.08);
			alb = mix(alb, g, m);
			rough = mix(rough, 0.96, m);
			sub = mix(sub, 0.0, m);
			h *= m;
		}
	}
	{
		float hh = h * (1.0 - smoothstep(6.0, 18.0, -VERTEX.z));
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 N = normalize(NORMAL);
		vec3 r1 = cross(dpdy, N);
		vec3 r2 = cross(N, dpdx);
		float det = dot(dpdx, r1);
		vec3 gr = sign(det) * (dFdx(hh) * r1 + dFdy(hh) * r2);
		if (abs(det) > 1e-14) {
			NORMAL = normalize(abs(det) * N - gr);
		}
	}
	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	SSS_STRENGTH = sub;
}
