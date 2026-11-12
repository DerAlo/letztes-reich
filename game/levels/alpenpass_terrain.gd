extends RefCounted
## Hochgebirgs-Gelaende fuer "Weisses Rauschen" (alpenpass.gd).
## Hoehenmodell: Talboden (Profil floor_y ueber z) mit verrauschter Breite, Haenge mit Grat-Rauschen ausserhalb,
## darauf gestempelte Plateaus (Pads) und Wege (Pfade). Kollision = eine HeightMapShape3D (1-m-Raster),
## Optik = 2-m-Chunks + grober Fernring bis an den Horizont (ferne Gipfel), Material: alpine_terrain.gdshader.

const X0 := -160.0
const X1 := 160.0
const Z0 := -720.0
const Z1 := 80.0
const NX := 321          # (X1 - X0) / 1 m + 1
const NZ := 801
const FAR_STEP := 20.0
const FAR_X := 1400.0
const FAR_Z0 := -1800.0
const FAR_Z1 := 1000.0
const VIS_STEP := 2      # Rasterpunkte pro Optik-Vertex
const CHUNK := 32        # Optik-Zellen pro Chunk-Kante (= 64 m)

## z -> Talboden-Hoehe (absteigend sortiert)
const FLOOR := [
	[80.0, 30.0], [30.0, 8.0], [15.0, 6.0], [-45.0, 3.0], [-62.0, 2.0], [-72.0, -8.0], [-85.0, -15.0], [-100.0, -22.0], [-115.0, -30.0],
	[-130.0, -38.0], [-150.0, -45.0], [-330.0, -47.0], [-360.0, -40.0], [-395.0, -22.0], [-410.0, -22.0], [-440.0, -24.0],
	[-600.0, -28.0], [-640.0, -30.0], [-675.0, -30.0], [-700.0, -48.0], [-740.0, -90.0], [-800.0, -70.0],
	[-880.0, -18.0], [-950.0, -70.0], [-1050.0, -45.0], [-1150.0, 62.0], [-1300.0, 120.0],
]
## z -> halbe Talbreite
const HALF_W := [
	[80.0, 30.0], [20.0, 28.0], [-40.0, 24.0], [-62.0, 28.0], [-80.0, 44.0], [-110.0, 60.0], [-150.0, 70.0],
	[-200.0, 72.0], [-250.0, 66.0], [-290.0, 60.0], [-330.0, 44.0], [-360.0, 26.0], [-380.0, 18.0],
	[-410.0, 18.0], [-440.0, 24.0], [-500.0, 28.0], [-600.0, 30.0], [-640.0, 36.0], [-680.0, 40.0],
	[-700.0, 120.0], [-800.0, 250.0],
]
## z -> Breite der Almzone (sanfte Terrassen-Haenge zwischen Talboden und Fels), 0 = direkt Fels
const ALM_W := [
	[80.0, 16.0], [-40.0, 20.0], [-70.0, 34.0], [-110.0, 52.0], [-290.0, 52.0], [-330.0, 36.0], [-370.0, 10.0], [-400.0, 0.0],
]
## Hintergrund-Gipfelketten (Ringe um BACK_C): Radius, Tiefe, Sockel, Gipfelhoehe
const BACK_C := Vector2(0.0, -350.0)
const BACK_LAYERS := [[2050.0, 520.0, 160.0, 560.0], [2650.0, 620.0, 260.0, 820.0], [3250.0, 640.0, 360.0, 1100.0]]

var heights := PackedFloat32Array()
var stamps: Array = []       ## {type: "pad"|"rect"|"path", ...}
var _ridge := FastNoiseLite.new()
var _small := FastNoiseLite.new()
var _hwn := FastNoiseLite.new()
var _mul := FastNoiseLite.new()
var road_paths: Array = []   ## Stempel-Pfade mit Fahrbahn (fuer die Strassenmaske im Shader)

