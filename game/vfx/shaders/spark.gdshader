shader_type spatial;
// Funken / glühende Trümmer: unlit, HDR-Farbe aus Partikel-Farbverlauf.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform float intensity = 7.0;

void fragment() {
	ALBEDO = COLOR.rgb * intensity;
	ALPHA = clamp(COLOR.a, 0.0, 1.0);
}
