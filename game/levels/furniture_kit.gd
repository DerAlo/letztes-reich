extends RefCounted
## Moebel-Kit: echte Poly-Haven-Modelle (CC0, 1k-Texturen) statt grauer Quader fuer Innenraeume.
## Aufruf aus den Level-Skripten: Kollision bleibt Sache des Aufrufers (gleiche Box wie vorher, damit
## Deckung und Navmesh unveraendert bleiben); place() setzt nur die Optik und liefert false, wenn das
## Modell fehlt - dann zeichnet der Aufrufer wie bisher seinen Quader.
##
## Einpassen: Das Modell wird (nach Drehung um yaw/tilt) gleichmaessig mit dem Median der Achsverhaeltnisse
## Box/Modell skaliert (begrenzt auf SCALE_MIN..SCALE_MAX, oder fest per opts.scale), danach je Achse um
## hoechstens STRETCH an die Box angenaehert, mittig auf die Grundflaeche und mit der Unterkante auf den
## Boden der Box gesetzt. Front der Modelle zeigt bei yaw 0
## nach +Z (Poly-Haven-Konvention, Blender -Y).

const DIR := "res://assets/props/furniture/"

## Modellname -> glTF (Ordner assets/props/furniture/<name>/<name>.gltf)
const MODELS := [
	"sofa_03", "sofa_02", "gothic_coffee_table", "GothicCabinet_01", "ClassicConsole_01", "WoodenTable_01",
	"GreenChair_01", "ArmChair_01", "dining_chair_02", "modern_wooden_cabinet", "vintage_cabinet_01",
	"metal_office_desk", "wooden_table_02",
]

const STRETCH := 1.15   ## maximale Abweichung je Achse von der gleichmaessigen Skalierung
const SCALE_MIN := 0.8  ## Moebel bleiben nahe Originalgroesse (Realismus vor exakter Box-Fuellung)
const SCALE_MAX := 1.25

static var _parts: Dictionary = {}
static var _bounds: Dictionary = {}

## Mesh-Teile [{mesh, xf}] eines Modells (einmal geladen, von allen Instanzen geteilt). Leer, wenn die Datei fehlt.
static func parts(mname: String) -> Array:
	if _parts.has(mname):
		return _parts[mname]
	var out: Array = []
	# Modelle ausserhalb von DIR: voller Ordnerpfad "res://.../<name>" (Datei <name>/<name>.gltf)
	var path := (mname if mname.begins_with("res://") else DIR + mname) + "/" + mname.get_file() + ".gltf"
	# --no-furniture: alte Quader (Vorher-Bilder, Fallback-Test)
	if not OS.get_cmdline_user_args().has("--no-furniture") and ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
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
		out.append({"mesh": (n as MeshInstance3D).mesh, "xf": t})
	for c in n.get_children():
		_collect(c, t, out, false)

static func has(mname: String) -> bool:
	return not parts(mname).is_empty()