func _init(seed_v: int = 1506) -> void:
	_ridge.seed = seed_v
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = 0.0045
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_ridge.fractal_gain = 0.5
	_small.seed = seed_v + 3
	_small.frequency = 0.02
	_small.fractal_octaves = 3
	_hwn.seed = seed_v + 7
	_hwn.frequency = 0.012
	_hwn.fractal_octaves = 2
	_mul.seed = seed_v + 11
	_mul.frequency = 0.022
	_mul.fractal_octaves = 2

# ------------------------------------------------------------------ Stempel (vor build() setzen)

## Kreisplateau: Mitte c (x, z), Hoehe y (NAN = Basis-Hoehe der Mitte), Radius r, weicher Rand fall.
func pad(c: Vector2, y: float, r: float, fall: float) -> void:
	if is_nan(y):
		y = base(c.x, c.y)
	stamps.append({"type": "pad", "c": c, "y": y, "r": r, "fall": fall})

## Rechteck-Plateau [x0..x1] x [z0..z1] auf Hoehe y.
func rect(x0: float, x1: float, z0: float, z1: float, y: float, fall: float) -> void:
	stamps.append({"type": "rect", "a": Vector2(minf(x0, x1), minf(z0, z1)), "b": Vector2(maxf(x0, x1), maxf(z0, z1)), "y": y, "fall": fall})

## Weg als Polylinie (Vector3: y = Wegoberkante, NAN = Basis), Breite w (voll), weicher Rand fall.
## road = true: Fahrbahn (festgefahrener Schnee mit Spurrillen im Shader).
func path(pts: Array, w: float, fall: float, road: bool = false) -> void:
	var p2: Array[Vector3] = []
	for p: Vector3 in pts:
		p2.append(Vector3(p.x, base(p.x, p.z) if is_nan(p.y) else p.y, p.z))
	var st := {"type": "path", "pts": p2, "w": w * 0.5, "fall": fall}
	stamps.append(st)
	if road:
		road_paths.append(st)

# ------------------------------------------------------------------ Hoehenmodell

static func _tab(tab: Array, z: float) -> float:
	if z >= float(tab[0][0]):
		return float(tab[0][1])
	for i in range(1, tab.size()):
		var z1 := float(tab[i][0])
		if z >= z1:
			var z0 := float(tab[i - 1][0])
			var t := (z - z0) / (z1 - z0)
			return lerpf(float(tab[i - 1][1]), float(tab[i][1]), t)
	return float(tab[tab.size() - 1][1])

static func _rise(d: float) -> float:
	if d <= 0.0:
		return 0.0
	if d < 50.0:
		return 0.009 * d * d
	var e := d - 50.0
	return 22.5 + 0.9 * e + 0.0025 * e * e

static func alm_w(z: float) -> float:
	return _tab(ALM_W, z)

## Unbestempelte Gelaendehoehe: Talboden mit Mulden, Almzone (sanfte Terrassen), darueber Fels mit Grat-Rauschen.
func base(x: float, z: float) -> float:
	var fy := _tab(FLOOR, z) + _small.get_noise_2d(x, z) * 1.2
	var aw := _tab(ALM_W, z)
	if aw > 0.0:
		fy += minf(_mul.get_noise_2d(x, z) + 0.12, 0.0) * 5.0 * clampf(aw / 30.0, 0.0, 1.0)   # flache Mulden
	var hw := _tab(HALF_W, z)
	var amp := minf(hw * 0.25, 12.0)
	var hl := hw + _hwn.get_noise_2d(z, 0.0) * amp
	var hr := hw + _hwn.get_noise_2d(z, 300.0) * amp
	var d := (-x - hl) if x < 0.0 else (x - hr)
	if d <= 0.0:
		return fy
	var r := _ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var y := fy
	if aw > 0.0:
		# Almwiesen: Grundneigung + weiche Terrassenstufen (Rauschen verbiegt die Stufen)
		var da := minf(d, aw + _hwn.get_noise_2d(x * 0.7, z * 0.7) * aw * 0.25)
		da = maxf(da, 0.0)
		var u := maxf(da / 15.0 + _small.get_noise_2d(x * 0.6, z * 0.6) * 0.45, 0.0)
		var terr := floorf(u) + smoothstep(0.3, 0.7, u - floorf(u))
		y += 0.12 * da + 1.7 * terr * smoothstep(0.0, 6.0, da) + r * minf(da * 0.04, 2.0)
		d -= da
		if d <= 0.0:
			return y
	# Fels: steil am Fuss, laeuft auf eine Gratlinie aus (Kammhoehe verrauscht) -> Kessel statt Schlucht,
	# dahinter flachere Kaemme, ueber die die Hintergrund-Ketten schauen.
	var raw := _rise(d) + 0.12 * d + r * minf(d * 0.4, 140.0)
	var hc := 140.0 + 130.0 * (_hwn.get_noise_2d(x * 0.35, z * 0.35) * 0.5 + 0.5)
	var wall := hc * (1.0 - exp(-raw / hc))
	wall += r * r * 90.0 * smoothstep(50.0, 170.0, d)   # Felszacken / Gipfel auf dem Kamm
	wall += maxf(d - 180.0, 0.0) * 0.12 * (r + 0.2)
	return y + wall + _small.get_noise_2d(x * 2.0, z * 2.0) * minf(d * 0.05, 3.0)

