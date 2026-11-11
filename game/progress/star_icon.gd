extends Control
## Gezeichneter Stern (unabhaengig von Schriftart-Glyphen). filled = Bernstein, sonst Umriss.
## Nutzung: var s = StarIcon.new(); s.setup(24.0, true)

var filled: bool = false
var fill_color: Color = Color(1.0, 0.72, 0.28)
var line_color: Color = Color(0.62, 0.66, 0.6, 0.55)
var glow: float = 0.0          ## 0..1, zusaetzlicher Schein (Animation im Abschluss-Bildschirm)


func setup(px: float, on: bool) -> Control:
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	pivot_offset = Vector2(px, px) * 0.5
	filled = on
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self


func set_filled(on: bool) -> void:
	filled = on
	queue_redraw()


func set_glow(g: float) -> void:
	glow = g
	queue_redraw()


func _points(r_out: float, r_in: float) -> PackedVector2Array:
	var c := size * 0.5
	var pts := PackedVector2Array()
	for i in 10:
		var r := r_out if i % 2 == 0 else r_in
		var a := -PI * 0.5 + float(i) * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	if glow > 0.01:
		draw_circle(size * 0.5, r * (1.0 + glow * 0.6), Color(fill_color.r, fill_color.g, fill_color.b, 0.18 * glow))
	var pts := _points(r * 0.96, r * 0.42)
	if filled:
		draw_colored_polygon(pts, fill_color)
	else:
		draw_colored_polygon(pts, Color(0, 0, 0, 0.25))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, fill_color if filled else line_color, maxf(1.0, r * 0.08), true)
