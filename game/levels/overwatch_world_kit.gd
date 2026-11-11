extends RefCounted
## Bausatz fuer Level 7 "Kaltes Auge" (overwatch): Materialien, Primitive (Traeger, Rohre, Drehkoerper),
## Gelaender, Treppenlaeufe mit Rampen-Kollision, Fachwerk, Leitern und Dampffahnen.
## Alle Funktionen statisch, per preload() einbinden.

const Geo = preload("res://game/levels/level_geo.gd")
const RailProps = preload("res://game/levels/rail_props.gd")
const VfxLib = preload("res://game/vfx/vfx_lib.gd")

const RAIL_TEX := "res://assets/environment/rail/textures/"
const RIVER_TEX := "res://assets/environment/river/textures/"
const STREET_TEX := "res://assets/environment/street/textures/"
const BERLIN_TEX := "res://assets/environment/berlin/textures/"
const BASE_TEX := "res://assets/textures/"

const RISER := 0.1834        ## Stufenhoehe (4.4 m / 24)
const RUN := 0.305           ## Auftritt -> 31.0 Grad
const RAIL_H := 1.1          ## Gelaenderhoehe

static var _cache: Dictionary = {}

# ------------------------------------------------------------------ Materialien

## PBR-Material aus einem beliebigen Texturordner (diffuse/normal/arm), triplanar in Weltkoordinaten.
static func pbr(dir: String, tint: Color = Color.WHITE, scale: float = 0.3, rough_mul: float = 1.0, metallic: float = 0.0, two_sided: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s|%s" % [dir, tint.to_html(), scale, rough_mul, metallic, two_sided]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + "/diffuse.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "/normal.jpg")
	m.roughness_texture = load(dir + "/arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough_mul
	m.ao_enabled = true
	m.ao_texture = load(dir + "/arm.jpg")
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metallic
	if metallic > 0.0:
		m.metallic_texture = load(dir + "/arm.jpg")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m

## Bodenmaterial: wenig Spiegelanteil, damit Schotter/Matsch im Gegenlicht nicht glitzert.
static func matte(m: StandardMaterial3D) -> StandardMaterial3D:
	m.metallic_specular = 0.08
	m.normal_scale = 0.45   # flachere Normalen: kein Funkeln/Rauschen auf Distanz
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func rust(tint: Color = Color(0.62, 0.5, 0.42)) -> StandardMaterial3D:
	return pbr(RAIL_TEX + "rust_coarse_01", tint, 0.35, 1.0)

static func dark_steel() -> StandardMaterial3D:
	return pbr(RAIL_TEX + "rust_coarse_01", Color(0.22, 0.2, 0.19), 0.45, 1.0)

static func paint(c: Color) -> StandardMaterial3D:
	return pbr(RAIL_TEX + "rusty_painted_metal", c, 0.3, 1.0)

static func green_rust(c: Color = Color(0.72, 0.78, 0.72)) -> StandardMaterial3D:
	return pbr(RIVER_TEX + "green_metal_rust", c, 0.18, 1.0)

static func corr(c: Color = Color(0.7, 0.62, 0.56)) -> StandardMaterial3D:
	return pbr(RAIL_TEX + "rusty_corrugated_iron", c, 0.32, 1.0)

static func worn_corr(c: Color = Color(0.72, 0.72, 0.7)) -> StandardMaterial3D:
	return pbr(RAIL_TEX + "worn_corrugated_iron", c, 0.3, 1.0)

static func concrete(c: Color = Color(0.72, 0.7, 0.67)) -> StandardMaterial3D:
	return pbr(RIVER_TEX + "rough_concrete", c, 0.12, 1.0)

static func concrete_floor(c: Color = Color(0.7, 0.68, 0.65)) -> StandardMaterial3D:
	return matte(pbr(RAIL_TEX + "damaged_concrete_floor_02", c, 0.12, 1.0))

static func tower_concrete() -> StandardMaterial3D:
	return pbr(BASE_TEX + "concrete_wall_008", Color(0.74, 0.72, 0.7), 0.05, 1.0, 0.0, false)

static func factory_wall(c: Color = Color(0.8, 0.76, 0.72)) -> StandardMaterial3D:
	return pbr(RAIL_TEX + "factory_wall", c, 0.12, 1.0)

static func brick(c: Color = Color(0.78, 0.66, 0.6)) -> StandardMaterial3D:
	return pbr(RIVER_TEX + "factory_brick", c, 0.25, 1.0)

static func grating() -> StandardMaterial3D:
	return pbr(BERLIN_TEX + "metal_plate", Color(0.42, 0.4, 0.38), 0.6, 0.9, 0.3)

static func asphalt() -> StandardMaterial3D:
	return matte(pbr(STREET_TEX + "worn_asphalt", Color(0.66, 0.66, 0.66), 0.12, 1.0))

static func gravel(c: Color = Color(0.6, 0.56, 0.52)) -> StandardMaterial3D:
	return matte(pbr(RAIL_TEX + "gravel_road", c, 0.12, 1.0))

static func stones(c: Color = Color(0.55, 0.52, 0.5)) -> StandardMaterial3D:
	return matte(pbr(RAIL_TEX + "gravel_stones", c, 0.4, 1.0))

static func mud(c: Color = Color(0.5, 0.45, 0.4)) -> StandardMaterial3D:
	return matte(pbr(RIVER_TEX + "brown_mud_02", c, 0.1, 1.0))

static func grass() -> StandardMaterial3D:
	return matte(pbr(RIVER_TEX + "withered_grass", Color(0.62, 0.6, 0.5), 0.12, 1.0))

static func slag() -> StandardMaterial3D:
	return matte(pbr(RAIL_TEX + "gravel_stones", Color(0.16, 0.145, 0.14), 0.08, 1.0))

static func ore() -> StandardMaterial3D:
	return matte(pbr(RIVER_TEX + "river_small_rocks", Color(0.45, 0.25, 0.18), 0.25, 1.0))

static func coke() -> StandardMaterial3D:
	return matte(pbr(RAIL_TEX + "gravel_stones", Color(0.13, 0.125, 0.12), 0.5, 0.8))

static func rail_yellow() -> StandardMaterial3D:
	return paint(Color(0.78, 0.6, 0.2))

static func black() -> StandardMaterial3D:
	return Geo.flat(Color(0.02, 0.02, 0.02), 0.9)

static func puddle() -> StandardMaterial3D:
	if not _cache.has("puddle"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.04, 0.045, 0.05)
		m.metallic = 0.6
		m.roughness = 0.04
		_cache["puddle"] = m
	return _cache["puddle"]

static func lamp_glow(c: Color = Color(1.0, 0.75, 0.45), e: float = 4.0) -> StandardMaterial3D:
	return Geo.flat(Color(0.1, 0.08, 0.06), 0.6, 0.0, c, e)

static func glass() -> StandardMaterial3D:
	return RailProps.glass()

# ------------------------------------------------------------------ Mathe

## Orthonormale Basis mit z entlang d (fuer Boxen zwischen zwei Punkten).
static func basis_z(d: Vector3) -> Basis:
	var z := d.normalized()
	var ref := Vector3.UP if absf(z.y) < 0.98 else Vector3.RIGHT
	var x := ref.cross(z).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)

