shader_type spatial;
// Bodennahe Waermeflecken (additiv, flaches Quad): Einschlagkrater/Brandstellen (ring = 0)
// und die Druckwelle der 105 mm als heller Ring (ring = relative Ringbreite).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
instance uniform float intensity = 0.0;
instance uniform float ring = 0.0;
instance uniform float seed = 0.0;

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float n = texture(noise_tex, UV * 0.8 + vec2(seed, seed * 0.7)).r;
	float n2 = texture(noise_tex, UV * 2.9 + vec2(seed * 1.3, seed)).r;
	float a;
	if (ring > 0.0) {
		a = smoothstep(1.0 - ring, 1.0 - ring * 0.35, r) * (1.0 - smoothstep(0.96, 1.0, r));
		a *= 0.6 + n * 0.8;
	} else {
		float rr = r + (n - 0.5) * 0.55;
		a = 1.0 - smoothstep(0.05, 1.0, rr);
		a = a * (0.5 + n2 * 0.7);
		a += (1.0 - smoothstep(0.0, 0.3, rr)) * 0.45;
	}
	ALBEDO = vec3(pow(max(intensity * a, 0.0), 2.2));
}
