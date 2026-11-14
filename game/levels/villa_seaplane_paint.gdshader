shader_type spatial;
// Wasserflugzeug (villa_seaplane.gd): Lack, Alu, Gummi in EINEM Material. Keine UVs: alles im Objektraum.
// Vertex-Farbe rgb = Grundfarbe, a = Bauteil-Kennung:
//   1.0 Rumpf, 0.95 Kabinentuer, 0.85 Flaeche, 0.78 Leitwerk, 0.70 Schwimmer (Alu), 0.62 Lack schlicht,
//   0.50 blankes Metall, 0.30 Gummi/Kunststoff dunkel, 0.15 dunkles Metall (Auspuff, Motor).
// Zierstreifen, Kennzeichnungsfarben, Blechstoesse/Nieten (Bump ueber Ableitungen), Schmutz, Auspuffruss,
// Algenrand und Oelschlieren auf den Schwimmern werden prozedural erzeugt.
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://game/levels/villa_seaplane_mask.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 trim : source_color = vec3(0.42, 0.045, 0.04);
uniform vec3 interior : source_color = vec3(0.045, 0.042, 0.04);
uniform float dirt = 1.0;
uniform float seam_depth = 0.00045;
instance uniform vec3 part_offset = vec3(0.0);

varying vec3 v_p;
varying vec3 v_n;

void vertex() {
	v_p = VERTEX + part_offset;
	v_n = NORMAL;
}

float aline(float d, float w) {
	float f = max(fwidth(d), 1e-5);
	return (1.0 - smoothstep(w - f * 0.5, w + f * 0.5, abs(d))) * clamp(w * 2.5 / f, 0.0, 1.0);
}

float rivet(vec2 q, float r) {
	float f = max(fwidth(q.x) + fwidth(q.y), 1e-5);
	return (1.0 - smoothstep(r - f * 0.5, r + f * 0.5, length(q))) * clamp(r * 3.0 / f, 0.0, 1.0);
}

vec4 tri_s(vec3 p, vec3 w) {
	return texture(noise_tex, p.zy) * w.x + texture(noise_tex, p.xz) * w.y + texture(noise_tex, p.xy) * w.z;
}

vec3 bump(vec3 N, vec3 pos, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, N);
	vec3 r2 = cross(N, dpdx);
	float det = dot(dpdx, r1);
	vec3 g = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * N - g);
}

