extends RefCounted
## Realismus-Requisiten aus Poly-Haven-Assets (CC0) fuer alle Level: Sandsaecke (eigenes Kissen-Mesh mit
## Poly-Haven-Jute "hessian_230", MultiMesh je Wall), Munitionskisten, bemooste Felsen, umgestuerzte
## Staemme, Baumstuempfe, Sturmlaternen, Gaslaternen, Betonbarrieren.
## Meshes werden einmal geladen und von allen Instanzen geteilt; snow >= 0 ersetzt die Materialien durch
## eine Variante mit Schneeauflage (snowy_uv.gdshader). Bereits vorhandene Modelle (river/rail/street)
## werden wiederverwendet statt doppelt abgelegt.

const SNOW_UV: Shader = preload("res://assets/environment/snowy_uv.gdshader")
const ENV_TEX := "res://assets/environment/textures/"
const HESSIAN := "res://assets/environment/props/textures/hessian_230/"

const MODELS := {
	"tree_stump_01": "res://assets/environment/props/models/tree_stump_01/tree_stump_01.gltf",
	"lantern_01": "res://assets/environment/props/models/Lantern_01/Lantern_01.gltf",
	"rock_moss_set_01": "res://assets/environment/river/models/rock_moss_set_01/rock_moss_set_01.gltf",
	"dead_tree_trunk": "res://assets/environment/river/models/dead_tree_trunk/dead_tree_trunk.gltf",
	"wooden_military_crate": "res://assets/environment/rail/models/wooden_military_crate/wooden_military_crate.gltf",
	"old_military_crate": "res://assets/environment/rail/models/old_military_crate/old_military_crate.gltf",
	"ammo_box": "res://assets/environment/rail/models/ammo_box/ammo_box.gltf",
	"street_lamp_01": "res://assets/environment/street/models/street_lamp_01/street_lamp_01.gltf",
	"concrete_road_barrier": "res://assets/environment/street/models/concrete_road_barrier/concrete_road_barrier.gltf",
}

## Gefuellter Sandsack (Breite x Hoehe x Laenge, m) und Lagenabstand.
const BAG := Vector3(0.47, 0.25, 0.64)
const BAG_PITCH := 0.215
const HESSIAN_TILE := 0.27      # Kantenlaenge der Jute-Textur in Metern (Poly-Haven-Angabe 268 mm)

static var _parts: Dictionary = {}
static var _mats: Dictionary = {}
static var _bag_mesh: ArrayMesh
static var _noise: NoiseTexture2D

# --------------------------------------------------------------------------- Modelle

## Mesh-Teile eines glTF-Modells: [{mesh, xf, name}] relativ zur Modellwurzel (einmal geladen).
static func parts(mname: String) -> Array:
	if _parts.has(mname):
		return _parts[mname]
	var out: Array = []
	var ps: PackedScene = load(MODELS[mname]) if MODELS.has(mname) else null
	if ps != null:
		var inst := ps.instantiate()
		_collect(inst, Transform3D.IDENTITY, out, true)
		inst.free()
	_parts[mname] = out
	return out

static func _collect(n: Node, xf: Transform3D, out: Array, is_root: bool) -> void:
	var t := xf
	if n is Node3D and not is_root:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append({"mesh": (n as MeshInstance3D).mesh, "xf": t, "name": str(n.name)})
	for c in n.get_children():
		_collect(c, t, out, false)

