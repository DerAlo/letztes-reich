shader_type spatial;
// Feine Muendungsfunken: duenne, weiche Striche (Partikel mit transform_align Z-Billboard/Y-Geschwindigkeit).
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform float intensity = 6.0;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = UV.y;  // 0 = Kopf (vorn), 1 = Schweif
	float m = across * across * smoothstep(1.0, 0.25, along) * smoothstep(0.0, 0.08, along);
	ALBEDO = COLOR.rgb * intensity * clamp(COLOR.a * m, 0.0, 1.0);
	ALPHA = 0.0;   // rein additiv (siehe muzzle_flash.gdshader)
}
