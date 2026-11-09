extends Node3D
## Stilisierte 3D-Lagekarte des Baltikums fuer das Intro.
## Konturen aus Natural Earth (map_data.gd, Public Domain), exakt zugeschnitten und trianguliert zur Laufzeit.
## Ablauf wird vom Director (intro.gd) per Methodenaufruf gesteuert; tick(t) bewegt die Kamera.

const MapData = preload("res://game/intro/map_data.gd")
const LINE_SHADER: Shader = preload("res://game/intro/map_line.gdshader")
const GRID_SHADER: Shader = preload("res://game/intro/map_grid.gdshader")

const LON0 := 25.5
const LAT0 := 57.0
const K := 12.0                       ## Einheiten pro Breitengrad
const RECT_LON := Vector2(17.5, 34.0)
const RECT_LAT := Vector2(53.2, 60.6)
const LINE_W := 0.22
const COL_LINE := Color(0.25, 0.8, 1.0)
const COL_RED := Color(1.0, 0.12, 0.08)
const COL_BLUE := Color(0.2, 0.5, 1.0)

const LAND_COLORS := {
	"LVA": Color(0.07, 0.15, 0.19),
	"default": Color(0.045, 0.07, 0.09),
}
const COUNTRY_LABELS: Array = [
	["LETTLAND", 25.6, 56.85, 1.5], ["ESTLAND", 25.6, 58.75, 1.0], ["LITAUEN", 23.9, 55.35, 1.0],
	["RUSSLAND", 31.2, 57.6, 1.25], ["BELARUS", 28.4, 54.4, 1.0], ["POLEN", 21.5, 53.65, 0.9],
	["FINNLAND", 26.0, 60.45, 0.9], ["OSTSEE", 19.6, 57.4, 1.1], ["Rigaer Bucht", 23.35, 57.55, 0.6],
]
const CITIES: Array = [
	["Riga", 24.11, 56.95], ["Daugavpils", 26.53, 55.87], ["Rēzekne", 27.33, 56.51], ["Tallinn", 24.75, 59.44],
	["Vilnius", 25.28, 54.69], ["Pskow", 28.33, 57.82], ["Minsk", 27.56, 53.9], ["Kaliningrad", 20.51, 54.71],
	["Tartu", 26.72, 58.38], ["Valmiera", 25.43, 57.54],
]
const RED_ARROWS: Array = [
	[[28.9, 57.8], [27.9, 57.35], [26.6, 57.15], [25.0, 57.0]],
	[[29.6, 56.75], [28.3, 56.55], [27.2, 56.45], [26.1, 56.5]],
	[[29.5, 56.15], [28.2, 55.98], [27.2, 55.9], [26.75, 55.9]],
]
const BLUE_ARROWS: Array = [
	[[23.6, 54.85], [24.6, 55.45], [25.6, 55.8], [26.2, 55.88]],
	[[20.4, 57.75], [22.0, 57.45], [23.2, 57.15], [23.95, 57.0]],
	[[24.9, 59.1], [25.4, 58.45], [25.9, 57.85], [26.25, 57.4]],
	[[22.0, 56.2], [23.4, 56.35], [24.6, 56.55], [25.6, 56.6]],
]
const RED_UNITS: Array = [[29.6, 57.95], [30.1, 56.95], [29.9, 56.25], [30.6, 57.5], [29.2, 58.4]]
const KG_NORD := Vector2(27.85, 56.3)

var cam: Camera3D
var env: Environment

var _rect: PackedVector2Array
var _fill_mats: Dictionary = {}       ## code -> StandardMaterial3D
var _line_mats: Array[ShaderMaterial] = []
var _grid_mat: ShaderMaterial
var _labels: Array[Label3D] = []
var _arrows: Array[Dictionary] = []
var _units_red: Array[Node3D] = []
var _kg: Node3D
var _kg_mat: ShaderMaterial
var _t: float = 0.0