## Platziert ein Modell (geteilte Meshes) unter parent. only = Teilnamen-Filter (Teilstring), snow < 0 = Originalmaterial.
## vis > 0 begrenzt die Sichtweite (Fade), shadows schaltet den Schattenwurf.
static func place(parent: Node3D, mname: String, xf: Transform3D, snow: float = -1.0, opts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "PH_" + mname
	root.transform = xf
	var only: String = str(opts.get("only", ""))
	var vis: float = float(opts.get("vis", 0.0))
	var shadows: bool = bool(opts.get("shadows", true))
	var center: bool = bool(opts.get("center", false))
	for p: Dictionary in parts(mname):
		if only != "" and not str(p.name).contains(only):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.transform = Transform3D(Basis.IDENTITY, -(p.xf as Transform3D).origin) * p.xf if center else p.xf
		if snow >= 0.0:
			var m: Mesh = p.mesh
			for s in m.get_surface_count():
				var src := m.surface_get_material(s)
				var sm := snow_mat(src, snow)
				if sm != src:
					mi.set_surface_override_material(s, sm)
		if vis > 0.0:
			mi.visibility_range_end = vis
			mi.visibility_range_end_margin = 6.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	parent.add_child(root)
	return root

static func xform(pos: Vector3, yaw_deg: float = 0.0, scale: Vector3 = Vector3.ONE, tilt: Vector3 = Vector3.ZERO) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(tilt.x), deg_to_rad(yaw_deg), deg_to_rad(tilt.z))).scaled_local(scale)
	return Transform3D(b, pos)

# --------------------------------------------------------------------------- Schnee-Materialien

static func noise_tex() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012
		fn.fractal_octaves = 4
		fn.seed = 77
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = fn
	return _noise

static func _tex(path: String) -> Texture2D:
	var key := "tex|" + path
	if not _mats.has(key):
		_mats[key] = load(path)
	return _mats[key]

## Schneevariante eines StandardMaterial3D (glTF-Import: Albedo, Normal, ARM). Transparente oder
## unbekannte Materialien bleiben unveraendert.
static func snow_mat(src: Material, snow: float) -> Material:
	if not (src is StandardMaterial3D):
		return src
	var sm := src as StandardMaterial3D
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return src
	var key := "snow|%d|%.2f" % [sm.get_instance_id(), snow]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SNOW_UV
	m.set_shader_parameter("has_albedo", sm.albedo_texture != null)
	if sm.albedo_texture != null:
		m.set_shader_parameter("albedo_tex", sm.albedo_texture)
	m.set_shader_parameter("tint", sm.albedo_color)
	m.set_shader_parameter("has_normal", sm.normal_enabled and sm.normal_texture != null)
	if sm.normal_texture != null:
		m.set_shader_parameter("normal_tex", sm.normal_texture)
		m.set_shader_parameter("normal_depth", sm.normal_scale)
	var arm: Texture2D = sm.roughness_texture if sm.roughness_texture != null else sm.metallic_texture
	m.set_shader_parameter("has_arm", arm != null)
	if arm != null:
		m.set_shader_parameter("arm_tex", arm)
		m.set_shader_parameter("arm_has_ao", sm.ao_enabled and sm.ao_texture == arm)
		m.set_shader_parameter("rough_mul", sm.roughness)
		m.set_shader_parameter("metal_mul", sm.metallic)
	m.set_shader_parameter("uv_scale", Vector2(sm.uv1_scale.x, sm.uv1_scale.y))
	_snow_params(m, snow)
	_mats[key] = m
	return m

static func _snow_params(m: ShaderMaterial, snow: float) -> void:
	m.set_shader_parameter("snow_amount", snow)
	m.set_shader_parameter("snow_albedo", _tex(ENV_TEX + "snow_02/diffuse.jpg"))
	m.set_shader_parameter("snow_normal", _tex(ENV_TEX + "snow_02/normal.jpg"))
	m.set_shader_parameter("noise_tex", noise_tex())

# --------------------------------------------------------------------------- Sandsaecke

