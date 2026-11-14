extends CanvasLayer
## Schleich-HUD fuer "curfew": Entdeckungsanzeige je Wache (ueber dem Kopf bzw. Randpfeil), Status oben
## (VERBORGEN / VERDÄCHTIG / ENTDECKT / ALARM) mit Lichtmesser, Download-Balken, Takedown-Hinweis,
## Alarm-Vignette und Loesch-Einblendung.

var director: Node
var takedown: Node
var terminal: Node
## Optional (villa): Aufklaerungsdrohne. Gesetzt -> Verdachtsaugen nur fuer von der Drohne markierte Watcher
## (unmarkierte erst, wenn sie den Spieler sicher sehen), dazu Radar unten links: markierte Wachen und
## Kameras mit Blickkegel, Weber, Zaehler "aufgeklaert". Ohne Aufklaerung bleibt das Radar leer.
var drone: Node
var radar_range: float = 34.0
## Vom Level gesetzt: Folgen des Alarms (z. B. "Verstärkung in 6 s", "Hoftor verriegelt"), Zeile unter dem Status.
var alarm_note: String = ""
## Kurze Einblendung unter dem Status (flash()), z. B. "Alarm beendet" oder Lohn fuers Schleichen.
var _flash_text: String = ""
var _flash_t: float = 0.0
var _flash_col: Color = Color(0.62, 0.9, 0.7)
var _was_alarm: bool = false

var _draw: Control      ## Weltmarker (unproject_position) in echten Pixeln
var _ui: Control        ## Status, Radar, Hinweise, Download in 1080p-Pixeln unter UIStyle.HudRoot
var _cv: Control        ## aktuelle Zeichenflaeche der Hilfsfunktionen
var _font: Font
var _t: float = 0.0
var _wipe: ColorRect
var _wipe_label: Label
var _toast_moved: bool = false

## Status (y 12-58) und bis zu drei Hinweiszeilen (_alarm_info ab y 59, je 22 px) belegen oben die Mitte
## bis ca. y 131; das CHECKPOINT-Toast der Spieler-HUD (sonst y 80-120) wandert darunter.
const TOAST_TOP := 146.0

func _move_player_toast() -> void:
	var pl := Game.get_player()
	if pl == null:
		return
	var h := pl.get_node_or_null("HUD")
	if h != null and h.has_method("set_toast_top"):
		h.call("set_toast_top", TOAST_TOP)
	_toast_moved = true

func _ready() -> void:
	layer = 6
	name = "CurfewHUD"
	_font = ThemeDB.fallback_font
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)
	var root := UIStyle.HudRoot.new()
	add_child(root)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_on_draw_ui)
	root.add_child(_ui)
	_wipe = ColorRect.new()
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe.color = Color(0, 0, 0, 0)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_wipe)
	_wipe_label = Label.new()
	_wipe_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wipe_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wipe_label.add_theme_font_size_override("font_size", 30)
	_wipe_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.2))
	_wipe_label.modulate.a = 0.0
	_wipe.add_child(_wipe_label)

func _process(delta: float) -> void:
	if not _toast_moved:
		_move_player_toast()
	_t += delta
	_flash_t = maxf(0.0, _flash_t - delta)
	if director != null and is_instance_valid(director):
		var a: bool = director.get("alarm")
		if _was_alarm and not a:
			flash("Alarm beendet – Wachen bleiben wachsam", 4.0)
		_was_alarm = a
	_draw.queue_redraw()
	_ui.queue_redraw()

## Kurzhinweis unter der Statusbox (z. B. Alarmende, Belohnung fuers Unentdecktbleiben).
func flash(text: String, dur: float = 4.0, col: Color = Color(0.62, 0.9, 0.7)) -> void:
	_flash_text = text
	_flash_t = dur
	_flash_col = col

## Einblendung "Protokolle geloescht" (Schwarzblende hin und zurueck, dauer gesamt ~3,4 s).
func show_wipe(text: String) -> void:
	_wipe_label.text = text
	var tw := create_tween()
	tw.tween_property(_wipe, "color:a", 1.0, 0.5)
	tw.parallel().tween_property(_wipe_label, "modulate:a", 1.0, 0.5)
	tw.tween_interval(2.2)
	tw.tween_property(_wipe, "color:a", 0.0, 0.7)
	tw.parallel().tween_property(_wipe_label, "modulate:a", 0.0, 0.7)

