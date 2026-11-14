extends RefCounted
## Mission "Kräne", Teil B (Bootsfahrt): Nachtbeleuchtung, damit die Fahrt lesbar bleibt, ohne taghell zu wirken.
## Wird einmal beim Wechsel aufs Boot gesetzt (hafen.gd _start_boat):
##   - Mond tief im Nordosten (vor dem Boot): silberne Mondbahn auf dem Wasser, Boote/Bruecke als Silhouetten
##   - etwas mehr Himmels-/Umgebungslicht und hellerer Horizontdunst (Kontrast Silhouette gegen Dunst)
##   - Kailaternen (Natriumdampf/Halogen) an beiden Beckenufern und auf der Westmole
##   - Fahrwassertonnen mit Blitzfeuer (rot backbord, gruen steuerbord), schaukelnd
##   - Lichtbahnen: jede ufernahe Lampe spiegelt sich als flimmernder Streifen auf dem Wasser (Richtung Kamera)
## Glow/Env werden NACH PostFx.apply (Levelaufbau) gesetzt, ueberschreiben also dessen Werte nur fuer Teil B.

const Geo = preload("res://game/levels/level_geo.gd")
const FK = preload("res://game/levels/furniture_kit.gd")

const WATER_Y := -2.0
const BUOY_MODEL := "res://assets/environment/curfew/models/ocean_buoy"
const SODIUM := Color(1.0, 0.66, 0.34)
const HALIDE := Color(0.84, 0.9, 1.0)

## Lichtbahn auf dem Wasser: flaches Band vom Lampenfusspunkt zur Kamera, im Vertex-Shader jedes Frame
## ausgerichtet; Flimmern ueber zwei wandernde Wellenmuster, weiche Raender, Distanz-Abschwaechung.
const STREAK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, world_vertex_coords, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.7, 0.4, 1.0);
uniform float energy = 1.0;
uniform float len = 30.0;
uniform float width = 1.2;
uniform float seed = 0.0;
varying float v_along;
varying float v_across;
varying vec3 wp;
varying float cam_d;
void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec2 d = cam.xz - c.xz;
	float dl = length(d);
	d = dl > 0.01 ? d / dl : vec2(0.0, 1.0);
	vec2 r = vec2(-d.y, d.x);
	float u = UV.x - 0.5;
	float v = UV.y;
	float L = min(len, dl * 0.85);
	float wv = width * (0.55 + v * 1.6);
	vec2 p = c.xz + r * u * wv + d * v * L;
	VERTEX = vec3(p.x, c.y, p.y);
	v_along = v;
	v_across = u * 2.0;
	wp = VERTEX;
	cam_d = dl;
}
void fragment() {
	float t = TIME + seed;
	float b1 = sin(wp.x * 1.9 + wp.z * 2.7 + t * 2.3);
	float b2 = sin(dot(wp.xz, vec2(1.3, -0.8)) * 1.4 - t * 1.6);
	float b3 = sin(dot(wp.xz, vec2(-0.4, 1.1)) * 3.1 + t * 3.4);
	float bands = clamp(0.35 + 0.4 * b1 * b2 + 0.35 * b3, 0.0, 1.0);
	bands = bands * bands;
	float across = 1.0 - smoothstep(0.15, 1.0, abs(v_across) * (0.8 + 0.5 * b2 * b2));
	float along = smoothstep(0.0, 0.05, v_along) * pow(1.0 - v_along, 1.4);
	float fade = exp(-cam_d * 0.0028);
	ALBEDO = col.rgb * energy * across * along * bands * fade;
}
"""

static var _streak_shader: Shader = null

## Positions-/Signallicht als weicher runder Lichtpunkt: kamerazugewandtes Quad mit radialem Kern + Hof.
## Statt leuchtender Wuerfel/Zylinder (die im Glow als Quadrate erscheinen) bleibt das Licht auf jede Distanz
## ein runder Punkt: unter min_ang wird das Quad mitwachsend gehalten (Helligkeit dabei gedrosselt), in der
## Ferne blendet es weich aus. Kern ist die eigentliche Lampe, der Hof das Streulicht im Regen/Dunst.
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.1, 0.05, 1.0);
uniform float energy = 4.0;
uniform float size = 0.5;
uniform float min_ang = 0.0026;
uniform float fade_far = 1100.0;
varying float v_gain;
void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = max(length(cam - c), 0.01);
	float r = max(size, d * min_ang);
	v_gain = clamp(pow(size / r, 0.9), 0.22, 1.0) * (1.0 - smoothstep(fade_far * 0.55, fade_far, d));
	vec3 toward = (cam - c) / d;
	vec3 wpos = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * 2.0 * r + toward * min(r, d * 0.5);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
}
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float core = exp(-r * r * 38.0);
	float halo = exp(-r * r * 6.0) * (1.0 - smoothstep(0.7, 1.0, r));
	ALBEDO = col.rgb * energy * v_gain * (core + 0.16 * halo);
}
"""

