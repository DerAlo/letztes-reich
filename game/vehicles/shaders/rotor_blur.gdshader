shader_type spatial;
// Bewegungsunschaerfe-Scheibe fuer Rotoren: halbtransparente Scheibe mit Nachzieh-Schlieren hinter jedem Blatt.
// spin = aktueller Rotorwinkel (Skript), blades = Blattzahl. Auf PlaneMesh (XZ) oder QuadMesh legen.
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform vec3 color : source_color = vec3(0.045, 0.048, 0.044);
uniform float blades = 5.0;
uniform float spin = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.34;
uniform float inner = 0.07;
uniform float streak_sharpness = 5.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float sector = fract((a - spin) / (6.2831853 / blades));
	// direkt hinter dem Blatt dunkel, dann auslaufend
	float trail = pow(1.0 - sector, streak_sharpness) * 0.75 + 0.25;
	float radial = smoothstep(inner, inner + 0.1, r) * (1.0 - smoothstep(0.965, 1.0, r));
	float tip = smoothstep(0.9, 0.95, r) * (1.0 - smoothstep(0.95, 0.99, r));
	ALBEDO = color + vec3(0.12, 0.11, 0.09) * tip;
	ROUGHNESS = 0.55;
	METALLIC = 0.2;
	ALPHA = opacity * radial * trail * (0.55 + 0.45 * r) + tip * 0.08 * radial;
}