func _on_draw() -> void:
	if director == null or not is_instance_valid(director):
		return
	_cv = _draw
	var cam := _draw.get_viewport().get_camera_3d()
	var vs := _draw.size
	var center := vs / 2.0
	if cam != null:
		var ms := UIStyle.hud_scale(vs)   # Augen/Randpfeile mit der HUD-Groesse skalieren
		for w in director.get("watchers"):
			if not is_instance_valid(w) or not bool(w.call("is_watcher_alive")):
				continue
			var st := int(w.call("get_watch_state"))
			var s := float(w.call("get_suspicion"))
			if st <= 0 and s < 0.03:
				continue
			if drone != null and st < 2 and not _watcher_marked(w):
				continue
			_marker(cam, vs, center, w.call("get_watch_pos"), s, st, ms)

## Feste HUD-Teile in 1080p-Pixeln (HudRoot skaliert auf die echte Ansicht).
func _on_draw_ui() -> void:
	if director == null or not is_instance_valid(director):
		return
	_cv = _ui
	var cam := _ui.get_viewport().get_camera_3d()
	var vs := _ui.size
	var center := vs / 2.0
	var alarm: bool = director.get("alarm")
	if alarm:
		_vignette(vs, Color(0.9, 0.05, 0.03, 0.10 + 0.07 * sin(_t * 6.0)))
	_status(vs, alarm)
	_alarm_info(vs, alarm)
	if drone != null and is_instance_valid(drone) and cam != null:
		_radar(cam, vs)
	var y := center.y + 142.0
	if takedown != null and is_instance_valid(takedown) and takedown.get("candidate") != null and not bool(takedown.call("busy")):
		_text_centered("[F] Lautlos ausschalten", Vector2(center.x, y), 19, Color(0.95, 0.92, 0.8))
	if terminal != null and is_instance_valid(terminal) and bool(terminal.get("downloading")):
		_download(Vector2(center.x, center.y + 176.0), float(terminal.get("progress")), bool(terminal.get("paused")), bool(terminal.get("locked")))

## Watcher -> Drohnenziel (Wachen melden ihr Gehirn an, Ziel ist der Gegner; Kameras sind beides).
func _watch_node(w: Object) -> Node3D:
	var e: Variant = w.get("enemy") if "enemy" in w else null
	if e is Node3D and is_instance_valid(e):
		return e as Node3D
	return w as Node3D

func _watcher_marked(w: Object) -> bool:
	var n := _watch_node(w)
	return n != null and bool(drone.call("is_marked", n))

## Blickrichtung (Welt, XZ) eines Watchers: Kamerakopf bzw. Gegner.
func _watch_dir(w: Object) -> Vector3:
	var n: Node3D = w.get("_head") as Node3D if "_head" in w else _watch_node(w)
	if n == null:
		return Vector3.FORWARD
	var f := -n.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD

