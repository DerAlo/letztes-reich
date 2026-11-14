extends RefCounted
## Bootssteg der Villa (nur Optik): einzelne Holzbohlen mit Fugen und leichtem Versatz, Laengstraeger,
## Querjoche, Rundholzpfaehle mit nassem Algensaum, gusseiserne Poller, Bootsleinen, Taurolle, alte
## Reifen als Fender, Rettungsring und ein Ruderboot. Holz: Poly Haven "rough_wood" (CC0), UVs je Bohle
## entlang der Maserung, Farbe je Bohle leicht variiert.
## Kollision und Laufflaeche legt villa_world.gd unveraendert als Boxen an (Deck-Oberkante y = 0.2).

const TEX := "res://assets/environment/villa/rough_wood/"
const TILE := 1.1              ## Meter je Texturkachel entlang der Maserung
const WATER_Y := -0.35
const BOTTOM_Y := -2.6         ## Seegrund unter dem Steg
const POLLER_Z := [-60.0, -65.5, -70.5]
const POLLER_X := -5.1

static var _wood: StandardMaterial3D = null

static func wood_mat() -> StandardMaterial3D:
	if _wood != null:
		return _wood
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(TEX + "diffuse.jpg"):
		m.albedo_texture = load(TEX + "diffuse.jpg")
		m.normal_enabled = true
		m.normal_texture = load(TEX + "normal.jpg")
		m.normal_scale = 1.2
		m.roughness_texture = load(TEX + "arm.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.ao_enabled = true
		m.ao_texture = load(TEX + "arm.jpg")
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	else:
		m.albedo_color = Color(0.4, 0.36, 0.3)
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_wood = m
	return m

## Baut den Steg unter parent (StaticBody3D der Welt; Meshes sind keine Kollider).
static func build(parent: Node3D, seed_v: int = 4711) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# --- Hauptsteg: x -7..-5, z -44..-72, Bohlen quer (entlang X)
	_deck(st, rng, Vector2(-7.0, -72.0), Vector2(-5.0, -44.0), 0, 0.2)
	# Laengstraeger unter den Bohlen
	for sx: float in [-6.85, -6.0, -5.15]:
		_box(st, Transform3D(Basis.IDENTITY, Vector3(sx, 0.075, -58.0)), Vector3(0.1, 0.16, 28.0), 2, _uvo(rng), _tone(rng, 0.62))
	# Querjoche und Pfaehle (Westseite ragt als Pfosten ueber das Deck, Ostseite endet unter dem Deck,
	# damit der linke Schwimmer des Wasserflugzeugs frei liegt)
	for k in 8:
		var z := -44.6 - float(k) * 3.88
		_box(st, Transform3D(Basis.IDENTITY, Vector3(-6.0, -0.08, z)), Vector3(2.3, 0.15, 0.14), 0, _uvo(rng), _tone(rng, 0.55))
		_pile(st, rng, Vector3(-7.09, 0.0, z), 0.11, 0.52)
		_pile(st, rng, Vector3(-5.0, 0.0, z), 0.1, -0.02)
	# --- Querkopf am Ende nach Westen: x -9.5..-7, z -72..-69.5, Bohlen entlang Z
	_deck(st, rng, Vector2(-9.5, -72.0), Vector2(-7.0, -69.5), 2, 0.2)
	for sz: float in [-71.85, -70.75, -69.65]:
		_box(st, Transform3D(Basis.IDENTITY, Vector3(-8.25, 0.075, sz)), Vector3(2.5, 0.16, 0.1), 0, _uvo(rng), _tone(rng, 0.62))
	for p: Vector2 in [Vector2(-9.45, -71.9), Vector2(-9.45, -69.6), Vector2(-8.2, -71.95)]:
		_box(st, Transform3D(Basis.IDENTITY, Vector3(-8.35, -0.08, p.y)), Vector3(2.4, 0.15, 0.14), 0, _uvo(rng), _tone(rng, 0.55))
		_pile(st, rng, Vector3(p.x, 0.0, p.y), 0.11, 0.48)
	# --- kleiner Steg vor dem Bootshaus (Westufer): x -38..-32, z 26..30, Bohlen entlang Z
	_deck(st, rng, Vector2(-38.0, 26.0), Vector2(-32.0, 30.0), 2, 0.18)
	for sz: float in [26.15, 28.0, 29.85]:
		_box(st, Transform3D(Basis.IDENTITY, Vector3(-35.0, 0.055, sz)), Vector3(6.0, 0.14, 0.1), 0, _uvo(rng), _tone(rng, 0.6))
	for px: float in [-37.85, -35.0]:
		for pz: float in [26.1, 29.9]:
			_pile(st, rng, Vector3(px, 0.0, pz), 0.1, 0.42)
	# --- Ruderboot: Duchten und Riemen aus Holz
	var boat := Transform3D(Basis.IDENTITY, Vector3(-8.6, WATER_Y, -52.0))
	for dz: float in [-0.7, 0.55]:
		_box(st, boat * Transform3D(Basis.IDENTITY, Vector3(0, 0.3, dz)), Vector3(1.0 - absf(dz) * 0.25, 0.04, 0.24), 0, _uvo(rng), _tone(rng, 0.75))
	_box(st, boat * Transform3D(Basis.IDENTITY, Vector3(0, 0.04, 0.1)), Vector3(0.5, 0.025, 2.6), 2, _uvo(rng), _tone(rng, 0.6))
	for sx: float in [-0.22, 0.18]:
		var ob := Basis(Vector3.UP, sx * 0.3) * Basis(Vector3.RIGHT, 0.08)
		_box(st, boat * Transform3D(ob, Vector3(sx, 0.18, 0.0)), Vector3(0.05, 0.035, 2.3), 2, _uvo(rng), _tone(rng, 0.85))
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "StegHolz"
	mi.mesh = st.commit()
	mi.material_override = wood_mat()
	parent.add_child(mi)
	_rowboat(parent, boat)
	_bollards(parent)
	_ropes(parent, rng)
	_tyres(parent)
	_life_ring(parent)

# ------------------------------------------------------------------ Holzteile

## Holzton je Teil (Grauholz mit leichter Streuung, gelegentlich dunkler/nasser oder heller/neuer).
static func _tone(rng: RandomNumberGenerator, base: float) -> Color:
	var v := base * rng.randf_range(0.88, 1.1)
	var warm := rng.randf_range(-0.04, 0.06)
	var r := rng.randf()
	if r < 0.08:
		v *= 0.72
	elif r < 0.12:
		v *= 1.22
		warm += 0.08
	return Color(v * (1.0 + warm), v, v * (1.0 - warm * 1.2), 1.0)

static func _uvo(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(rng.randf(), rng.randf())

## Bohlenbelag im Rechteck lo..hi (xz), Bohlen entlang Achse along (0 = X, 2 = Z), Oberkante top.
static func _deck(st: SurfaceTool, rng: RandomNumberGenerator, lo: Vector2, hi: Vector2, along: int, top: float) -> void:
	var pitch := 0.2
	var th := 0.045
	var span: float = (hi.y - lo.y) if along == 0 else (hi.x - lo.x)
	var length: float = (hi.x - lo.x) if along == 0 else (hi.y - lo.y)
	var n := int(floor(span / pitch))
	var off := (span - float(n) * pitch) * 0.5
	for i in n:
		var w := pitch - rng.randf_range(0.018, 0.032)
		var c := off + (float(i) + 0.5) * pitch + rng.randf_range(-0.006, 0.006)
		var l := length + rng.randf_range(-0.03, 0.07)
		var shift := rng.randf_range(-0.03, 0.03)
		var y := top - th * 0.5 - rng.randf_range(0.0, 0.007)
		var yaw := rng.randf_range(-0.006, 0.006)
		var tilt := rng.randf_range(-0.012, 0.012)
		var pos: Vector3
		var s: Vector3
		var b: Basis
		if along == 0:
			pos = Vector3((lo.x + hi.x) * 0.5 + shift, y, lo.y + c)
			s = Vector3(l, th, w)
			b = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
		else:
			pos = Vector3(lo.x + c, y, (lo.y + hi.y) * 0.5 + shift)
			s = Vector3(w, th, l)
			b = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt)
		_box(st, Transform3D(b, pos), s, along, _uvo(rng), _tone(rng, 0.78))

## Rundholzpfahl vom Seegrund bis top_y: unten nass/veralgt (dunkel gruenlich), darueber Grauholz.
static func _pile(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, r: float, top_y: float) -> void:
	var uvo := _uvo(rng)
	var wet_top := WATER_Y + rng.randf_range(0.12, 0.2)
	var tone := _tone(rng, 0.6)
	_cyl(st, Vector3(base.x, BOTTOM_Y, base.z), r * 1.02, wet_top - BOTTOM_Y, 10, uvo, Color(0.2, 0.24, 0.16))
	_cyl(st, Vector3(base.x, wet_top, base.z), r, top_y - wet_top, 10, uvo + Vector2(0, (wet_top - BOTTOM_Y) / TILE), tone)

## Quader mit Holz-UVs: die Maserung (Textur-V) laeuft entlang Achse long_axis (0/1/2).
static func _box(st: SurfaceTool, xf: Transform3D, s: Vector3, long_axis: int, uvo: Vector2, col: Color) -> void:
	var h := s * 0.5
	var corners_q: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for n_ax in 3:
		var a := (n_ax + 1) % 3
		var b := (n_ax + 2) % 3
		var ua := a
		var va := b
		if a == long_axis:
			ua = b
			va = a
		for sgn: float in [-1.0, 1.0]:
			var nl := Vector3.ZERO
			nl[n_ax] = sgn
			var nw := (xf.basis * nl).normalized()
			var ps: Array[Vector3] = []
			var us: Array[Vector2] = []
			for q in corners_q:
				var p := Vector3.ZERO
				p[n_ax] = sgn * h[n_ax]
				p[a] = q.x * h[a]
				p[b] = q.y * h[b]
				ps.append(xf * p)
				us.append(Vector2(p[ua], p[va]) / TILE + uvo)
			var order: Array = [0, 2, 1, 0, 3, 2] if sgn > 0.0 else [0, 1, 2, 0, 2, 3]
			for i: int in order:
				st.set_color(col)
				st.set_normal(nw)
				st.set_uv(us[i])
				st.add_vertex(ps[i])

## Zylindermantel (ohne Deckel unten) mit Deckel oben; Maserung entlang der Hoehe.
static func _cyl(st: SurfaceTool, base: Vector3, r: float, h: float, seg: int, uvo: Vector2, col: Color) -> void:
	if h <= 0.01:
		return
	for j in seg:
		var a0 := TAU * float(j) / float(seg)
		var a1 := TAU * float(j + 1) / float(seg)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p00 := base + d0 * r
		var p10 := base + d1 * r
		var p01 := p00 + Vector3(0, h, 0)
		var p11 := p10 + Vector3(0, h, 0)
		var u0 := float(j) / float(seg) * TAU * r / TILE + uvo.x
		var u1 := float(j + 1) / float(seg) * TAU * r / TILE + uvo.x
		var v0 := uvo.y
		var v1 := uvo.y + h / TILE
		# Aussenseite (Godot-Vorderseite = von aussen im Uhrzeigersinn)
		for e: Array in [[p00, d0, Vector2(u0, v0)], [p10, d1, Vector2(u1, v0)], [p11, d1, Vector2(u1, v1)],
				[p00, d0, Vector2(u0, v0)], [p11, d1, Vector2(u1, v1)], [p01, d0, Vector2(u0, v1)]]:
			st.set_color(col)
			st.set_normal(e[1])
			st.set_uv(e[2])
			st.add_vertex(e[0])
		# Deckel (Hirnholz, etwas dunkler)
		var top := base + Vector3(0, h, 0)
		for e2: Array in [[top, Vector2(0.5, 0.5)], [p01, Vector2(0.5 + d0.x * r, 0.5 + d0.z * r)], [p11, Vector2(0.5 + d1.x * r, 0.5 + d1.z * r)]]:
			st.set_color(col * 0.8)
			st.set_normal(Vector3.UP)
			st.set_uv(e2[1] + uvo)
			st.add_vertex(e2[0])

# ------------------------------------------------------------------ Ruderboot

## Klinker-artiger Rumpf (4 m, Breite 1,3 m) mit Spiegelheck, beidseitig sichtbar, Bug nach -Z.
static func _rowboat(parent: Node3D, xf: Transform3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ns := 16
	var nj := 9
	var half_len := 2.0
	var sections: Array = []
	for i in ns + 1:
		var t := -1.0 + 2.0 * float(i) / float(ns)
		var w: float = 0.64 * sqrt(maxf(0.0, 1.0 - t * t)) if t < 0.0 else 0.64 * (1.0 - 0.42 * t * t)
		w = maxf(w, 0.004)
		var depth := 0.42 * (1.0 - 0.25 * t * t)
		var sheer := 0.5 + 0.1 * t * t   # Bordwand steigt zu den Enden
		var ring: Array[Vector3] = []
		for j in nj:
			var th := -PI * 0.5 + PI * float(j) / float(nj - 1)
			var x := w * sin(th)
			var y := sheer - depth * pow(cos(th), 0.7) - 0.08
			ring.append(Vector3(x, y, t * half_len))
		sections.append(ring)
	var paint := Color(0.2, 0.3, 0.27)
	for i in ns:
		var r0: Array = sections[i]
		var r1: Array = sections[i + 1]
		for j in nj - 1:
			var a: Vector3 = r0[j]
			var b: Vector3 = r0[j + 1]
			var c: Vector3 = r1[j + 1]
			var d: Vector3 = r1[j]
			var n := (b - a).cross(d - a).normalized()
			# Klinkerbaender: jede zweite Planke etwas dunkler, Unterwasserschiff dunkel
			var col := paint * (0.85 if j % 2 == 0 else 1.0)
			if a.y < 0.02:
				col = Color(0.12, 0.13, 0.11)
			for e: Array in [[a, Vector2(a.x, a.z)], [b, Vector2(b.x, b.z)], [c, Vector2(c.x, c.z)],
					[a, Vector2(a.x, a.z)], [c, Vector2(c.x, c.z)], [d, Vector2(d.x, d.z)]]:
				st.set_color(col)
				st.set_normal(-n)
				st.set_uv((e[1] as Vector2) / TILE)
				st.add_vertex(e[0])
	# Spiegel (Heck, +Z)
	var last: Array = sections[ns]
	var mid := Vector3(0, (last[0] as Vector3).y - 0.15, half_len)
	for j in nj - 1:
		for e3: Vector3 in [mid, last[j + 1], last[j]]:
			st.set_color(paint * 0.8)
			st.set_normal(Vector3.BACK)
			st.set_uv(Vector2(e3.x, e3.y) / TILE)
			st.add_vertex(e3)
	st.generate_tangents()
	var m := wood_mat().duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	var mi := MeshInstance3D.new()
	mi.name = "Ruderboot"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.transform = xf * Transform3D(Basis(Vector3.UP, 0.05), Vector3.ZERO)
	parent.add_child(mi)

# ------------------------------------------------------------------ Eisen, Seile, Gummi

static func _flat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

## Gusseiserne Poller (Fussplatte, taillierter Schaft, Pilzkopf). Kollision bleibt die alte Box.
static func _bollards(parent: Node3D) -> void:
	var iron := _flat(Color(0.07, 0.068, 0.065), 0.62, 0.55)
	var rust := _flat(Color(0.22, 0.11, 0.06), 0.9, 0.2)
	for z: float in POLLER_Z:
		var n := Node3D.new()
		n.name = "Poller"
		n.position = Vector3(POLLER_X, 0.2, z)
		parent.add_child(n)
		for part: Array in [[0.15, 0.15, 0.035, 0.0175, rust], [0.085, 0.105, 0.29, 0.18, iron],
				[0.13, 0.11, 0.07, 0.355, iron], [0.1, 0.13, 0.025, 0.4025, iron]]:
			var cm := CylinderMesh.new()
			cm.top_radius = part[0]
			cm.bottom_radius = part[1]
			cm.height = part[2]
			cm.radial_segments = 14
			cm.rings = 1
			var mi := MeshInstance3D.new()
			mi.mesh = cm
			mi.material_override = part[4]
			mi.position = Vector3(0, part[3], 0)
			n.add_child(mi)
		# Schraubenkoepfe der Fussplatte
		for k in 4:
			var a := TAU * float(k) / 4.0 + 0.4
			var bm := CylinderMesh.new()
			bm.top_radius = 0.016
			bm.bottom_radius = 0.016
			bm.height = 0.02
			bm.radial_segments = 6
			var bi := MeshInstance3D.new()
			bi.mesh = bm
			bi.material_override = rust
			bi.position = Vector3(cos(a) * 0.12, 0.045, sin(a) * 0.12)
			n.add_child(bi)

## Seil als Rohr entlang eines durchhaengenden Bogens a -> b.
static func _rope(st: SurfaceTool, a: Vector3, b: Vector3, sag: float, r: float, segs: int = 14) -> void:
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / float(segs)
		pts.append(a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0))
	_tube(st, pts, r)

static func _tube(st: SurfaceTool, pts: Array[Vector3], r: float) -> void:
	var sides := 6
	for i in pts.size() - 1:
		var d := (pts[i + 1] - pts[i]).normalized()
		var side := d.cross(Vector3.UP)
		if side.length() < 0.1:
			side = d.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(d).normalized()
		for j in sides:
			var a0 := TAU * float(j) / float(sides)
			var a1 := TAU * float(j + 1) / float(sides)
			var n0 := side * cos(a0) + up * sin(a0)
			var n1 := side * cos(a1) + up * sin(a1)
			var q: Array = [[pts[i] + n0 * r, n0], [pts[i] + n1 * r, n1], [pts[i + 1] + n1 * r, n1], [pts[i + 1] + n0 * r, n0]]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(q[k][1])
				st.add_vertex(q[k][0])

static func _ropes(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Bootsleinen des Ruderboots an die Westpfaehle (Bug und Heck)
	_rope(st, Vector3(-8.62, 0.1, -53.85), Vector3(-7.09, 0.4, -52.36), 0.28, 0.012)
	_rope(st, Vector3(-8.58, 0.12, -50.2), Vector3(-7.09, 0.4, -48.48), 0.3, 0.012)
	# Schlaege um die Pfahlkoepfe
	for pz: float in [-52.36, -48.48]:
		for k in 3:
			var y := 0.36 + float(k) * 0.025
			var ring: Array[Vector3] = []
			for j in 11:
				var a := TAU * float(j) / 10.0
				ring.append(Vector3(-7.09 + cos(a) * 0.123, y + sin(a * 0.5) * 0.01, pz + sin(a) * 0.123))
			_tube(st, ring, 0.012)
	# Taurolle auf dem Querkopf (flache Spirale) mit losem Ende
	var c := Vector3(-8.9, 0.215, -70.6)
	var spiral: Array[Vector3] = []
	var turns := 5.0
	var steps := 90
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := TAU * turns * t
		var rr := 0.07 + 0.2 * t
		spiral.append(c + Vector3(cos(a) * rr, 0.012 + rng.randf_range(0.0, 0.004), sin(a) * rr))
	var tail := spiral[spiral.size() - 1]
	spiral.append(tail + Vector3(0.25, 0.0, 0.18))
	spiral.append(tail + Vector3(0.55, 0.0, 0.2))
	_tube(st, spiral, 0.014)
	# Reifen-Fender haengen an kurzen Seilen am Westrand
	for z: float in [-51.0, -55.0]:
		_rope(st, Vector3(-7.02, 0.2, z), Vector3(-7.2, -0.02, z), 0.0, 0.01, 2)
	# Rettungsring-Leine
	_rope(st, Vector3(-9.32, 0.85, -69.5), Vector3(-9.3, 0.25, -69.75), 0.05, 0.007, 6)
	var mi := MeshInstance3D.new()
	mi.name = "Seile"
	mi.mesh = st.commit()
	mi.material_override = _flat(Color(0.5, 0.43, 0.31), 0.95)
	parent.add_child(mi)

static func _tyres(parent: Node3D) -> void:
	var rubber := _flat(Color(0.035, 0.035, 0.035), 0.88)
	for z: float in [-51.0, -55.0]:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.17
		tm.outer_radius = 0.3
		tm.rings = 20
		tm.ring_segments = 8
		var mi := MeshInstance3D.new()
		mi.name = "Fender"
		mi.mesh = tm
		mi.material_override = rubber
		# Achse entlang X: Reifen haengt flach an der Stegkante
		mi.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, 0.1), Vector3(-7.26, -0.2, z))
		parent.add_child(mi)