static var _glow_shader: Shader = null
static var _glow_quad: QuadMesh = null

## Runder Lichtpunkt an pos (lokal zu parent). Rueckgabe: das Quad (Material ist eigen -> "shader_parameter/energy"
## laesst sich fuer Blitzfeuer tweenen).
static func glow_light(parent: Node, pos: Vector3, c: Color, energy: float = 4.0, size: float = 0.5) -> MeshInstance3D:
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER
		_glow_quad = QuadMesh.new()
		_glow_quad.size = Vector2(1.0, 1.0)
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("size", size)
	var mi := MeshInstance3D.new()
	mi.name = "Lichtpunkt"
	mi.mesh = _glow_quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	mi.position = pos
	parent.add_child(mi)
	return mi

static func apply(lv: Node3D, path: Array[Vector3]) -> void:
	if lv.has_node("BootNacht"):
		return
	var root := Node3D.new()
	root.name = "BootNacht"
	lv.add_child(root)
	_quay_lamps(root)
	_buoys(root, path)
	_streaks(lv, root, path)
	_env(lv)

# ------------------------------------------------------------------ Licht/Env

static func _env(lv: Node3D) -> void:
	var we := lv.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.ambient_light_color = Color(0.3, 0.36, 0.52)
		env.ambient_light_energy = 1.55
		env.fog_light_color = Color(0.075, 0.085, 0.112)
		env.volumetric_fog_emission = Color(0.0025, 0.0028, 0.0038)
		# Volumetrik bis 170 m statt 96 m: Suchscheinwerfer der Garde-Boote/des Helis zeichnen ihren Strahl im
		# Regen auch auf Gefechtsabstand (Bruecke ~90 m, Boote 100-170 m); Detailverteilung bleibt nah dicht
		env.volumetric_fog_length = 170.0
		env.volumetric_fog_detail_spread = 2.4
		# Lampen bekommen weiche Lichthoefe, Wasserglanz bleibt darunter (PostFx night_city: 0.8 / 1.0)
		env.glow_intensity = 0.95
		env.glow_hdr_threshold = 0.85
		env.glow_bloom = 0.03
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sm := (env.sky.sky_material as ProceduralSkyMaterial).duplicate() as ProceduralSkyMaterial
			sm.sky_top_color = Color(0.045, 0.07, 0.13)
			sm.sky_horizon_color = Color(0.22, 0.19, 0.19)
			sm.sky_energy_multiplier = 1.3
			sm.sun_angle_max = 1.2
			sm.sun_curve = 0.02
			env.sky.sky_material = sm
	# Wasser: Fresnel-Himmelsreflex auf den Nachthorizont (kuehles Graublau statt Abendrot), etwas staerker,
	# damit die Wasserflaeche im flachen Blick als Flaeche lesbar bleibt (steil nach unten bleibt sie schwarz)
	var water := lv.get_node_or_null("Water") as MeshInstance3D
	if water != null and water.material_override is ShaderMaterial:
		var wm := water.material_override as ShaderMaterial
		wm.set_shader_parameter("sky_tint", Color(0.13, 0.145, 0.19))
		wm.set_shader_parameter("fresnel_amt", 0.65)
	var moon := lv.get_node_or_null("Moon") as DirectionalLight3D
	if moon != null:
		# Mond ~38 Grad hoch links (Westen) leicht voraus: die Mondbahn liegt seitlich auf dem Wasser und
		# blendet nicht in Fahrtrichtung (frueher: tiefer Mond voraus -> weisser Glanzfleck vor dem Bug)
		var dir := Vector3(0.74, -0.62, 0.26).normalized()
		moon.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
		moon.light_color = Color(0.66, 0.75, 1.0)
		moon.light_energy = 0.8
		moon.light_specular = 0.45

# ------------------------------------------------------------------ Kailaternen

