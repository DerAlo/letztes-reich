shader_type canvas_item;
// Pausenmenue-Hintergrund: weicher Unschaerfe-Blick auf die Szene, abgedunkelt, leicht oliv getoent,
// feine Funk-Scanlines und Vignette. amount 0..1 wird beim Oeffnen eingeblendet.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float blur_lod : hint_range(0.0, 6.0) = 2.6;
uniform float darken : hint_range(0.0, 1.0) = 0.62;
uniform vec3 tint = vec3(0.55, 0.62, 0.52);

void fragment() {
	vec2 uv = SCREEN_UV;
	float lod = blur_lod * amount;
	vec2 px = SCREEN_PIXEL_SIZE * (1.0 + 3.0 * amount);
	vec3 c = textureLod(screen_tex, uv, lod).rgb * 0.4;
	c += textureLod(screen_tex, uv + vec2(px.x, px.y) * 2.0, lod).rgb * 0.15;
	c += textureLod(screen_tex, uv + vec2(-px.x, px.y) * 2.0, lod).rgb * 0.15;
	c += textureLod(screen_tex, uv + vec2(px.x, -px.y) * 2.0, lod).rgb * 0.15;
	c += textureLod(screen_tex, uv + vec2(-px.x, -px.y) * 2.0, lod).rgb * 0.15;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 graded = mix(c, vec3(lum) * tint * 1.25, 0.55 * amount);
	graded *= 1.0 - darken * amount;
	// Scanlines (Bildschirmpixel) + Vignette
	float scan = 0.94 + 0.06 * sin(FRAGCOORD.y * 1.6);
	vec2 d = uv - 0.5;
	float vig = smoothstep(0.85, 0.25, length(d * vec2(1.1, 1.0)));
	graded *= mix(1.0, scan * mix(0.55, 1.0, vig), amount);
	COLOR = vec4(graded, 1.0);
}
