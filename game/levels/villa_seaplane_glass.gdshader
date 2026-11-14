shader_type spatial;
// Verglasung des Wasserflugzeugs: liegt als Kopie der Rumpfhaut 4 mm ausserhalb und zeigt nur die
// Fensterflaechen (Maske wie im Lack-Shader). Getoent, spiegelnd (Fresnel), Innenraum dahinter sichtbar.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://game/levels/villa_seaplane_mask.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.02, 0.026, 0.03);
uniform float base_alpha = 0.38;
instance uniform vec3 part_offset = vec3(0.0);

varying vec3 v_p;

void vertex() {
	v_p = VERTEX + part_offset;
	VERTEX += NORMAL * 0.004;
}

void fragment() {
	vec3 p = v_p;
	if (sp_window_sd(p) > 0.0) {
		discard;
	}
	bool door = COLOR.a < 0.975;
	if (p.x < -0.3) {
		float dd = sp_door_sd(p);
		if (!door && dd < 0.0) {
			discard;
		}
		if (door && dd > 0.0) {
			discard;
		}
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = tint;
	METALLIC = 0.0;
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
	ALPHA = mix(base_alpha, 0.94, fres);
}