static func _quay_lamps(root: Node3D) -> void:
	var pole_m := Geo.flat(Color(0.18, 0.19, 0.2), 0.55, 0.7)
	var spots: Array = []
	# Westkai (Land x < 41), Ostkai (Land x > 140 bis z -930), Westmole (z -1150)
	var z := -330.0
	while z > -1130.0:
		if absf(z - (-620.0)) > 16.0:
			spots.append([Vector3(38.6, 0.0, z), 1.0, SODIUM if int(absf(z)) % 3 != 0 else HALIDE])
		z -= 58.0
	z = -312.0
	while z > -925.0:
		if absf(z - (-620.0)) > 16.0:
			spots.append([Vector3(142.4, 0.0, z), -1.0, SODIUM])
		z -= 64.0
	for x: float in [70.0, 140.0, 210.0, 280.0]:
		spots.append([Vector3(x, 2.0, -1151.5), 0.0, HALIDE])
	var i := 0
	for s: Array in spots:
		var p: Vector3 = s[0]
		var side: float = s[1]
		var c: Color = s[2]
		var h := 9.0
		root.add_child(Geo.cylinder_node(0.11, h, pole_m, p + Vector3(0, h * 0.5, 0), Vector3.ZERO, 8))
		# Ausleger zum Wasser hin, Leuchtenkopf mit leuchtender Unterseite
		var arm := Vector3(side * 1.1, 0, 0) if side != 0.0 else Vector3(0, 0, 1.1)
		var head_p := p + Vector3(0, h - 0.1, 0) + arm
		root.add_child(Geo.box_mesh_node(Vector3(absf(arm.x) + 0.12, 0.08, absf(arm.z) + 0.12), pole_m, p + Vector3(0, h, 0) + arm * 0.5))
		root.add_child(Geo.box_mesh_node(Vector3(0.62, 0.16, 0.34), pole_m, head_p + Vector3(0, 0.06, 0)))
		var lens := Geo.flat(c, 0.4, 0.0, c, 4.0)
		var lm := Geo.box_mesh_node(Vector3(0.52, 0.03, 0.26), lens, head_p - Vector3(0, 0.03, 0))
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(lm)
		glow_light(root, head_p - Vector3(0, 0.12, 0), c, 1.6, 0.55)   # weicher Lichthof unter dem Leuchtenkopf
		var l := OmniLight3D.new()
		l.name = "KaiLaterne%d" % i
		l.light_color = c
		l.light_energy = 3.2
		l.omni_range = 24.0
		l.omni_attenuation = 1.3
		l.light_volumetric_fog_energy = 0.6
		l.distance_fade_enabled = true
		l.distance_fade_begin = 220.0
		l.distance_fade_length = 40.0
		l.position = head_p - Vector3(0, 0.35, 0)
		root.add_child(l)
		i += 1

# ------------------------------------------------------------------ Fahrwassertonnen

