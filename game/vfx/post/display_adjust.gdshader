shader_type canvas_item;
// Anzeige-Kalibrierung (Graphics-Autoload): Helligkeit, Kontrast, Gamma ueber dem fertigen Bild.
// Liegt ganz oben (ueber HUD und Menues) und ist nur sichtbar, wenn ein Wert vom Neutralwert abweicht.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float brightness = 1.0;
uniform float contrast = 1.0;
uniform float gamma = 1.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	c = (c - 0.5) * contrast + 0.5;
	c *= brightness;
	c = pow(max(c, vec3(0.0)), vec3(1.0 / max(gamma, 0.05)));
	COLOR = vec4(c, 1.0);
}