# Kamera-Schluesselbilder: [Zeit, Ziel (lon, lat), Abstand-Offset]
var _keys: Array = [
	[0.0, Vector2(25.6, 56.9), Vector3(0, 96, 52)],
	[8.0, Vector2(25.8, 56.9), Vector3(0, 80, 46)],
	[17.0, Vector2(26.9, 56.7), Vector3(-2, 50, 32)],
	[24.0, Vector2(27.4, 56.4), Vector3(-5, 36, 26)],
	[28.0, Vector2(25.6, 56.8), Vector3(0, 70, 44)],
	[37.0, Vector2(25.4, 56.8), Vector3(0, 64, 40)],
]

static func proj(lon: float, lat: float) -> Vector2:
	return Vector2((lon - LON0) * cos(deg_to_rad(LAT0)) * K, -(lat - LAT0) * K)

static func p3(lon: float, lat: float, y: float = 0.0) -> Vector3:
	var p := proj(lon, lat)
	return Vector3(p.x, y, p.y)

func _ready() -> void:
	var a := proj(RECT_LON.x, RECT_LAT.y)
	var b := proj(RECT_LON.y, RECT_LAT.x)
	_rect = PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y)])
	env = _make_env()
	_build_sea()
	_build_countries()
	_build_lakes()
	_build_labels()
	_build_units()
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 600.0
	add_child(cam)
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

func activate() -> void:
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	cam.environment = env
	cam.make_current()
	tick(0.0)

# --------------------------------------------------------------------------- Ablauf (vom Director)

## Grenzlinien zeichnen sich ein, Meer und Beschriftung blenden auf.
func reveal(duration: float = 3.0) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_set_reveal, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_grid_mat, "shader_parameter/fade_in", 1.0, duration * 0.7)
	for l in _labels:
		tw.tween_property(l, "modulate:a", float(l.get_meta("alpha", 0.8)), 1.2).set_delay(duration * 0.6 + randf() * 0.6)

