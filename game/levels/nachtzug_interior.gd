extends RefCounted
## Innenausstattung der Nachtzug-Waggons (nur Optik, KEINE Kollision – die bleibt in nachtzug_world).
## PBR-Materialien (Poly Haven CC0: Sapele-Furnier, Jacquard-Moquette, Teppich, Kirschholz lackiert,
## Velours), gepolsterte Sitze als abgerundete Kissen statt Quader, Tische mit Kante, Gepaeckablagen
## aus Rohr, Leselampen, Vorhaenge, Schilder (erfundene Schriftzuege, tools/gen_train_signs.py) und
## Schmutz-Decals. Alles in wenigen Batches je Material (ein Draw-Call pro Material und Waggon).

const Geo := preload("res://game/levels/level_geo.gd")
const TEX := "res://assets/environment/train/textures/"
const SIGNS := "res://assets/environment/train/signs/"
const DECALS := "res://assets/environment/villa/decals/"
const ART := "res://assets/environment/villa/art/"

static var _mats: Dictionary = {}

## PBR-Material aus <dir>/diffuse|normal|arm.jpg, Weltraum-triplanar (der Zug steht im Ursprung).
static func pbr(dir: String, tint: Color, scale: float, rough_mul: float = 1.0, metal: float = 0.0, normal_k: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [dir, tint.to_html(), scale, rough_mul, normal_k]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + "/diffuse.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "/normal.jpg")
	m.normal_scale = normal_k
	m.roughness_texture = load(dir + "/arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough_mul
	m.ao_enabled = true
	m.ao_texture = load(dir + "/arm.jpg")
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m

static func mats() -> Dictionary:
	var d := {}
	d["veneer"] = pbr(TEX + "sapele_veneer", Color(0.6, 0.5, 0.43), 0.9, 0.9)
	d["veneer_dark"] = pbr(TEX + "sapele_veneer", Color(0.36, 0.28, 0.24), 0.9, 0.9)
	d["cherry"] = pbr(TEX + "lacquered_cherry_wood", Color(0.85, 0.7, 0.6), 1.4, 1.0)
	d["moquette"] = pbr(TEX + "quatrefoil_jacquard_fabric", Color(0.62, 0.48, 0.5), 2.6, 1.0, 0.0, 1.2)
	d["carpet"] = pbr(TEX + "dirty_carpet", Color(0.62, 0.36, 0.3), 1.3, 1.0)
	d["curtain"] = pbr(TEX + "velour_velvet", Color(0.62, 0.42, 0.36), 2.0, 1.0)
	d["curtain"].cull_mode = BaseMaterial3D.CULL_DISABLED
	d["linen"] = Geo.flat(Color(0.86, 0.84, 0.79), 0.9)
	d["linen"].cull_mode = BaseMaterial3D.CULL_DISABLED
	d["panel"] = pbr("res://assets/environment/villa/beige_wall_001", Color(0.93, 0.9, 0.84), 0.6, 0.55, 0.0, 0.35)
	d["planks"] = pbr("res://assets/environment/textures/weathered_planks", Color(0.7, 0.62, 0.55), 0.7, 1.0)
	d["cargo_wall"] = pbr("res://assets/environment/rail/textures/rusty_painted_metal", Color(0.55, 0.6, 0.56), 0.5, 1.0)
	d["chrome"] = Geo.flat(Color(0.75, 0.76, 0.78), 0.22, 0.95)
	d["alu"] = Geo.flat(Color(0.6, 0.61, 0.62), 0.38, 0.85)
	d["brass"] = Geo.flat(Color(0.72, 0.55, 0.3), 0.32, 0.9)
	d["black"] = Geo.flat(Color(0.04, 0.04, 0.045), 0.6)
	d["rubber"] = Geo.flat(Color(0.05, 0.05, 0.05), 0.9)
	d["porcelain"] = Geo.flat(Color(0.93, 0.93, 0.9), 0.15)
	d["shade"] = Geo.flat(Color(1.0, 0.86, 0.66), 0.7, 0.0, Color(1.0, 0.78, 0.5), 1.1)
	d["bulb"] = Geo.flat(Color(1.0, 0.9, 0.75), 0.4, 0.0, Color(1.0, 0.85, 0.6), 2.0)
	d["case"] = Geo.flat(Color(0.2, 0.14, 0.1), 0.55)
	d["case2"] = Geo.flat(Color(0.12, 0.17, 0.22), 0.45, 0.1)
	d["mattress"] = pbr(TEX + "quatrefoil_jacquard_fabric", Color(0.55, 0.58, 0.62), 3.2, 1.0, 0.0, 0.6)
	d["blanket"] = pbr(TEX + "velour_velvet", Color(0.36, 0.2, 0.18), 2.4, 1.0)
	d["glass_bottle"] = Geo.flat(Color(0.12, 0.22, 0.12), 0.1, 0.2)
	return d

# ------------------------------------------------------------------ abgerundete Kisten

## Sammelt abgerundete Quader (Kantenradius r) in EIN Mesh. Normalen weich ueber die Rundung.
class RBatch:
	var st := SurfaceTool.new()
	var count: int = 0
	var _nv: int = 0
	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## Quader mit Mitte c, Groesse s, Kantenradius r; n Unterteilungen je Viertelrundung.
	func add(c: Vector3, s: Vector3, r: float, rot: Basis = Basis.IDENTITY, n: int = 3) -> void:
		var h := s * 0.5
		r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.98)
		var inner := h - Vector3.ONE * r
		var axes: Array = []
		for ax in 3:
			var arr := PackedFloat32Array()
			for k in range(n, -1, -1):
				arr.append(-inner[ax] - r * tan(PI * 0.25 * float(k) / n))
			for k in range(0, n + 1):
				arr.append(inner[ax] + r * tan(PI * 0.25 * float(k) / n))
			axes.append(arr)
		for a in 3:
			var u := (a + 1) % 3
			var v := (a + 2) % 3
			var au: PackedFloat32Array = axes[u]
			var av: PackedFloat32Array = axes[v]
			for sg: float in [-1.0, 1.0]:
				var base := _nv
				for iu in au.size():
					for iv in av.size():
						var p := Vector3.ZERO
						p[a] = sg * h[a]
						p[u] = au[iu]
						p[v] = av[iv]
						var q := p.clamp(-inner, inner)
						var nrm := (p - q).normalized()
						st.set_normal(rot * nrm)
						st.add_vertex(c + rot * (q + nrm * r))
						_nv += 1
				var nv := av.size()
				for iu in au.size() - 1:
					for iv in nv - 1:
						var i0 := base + iu * nv + iv
						var i1 := i0 + 1
						var i2 := i0 + nv + 1
						var i3 := i0 + nv
						# Front im Uhrzeigersinn (Godot): Kreuzprodukt zeigt nach innen
						var flip := sg > 0.0
						if flip:
							st.add_index(i0); st.add_index(i1); st.add_index(i2)
							st.add_index(i0); st.add_index(i2); st.add_index(i3)
						else:
							st.add_index(i0); st.add_index(i2); st.add_index(i1)
							st.add_index(i0); st.add_index(i3); st.add_index(i2)
		count += 1
	## Vorhang als gefaltete Bahn: senkrecht, Ebene x = const, von z0 bis z1, y0..y1, Falten nach innen (dir).
	func curtain(x: float, dir: float, y0: float, y1: float, z0: float, z1: float, folds: float, depth: float) -> void:
		var segs := int(maxf(8.0, absf(z1 - z0) * 40.0))
		var rows := 4
		var base := _nv
		for i in segs + 1:
			var t := float(i) / segs
			var z := lerpf(z0, z1, t)
			var ph := t * folds * TAU
			var off := (0.5 - 0.5 * cos(ph)) * depth
			var dz := (z1 - z0)
			var slope := 0.5 * sin(ph) * depth * folds * TAU / dz if absf(dz) > 0.001 else 0.0
			var nrm := Vector3(dir, 0.0, -slope * dir).normalized()
			for j in rows + 1:
				var y := lerpf(y0, y1, float(j) / rows)
				# unten leicht nach innen gebauscht
				var bulge := (1.0 - float(j) / rows) * depth * 0.25
				st.set_normal(nrm)
				st.add_vertex(Vector3(x + dir * (off + bulge), y, z))
				_nv += 1
		for i in segs:
			for j in rows:
				var a := base + i * (rows + 1) + j
				var b := a + rows + 1
				st.add_index(a); st.add_index(b); st.add_index(a + 1)
				st.add_index(a + 1); st.add_index(b); st.add_index(b + 1)
		count += 1
	func build() -> ArrayMesh:
		if count == 0:
			return null
		return st.commit()

## Haengt ein Mesh mit Material an parent.
static func put(parent: Node3D, mesh: Mesh, m: Material, shadows: bool = true) -> MeshInstance3D:
	if mesh == null:
		return null
	var mi := Geo.mesh_node(mesh, m, Vector3.ZERO, shadows)
	parent.add_child(mi)
	return mi

static func surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# ------------------------------------------------------------------ Schilder, Decals

static var _tex: Dictionary = {}

static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]