func _radar(cam: Camera3D, vs: Vector2) -> void:
	# Groesse/Lage abhaengig von der Fenstergroesse: unten links ueber der Lebensleiste (hud.gd, y = h - 44);
	# reicht die Breite nicht, damit die Untertitel-Box (story_ui: ca. 900 px breit, unten mittig bis h - 104,
	# bis zu drei Zeilen hoch) frei bleibt, rueckt das Radar ueber die Untertitel-Zone.
	var rr := clampf(vs.y * 0.1, 52.0, 74.0)
	var c := Vector2(24.0 + rr, vs.y - 84.0 - rr)
	var sub_left := vs.x * 0.5 - 460.0
	if c.x + rr + 8.0 > sub_left:
		c.y = minf(c.y, vs.y - 104.0 - 112.0 - 28.0 - rr)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	var origin := pl.global_position
	var cf := -cam.global_transform.basis.z
	var yaw := atan2(cf.x, -cf.z)       # Blickrichtung oben
	var k := rr / radar_range
	var to_screen := func(wp: Vector3) -> Vector2:
		var d := Vector2(wp.x - origin.x, wp.z - origin.z).rotated(-yaw)
		return c + d * k
	_cv.draw_circle(c, rr + 3.0, Color(0, 0, 0, 0.5))
	_cv.draw_circle(c, rr, Color(0.06, 0.1, 0.08, 0.55))
	_cv.draw_arc(c, rr, 0.0, TAU, 48, Color(0.55, 0.8, 0.6, 0.55), 1.4, true)
	_cv.draw_arc(c, rr * 0.5, 0.0, TAU, 32, Color(0.55, 0.8, 0.6, 0.18), 1.0, true)
	var marked := 0
	var total := 0
	for w in director.get("watchers"):
		if not is_instance_valid(w) or not bool(w.call("is_watcher_alive")):
			continue
		total += 1
		var st := int(w.call("get_watch_state"))
		var mk := _watcher_marked(w)
		if mk:
			marked += 1
		elif st < 2:
			continue
		var wp: Vector3 = w.call("get_watch_pos")
		var p: Vector2 = to_screen.call(wp)
		var off := p - c
		var edge := off.length() > rr - 5.0
		if edge:
			p = c + off.normalized() * (rr - 5.0)
		var col := _col(st, float(w.call("get_suspicion")))
		if st <= 0:
			col = Color(0.62, 0.85, 1.0)
		var is_cam: bool = "_head" in w
		if not edge:
			var f := _watch_dir(w)
			var fa := Vector2(f.x, f.z).rotated(-yaw).angle()
			var half := deg_to_rad(28.0 if is_cam else 52.0)
			var reach := minf((16.0 if is_cam else 12.0) * k, rr * 0.5)
			var cone := PackedVector2Array([p])
			for i in 9:
				var a := fa - half + 2.0 * half * float(i) / 8.0
				cone.append(p + Vector2(cos(a), sin(a)) * reach)
			_poly(cone, Color(col.r, col.g, col.b, 0.16 if st <= 0 else 0.3))
		if is_cam:
			_cv.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(col.r, col.g, col.b, 0.95))
		else:
			_cv.draw_circle(p, 3.6, Color(0, 0, 0, 0.6))
			_cv.draw_circle(p, 2.8, Color(col.r, col.g, col.b, 0.95))
	# markierte Personen ohne Watcher (Weber, Jaeger)
	for t: Dictionary in drone.get("targets"):
		if not bool(t["marked"]) or str(t["kind"]) not in ["weber", "jaeger"]:
			continue
		var n := t["node"] as Node3D
		if n == null or not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		var p2: Vector2 = to_screen.call(n.global_position)
		if (p2 - c).length() > rr - 5.0:
			p2 = c + (p2 - c).normalized() * (rr - 5.0)
		var tc := Color(1.0, 0.82, 0.25) if str(t["kind"]) == "weber" else Color(0.75, 0.75, 0.78)
		var dm := PackedVector2Array([p2 + Vector2(0, -4.5), p2 + Vector2(4.5, 0), p2 + Vector2(0, 4.5), p2 + Vector2(-4.5, 0)])
		_poly(dm, tc)
	# Spieler (Pfeil nach oben = Blickrichtung)
	_poly(PackedVector2Array([c + Vector2(0, -6), c + Vector2(4.5, 5), c + Vector2(-4.5, 5)]), Color(0.95, 0.95, 0.9))
	var lbl := "AUFGEKLÄRT %d/%d" % [marked, total] if total > 0 else "KEINE ZIELE"
	var lc := Color(0.6, 0.85, 0.65) if total > 0 and marked >= total else (Color(1.0, 0.72, 0.25) if marked > 0 else Color(1.0, 0.45, 0.3))
	_text_centered(lbl, Vector2(c.x, c.y + rr + 16.0), 13, lc)
	if marked == 0:
		_text_centered("Keine Aufklärung", c, 12, Color(1.0, 0.5, 0.35, 0.8))

func _col(st: int, s: float) -> Color:
	if st >= 2:
		return Color(1.0, 0.18, 0.12)
	return Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.62, 0.1), clampf(s * 1.6, 0.0, 1.0))