## Endgueltige Hoehe (Raster innen bilinear, aussen Basis).
func height(x: float, z: float) -> float:
	if heights.is_empty() or x < X0 or x > X1 or z < Z0 or z > Z1:
		return base(x, z)
	var fx := x - X0
	var fz := z - Z0
	var ix := mini(int(fx), NX - 2)
	var iz := mini(int(fz), NZ - 2)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var i := iz * NX + ix
	var a := lerpf(heights[i], heights[i + 1], tx)
	var b := lerpf(heights[i + NX], heights[i + NX + 1], tx)
	return lerpf(a, b, tz)

func normal(x: float, z: float) -> Vector3:
	var e := 1.0
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()

## Rechnet das Raster (Basis + Stempel).
func build() -> void:
	heights.resize(NX * NZ)
	for iz in NZ:
		var z := Z0 + float(iz)
		var row := iz * NX
		for ix in NX:
			heights[row + ix] = base(X0 + float(ix), z)
	for s: Dictionary in stamps:
		_apply(s)

func _apply(s: Dictionary) -> void:
	var fall: float = s["fall"]
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	match str(s["type"]):
		"pad":
			var c: Vector2 = s["c"]
			var e := float(s["r"]) + fall
			lo = c - Vector2(e, e)
			hi = c + Vector2(e, e)
		"rect":
			lo = (s["a"] as Vector2) - Vector2(fall, fall)
			hi = (s["b"] as Vector2) + Vector2(fall, fall)
		"path":
			lo = Vector2(INF, INF)
			hi = Vector2(-INF, -INF)
			for p: Vector3 in s["pts"]:
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
			var e := float(s["w"]) + fall
			lo -= Vector2(e, e)
			hi += Vector2(e, e)
	var ix0 := clampi(int(floor(lo.x - X0)), 0, NX - 1)
	var ix1 := clampi(int(ceil(hi.x - X0)), 0, NX - 1)
	var iz0 := clampi(int(floor(lo.y - Z0)), 0, NZ - 1)
	var iz1 := clampi(int(ceil(hi.y - Z0)), 0, NZ - 1)
	for iz in range(iz0, iz1 + 1):
		var z := Z0 + float(iz)
		for ix in range(ix0, ix1 + 1):
			var x := X0 + float(ix)
			var dy := _stamp_at(s, x, z)    # x = Abstand ausserhalb des Kerns, y = Zielhoehe
			if dy.x >= fall:
				continue
			var f := 1.0 if dy.x <= 0.0 else 1.0 - smoothstep(0.0, fall, dy.x)
			var i := iz * NX + ix
			heights[i] = lerpf(heights[i], dy.y, f)