func show_red_units() -> void:
	var tw := create_tween().set_parallel(true)
	for code: String in ["RUS", "BLR"]:
		if _fill_mats.has(code):
			tw.tween_property(_fill_mats[code], "albedo_color", Color(0.13, 0.035, 0.035), 2.0)
	for i in _units_red.size():
		var u := _units_red[i]
		u.visible = true
		u.scale = Vector3.ONE * 0.01
		tw.tween_property(u, "scale", Vector3.ONE, 0.35).set_delay(i * 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func start_red_arrows() -> void:
	for i in RED_ARROWS.size():
		_add_arrow(RED_ARROWS[i], COL_RED, 1.5, i * 0.8, 6.5)

func show_kg_nord() -> void:
	_kg.visible = true
	_kg.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(_kg, "scale", Vector3.ONE * 1.15, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_kg_mat.set_shader_parameter("pulse", 1.0)

func start_blue_arrows() -> void:
	for i in BLUE_ARROWS.size():
		_add_arrow(BLUE_ARROWS[i], COL_BLUE, 1.3, i * 0.6, 5.5)

func fade_out(duration: float) -> void:
	var tw := create_tween()
	tw.tween_method(_set_alpha, 1.0, 0.0, duration)

func tick(t: float) -> void:
	_t = t
	# Kamera zwischen Schluesselbildern
	var i := 0
	while i < _keys.size() - 2 and t > float(_keys[i + 1][0]):
		i += 1
	var k0: Array = _keys[i]
	var k1: Array = _keys[i + 1]
	var f := clampf((t - float(k0[0])) / maxf(float(k1[0]) - float(k0[0]), 0.001), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var g0: Vector2 = k0[1]
	var g1: Vector2 = k1[1]
	var tgt := p3(lerpf(g0.x, g1.x, f), lerpf(g0.y, g1.y, f))
	var off: Vector3 = (k0[2] as Vector3).lerp(k1[2], f)
	cam.position = tgt + off
	cam.look_at(tgt, Vector3.UP)
	_update_arrows(t)

# --------------------------------------------------------------------------- Aufbau

func _make_env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.0, 0.006, 0.014)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.4, 0.5)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 1.1
	e.glow_bloom = 0.15
	e.glow_hdr_threshold = 0.7
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(0.0, 0.01, 0.02)
	e.fog_depth_begin = 90.0
	e.fog_depth_end = 220.0
	return e

func _line_mat(col: Color, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LINE_SHADER
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("reveal", 0.0)
	_line_mats.append(m)
	return m

func _set_reveal(v: float) -> void:
	for m in _line_mats:
		if not m.has_meta("fixed"):
			m.set_shader_parameter("reveal", v)

func _set_alpha(v: float) -> void:
	for m in _line_mats:
		m.set_shader_parameter("alpha", v)
	_grid_mat.set_shader_parameter("fade_in", v)
	for l in _labels:
		l.modulate.a = minf(l.modulate.a, v)

func _build_sea() -> void:
	_grid_mat = ShaderMaterial.new()
	_grid_mat.shader = GRID_SHADER
	_grid_mat.set_shader_parameter("fade_in", 0.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = _grid_mat
	mi.position = Vector3(0, -0.05, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _ring_to_2d(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		out.append(proj(float(flat[i]), float(flat[i + 1])))
	return out

func _clip(poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var res: Array[PackedVector2Array] = []
	for p in Geometry2D.intersect_polygons(poly, _rect):
		res.append(p)
	return res

func _on_rect_edge(a: Vector2, b: Vector2) -> bool:
	var e := 0.05
	var x0 := _rect[0].x
	var x1 := _rect[1].x
	var z0 := _rect[0].y
	var z1 := _rect[2].y
	if absf(a.x - x0) < e and absf(b.x - x0) < e:
		return true
	if absf(a.x - x1) < e and absf(b.x - x1) < e:
		return true
	if absf(a.y - z0) < e and absf(b.y - z0) < e:
		return true
	if absf(a.y - z1) < e and absf(b.y - z1) < e:
		return true
	return false

func _build_countries() -> void:
	for code: String in MapData.COUNTRIES:
		var col: Color = LAND_COLORS.get(code, LAND_COLORS["default"])
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = col
		_fill_mats[code] = fm
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var lines: Array[PackedVector2Array] = []
		var any := false
		for ring: Array in MapData.COUNTRIES[code]:
			for poly in _clip(_ring_to_2d(ring)):
				var idx := Geometry2D.triangulate_polygon(poly)
				if idx.is_empty():
					continue
				any = true
				for j in idx:
					st.add_vertex(Vector3(poly[j].x, 0.0, poly[j].y))
				lines.append_array(_split_outline(poly))
		if not any:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = fm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var hl := code == "LVA"
		var lm := _line_mat(Color(0.55, 0.95, 1.0) if hl else COL_LINE, 2.6 if hl else 1.1)
		_add_ribbons(lines, LINE_W * (1.5 if hl else 1.0), 0.06 if hl else 0.04, lm)

## Umriss ohne Kanten am Kartenrand, als Liste offener Polylinien.
func _split_outline(poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var n := poly.size()
	# Start an einer Randkante, damit Linien nicht mittendrin umbrechen
	var start := 0
	for i in n:
		if _on_rect_edge(poly[i], poly[(i + 1) % n]):
			start = (i + 1) % n
			break
	var cur := PackedVector2Array()
	for k in n + 1:
		var i := (start + k) % n
		var j := (i + 1) % n
		if k == n or _on_rect_edge(poly[i], poly[j]):
			if cur.size() >= 2:
				out.append(cur)
			cur = PackedVector2Array()
			continue
		if cur.is_empty():
			cur.append(poly[i])
		cur.append(poly[j])
	if cur.size() >= 2:
		out.append(cur)
	return out

func _build_lakes() -> void:
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.012, 0.03, 0.055)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines: Array[PackedVector2Array] = []
	for ring: Array in MapData.LAKES:
		for poly in _clip(_ring_to_2d(ring)):
			var idx := Geometry2D.triangulate_polygon(poly)
			for j in idx:
				st.add_vertex(Vector3(poly[j].x, 0.02, poly[j].y))
			lines.append_array(_split_outline(poly))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = fm
	add_child(mi)
	_add_ribbons(lines, LINE_W * 0.7, 0.05, _line_mat(COL_LINE, 0.7))

## Polylinien als flache Baender (ein Mesh). UV.x = relative Laenge je Linie.
func _add_ribbons(lines: Array[PackedVector2Array], w: float, y: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for pl in lines:
		count += _ribbon_into(st, pl, w, w, y)
	if count == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _ribbon_into(st: SurfaceTool, pl: PackedVector2Array, w0: float, w1: float, y: float, len_override: float = -1.0) -> int:
	var n := pl.size()
	if n < 2:
		return 0
	var cum := PackedFloat32Array()
	cum.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + pl[i].distance_to(pl[i - 1])
	var total := maxf(cum[n - 1], 0.001) if len_override <= 0.0 else len_override
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in n:
		var d: Vector2
		if i == 0:
			d = pl[1] - pl[0]
		elif i == n - 1:
			d = pl[n - 1] - pl[n - 2]
		else:
			d = (pl[i + 1] - pl[i]).normalized() + (pl[i] - pl[i - 1]).normalized()
		d = d.normalized()
		var nrm := Vector2(-d.y, d.x)
		var w := lerpf(w0, w1, cum[i] / total) * 0.5
		left.append(Vector3(pl[i].x + nrm.x * w, y, pl[i].y + nrm.y * w))
		right.append(Vector3(pl[i].x - nrm.x * w, y, pl[i].y - nrm.y * w))
	for i in n - 1:
		var u0 := cum[i] / total
		var u1 := cum[i + 1] / total
		st.set_uv(Vector2(u0, 0)); st.add_vertex(left[i])
		st.set_uv(Vector2(u0, 1)); st.add_vertex(right[i])
		st.set_uv(Vector2(u1, 0)); st.add_vertex(left[i + 1])
		st.set_uv(Vector2(u1, 0)); st.add_vertex(left[i + 1])
		st.set_uv(Vector2(u0, 1)); st.add_vertex(right[i])
		st.set_uv(Vector2(u1, 1)); st.add_vertex(right[i + 1])
	return n

func _label(text: String, pos: Vector3, size: float, col: Color, alpha: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _font()
	l.font_size = 96
	l.pixel_size = 0.012 * size
	l.outline_size = 0
	l.modulate = Color(col.r, col.g, col.b, 0.0)
	l.set_meta("alpha", alpha)
	l.shaded = false
	l.double_sided = true
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = pos
	add_child(l)
	_labels.append(l)
	return l

static func _font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Segoe UI", "Arial"])
	f.font_weight = 600
	return f

func _build_labels() -> void:
	for e: Array in COUNTRY_LABELS:
		var water := str(e[0]) == "OSTSEE" or str(e[0]) == "Rigaer Bucht"
		var c := Color(0.55, 0.85, 1.0) if not water else Color(0.3, 0.55, 0.75)
		if str(e[0]) == "LETTLAND":
			c = Color(0.85, 0.97, 1.0)
		_label(str(e[0]), p3(float(e[1]), float(e[2]), 0.12), float(e[3]), c, 0.85 if not water else 0.6)
	var dot_m := StandardMaterial3D.new()
	dot_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_m.albedo_color = Color(0.9, 0.97, 1.0)
	for c: Array in CITIES:
		var p := p3(float(c[1]), float(c[2]), 0.1)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.28
		cm.bottom_radius = 0.28
		cm.height = 0.05
		cm.radial_segments = 12
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = dot_m
		mi.position = p
		add_child(mi)
		var l := _label(str(c[0]), p + Vector3(0.5, 0.02, -0.5), 0.42, Color(0.8, 0.9, 0.95), 0.75)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.offset = Vector2(l.font_size * 0.2, 0)

## Taktisches Zeichen: Rechteck mit Ellipse (Panzer) als Leuchtlinie.
func _unit_symbol(center: Vector3, col: Color, w: float, h: float, mat: ShaderMaterial) -> Node3D:
	var root := Node3D.new()
	root.position = center
	add_child(root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lw := 0.2
	var rect := PackedVector2Array([Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h), Vector2(-w, -h)])
	_ribbon_into(st, rect, lw, lw, 0.0)
	var ell := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		ell.append(Vector2(cos(a) * w * 0.62, sin(a) * h * 0.5))
	_ribbon_into(st, ell, lw * 0.8, lw * 0.8, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
	# dunkle Fuellung, damit das Zeichen lesbar bleibt
	var bg := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 2.0, h * 2.0)
	bg.mesh = pm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = col * 0.15
	bg.material_override = bm
	bg.position = Vector3(0, -0.02, 0)
	root.add_child(bg)
	root.visible = false
	return root

func _build_units() -> void:
	var rm := _line_mat(COL_RED, 2.2)
	rm.set_meta("fixed", true)
	rm.set_shader_parameter("reveal", 1.0)
	for u: Array in RED_UNITS:
		_units_red.append(_unit_symbol(p3(float(u[0]), float(u[1]), 0.15), COL_RED, 1.0, 0.65, rm))
	_kg_mat = _line_mat(Color(0.35, 0.65, 1.0), 2.6)
	_kg_mat.set_meta("fixed", true)
	_kg_mat.set_shader_parameter("reveal", 1.0)
	_kg = _unit_symbol(p3(KG_NORD.x, KG_NORD.y, 0.2), COL_BLUE, 1.0, 0.65, _kg_mat)
	var l := Label3D.new()
	l.text = "KG NORD"
	l.font = _font()
	l.font_size = 96
	l.pixel_size = 0.0075
	l.outline_size = 0
	l.modulate = Color(0.6, 0.85, 1.0)
	l.shaded = false
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = Vector3(0, 0.05, 1.25)
	_kg.add_child(l)

# --------------------------------------------------------------------------- Pfeile

func _catmull(pts: Array, samples: int) -> PackedVector2Array:
	var p: Array[Vector2] = []
	for q: Array in pts:
		p.append(proj(float(q[0]), float(q[1])))
	var out := PackedVector2Array()
	var segs := p.size() - 1
	for s in segs:
		var p0: Vector2 = p[maxi(s - 1, 0)]
		var p1: Vector2 = p[s]
		var p2: Vector2 = p[s + 1]
		var p3_: Vector2 = p[mini(s + 2, p.size() - 1)]
		for i in samples:
			var t := float(i) / samples
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3_) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3_) * t3))
	out.append(p[p.size() - 1])
	return out

func _add_arrow(pts: Array, col: Color, width: float, delay: float, dur: float) -> void:
	var m := _line_mat(col, 2.4)
	m.set_meta("fixed", true)
	m.set_shader_parameter("reveal", 1.0)
	m.set_shader_parameter("pulse", 0.6)
	var mi := MeshInstance3D.new()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var curve := _catmull(pts, 14)
	var total := 0.0
	for i in range(1, curve.size()):
		total += curve[i].distance_to(curve[i - 1])
	_arrows.append({"mi": mi, "curve": curve, "len": total, "w": width, "t0": _t + delay, "dur": dur, "done": false})

func _update_arrows(t: float) -> void:
	for a in _arrows:
		if a["done"]:
			continue
		var k := clampf((t - float(a["t0"])) / float(a["dur"]), 0.0, 1.0)
		if k <= 0.0:
			continue
		k = 1.0 - pow(1.0 - k, 2.2)
		var curve: PackedVector2Array = a["curve"]
		var want := float(a["len"]) * k
		var pl := PackedVector2Array([curve[0]])
		var acc := 0.0
		for i in range(1, curve.size()):
			var seg := curve[i].distance_to(curve[i - 1])
			if acc + seg >= want:
				pl.append(curve[i - 1].lerp(curve[i], (want - acc) / maxf(seg, 0.0001)))
				break
			acc += seg
			pl.append(curve[i])
		if pl.size() < 2 or want < 0.3:
			continue
		var w: float = a["w"]
		var head_len := w * 1.8
		# Koerper endet vor der Spitze
		var tip := pl[pl.size() - 1]
		var dir := (tip - pl[pl.size() - 2]).normalized()
		var body := pl.duplicate()
		body[body.size() - 1] = tip - dir * head_len * 0.9
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_ribbon_into(st, body, w * 0.45, w, 0.25 + k * 0.001)
		var nrm := Vector2(-dir.y, dir.x)
		var base := tip - dir * head_len
		var y := 0.26
		st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(base.x + nrm.x * w * 1.1, y, base.y + nrm.y * w * 1.1))
		st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(base.x - nrm.x * w * 1.1, y, base.y - nrm.y * w * 1.1))
		st.set_uv(Vector2(1, 0.5)); st.add_vertex(Vector3(tip.x, y, tip.y))
		(a["mi"] as MeshInstance3D).mesh = st.commit()
		if k >= 1.0:
			a["done"] = true
