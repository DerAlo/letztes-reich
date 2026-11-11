shader_type spatial;
// UV-gemapptes Modellmaterial (Poly-Haven-Modelle, Sandsaecke) mit Schneeauflage auf nach oben
// zeigenden Flaechen. Ergaenzt snowy.gdshader (triplanar) fuer Meshes mit eigenen Texturen.
// Instanzfarbe (MultiMesh) wird ueber COLOR in die Albedo multipliziert.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_albedo = true;
uniform bool has_normal = true;
uniform bool has_arm = true;
uniform bool arm_has_ao = true;        // R-Kanal = AO (Poly-Haven-ARM); sonst ignoriert
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float rough_mul = 1.0;
uniform float metal_mul = 1.0;
uniform float normal_depth = 1.0;

uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 snow_tint : source_color = vec3(0.82, 0.87, 0.96);
uniform float snow_scale = 0.35;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.5;
uniform float snow_sharp = 7.0;
uniform float noise_amp = 0.6;
uniform float noise_scale = 0.18;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 alb = tint.rgb * COLOR.rgb;
	if (has_albedo) {
		alb *= texture(albedo_tex, uv).rgb;
	}
	float ao = 1.0;
	float rough = rough_mul;
	float metal = 0.0;
	if (has_arm) {
		vec3 arm = texture(arm_tex, uv).rgb;
		ao = arm_has_ao ? arm.r : 1.0;
		rough = arm.g * rough_mul;
		metal = arm.b * metal_mul;
	}
	vec3 nm = has_normal ? texture(normal_tex, uv).rgb : vec3(0.5, 0.5, 1.0);
	// Schnee: geometrische Weltnormale + Rauschen; in Hohlraeumen (AO) weniger Schnee
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float nz = texture(noise_tex, wpos.xz * noise_scale + wpos.y * 0.07).r;
	float s = clamp((n.y - (1.0 - snow_amount) + (nz - 0.5) * noise_amp) * snow_sharp, 0.0, 1.0);
	s *= smoothstep(0.25, 0.7, ao);
	vec3 sp = wpos * snow_scale;
	vec3 salb = tri(snow_albedo, sp, w).rgb * snow_tint;
	ALBEDO = mix(alb, salb, s);
	ROUGHNESS = mix(rough, 0.62, s);
	METALLIC = mix(metal, 0.0, s);
	AO = mix(ao, 1.0, s);
	AO_LIGHT_AFFECT = 0.3;
	NORMAL_MAP = mix(nm, tri(snow_normal, sp, w).rgb, s);
	NORMAL_MAP_DEPTH = normal_depth;
	SPECULAR = mix(0.5, 0.65, s);
}
