extends Control
## Stilisierte taktische Karte fuer das Briefing (Welle 4, systeme-b). Zeichnet alles per _draw():
## Gitter mit Planquadraten, Gelaende aus BriefingMaps, und Lagesymbole/Pfeile, die im Takt des Textes erscheinen.
## Steuerung von aussen: setup(map, text) einmal, dann set_progress(sichtbare_zeichen) pro Frame; reveal_all().

const BriefingMaps = preload("res://game/briefing/briefing_maps.gd")

const COL_FRIEND := Color(0.42, 0.68, 1.0)
const COL_ENEMY := Color(1.0, 0.36, 0.28)
const COL_OBJ := Color(1.0, 0.72, 0.28)
const COL_HVT := Color(1.0, 0.52, 0.22)
const COL_NEUTRAL := Color(0.55, 0.9, 0.6)
const COL_WEATHER := Color(0.72, 0.82, 0.92)
const COL_HOSTAGE := Color(0.92, 0.92, 0.86)
const COL_GRID := Color(0.62, 0.66, 0.6, 0.10)
const COL_GRID_HI := Color(0.62, 0.66, 0.6, 0.22)
const COL_LABEL := Color(0.62, 0.66, 0.6, 0.55)
const COL_PAPER := Color(0.03, 0.045, 0.04, 1.0)

const ARROW_TIME := 1.4    # Sekunden, bis ein Pfeil ausgezogen ist
const MARK_TIME := 0.35
const HIDDEN := -1.0e9
const ZONE_TIME := 0.8

var _map: Dictionary = {}
var _cues: Array = []
var _cue_chars: PackedInt32Array = PackedInt32Array()
var _cue_on: PackedFloat32Array = PackedFloat32Array()   # Zeitpunkt der Aktivierung, HIDDEN = noch verdeckt
var _t: float = 0.0
var _font: Font
var _font_b: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_font = UIStyle.font(600, true)
	_font_b = UIStyle.font(700, true)


func setup(map: Dictionary, text: String) -> void:
	_map = map
	_cues = map.get("cues", [])
	var starts := BriefingMaps.sentence_starts(text)
	_cue_chars.resize(_cues.size())
	_cue_on.resize(_cues.size())
	for i in _cues.size():
		_cue_chars[i] = BriefingMaps.cue_char(starts, text.length(), float((_cues[i] as Dictionary).get("at", 0.0)))
		_cue_on[i] = HIDDEN
	queue_redraw()


## Aktiviert alle Hinweise, deren Satzposition der Text erreicht hat. Gibt die Zahl neu erschienener zurueck.
func set_progress(chars: int) -> int:
	var fresh := 0
	for i in _cues.size():
		if _cue_on[i] <= HIDDEN and chars >= _cue_chars[i]:
			_cue_on[i] = _t
			fresh += 1
	return fresh


func reveal_all() -> void:
	for i in _cues.size():
		if _cue_on[i] <= HIDDEN:
			_cue_on[i] = _t - 10.0


func revealed_count() -> int:
	var c := 0
	for v in _cue_on:
		if v > HIDDEN:
			c += 1
	return c


## Arten der bereits sichtbaren Symbole (fuer die Legende); Marschweg-Pfeile zaehlen als "route".
func revealed_kinds() -> Dictionary:
	var out := {}
	for i in _cues.size():
		if _cue_on[i] > HIDDEN:
			var cd: Dictionary = _cues[i]
			if cd.get("t", "") == "arrow" and cd.get("k", "") == "route":
				out["route"] = true
			elif cd.get("t", "") == "mark":
				out[str(cd.get("k", ""))] = true
	return out


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# ------------------------------------------------------------------ Zeichnen

func _p(x: float, y: float) -> Vector2:
	return Vector2(x * size.x, y * size.y)