## Jute-Material der Sandsaecke; snow < 0 = ohne Schnee. Instanzfarbe (MultiMesh) variiert den Ton.
static func sandbag_mat(snow: float = -1.0, tint: Color = Color(0.86, 0.8, 0.68)) -> Material:
	var key := "bag|%.2f|%s" % [snow, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if snow < 0.0:
		var s := StandardMaterial3D.new()
		s.albedo_texture = _tex(HESSIAN + "diffuse.jpg")
		s.albedo_color = tint
		s.vertex_color_use_as_albedo = true
		s.normal_enabled = true
		s.normal_texture = _tex(HESSIAN + "normal.jpg")
		s.normal_scale = 1.4
		s.roughness_texture = _tex(HESSIAN + "arm.jpg")
		s.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		s.ao_enabled = true
		s.ao_texture = _tex(HESSIAN + "arm.jpg")
		s.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		s.ao_light_affect = 0.4
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m = s
	else:
		var sh := ShaderMaterial.new()
		sh.shader = SNOW_UV
		sh.set_shader_parameter("albedo_tex", _tex(HESSIAN + "diffuse.jpg"))
		sh.set_shader_parameter("normal_tex", _tex(HESSIAN + "normal.jpg"))
		sh.set_shader_parameter("arm_tex", _tex(HESSIAN + "arm.jpg"))
		sh.set_shader_parameter("tint", tint)
		sh.set_shader_parameter("normal_depth", 1.4)
		sh.set_shader_parameter("metal_mul", 0.0)
		_snow_params(sh, snow)
		m = sh
	_mats[key] = m
	return m

## Kissenfoermiger, gefuellter Sack (Ursprung = Mitte). Wuerfelkugel-Parametrisierung mit kastenartigem
## Grundriss, zu den Enden hin flacher (abgebundene Enden), leicht durchhaengender Oberseite.
static func sandbag_mesh() -> ArrayMesh:
	if _bag_mesh != null:
		return _bag_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const N := 7
	var faces: Array = [
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.BACK, Vector3.RIGHT],
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.UP, Vector3.BACK],
		[Vector3.BACK, Vector3.UP, Vector3.RIGHT], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	var base := 0
	for f: Array in faces:
		var fn: Vector3 = f[0]
		var fu: Vector3 = f[1]
		var fv: Vector3 = f[2]
		for j in N + 1:
			for i in N + 1:
				var a := -1.0 + 2.0 * i / N
				var b := -1.0 + 2.0 * j / N
				var p := _bag_point(fn + fu * a + fv * b)
				var e := 0.02
				var pa := _bag_point(fn + fu * (a + e) + fv * b) - _bag_point(fn + fu * (a - e) + fv * b)
				var pb := _bag_point(fn + fu * a + fv * (b + e)) - _bag_point(fn + fu * a + fv * (b - e))
				var n := pa.cross(pb).normalized()
				if n.dot(p) < 0.0:
					n = -n
				var uv: Vector2
				if absf(fn.y) > 0.5:
					uv = Vector2(p.z, p.x)
				elif absf(fn.x) > 0.5:
					uv = Vector2(p.z, p.y)
				else:
					uv = Vector2(p.x, p.y)
				st.set_normal(n)
				st.set_uv(uv / HESSIAN_TILE + Vector2(fn.x, fn.z) * 0.37)
				st.set_color(Color.WHITE)
				st.add_vertex(p)
		for j in N:
			for i in N:
				var v0 := base + j * (N + 1) + i
				var v1 := v0 + 1
				var v2 := v0 + N + 1
				var v3 := v2 + 1
				# Umlaufsinn so, dass die Flaeche nach aussen zeigt (fu x fv = fn)
				if fu.cross(fv).dot(fn) > 0.0:
					st.add_index(v0); st.add_index(v2); st.add_index(v1)
					st.add_index(v1); st.add_index(v2); st.add_index(v3)
				else:
					st.add_index(v0); st.add_index(v1); st.add_index(v2)
					st.add_index(v1); st.add_index(v3); st.add_index(v2)
		base += (N + 1) * (N + 1)
	st.generate_tangents()
	_bag_mesh = st.commit()
	return _bag_mesh

static func _bag_point(c: Vector3) -> Vector3:
	var d := c.normalized()
	var sx := signf(d.x) * pow(absf(d.x), 0.5)
	var sy := signf(d.y) * pow(absf(d.y), 0.75)
	var sz := signf(d.z) * pow(absf(d.z), 0.42)
	sx = clampf(sx, -1.0, 1.0)
	sz = clampf(sz, -1.0, 1.0)
	# Dicke nimmt zu den abgebundenen Enden und zu den Seitennaehten hin ab
	var thick := (1.0 - 0.62 * pow(absf(sz), 5.0)) * (1.0 - 0.3 * pow(absf(sx), 4.0))
	var y := sy * thick
	if y < 0.0:
		y *= 0.82          # Unterseite flach gedrueckt
	else:
		y *= 1.0 - 0.12 * (1.0 - absf(sx)) * (1.0 - absf(sz))   # Oberseite leicht eingesunken
	var x := sx * (1.0 - 0.14 * pow(absf(sz), 4.0))
	# leichte Beulen (Sandfuellung)
	y += 0.05 * sin(sz * 5.3 + 0.8) * cos(sx * 3.1) * maxf(sy, 0.0)
	x += 0.03 * sin(sz * 4.1 + sy * 2.0)
	return Vector3(x * BAG.x * 0.5, y * BAG.y * 0.5, sz * BAG.z * 0.5)