## Orthonormale Basis mit y entlang d (fuer Zylinder zwischen zwei Punkten).
static func basis_y(d: Vector3) -> Basis:
	var y := d.normalized()
	var ref := Vector3.FORWARD if absf(y.y) > 0.9 else Vector3.UP
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)

static func yaw_b(deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(deg))

# ------------------------------------------------------------------ Kollision

static func col(body: CollisionObject3D, c: Vector3, size: Vector3, rot: Basis = Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(rot.orthonormalized(), c)
	body.add_child(cs)

static func col_cyl(body: CollisionObject3D, bottom: Vector3, h: float, r: float) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	cs.shape = s
	cs.position = bottom + Vector3(0, h * 0.5, 0)
	body.add_child(cs)

## Statischer Koerper (Layer 1), nicht vom PropCollision-Refit angefasst (begehbare Bauten).
static func body(parent: Node3D, name: String, no_fit: bool = true) -> StaticBody3D:
	var b := Geo.static_body()
	b.name = name
	if no_fit:
		b.set_meta("no_fit", true)
	parent.add_child(b)
	return b

# ------------------------------------------------------------------ Primitive (in Kit-Batches)

static func box(k: RailProps.Kit, key: String, m: Material, c: Vector3, size: Vector3, rot: Basis = Basis.IDENTITY, b: StaticBody3D = null) -> void:
	k.b(key, m).add(c, size, rot)
	if b != null:
		col(b, c, size, rot)

## Kantiger Traeger zwischen a und b (Querschnitt th x th).
static func beam(k: RailProps.Kit, key: String, m: Material, a: Vector3, bb: Vector3, th: float, b: StaticBody3D = null) -> void:
	var d := bb - a
	if d.length() < 0.01:
		return
	var rot := basis_z(d)
	k.b(key, m).add((a + bb) * 0.5, Vector3(th, th, d.length()), rot)
	if b != null:
		col(b, (a + bb) * 0.5, Vector3(th, th, d.length()), rot)

## I-Traeger (Flansche + Steg) zwischen a und b, Steg vertikal (fuer horizontale/schraege Traeger).
static func ibeam(k: RailProps.Kit, key: String, m: Material, a: Vector3, bb: Vector3, h: float, w: float, b: StaticBody3D = null) -> void:
	var d := bb - a
	var L := d.length()
	if L < 0.01:
		return
	var rot := basis_z(d)
	var c := (a + bb) * 0.5
	var bt := k.b(key, m)
	bt.add(c, Vector3(0.03 + w * 0.08, h, L), rot)
	bt.add(c + rot.y * (h * 0.5 - 0.02), Vector3(w, 0.04, L), rot)
	bt.add(c - rot.y * (h * 0.5 - 0.02), Vector3(w, 0.04, L), rot)
	if b != null:
		col(b, c, Vector3(w, h, L), rot)

## Vertikale Stuetze als H-Profil (unten bei p, Hoehe h).
static func column(k: RailProps.Kit, key: String, m: Material, p: Vector3, h: float, s: float, b: StaticBody3D = null, yaw: float = 0.0) -> void:
	var rot := yaw_b(yaw)
	var c := p + Vector3(0, h * 0.5, 0)
	var bt := k.b(key, m)
	bt.add(c, Vector3(s, h, 0.05), rot)
	bt.add(c + rot.z * (s * 0.5 - 0.025), Vector3(s, h, 0.05), rot)
	bt.add(c - rot.z * (s * 0.5 - 0.025), Vector3(s, h, 0.05), rot)
	bt.add(c, Vector3(0.04, h, s), rot)
	# Fussplatte
	bt.add(p + Vector3(0, 0.03, 0), Vector3(s + 0.3, 0.06, s + 0.3), rot)
	if b != null:
		col(b, c, Vector3(s, h, s), rot)

static func _unit_cyl(seg: int) -> CylinderMesh:
	var key := "ucyl%d" % seg
	if not _cache.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.height = 1.0
		cm.radial_segments = seg
		cm.rings = 1
		_cache[key] = cm
	return _cache[key]

static func _unit_sphere(seg: int) -> SphereMesh:
	var key := "usph%d" % seg
	if not _cache.has(key):
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = seg
		sm.rings = maxi(4, seg / 2)
		_cache[key] = sm
	return _cache[key]

## Beliebiges Mesh in einen Batch haengen.
static func add_mesh(k: RailProps.Kit, key: String, m: Material, mesh: Mesh, xf: Transform3D) -> void:
	var bt := k.b(key, m)
	bt.st.append_from(mesh, 0, xf)
	bt.count += 1

## Rohr/Zylinder zwischen a und b.
static func pipe(k: RailProps.Kit, key: String, m: Material, a: Vector3, bb: Vector3, r: float, seg: int = 12, b: StaticBody3D = null) -> void:
	var d := bb - a
	var L := d.length()
	if L < 0.01:
		return
	var rot := basis_y(d)
	add_mesh(k, key, m, _unit_cyl(seg), Transform3D(rot.scaled_local(Vector3(r * 2.0, L, r * 2.0)), (a + bb) * 0.5))
	if b != null:
		var cs := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = r
		s.height = L
		cs.shape = s
		cs.transform = Transform3D(rot, (a + bb) * 0.5)
		b.add_child(cs)

static func ball(k: RailProps.Kit, key: String, m: Material, c: Vector3, r: float, seg: int = 12) -> void:
	add_mesh(k, key, m, _unit_sphere(seg), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r * 2.0), c))

