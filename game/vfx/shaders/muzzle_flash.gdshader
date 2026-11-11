shader_type spatial;
// Muendungsfeuer-Sprite (Textur-Atlas aus assets/vfx/gen_muzzle_flash.py), rein additiv, HDR.
// Additiv per blend_premul_alpha mit ALPHA = 0: Farbe wird addiert, der Alpha-Kanal bleibt unberuehrt.
// (blend_add schreibt Alpha mit -> im transparenten Waffen-Viewport verdeckte das Feuer die Welt wie ein Aufkleber.)
// axial = false: kamerazugewandt (Front-Stern, Rotation per Instanz).
// axial = true:  Quad dreht sich nur um die Laufachse (lokal -Z) zur Kamera; Mesh-Y = entlang des Laufs,
//                Wurzel bei y = 0 (QuadMesh.center_offset). Seitenflamme.
// Mit dem Alter (0..1) werden die schwachen Bereiche zuerst weggefressen und die Farbe kuehlt ab.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D flash_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(2.0, 2.0);
uniform bool axial = false;
uniform float energy = 4.0;

instance uniform float frame = 0.0;
instance uniform float age = 0.0;
instance uniform float rot = 0.0;
instance uniform float strength = 1.0;

varying float v_view_fade;

void vertex() {
	vec3 cam_m = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	if (axial) {
		vec3 axis = vec3(0.0, 0.0, -1.0);
		vec3 to_cam = cam_m - axis * VERTEX.y;
		vec3 side = cross(axis, to_cam);
		float sl = length(side);
		side = sl > 1e-5 ? side / sl : vec3(1.0, 0.0, 0.0);
		// Blick genau entlang der Achse: Seitenflamme ausblenden (Front-Stern uebernimmt)
		v_view_fade = smoothstep(0.03, 0.25, sl / max(length(to_cam), 1e-4));
		VERTEX = side * VERTEX.x + axis * VERTEX.y;
	} else {
		vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]) * sc.x, normalize(INV_VIEW_MATRIX[1]) * sc.y, normalize(INV_VIEW_MATRIX[2]) * sc.z, MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * mw;
		// von der Seite gesehen ist der Front-Stern schwaecher (die Seitenflamme traegt dann)
		vec3 ax = normalize(MODEL_MATRIX[2].xyz);
		vec3 vd = normalize(CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz);
		v_view_fade = mix(0.45, 1.0, abs(dot(ax, vd)));
	}
}

void fragment() {
	vec2 uv = UV;
	if (!axial) {
		vec2 p = uv - 0.5;
		float c = cos(rot), s = sin(rot);
		uv = vec2(c * p.x - s * p.y, s * p.x + c * p.y) + 0.5;
	}
	float f = floor(mod(frame, grid.x * grid.y));
	vec2 cell = vec2(mod(f, grid.x), floor(f / grid.x));
	vec2 auv = (clamp(uv, vec2(0.002), vec2(0.998)) + cell) / grid;
	vec4 t = texture(flash_tex, auv);
	float a = t.a;
	// Erosion: duenne Ausleger verschwinden zuerst, der Kern bleibt
	float thr = age * 0.75;
	a *= smoothstep(thr, thr + 0.22, a);
	vec3 col = t.rgb * mix(vec3(1.0), vec3(1.0, 0.55, 0.25), age);
	ALBEDO = col * clamp(a, 0.0, 1.0) * energy * strength * v_view_fade * (1.0 - age * 0.6);
	ALPHA = 0.0;
}
