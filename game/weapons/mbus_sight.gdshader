shader_type spatial;
// Magpul MBUS (Kimme/Korn) – PBR aus den Modelltexturen (ORM: G = Rauheit, B = Metall).
// Nah am Auge (ADS: Kimme wenige cm vor der Kamera) wird die Oberflaeche "unscharf": Mip-Bias auf alle
// Texturen, dunkler, rauer, flachere Normalen – das Kimmenblatt liest sich als weicher dunkler Rahmen,
// waehrend Korn und Ziel scharf bleiben. Ab near_dist (Huefte, Seitenansicht, Weltmodell) unveraendert.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform float near_dist = 0.11;     // ab hier (m Abstand zur Kamera) beginnt die Unschaerfe
uniform float blur_bias = 5.0;      // Mip-Bias bei voller Unschaerfe
uniform float near_dark = 0.5;      // Helligkeit bei voller Unschaerfe

void fragment() {
	float k = clamp((near_dist - length(VERTEX)) / (near_dist * 0.45), 0.0, 1.0);
	float b = k * blur_bias;
	vec3 orm = texture(orm_tex, UV, b).rgb;
	ALBEDO = texture(albedo_tex, UV, b).rgb * mix(1.0, near_dark, k);
	ROUGHNESS = mix(orm.g, 1.0, k);
	METALLIC = orm.b * (1.0 - k);
	NORMAL_MAP = texture(normal_tex, UV, b).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.25, k);
}