## Rohrzug durch mehrere Punkte, Kugeln an den Knicken (weiche Boegen).
static func pipe_path(k: RailProps.Kit, key: String, m: Material, pts: Array, r: float, seg: int = 14, b: StaticBody3D = null) -> void:
	for i in pts.size() - 1:
		pipe(k, key, m, pts[i], pts[i + 1], r, seg, b)
		if i > 0:
			ball(k, key, m, pts[i], r * 1.02, seg)

## Flanschring um ein Rohr (Ziernaht).
static func flange(k: RailProps.Kit, key: String, m: Material, c: Vector3, dir: Vector3, r: float, seg: int = 14) -> void:
	var rot := basis_y(dir)
	add_mesh(k, key, m, _unit_cyl(seg), Transform3D(rot.scaled_local(Vector3(r * 2.0, 0.12, r * 2.0)), c))

static func torus(k: RailProps.Kit, key: String, m: Material, c: Vector3, R: float, r: float, rot: Basis = Basis.IDENTITY, segs: int = 32) -> void:
	var key2 := "tor|%s|%s|%d" % [R, r, segs]
	if not _cache.has(key2):
		var tm := TorusMesh.new()
		tm.inner_radius = R - r
		tm.outer_radius = R + r
		tm.rings = segs
		tm.ring_segments = 10
		_cache[key2] = tm
	add_mesh(k, key, m, _cache[key2], Transform3D(rot, c))

