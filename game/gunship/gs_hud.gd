extends CanvasLayer
## Feuerleit-HUD der "Waechter": Fadenkreuz je Waffe, Bildecken, Sensor-/Flugdaten, Waffenleiste mit Munition/Nachladen,
## Lage des Trupps, Zellen-Zustand, Taeuschkoerper, Warnungen (Rakete, Danger Close, Eigenbeschuss),
## IFF-Markierungen eigener Leute und Zielhinweise. Liegt ueber dem Waermebild-Postprozess, unter der StoryUI.

const WHITE := Color(0.93, 0.95, 0.93, 0.92)
const DIM := Color(0.93, 0.95, 0.93, 0.5)
const SHADOW := Color(0, 0, 0, 0.55)
const WARN := Color(1.0, 0.78, 0.3, 1.0)

var ctrl = null          # GunshipController
var world = null         # GSWorld
var mark_targets: bool = false
var targets_left: int = -1
var upload: float = -1.0          # 0..1 Sendefortschritt, < 0 aus
var upload_label: String = "UPLOAD"
var phase_label: String = ""
var ff_warn: float = 0.0          # Eigenbeschuss-Warnung (Sekunden)
var hint: String = ""
var hint_t: float = 0.0

var _c: Control         ## feste HUD-Teile in 1080p-Pixeln unter UIStyle.HudRoot
var _w: Control         ## Weltmarker (unproject_position) in echten Pixeln
var _cv: Control        ## aktuelle Zeichenflaeche der Hilfsfunktionen
var _font: Font
var _blink: float = 0.0

func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
	_w = Control.new()
	_w.set_anchors_preset(Control.PRESET_FULL_RECT)
	_w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_w.draw.connect(_draw_world)
	add_child(_w)
	var root := UIStyle.HudRoot.new()
	add_child(root)
	_c = Control.new()
	_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw_hud)
	root.add_child(_c)

func show_hint(text: String, dur: float = 5.0) -> void:
	hint = text
	hint_t = dur

func _process(delta: float) -> void:
	_blink += delta
	ff_warn = maxf(0.0, ff_warn - delta)
	hint_t = maxf(0.0, hint_t - delta)
	_c.queue_redraw()
	_w.queue_redraw()

