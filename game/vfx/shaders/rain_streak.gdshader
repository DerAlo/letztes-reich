shader_type spatial;
// Regenstreifen: QuadMesh auf Partikel mit particle_flag_align_y (Y = Fallrichtung).
// Achsenfestes Billboard um die Fallrichtung, weiche Kanten, Helligkeit per Uniform (Blitz hebt sie an).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.62, 0.68, 0.76);
uniform float brightness = 0.35;
uniform float flash = 0.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 ay = MODEL_MATRIX[1].xyz;
	float sy = length(ay);
	ay /= max(sy, 0.0001);
	float sx = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 ax = cross(ay, to_cam);
	float lx = length(ax);
	ax = lx > 0.001 ? ax / lx : vec3(1.0, 0.0, 0.0);
	vec3 wp = origin + ax * VERTEX.x * sx + ay * VERTEX.y * sy;
	mat4 inv_model = inverse(MODEL_MATRIX);
	VERTEX = (inv_model * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((inv_model * vec4(to_cam, 0.0)).xyz);
}

void fragment() {
	float across = 1.0 - pow(abs(UV.x * 2.0 - 1.0), 1.5);
	float along = smoothstep(0.0, 0.35, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	// sehr nahe Tropfen ausblenden (sonst riesige Streifen direkt vor der Kamera)
	float near_fade = smoothstep(0.6, 2.5, -VERTEX.z);
	ALBEDO = tint * (brightness + flash * 2.5) * COLOR.rgb;
	ALPHA = clamp(across * along * near_fade * COLOR.a, 0.0, 1.0);
}
