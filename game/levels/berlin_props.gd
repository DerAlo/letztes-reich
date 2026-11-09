extends RefCounted
## Bausteine fuer Level "berlin" (Das letzte Reich): Materialien aus assets/environment/berlin/textures
## (Poly Haven, CC0), Fassaden mit Fensterraster, Kolonnaden, Fahnen mit Wind-Shader, Lichterketten.
## Alles statisch; Geometrie wird ueber einen Builder pro Material zu wenigen Meshes zusammengefasst.

const Geo = preload("res://game/levels/level_geo.gd")
const FK = preload("res://game/levels/facade_kit.gd")
const TEX := "res://assets/environment/berlin/textures/"
const EU_FLAG := "res://assets/environment/berlin/eu_flag.png"

static var _cache: Dictionary = {}

# --------------------------------------------------------------------------- Materialien

## PBR-Material (diffuse/normal/arm), triplanar in Weltkoordinaten. Kopie von Geo.mat mit eigenem Ordner.
static func mat(dir: String, tint: Color = Color.WHITE, scale: float = 0.3, rough_mul: float = 1.0, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [dir, tint.to_html(), scale, rough_mul, metallic]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + dir + "/diffuse.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX + dir + "/normal.jpg")
	m.roughness_texture = load(TEX + dir + "/arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough_mul
	m.ao_enabled = true
	m.ao_texture = load(TEX + dir + "/arm.jpg")
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metallic
	if metallic > 0.0:
		m.metallic_texture = load(TEX + dir + "/arm.jpg")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	_cache[key] = m
	return m

static func sandstone() -> StandardMaterial3D:
	return mat("large_sandstone_blocks", Color(0.8, 0.75, 0.68), 0.2)

static func facade() -> StandardMaterial3D:
	return mat("concrete_tile_facade", Color(0.72, 0.72, 0.74), 0.22)

static func granite() -> StandardMaterial3D:
	return mat("granite_tile", Color(0.5, 0.5, 0.52), 0.32, 0.75)

## Leicht nasser Asphalt: niedrige Rauheit -> Spiegelungen der Lichter (SSR).
static func asphalt() -> StandardMaterial3D:
	return mat("clean_asphalt", Color(0.42, 0.42, 0.44), 0.22, 0.5)

static func steel() -> StandardMaterial3D:
	return mat("metal_plate", Color(0.42, 0.43, 0.46), 0.5, 0.75, 0.8)

static func marble() -> StandardMaterial3D:
	return mat("marble_01", Color(0.86, 0.85, 0.82), 0.18, 0.7)

static func trim() -> StandardMaterial3D:
	return mat("large_sandstone_blocks", Color(0.62, 0.6, 0.56), 0.5)

static func glass() -> StandardMaterial3D:
	return Geo.flat(Color(0.025, 0.03, 0.035), 0.06, 0.7)

static func win_warm() -> StandardMaterial3D:
	return Geo.flat(Color(0.1, 0.08, 0.05), 0.4, 0.0, Color(1.0, 0.76, 0.46), 2.0)

static func win_cool() -> StandardMaterial3D:
	return Geo.flat(Color(0.06, 0.07, 0.09), 0.4, 0.0, Color(0.6, 0.74, 1.0), 1.5)

static func unshaded(c: Color) -> StandardMaterial3D:
	var key := "unsh|%s|%s|%s" % [c.r, c.g, c.b]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	_cache[key] = m
	return m

## Fassadenmaterial mit Facade-Shader (Triplanar, Detail-Normal, Sockelschmutz, Schlieren, leichte Naesse).
static func facade_shader(variant: String, tint: Color) -> ShaderMaterial:
	return FK.facade_mat(variant, tint, {"grime_amount": 0.4, "grime_height": 1.4, "streaks": 0.28, "wetness": 0.12, "variation": 0.14})

static func materials() -> Dictionary:
	return {
		"sandstone": facade_shader("sandstone", Color(0.8, 0.75, 0.68)), "facade": facade_shader("tile_facade", Color(0.72, 0.72, 0.74)), "granite": granite(), "asphalt": asphalt(),
		"steel": steel(), "marble": marble(), "trim": trim(), "glass": glass(),
		"win_warm": win_warm(), "win_cool": win_cool(),
		"dark": Geo.flat(Color(0.05, 0.05, 0.055), 0.6, 0.4),
		"black": Geo.flat(Color(0.015, 0.015, 0.018), 0.9),
		"red_light": unshaded(Color(3.0, 0.15, 0.1)),
		"canvas_red": Geo.flat(Color(0.55, 0.08, 0.07), 0.9),
		"canvas_white": Geo.flat(Color(0.8, 0.8, 0.78), 0.9),
		"wood": Geo.flat(Color(0.22, 0.15, 0.1), 0.85),
		"chair": Geo.flat(Color(0.75, 0.76, 0.78), 0.5, 0.3),
	}

# --------------------------------------------------------------------------- Builder

## Sammelt Boxen/Zylinder je Material-Schluessel; build() erzeugt pro Schluessel ein Mesh.
class Builder:
	const G = preload("res://game/levels/level_geo.gd")
	var batches: Dictionary = {}
	var mats: Dictionary = {}
	var no_shadow: Array = ["win_warm", "win_cool", "red_light"]
	var _cyl_cache: Dictionary = {}
	## Fenster-Kit (Rahmen, Sprossen, Baenke, Dachaufbauten) und Scheiben mit Interior Mapping
	var fk := FKit.Parts.new()
	var wins := FKit.WindowBatch.new()
	const FKit = preload("res://game/levels/facade_kit.gd")

	func _init(p_mats: Dictionary) -> void:
		mats = p_mats

	func _bb(key: String) -> G.BoxBatch:
		if not batches.has(key):
			batches[key] = G.BoxBatch.new()
		return batches[key]

	func box(key: String, c: Vector3, s: Vector3, rot: Basis = Basis.IDENTITY) -> void:
		_bb(key).add(c, s, rot)

	func ball(key: String, c: Vector3, s: Vector3) -> void:
		_bb(key).add_ball(c, s)

	func cyl(key: String, c: Vector3, r_top: float, r_bot: float, h: float, seg: int = 14, rot: Basis = Basis.IDENTITY) -> void:
		var ck := "%s|%s|%s|%s" % [r_top, r_bot, h, seg]
		if not _cyl_cache.has(ck):
			var cm := CylinderMesh.new()
			cm.top_radius = r_top
			cm.bottom_radius = r_bot
			cm.height = h
			cm.radial_segments = seg
			cm.rings = 1
			_cyl_cache[ck] = cm
		var bb := _bb(key)
		bb.st.append_from(_cyl_cache[ck], 0, Transform3D(rot, c))
		bb.count += 1

	func build(parent: Node3D) -> void:
		for k in batches:
			var mesh: ArrayMesh = (batches[k] as G.BoxBatch).build()
			if mesh == null:
				continue
			var mi := G.mesh_node(mesh, mats.get(k, G.flat(Color.MAGENTA)), Vector3.ZERO, not no_shadow.has(k))
			mi.name = "B_" + k
			parent.add_child(mi)
		batches.clear()
		if not fk.batches.is_empty():
			var fm := {
				"frame_dark": FKit.frame_mat(Color(0.05, 0.05, 0.055)),
				"frame_white": FKit.frame_mat(Color(0.62, 0.6, 0.56)),
				"sill": mats.get("trim", G.flat(Color(0.5, 0.5, 0.5))),
				"metal": FKit.metal_mat(Color(0.25, 0.26, 0.27)),
				"chimney": mats.get("dark", G.flat(Color(0.1, 0.1, 0.1))),
			}
			fk.build(parent, fm, [], {"frame_dark": 90.0, "frame_white": 90.0})
		var gl := wins.build_node(FKit.window_mat("night"))
		if gl != null:
			parent.add_child(gl)
			wins = FKit.WindowBatch.new()

# --------------------------------------------------------------------------- Gebaeude

## Gebaeudeblock mit Strassenfassade. side -1 = links (Fassade zeigt nach +x), +1 = rechts (nach -x).
## face_x: x der Fassade, z0 > z1 (Strecke laeuft nach -z). style = Material-Schluessel der Wand.
## opts: lit (Anteil beleuchteter Fenster), shop (Anteil beleuchteter Schaufenster), roof (Dachaufbau)
## Optik: Die Fassade ist eine 0,3 m starke Vorsatzschale mit echten Oeffnungen; Fenster sitzen in der
## Laibung (Rahmen, Sprossen, Bank, Glas mit Interior Mapping). Die Kollision bleibt die volle Box bis face_x.
const REVEAL := 0.3

static func block(bd: Builder, body: StaticBody3D, side: int, face_x: float, z0: float, z1: float, depth: float, h: float, style: String, rng: RandomNumberGenerator, opts: Dictionary = {}) -> void:
	var n := -float(side)
	var nv := Vector3(n, 0, 0)
	var cx := face_x - n * depth / 2.0
	var cz := (z0 + z1) / 2.0
	var L := absf(z0 - z1)
	# eigener RNG fuer die Optik, damit die Aufrufreihenfolge des Level-RNG gleich bleibt
	var vr := RandomNumberGenerator.new()
	vr.seed = hash(Vector3(face_x, z0, h))
	# Baukoerper (sichtbar hinter der Vorsatzschale); Kollision unveraendert bis face_x
	bd.box(style, Vector3(face_x - n * (REVEAL + (depth - REVEAL) / 2.0), h / 2.0, cz), Vector3(depth - REVEAL, h, L))
	Geo.add_box_shape(body, Vector3(cx, h / 2.0, cz), Vector3(depth, h, L))
	var sx := face_x - n * REVEAL / 2.0   # Mitte der Vorsatzschale
	var modern := style == "facade"
	var frame_key := "frame_dark" if modern else "frame_white"
	var win_style: String = (["t", "single"] if modern else ["cross", "t"])[vr.randi() % 2]
	# Sockel, Gesimse, Hauptgesims, Dachaufbau
	bd.box("granite", Vector3(face_x + n * 0.14, 0.3, cz), Vector3(0.3, 0.6, L))
	var floors := int((h - 6.0) / 3.6)
	bd.box("trim", Vector3(face_x + n * 0.2, 4.6, cz), Vector3(0.4, 0.35, L))
	for f in range(1, floors + 1):
		bd.box("trim", Vector3(face_x + n * 0.1, 5.0 + f * 3.6 - 0.3, cz), Vector3(0.2, 0.16, L))
	bd.box("trim", Vector3(face_x + n * 0.45, h - 0.45, cz), Vector3(0.9, 0.9, L + 0.4))
	if opts.get("roof", true):
		bd.box("dark", Vector3(cx - n * 2.0, h + 1.6, cz), Vector3(depth - 6.0, 3.2, L - 3.0))
		FK.roof(bd.fk, Vector3(face_x - n * 1.6, h, cz), nv, L - 2.0, 3.0, vr, {"cap": "sill", "chimney": "chimney", "metal": "metal"})
	var lit: float = opts.get("lit", 0.22)
	var shop: float = opts.get("shop", 0.4)
	var cols := maxi(int(L / 3.4), 2)
	var step := L / float(cols)
	var top_y := 5.0 + floors * 3.6
	for i in cols:
		var z := z0 - step * (float(i) + 0.5)
		if i > 0:
			bd.box("trim", Vector3(face_x + n * 0.09, (h + 4.6) / 2.0, z0 - step * i), Vector3(0.18, h - 5.2, 0.38))
		# Erdgeschoss: Schaufenster in der Oeffnung (0,6 .. 3,85 m)
		var sw := step * 0.74
		var lit_shop := rng.randf() < shop
		_shell_bay(bd, style, sx, z, step, 0.0, 5.0, sw, 0.6, 3.85)
		FK.window(bd.fk, bd.wins, Vector3(face_x, 2.225, z), nv, sw, 3.25, REVEAL - 0.04, "frame_dark", "sill", "shop", 0.55 if lit_shop else 0.0, vr.randf_range(0.55, 1.0), vr.randf(), false, false)
		bd.box("dark", Vector3(face_x + n * 0.1, 3.95, z), Vector3(0.16, 0.2, step * 0.8))
		for f in floors:
			var y := 5.0 + f * 3.6 + 1.25
			var r := rng.randf()
			var light := 0.0
			var warm := vr.randf_range(0.6, 1.0)
			if r < lit:
				light = vr.randf_range(0.6, 1.0)
			elif r < lit + 0.05:
				light = vr.randf_range(0.5, 0.9)
				warm = vr.randf_range(0.0, 0.25)
			var ww := step * 0.46
			_shell_bay(bd, style, sx, z, step, 5.0 + f * 3.6, 5.0 + (f + 1) * 3.6, ww, y - 0.975, y + 0.975)
			FK.window(bd.fk, bd.wins, Vector3(face_x, y, z), nv, ww, 1.95, REVEAL - 0.04, frame_key, "sill", win_style, light, warm, vr.randf(), false, true)
			bd.box("trim", Vector3(face_x + n * 0.07, y + 1.1, z), Vector3(0.14, 0.18, step * 0.54))
		# Attika ueber dem obersten Geschoss
		if h > top_y:
			bd.box(style, Vector3(sx, (top_y + h) / 2.0, z), Vector3(REVEAL, h - top_y, step))

## Vorsatzschale eines Fassadenfelds (Breite step um z, Hoehe y0..y1) mit einer Oeffnung
## (Breite ow, Unterkante oy0, Oberkante oy1): Pfeiler links/rechts, Bruestung, Sturz.
static func _shell_bay(bd: Builder, style: String, sx: float, z: float, step: float, y0: float, y1: float, ow: float, oy0: float, oy1: float) -> void:
	var pw := (step - ow) / 2.0
	for s: float in [-1.0, 1.0]:
		bd.box(style, Vector3(sx, (y0 + y1) / 2.0, z + s * (ow + pw) / 2.0), Vector3(REVEAL, y1 - y0, pw))
	if oy0 > y0 + 0.01:
		bd.box(style, Vector3(sx, (y0 + oy0) / 2.0, z), Vector3(REVEAL, oy0 - y0, ow))
	if y1 > oy1 + 0.01:
		bd.box(style, Vector3(sx, (oy1 + y1) / 2.0, z), Vector3(REVEAL, y1 - oy1, ow))

## Kolonnade vor einer Fassade (Regierungsbau): Saeulen mit Basis/Kapitell, Gebaelk. Mit Kollision.
static func colonnade(bd: Builder, body: StaticBody3D, side: int, face_x: float, z0: float, z1: float, col_h: float, out: float = 3.6) -> void:
	var n := -float(side)
	var x := face_x + n * out
	var L := absf(z0 - z1)
	var cnt := int(L / 4.4)
	var step := L / float(cnt)
	for i in cnt + 1:
		var z := z0 - step * i
		bd.box("marble", Vector3(x, 0.3, z), Vector3(1.7, 0.6, 1.7))
		bd.cyl("marble", Vector3(x, 0.6 + col_h / 2.0, z), 0.58, 0.68, col_h, 16)
		bd.box("marble", Vector3(x, 0.6 + col_h + 0.25, z), Vector3(1.6, 0.5, 1.6))
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.7
		sh.height = col_h + 1.0
		cs.shape = sh
		cs.position = Vector3(x, (col_h + 1.0) / 2.0, z)
		body.add_child(cs)
	var top := 0.6 + col_h + 0.5
	bd.box("sandstone", Vector3(face_x + n * (out / 2.0 + 0.4), top + 0.9, (z0 + z1) / 2.0), Vector3(out + 1.6, 1.8, L + 2.0))
	bd.box("trim", Vector3(face_x + n * (out + 1.15), top + 2.0, (z0 + z1) / 2.0), Vector3(0.5, 0.4, L + 2.4))
	# Decke der Halle leicht beleuchtet (Lichtband)
	bd.box("win_warm", Vector3(face_x + n * (out / 2.0), top - 0.02, (z0 + z1) / 2.0), Vector3(0.3, 0.04, L - 1.0))

# --------------------------------------------------------------------------- Fahnen

static var _flag_shader: Shader

static func _flag_mat(tex_path: String, phase: float) -> ShaderMaterial:
	if _flag_shader == null:
		_flag_shader = Shader.new()
		_flag_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float amp = 0.16;
uniform float phase = 0.0;
varying float shade;
void vertex() {
	float u = UV.x;
	float w = sin(u * 7.0 - TIME * 3.4 + phase);
	VERTEX.z += w * amp * u;
	VERTEX.y += sin(u * 4.0 - TIME * 2.2 + phase) * amp * 0.3 * u;
	shade = 0.82 + 0.18 * cos(u * 7.0 - TIME * 3.4 + phase);
}
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	ALBEDO = c * shade;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _flag_shader
	m.set_shader_parameter("tex", load(tex_path))
	m.set_shader_parameter("phase", phase)
	return m

## Fahnenmast mit wehender Fahne (Fahne zeigt in lokale +x-Richtung). Mast mit Kollision.
static func flag(parent: Node3D, pos: Vector3, yaw_deg: float, pole_h: float, size: Vector2, rng: RandomNumberGenerator, tex_path: String = EU_FLAG) -> Node3D:
	var b := Geo.static_body(pos, yaw_deg)
	b.add_child(Geo.cylinder_node(0.07, pole_h, steel(), Vector3(0, pole_h / 2.0, 0), Vector3.ZERO, 8))
	b.add_child(Geo.cylinder_node(0.12, 0.12, unshaded(Color(0.9, 0.75, 0.3)), Vector3(0, pole_h + 0.06, 0), Vector3.ZERO, 8))
	var q := QuadMesh.new()
	q.size = size
	q.subdivide_width = 18
	q.subdivide_depth = 4
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _flag_mat(tex_path, rng.randf() * TAU)
	mi.position = Vector3(size.x / 2.0 + 0.07, pole_h - size.y / 2.0 - 0.15, 0)
	b.add_child(mi)
	Geo.add_box_shape(b, Vector3(0, pole_h / 2.0, 0), Vector3(0.2, pole_h, 0.2))
	parent.add_child(b)
	return b

# --------------------------------------------------------------------------- Lichterketten

## Lichterkette zwischen a und b mit Durchhang. Gibt die MultiMeshInstance zurueck (zum Abschalten).
static func string_lights(parent: Node3D, a: Vector3, b: Vector3, sag: float, spacing: float, palette: Array, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var L := a.distance_to(b)
	var cnt := maxi(int(L / spacing), 2)
	var sm := SphereMesh.new()
	sm.radius = 0.075
	sm.height = 0.15
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	sm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sm
	mm.instance_count = cnt + 1
	var cable := Geo.batch()
	var prev := a
	for i in cnt + 1:
		var t := float(i) / float(cnt)
		var p := a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p + Vector3(0, -0.09, 0)))
		var c: Color = palette[rng.randi() % palette.size()]
		mm.set_instance_color(i, c * rng.randf_range(2.2, 3.4))
		if i > 0:
			var mid := (prev + p) / 2.0
			var d := p - prev
			var basis := Basis.looking_at(d.normalized(), Vector3.UP) if d.length() > 0.01 else Basis.IDENTITY
			cable.add(mid, Vector3(0.015, 0.015, d.length()), basis)
		prev = p
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	var cm := cable.build()
	if cm != null:
		mmi.add_child(Geo.mesh_node(cm, Geo.flat(Color(0.03, 0.03, 0.03), 0.8), Vector3.ZERO, false))
	return mmi

## Lichterkette dimmen/abschalten (z. B. Stromausfall nach der Explosion).
static func set_lights_level(mmi: MultiMeshInstance3D, k: float) -> void:
	if not is_instance_valid(mmi):
		return
	var mm := mmi.multimesh
	for i in mm.instance_count:
		var c := mm.get_instance_color(i)
		mm.set_instance_color(i, Color(c.r * k, c.g * k, c.b * k, 1.0))