func _marker(cam: Camera3D, vs: Vector2, center: Vector2, wp: Vector3, s: float, st: int, ms: float = 1.0) -> void:
	var col := _col(st, s)
	var behind := cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp)
	var on_screen := not behind and sp.x > 30 and sp.x < vs.x - 30 and sp.y > 30 and sp.y < vs.y - 30
	if on_screen:
		var dist := cam.global_position.distance_to(wp)
		var sc := clampf(14.0 / maxf(dist, 1.0), 0.55, 1.15)
		_eye(sp + Vector2(0, -6.0 * ms), maxf(15.0 * sc * ms, 6.0), s, col, st)
		return
	# Randpfeil auf einem Ring um die Bildmitte
	var local := cam.global_transform.basis.inverse() * (wp - cam.global_position)
	var dir2 := Vector2(local.x, local.z)
	if dir2.length() < 0.01:
		return
	var ang := atan2(dir2.x, -dir2.y)     # 0 = vorn (oben), positiv = rechts
	var r := 170.0 * ms
	var p := center + Vector2(sin(ang), -cos(ang)) * r
	var fwd := Vector2(sin(ang), -cos(ang)) * maxf(ms, 0.5)
	var side := Vector2(-fwd.y, fwd.x)
	var tip := p + fwd * 16.0
	var pts := PackedVector2Array([tip, p - fwd * 6.0 + side * 13.0, p - fwd * 6.0 - side * 13.0])
	_poly(pts, Color(0, 0, 0, 0.45))
	var fill := clampf(s, 0.15, 1.0)
	var inner := PackedVector2Array([p - fwd * 6.0 + (tip - (p - fwd * 6.0)) * 1.0, p - fwd * 6.0 + side * 13.0 * fill, p - fwd * 6.0 - side * 13.0 * fill])
	_poly(inner, Color(col.r, col.g, col.b, 0.35 + 0.6 * s))
	_cv.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(col.r, col.g, col.b, 0.9), 1.5, true)

## Augen-Symbol: Umriss + Fuellung von unten nach Verdacht, Kampf = rot gefuellt mit Ausrufezeichen.
func _eye(c: Vector2, w: float, s: float, col: Color, st: int) -> void:
	var h := w * 0.55
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in 17:
		var x := -w + 2.0 * w * i / 16.0
		var y := h * (1.0 - pow(x / w, 2.0))
		top.append(c + Vector2(x, -y))
		bot.append(c + Vector2(x, y))
	var outline := top.duplicate()
	for i in range(bot.size() - 2, 0, -1):
		outline.append(bot[i])
	_poly(outline, Color(0, 0, 0, 0.5))
	# Fuellung: Pupille waechst mit dem Verdacht
	var pr := h * (0.25 + 0.75 * clampf(s, 0.0, 1.0))
	_cv.draw_circle(c, pr, Color(col.r, col.g, col.b, 0.5 + 0.5 * s))
	outline.append(outline[0])
	_cv.draw_polyline(outline, Color(col.r, col.g, col.b, 0.95), 1.6, true)
	if st >= 2:
		_text_centered("!", c + Vector2(0, -h - 10.0), int(w * 1.3), col)
	elif s > 0.35:
		_text_centered("?", c + Vector2(0, -h - 9.0), int(w * 1.1), col)

func _status(vs: Vector2, alarm: bool) -> void:
	var top := int(director.call("top_state"))
	var txt := "VERBORGEN"
	var col := Color(0.62, 0.78, 0.66)
	if alarm:
		txt = "ALARM"
		col = Color(1.0, 0.2, 0.12) if fmod(_t, 0.8) < 0.5 else Color(0.7, 0.12, 0.08)
	elif top >= 2:
		txt = "ENTDECKT"
		col = Color(1.0, 0.25, 0.15)
	elif top == 1:
		txt = "VERDÄCHTIG"
		col = Color(1.0, 0.72, 0.2)
	var cx := vs.x / 2.0
	var bg := Rect2(cx - 110, 12, 220, 46)
	_cv.draw_rect(bg, Color(0, 0, 0, 0.42))
	_cv.draw_rect(Rect2(bg.position, Vector2(bg.size.x, 2)), Color(col.r, col.g, col.b, 0.85))
	_text_centered(txt, Vector2(cx, 33), 17, col)
	# Lichtmesser
	var l: float = director.get("player_light")
	var bar := Rect2(cx - 80, 44, 160, 6)
	_cv.draw_rect(bar, Color(0.15, 0.15, 0.17, 0.9))
	var lc := Color(0.35, 0.38, 0.5).lerp(Color(1.0, 0.92, 0.65), clampf(l, 0.0, 1.0))
	_cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(l, 0.0, 1.0), bar.size.y)), lc)
	_cv.draw_arc(Vector2(cx - 94, 47), 4.5, 0.0, TAU, 16, Color(0.8, 0.8, 0.85, 0.8), 1.2, true)
	_cv.draw_circle(Vector2(cx - 94, 47), 3.0 * clampf(l, 0.15, 1.0), lc)
	var nr: float = director.get("noise_radius")
	if nr > 0.0:
		var dots := 1 if nr < 2.0 else (2 if nr < 6.0 else 3)
		for i in dots:
			_cv.draw_circle(Vector2(cx + 92 + i * 6, 47), 2.0, Color(0.9, 0.9, 0.9, 0.8))