func _stamp_at(s: Dictionary, x: float, z: float) -> Vector2:
	match str(s["type"]):
		"pad":
			var c: Vector2 = s["c"]
			return Vector2(Vector2(x, z).distance_to(c) - float(s["r"]), float(s["y"]))
		"rect":
			var a: Vector2 = s["a"]
			var b: Vector2 = s["b"]
			var dx := maxf(maxf(a.x - x, x - b.x), 0.0)
			var dz := maxf(maxf(a.y - z, z - b.y), 0.0)
			return Vector2(sqrt(dx * dx + dz * dz), float(s["y"]))
	var pts: Array[Vector3] = s["pts"]
	var best := INF
	var by := 0.0
	var p := Vector2(x, z)
	for i in range(pts.size() - 1):
		var a3 := pts[i]
		var b3 := pts[i + 1]
		var a := Vector2(a3.x, a3.z)
		var ab := Vector2(b3.x, b3.z) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			by = lerpf(a3.y, b3.y, t)
	return Vector2(best - float(s["w"]), by)

# ------------------------------------------------------------------ Knoten

## Statische Kollision (HeightMapShape3D, Layer 1). meta no_fit: PropCollision ueberspringt den Koerper.
func build_collision(parent: Node) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("no_fit", true)
	var hm := HeightMapShape3D.new()
	hm.map_width = NX
	hm.map_depth = NZ
	hm.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = hm
	body.add_child(cs)
	body.position = Vector3((X0 + X1) * 0.5, 0.0, (Z0 + Z1) * 0.5)
	parent.add_child(body)
	return body

