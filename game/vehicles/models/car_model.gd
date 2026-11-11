extends RefCounted
## Zivile Fahrzeuge/Wracks fuer LevelProps.vehicle: Karosserie aus Seitenprofilen (mit Radlaeufen)
## per GunModels.extrude mit runder Fase, Fensterband/Greenhouse als eigenes Profil, Saeulen und Dach,
## Raeder bzw. (ausgebrannt) nackte Felgen. Front = +Z, Boden y = 0. Geometrie je Typ gecacht;
## pro Fahrzeug 3-4 Draw-Calls (Lack, Glas, Reifen, Felgen).
## Keine UVs noetig: die Level-Materialien (Geo.mat) sind welt-triplanar.

static var _cache: Dictionary = {}

## kind: "car", "van", "bus", "truck". Haengt die Meshes an root.
static func build(root: Node3D, kind: String, paint: Material, glass: Material, rubber: Material, rim: Material,
		burnt: bool) -> void:
	var key := kind + ("_b" if burnt else "")
	if not _cache.has(key):
		_cache[key] = _make(kind, burnt)
	var parts: Dictionary = _cache[key]
	_add(root, parts["body"], paint)
	_add(root, parts["glass"], glass)
	if parts.has("tires"):
		_add(root, parts["tires"], rubber)
	_add(root, parts["rims"], rim)

