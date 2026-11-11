shader_type spatial;
// Leuchtpunkte/Leuchtspuren im Waermebild (ImmediateMesh, additiv).
// COLOR.r = Helligkeit (Temperatur), COLOR.a = Deckkraft. UV: x laengs, y quer; UV2.x: 0 = rund, 1 = Strich.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float a;
	if (UV2.x > 0.5) {
		a = (1.0 - smoothstep(0.0, 1.0, abs(c.y))) * (1.0 - smoothstep(0.7, 1.0, abs(c.x)));
	} else {
		float r = length(c);
		a = 1.0 - smoothstep(0.0, 1.0, r);
		a = a * a * (0.6 + 0.4 * (1.0 - smoothstep(0.0, 0.3, r)));
	}
	ALBEDO = vec3(pow(max(COLOR.r, 0.0), 2.2)) * a * COLOR.a;
}
