shader_type spatial;
// Gelaende im Waermebild: Feld-Flickenteppich (Brandenburg), gemaehtes Gras im Fliegerhorst,
// Furchen, Feuchte-Flecken. Nachts kuehl; Wald und Beton sind waermer (eigene Meshes).
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float haze_k = 0.00022;
uniform float haze_heat = 0.24;
uniform vec4 base_rect = vec4(-720.0, -450.0, 720.0, 210.0);   // Fliegerhorst (x0, z0, x1, z1)

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	// grosse Felder, leicht gedreht
	float a = 0.21;
	vec2 q = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	vec2 cell_size = vec2(190.0, 130.0);
	vec2 cid = floor(q / cell_size);
	vec2 cuv = fract(q / cell_size);
	float h1 = hash(cid);
	float heat = 0.13 + h1 * 0.1;
	// Furchen je Feld in eigener Richtung
	float fdir = step(0.5, hash(cid + 7.0));
	float fcoord = mix(cuv.y * cell_size.y, cuv.x * cell_size.x, fdir);
	heat += sin(fcoord * 2.1) * 0.014 * step(0.35, h1);
	// Feldraender (Hecken/Feldwege etwas waermer)
	vec2 edge = min(cuv, 1.0 - cuv) * cell_size;
	float e = 1.0 - smoothstep(0.0, 3.5, min(edge.x, edge.y));
	heat += e * 0.07;
	// Fliegerhorst: gemaehtes, einheitliches Gras
	float inside = step(base_rect.x, p.x) * step(p.x, base_rect.z) * step(base_rect.y, p.y) * step(p.y, base_rect.w);
	heat = mix(heat, 0.165, inside * 0.85);
	// Rauschen in drei Groessen (Feuchte, Bewuchs, Grasbueschel)
	float n1 = texture(noise_tex, p * 0.0031).r;
	float n2 = texture(noise_tex, p * 0.041).r;
	float n3 = texture(noise_tex, p * 0.37).r;
	heat += (n1 - 0.5) * 0.09 + (n2 - 0.5) * 0.04 + (n3 - 0.5) * 0.025;
	float d = length(VERTEX);
	heat = mix(heat, haze_heat, 1.0 - exp(-d * haze_k));
	ALBEDO = vec3(pow(max(heat, 0.0), 2.2));
}