static func _add(root: Node3D, mesh: Mesh, m: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	root.add_child(mi)

## Halbkreis-Radlauf in ein Unterkanten-Profil einfuegen (von vorn nach hinten laufend).
static func _arch(out: Array, zc: float, r: float, y0: float) -> void:
	for i in 9:
		var a := PI * float(i) / 8.0
		out.append(Vector2(zc + cos(a) * r, y0 + sin(a) * r * 0.92))

static func _ext(pts: Array, hw: float, bevel: float, r: float = 0.06) -> ArrayMesh:
	return GunModels.extrude(GunModels.rounded(pts, r, true, 3), hw, bevel, 2)

static func _merge(meshes: Array, xforms: Array = []) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in meshes.size():
		var xf: Transform3D = xforms[i] if i < xforms.size() else Transform3D.IDENTITY
		st.append_from(meshes[i], 0, xf)
	return st.commit()

static func _make(kind: String, burnt: bool) -> Dictionary:
	var L := 4.4
	var W := 1.8
	var wheel_r := 0.33
	var wz: Array[float] = [1.42, -1.38]
	match kind:
		"van":
			L = 5.2; W = 2.0; wheel_r = 0.36; wz = [1.75, -1.65]
		"bus":
			L = 11.0; W = 2.5; wheel_r = 0.5; wz = [4.0, -3.4]
		"truck":
			L = 7.0; W = 2.4; wheel_r = 0.5; wz = [2.45, -2.2]
	var hz := L * 0.5
	var sink := 0.1 if burnt else 0.0      # ausgebrannt: ohne Reifen tiefer
	var y0 := 0.3 - sink                   # Unterkante Schweller
	var ar := wheel_r + 0.07               # Radlauf-Radius
	var body: Array = []
	var glass: Array = []
	# Unterkante (vorn -> hinten) mit Radlaeufen, wird an jedes Seitenprofil angehaengt
	var bottom: Array = [Vector2(hz - 0.05, y0)]
	for z in wz:
		_arch(bottom, z, ar, y0)
	bottom.append(Vector2(-hz + 0.05, y0))
	match kind:
		"car":
			var top: Array = [Vector3(-hz, y0 + 0.08, 0.05), Vector3(-hz - 0.03, y0 + 0.36, 0.08), Vector3(-hz + 0.12, y0 + 0.62, 0.12),
				Vector3(-1.3, y0 + 0.66, 0.05), Vector3(1.05, y0 + 0.66, 0.05), Vector3(hz - 0.18, y0 + 0.52, 0.18),
				Vector3(hz + 0.02, y0 + 0.3, 0.08), Vector3(hz, y0 + 0.08, 0.05)]
			body.append(_ext(_profile(top, bottom), W * 0.5, 0.12))
			# Greenhouse (Glas/Innenraum) mit Einzug, Dach und Saeulen aus Lack
			var yb := y0 + 0.64
			var gh := [Vector2(-1.33, yb), Vector2(-0.98, yb + 0.47), Vector2(0.32, yb + 0.49), Vector2(1.1, yb)]
			glass.append(_ext(gh, W * 0.5 - 0.11, 0.1, 0.08))
			body.append(_ext(GunModels.stroke([Vector2(-1.02, yb + 0.46), Vector2(0.36, yb + 0.48)], 0.07), W * 0.5 - 0.1, 0.035))
			var hw := W * 0.5 - 0.115
			for sx: float in [-1.0, 1.0]:
				var xf := Transform3D(Basis.IDENTITY, Vector3(sx * hw, 0, 0))
				body.append(_merge([GunModels.extrude(GunModels.stroke([Vector2(1.1, yb), Vector2(0.33, yb + 0.48)], 0.075), 0.035, 0.012)], [xf]))
				body.append(_merge([GunModels.extrude(GunModels.stroke([Vector2(-0.22, yb), Vector2(-0.26, yb + 0.48)], 0.1), 0.035, 0.012)], [xf]))
				body.append(_merge([GunModels.extrude(GunModels.stroke([Vector2(-1.34, yb), Vector2(-0.99, yb + 0.47)], 0.16), 0.035, 0.012)], [xf]))
		"van":
			var top: Array = [Vector3(-hz, y0 + 0.05, 0.05), Vector3(-hz - 0.02, y0 + 1.48, 0.16), Vector3(1.25, y0 + 1.5, 0.22),
				Vector3(hz - 0.62, y0 + 0.86, 0.12), Vector3(hz - 0.05, y0 + 0.66, 0.16), Vector3(hz + 0.02, y0 + 0.2, 0.08)]
			body.append(_ext(_profile(top, bottom), W * 0.5, 0.14))
			# Fensterband + Frontscheibe, leicht vor der Karosserie
			var gb: Array = [Vector2(-hz + 0.3, y0 + 1.02), Vector2(-hz + 0.3, y0 + 1.36), Vector2(1.2, y0 + 1.38),
				Vector2(hz - 0.56, y0 + 0.92), Vector2(hz - 1.4, y0 + 0.98)]
			glass.append(_ext(gb, W * 0.5 + 0.012, 0.012, 0.05))
		"bus":
			var top: Array = [Vector3(-hz, y0 + 0.05, 0.08), Vector3(-hz - 0.02, y0 + 2.62, 0.22), Vector3(hz - 0.22, y0 + 2.66, 0.22),
				Vector3(hz + 0.02, y0 + 1.1, 0.1), Vector3(hz, y0 + 0.08, 0.08)]
			body.append(_ext(_profile(top, bottom), W * 0.5, 0.12))
			var gb: Array = [Vector2(-hz + 0.35, y0 + 1.35), Vector2(-hz + 0.35, y0 + 2.4), Vector2(hz - 0.2, y0 + 2.42),
				Vector2(hz + 0.03, y0 + 1.15), Vector2(hz - 1.2, y0 + 1.2)]
			glass.append(_ext(gb, W * 0.5 + 0.012, 0.012, 0.05))
			# Dachkante/Regenrinne
			body.append(_ext(GunModels.stroke([Vector2(-hz + 0.2, y0 + 2.5), Vector2(hz - 0.3, y0 + 2.52)], 0.05), W * 0.5 + 0.02, 0.02))
		"truck":
			# Fahrerhaus vorn (z 1.35..hz), Pritsche/Koffer hinten, Rahmen dazwischen
			var cab: Array = [Vector3(1.35, y0 + 0.3, 0.05), Vector3(1.35, y0 + 2.42, 0.14), Vector3(hz - 0.48, y0 + 2.46, 0.2),
				Vector3(hz - 0.08, y0 + 1.5, 0.1), Vector3(hz + 0.02, y0 + 0.6, 0.12), Vector3(hz, y0 + 0.3, 0.05)]
			var cb: Array = []
			_arch(cb, wz[0], ar, y0 + 0.3)
			for p: Vector2 in cb:
				cab.append(Vector3(p.x, p.y, 0.0))
			body.append(_ext(cab, W * 0.5, 0.12))
			var gb: Array = [Vector2(1.6, y0 + 1.55), Vector2(1.6, y0 + 2.2), Vector2(hz - 0.5, y0 + 2.24), Vector2(hz - 0.12, y0 + 1.5)]
			glass.append(_ext(gb, W * 0.5 + 0.012, 0.012, 0.04))
			body.append(_ext([Vector3(-hz, y0 + 0.72, 0.04), Vector3(-hz, y0 + 2.6, 0.06), Vector3(1.2, y0 + 2.6, 0.06),
				Vector3(1.2, y0 + 0.72, 0.04)], W * 0.5, 0.05))
			body.append(_ext(GunModels.stroke([Vector2(-hz + 0.1, y0 + 0.35), Vector2(hz - 0.2, y0 + 0.35)], 0.26), W * 0.5 - 0.45, 0.03))
			# Kotfluegel hinten
			for z in [wz[1]]:
				body.append(_ext([Vector2(z - ar - 0.1, y0 + 0.62), Vector2(z - ar - 0.1, y0 + 0.74), Vector2(z + ar + 0.1, y0 + 0.74),
					Vector2(z + ar + 0.1, y0 + 0.62)], W * 0.5 - 0.05, 0.02))
	# Stossstangen (Pkw/Van/Bus)
	if kind != "truck":
		for sz: float in [1.0, -1.0]:
			body.append(_ext(GunModels.stroke([Vector2(sz * (hz + 0.03), y0 + 0.08), Vector2(sz * (hz + 0.04), y0 + 0.3)], 0.1), W * 0.5 - 0.04, 0.04))
	var res := {}
	res["body"] = _merge(body)
	res["glass"] = _merge(glass)
	# Raeder: Reifen + Felge; ausgebrannt nur Felge
	var tire := CylinderMesh.new()
	tire.top_radius = wheel_r
	tire.bottom_radius = wheel_r
	tire.height = 0.24 if kind == "car" else 0.3
	tire.radial_segments = 20
	tire.rings = 1
	var rimm := CylinderMesh.new()
	rimm.top_radius = wheel_r * 0.62
	rimm.bottom_radius = wheel_r * 0.66
	rimm.height = (0.24 if kind == "car" else 0.3) + (0.02 if not burnt else -0.06)
	rimm.radial_segments = 16
	rimm.rings = 1
	var t_meshes: Array = []
	var t_xf: Array = []
	var r_meshes: Array = []
	var r_xf: Array = []
	for z in wz:
		for sx: float in [-1.0, 1.0]:
			var wb := Basis(Vector3(0, 0, 1), PI * 0.5)
			var cy := wheel_r - 0.02
			var c := Vector3(sx * (W * 0.5 - 0.17), cy if not burnt else wheel_r * 0.66 - 0.01, z)
			if not burnt:
				t_meshes.append(tire)
				t_xf.append(Transform3D(wb, c))
			r_meshes.append(rimm)
			r_xf.append(Transform3D(wb, c + Vector3(sx * 0.005, 0, 0)))
	if not t_meshes.is_empty():
		res["tires"] = _merge(t_meshes, t_xf)
	res["rims"] = _merge(r_meshes, r_xf)
	return res

## Seitenprofil: Oberkontur (hinten -> vorn, Vector3 mit Eckradius) + Unterkante (vorn -> hinten).
static func _profile(top: Array, bottom: Array) -> Array:
	var out: Array = top.duplicate()
	for p: Vector2 in bottom:
		out.append(Vector3(p.x, p.y, 0.0))
	return out