## Kegelstumpf/Zylinder vertikal (unten bei p).
static func cone(k: RailProps.Kit, key: String, m: Material, p: Vector3, h: float, r_bot: float, r_top: float, seg: int = 20) -> void:
	var key2 := "cone|%s|%s|%s|%d" % [h, r_bot, r_top, seg]
	if not _cache.has(key2):
		var cm := CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bot
		cm.height = h
		cm.radial_segments = seg
		cm.rings = 1
		_cache[key2] = cm
	add_mesh(k, key, m, _cache[key2], Transform3D(Basis.IDENTITY, p + Vector3(0, h * 0.5, 0)))

# ------------------------------------------------------------------ Drehkoerper

## Drehkoerper aus einem Profil [Vector2(r, y), ...] (von unten nach oben). Normalen: weich, ausser
## an scharfen Profilknicken (> 35 Grad). Eigene MeshInstance (kein Batch).
static func lathe(profile: Array, seg: int = 32) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var seg_n: Array[Vector2] = []
	for i in n - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		var d := b - a
		seg_n.append(Vector2(d.y, -d.x).normalized())
	for i in n - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		if a.distance_to(b) < 0.0001:
			continue
		var na: Vector2 = seg_n[i]
		var nb: Vector2 = seg_n[i]
		if i > 0 and seg_n[i - 1].dot(seg_n[i]) > 0.82:
			na = (seg_n[i - 1] + seg_n[i]).normalized()
		if i < n - 2 and seg_n[i + 1].dot(seg_n[i]) > 0.82:
			nb = (seg_n[i + 1] + seg_n[i]).normalized()
		for s in seg:
			var a0 := TAU * float(s) / seg
			var a1 := TAU * float(s + 1) / seg
			var c0 := Vector2(cos(a0), sin(a0))
			var c1 := Vector2(cos(a1), sin(a1))
			var p00 := Vector3(a.x * c0.x, a.y, a.x * c0.y)
			var p01 := Vector3(a.x * c1.x, a.y, a.x * c1.y)
			var p10 := Vector3(b.x * c0.x, b.y, b.x * c0.y)
			var p11 := Vector3(b.x * c1.x, b.y, b.x * c1.y)
			var n00 := Vector3(na.x * c0.x, na.y, na.x * c0.y)
			var n01 := Vector3(na.x * c1.x, na.y, na.x * c1.y)
			var n10 := Vector3(nb.x * c0.x, nb.y, nb.x * c0.y)
			var n11 := Vector3(nb.x * c1.x, nb.y, nb.x * c1.y)
			# Dreiecke im Uhrzeigersinn von aussen gesehen (Godot: Vorderseite = CW)
			st.set_normal(n00); st.add_vertex(p00)
			st.set_normal(n11); st.add_vertex(p11)
			st.set_normal(n10); st.add_vertex(p10)
			st.set_normal(n00); st.add_vertex(p00)
			st.set_normal(n01); st.add_vertex(p01)
			st.set_normal(n11); st.add_vertex(p11)
	return st.commit()

