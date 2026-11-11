shader_type spatial;
// Staub/Rauch-Partikel im Waermebild (Mischung). COLOR.r = Temperatur, COLOR.a = Deckkraft.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float haze_k = 0.00022;
uniform float haze_heat = 0.24;
varying float seed;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = INSTANCE_CUSTOM.x * 0.37 + MODEL_MATRIX[3].x * 0.011;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float n = texture(noise_tex, UV * 0.55 + vec2(seed, seed * 1.7)).r;
	float a = 1.0 - smoothstep(0.2, 1.0, r + (n - 0.5) * 0.7);
	float heat = COLOR.r * (0.85 + n * 0.3);
	float d = length(VERTEX);
	heat = mix(heat, haze_heat, 1.0 - exp(-d * haze_k));
	ALBEDO = vec3(pow(max(heat, 0.0), 2.2));
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
