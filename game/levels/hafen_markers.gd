extends CanvasLayer
## Mission "Kräne": Zielmarker im HUD. Pfeilspitze ueber dem Ziel mit Name und Entfernung; liegt das Ziel
## ausserhalb des Bildes oder hinter der Kamera, zeigt ein Randpfeil die Richtung. Rot = Pflichtziel,
## Blau = nicht schiessen (Weber), Weiss = Orientierung. Tote/entfernte Ziele fallen automatisch heraus.

const C_RED := Color(1.0, 0.32, 0.26)
const C_BLUE := Color(0.4, 0.72, 1.0)
const C_WHITE := Color(0.92, 0.92, 0.88)

var _items: Array[Dictionary] = []   ## {n, label, col, off}
var _ctl: Control
var _pulse: float = 0.0

func _ready() -> void:
	layer = 4
	_ctl = Control.new()
	_ctl.name = "Markers"
	_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ctl)
	_ctl.draw.connect(_on_draw)

func add(n: Node3D, label: String, col: Color = C_RED, off: Vector3 = Vector3(0, 1.9, 0)) -> void:
	if n == null or not is_instance_valid(n):
		return
	remove(n)
	_items.append({"n": n, "label": label, "col": col, "off": off})

func remove(n: Node) -> void:
	for i in range(_items.size() - 1, -1, -1):
		if _items[i]["n"] == n:
			_items.remove_at(i)

func clear() -> void:
	_items.clear()

## Marker kurz blinken lassen (Hinweis-Stufe).
func pulse(t: float = 4.0) -> void:
	_pulse = maxf(_pulse, t)

func count() -> int:
	return _items.size()

func _alive(n: Variant) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	var o := n as Object
	if o.has_method("is_alive"):
		return bool(o.call("is_alive"))
	var d: Variant = o.get("dead")
	return not (d is bool and d)

func _process(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta)
	for i in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[i]
		var n: Variant = it["n"]
		if not _alive(n):
			_items.remove_at(i)
	_ctl.queue_redraw()

func _on_draw() -> void:
	if _items.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var sz := _ctl.size
	var sc := sz.y / 1080.0
	var font := ThemeDB.fallback_font
	var fs := int(round(19.0 * sc))
	var margin := 56.0 * sc
	var ctr := sz * 0.5
	var blink := 1.0
	if _pulse > 0.0:
		blink = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.016)
	# Naechste Ziele zuerst; Beschriftungen, die sich ueberlappen wuerden, werden nach oben gestapelt
	# bzw. bei Platzmangel weggelassen (Pfeil bleibt).
	var order: Array = []
	for it: Dictionary in _items:
		var n0 := it["n"] as Node3D
		var wp0: Vector3 = n0.call("marker_point") if n0.has_method("marker_point") else n0.global_position + (it["off"] as Vector3)
		order.append([cam.global_position.distance_to(wp0), it, wp0])
	order.sort_custom(func(a, b): return a[0] < b[0])
	var used: Array[Rect2] = []
	for e: Array in order:
		var it: Dictionary = e[1]
		var col: Color = it["col"]
		col.a = 0.9 * blink
		var wp: Vector3 = e[2]
		var dist: float = e[0]
		var txt := "%s  %d m" % [str(it["label"]), int(round(dist))]
		var behind := cam.is_position_behind(wp)
		var sp := cam.unproject_position(wp)
		var inner := Rect2(Vector2(margin, margin), sz - Vector2(margin, margin) * 2.0)
		if not behind and inner.has_point(sp):
			var tip := sp - Vector2(0, 14.0 * sc)
			var w := 11.0 * sc
			var h := 14.0 * sc
			var tri := PackedVector2Array([tip, tip + Vector2(-w, -h), tip + Vector2(w, -h)])
			_ctl.draw_colored_polygon(tri, col)
			_ctl.draw_polyline(PackedVector2Array([tip, tip + Vector2(-w, -h), tip + Vector2(w, -h), tip]), Color(0, 0, 0, 0.7 * blink), maxf(1.0, 1.5 * sc))
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp := tip + Vector2(-tw * 0.5, -h - 6.0 * sc)
			var ok := false
			for _k in 5:
				var r := Rect2(tp + Vector2(-4, -fs), Vector2(tw + 8, fs + 4))
				var hit := false
				for u in used:
					if u.intersects(r):
						hit = true
						break
				if not hit:
					used.append(r)
					ok = true
					break
				tp.y -= fs + 3.0
			if not ok:
				continue
			if tp.y < tip.y - h - 10.0 * sc:
				_ctl.draw_line(tip + Vector2(0, -h), tp + Vector2(tw * 0.5, 3.0), Color(col, 0.5), maxf(1.0, sc))
			_ctl.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(max(2.0, 4.0 * sc)), Color(0, 0, 0, 0.75 * blink))
			_ctl.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		else:
			var v := sp - ctr
			if behind:
				v = -v
				if v.y < 0.0:
					v.y = absf(v.y) * 0.2   # hinter der Kamera: Pfeil an den unteren/seitlichen Rand
			if v.length() < 1.0:
				v = Vector2(0, 1)
			var hx := sz.x * 0.5 - margin
			var hy := sz.y * 0.5 - margin
			var k := minf(hx / maxf(absf(v.x), 0.001), hy / maxf(absf(v.y), 0.001))
			var p := ctr + v * k
			var d := v.normalized()
			var nrm := Vector2(-d.y, d.x)
			var a := 18.0 * sc
			var tri2 := PackedVector2Array([p + d * a, p - d * a * 0.6 + nrm * a * 0.75, p - d * a * 0.6 - nrm * a * 0.75])
			_ctl.draw_colored_polygon(tri2, col)
			_ctl.draw_polyline(PackedVector2Array([tri2[0], tri2[1], tri2[2], tri2[0]]), Color(0, 0, 0, 0.7 * blink), maxf(1.0, 1.5 * sc))
			var tw2 := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp2 := p - d * (a * 1.6) + Vector2(-tw2 * 0.5, fs * 0.35)
			tp2.x = clampf(tp2.x, 8.0, sz.x - tw2 - 8.0)
			tp2.y = clampf(tp2.y, fs + 4.0, sz.y - 8.0)
			_ctl.draw_string_outline(font, tp2, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(max(2.0, 4.0 * sc)), Color(0, 0, 0, 0.75 * blink))
			_ctl.draw_string(font, tp2, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
