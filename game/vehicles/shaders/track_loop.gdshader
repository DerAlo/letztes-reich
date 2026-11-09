shader_type spatial;
// Durchgehendes Kettenband (ein Mesh je Seite, um Leitrad/Laufrollen/Antriebsrad gelegt).
// UV.y = Bogenlaenge entlang der Kette (m), UV.x = quer (0..1), COLOR.r = 1 aussen (Lauffläche), 0 innen.
// TANGENT zeigt in Laufrichtung -> prozedurale Normal-Map fuer Glieder, Stege und Fuehrungszaehne.
// scroll = zurueckgelegter Weg (m) der Seite.
render_mode cull_back;

uniform float scroll = 0.0;
uniform float link_len = 0.16;
uniform sampler2D detail : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 steel : source_color = vec3(0.2, 0.19, 0.18);
uniform vec3 rust : source_color = vec3(0.26, 0.17, 0.1);
uniform vec3 dirt : source_color = vec3(0.22, 0.19, 0.15);

void fragment() {
	float s = (UV.y - scroll) / link_len;
	float f = fract(s);
	float outer = COLOR.r;
	float x = UV.x;
	// Hoehenprofil eines Gliedes: Spalt an den Enden, Steg (Grouser) aussen, zwei Polster innen
	float gap = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.92, 1.0, f));
	float grouser = smoothstep(0.28, 0.36, f) * (1.0 - smoothstep(0.62, 0.7, f));
	float pad = (1.0 - smoothstep(0.06, 0.1, abs(x - 0.5) - 0.12)) * step(abs(x - 0.5), 0.45);
	float horn = (1.0 - outer) * (1.0 - smoothstep(0.035, 0.05, abs(x - 0.5))) * smoothstep(0.3, 0.38, f) * (1.0 - smoothstep(0.55, 0.63, f));
	float hgt = gap * 0.4 + outer * grouser * 0.6 + horn * 0.8;
	float dh = (dFdx(hgt) * dFdx(s) + dFdy(hgt) * dFdy(s)) / max(dFdx(s) * dFdx(s) + dFdy(s) * dFdy(s), 1e-6);
	dh = clamp(dh, -6.0, 6.0);
	NORMAL_MAP = normalize(vec3(-dh * 0.35, 0.0, 1.0)) * 0.5 + 0.5;

	vec3 tex = texture(detail, vec2(x * 0.6, UV.y * 0.6)).rgb;
	vec3 c = mix(rust, steel, 0.55 + 0.45 * grouser * outer + 0.3 * horn);
	c *= 0.75 + 0.6 * dot(tex, vec3(0.333));
	c *= mix(0.22, 1.0, gap);
	// Laufflaeche blank gescheuert, Innenseite und Raender verschmutzt
	float worn = outer * grouser * pad;
	c = mix(c, vec3(0.42, 0.41, 0.39), worn * 0.6);
	c = mix(c, dirt, (1.0 - outer) * 0.35 + (1.0 - pad) * 0.25);
	ALBEDO = c;
	METALLIC = mix(0.3, 0.85, worn) * gap;
	ROUGHNESS = mix(0.85, 0.35, worn);
}