static func _sign_mat(file: String, unshaded_glow: float = 0.0) -> StandardMaterial3D:
	var key := "sign|" + file
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(SIGNS + file)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.roughness = 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if unshaded_glow > 0.0:
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = unshaded_glow
	_mats[key] = m
	return m

static func _art_mat(file: String) -> StandardMaterial3D:
	var key := "art|" + file
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(ART + file)
	m.roughness = 0.35
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m

## Flaches Schild an einer Wand. normal: Blickrichtung der Vorderseite (+-X oder +-Z).
static func wall_sign(parent: Node3D, file: String, pos: Vector3, size: Vector2, normal: Vector3) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _sign_mat(file)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos + normal * 0.004
	# QuadMesh zeigt nach +Z
	mi.basis = Basis.looking_at(-normal, Vector3.UP)
	return mi

## Gerahmtes Bild (Landschaftsfoto) an einer Wand.
static func picture(parent: Node3D, file: String, pos: Vector3, size: Vector2, normal: Vector3, frame_m: Material) -> void:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _art_mat(file)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos + normal * 0.012
	mi.basis = Basis.looking_at(-normal, Vector3.UP)
	var fr := RBatch.new()
	var side := Vector3.UP.cross(normal).normalized()
	var t := 0.03
	for sy: float in [-1.0, 1.0]:
		fr.add(pos + Vector3.UP * sy * (size.y * 0.5 + t * 0.5) + normal * 0.012, (side.abs() * (size.x + t * 2.0) + Vector3.UP * t + normal.abs() * 0.024), 0.008)
	for sx: float in [-1.0, 1.0]:
		fr.add(pos + side * sx * (size.x * 0.5 + t * 0.5) + normal * 0.012, (side.abs() * t + Vector3.UP * size.y + normal.abs() * 0.024), 0.008)
	put(parent, fr.build(), frame_m, false)

## Projizierte Schmutz-/Abnutzungs-Decal. up: Projektionsachse (Decal projiziert entlang -Y lokal).
static func decal(parent: Node3D, file: String, pos: Vector3, size: Vector3, b: Basis, alpha: float = 0.8, tint: Color = Color.WHITE) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex(DECALS + file)
	d.size = size
	d.modulate = Color(tint.r, tint.g, tint.b, alpha)
	d.albedo_mix = 1.0
	d.cull_mask = 1
	d.distance_fade_enabled = true
	d.distance_fade_begin = 22.0
	d.distance_fade_length = 6.0
	parent.add_child(d)
	d.position = pos
	d.basis = b
	return d