static func lathe_node(parent: Node3D, profile: Array, m: Material, pos: Vector3, seg: int = 32, shadows: bool = true) -> MeshInstance3D:
	var mi := Geo.mesh_node(lathe(profile, seg), m, pos, shadows)
	parent.add_child(mi)
	return mi

# ------------------------------------------------------------------ Gelaender, Treppen, Fachwerk

## Gelaender von a nach b (Punkte auf der Lauf-/Bodenflaeche, duerfen geneigt sein):
## Pfosten, Handlauf, Knieleiste, Fussleiste. Kollision: duenne Box 1.1 m hoch.
static func railing(k: RailProps.Kit, m: Material, a: Vector3, bb: Vector3, b: StaticBody3D = null, h: float = RAIL_H, posts: bool = true) -> void:
	var d := bb - a
	var L := d.length()
	if L < 0.05:
		return
	var key := "rail"
	var nseg := maxi(1, int(ceil(L / 1.5)))
	if posts:
		for i in nseg + 1:
			var p := a + d * (float(i) / nseg)
			k.b(key, m).add(p + Vector3(0, h * 0.5, 0), Vector3(0.05, h, 0.05))
	beam(k, key, m, a + Vector3(0, h, 0), bb + Vector3(0, h, 0), 0.055)
	beam(k, key, m, a + Vector3(0, h * 0.52, 0), bb + Vector3(0, h * 0.52, 0), 0.035)
	var hd := Vector3(d.x, 0, d.z)
	if hd.length() > 0.01:
		var rot := basis_z(d)
		k.b(key, m).add((a + bb) * 0.5 + Vector3(0, 0.06, 0), Vector3(0.012, 0.12, L), rot)
	if b != null:
		var rot2 := basis_z(d)
		var cosv := sqrt(maxf(0.05, 1.0 - d.normalized().y * d.normalized().y))
		col(b, (a + bb) * 0.5 + Vector3(0, h * 0.5, 0), Vector3(0.06, h * cosv, L), rot2)

## Gelaender ueber eine Punktfolge (geschlossen = false).
static func railing_path(k: RailProps.Kit, m: Material, pts: Array, b: StaticBody3D = null) -> void:
	for i in pts.size() - 1:
		railing(k, m, pts[i], pts[i + 1], b)