func _txt(p: Vector2, s: String, size: int = 16, col: Color = WHITE, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	size = UIStyle.min_fs(size, UIStyle.hud_scale(_w.size) if _cv == _c else 1.0)
	_cv.draw_string(_font, p + Vector2(1, 1), s, align, width, size, SHADOW)
	_cv.draw_string(_font, p, s, align, width, size, col)

func _line(a: Vector2, b: Vector2, col: Color = WHITE, w: float = 1.6) -> void:
	_cv.draw_line(a + Vector2(1, 1), b + Vector2(1, 1), SHADOW, w)
	_cv.draw_line(a, b, col, w)

func _rect(r: Rect2, col: Color = WHITE, w: float = 1.4, filled: bool = false) -> void:
	if filled:
		_cv.draw_rect(r, col, true)
	else:
		_cv.draw_rect(r.grow(0.5), SHADOW, false, w)
		_cv.draw_rect(r, col, false, w)

## Weltmarker (IFF, Zielhinweise) in echten Pixeln; Groessen mit der HUD-Skalierung.
func _draw_world() -> void:
	if ctrl == null:
		return
	_cv = _w
	var sz := _w.size
	var cx := sz * 0.5
	var ms := UIStyle.hud_scale(sz)
	# --- IFF eigener Leute
	var cam: Camera3D = ctrl.cam
	if world != null and cam != null:
		for u in world.team:
			var un := u as Node3D
			if not un.alive or un.state == "ride":
				continue
			var wp := un.global_position + Vector3(0, 2.6, 0)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			if sp.x < 0 or sp.y < 0 or sp.x > sz.x or sp.y > sz.y:
				continue
			var s := 6.0 * maxf(ms, 0.6)
			_line(sp + Vector2(-s, -s * 1.6), sp, Color(0.85, 0.95, 1.0, 0.55), 1.2)
			_line(sp + Vector2(s, -s * 1.6), sp, Color(0.85, 0.95, 1.0, 0.55), 1.2)
		for u2 in world.units:
			var tu := u2 as Node3D
			if tu.kind == "team_truck" and tu.alive:
				var tp := tu.global_position + Vector3(0, 4.0, 0)
				if not cam.is_position_behind(tp):
					var sp2 := cam.unproject_position(tp)
					var q := maxf(ms, 0.6)
					_line(sp2 + Vector2(-8, -12) * q, sp2, Color(0.85, 0.95, 1.0, 0.55), 1.2)
					_line(sp2 + Vector2(8, -12) * q, sp2, Color(0.85, 0.95, 1.0, 0.55), 1.2)
		# Zielhinweise (wenige Ziele uebrig)
		if mark_targets:
			for e in world.alive_enemies(-1, true):
				var en := e as Node3D
				var ep := en.global_position + Vector3(0, en.hit_h * 2.0 + 2.0, 0)
				if cam.is_position_behind(ep):
					continue
				var esp := cam.unproject_position(ep)
				var inside := Rect2(Vector2(30, 30), sz - Vector2(60, 60)).has_point(esp)
				if inside:
					var k := (7.0 + 2.0 * sin(_blink * 6.0)) * maxf(ms, 0.6)
					_line(esp + Vector2(-k, -k * 1.4), esp + Vector2(k, -k * 1.4), WARN, 1.6)
					_line(esp + Vector2(-k, -k * 1.4), esp, WARN, 1.6)
					_line(esp + Vector2(k, -k * 1.4), esp, WARN, 1.6)
				else:
					var d := (esp - cx).normalized()
					var edge := cx + d * minf(sz.x, sz.y) * 0.42
					_line(edge, edge - d.rotated(0.45) * 16.0 * maxf(ms, 0.6), WARN, 2.0)
					_line(edge, edge - d.rotated(-0.45) * 16.0 * maxf(ms, 0.6), WARN, 2.0)

func _draw_hud() -> void:
	if ctrl == null:
		return
	_cv = _c
	var sz := _c.size
	var cx := sz * 0.5
	var sel: int = ctrl.sel
	# --- Bildecken
	var m := Vector2(sz.x * 0.08, sz.y * 0.09)
	var L := 46.0
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p := Vector2(lerpf(m.x, sz.x - m.x, corner.x), lerpf(m.y, sz.y - m.y, corner.y))
		var sx := 1.0 if corner.x == 0 else -1.0
		var sy := 1.0 if corner.y == 0 else -1.0
		_line(p, p + Vector2(L * sx, 0), DIM)
		_line(p, p + Vector2(0, L * sy), DIM)
	# --- Fadenkreuz
	_crosshair(cx, sel)
	# --- linke Datenspalte (unterhalb der Ziel-Box der StoryUI)
	var y0 := sz.y * 0.3
	var x0 := m.x - 10.0
	_txt(Vector2(x0, y0), "WÄCHTER  FLIR", 17)
	_txt(Vector2(x0, y0 + 24), ("BHOT" if ctrl.black_hot else "WHOT") + "   " + str(ctrl.ZOOM_NAMES[ctrl.zoom]) + "   %.1f°" % ctrl.cam.fov, 15, DIM)
	_txt(Vector2(x0, y0 + 46), "ALT %d FT" % int(ctrl.aircraft_pos.y * 3.281), 15, DIM)
	_txt(Vector2(x0, y0 + 68), "SLR %d M" % int(ctrl.slant_range), 15, DIM)
	var ah: Vector3 = ctrl.aim_hit
	_txt(Vector2(x0, y0 + 90), "33U UV %04d %04d" % [int(fposmod(ah.x + 4180.0, 10000.0)), int(fposmod(-ah.z + 3320.0, 10000.0))], 15, DIM)
	if phase_label != "":
		_txt(Vector2(x0, y0 + 118), phase_label, 15, WHITE)
	# --- rechte Spalte: Zustand
	var xr := sz.x - m.x - 210.0
	var integ: float = ctrl.integrity
	_txt(Vector2(xr, y0), "ZELLE", 15, DIM)
	_bar(Rect2(xr + 70, y0 - 12, 140, 12), integ / 100.0, WARN if integ < 35.0 else WHITE)
	if world != null and world.pressure_active:
		var pr: float = world.pressure
		_txt(Vector2(xr, y0 + 26), "TRUPP", 15, DIM)
		var pc := WHITE if pr > 35.0 else (WARN if fmod(_blink, 0.6) < 0.4 else DIM)
		_bar(Rect2(xr + 70, y0 + 14, 140, 12), pr / 100.0, pc)
	_txt(Vector2(xr, y0 + 52), "TÄUSCHK.  %d" % int(ctrl.flares_left) + ("   BEREIT" if ctrl.flare_cd <= 0.0 else "   ..."), 15, DIM)
	if targets_left >= 0:
		_txt(Vector2(xr, y0 + 78), "ZIELE  %d" % targets_left, 15, WHITE)
	if upload >= 0.0:
		_txt(Vector2(xr, y0 + 104), upload_label, 15, WHITE)
		_bar(Rect2(xr, y0 + 112, 210, 12), upload, WHITE)
		_txt(Vector2(xr, y0 + 142), "%d %%" % int(upload * 100.0), 15, DIM)
	# --- Waffenleiste unten
	# Kaesten wachsen mit der Mindestschrift mit (kleine Fenster), sonst ueberlappen Munition und Bezeichnung
	var wk := float(UIStyle.min_fs(15, UIStyle.hud_scale(_w.size))) / 15.0
	var bw := 190.0 * wk
	var bx := cx.x - bw * 1.5 - 10.0
	var by := sz.y - 18.0 - 48.0 * wk
	for i in 3:
		var w: Dictionary = ctrl.weapons[i]
		var r := Rect2(bx + i * (bw + 10.0), by, bw, 48 * wk)
		var on := i == sel
		if on:
			_cv.draw_rect(r, Color(0.93, 0.95, 0.93, 0.12), true)
		_rect(r, WHITE if on else DIM, 2.0 if on else 1.0)
		_txt(r.position + Vector2(10, 20 * wk), "%d  %s" % [i + 1, str(w["name"])], 17 if on else 15, WHITE if on else DIM)
		var rt := float(w["rt"])
		if rt > 0.0:
			var k := 1.0 - rt / float(w["reload"])
			_bar(Rect2(r.position + Vector2(10, 30 * wk), Vector2(bw - 20, 9 * wk)), k, DIM)
			_txt(r.position + Vector2(10, 20 * wk), "LADEN", 13, WARN, HORIZONTAL_ALIGNMENT_RIGHT, bw - 20)
		else:
			_txt(r.position + Vector2(10, 42 * wk), "%d / %d" % [int(w["ammo"]), int(w["mag"])], 14, WHITE if on else DIM)
			_txt(r.position + Vector2(10, 42 * wk), str(w["long"]), 12, DIM, HORIZONTAL_ALIGNMENT_RIGHT, bw - 20)
	# --- Warnungen
	var wy := sz.y * 0.2
	if ctrl.missile_warn and fmod(_blink, 0.5) < 0.32:
		_txt(Vector2(0, wy), "RAKETENSTART  –  TÄUSCHKÖRPER  [F]", 26, WARN, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		wy += 34
	if ctrl.flare_flash > 0.0:
		_txt(Vector2(0, wy), "TÄUSCHKÖRPER AUSGESTOSSEN", 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		wy += 26
	if ff_warn > 0.0 and fmod(_blink, 0.4) < 0.28:
		_txt(Vector2(0, wy), "EIGENBESCHUSS  –  FEUER EINSTELLEN", 24, WARN, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		wy += 30
	if ctrl.danger_close:
		_txt(Vector2(0, cx.y - 78), "DANGER CLOSE", 18, WARN if fmod(_blink, 0.5) < 0.3 else DIM, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if not ctrl.weapons_free:
		_txt(Vector2(0, cx.y + 118), "FEUER HALTEN", 16, DIM, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if hint_t > 0.0:
		_txt(Vector2(0, sz.y - 96), hint, 16, Color(1, 1, 1, minf(1.0, hint_t)), HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not ctrl.bot_active:
		_txt(Vector2(0, cx.y - 120), "Klicken, um die Optik zu übernehmen", 16, DIM, HORIZONTAL_ALIGNMENT_CENTER, sz.x)

func _bar(r: Rect2, k: float, col: Color) -> void:
	_cv.draw_rect(r, Color(0, 0, 0, 0.35), true)
	_cv.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(k, 0.0, 1.0), r.size.y)), col, true)
	_cv.draw_rect(r, DIM, false, 1.0)

func _crosshair(c: Vector2, sel: int) -> void:
	match sel:
		0:
			var g := 7.0
			var l := 22.0
			_line(c + Vector2(-g - l, 0), c + Vector2(-g, 0))
			_line(c + Vector2(g, 0), c + Vector2(g + l, 0))
			_line(c + Vector2(0, -g - l), c + Vector2(0, -g))
			_line(c + Vector2(0, g), c + Vector2(0, g + l))
			var b := 46.0
			for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var p := c + s * b
				_line(p, p - Vector2(s.x * 12.0, 0), DIM)
				_line(p, p - Vector2(0, s.y * 12.0), DIM)
		1:
			var h := 30.0
			_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), WHITE, 1.6)
			_cv.draw_circle(c, 2.2, WHITE)
			for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_line(c + d * h, c + d * (h + 40.0))
				_line(c + d * (h + 52.0), c + d * (h + 60.0), DIM)
		2:
			var big := 150.0
			var gap := 26.0
			for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_line(c + d * gap, c + d * big, WHITE, 2.0)
				for t in range(1, 5):
					var tp: Vector2 = c + d * (gap + t * 28.0)
					var n := Vector2(-d.y, d.x) * (7.0 if t % 2 == 0 else 4.0)
					_line(tp - n, tp + n, DIM, 1.4)
			_cv.draw_arc(c + Vector2(1, 1), gap, 0, TAU, 40, SHADOW, 1.6)
			_cv.draw_arc(c, gap, 0, TAU, 40, WHITE, 1.6)
			_cv.draw_circle(c, 1.8, WHITE)
