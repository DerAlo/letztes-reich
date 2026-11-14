extends RefCounted
## Nachtzug, Speisewagen: Tischdeko statt Kastenformen.
## Teller, Tassen, Untertassen aus Poly Haven "tea_set_01", Weinflaschen aus "wine_bottles_01" (beide CC0,
## assets/environment/train/models/), Weinglaeser, Tischlampen (Messingfuss, Stoffschirm) und Besteck als
## gedrehte Profile (Lathe). Alles als MultiMesh je Teil, ohne Kollision und ohne Schattenwurf.
## Aufruf: add(sx, z, floor_y) je Tisch, danach flush(parent).

const MOD := "res://assets/environment/train/models/"
const TEA := MOD + "tea_set_01/tea_set_01.gltf"
const WINE := MOD + "wine_bottles_01/wine_bottles_01.gltf"
const TOP := 0.769          ## Oberkante Tischdecke ueber dem Wagenboden
const SEG := 20             ## Segmente der Drehkoerper

static var _cache: Dictionary = {}     ## Schluessel -> Mesh

var _xf: Dictionary = {}               ## Schluessel -> Array[Transform3D]
var _mats: Dictionary
var _rng := RandomNumberGenerator.new()

func _init(mats: Dictionary, seed_v: int) -> void:
	_mats = mats
	_rng.seed = seed_v

## Ein Tisch: Mitte (sx, z), Fensterseite in Richtung sign(sx). Plaetze bei z +- 0.24.
func add(sx: float, z: float, floor_y: float) -> void:
	var s := signf(sx)
	var y := floor_y + TOP
	# Tischlampe am Fenster
	_put("lamp", Vector3(sx + s * 0.27, y, z), 0.0)
	# Weinflasche auf jedem zweiten Tisch, neben der Lampe
	if _rng.randf() < 0.55:
		var b: String = ["bordeaux", "burgundy", "alsace"][_rng.randi() % 3]
		_put("wine/" + b, Vector3(sx + s * 0.26, y, z + (0.27 if _rng.randf() < 0.5 else -0.27)), _rng.randf() * TAU)
	for side: float in [1.0, -1.0]:
		var pz := z + side * 0.24
		var px := sx - s * 0.06
		var used := _rng.randf()
		if used < 0.15:
			continue                                # freier Platz: nur Gedeck fehlt
		_put("tea/tea_set_01_plate_large_circular_03", Vector3(px, y, pz), _rng.randf() * TAU)
		# Besteck links/rechts vom Teller (Gast schaut nach -side in z)
		for k: float in [-1.0, 1.0]:
			_put("knife" if k * side > 0.0 else "fork", Vector3(px + k * 0.125, y + 0.003, pz), 0.0)
		if used < 0.6:
			_put("wineglass", Vector3(sx + s * 0.13, y, z + side * 0.1), 0.0)
			if _rng.randf() < 0.7:
				_put("wine_fill", Vector3(sx + s * 0.13, y, z + side * 0.1), 0.0)
		else:
			# Kaffee: Untertasse + Tasse
			var cp := Vector3(sx + s * 0.15, y, z + side * 0.16)
			_put("tea/tea_set_01_saucer_circular_03", cp, 0.0)
			_put("tea/tea_set_01_cup_small_01", cp + Vector3(0, 0.012, 0), _rng.randf() * TAU)

func _put(key: String, p: Vector3, yaw: float) -> void:
	if not _xf.has(key):
		_xf[key] = []
	(_xf[key] as Array).append(Transform3D(Basis(Vector3.UP, yaw), p))

