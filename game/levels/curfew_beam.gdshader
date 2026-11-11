shader_type spatial;
// Weicher Lichtkegel (Scheinwerfer/Drohne/Taschenlampe) fuer "curfew": additiv, faellt zum Rand und
// zum Ende hin ab und blendet an Geometrie weich aus (keine harten Schnittkanten am Boden).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float strength = 0.06;
uniform float soft_dist = 1.2;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = pow(facing, 2.2) * strength * (1.0 - UV.y * 0.9);
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = up.z / up.w;
	a *= clamp((VERTEX.z - scene_z) / soft_dist, 0.0, 1.0);
	a *= clamp(-VERTEX.z / 2.0, 0.0, 1.0);
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
