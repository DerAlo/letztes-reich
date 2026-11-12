shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Glas des Reflexvisiers mit parallaxenfreiem Leuchtpunkt.
// Der Punkt liegt "im Unendlichen" entlang der Waffenachse (axis_local, Objektraum des Glases):
// im ADS (Waffe auf der Kameraachse) sitzt er exakt in der Bildmitte, bei Sway/Rückstoß wandert er
// mit der Waffe. Größe ~2 MOA, mindestens ~1 Pixel Radius, damit er scharf sichtbar bleibt.

uniform vec4 glass_tint : source_color = vec4(0.55, 0.75, 0.80, 0.07);
uniform vec4 coat_tint : source_color = vec4(0.35, 0.95, 0.55, 1.0);   // Beschichtung am Rand (leicht grünlich)
uniform vec4 dot_color : source_color = vec4(1.0, 0.04, 0.02, 1.0);
uniform float dot_radius_deg = 0.0167;   // 2 MOA Durchmesser
uniform float min_radius_px = 1.1;
uniform float glow_strength = 0.55;
uniform float halo_strength = 0.06;
uniform float brightness = 3.0;
uniform vec3 axis_local = vec3(0.0, 0.0, -1.0);
uniform vec2 half_size = vec2(0.017, 0.013);
uniform float ring_radius_deg = 0.0;   // > 0: holografischer Ring (EOTech-Stil, 65 MOA ~ 0.54 Grad)
uniform float ring_width_deg = 0.03;
// Rundes Objektivglas (Rohr-Rotpunkt): Kreis mit Radius half_size.x, aussen verworfen; Vergütung
// leicht violett-bernstein statt grün, kaum Tönung, Punkt dezenter (weniger Glow).
uniform bool round_glass = false;

varying vec3 obj_pos;
varying vec3 axis_view;

void vertex() {
	obj_pos = VERTEX;
	axis_view = normalize((MODELVIEW_MATRIX * vec4(axis_local, 0.0)).xyz);
}

void fragment() {
	vec3 ray = normalize(VERTEX);
	float ang = degrees(acos(clamp(dot(ray, normalize(axis_view)), -1.0, 1.0)));
	// Winkel pro Pixel -> Mindestgröße, damit 2 MOA nicht im Subpixel verschwindet
	float px = max(fwidth(ang), 1e-5);
	float r = max(dot_radius_deg, px * min_radius_px);
	float aa = px * 0.6;
	float core = 1.0 - smoothstep(r - aa, r + aa, ang);
	float glow = exp(-pow(ang / (r * 3.0), 2.0)) * glow_strength;
	float halo = exp(-pow(ang / (r * 10.0), 2.0)) * halo_strength;
	// Glas: Rand-Beschichtung + diagonaler Reflexstreifen
	vec2 e = abs(obj_pos.xy) / half_size;
	float edge = smoothstep(0.75, 1.0, max(e.x, e.y));
	vec3 coat = coat_tint.rgb;
	float glow_k = 1.0;
	if (round_glass) {
		float rr = length(obj_pos.xy) / half_size.x;
		if (rr > 1.0) {
			discard;
		}
		edge = smoothstep(0.7, 1.0, rr);
		coat = vec3(0.55, 0.42, 0.75);
		glow_k = 0.55;
	}
	float streak_c = (obj_pos.x / half_size.x) * 0.6 + (obj_pos.y / half_size.y) * 0.8;
	float streak = exp(-pow((streak_c - 0.55) / 0.12, 2.0)) * 0.05;
	vec3 glass = mix(glass_tint.rgb, coat, edge * 0.35) + vec3(streak);
	float ga = glass_tint.a + edge * 0.06 + streak;
	vec3 hot = mix(dot_color.rgb, vec3(1.0, 0.6, 0.5), core * 0.35) * brightness;
	float ring = 0.0;
	if (ring_radius_deg > 0.0) {
		float rw = max(ring_width_deg, px * 1.2) * 0.5;
		float rd = abs(ang - ring_radius_deg);
		ring = (1.0 - smoothstep(rw - aa, rw + aa, rd)) * 0.9 + exp(-pow(rd / (rw * 4.0), 2.0)) * 0.12;
	}
	float d = clamp(core + (glow + halo) * glow_k + ring, 0.0, 1.0);
	ALBEDO = mix(glass, hot, d);
	ALPHA = clamp(ga + d, 0.0, 1.0);
}
