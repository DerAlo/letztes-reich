shader_type spatial;
// Animiertes Feuer als Partikel-Billboard: Noise-Dissolve, additiv, HDR-Emission fuer Glow.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float intensity = 5.0;
uniform float tex_scale = 0.55;
uniform float rise = 0.6;
uniform float core_heat = 1.35;
uniform float soft_dist = 1.2;
uniform vec3 hot_color : source_color = vec3(1.0, 0.72, 0.32);
uniform vec3 mid_color : source_color = vec3(1.0, 0.3, 0.04);
uniform vec3 cool_color : source_color = vec3(0.5, 0.06, 0.01);

varying float v_life;
varying float v_seed;

void vertex() {
	v_life = INSTANCE_CUSTOM.y;
	v_seed = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]) * sc.x, normalize(INV_VIEW_MATRIX[1]) * sc.y, normalize(INV_VIEW_MATRIX[2]) * sc.z, MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	mw = mw * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float life = clamp(v_life, 0.0, 1.0);
	vec2 nuv = UV * tex_scale + vec2(v_seed * 7.3, v_seed * 3.1) + vec2(0.0, life * rise);
	float n1 = texture(noise_tex, nuv).g;
	float n2 = texture(noise_tex, nuv * 2.1 + vec2(0.37, 0.11)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	float shape = 1.0 - r;
	float heat = shape * core_heat * (1.0 - life * 0.85) + (n - 0.5) * 0.85;
	float alpha = smoothstep(0.02 + life * 0.3, 0.55, heat);
	alpha *= smoothstep(1.0, 0.7, r);
	vec3 col = mix(cool_color, mid_color, smoothstep(0.1, 0.5, heat));
	col = mix(col, hot_color, smoothstep(0.55, 1.0, heat));

	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float fade = clamp((-view.z + VERTEX.z) / soft_dist, 0.0, 1.0);

	ALBEDO = col * intensity * COLOR.rgb;
	ALPHA = clamp(alpha * COLOR.a * fade, 0.0, 1.0);
}
