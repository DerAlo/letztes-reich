shader_type spatial;
// Schockwelle: Refraktion des Bildschirminhalts am Rand einer expandierenden Kugel.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float progress = 0.0;
uniform float strength = 0.09;
uniform float sheen = 0.06;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float rim = 1.0 - abs(dot(n, v));
	float ring = smoothstep(0.78, 0.96, rim) * (1.0 - smoothstep(0.985, 1.0, rim));
	float life = (1.0 - progress);
	life *= life;
	vec2 off = n.xy * ring * strength * life;
	off.y = -off.y;
	vec3 col = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALBEDO = col + vec3(1.0, 0.85, 0.65) * ring * sheen * life;
	ALPHA = smoothstep(0.0, 0.04, ring * life);
}
