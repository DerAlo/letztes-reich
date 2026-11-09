shader_type spatial;
render_mode unshaded, cull_disabled;
// Meeresflaeche der Lagekarte: dunkles Blau, Koordinatengitter, wandernde Abtastlinie.

uniform vec3 base_color : source_color = vec3(0.01, 0.025, 0.05);
uniform vec3 grid_color : source_color = vec3(0.1, 0.45, 0.6);
uniform float grid_step = 6.5;
uniform float fade_in : hint_range(0.0, 1.0) = 1.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(wpos.xz / grid_step - 0.5) - 0.5) / fwidth(wpos.xz / grid_step);
	float line = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	vec2 g2 = abs(fract(wpos.xz / (grid_step * 0.2) - 0.5) - 0.5) / fwidth(wpos.xz / (grid_step * 0.2));
	float fine = 1.0 - clamp(min(g2.x, g2.y), 0.0, 1.0);
	float scan = exp(-pow(fract(wpos.z * 0.012 - TIME * 0.12) - 0.5, 2.0) * 900.0);
	float r = length(wpos.xz) / 90.0;
	vec3 c = base_color * (1.2 - r * 0.6);
	c += grid_color * (line * 0.22 + fine * 0.04 + scan * 0.05);
	ALBEDO = c * fade_in;
}
