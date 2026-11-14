extends RefCounted
## Fernkulisse fuer Tag/Daemmerung (spreebogen, rail_yard): Gebaeudebloecke mit echter Wandtextur, Gesimsen,
## Sockel, Attika, Dachaufbauten und Satteldaechern; Fenster als prozedurales Raster im Shader
## (assets/environment/facade/far_facade.gdshader: Laibung per Parallaxe, Rahmen, Spiegelung, Vorhaenge, Licht,
## ausgebrannte Fenster mit Russfahne). Alles nur Optik, keine Kollision.
## Geometrie wird pro Wandtextur zu einem Mesh zusammengefasst (ein Material je Textur, Farbton/Typ/Zufall
## stehen in den Vertexdaten) -> wenige Draw Calls auch bei vielen Haeusern.
##
## Typen (KIND): altbau (Gruenderzeit, Kreuzstockfenster, Laeden im EG), platte (Plattenbau, Fugen),
## office (Buerobau, Fensterbaender), hall (Industriehalle, Sprossenfensterband oben),
## palace (Werkstein-Monumentalbau, Pilaster, Rustika-Sockel), plain (fensterlos).

const SHADER := preload("res://assets/environment/facade/far_facade.gdshader")
const FKit := preload("res://game/levels/facade_kit.gd")
const FTEX := "res://assets/environment/facade/textures/"
const BTEX := "res://assets/environment/berlin/textures/"
const RTEX := "res://assets/environment/rail/textures/"
const OTEX := "res://assets/textures/"

## Wandtexturen: Ordner (diffuse/normal/arm), Kacheln pro Meter
const TEX := {
	"brick": [FTEX + "red_brick_03", 0.42],
	"brick_old": [OTEX + "brick_wall_02", 0.3],
	"plaster": [FTEX + "painted_plaster_wall", 0.28],
	"plaster_old": [FTEX + "rough_plaster_broken", 0.3],
	"concrete": [FTEX + "precast_concrete_wall", 0.22],
	"concrete_old": [OTEX + "concrete_wall_008", 0.3],
	"panel": ["res://assets/environment/funkturm/textures/concrete_panels", 0.25],
	"sandstone": [BTEX + "large_sandstone_blocks", 0.2],
	"tile": [BTEX + "concrete_tile_facade", 0.22],
	"factory": [RTEX + "factory_wall", 0.25],
	"corrugated": [RTEX + "worn_corrugated_iron", 0.35],
}
static var _mats: Dictionary = {}

## Material je Wandtextur. opts: Shader-Parameter (lit_ratio, sky_tint, reflect_amt, emission_energy, grime ...).
static func material(tex: String, opts: Dictionary = {}) -> ShaderMaterial:
	var key := tex + "|" + str(opts)
	if _mats.has(key):
		return _mats[key]
	var v: Array = TEX.get(tex, TEX["concrete_old"])
	var dir: String = v[0]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("wall_albedo", load(dir + "/diffuse.jpg"))
	m.set_shader_parameter("wall_normal", load(dir + "/normal.jpg"))
	m.set_shader_parameter("wall_arm", load(dir + "/arm.jpg"))
	m.set_shader_parameter("noise_tex", FKit.noise_tex())
	m.set_shader_parameter("tex_scale", v[1])
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	_mats[key] = m
	return m