func build_visual(parent: Node, mat: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "TerrainMesh"
	parent.add_child(root)
	var cells_x := (NX - 1) / VIS_STEP
	var cells_z := (NZ - 1) / VIS_STEP
	var cz := 0
	while cz < cells_z:
		var cx := 0
		while cx < cells_x:
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk(cx, cz, mini(CHUNK, cells_x - cx), mini(CHUNK, cells_z - cz), cells_x, cells_z)
			mi.material_override = mat
			mi.name = "Chunk_%d_%d" % [cx / CHUNK, cz / CHUNK]
			root.add_child(mi)
			cx += CHUNK
		cz += CHUNK
	var far := MeshInstance3D.new()
	far.name = "FarRing"
	far.mesh = _far_mesh()
	far.material_override = mat
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(far)
	return root

func _gh(ix: int, iz: int) -> float:
	return heights[clampi(iz, 0, NZ - 1) * NX + clampi(ix, 0, NX - 1)]

func _gn(ix: int, iz: int) -> Vector3:
	var s := VIS_STEP
	return Vector3(_gh(ix - s, iz) - _gh(ix + s, iz), 4.0 * float(s) * 0.5, _gh(ix, iz - s) - _gh(ix, iz + s)).normalized()

func _chunk(cx: int, cz: int, w: int, d: int, cells_x: int, cells_z: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var stride := w + 1
	for j in d + 1:
		for i in w + 1:
			var gx := (cx + i) * VIS_STEP
			var gz := (cz + j) * VIS_STEP
			verts.append(Vector3(X0 + float(gx), _gh(gx, gz), Z0 + float(gz)))
			norms.append(_gn(gx, gz))
	for j in d:
		for i in w:
			var a := j * stride + i
			var b := a + 1
			var c := a + stride
			var e := c + 1
			idx.append_array([a, b, c, b, e, c])
	# Schuerzen am Aussenrand (verdecken Ritzen zum Fernring)
	var edges: Array = []
	if cz == 0:
		edges.append(range(0, w + 1))                                 # Nordrand (z = Z0)
	if cz + d >= cells_z:
		var r: Array = []
		for i in w + 1:
			r.append(d * stride + (w - i))
		edges.append(r)
	if cx == 0:
		var r2: Array = []
		for j in d + 1:
			r2.append((d - j) * stride)
		edges.append(r2)
	if cx + w >= cells_x:
		var r3: Array = []
		for j in d + 1:
			r3.append(j * stride + w)
		edges.append(r3)
	for edge: Array in edges:
		var base_i := verts.size()
		for k in edge.size():
			var v: Vector3 = verts[int(edge[k])]
			verts.append(v - Vector3(0, 8.0, 0))
			norms.append(norms[int(edge[k])])
		for k in edge.size() - 1:
			var t0 := int(edge[k])
			var t1 := int(edge[k + 1])
			var b0 := base_i + k
			var b1 := base_i + k + 1
			idx.append_array([t0, b0, t1, t1, b0, b1, t0, t1, b0, t1, b1, b0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Grober Ring um das Spielfeld (Zellen im Innenbereich fehlen; Randpunkte nutzen das Innenraster).
func _far_mesh() -> ArrayMesh:
	var nx := int((FAR_X * 2.0) / FAR_STEP) + 1
	var nz := int((FAR_Z1 - FAR_Z0) / FAR_STEP) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in nz:
		var z := FAR_Z0 + float(j) * FAR_STEP
		for i in nx:
			var x := -FAR_X + float(i) * FAR_STEP
			var y := height(x, z)
			# Horizont: nach aussen hin hoehere Kulissen-Gipfel
			var edge := maxf(absf(x) - 700.0, 0.0) + maxf(absf(z + 400.0) - 1000.0, 0.0)
			y += edge * 0.35 * (_ridge.get_noise_2d(x * 0.5, z * 0.5) * 0.5 + 0.7)
			verts.append(Vector3(x, y, z))
	for j in nz:
		for i in nx:
			var l := verts[j * nx + maxi(i - 1, 0)].y
			var r := verts[j * nx + mini(i + 1, nx - 1)].y
			var u := verts[maxi(j - 1, 0) * nx + i].y
			var dn := verts[mini(j + 1, nz - 1) * nx + i].y
			norms.append(Vector3(l - r, 2.0 * FAR_STEP, u - dn).normalized())
	for j in nz - 1:
		for i in nx - 1:
			var x0 := -FAR_X + float(i) * FAR_STEP
			var z0 := FAR_Z0 + float(j) * FAR_STEP
			if x0 >= X0 and x0 + FAR_STEP <= X1 and z0 >= Z0 and z0 + FAR_STEP <= Z1:
				continue
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var e := c + 1
			idx.append_array([a, b, c, b, e, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Strassenmaske (RG8, 1 m je Texel wie das Hoehenraster): R = Fahrbahn-Anteil, G = Querabstand zur Mittellinie
## (-6..6 m -> 0..1, vorzeichenbehaftet) fuer Spurrillen im Shader.
func road_mask() -> ImageTexture:
	var img := Image.create(NX, NZ, false, Image.FORMAT_RG8)
	img.fill(Color(0.0, 0.5, 0.0))
	var best := PackedFloat32Array()
	best.resize(NX * NZ)
	best.fill(INF)
	for st: Dictionary in road_paths:
		var pts: Array[Vector3] = st["pts"]
		var hw: float = st["w"]
		var e := hw + 3.0
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p: Vector3 in pts:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		var ix0 := clampi(int(floor(lo.x - e - X0)), 0, NX - 1)
		var ix1 := clampi(int(ceil(hi.x + e - X0)), 0, NX - 1)
		var iz0 := clampi(int(floor(lo.y - e - Z0)), 0, NZ - 1)
		var iz1 := clampi(int(ceil(hi.y + e - Z0)), 0, NZ - 1)
		for iz in range(iz0, iz1 + 1):
			var z := Z0 + float(iz)
			for ix in range(ix0, ix1 + 1):
				var x := X0 + float(ix)
				var p := Vector2(x, z)
				var bd := INF
				var bs := 0.0
				for k in range(pts.size() - 1):
					var a := Vector2(pts[k].x, pts[k].z)
					var ab := Vector2(pts[k + 1].x, pts[k + 1].z) - a
					var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
					var d := p.distance_to(a + ab * t)
					if d < bd:
						bd = d
						bs = signf(ab.cross(p - a)) * d
				var i := iz * NX + ix
				if bd >= e or bd >= best[i]:
					continue
				best[i] = bd
				var road := 1.0 - smoothstep(hw - 0.6, hw + 1.6, bd)
				img.set_pixel(ix, iz, Color(road, clampf(bs, -6.0, 6.0) / 12.0 + 0.5, 0.0))
	return ImageTexture.create_from_image(img)

## Ferne Gipfelketten als Kulisse hinter dem Fernring: drei Ringbaender mit Grat-Rauschen, eigenes Material
## (ohne Szenen-Nebel, eigene Luftperspektive; siehe alpine_backdrop.gdshader).
func build_backdrop(parent: Node) -> MeshInstance3D:
	var n := FastNoiseLite.new()
	n.seed = _ridge.seed + 21
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n.fractal_octaves = 6
	n.fractal_gain = 0.48
	n.frequency = 0.00085
	var seg := 1100
	var rows := 12
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for li in BACK_LAYERS.size():
		var lay: Array = BACK_LAYERS[li]
		var r0 := float(lay[0])
		var dep := float(lay[1])
		var sock := float(lay[2])
		var peak := float(lay[3])
		var start := verts.size()
		for j in rows:
			var t := float(j) / float(rows - 1)
			var r := r0 - dep * 0.5 + dep * t
			var bell := pow(sin(PI * t), 0.65)
			for i in seg + 1:
				var a := TAU * float(i % seg) / float(seg)
				var x := BACK_C.x + cos(a) * r
				var z := BACK_C.y + sin(a) * r
				var h := pow(clampf(n.get_noise_3d(x, z, float(li) * 900.0) * 0.5 + 0.5, 0.0, 1.0), 1.7)
				verts.append(Vector3(x, -260.0 + (sock + 260.0 + peak * h) * bell, z))
		for j in rows:
			for i in seg + 1:
				var il := start + j * (seg + 1) + (i - 1 if i > 0 else seg - 1)
				var ir := start + j * (seg + 1) + (i + 1 if i < seg else 1)
				var jd := start + maxi(j - 1, 0) * (seg + 1) + i
				var ju := start + mini(j + 1, rows - 1) * (seg + 1) + i
				var nn := (verts[ir] - verts[il]).cross(verts[jd] - verts[ju]).normalized()
				if nn.y < 0.0:
					nn = -nn
				norms.append(nn)
		for j in rows - 1:
			for i in seg:
				var a0 := start + j * (seg + 1) + i
				var b0 := a0 + 1
				var c0 := a0 + seg + 1
				var e0 := c0 + 1
				idx.append_array([a0, c0, b0, b0, c0, e0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Gipfelketten"
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.extra_cull_margin = 400.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/environment/alpine_backdrop.gdshader")
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	fn.fractal_octaves = 4
	nt.noise = fn
	mat.set_shader_parameter("noise_tex", nt)
	mi.material_override = mat
	parent.add_child(mi)
	return mi

## Material fuer Gelaende (und Felsen/Schneehaufen, die wie Gelaende aussehen sollen).
static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/environment/alpine_terrain.gdshader")
	var d := "res://assets/environment/textures/"
	m.set_shader_parameter("snow_albedo", load(d + "snow_02/diffuse.jpg"))
	m.set_shader_parameter("snow_normal", load(d + "snow_02/normal.jpg"))
	m.set_shader_parameter("drift_albedo", load(d + "snow_field_aerial/diffuse.jpg"))
	m.set_shader_parameter("drift_normal", load(d + "snow_field_aerial/normal.jpg"))
	m.set_shader_parameter("rock_albedo", load(d + "rock_face_03/diffuse.jpg"))
	m.set_shader_parameter("rock_normal", load(d + "rock_face_03/normal.jpg"))
	m.set_shader_parameter("rock_arm", load(d + "rock_face_03/arm.jpg"))
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	nt.noise = fn
	m.set_shader_parameter("noise_tex", nt)
	return m
