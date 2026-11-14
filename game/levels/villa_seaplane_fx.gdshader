shader_type spatial;
// Wasserflugzeug-Effekte ohne UVs (lokale Vertexposition):
//   mode 0: Propellerkreis (Bewegungsunschaerfe, Scheibe in der lokalen XY-Ebene, Radius `radius`)
//   mode 1: Kielwasser/Bugwellen/Propellerwasser auf dem See (flaches Netz, x quer, z nach hinten)
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform int mode = 0;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float strength = 0.0;     // Scheibe: Sichtbarkeit; Kielwasser: Fahrt 0..1
uniform float wash = 0.0;         // Propellerwasser 0..1
uniform float contact = 0.0;      // Schaumrand an den Schwimmern 0..1
uniform float travel = 0.0;       // zurueckgelegter Weg (m), Schaum bleibt ortsfest auf dem Wasser
uniform float spin = 0.0;         // scheinbare Drehung der Blattschatten (rad)
uniform float radius = 1.3;
uniform float float_x = 1.25;     // halber Schwimmerabstand
uniform float bow_z = -4.6;
uniform float stern_z = 3.0;

varying vec3 v_p;

void vertex() {
	v_p = VERTEX;
}

void fragment() {
	if (mode == 0) {
		float r = length(v_p.xy) / radius;
		if (r > 1.0) {
			discard;
		}
		float a = atan(v_p.y, v_p.x);
		float blades = pow(abs(cos(a - spin)), 5.0);
		float tip = smoothstep(0.9, 0.925, r) * (1.0 - smoothstep(0.985, 1.0, r));
		float hub = smoothstep(0.1, 0.17, r);
		ALBEDO = mix(vec3(0.025), vec3(0.8, 0.62, 0.06), tip);
		ROUGHNESS = 0.6;
		SPECULAR = 0.3;
		ALPHA = strength * hub * (0.1 + 0.1 * blades * (1.0 - r * 0.5) + tip * 0.05) * (1.0 - smoothstep(0.97, 1.0, r));
	} else {
		vec2 q = v_p.xz;
		float ax = abs(q.x);
		float zb = q.y - bow_z;
		float n1 = texture(noise_tex, vec2(q.x * 0.09, (q.y - travel) * 0.09)).r;
		float n2 = texture(noise_tex, vec2(q.x * 0.33 + 0.3, (q.y - travel) * 0.29)).g;
		float n3 = texture(noise_tex, vec2(q.x * 0.9 + 0.7, (q.y - travel) * 0.8)).b;
		float foam = smoothstep(0.32, 0.78, n1 * 0.5 + n2 * 0.35 + n3 * 0.25);
		// Bugwellen-Arme (Kelvin-Winkel ~20 Grad) aussen an den Schwimmern
		float arm_x = float_x + 0.36 + zb * 0.36;
		float arm_w = 0.1 + zb * 0.045;
		float arm = (1.0 - smoothstep(0.0, arm_w, abs(ax - arm_x))) * smoothstep(0.0, 0.8, zb) * exp(-max(zb, 0.0) / 13.0);
		// Gischt entlang der Schwimmerflanken
		float side = (1.0 - smoothstep(0.0, 0.3, abs(ax - float_x - 0.38))) * smoothstep(bow_z + 0.4, bow_z + 1.2, q.y) * (1.0 - smoothstep(stern_z - 0.5, stern_z + 0.5, q.y));
		// Hecksee hinter den Schwimmern
		float zs = q.y - stern_z;
		float tw = 0.32 + max(zs, 0.0) * 0.1;
		float trail = (1.0 - smoothstep(tw * 0.3, tw, abs(ax - float_x))) * smoothstep(-0.6, 0.4, zs) * exp(-max(zs, 0.0) / 11.0);
		// Schaumrand an der Wasserlinie der Schwimmer (auch im Stand, leicht)
		float fz = clamp(q.y, bow_z + 0.75, stern_z);
		float dfl = length(vec2(ax - float_x, q.y - fz));
		float ring = (1.0 - smoothstep(0.3, 0.52, dfl)) * smoothstep(0.24, 0.32, dfl);
		// Propellerwasser: aufgeraute Streifen hinter dem Propeller
		float pz = q.y + 3.0;
		float wm = (1.0 - smoothstep(0.5 + pz * 0.1, 1.3 + pz * 0.22, ax)) * smoothstep(-0.8, 0.8, pz) * exp(-max(pz, 0.0) / 6.0);
		float wn = texture(noise_tex, vec2(q.x * 0.35 + 0.1, (q.y - TIME * 8.0) * 0.06)).b;
		float wn2 = texture(noise_tex, vec2(q.x * 0.8 + 0.5, (q.y - TIME * 11.0) * 0.2)).r;
		float ws = wm * wash * smoothstep(0.35, 0.8, wn * 0.6 + wn2 * 0.5);
		float f = (arm * 0.9 + trail + side * 0.7) * strength * (0.25 + 0.95 * foam) + ring * contact * (0.25 + 0.75 * foam);
		ALBEDO = vec3(0.8, 0.82, 0.84);
		ROUGHNESS = 0.6;
		SPECULAR = 0.3;
		ALPHA = clamp(f * 0.85 + ws * 0.4, 0.0, 0.92);
	}
}