## Treppenlauf: start = Lauflinienmitte am Fuss (Bodenhoehe), dir = horizontale Laufrichtung,
## rise = Hoehe. Optik: Stufen (Gitterrost), Wangen; Kollision: eine schraege Rampe (31 Grad).
## rails: [links, rechts] (bezogen auf die Laufrichtung). Gibt den Endpunkt (oben, Lauflinie) zurueck.
static func stair_flight(k: RailProps.Kit, b: StaticBody3D, start: Vector3, dir: Vector3, rise: float, width: float, rail_l: bool, rail_r: bool, rail_m: Material) -> Vector3:
	var n := maxi(1, int(round(rise / RISER)))
	var riser := rise / n
	var L := n * RUN
	var side := dir.cross(Vector3.UP).normalized()      # rechte Seite
	var tread_rot := Basis(side, Vector3.UP, -dir)
	var gm := grating()
	for i in n:
		var c := start + dir * ((i + 0.5) * RUN) + Vector3(0, (i + 1) * riser - 0.025, 0)
		k.b("tread", gm).add(c, Vector3(width, 0.05, RUN + 0.02), tread_rot)
		k.b("tread_edge", dark_steel()).add(c + dir * (RUN * 0.5 - 0.02) - Vector3(0, 0.03, 0), Vector3(width, 0.07, 0.04), tread_rot)
	var top := start + dir * L + Vector3(0, rise, 0)
	# Wangen (U-Profil)
	var sm := dark_steel()
	for s: float in [-1.0, 1.0]:
		var off := side * s * (width * 0.5 + 0.05)
		beam(k, "stringer", sm, start + off + Vector3(0, -0.12, 0) - dir * 0.15, top + off + Vector3(0, -0.12, 0) - dir * RUN * 0.5, 0.26)
	# Rampe: Oberkante durch die Stufenmitten, von -RUN/2 (Boden) bis L - RUN/2 (Podest)
	var p0 := start - dir * (RUN * 0.5)
	var p1 := start + dir * (L - RUN * 0.5) + Vector3(0, rise, 0)
	var s_dir := (p1 - p0).normalized()
	var nrm := side.cross(s_dir).normalized()
	var rot := Basis(side, nrm, -s_dir)
	col(b, (p0 + p1) * 0.5 - nrm * 0.06, Vector3(width + 0.1, 0.12, (p1 - p0).length()), rot)
	# Gelaender entlang der Rampenlinie (Lauf-Oberflaeche)
	for s: float in [-1.0, 1.0]:
		if (s < 0.0 and not rail_l) or (s > 0.0 and not rail_r):
			continue
		var off := side * s * (width * 0.5 + 0.06)
		railing(k, rail_m, p0 + off + dir * 0.15 + s_dir * 0.0, p1 + off, b)
	return top

## Fachwerkwand (vertikale Ebene) von a nach bb (Untergurt), Hoehe h, Feldweite panel.
static func truss(k: RailProps.Kit, key: String, m: Material, a: Vector3, bb: Vector3, h: float, panel: float, th: float, b: StaticBody3D = null, chords: bool = true) -> void:
	var d := bb - a
	var n := maxi(1, int(round(d.length() / panel)))
	var up := Vector3(0, h, 0)
	if chords:
		beam(k, key, m, a, bb, th * 1.4, b)
		beam(k, key, m, a + up, bb + up, th * 1.4, b)
	for i in n + 1:
		var p := a + d * (float(i) / n)
		beam(k, key, m, p, p + up, th, b)
		if i < n:
			var q := a + d * (float(i + 1) / n)
			if i % 2 == 0:
				beam(k, key, m, p, q + up, th * 0.8, b)
			else:
				beam(k, key, m, p + up, q, th * 0.8, b)