## Zeilen unter der Statusbox: was der Alarm bewirkt und wie er endet (Sichtkontakt-Countdown).
func _alarm_info(vs: Vector2, alarm: bool) -> void:
	var cx := vs.x / 2.0
	var y := 72.0
	var lines: Array = []
	if alarm:
		if alarm_note != "":
			lines.append([alarm_note, Color(1.0, 0.55, 0.4)])
		var nl: float = director.get("_no_los_t")
		var dv: Variant = director.get("ALARM_DECAY")
		var decay := float(dv) if dv != null else 28.0
		if nl > 0.5:
			lines.append(["Außer Sicht – Alarm endet in %d s" % ceili(maxf(0.0, decay - nl)), Color(0.85, 0.85, 0.8)])
		else:
			lines.append(["Sichtkontakt brechen, um den Alarm zu beenden", Color(0.85, 0.85, 0.8)])
	if _flash_t > 0.0 and _flash_text != "":
		var c := _flash_col
		c.a = clampf(_flash_t / 0.6, 0.0, 1.0)
		lines.append([_flash_text, c])
	if lines.is_empty():
		return
	var h := 22.0 * lines.size() + 6.0
	_cv.draw_rect(Rect2(cx - 230, y - 13, 460, h), Color(0, 0, 0, 0.35))
	for l in lines:
		_text_centered(String(l[0]), Vector2(cx, y), 15, l[1])
		y += 22.0

func _download(c: Vector2, p: float, paused: bool, locked: bool) -> void:
	var w := 300.0
	var r := Rect2(c.x - w / 2.0, c.y, w, 10)
	_cv.draw_rect(Rect2(r.position - Vector2(8, 26), r.size + Vector2(16, 34)), Color(0, 0, 0, 0.5))
	var label := "FUNKPROTOKOLLE  %d %%" % int(p * 100.0)
	var col := Color(0.4, 1.0, 0.6)
	if locked:
		label = "ALARM – ÜBERTRAGUNG GESPERRT"
		col = Color(1.0, 0.3, 0.2)
	elif paused:
		label = "VERBINDUNG UNTERBROCHEN – zurück zum Terminal"
		col = Color(1.0, 0.75, 0.25)
	_text_centered(label, Vector2(c.x, c.y - 10), 15, col)
	_cv.draw_rect(r, Color(0.1, 0.12, 0.1, 0.9))
	_cv.draw_rect(Rect2(r.position, Vector2(w * p, r.size.y)), col)

func _text_centered(t: String, pos: Vector2, fs: int, col: Color) -> void:
	fs = UIStyle.min_fs(fs, UIStyle.hud_scale(_draw.size) if _cv == _ui else 1.0)
	var sz := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := pos + Vector2(-sz.x / 2.0, sz.y * 0.35)
	_cv.draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	_cv.draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _vignette(vs: Vector2, col: Color) -> void:
	var b := 70.0
	var clear := Color(col.r, col.g, col.b, 0.0)
	_poly_c(PackedVector2Array([Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x - b, b), Vector2(b, b)]), PackedColorArray([col, col, clear, clear]))
	_poly_c(PackedVector2Array([Vector2(0, vs.y), Vector2(b, vs.y - b), Vector2(vs.x - b, vs.y - b), Vector2(vs.x, vs.y)]), PackedColorArray([col, clear, clear, col]))
	_poly_c(PackedVector2Array([Vector2(0, 0), Vector2(b, b), Vector2(b, vs.y - b), Vector2(0, vs.y)]), PackedColorArray([col, clear, clear, col]))
	_poly_c(PackedVector2Array([Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(vs.x - b, vs.y - b), Vector2(vs.x - b, b)]), PackedColorArray([col, col, clear, clear]))

## Polygone nur zeichnen, wenn sie triangulierbar sind (sonst Fehlerflut bei winzigen/entarteten Formen).
func _poly(pts: PackedVector2Array, col: Color) -> void:
	if Geometry2D.triangulate_polygon(pts).size() >= 3:
		_cv.draw_colored_polygon(pts, col)

func _poly_c(pts: PackedVector2Array, cols: PackedColorArray) -> void:
	if Geometry2D.triangulate_polygon(pts).size() >= 3:
		_cv.draw_polygon(pts, cols)