func _pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i + 1 < flat.size():
		out.append(_p(float(flat[i]), float(flat[i + 1])))
		i += 2
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_PAPER)
	_draw_grid()
	for e in _map.get("terrain", []):
		_draw_terrain(e as Dictionary)
	# Zonen zuerst (unter Pfeilen und Symbolen), dann Linien/Pfeile, dann Symbole
	for pass_i in 3:
		for i in _cues.size():
			if _cue_on[i] <= HIDDEN:
				continue
			var c: Dictionary = _cues[i]
			var t: String = c.get("t", "mark")
			var layer := 0 if t == "zone" else (1 if t == "arrow" or t == "line" else 2)
			if layer != pass_i:
				continue
			var age := _t - _cue_on[i]
			match t:
				"zone": _draw_zone(c, age)
				"arrow": _draw_arrow(c, age, false)
				"line": _draw_arrow(c, age, true)
				_: _draw_mark(c, age)
	_draw_frame()


func _draw_grid() -> void:
	var cols := 8
	var rows := 6
	for i in range(1, cols * 2):
		var x := size.x * i / (cols * 2.0)
		draw_line(Vector2(x, 0), Vector2(x, size.y), COL_GRID_HI if i % 2 == 0 else COL_GRID, 1.0)
	for j in range(1, rows * 2):
		var y := size.y * j / (rows * 2.0)
		draw_line(Vector2(0, y), Vector2(size.x, y), COL_GRID_HI if j % 2 == 0 else COL_GRID, 1.0)
	var letters := "ABCDEFGH"
	for i in cols:
		draw_string(_font, Vector2(size.x * (i + 0.5) / cols - 5, 16), letters[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_LABEL)
	for j in rows:
		draw_string(_font, Vector2(6, size.y * (j + 0.5) / rows + 4), str(j + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_LABEL)
	# langsame Abtastlinie
	var sy := fposmod(_t * 60.0, size.y + 200.0) - 100.0
	draw_rect(Rect2(0, sy, size.x, 2), Color(0.55, 0.9, 0.6, 0.05))
	draw_rect(Rect2(0, sy - 30, size.x, 30), Color(0.55, 0.9, 0.6, 0.015))


func _fill_shape(e: Dictionary, col: Color, outline: Color) -> void:
	if e.has("r"):
		var r: Array = e["r"]
		var rect := Rect2(_p(float(r[0]), float(r[1])), _p(float(r[2]), float(r[3])))
		draw_rect(rect, col)
		draw_rect(rect, outline, false, 1.0)
	elif e.has("p"):
		var pts := _pts(e["p"])
		if pts.size() >= 3 and Geometry2D.triangulate_polygon(pts).size() > 0:
			draw_colored_polygon(pts, col)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, outline, 1.0, true)


func _draw_terrain(e: Dictionary) -> void:
	var k: String = e.get("k", "")
	match k:
		"field":
			_fill_shape(e, Color(0.55, 0.6, 0.42, 0.05), Color(0.55, 0.6, 0.42, 0.10))
		"forest":
			_fill_shape(e, Color(0.3, 0.55, 0.32, 0.13), Color(0.4, 0.65, 0.4, 0.28))
		"water":
			_fill_shape(e, Color(0.25, 0.45, 0.7, 0.20), Color(0.4, 0.62, 0.9, 0.40))
		"block":
			_fill_shape(e, Color(0.62, 0.66, 0.6, 0.10), Color(0.62, 0.66, 0.6, 0.38))
		"zone":
			_fill_shape(e, Color(0.62, 0.66, 0.6, 0.04), Color(0.62, 0.66, 0.6, 0.22))
		"road":
			var pts := _pts(e.get("p", []))
			draw_polyline(pts, Color(0.62, 0.66, 0.6, 0.30), 9.0, true)
			draw_polyline(pts, Color(0.06, 0.075, 0.07, 1.0), 5.0, true)
		"rail":
			var pts := _pts(e.get("p", []))
			draw_polyline(pts, Color(0.62, 0.66, 0.6, 0.45), 2.0, true)
			_ticks(pts, 16.0, 5.0, Color(0.62, 0.66, 0.6, 0.45))
		"path":
			_dashed(_pts(e.get("p", [])), Color(0.62, 0.66, 0.6, 0.35), 2.0, 8.0, 6.0)
		"tunnel":
			_dashed(_pts(e.get("p", [])), Color(1.0, 0.72, 0.28, 0.35), 4.0, 10.0, 7.0)
		"contour":
			draw_polyline(_pts(e.get("p", [])), Color(0.75, 0.6, 0.4, 0.28), 1.5, true)
		"border":
			_dashed(_pts(e.get("p", [])), Color(1.0, 0.36, 0.28, 0.45), 2.5, 16.0, 6.0)
		"fence":
			_dashed(_pts(e.get("p", [])), Color(0.62, 0.66, 0.6, 0.30), 1.5, 4.0, 4.0)
		"label":
			var c: Array = e.get("c", [0, 0])
			draw_string(_font, _p(float(c[0]), float(c[1])) + Vector2(0, 12), str(e.get("s", "")),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_LABEL)


func _ticks(pts: PackedVector2Array, every: float, half: float, col: Color) -> void:
	var acc := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		if seg < 0.01:
			continue
		var dir := (b - a) / seg
		var nrm := Vector2(-dir.y, dir.x) * half
		var d := every - acc
		while d < seg:
			var q := a + dir * d
			draw_line(q - nrm, q + nrm, col, 1.5)
			d += every
		acc = seg - (d - every)


func _dashed(pts: PackedVector2Array, col: Color, w: float, dash: float, gap: float) -> void:
	var on := true
	var left := dash
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		if seg < 0.01:
			continue
		var dir := (b - a) / seg
		var pos := 0.0
		while pos < seg:
			var step := minf(left, seg - pos)
			if on:
				draw_line(a + dir * pos, a + dir * (pos + step), col, w, true)
			pos += step
			left -= step
			if left <= 0.001:
				on = not on
				left = dash if on else gap


func _draw_frame() -> void:
	var c := UIStyle.C_LINE_HI
	draw_rect(Rect2(Vector2.ZERO, size), c, false, 1.0)
	var L := 26.0
	for corner in [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, size.y), size]:
		var sx := 1.0 if corner.x == 0.0 else -1.0
		var sy := 1.0 if corner.y == 0.0 else -1.0
		draw_line(corner, corner + Vector2(L * sx, 0), UIStyle.C_AMBER, 2.0)
		draw_line(corner, corner + Vector2(0, L * sy), UIStyle.C_AMBER, 2.0)
	# Nordpfeil
	var n := Vector2(size.x - 40, 52)
	draw_colored_polygon(PackedVector2Array([n + Vector2(0, -22), n + Vector2(9, 8), n + Vector2(0, 2), n + Vector2(-9, 8)]),
			Color(0.9, 0.91, 0.87, 0.75))
	draw_string(_font_b, n + Vector2(-5, 28), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.91, 0.87, 0.75))
	# Massstabsleiste
	var s0 := Vector2(28, size.y - 28)
	for i in 4:
		draw_rect(Rect2(s0 + Vector2(i * 36, -4), Vector2(36, 5)), Color(0.9, 0.91, 0.87, 0.7 if i % 2 == 0 else 0.15))
	draw_rect(Rect2(s0 + Vector2(0, -4), Vector2(144, 5)), Color(0.9, 0.91, 0.87, 0.5), false, 1.0)
	var ref := str(_map.get("ref", ""))
	if ref != "":
		draw_string(_font, s0 + Vector2(160, 2), ref.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_LABEL)
	var grid := str(_map.get("grid", ""))
	if grid != "":
		draw_string(_font, Vector2(size.x - 200, size.y - 22), grid, HORIZONTAL_ALIGNMENT_RIGHT, 180, 12, COL_LABEL)