## Steigleiter (Optik) von unten p nach oben (Hoehe h), Holme quer zu "face" (Blickrichtung zur Leiter).
static func ladder(k: RailProps.Kit, m: Material, p: Vector3, h: float, face: Vector3, cage: bool = false) -> void:
	var side := face.cross(Vector3.UP).normalized()
	for s: float in [-0.22, 0.22]:
		k.b("ladder", m).add(p + side * s + Vector3(0, h * 0.5, 0), Vector3(0.05, h, 0.05))
	var y := 0.3
	while y < h:
		k.b("ladder", m).add(p + Vector3(0, y, 0), Vector3(0.03, 0.03, 0.03) + side.abs() * 0.44)
		y += 0.3
	if cage:
		y = 2.4
		while y < h:
			var c := p - face * 0.38 + Vector3(0, y, 0)
			k.b("ladder", m).add(c - face * 0.33, Vector3(0.04, 0.04, 0.04) + side.abs() * 0.72)
			k.b("ladder", m).add(c + side * 0.36 - face * 0.0, Vector3(0.04, 0.04, 0.04) + face.abs() * 0.7)
			k.b("ladder", m).add(c - side * 0.36 - face * 0.0, Vector3(0.04, 0.04, 0.04) + face.abs() * 0.7)
			y += 0.9
		for s2: float in [-0.36, 0.0, 0.36]:
			var c2 := p - face * (0.38 + (0.33 if s2 == 0.0 else 0.0)) + side * s2 + Vector3(0, 2.4 + (h - 2.4) * 0.5, 0)
			k.b("ladder", m).add(c2, Vector3(0.03, h - 2.4, 0.03))

## Kit in Knoten schreiben, optional mit Sichtweiten-Grenze und ohne Schatten.
static func flush(k: RailProps.Kit, parent: Node3D, shadows: bool = true, vis_end: float = 0.0) -> void:
	var before := parent.get_child_count()
	k.flush(parent, shadows)
	if vis_end > 0.0:
		for i in range(before, parent.get_child_count()):
			var gi := parent.get_child(i) as GeometryInstance3D
			if gi != null:
				gi.visibility_range_end = vis_end
				gi.visibility_range_end_margin = vis_end * 0.08
				gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

# ------------------------------------------------------------------ Dampf

## Weiche Dampffahne (helle, sehr transparente, grosse Partikel; langsam steigend, Wind-Drift).
## size = Partikelgroesse (m), rise = Steiggeschwindigkeit, life = Lebensdauer (s), drift = Windfaktor.
static func steam(parent: Node3D, pos: Vector3, radius: float, size: float, rise: float, life: float, amount: int, drift: float, alpha: float = 0.32, tint: Color = Color(0.86, 0.86, 0.87)) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	VfxLib.smoke_pm(pm, 3.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = rise * 0.8
	pm.initial_velocity_max = rise * 1.2
	pm.gravity = Vector3(0, rise * 0.04, 0) + VfxLib.WIND * drift
	pm.damping_min = rise * 0.02
	pm.damping_max = rise * 0.05
	pm.scale_min = size * 0.75
	pm.scale_max = size * 1.25
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.35], [0.25, 0.85], [1.0, 2.6]])
	pm.color_ramp = VfxLib.smoke_alpha_ramp(alpha, 0.1, 0.5)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = size * 1.5
	pm.turbulence_noise_speed = Vector3(0, 0.05, 0)
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.04
	var mat := VfxLib.smoke_mat({
		"smoke_color": tint,
		"smoke_color_end": tint.lerp(Color(0.8, 0.83, 0.88), 0.5),
		"color_shift": 1.0,
		"density": 0.85,
		"erosion": 0.45,
		"frame_span": 4.0,
		"soft_dist": 4.0,
		"self_shadow": 0.3,
		"wrap": 0.9,
		"scatter": 1.8,
		"scatter_power": 4.0,
		"detail_erode": 0.45,
		"near_fade": 3.0,
	}, true)
	var p := VfxLib.make_particles(amount, life, pm, VfxLib.quad(1.0), mat)
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.5
	p.preprocess = life
	var ext := size * 3.0 + rise * life + VfxLib.WIND.length() * drift * life * life * 0.5
	p.visibility_aabb = AABB(Vector3(-ext, -size * 2.0, -ext), Vector3(ext * 2.0, ext * 1.6 + size * 2.0, ext * 2.0))
	p.name = "Steam"
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	return p