class Builder:
	const KIND := {"altbau": 0, "platte": 2, "office": 3, "hall": 4, "palace": 5, "plain": 6}
	## Achsabstand der Fenster je Typ (muss zu far_facade.gdshader passen) und Eckpfeiler ohne Fenster
	const CELL_X := {0: 2.7, 2: 3.0, 3: 1.5, 4: 1.6, 5: 3.4, 6: 1.0}
	const PIER := {0: 1.0, 2: 0.6, 3: 0.5, 4: 2.0, 5: 1.4, 6: 0.0}
	const GROUND := {0: 4.4, 2: 0.0, 3: 4.6, 4: 0.0, 5: 6.0, 6: 0.0}
	var _st: Dictionary = {}       ## tex -> SurfaceTool
	var _count: int = 0

	func _surf(tex: String) -> SurfaceTool:
		if not _st.has(tex):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
			_st[tex] = st
		return _st[tex]

	## Viereck: p = [unten links, oben links, oben rechts, unten rechts] von aussen gesehen.
	func _quad(st: SurfaceTool, p: Array, uv: Array, n: Vector3, uv2: Vector2, col: Color, cust: Color) -> void:
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uv[i])
			st.set_uv2(uv2)
			st.set_custom(0, cust)
			st.add_vertex(p[i])
		_count += 1

	func _tri(st: SurfaceTool, p: Array, uv: Array, n: Vector3, col: Color, cust: Color) -> void:
		for i in 3:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uv[i])
			st.set_uv2(Vector2(0.0, -1.0))
			st.set_custom(0, cust)
			st.add_vertex(p[i])

	## Senkrechte Wandflaeche: Mitte c, Aussennormale n (waagerecht), Breite w, Hoehe h.
	## base_y = Fuss des Gebaeudes (v-Koordinate), u0 = u-Wert der Flaechenmitte, uv2 = (Fensterzone, Wandhoehe).
	func wall(tex: String, c: Vector3, n: Vector3, w: float, h: float, base_y: float, u0: float, uv2: Vector2, col: Color, cust: Color) -> void:
		var t := Vector3.UP.cross(n).normalized()
		var hw := t * (w * 0.5)
		var hh := Vector3.UP * (h * 0.5)
		var v0 := -(c.y - base_y)
		var p := [c - hw - hh, c - hw + hh, c + hw + hh, c + hw - hh]
		var uv := [Vector2(u0 - w * 0.5, v0 + h * 0.5), Vector2(u0 - w * 0.5, v0 - h * 0.5),
			Vector2(u0 + w * 0.5, v0 - h * 0.5), Vector2(u0 + w * 0.5, v0 + h * 0.5)]
		_quad(_surf(tex), p, uv, n, uv2, col, cust)

	## Waagerechte Flaeche nach oben (Dach, Gesimsoberseite).
	func top(tex: String, c: Vector3, sx: float, sz: float, col: Color, cust: Color) -> void:
		var a := Vector3(sx * 0.5, 0, 0)
		var b := Vector3(0, 0, sz * 0.5)
		var p := [c - a + b, c - a - b, c + a - b, c + a + b]
		var uv: Array = []
		for q: Vector3 in p:
			uv.append(Vector2(q.x, q.z))
		_quad(_surf(tex), p, uv, Vector3.UP, Vector2(0.0, -1.0), col, cust)

	## Unterseite (auskragende Gesimse, sonst sieht man von unten hindurch).
	func bottom(tex: String, c: Vector3, sx: float, sz: float, col: Color, cust: Color) -> void:
		var a := Vector3(sx * 0.5, 0, 0)
		var b := Vector3(0, 0, sz * 0.5)
		var p := [c - a - b, c - a + b, c + a + b, c + a - b]
		var uv: Array = []
		for q: Vector3 in p:
			uv.append(Vector2(q.x, q.z))
		_quad(_surf(tex), p, uv, Vector3.DOWN, Vector2(0.0, -1.0), col, cust)

	## Achsparallele Box ohne Fenster (Gesims, Attika, Aufbau). part: 1 Gesims, 3 Sockel, 0 Wand ohne Fenster.
	func plain_box(tex: String, c: Vector3, s: Vector3, base_y: float, col: Color, cust: Color, roof_col: Color = Color(-1, 0, 0), under: bool = false) -> void:
		for n: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			var w := s.x if absf(n.z) > 0.5 else s.z
			var d := s.z if absf(n.z) > 0.5 else s.x
			wall(tex, c + n * (d * 0.5), n, w, s.y, base_y, 0.0, Vector2(0.0, -1.0), col, cust)
		var rc := cust
		var rcol := col
		if roof_col.r >= 0.0:
			rc = Color(cust.r, 2.0, cust.b, cust.a)
			rcol = roof_col
		top(tex, c + Vector3.UP * (s.y * 0.5), s.x, s.z, rcol, rc)
		if under:
			bottom(tex, c - Vector3.UP * (s.y * 0.5), s.x, s.z, col, cust)

	## Zylinder/Kegelstumpf (Schornstein, Saeule, Turm). part 0 ohne Fenster (Typ plain).
	func tube(tex: String, base: Vector3, r0: float, r1: float, h: float, col: Color, seed_v: float, segs: int = 12, cap_col: Color = Color(-1, 0, 0)) -> void:
		var st := _surf(tex)
		var cust := Color(seed_v, 0.0, 0.0, 0.0)
		var kc := Color(col.r, col.g, col.b, 6.0 / 16.0)
		var circ := TAU * (r0 + r1) * 0.5
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var d0 := Vector3(sin(a0), 0, cos(a0))
			var d1 := Vector3(sin(a1), 0, cos(a1))
			var u0 := circ * float(i) / float(segs)
			var u1 := circ * float(i + 1) / float(segs)
			var slope := (r0 - r1) / maxf(h, 0.01)
			var n0 := (d0 + Vector3.UP * slope).normalized()
			var n1 := (d1 + Vector3.UP * slope).normalized()
			# unten links, oben links, oben rechts, unten rechts (von aussen: rechts = Richtung zunehmender Winkel)
			var p := [base + d0 * r0, base + d0 * r1 + Vector3.UP * h, base + d1 * r1 + Vector3.UP * h, base + d1 * r0]
			var nn := [n0, n0, n1, n1]
			var uv := [Vector2(u0, 0.0), Vector2(u0, -h), Vector2(u1, -h), Vector2(u1, 0.0)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(kc)
				st.set_normal(nn[k])
				st.set_uv(uv[k])
				st.set_uv2(Vector2(0.0, -1.0))
				st.set_custom(0, cust)
				st.add_vertex(p[k])
		if cap_col.r >= 0.0 and r1 > 0.01:
			var top_c := base + Vector3.UP * h
			var cc := Color(seed_v, 2.0, 0.0, 0.0)
			var cap := Color(cap_col.r, cap_col.g, cap_col.b, 6.0 / 16.0)
			for i in segs:
				var a0 := TAU * float(i) / float(segs)
				var a1 := TAU * float(i + 1) / float(segs)
				var q0 := top_c + Vector3(sin(a0), 0, cos(a0)) * r1
				var q1 := top_c + Vector3(sin(a1), 0, cos(a1)) * r1
				_tri(st, [top_c, q1, q0], [Vector2(top_c.x, top_c.z), Vector2(q1.x, q1.z), Vector2(q0.x, q0.z)], Vector3.UP, cap, cc)

	## Satteldach: Traufe auf Hoehe c.y, First laengs der laengeren Seite, Giebel in Wandtextur.
	func gable_roof(tex: String, c: Vector3, sx: float, sz: float, h: float, wall_col: Color, roof_col: Color, seed_v: float, overhang: float = 0.35) -> void:
		var along_x := sx >= sz
		var L := (sx if along_x else sz) + overhang * 2.0
		var W := (sz if along_x else sx) + overhang * 2.0
		var ax := Vector3.RIGHT if along_x else Vector3.BACK
		var side := Vector3.BACK if along_x else Vector3.LEFT
		var st := _surf(tex)
		var rc := Color(seed_v, 2.0, 0.0, 0.0)
		var rcol := Color(roof_col.r, roof_col.g, roof_col.b, 6.0 / 16.0)
		var ridge := c + Vector3.UP * h
		for s: float in [-1.0, 1.0]:
			var e := c + side * (W * 0.5 * s) - Vector3.UP * (overhang * h / (W * 0.5))
			var n := (side * s * h + Vector3.UP * (W * 0.5)).normalized()
			# von aussen gesehen: unten links/oben links/oben rechts/unten rechts
			var t := Vector3.UP.cross(side * s).normalized()
			var a := t * (L * 0.5)
			var p := [e - a, ridge - a, ridge + a, e + a]
			var slope_len := Vector2(W * 0.5, h).length()
			var uv := [Vector2(-L * 0.5, slope_len), Vector2(-L * 0.5, 0.0), Vector2(L * 0.5, 0.0), Vector2(L * 0.5, slope_len)]
			_quad(st, p, uv, n, Vector2(0.0, -1.0), rcol, rc)
		# Giebeldreiecke (Wand, ohne Fenster)
		var gc := Color(seed_v, 1.0, 0.0, 0.0)
		var gcol := Color(wall_col.r, wall_col.g, wall_col.b, 6.0 / 16.0)
		var Lw := L - overhang * 2.0
		var Ww := W - overhang * 2.0
		for s2: float in [-1.0, 1.0]:
			var n2 := ax * s2
			var t2 := Vector3.UP.cross(n2).normalized()
			var b := c + ax * (Lw * 0.5 * s2)
			var p0 := b - t2 * (Ww * 0.5)
			var p1 := b + t2 * (Ww * 0.5)
			var p2 := b + Vector3.UP * h
			_tri(_surf(tex), [p0, p2, p1], [Vector2(-Ww * 0.5, 0.0), Vector2(0.0, -h), Vector2(Ww * 0.5, 0.0)], n2, gcol, gc)

	## Gebaeudeblock. c = Mitte am Boden, size = (Breite x, Traufhoehe, Tiefe z).
	## o: seed, damage (0..1), lit (Lichtfaktor), roof ("flat" | "gable" | "none"), roof_col, roof_h,
	##    trim_tex (Gesimse), cornice (bool), bits (Dachaufbauten), faces (Array der Normalen mit Fenstern; Standard alle)
	func block(c: Vector3, size: Vector3, kind_name: String, tex: String, tint: Color, o: Dictionary = {}) -> void:
		var kind: int = KIND.get(kind_name, 0)
		var seed_v: float = o.get("seed", fposmod(c.x * 0.0137 + c.z * 0.0291, 1.0))
		var dmg: float = o.get("damage", 0.0)
		var lit: float = o.get("lit", 1.0)
		var trim_tex: String = o.get("trim_tex", tex)
		var roof: String = o.get("roof", "gable" if kind == 0 else "flat")
		var roof_col: Color = o.get("roof_col", Color(0.3, 0.29, 0.28))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(seed_v * 100000.0) + 17
		var h := size.y
		var base_y := c.y
		var col := Color(tint.r, tint.g, tint.b, float(kind) / 16.0)
		var cust := Color(seed_v, 0.0, dmg, lit)
		var tcol := Color(tint.r, tint.g, tint.b, 6.0 / 16.0)
		var tcust := Color(seed_v, 1.0, dmg * 0.5, 0.0)
		var cx: float = CELL_X.get(kind, 2.7)
		var pier: float = PIER.get(kind, 1.0)
		var faces: Array = o.get("faces", [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT])
		# Wandflaechen mit Fensterraster
		for n: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			var w := size.x if absf(n.z) > 0.5 else size.z
			var d := size.z if absf(n.z) > 0.5 else size.x
			var hwz := floorf((w * 0.5 - pier) / cx) * cx if faces.has(n) else 0.0
			var k := kind if faces.has(n) else 6
			var cc := Color(tint.r, tint.g, tint.b, float(k) / 16.0)
			wall(tex, c + Vector3.UP * (h * 0.5) + n * (d * 0.5), n, w, h, base_y, 0.0, Vector2(maxf(hwz, 0.0), h), cc, cust)
		if roof != "none":
			top(tex, c + Vector3.UP * h, size.x, size.z, roof_col, Color(seed_v, 2.0, 0.0, 0.0))
		var cornice: bool = o.get("cornice", kind == 0 or kind == 5)
		# Sockel / Gurtgesims / Kranzgesims (Altbau, Palais)
		if kind == 5:
			plain_box(trim_tex, c + Vector3.UP * 0.6, Vector3(size.x + 0.3, 1.2, size.z + 0.3), base_y, tcol, Color(seed_v, 3.0, dmg * 0.5, 0.0))
		if cornice:
			var g: float = GROUND.get(kind, 0.0)
			if g > 0.0 and h > g + 3.0:
				plain_box(trim_tex, c + Vector3.UP * (g + 0.12), Vector3(size.x + 0.24, 0.3, size.z + 0.24), base_y, tcol, tcust, Color(-1, 0, 0), true)
			var ck := 0.55 if kind == 5 else 0.42
			plain_box(trim_tex, c + Vector3.UP * (h - 0.55), Vector3(size.x + ck * 0.5, 0.4, size.z + ck * 0.5), base_y, tcol, tcust, Color(-1, 0, 0), true)
			plain_box(trim_tex, c + Vector3.UP * (h - 0.18), Vector3(size.x + ck * 2.0, 0.36, size.z + ck * 2.0), base_y, tcol, tcust, Color(-1, 0, 0), true)
		# Attika / Bruestung um das Flachdach
		var par_h: float = o.get("parapet", 1.5 if kind == 5 else (0.9 if kind == 2 or kind == 3 else (0.6 if kind == 4 else 0.0)))
		if roof == "flat" and par_h > 0.0:
			var pt := 0.35
			var yc := h + par_h * 0.5
			var pc := Color(seed_v, 1.0, 0.0, 0.0)
			plain_box(trim_tex, c + Vector3(0, yc, size.z * 0.5 - pt * 0.5), Vector3(size.x, par_h, pt), base_y, tcol, pc)
			plain_box(trim_tex, c + Vector3(0, yc, -size.z * 0.5 + pt * 0.5), Vector3(size.x, par_h, pt), base_y, tcol, pc)
			plain_box(trim_tex, c + Vector3(size.x * 0.5 - pt * 0.5, yc, 0), Vector3(pt, par_h, size.z - pt * 2.0), base_y, tcol, pc)
			plain_box(trim_tex, c + Vector3(-size.x * 0.5 + pt * 0.5, yc, 0), Vector3(pt, par_h, size.z - pt * 2.0), base_y, tcol, pc)
		# Dach
		if roof == "gable":
			var rh: float = o.get("roof_h", minf(size.x, size.z) * 0.32)
			if dmg > 0.55 and rng.randf() < dmg * 0.7:
				# ausgebrannter Dachstuhl: nur Giebelreste und Sparrenstuempfe
				var along_x := size.x >= size.z
				for s: float in [-1.0, 1.0]:
					var gp := c + Vector3.UP * (h + rh * 0.3) + (Vector3.RIGHT * (size.x * 0.5 - 0.2) * s if along_x else Vector3.BACK * (size.z * 0.5 - 0.2) * s)
					plain_box(tex, gp, Vector3(0.4 if along_x else size.x * 0.5, rh * 0.6, size.z * 0.5 if along_x else 0.4), base_y, tcol, Color(seed_v, 1.0, dmg, 0.0))
			else:
				gable_roof(tex, c + Vector3.UP * h, size.x, size.z, rh, tint, roof_col, seed_v)
				# Gauben/Schornsteine auf dem Dach
				for i in rng.randi_range(1, 3):
					var along := size.x >= size.z
					var off := rng.randf_range(-0.38, 0.38) * (size.x if along else size.z)
					var p := c + Vector3.UP * (h + rh * 0.55) + (Vector3(off, 0, rng.randf_range(-0.15, 0.15) * size.z) if along else Vector3(rng.randf_range(-0.15, 0.15) * size.x, 0, off))
					tube("brick", p, 0.42, 0.4, rh * 0.75 + rng.randf_range(0.6, 1.4), Color(0.7, 0.55, 0.48), seed_v, 4, Color(0.15, 0.14, 0.13))
		elif roof == "flat" and bool(o.get("bits", true)):
			for i in rng.randi_range(1, 3):
				var bs := Vector3(rng.randf_range(2.5, 5.0), rng.randf_range(1.6, 3.0), rng.randf_range(2.5, 4.5))
				var bp := c + Vector3(rng.randf_range(-0.3, 0.3) * size.x, h + bs.y * 0.5, rng.randf_range(-0.3, 0.3) * size.z)
				plain_box(trim_tex, bp, bs, base_y, tcol, Color(seed_v, 0.0, 0.0, 0.0), roof_col)

## Haengt alle gesammelten Meshes eines Builders an parent. opts gehen als Shader-Parameter an jedes Material.
static func build(b: Builder, parent: Node3D, shadows: bool = false, opts: Dictionary = {}, node_name: String = "FarCity") -> void:
	for tex: String in b._st:
		var st: SurfaceTool = b._st[tex]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = node_name + "_" + tex
		mi.mesh = st.commit()
		mi.material_override = material(tex, opts)
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	b._st.clear()