# ------------------------------------------------------------------ Lagesymbole

static func kind_color(k: String) -> Color:
	match k:
		"friend": return COL_FRIEND
		"enemy": return COL_ENEMY
		"objective", "route", "charge": return COL_OBJ
		"hvt": return COL_HVT
		"neutral": return COL_NEUTRAL
		"weather": return COL_WEATHER
		"hostage": return COL_HOSTAGE
	return UIStyle.C_TEXT


## Zeichnet ein Lagesymbol auf ein beliebiges CanvasItem (auch fuer die Legende).
static func draw_symbol(ci: CanvasItem, k: String, at: Vector2, sc: float, a: float, t: float) -> void:
	var col := kind_color(k)
	var fill := Color(col.r, col.g, col.b, 0.22 * a)
	var line := Color(col.r, col.g, col.b, a)
	match k:
		"friend":
			var r := Rect2(at - Vector2(17, 11) * sc, Vector2(34, 22) * sc)
			ci.draw_rect(r, fill)
			ci.draw_rect(r, line, false, 2.0)
			ci.draw_line(r.position, r.end, Color(line, 0.6 * a), 1.5)
			ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(line, 0.6 * a), 1.5)
		"enemy":
			var d := 14.0 * sc
			var pts := PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)])
			ci.draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			ci.draw_polyline(pts, line, 2.0, true)
		"objective":
			var pulse := 1.0 + 0.18 * sin(t * 4.0)
			ci.draw_arc(at, 13.0 * sc * pulse, 0.0, TAU, 32, line, 2.0, true)
			ci.draw_arc(at, 4.0 * sc, 0.0, TAU, 16, line, 2.0, true)
			for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				ci.draw_line(at + v * 8.0 * sc, at + v * 20.0 * sc, line, 2.0)
		"hvt":
			var pulse2 := 1.0 + 0.15 * sin(t * 5.0)
			ci.draw_arc(at, 15.0 * sc * pulse2, 0.0, TAU, 32, line, 2.0, true)
			ci.draw_arc(at, 9.0 * sc, 0.0, TAU, 24, Color(line, 0.6 * a), 1.5, true)
			ci.draw_circle(at, 3.5 * sc, line)
		"neutral":
			var r2 := Rect2(at - Vector2(11, 11) * sc, Vector2(22, 22) * sc)
			ci.draw_rect(r2, fill)
			ci.draw_rect(r2, line, false, 2.0)
		"charge":
			var r3 := Rect2(at - Vector2(10, 10) * sc, Vector2(20, 20) * sc)
			ci.draw_rect(r3, Color(fill, 0.35 * a))
			ci.draw_rect(r3, line, false, 2.0)
			ci.draw_line(r3.position + Vector2(4, 4) * sc, r3.end - Vector2(4, 4) * sc, line, 2.0)
			ci.draw_line(Vector2(r3.position.x, r3.end.y) + Vector2(4, -4) * sc, Vector2(r3.end.x, r3.position.y) + Vector2(-4, 4) * sc, line, 2.0)
		"hostage":
			ci.draw_arc(at, 11.0 * sc, 0.0, TAU, 24, line, 2.0, true)
			ci.draw_circle(at + Vector2(0, -3) * sc, 3.5 * sc, line)
			ci.draw_line(at + Vector2(-5, 6) * sc, at + Vector2(5, 6) * sc, line, 2.0)
		_:
			ci.draw_circle(at, 6.0 * sc, line)


