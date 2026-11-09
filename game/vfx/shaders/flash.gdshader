shader_type spatial;
// Mündungs-/Explosionsblitz: sehr heller Kern, Halo und Strahlen, additiv.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec3 flash_color : source_color = vec3(1.0, 0.78, 0.45);
uniform float intensity = 14.0;
uniform float fade = 1.0;
uniform float seed = 0.0;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]) * sc.x, normalize(INV_VIEW_MATRIX[1]) * sc.y, normalize(INV_VIEW_MATRIX[2]) * sc.z, MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float core = exp(-r * r * 14.0);
	float halo = exp(-r * 3.5) * 0.45;
	float spikes = pow(abs(cos(ang * 3.0 + seed)), 24.0) * exp(-r * 3.2) * 0.9;
	spikes += pow(abs(cos(ang * 5.0 + seed * 2.0)), 40.0) * exp(-r * 4.0) * 0.5;
	float v = (core * 2.0 + halo + spikes) * smoothstep(1.0, 0.7, r);
	ALBEDO = mix(flash_color, vec3(1.0), core) * v * intensity * fade;
	ALPHA = 1.0;
}
