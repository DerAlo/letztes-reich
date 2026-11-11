shader_type spatial;
// Gluehende Partikel (Funken, Truemmer, Feuerball, Flammen) im Waermebild, additiv.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
varying float seed;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = INSTANCE_CUSTOM.x * 0.53 + MODEL_MATRIX[3].z * 0.013;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float n = texture(noise_tex, UV * 0.7 + vec2(seed * 1.3, seed)).r;
	float a = 1.0 - smoothstep(0.0, 1.0, r + (n - 0.5) * 0.5);
	a *= a;
	ALBEDO = vec3(pow(max(COLOR.r, 0.0), 2.2)) * a * COLOR.a;
}
