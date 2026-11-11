shader_type spatial;
// Panzerglas-Visier (gepanzerte Gegner / Juggernaut): dunkel getoent, stark spiegelnd.
// crack (0..1) zeichnet radiale Bruchlinien + Splitterringe um crack_pos (Objektraum) - waechst mit Treffern.
render_mode cull_back, depth_draw_opaque;

uniform vec3 tint : source_color = vec3(0.035, 0.045, 0.05);
uniform vec3 rim_tint : source_color = vec3(0.25, 0.32, 0.3);
uniform float crack = 0.0;
uniform vec3 crack_pos = vec3(0.0);
uniform vec3 crack_pos2 = vec3(0.0);
uniform float crack2 = 0.0;
uniform float crack_scale = 1.0;   // Visiergroesse (Juggernaut > 1)

varying vec3 v_p;

void vertex() {
	v_p = VERTEX;
}

float hash1(float n) {
	return fract(sin(n) * 43758.5453);
}

float cracks(vec3 p, vec3 c, float amount) {
	if (amount <= 0.0) {
		return 0.0;
	}
	vec3 d = (p - c) / crack_scale;
	float r = length(d.xy) + 1e-4;
	float a = atan(d.y, d.x);
	float lines = 0.0;
	// radiale Strahlen mit Knick
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float ang = fi * 0.698 + hash1(fi * 7.3) * 0.5;
		float wob = sin(r * 70.0 + fi * 2.0) * 0.06 + (hash1(fi + 2.0) - 0.5) * r * 2.0;
		float da = abs(mod(a - ang - wob + 3.14159, 6.28318) - 3.14159);
		float len = 0.04 + 0.11 * hash1(fi * 3.7) ;
		len *= amount * 1.6;
		float w = 0.0022 / r;
		lines = max(lines, (1.0 - smoothstep(w * 0.5, w, da)) * (1.0 - smoothstep(len * 0.8, len, r)));
	}
	// Splitterringe
	float ring = 0.0;
	for (int k = 1; k < 4; k++) {
		float rk = float(k) * 0.017 * (0.8 + amount);
		ring = max(ring, (1.0 - smoothstep(0.0, 0.0018, abs(r - rk * (1.0 + 0.15 * sin(a * 5.0 + float(k)))))) * step(float(k) * 0.3, amount + 0.1));
	}
	float star = 1.0 - smoothstep(0.004, 0.014 * (0.6 + amount), r);
	return clamp(max(max(lines, ring * 0.8), star), 0.0, 1.0);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 alb = tint + rim_tint * fres * 0.4;
	float c = max(cracks(v_p, crack_pos, crack), cracks(v_p, crack_pos2, crack2));
	alb = mix(alb, vec3(0.75, 0.8, 0.78), c * 0.85);
	ALBEDO = alb;
	METALLIC = 0.2;
	ROUGHNESS = mix(0.06, 0.5, c);
	SPECULAR = 0.9;
	CLEARCOAT = 1.0 - c;
	CLEARCOAT_ROUGHNESS = 0.05;
}