## Achsenparallele Huelle des Modells nach Drehung rot (Modellursprung bleibt Ursprung).
static func _aabb(mname: String, rot: Basis) -> AABB:
	var key := "%s|%s" % [mname, str(rot)]
	if _bounds.has(key):
		return _bounds[key]
	var box := AABB()
	var first := true
	for p: Dictionary in parts(mname):
		var xf := Transform3D(rot, Vector3.ZERO) * (p.xf as Transform3D)
		var b: AABB = xf * (p.mesh as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	_bounds[key] = box
	return box

## Setzt Modell mname in die Box (Mitte c, Groesse s, achsenparallel) unter parent.
## yaw_deg dreht die Front (0 = +Z, 90 = +X, -90 = -X, 180 = -Z). opts:
##   tilt: Vector3 (Grad, z. B. umgekippter Tisch), scale: float (feste Skalierung statt Einpassen),
##   stretch: float (max. Achsenabweichung, 1.0 = streng gleichmaessig), shadows: bool, vis: float (Sichtweite).
## Liefert false, wenn das Modell fehlt (Aufrufer zeichnet dann den alten Quader).
static func place(parent: Node3D, mname: String, c: Vector3, s: Vector3, yaw_deg: float = 0.0, opts: Dictionary = {}) -> bool:
	var ps := parts(mname)
	if ps.is_empty():
		return false
	var tilt: Vector3 = opts.get("tilt", Vector3.ZERO)
	var rot := Basis.from_euler(Vector3(deg_to_rad(tilt.x), deg_to_rad(yaw_deg), deg_to_rad(tilt.z)), EULER_ORDER_YXZ)
	var bb := _aabb(mname, rot)
	var sz := bb.size
	var r := Vector3(s.x / maxf(sz.x, 0.001), s.y / maxf(sz.y, 0.001), s.z / maxf(sz.z, 0.001))
	# Gleichmaessige Skalierung: Median der Achsverhaeltnisse, auf realistische Groessen begrenzt
	var med := r.x + r.y + r.z - minf(r.x, minf(r.y, r.z)) - maxf(r.x, maxf(r.y, r.z))
	var u: float = float(opts["scale"]) if opts.has("scale") else clampf(med, SCALE_MIN, SCALE_MAX)
	var st: float = float(opts.get("stretch", STRETCH))
	var k := Vector3(u * clampf(r.x / u, 1.0 / st, st), u * clampf(r.y / u, 1.0 / st, st), u * clampf(r.z / u, 1.0 / st, st))
	# Skalierte Huelle: Unterkante auf Boxboden, Grundflaechenmitte auf Boxmitte
	var lo := bb.position * k
	var hi := bb.end * k
	var off := Vector3(c.x - (lo.x + hi.x) * 0.5, c.y - s.y * 0.5 - lo.y, c.z - (lo.z + hi.z) * 0.5)
	var root_xf := Transform3D(Basis.from_scale(k) * rot, off)
	var root := Node3D.new()
	root.name = "Furn_" + mname.get_file()
	root.transform = root_xf
	var shadows: bool = bool(opts.get("shadows", true))
	var vis: float = float(opts.get("vis", 0.0))
	for p: Dictionary in ps:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.transform = p.xf
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis > 0.0:
			mi.visibility_range_end = vis
			mi.visibility_range_end_margin = 4.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
	parent.add_child(root)
	return true

## Bequemlichkeit fuer Ecken-Notation (a, b = gegenueberliegende Ecken der alten Box).
static func place_ab(parent: Node3D, mname: String, a: Vector3, b: Vector3, yaw_deg: float = 0.0, opts: Dictionary = {}) -> bool:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	return place(parent, mname, (lo + hi) * 0.5, hi - lo, yaw_deg, opts)

# ================================================================== Buecherregale
## Bibliotheksregal "wooden_bookshelf_worn" (Poly Haven, CC0) in Reihe entlang einer Wand, gefuellt mit
## Buechern. Die Buecher sind einfache Quader mit Rueckentexturen aus "book_encyclopedia_set_01" (Poly Haven,
## CC0; Ruecken-Streifen des Cover-Atlas) und werden als MultiMesh je Rueckenvariante gezeichnet. Farbe,
## Goldpraegung, Glanz und Ausbleichen je Buch ueber Instanzfarbe/INSTANCE_CUSTOM (BOOK_SHADER), Hoehe und
## Dicke je Buch. Pro Fach: Reihen und Einzelbaende mit Luecken, liegende Stapel, angelehnte Buecher. c/s = alte Box (achsenparallel), yaw_deg = Front (wie place()).
## Liefert false, wenn das Regalmodell fehlt (Aufrufer zeichnet dann wie bisher).
const SHELF := "wooden_bookshelf_worn"
const BOOK_DIR := "res://assets/props/furniture/book_encyclopedia_set_01/textures/book_encyclopedia_set_01_cover_"
const SHELF_W := 1.374      ## Modellmasse (Ursprung Boden-Mitte, Front +Z)
const SHELF_H := 2.063
const SHELF_D := 0.581
const SHELF_IN_X := 0.6     ## halbe lichte Breite der Faecher
const SHELF_IN_Z := 0.27    ## halbe lichte Tiefe
const SHELF_FLOORS := [0.11, 0.39, 0.67, 0.96, 1.28, 1.66]   ## Brett-Oberkanten (Modell)
const SHELF_CEILS := [0.35, 0.63, 0.92, 1.23, 1.62, 2.02]    ## Unterkante des naechsten Bretts
const BOOK_VARIANTS := 6
const BOOK_TINTS := [
	Color(1.0, 1.0, 1.0), Color(1.0, 0.92, 0.82), Color(0.78, 0.32, 0.26), Color(0.42, 0.55, 0.38),
	Color(0.38, 0.44, 0.62), Color(0.42, 0.38, 0.36), Color(0.62, 0.5, 0.36),
]
## Einbandfarben fuer Einzelbaende und Leinenausgaben (Zielalbedo: BOOK_SHADER ersetzt den Lederton der
## Rueckentextur und behaelt nur deren Struktur).
const BOOK_COVERS := [
	Color(0.42, 0.07, 0.06), Color(0.3, 0.06, 0.07), Color(0.1, 0.2, 0.12), Color(0.16, 0.27, 0.18),
	Color(0.08, 0.11, 0.24), Color(0.15, 0.2, 0.34), Color(0.05, 0.05, 0.055), Color(0.12, 0.1, 0.09),
	Color(0.55, 0.42, 0.26), Color(0.72, 0.65, 0.5), Color(0.8, 0.76, 0.64), Color(0.34, 0.38, 0.42),
	Color(0.55, 0.38, 0.1), Color(0.3, 0.17, 0.09), Color(0.5, 0.3, 0.3), Color(0.24, 0.3, 0.3),
]
## Buchshader: INSTANCE_CUSTOM = (Umfaerben 0..1, Gold behalten 0..1, Glanz 0..1, Ausbleichen 0..1).
const BOOK_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D nor : hint_normal, filter_linear_mipmap_anisotropic;
varying vec4 cd;
void vertex() {
	cd = INSTANCE_CUSTOM;
}
void fragment() {
	vec4 t = texture(tex, UV);
	float l = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	float sat = max(t.r, max(t.g, t.b)) - min(t.r, min(t.g, t.b));
	// Goldpraegung/-baender der Vorlage: hell und gesaettigt
	float gold = smoothstep(0.3, 0.5, l) * smoothstep(0.18, 0.32, sat);
	// Einband: Farbe aus COLOR, Helligkeitsstruktur aus der Textur
	vec3 cover = COLOR.rgb * clamp(l / 0.26, 0.55, 1.45);
	vec3 base = mix(t.rgb * COLOR.rgb, cover, cd.x);
	// Gold behalten (cd.y = 1) oder als blinde Praegung abdunkeln (cd.y = 0)
	vec3 emb = mix(cover * 0.7, t.rgb * vec3(1.0, 0.92, 0.75), cd.y);
	base = mix(base, emb, gold * cd.x);
	// Ausbleichen/Staub
	base = mix(base, vec3(dot(base, vec3(0.333)) * 1.1 + 0.03), cd.w);
	ALBEDO = base;
	ROUGHNESS = mix(0.85, 0.42, cd.z);
	METALLIC = gold * cd.y * 0.5;
	NORMAL_MAP = texture(nor, UV).rgb;
}
"""

static var _book_meshes: Array = []

static func bookshelves(parent: Node3D, c: Vector3, s: Vector3, yaw_deg: float, max_h: float = 2.7, rng_seed: int = 1) -> bool:
	var ps := parts(SHELF)
	if ps.is_empty():
		return false
	var rot := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var along: Vector3 = rot * Vector3.RIGHT
	var side_x: bool = absf(along.x) > 0.5
	var length: float = s.x if side_x else s.z
	var depth: float = s.z if side_x else s.x
	var n: int = maxi(1, roundi(length / (SHELF_W * 1.12)))
	var k := Vector3(length / (n * SHELF_W), minf(s.y, max_h) / SHELF_H, clampf(depth / SHELF_D, 0.9, 1.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var books: Array = []
	for v in BOOK_VARIANTS:
		books.append([])
	var root := Node3D.new()
	root.name = "Bookshelves"
	parent.add_child(root)
	var floor_y: float = c.y - s.y * 0.5
	for i in n:
		var t: float = (float(i) + 0.5) / float(n) - 0.5
		var org := Vector3(c.x, floor_y, c.z) + along * (t * length)
		var sh := Node3D.new()
		sh.transform = Transform3D(rot * Basis.from_scale(k), org)
		for p: Dictionary in ps:
			var mi := MeshInstance3D.new()
			mi.mesh = p.mesh
			mi.transform = p.xf
			sh.add_child(mi)
		root.add_child(sh)
		for f in SHELF_FLOORS.size():
			_fill_shelf(books, rng, Transform3D(rot, org), k, float(SHELF_FLOORS[f]) * k.y, (float(SHELF_CEILS[f]) - float(SHELF_FLOORS[f])) * k.y)
	var meshes := _books()
	for v in BOOK_VARIANTS:
		var list: Array = books[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[v]
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j][0])
			mm.set_instance_color(j, list[j][1])
			mm.set_instance_custom_data(j, list[j][2])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	return true

## Ein Fach fuellen. base = Regalursprung (nur Drehung), k = Regalskalierung, fy = Fachboden (skaliert, ueber
## Regalboden), fh = lichte Fachhoehe. Buch-Quader: Ursprung Ruecken-unten-Mitte, Ruecken nach +Z.
## Eintrag je Buch: [Transform, Farbe, Custom] (Custom siehe BOOK_SHADER). Mischung aus Reihen
## (Lexikon-/Werkausgaben: gleiche Farbe und Hoehe) und Einzelbaenden (eigene Farbe, Hoehe, Dicke), dazu
## liegende Stapel, angelehnte und quer obenauf liegende Buecher.
static func _fill_shelf(books: Array, rng: RandomNumberGenerator, base: Transform3D, k: Vector3, fy: float, fh: float) -> void:
	var x0: float = -SHELF_IN_X * k.x + 0.01
	var x1: float = SHELF_IN_X * k.x - 0.01
	var zf: float = SHELF_IN_Z * k.z - 0.01
	var dmax: float = SHELF_IN_Z * 2.0 * k.z - 0.03
	# Manche Faecher nur teilweise belegt
	if rng.randf() < 0.18:
		if rng.randf() < 0.5:
			x0 += rng.randf_range(0.3, 0.7) * (x1 - x0)
		else:
			x1 -= rng.randf_range(0.3, 0.7) * (x1 - x0)
	var x: float = x0
	var run_left: int = 0          # verbleibende Baende der aktuellen Reihe (0 = Einzelbaende)
	var run_col := Color.WHITE
	var run_cd := Color(0, 0, 0, 0)
	var run_h: float = 0.25
	var run_t: float = 0.03
	var stand: Array = []          # [x_links, Dicke, Hoehe] stehender Buecher (fuer quer obenauf gelegte)
	while x < x1 - 0.02:
		var r := rng.randf()
		if run_left <= 0 and rng.randf() < 0.16:   # neue Reihe (Ausgabe in mehreren Baenden)
			run_left = rng.randi_range(4, 14)
			run_h = minf(rng.randf_range(0.2, 0.32), fh - 0.025)
			run_t = rng.randf_range(0.026, 0.045)
			if rng.randf() < 0.5:   # Lederausgabe mit Goldruecken nach Vorlage, leicht getoent
				run_col = BOOK_TINTS[rng.randi() % BOOK_TINTS.size()]
				run_cd = Color(rng.randf_range(0.0, 0.35), 1.0, rng.randf_range(0.3, 0.7), rng.randf_range(0.0, 0.12))
			else:                    # Leinenausgabe in eigener Farbe
				run_col = BOOK_COVERS[rng.randi() % BOOK_COVERS.size()]
				run_cd = Color(1.0, 1.0 if rng.randf() < 0.6 else 0.0, rng.randf_range(0.0, 0.4), rng.randf_range(0.0, 0.2))
		var v: int = rng.randi() % BOOK_VARIANTS
		var col: Color
		var cd: Color
		var h: float
		var t: float
		if run_left > 0:
			run_left -= 1
			col = run_col * rng.randf_range(0.93, 1.05)
			cd = run_cd
			h = clampf(run_h * rng.randf_range(0.985, 1.01), 0.12, fh - 0.02)
			t = run_t * rng.randf_range(0.9, 1.12)
		else:
			col = BOOK_COVERS[rng.randi() % BOOK_COVERS.size()] * rng.randf_range(0.8, 1.15)
			cd = Color(1.0, 1.0 if rng.randf() < 0.3 else 0.0, rng.randf_range(0.0, 0.6), rng.randf_range(0.0, 0.3))
			# Hoehen Oktav bis Quart, gelegentlich ein grosser Bildband; Dicke vom Heft bis zum Waelzer
			h = rng.randf_range(0.17, 0.27) if rng.randf() < 0.8 else rng.randf_range(0.27, 0.34)
			h = clampf(h, 0.12, fh - 0.02)
			t = rng.randf_range(0.016, 0.06) if rng.randf() < 0.85 else rng.randf_range(0.06, 0.085)
		col.a = 1.0
		if r < 0.045:   # Luecke
			x += rng.randf_range(0.04, 0.16)
			run_left = 0
			continue
		if r < 0.095 and x1 - x > 0.3:   # liegender Stapel (Baende verschieden gross, leicht verdreht)
			var lh: float = minf(rng.randf_range(0.2, 0.3), x1 - x - 0.02)
			var cnt: int = rng.randi_range(2, 6)
			var yy: float = 0.0
			for q in cnt:
				var th: float = rng.randf_range(0.02, 0.05)
				if yy + th > fh - 0.02:
					break
				var w: float = lh * rng.randf_range(0.82, 1.0)
				var d: float = clampf(w * 0.7, 0.13, dmax)
				var bl := Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)) * Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(th, w, d))
				var ol := Vector3(x + lh * 0.5 + w * 0.5 + rng.randf_range(-0.012, 0.012), fy + yy + th * 0.5, zf - rng.randf_range(0.0, 0.03))
				var cl: Color = BOOK_COVERS[rng.randi() % BOOK_COVERS.size()] * rng.randf_range(0.85, 1.1)
				cl.a = 1.0
				var cq := Color(1.0, 1.0 if rng.randf() < 0.3 else 0.0, rng.randf_range(0.0, 0.5), rng.randf_range(0.0, 0.25))
				books[rng.randi() % BOOK_VARIANTS].append([base * Transform3D(bl, ol), cl, cq])
				yy += th
			x += lh + rng.randf_range(0.02, 0.06)
			run_left = 0
			continue
		var dd: float = clampf(h * rng.randf_range(0.62, 0.76), 0.12, dmax)
		if r > 0.93 and x1 - x > 0.25 and run_left <= 0:   # angelehntes Buch, danach Luecke
			var a: float = rng.randf_range(0.15, 0.55)
			var ba := Basis(Vector3.BACK, -a) * Basis.from_scale(Vector3(t, h, dd))
			var oa := Vector3(x + t * 0.5 * cos(a), fy + t * 0.5 * sin(a), zf - 0.01)
			books[v].append([base * Transform3D(ba, oa), col, cd])
			x += t + h * sin(a) + rng.randf_range(0.02, 0.1)
			continue
		var b := Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)) * Basis.from_scale(Vector3(t, h, dd))
		var o := Vector3(x + t * 0.5, fy, zf - rng.randf_range(0.0, 0.03) - (0.0 if run_left > 0 else rng.randf_range(0.0, 0.02)))
		books[v].append([base * Transform3D(b, o), col, cd])
		stand.append([x, t, h])
		x += t + rng.randf_range(0.0, 0.004)
	# Gelegentlich ein Buch quer obenauf (auf mehreren stehenden Buechern, mit Luft zum naechsten Brett)
	if stand.size() > 8 and rng.randf() < 0.4:
		var w2: float = rng.randf_range(0.17, 0.24)
		var i0: int = rng.randi_range(0, stand.size() - 8)
		var xa: float = float(stand[i0][0])
		var hmax: float = 0.0
		var q2: int = i0
		while q2 < stand.size() and float(stand[q2][0]) < xa + w2:
			hmax = maxf(hmax, float(stand[q2][2]))
			q2 += 1
		var th2: float = rng.randf_range(0.022, 0.04)
		var last: Array = stand[q2 - 1]
		if hmax + th2 < fh - 0.015 and float(last[0]) + float(last[1]) >= xa + w2 * 0.6:
			var bl2 := Basis(Vector3.UP, rng.randf_range(-0.25, 0.25)) * Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(th2, w2, clampf(w2 * 0.7, 0.12, dmax)))
			var ol2 := Vector3(xa + w2, fy + hmax + th2 * 0.5 + 0.002, zf - rng.randf_range(0.0, 0.03))
			var c2: Color = BOOK_COVERS[rng.randi() % BOOK_COVERS.size()]
			books[rng.randi() % BOOK_VARIANTS].append([base * Transform3D(bl2, ol2), c2, Color(1.0, 0.0, 0.3, 0.1)])

## Buch-Quader je Rueckenvariante (Einheitsgroesse: x -0.5..0.5, y 0..1, z -1..0, Ruecken bei z = 0).
static func _books() -> Array:
	if not _book_meshes.is_empty():
		return _book_meshes
	var mat: Material
	if ResourceLoader.exists(BOOK_DIR + "diff_1k.jpg") and ResourceLoader.exists(BOOK_DIR + "nor_gl_1k.jpg"):
		var sh := Shader.new()
		sh.code = BOOK_SHADER
		var smat := ShaderMaterial.new()
		smat.shader = sh
		smat.set_shader_parameter("tex", load(BOOK_DIR + "diff_1k.jpg"))
		smat.set_shader_parameter("nor", load(BOOK_DIR + "nor_gl_1k.jpg"))
		mat = smat
	else:
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.45, 0.28, 0.16)
		fm.vertex_color_use_as_albedo = true
		fm.roughness = 0.75
		mat = fm
	var spines: Array = [0, 3, 7, 10, 14, 18]
	var g0 := Vector2(0.17, 0.262)   # Goldschnitt-Streifen fuer Schnittflaechen
	var g1 := Vector2(0.30, 0.268)
	var c0 := Vector2(0.02, 0.19)    # dunkles Leder fuer die Deckel
	var c1 := Vector2(0.14, 0.27)
	for v in BOOK_VARIANTS:
		var u0: float = 0.588 + float(spines[v]) * 0.02005 + 0.002
		var u1: float = u0 + 0.02005 - 0.004
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Ruecken (+Z), Text oben = kleines v
		_quad(st, Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0), Vector3.BACK,
			Vector2(u0, 0.150), Vector2(u1, 0.150), Vector2(u1, 0.018), Vector2(u0, 0.018))
		_quad(st, Vector3(0.5, 0, 0), Vector3(0.5, 0, -1), Vector3(0.5, 1, -1), Vector3(0.5, 1, 0), Vector3.RIGHT,
			Vector2(c0.x, c1.y), c1, Vector2(c1.x, c0.y), c0)
		_quad(st, Vector3(-0.5, 0, -1), Vector3(-0.5, 0, 0), Vector3(-0.5, 1, 0), Vector3(-0.5, 1, -1), Vector3.LEFT,
			Vector2(c0.x, c1.y), c1, Vector2(c1.x, c0.y), c0)
		_quad(st, Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), Vector3(0.5, 1, -1), Vector3(-0.5, 1, -1), Vector3.UP,
			g0, Vector2(g0.x, g1.y), g1, Vector2(g1.x, g0.y))
		_quad(st, Vector3(-0.5, 0, -1), Vector3(0.5, 0, -1), Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3.DOWN,
			g0, Vector2(g0.x, g1.y), g1, Vector2(g1.x, g0.y))
		_quad(st, Vector3(0.5, 0, -1), Vector3(-0.5, 0, -1), Vector3(-0.5, 1, -1), Vector3(0.5, 1, -1), Vector3.FORWARD,
			g0, Vector2(g0.x, g1.y), g1, Vector2(g1.x, g0.y))
		st.generate_tangents()
		var m := st.commit()
		m.surface_set_material(0, mat)
		_book_meshes.append(m)
	return _book_meshes

## Viereck a-b-c-d (von aussen gesehen gegen den Uhrzeigersinn) mit UVs; Godot-Vorderseite = im Uhrzeigersinn.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var vs: Array = [a, b, c, d]
	var us: Array = [ua, ub, uc, ud]
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_uv(us[i])
		st.add_vertex(vs[i])
