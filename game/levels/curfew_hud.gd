extends CanvasLayer
## Schleich-HUD fuer "curfew": Entdeckungsanzeige je Wache (ueber dem Kopf bzw. Randpfeil), Status oben
## (VERBORGEN / VERDÄCHTIG / ENTDECKT / ALARM) mit Lichtmesser, Download-Balken, Takedown-Hinweis,
## Alarm-Vignette und Loesch-Einblendung.

var director: Node
var takedown: Node
var terminal: Node

var _draw: Control
var _font: Font
var _t: float = 0.0
var _wipe: ColorRect
var _wipe_label: Label

func _ready() -> void:
	layer = 6
	name = "CurfewHUD"
	_font = ThemeDB.fallback_font
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)
	_wipe = ColorRect.new()
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe.color = Color(0, 0, 0, 0)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wipe)
	_wipe_label = Label.new()
	_wipe_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wipe_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wipe_label.add_theme_font_size_override("font_size", 30)
	_wipe_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.2))
	_wipe_label.modulate.a = 0.0
	_wipe.add_child(_wipe_label)

func _process(delta: float) -> void:
	_t += delta
	_draw.queue_redraw()

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
	var cam := _draw.get_viewport().get_camera_3d()
	var vs := _draw.size
	var center := vs / 2.0
	var alarm: bool = director.get("alarm")
	if alarm:
		_vignette(vs, Color(0.9, 0.05, 0.03, 0.10 + 0.07 * sin(_t * 6.0)))
	if cam != null:
		for w in director.get("watchers"):
			if not is_instance_valid(w) or not bool(w.call("is_watcher_alive")):
				continue
			var st := int(w.call("get_watch_state"))
			var s := float(w.call("get_suspicion"))
			if st <= 0 and s < 0.03:
				continue
			_marker(cam, vs, center, w.call("get_watch_pos"), s, st)
	_status(vs, alarm)
	var y := center.y + 142.0
	if takedown != null and is_instance_valid(takedown) and takedown.get("candidate") != null and not bool(takedown.call("busy")):
		_text_centered("[F] Lautlos ausschalten", Vector2(center.x, y), 19, Color(0.95, 0.92, 0.8))
	if terminal != null and is_instance_valid(terminal) and bool(terminal.get("downloading")):
		_download(Vector2(center.x, center.y + 176.0), float(terminal.get("progress")), bool(terminal.get("paused")), bool(terminal.get("locked")))

func _col(st: int, s: float) -> Color:
	if st >= 2:
		return Color(1.0, 0.18, 0.12)
	return Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.62, 0.1), clampf(s * 1.6, 0.0, 1.0))

func _marker(cam: Camera3D, vs: Vector2, center: Vector2, wp: Vector3, s: float, st: int) -> void:
	var col := _col(st, s)
	var behind := cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp)
	var on_screen := not behind and sp.x > 30 and sp.x < vs.x - 30 and sp.y > 30 and sp.y < vs.y - 30
	if on_screen:
		var dist := cam.global_position.distance_to(wp)
		var sc := clampf(14.0 / maxf(dist, 1.0), 0.55, 1.15)
		_eye(sp + Vector2(0, -6), 15.0 * sc, s, col, st)
		return
	# Randpfeil auf einem Ring um die Bildmitte
	var local := cam.global_transform.basis.inverse() * (wp - cam.global_position)
	var dir2 := Vector2(local.x, local.z)
	if dir2.length() < 0.01:
		return
	var ang := atan2(dir2.x, -dir2.y)     # 0 = vorn (oben), positiv = rechts
	var r := 170.0
	var p := center + Vector2(sin(ang), -cos(ang)) * r
	var fwd := Vector2(sin(ang), -cos(ang))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := p + fwd * 16.0
	var pts := PackedVector2Array([tip, p - fwd * 6.0 + side * 13.0, p - fwd * 6.0 - side * 13.0])
	_poly(pts, Color(0, 0, 0, 0.45))
	var fill := clampf(s, 0.15, 1.0)
	var inner := PackedVector2Array([p - fwd * 6.0 + (tip - (p - fwd * 6.0)) * 1.0, p - fwd * 6.0 + side * 13.0 * fill, p - fwd * 6.0 - side * 13.0 * fill])
	_poly(inner, Color(col.r, col.g, col.b, 0.35 + 0.6 * s))
	_draw.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(col.r, col.g, col.b, 0.9), 1.5, true)

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
	_draw.draw_circle(c, pr, Color(col.r, col.g, col.b, 0.5 + 0.5 * s))
	outline.append(outline[0])
	_draw.draw_polyline(outline, Color(col.r, col.g, col.b, 0.95), 1.6, true)
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
	_draw.draw_rect(bg, Color(0, 0, 0, 0.42))
	_draw.draw_rect(Rect2(bg.position, Vector2(bg.size.x, 2)), Color(col.r, col.g, col.b, 0.85))
	_text_centered(txt, Vector2(cx, 33), 17, col)
	# Lichtmesser
	var l: float = director.get("player_light")
	var bar := Rect2(cx - 80, 44, 160, 6)
	_draw.draw_rect(bar, Color(0.15, 0.15, 0.17, 0.9))
	var lc := Color(0.35, 0.38, 0.5).lerp(Color(1.0, 0.92, 0.65), clampf(l, 0.0, 1.0))
	_draw.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(l, 0.0, 1.0), bar.size.y)), lc)
	_draw.draw_arc(Vector2(cx - 94, 47), 4.5, 0.0, TAU, 16, Color(0.8, 0.8, 0.85, 0.8), 1.2, true)
	_draw.draw_circle(Vector2(cx - 94, 47), 3.0 * clampf(l, 0.15, 1.0), lc)
	var nr: float = director.get("noise_radius")
	if nr > 0.0:
		var dots := 1 if nr < 2.0 else (2 if nr < 6.0 else 3)
		for i in dots:
			_draw.draw_circle(Vector2(cx + 92 + i * 6, 47), 2.0, Color(0.9, 0.9, 0.9, 0.8))

func _download(c: Vector2, p: float, paused: bool, locked: bool) -> void:
	var w := 300.0
	var r := Rect2(c.x - w / 2.0, c.y, w, 10)
	_draw.draw_rect(Rect2(r.position - Vector2(8, 26), r.size + Vector2(16, 34)), Color(0, 0, 0, 0.5))
	var label := "FUNKPROTOKOLLE  %d %%" % int(p * 100.0)
	var col := Color(0.4, 1.0, 0.6)
	if locked:
		label = "ALARM – ÜBERTRAGUNG GESPERRT"
		col = Color(1.0, 0.3, 0.2)
	elif paused:
		label = "VERBINDUNG UNTERBROCHEN – zurück zum Terminal"
		col = Color(1.0, 0.75, 0.25)
	_text_centered(label, Vector2(c.x, c.y - 10), 15, col)
	_draw.draw_rect(r, Color(0.1, 0.12, 0.1, 0.9))
	_draw.draw_rect(Rect2(r.position, Vector2(w * p, r.size.y)), col)

func _text_centered(t: String, pos: Vector2, fs: int, col: Color) -> void:
	var sz := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := pos + Vector2(-sz.x / 2.0, sz.y * 0.35)
	_draw.draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	_draw.draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

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
		_draw.draw_colored_polygon(pts, col)

func _poly_c(pts: PackedVector2Array, cols: PackedColorArray) -> void:
	if Geometry2D.triangulate_polygon(pts).size() >= 3:
		_draw.draw_polygon(pts, cols)