static func _buoys(root: Node3D, path: Array[Vector3]) -> void:
	var red_body := Geo.mat("rusty_metal_02", Color(0.75, 0.22, 0.16), 0.5, 1.0, 0.3)
	var grn_body := Geo.mat("rusty_metal_02", Color(0.22, 0.5, 0.26), 0.5, 1.0, 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var acc := 0.0
	var next := 60.0
	var k := 0
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var seg := a.distance_to(b)
		var d := (b - a) / maxf(seg, 0.001)
		var right := Vector3(-d.z, 0.0, d.x)
		while acc + seg >= next:
			var p := a + d * (next - acc)
			next += 85.0
			if absf(p.z - (-620.0)) < 22.0:
				continue
			var port := k % 2 == 0
			k += 1
			var q := p + right * (-17.0 if port else 17.0)
			if q.z > -925.0:
				q.x = clampf(q.x, 48.0, 133.0)
			_buoy(root, Vector3(q.x, WATER_Y, q.z), port, red_body, grn_body, rng)
		acc += seg

static func _buoy(root: Node3D, p: Vector3, port: bool, red_body: Material, grn_body: Material, rng: RandomNumberGenerator) -> void:
	var bob := Node3D.new()
	bob.name = "Tonne"
	bob.position = p
	root.add_child(bob)
	var top := 1.9
	if not port or not FK.place(bob, BUOY_MODEL, Vector3(0, 0.53, 0), Vector3(1.07, 2.66, 0.95), rng.randf_range(0, 360), {"scale": 1.0}):
		# Spierentonne/Stumpftonne: Schwimmkoerper, Gitteraufbau, Toppzeichen
		var m := red_body if port else grn_body
		bob.add_child(Geo.cylinder_node(0.7, 1.4, m, Vector3(0, -0.1, 0), Vector3.ZERO, 14))
		bob.add_child(Geo.cylinder_node(0.22, 1.5, m, Vector3(0, 1.3, 0), Vector3.ZERO, 8))
		bob.add_child(Geo.cylinder_node(0.35, 0.3, m, Vector3(0, 2.05, 0), Vector3.ZERO, 10))
		top = 2.35
	var c := Color(1.0, 0.12, 0.08) if port else Color(0.15, 1.0, 0.3)
	var lamp_m := Geo.flat(c * 0.3, 0.4).duplicate() as StandardMaterial3D
	lamp_m.emission_enabled = true
	lamp_m.emission = c
	lamp_m.emission_energy_multiplier = 0.0
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	sm.radial_segments = 8
	sm.rings = 4
	var lamp := Geo.mesh_node(sm, lamp_m, Vector3(0, top, 0), false)
	bob.add_child(lamp)
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 0.0
	l.omni_range = 11.0
	l.light_volumetric_fog_energy = 1.2
	l.position = Vector3(0, top + 0.1, 0)
	l.set_meta("no_streak", true)
	bob.add_child(l)
	# runder Lichtpunkt (Fresnel-Laterne): bleibt auch auf 300+ m ein weicher Punkt statt eines Glow-Quadrats
	var gm := glow_light(bob, Vector3(0, top, 0), c, 0.0, 0.32).material_override as ShaderMaterial
	# Blitzfeuer (Kennung Fl. 3 s), Phasen versetzt
	var tw := bob.create_tween().set_loops()
	tw.tween_interval(rng.randf_range(0.2, 2.8))
	tw.tween_property(l, "light_energy", 2.2, 0.08)
	tw.parallel().tween_property(lamp_m, "emission_energy_multiplier", 3.0, 0.08)
	tw.parallel().tween_property(gm, "shader_parameter/energy", 5.0, 0.08)
	tw.tween_interval(0.5)
	tw.tween_property(l, "light_energy", 0.0, 0.25)
	tw.parallel().tween_property(lamp_m, "emission_energy_multiplier", 0.0, 0.25)
	tw.parallel().tween_property(gm, "shader_parameter/energy", 0.0, 0.25)
	tw.tween_interval(2.2)
	# Schaukeln in der Duenung
	var ph := rng.randf_range(0.0, TAU)
	var tb := bob.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var r0 := Vector3(deg_to_rad(4.0) * sin(ph), bob.rotation.y, deg_to_rad(4.0) * cos(ph))
	tb.tween_property(bob, "rotation", r0, 1.6 + rng.randf() * 0.6)
	tb.parallel().tween_property(bob, "position:y", WATER_Y + 0.12, 1.6)
	tb.tween_property(bob, "rotation", Vector3(-r0.x, bob.rotation.y, -r0.z), 1.7 + rng.randf() * 0.6)
	tb.parallel().tween_property(bob, "position:y", WATER_Y - 0.1, 1.7)

# ------------------------------------------------------------------ Lichtbahnen auf dem Wasser

static func _path_dist(p: Vector3, path: Array[Vector3]) -> float:
	var best := INF
	var q := Vector2(p.x, p.z)
	for i in range(1, path.size()):
		var a := Vector2(path[i - 1].x, path[i - 1].z)
		var b := Vector2(path[i].x, path[i].z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best

static func _in_freed(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p.is_queued_for_deletion():
			return true
		p = p.get_parent()
	return false

static func _streaks(lv: Node3D, root: Node3D, path: Array[Vector3]) -> void:
	if _streak_shader == null:
		_streak_shader = Shader.new()
		_streak_shader.code = STREAK_SHADER
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.0, 1.0)
	pm.center_offset = Vector3(0, 0, 0.5)
	pm.subdivide_depth = 10
	var n := 0
	for node in lv.find_children("*", "Light3D", true, false):
		var l := node as Light3D
		if l is DirectionalLight3D or l.has_meta("no_streak") or not l.is_visible_in_tree() or l.light_energy < 0.8:
			continue
		if l.is_queued_for_deletion() or _in_freed(l):
			continue
		var gp := l.global_position
		var h := gp.y - WATER_Y
		if h < 1.5 or h > 50.0:
			continue
		if _path_dist(gp, path) > 85.0:
			continue
		var m := ShaderMaterial.new()
		m.shader = _streak_shader
		var c := l.light_color
		m.set_shader_parameter("col", c)
		# kraeftiger, laenger, breiter: die Bahnen sollen das Nachtwasser lesbar machen (Kailaternen ~9 m -> ~40 m Bahn)
		m.set_shader_parameter("energy", clampf(l.light_energy * 0.5, 0.6, 2.4))
		m.set_shader_parameter("len", clampf(h * 4.4, 14.0, 95.0))
		m.set_shader_parameter("width", clampf(1.0 + h * 0.1, 1.2, 4.2))
		m.set_shader_parameter("seed", float(n) * 1.37)
		var mi := MeshInstance3D.new()
		mi.name = "Lichtbahn%d" % n
		mi.mesh = pm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-80, -1, -80), Vector3(160, 2, 160))
		mi.visibility_range_end = 420.0
		mi.position = Vector3(gp.x, WATER_Y + 0.2, gp.z)
		root.add_child(mi)
		n += 1
	print("[hafen] Bootsnacht: %d Lichtbahnen" % n)