## Rettungsring an einem Pfosten am Querkopf (orange mit vier weissen Reflexbaendern).
static func _life_ring(parent: Node3D) -> void:
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.09, 1.1, 0.09)
	post.mesh = pm
	post.material_override = wood_mat()
	post.position = Vector3(-9.3, 0.75, -69.62)
	parent.add_child(post)
	var hk := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.03, 0.03, 0.14)
	hk.mesh = hm
	hk.material_override = _flat(Color(0.1, 0.1, 0.1), 0.5, 0.6)
	hk.position = Vector3(-9.3, 1.12, -69.72)
	parent.add_child(hk)
	var c := Vector3(-9.3, 0.82, -69.73)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.32
	tm.rings = 24
	tm.ring_segments = 10
	var ring := MeshInstance3D.new()
	ring.mesh = tm
	ring.material_override = _flat(Color(0.74, 0.24, 0.06), 0.7)
	ring.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c)
	parent.add_child(ring)
	var white := _flat(Color(0.8, 0.78, 0.72), 0.7)
	for k in 4:
		var phi := PI * 0.25 + PI * 0.5 * float(k)
		var band := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.13, 0.13)
		band.mesh = bm
		band.material_override = white
		band.transform = Transform3D(Basis(Vector3.BACK, phi - PI * 0.5), c + Vector3(cos(phi), sin(phi), 0) * 0.26)
		parent.add_child(band)
