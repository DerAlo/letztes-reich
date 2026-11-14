shader_type spatial;
// Bluttropfen fuer GPUParticles3D (blood_fx.gd): achsenausgerichtetes Billboard entlang der Flugrichtung
// (ParticleProcessMaterial.particle_flag_align_y -> MODEL_MATRIX[1] = Geschwindigkeitsrichtung).
// Quad dreht sich nur um die Flugachse zur Kamera -> gestreckte Tropfen/Striche statt Kugeln.
// Beleuchtet mit gewoelbter Pseudo-Normale (Glanzpunkt wie bei einem Fluessigkeitstropfen).
// stretch: Laenge/Breite. Die Streckung nimmt mit dem Alter ab (Tropfen bremst/zerfaellt).
render_mode skip_vertex_transform, blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx, shadows_disabled;

uniform sampler2D drop_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 blood_color : source_color = vec3(0.23, 0.012, 0.01);
uniform float stretch = 3.0;
uniform float stretch_end = 1.3;
uniform float roughness_v = 0.16;
uniform float near_fade = 0.25;

varying float v_life;
varying float v_dist;

void vertex() {
	v_life = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	vec3 p = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 axis = MODEL_MATRIX[1].xyz;
	axis = length(axis) > 1e-5 ? normalize(axis) : vec3(0.0, 1.0, 0.0);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = normalize(cam - p);
	vec3 side = cross(axis, to_cam);
	if (length(side) < 1e-4) {
		side = INV_VIEW_MATRIX[0].xyz;
	}
	side = normalize(side);
	float st = mix(stretch, stretch_end, v_life);
	vec3 w = p + side * VERTEX.x * s + axis * VERTEX.y * s * st;
	vec3 nrm = normalize(cross(side, axis));
	if (dot(nrm, to_cam) < 0.0) {
		nrm = -nrm;
	}
	v_dist = length(cam - w);
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	TANGENT = normalize((VIEW_MATRIX * vec4(side, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(axis, 0.0)).xyz);
}

void fragment() {
	vec4 t = texture(drop_tex, UV);
	vec2 q = UV * 2.0 - 1.0;
	// gewoelbte Kuppel: Normale kippt zum Rand hin
	float r2 = clamp(dot(q, q), 0.0, 1.0);
	NORMAL_MAP = vec3(q.x * 0.5 * 0.8 + 0.5, -q.y * 0.5 * 0.8 + 0.5, sqrt(1.0 - r2) * 0.5 + 0.5);
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = blood_color * COLOR.rgb;
	ROUGHNESS = roughness_v;
	SPECULAR = 0.6;
	// Durchscheinen bei Gegenlicht (duenne Tropfen leuchten rot statt schwarz)
	BACKLIGHT = blood_color * 0.8;
	ALPHA = t.a * COLOR.a * smoothstep(0.02, near_fade, v_dist);
}
