shader_type canvas_item;
render_mode unshaded;
// Kino-/Militaer-Shooter-Nachbearbeitung (ersetzt zur Laufzeit post_fx.gdshader, siehe Graphics-Autoload).
// Liegt auf CanvasLayer 2: ueber Welt und Waffe (1), unter Zielfernrohr (3), Nachtsicht (3) und HUD (5+).
// Reihenfolge: chromatische Aberration -> Nachschaerfen (CAS) -> Kamera-Bewegungsunschaerfe (Waffe maskiert)
// -> Saettigung/Lift -> Farb-LUT (Teal-Orange) -> Vignette -> Filmkorn.
// Die ersten sieben Uniforms sind namensgleich mit post_fx.gdshader (Level-Profile bleiben gueltig).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aberration = 0.0018;
uniform float vignette = 0.32;
uniform float vignette_soft = 0.55;
uniform float grain = 0.035;
uniform float grain_size = 1.6;
uniform float saturation = 1.0;
uniform vec3 lift = vec3(0.0);

uniform sampler3D grade_lut : filter_linear, repeat_disable;
uniform float grade_mix = 0.0;          // 0 = kein Grading, 1 = volle LUT
uniform float lut_size = 32.0;
uniform float sharpen = 0.0;            // 0..1 (Contrast Adaptive Sharpening, vereinfachte Fassung)
uniform vec2 blur_vec = vec2(0.0);      // Kamera-Bewegung in UV pro Belichtung
uniform sampler2D weapon_mask : hint_default_transparent, filter_linear, repeat_disable;
uniform float use_weapon_mask = 0.0;
uniform float fx_mute = 0.0;            // 1 = Sondersicht (Nachtsicht/Drohne): Grading/Schaerfe/Unschaerfe aus

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 tap(vec2 uv) {
	return textureLod(screen_tex, uv, 0.0).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	float live = 1.0 - clamp(fx_mute, 0.0, 1.0);
	vec2 d = uv - 0.5;
	float r2 = dot(d * vec2(aspect, 1.0), d * vec2(aspect, 1.0));

	// Chromatische Aberration (nur zum Rand hin)
	vec2 off = d * aberration * r2 * (0.3 + 0.7 * live);
	vec3 c;
	c.r = textureLod(screen_tex, uv - off, 0.0).r;
	c.g = textureLod(screen_tex, uv, 0.0).g;
	c.b = textureLod(screen_tex, uv + off, 0.0).b;

	// Nachschaerfen (CAS): staerker in flachen Bereichen, kein Ueberschwingen an harten Kanten
	float sh = sharpen * live;
	if (sh > 0.001) {
		vec3 n = tap(uv + vec2(0.0, -px.y));
		vec3 s = tap(uv + vec2(0.0, px.y));
		vec3 e = tap(uv + vec2(px.x, 0.0));
		vec3 w = tap(uv + vec2(-px.x, 0.0));
		vec3 mn = min(min(min(n, s), min(e, w)), c);
		vec3 mx = max(max(max(n, s), max(e, w)), c);
		vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0));
		vec3 wt = amp * (-1.0 / mix(8.0, 5.0, clamp(sh, 0.0, 1.0)));
		c = max((c + (n + s + e + w) * wt) / (1.0 + 4.0 * wt), vec3(0.0));
	}

	// Kamera-Bewegungsunschaerfe: Waffe (Viewmodel-Alpha) bleibt scharf und blutet nicht in die Welt
	vec2 bv = blur_vec * live;
	if (dot(bv, bv) > 1e-7) {
		float wm = use_weapon_mask > 0.5 ? textureLod(weapon_mask, uv, 0.0).a : 0.0;
		bv *= 1.0 - wm;
		if (dot(bv, bv) > 1e-7) {
			float jit = hash(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
			vec3 acc = c;
			float wsum = 1.0;
			for (int i = 0; i < 8; i++) {
				float t = (float(i) + 0.5 + jit) / 8.0 - 0.5;
				vec2 suv = uv + bv * t;
				float k = 1.0;
				if (use_weapon_mask > 0.5) {
					k = 1.0 - textureLod(weapon_mask, suv, 0.0).a;
				}
				acc += tap(suv) * k;
				wsum += k;
			}
			c = acc / wsum;
		}
	}

	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	c += lift * (1.0 - clamp(luma * 4.0, 0.0, 1.0));

	// Farb-LUT (per Skript erzeugt, game/graphics/grade_lut.gd); Texelmitten exakt treffen
	float gm = grade_mix * live;
	if (gm > 0.001) {
		vec3 uvw = clamp(c, 0.0, 1.0) * ((lut_size - 1.0) / lut_size) + 0.5 / lut_size;
		vec3 g = textureLod(grade_lut, uvw, 0.0).rgb;
		c = mix(c, g + max(c - 1.0, vec3(0.0)), gm);
	}

	// Vignette
	float vr = length(d * vec2(aspect * 0.78, 1.0));
	float vig = smoothstep(0.85, 0.85 - vignette_soft, vr);
	c *= mix(1.0, vig, vignette);

	// Filmkorn (24 Bilder/s, in den Mitteltoenen am staerksten)
	vec2 gp = floor(FRAGCOORD.xy / grain_size);
	float tt = floor(TIME * 24.0);
	float gr = hash(gp + tt * 13.17) + hash(gp * 1.7 + tt * 7.31) - 1.0;
	luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float mids = 1.0 - abs(clamp(luma, 0.0, 1.0) * 2.0 - 1.0);
	c += gr * grain * (0.35 + 0.65 * mids);
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