void fragment() {
	vec3 p = v_p;
	vec3 n = normalize(v_n);
	float flag = COLOR.a;
	bool fus = flag > 0.92;
	bool door = fus && flag < 0.975;
	bool wing = flag > 0.815 && flag <= 0.92;
	bool tail = flag > 0.74 && flag <= 0.815;
	bool flt = flag > 0.66 && flag <= 0.74;
	bool plain = flag > 0.56 && flag <= 0.66;
	bool metal = flag > 0.40 && flag <= 0.56;
	bool rubber = flag > 0.22 && flag <= 0.40;

	if (fus) {
		if (sp_window_sd(p) < 0.0) {
			discard;
		}
		float dd = sp_door_sd(p);
		if (p.x < -0.3) {
			if (!door && dd < 0.0) {
				discard;
			}
			if (door && dd > 0.0) {
				discard;
			}
		}
	}
	if (!FRONT_FACING) {
		// Kabineninnenraum / Innenseite der Verkleidung
		ALBEDO = interior;
		ROUGHNESS = 0.92;
		METALLIC = 0.0;
		SPECULAR = 0.2;
		NORMAL = -NORMAL;
	} else {
		vec3 alb = COLOR.rgb;
		vec3 w3 = pow(abs(n), vec3(4.0));
		w3 /= (w3.x + w3.y + w3.z);
		float n1 = tri_s(p * 0.33, w3).r;
		float n2 = tri_s(p * 1.9 + vec3(0.31, 0.17, 0.53), w3).g;
		float n3 = tri_s(p * 7.0 + vec3(0.11, 0.71, 0.29), w3).b;
		float streak = texture(noise_tex, vec2(p.z * 0.11 + p.x * 0.07, p.y * 2.6 + p.x * 0.9)).b;
		float L = 0.0;      // Blechstoss
		float R = 0.0;      // Niete
		float soot = 0.0;
		float grime = 0.0;
		float metal_v = 0.0;
		float rough = 0.34;
		float coat = 0.0;
		float side = smoothstep(0.2, 0.45, abs(n.x));

		if (fus) {
			// Zierstreifen (Cheatline) mit Begleitlinie, steigt zum Heck an
			float yc = 1.88 + max(p.z - 0.6, 0.0) * 0.12;
			float hw = 0.062 * (1.0 - 0.45 * smoothstep(1.0, 5.6, p.z));
			float band = 1.0 - smoothstep(hw - 0.003, hw + 0.003, abs(p.y - yc));
			float pin = 1.0 - smoothstep(0.009, 0.014, abs(p.y - (yc - hw - 0.04)));
			alb = mix(alb, trim, max(band, pin) * side * (1.0 - step(5.75, p.z)));
			// Fenstergummi
			float wd = sp_window_sd(p);
			alb = mix(alb, vec3(0.025), 1.0 - smoothstep(0.013, 0.019, wd));
			// Spanten, Tuerfugen, Laengsstoss
			float fz = p.z > 1.25 ? (mod(p.z - 1.58 + 0.33, 0.66) - 0.33) : min(abs(p.z + 2.18), min(abs(p.z + 1.62), abs(p.z - 0.92)));
			L = max(L, aline(fz, 0.0012));
			if (abs(p.x) > 0.25) {
				L = max(L, aline(sp_door_sd(p), 0.0016));
				L = max(L, aline(sp_pilot_door_sd(p), 0.0016));
			}
			if (p.z > 0.9) {
				L = max(L, aline(p.y - 1.66 - (p.z - 0.9) * 0.08, 0.0011));
			}
			float ry = mod(p.y, 0.045) - 0.0225;
			R = max(R, rivet(vec2(fz - 0.012, ry), 0.0024));
			// Auspuffruss rechts, Oelschliere am Bauch
			float dz = p.z + 2.06;
			if (dz > 0.0 && p.x > 0.0) {
				float ye = 1.52 + 0.05 * dz;
				float we = 0.07 + 0.07 * dz;
				soot = exp(-dz / 1.7) * (1.0 - smoothstep(we * 0.4, we, abs(p.y - ye))) * smoothstep(0.1, 0.35, p.x);
				soot *= 0.55 + 0.7 * streak;
			}
			if (p.y < 1.55 && n.y < -0.2) {
				grime = max(grime, smoothstep(0.45, 0.8, streak) * 0.6 * (1.0 - smoothstep(-2.2, 2.0, p.z) * 0.6));
			}
			coat = 0.4;
		} else if (wing) {
			// Rote Flaechenenden, Ruderfugen, Rippen-Nietreihen
			alb = mix(alb, trim, step(6.55, abs(p.x)));
			float ax = abs(p.x);
			if (ax > 0.72 && ax < 7.08) {
				L = max(L, aline(p.z + 0.55, 0.0035));
				L = max(L, aline(ax - 4.05, 0.003));
			}
			L = max(L, aline(ax - 0.72, 0.0012));
			L = max(L, aline(ax - 7.08, 0.0012));
			L = max(L, aline(p.z + 1.44, 0.0010));
			float rx = mod(ax + 0.165, 0.33) - 0.165;
			R = max(R, rivet(vec2(rx, mod(p.z, 0.06) - 0.03), 0.0022));
			// Vorderkante: Insekten/Abrieb
			grime = max(grime, (1.0 - smoothstep(-1.72, -1.62, p.z)) * 0.5 * n2);
			coat = 0.35;
		} else if (tail) {
			// Seitenruder: rote Spitze, rot-weiss-rote Flagge; Hoehenruder-Enden rot
			if (abs(p.x) < 0.2) {
				alb = mix(alb, trim, step(3.8, p.y));
				if (p.z > 4.95 && p.z < 5.42 && p.y > 3.12 && p.y < 3.58) {
					float fy = (p.y - 3.12) / 0.46;
					alb = (fy > 0.333 && fy < 0.667) ? vec3(0.86, 0.85, 0.82) : vec3(0.62, 0.04, 0.05);
				}
				L = max(L, aline(p.z - 5.48, 0.003) * step(2.72, p.y));
			}
			if (abs(p.x) > 0.2) {
				alb = mix(alb, trim, step(2.25, abs(p.x)));
				L = max(L, aline(p.z - 5.36, 0.003));
			}
			coat = 0.35;
		} else if (flt) {
			// Alu-Schwimmer: Schotte mit Nietreihen, Algenrand an der Wasserlinie, Oelschlieren
			float sz = mod(p.z + 0.475, 0.95) - 0.475;
			L = max(L, aline(sz, 0.0012));
			R = max(R, rivet(vec2(sz - 0.014, mod(p.y, 0.04) - 0.02), 0.0024));
			R = max(R, rivet(vec2(mod(p.z, 0.05) - 0.025, p.y - 0.44), 0.0024));
			alb *= 0.9 + 0.2 * n1;
			float wl = 1.0 - smoothstep(0.06, 0.16, p.y);
			alb = mix(alb, vec3(0.13, 0.14, 0.08), wl * (0.55 + 0.35 * n2));
			float oil = smoothstep(0.58, 0.82, texture(noise_tex, vec2(p.z * 0.06, p.y * 4.5 + p.x)).r) * side;
			alb = mix(alb, vec3(0.08, 0.075, 0.06), oil * 0.55);
			// Trittspuren auf dem Deck des linken Schwimmers an der Tuer
			float tread = (1.0 - smoothstep(0.3, 0.5, n.y * 0.0 + abs(p.z - 0.2) / 2.5)) * step(0.7, n.y) * step(p.x, 0.0);
			metal_v = 0.75;
			rough = 0.38 + 0.25 * n2 + wl * 0.3 + oil * 0.15 + tread * 0.2;
		} else if (plain) {
			coat = 0.25;
		} else if (metal) {
			metal_v = 0.9;
			rough = 0.24 + 0.12 * n2;
		} else if (rubber) {
			rough = 0.72;
		} else {
			metal_v = 0.55;
			rough = 0.55 + 0.2 * n2;
			soot = 0.4 * n2;
		}

		// allgemeiner Schmutz (Fleckig grob/fein)
		float g = smoothstep(0.42, 0.92, n1 * 0.6 + n2 * 0.4) * 0.35 + grime;
		g *= dirt;
		alb = mix(alb, alb * vec3(0.66, 0.62, 0.55), clamp(g, 0.0, 1.0));
		alb = mix(alb, vec3(0.045, 0.04, 0.035), clamp(soot, 0.0, 0.92));
		alb *= 1.0 - 0.38 * L;
		alb *= 0.97 + 0.06 * n3;
		ALBEDO = alb;
		METALLIC = metal_v;
		ROUGHNESS = clamp(rough + g * 0.3 + soot * 0.35 + L * 0.2 + n3 * 0.05, 0.05, 1.0);
		CLEARCOAT = coat * (1.0 - clamp(g + soot, 0.0, 1.0));
		CLEARCOAT_ROUGHNESS = 0.2;
		float h = -L * seam_depth + R * 0.00025;
		NORMAL = bump(NORMAL, VERTEX, h);
	}
}