func flush(parent: Node3D) -> void:
	for key: String in _xf:
		var mesh := _mesh(key)
		if mesh == null:
			continue
		var list: Array = _xf[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Deko_" + key.get_file()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 40.0
		parent.add_child(mmi)
	_xf.clear()

# --------------------------------------------------------------------------- Meshes

func _mesh(key: String) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var m: Mesh = null
	if key.begins_with("tea/"):
		m = _gltf_mesh(TEA, key.trim_prefix("tea/"))
	elif key.begins_with("wine/"):
		m = _gltf_mesh(WINE, "wine_bottles_01_" + key.trim_prefix("wine/"))
	else:
		match key:
			"lamp":
				m = _lamp()
			"wineglass":
				m = _lathe([Vector2(0.032, 0.0), Vector2(0.03, 0.004), Vector2(0.005, 0.008), Vector2(0.004, 0.085),
					Vector2(0.012, 0.095), Vector2(0.034, 0.13), Vector2(0.036, 0.16), Vector2(0.031, 0.19)], _glass(), false)
			"wine_fill":
				m = _lathe([Vector2(0.0, 0.097), Vector2(0.012, 0.098), Vector2(0.03, 0.125), Vector2(0.0, 0.125)], _wine(), true)
			"knife":
				m = _box(Vector3(0.016, 0.003, 0.2), _mats.get("chrome"))
			"fork":
				m = _box(Vector3(0.02, 0.003, 0.18), _mats.get("chrome"))
	_cache[key] = m
	return m

func _gltf_mesh(path: String, node_name: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var root := ps.instantiate()
	var mi := root.find_child(node_name, true, false) as MeshInstance3D
	var m: Mesh = mi.mesh if mi != null else null
	root.free()
	return m

## Tischlampe: Messingfuss + Stiel (Lathe), Stoffschirm als Kegelstumpf (leuchtend, beidseitig).
func _lamp() -> Mesh:
	var am := ArrayMesh.new()
	_lathe_into(am, [Vector2(0.0, 0.0), Vector2(0.058, 0.0), Vector2(0.06, 0.006), Vector2(0.05, 0.018), Vector2(0.02, 0.026),
		Vector2(0.011, 0.034), Vector2(0.009, 0.2), Vector2(0.016, 0.205), Vector2(0.016, 0.215), Vector2(0.0, 0.215)], _mats.get("brass"))
	_lathe_into(am, [Vector2(0.088, 0.17), Vector2(0.086, 0.175), Vector2(0.055, 0.29), Vector2(0.053, 0.292)], _shade())
	# Gluehbirne im Schirm
	_lathe_into(am, [Vector2(0.0, 0.215), Vector2(0.018, 0.225), Vector2(0.02, 0.24), Vector2(0.012, 0.255), Vector2(0.0, 0.258)], _bulb())
	return am

func _lathe(profile: Array, mat: Material, close_top: bool) -> Mesh:
	var am := ArrayMesh.new()
	var pr := profile.duplicate()
	if close_top:
		pr.append(Vector2(0.0, (profile[profile.size() - 1] as Vector2).y))
	_lathe_into(am, pr, mat)
	return am

func _lathe_into(am: ArrayMesh, profile: Array, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in range(profile.size() - 1):
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for k in SEG:
			var t0 := TAU * float(k) / SEG
			var t1 := TAU * float(k + 1) / SEG
			var p00 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			var u0 := float(k) / SEG
			var u1 := float(k + 1) / SEG
			st.set_uv(Vector2(u0, a.y)); st.add_vertex(p00)
			st.set_uv(Vector2(u0, b.y)); st.add_vertex(p10)
			st.set_uv(Vector2(u1, a.y)); st.add_vertex(p01)
			st.set_uv(Vector2(u1, a.y)); st.add_vertex(p01)
			st.set_uv(Vector2(u0, b.y)); st.add_vertex(p10)
			st.set_uv(Vector2(u1, b.y)); st.add_vertex(p11)
	st.generate_normals()
	st.set_material(mat)
	st.commit(am)

func _box(size: Vector3, mat: Material) -> Mesh:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	return bm

func _glass() -> Material:
	if _cache.has("_m_glass"):
		return _cache["_m_glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.9, 0.95, 0.16)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic_specular = 1.0
	m.rim_enabled = true
	m.rim = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["_m_glass"] = m
	return m

func _shade() -> Material:
	if _cache.has("_m_shade"):
		return _cache["_m_shade"]
	var m := StandardMaterial3D.new()
	var src := _mats.get("shade") as BaseMaterial3D
	if src != null:
		m = src.duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["_m_shade"] = m
	return m

func _wine() -> Material:
	if _cache.has("_m_wine"):
		return _cache["_m_wine"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.02, 0.05, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["_m_wine"] = m
	return m

func _bulb() -> Material:
	if _cache.has("_m_bulb"):
		return _cache["_m_bulb"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.9, 0.7)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.78, 0.5)
	m.emission_energy_multiplier = 2.5
	_cache["_m_bulb"] = m
	return m