func _label(s: String, at: Vector2, col: Color, a: float) -> void:
	if s == "":
		return
	var fs := 16
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := at
	if pos.x + w + 8 > size.x:   # am rechten Rand nach links klappen
		pos.x = at.x - w - 52
	pos.y = clampf(pos.y, 14.0, size.y - 8.0)
	draw_rect(Rect2(pos + Vector2(-4, -15), Vector2(w + 8, 21)), Color(0.02, 0.03, 0.028, 0.78 * a))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lightened(0.25), a))


func _draw_mark(c: Dictionary, age: float) -> void:
	var k: String = c.get("k", "neutral")
	var cc: Array = c.get("c", [0.5, 0.5])
	var at := _p(float(cc[0]), float(cc[1]))
	var f := clampf(age / MARK_TIME, 0.0, 1.0)
	var sc := lerpf(1.7, 1.0, ease(f, 0.4))
	draw_symbol(self, k, at, sc, f, _t)
	if age < 1.2:   # einmaliger Ortungsring
		var rr := 14.0 + age * 60.0
		draw_arc(at, rr, 0.0, TAU, 40, Color(kind_color(k), 0.5 * (1.0 - age / 1.2)), 1.5, true)
	_label(str(c.get("s", "")), at + Vector2(24, 6), kind_color(k), clampf((age - 0.15) / 0.3, 0.0, 1.0))


