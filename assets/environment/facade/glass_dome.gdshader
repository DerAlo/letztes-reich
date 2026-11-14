shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
// Glaskuppel (Reichstag, spreebogen): Stahlrippen (Meridiane + Ringe) als prozedurales Raster in Objektkoordinaten,
// dazwischen leicht getoentes, spiegelndes Glas (Fresnel). Fuer eine Halbkugel (SphereMesh, is_hemisphere).

uniform vec4 glass_col : source_color = vec4(0.5, 0.58, 0.64, 1.0);
uniform vec4 steel_col : source_color = vec4(0.58, 0.6, 0.62, 1.0);
uniform float glass_alpha = 0.32;
uniform float ribs = 24.0;
uniform float rings = 17.0;
uniform float radius = 1.0;
uniform float height = 1.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float grid_line(float x, float w, float fw) {
	float d = abs(fract(x) - 0.5);
	return smoothstep(0.5 - w - fw, 0.5 - w + fw, d);
}

void fragment() {
	float ang = atan(lp.z, lp.x) / 6.2831853 + 0.5;
	float h = clamp(lp.y / height, 0.0, 1.0);
	vec2 g = vec2(ang * ribs, h * rings);
	vec2 fw = fwidth(g);
	float l = max(grid_line(g.x, 0.07, fw.x), grid_line(g.y, 0.09, fw.y));
	// Oberer Ring (Oeffnung) und Fussring massiv
	l = max(l, step(0.94, h));
	l = max(l, 1.0 - step(0.035, h));
	l = clamp(l + smoothstep(0.25, 0.6, max(fw.x, fw.y)) * 0.35, 0.0, 1.0);   // Ferne: Raster mitteln
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(glass_col.rgb * 0.45, steel_col.rgb, l);
	METALLIC = mix(0.0, 0.75, l);
	ROUGHNESS = mix(0.04, 0.38, l);
	SPECULAR = 0.8;
	ALPHA = mix(clamp(glass_alpha + fres * 0.55, 0.0, 1.0), 1.0, l);
}
