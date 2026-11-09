shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Leuchtende Grenzlinie / Pfeil der Lagekarte. UV.x = relative Laenge entlang der Linie (0..1),
// UV.y = Querposition (0..1). reveal blendet die Linie von vorne nach hinten ein.

uniform vec3 color : source_color = vec3(0.3, 0.85, 1.0);
uniform float energy = 2.0;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float alpha = 1.0;
uniform float pulse = 0.0;

void fragment() {
	if (UV.x > reveal) {
		discard;
	}
	float edge = 1.0 - abs(UV.y - 0.5) * 2.0;
	float core = smoothstep(0.0, 0.6, edge);
	float head = smoothstep(reveal - 0.04, reveal, UV.x) * 1.5;
	float p = 1.0 + pulse * (0.5 + 0.5 * sin(TIME * 6.0 - UV.x * 30.0));
	ALBEDO = color * energy * (core + head) * p * alpha;
}
