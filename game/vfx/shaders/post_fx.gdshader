shader_type canvas_item;
// Bildschirm-Nachbearbeitung fuer den Militaer-Shooter-Look (liegt ueber Welt und Waffe, unter dem HUD):
// leichte chromatische Aberration zum Rand hin, Vignette, feines animiertes Filmkorn
// (in den Mitteltoenen am staerksten, in Lichtern/Tiefen schwaecher), optional Entsaettigung.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aberration = 0.0018;     // Versatz am Bildrand (Anteil der Bildbreite)
uniform float vignette = 0.32;         // Abdunklung in den Ecken
uniform float vignette_soft = 0.55;
uniform float grain = 0.035;
uniform float grain_size = 1.6;        // Korngroesse in Pixeln
uniform float saturation = 1.0;
uniform vec3 lift = vec3(0.0);         // Anhebung der Tiefen (z. B. Nacht leicht blaeulich)

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 d = uv - 0.5;
	float r2 = dot(d * vec2(aspect, 1.0), d * vec2(aspect, 1.0));
	vec2 off = d * aberration * r2;
	vec3 c;
	c.r = textureLod(screen_tex, uv - off, 0.0).r;
	c.g = textureLod(screen_tex, uv, 0.0).g;
	c.b = textureLod(screen_tex, uv + off, 0.0).b;

	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	c += lift * (1.0 - clamp(luma * 4.0, 0.0, 1.0));

	// Vignette (rund, an das Seitenverhaeltnis angepasst)
	float vr = length(d * vec2(aspect * 0.78, 1.0));
	float vig = smoothstep(0.85, 0.85 - vignette_soft, vr);
	c *= mix(1.0, vig, vignette);

	// Filmkorn: zwei Ebenen, zeitlich wechselnd (ca. 24 Bilder/s)
	vec2 gp = floor(FRAGCOORD.xy / grain_size);
	float tt = floor(TIME * 24.0);
	float g = hash(gp + tt * 13.17) + hash(gp * 1.7 + tt * 7.31) - 1.0;
	float mids = 1.0 - abs(luma * 2.0 - 1.0);
	c += g * grain * (0.35 + 0.65 * mids);
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