func _draw_zone(c: Dictionary, age: float) -> void:
	var k: String = c.get("k", "neutral")
	var cc: Array = c.get("c", [0.5, 0.5])
	var at := _p(float(cc[0]), float(cc[1]))
	var f := ease(clampf(age / ZONE_TIME, 0.0, 1.0), 0.35)
	var r := float(c.get("r", 0.1)) * (size.x + size.y) * 0.5 * f
	var col := kind_color(k)
	if r < 1.0:
		return
	draw_circle(at, r, Color(col, 0.07 * f))
	if k == "weather":   # Schraffur fuer Wetter
		var step := 18.0
		var x := -r
		while x < r:
			var h := sqrt(maxf(r * r - x * x, 0.0))
			draw_line(at + Vector2(x, -h), at + Vector2(x, h), Color(col, 0.06 * f), 1.0)
			x += step
	# gestrichelter, langsam drehender Rand
	var segs := 36
	var rot := _t * 0.15
	for i in segs:
		if i % 2 == 1:
			continue
		var a0 := rot + TAU * i / segs
		draw_arc(at, r, a0, a0 + TAU / segs, 4, Color(col, 0.6 * f), 2.0, true)
	var s := str(c.get("s", ""))
	if s != "":
		_label(s, at + Vector2(-r * 0.7, -r * 0.72), col, clampf((age - 0.4) / 0.4, 0.0, 1.0))


func _draw_arrow(c: Dictionary, age: float, plain: bool) -> void:
	var k: String = c.get("k", "route")
	var pts := _pts(c.get("p", []))
	if pts.size() < 2:
		return
	var col := kind_color(k)
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var f := ease(clampf(age / ARROW_TIME, 0.0, 1.0), 0.6)
	var want := total * f
	var part := PackedVector2Array([pts[0]])
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if acc + seg >= want:
			part.append(pts[i - 1].lerp(pts[i], (want - acc) / maxf(seg, 0.001)))
			break
		part.append(pts[i])
		acc += seg
	if part.size() < 2 or want < 2.0:
		return
	if plain:
		_dashed(part, Color(col, 0.75), 2.0, 10.0, 7.0)
	else:
		draw_polyline(part, Color(col, 0.14), 12.0, true)
		if k == "enemy":
			_dashed(part, col, 4.0, 18.0, 8.0)
		else:
			draw_polyline(part, col, 4.0, true)
		var tip := part[part.size() - 1]
		var prev := part[part.size() - 2]
		var dir := (tip - prev).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		var nrm := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip + dir * 14.0, tip - dir * 8.0 + nrm * 11.0, tip - dir * 8.0 - nrm * 11.0]), col)
	var s := str(c.get("s", ""))
	if s != "" and f > 0.5:
		var mid := pts[0].lerp(pts[pts.size() - 1], 0.5) if pts.size() == 2 else pts[pts.size() / 2]
		_label(s, mid + Vector2(16, -8), col, clampf((f - 0.5) / 0.3, 0.0, 1.0))