## Sandsackwall entlang der lokalen z-Achse (Laenge length, Mitte = Ursprung von parent), rows = Reihen
## nebeneinander (Wanddicke). Ein MultiMesh je Wall. Oberkante ~ 0.12 + layers * BAG_PITCH.
static func sandbag_wall(parent: Node3D, length: float, layers: int, rng: RandomNumberGenerator, snow: float = -1.0, rows: int = 2, offset: Vector3 = Vector3.ZERO) -> MultiMeshInstance3D:
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var n := maxi(2, roundi((length - 0.04) / (BAG.z * 0.98)))
	var step := (length - BAG.z) / maxf(n - 1, 1)
	for layer in layers:
		var stagger := layer % 2 == 1
		var cnt := n - 1 if stagger else n
		for i in cnt:
			var z := -length / 2.0 + BAG.z * 0.5 + i * step + (step * 0.5 if stagger else 0.0)
			for r in rows:
				var x := (r - (rows - 1) * 0.5) * (BAG.x * 0.97) + rng.randf_range(-0.025, 0.025)
				var y := BAG.y * 0.5 * 0.86 + layer * BAG_PITCH + rng.randf_range(-0.01, 0.01)
				var sc := Vector3(rng.randf_range(0.94, 1.05), rng.randf_range(0.9, 1.08), rng.randf_range(0.95, 1.04))
				var basis := Basis.from_euler(Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.09, 0.09), rng.randf_range(-0.06, 0.06)))
				if rng.randf() < 0.5:
					basis = basis * Basis(Vector3.UP, PI)   # abgebundenes Ende mal links, mal rechts
				xfs.append(Transform3D(basis.scaled_local(sc), offset + Vector3(x, y, z + rng.randf_range(-0.03, 0.03))))
				var v := rng.randf_range(0.78, 1.06)
				var g := rng.randf_range(-0.04, 0.04)
				cols.append(Color(v + g, v, v - g * 1.5))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sandbag_mesh()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sandbags"
	mmi.multimesh = mm
	mmi.material_override = sandbag_mat(snow)
	parent.add_child(mmi)
	return mmi

## Oberkante eines Walls mit `layers` Lagen.
static func wall_height(layers: int) -> float:
	return BAG.y * 0.86 + (layers - 1) * BAG_PITCH + BAG.y * 0.5

# --------------------------------------------------------------------------- Kisten

## Stapel Munitionskisten (Holz, Poly Haven), Grundflaeche ~2,5 x 0,55 m: zwei unten, eine oben,
## optional eine Metall-Munitionsbox obenauf.
static func crate_stack(parent: Node3D, rng: RandomNumberGenerator, snow: float = -1.0) -> void:
	var count := rng.randi_range(2, 3)
	for i in 2:
		place(parent, "wooden_military_crate", xform(Vector3((i - 0.5) * 1.27, 0.0, rng.randf_range(-0.05, 0.05)), rng.randf_range(-4.0, 4.0) + (180.0 if rng.randf() < 0.5 else 0.0)), snow)
	if count == 3:
		place(parent, "wooden_military_crate", xform(Vector3(rng.randf_range(-0.45, 0.45), 0.47, rng.randf_range(-0.04, 0.04)), rng.randf_range(-12.0, 12.0)), snow)
	else:
		for k in 2:
			place(parent, "ammo_box", xform(Vector3(rng.randf_range(-0.9, -0.3) + k * 1.1, 0.47, rng.randf_range(-0.1, 0.1)), rng.randf_range(0.0, 360.0)), snow)
