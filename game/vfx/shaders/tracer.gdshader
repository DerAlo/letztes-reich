// Leuchtspur (Gegner/Juggernaut): achsenparalleles Billboard mit weichem, glühendem Kern,
// heller Spitze und auslaufendem Schweif. Mesh = QuadMesh 1x1 (x = quer, y = laengs, +y = Flugrichtung).
// Breite in Metern, aber nie duenner als min_px Bildschirmpixel (sonst flimmert es auf Distanz).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform float length_m = 1.6;
uniform float width_m = 0.016;
uniform float min_px = 3.5;
uniform vec4 core_color : source_color = vec4(1.0, 0.78, 0.48, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform float energy = 4.0;

varying vec2 q;

void vertex() {
	q = VERTEX.xy;   // x,y in [-0.5, 0.5]
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 axis = normalize((MODEL_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - center;
	float dist = max(length(to_cam), 0.01);
	vec3 side = cross(axis, to_cam / dist);
	float sl = length(side);
	side = sl > 1e-4 ? side / sl : INV_VIEW_MATRIX[0].xyz;
	// Weltgroesse eines Pixels in dieser Entfernung (PROJECTION_MATRIX[1][1] = 1/tan(fov/2))
	float px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(width_m, px * min_px) * 3.0;   // Quad breiter als Kern -> Platz fuer Glow
	vec3 wp = center + axis * (q.y * length_m) + side * (q.x * w);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_cam, 0.0)).xyz);
}

void fragment() {
	float t = q.y + 0.5;                    // 0 = Schweifende, 1 = Spitze
	float across = q.x * 2.0;               // -1..1
	float core = exp(-across * across * 14.0);
	float glow = exp(-across * across * 3.0);
	float along = smoothstep(0.0, 0.85, t) * (1.0 - smoothstep(0.96, 1.0, t));
	along *= along;
	vec3 col = core_color.rgb * core * 1.2 + glow_color.rgb * glow * 0.9;
	ALBEDO = col * along * energy;
	ALPHA = clamp((core + glow * 0.7) * along, 0.0, 1.0);
}
