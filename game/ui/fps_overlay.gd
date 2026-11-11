extends CanvasLayer
## Kleines Leistungs-Overlay (Graphics-Autoload, Option "graphics/fps_overlay"):
## FPS, Frametime (Mittel / schlechteste 1 %), GPU-Zeit und ein Frametime-Graph der letzten ~3 s.
## Laeuft auch im Pausenmenue (PROCESS_MODE_ALWAYS), liegt ueber allem.

const SAMPLES := 180
const GRAPH_MAX_MS := 50.0   # oberer Rand des Graphen (20 FPS)

var _times := PackedFloat32Array()   # Frametimes in ms (Ringpuffer)
var _head: int = 0
var _last_us: int = 0
var _label: Label
var _graph: Control
var _acc: float = 0.0


func _ready() -> void:
	layer = 127
	process_mode = Node.PROCESS_MODE_ALWAYS
	_times.resize(SAMPLES)
	_times.fill(0.0)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(8, 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	box.add_child(_label)
	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(SAMPLES, 40)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.draw.connect(_draw_graph)
	box.add_child(_graph)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_last_us = Time.get_ticks_usec()


func _exit_tree() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)


func _process(_delta: float) -> void:
	# echte Zeit (unabhaengig von Engine.time_scale / Pause)
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_us) / 1000.0
	_last_us = now
	_times[_head] = ms
	_head = (_head + 1) % SAMPLES
	_graph.queue_redraw()
	_acc += ms
	if _acc < 250.0:
		return
	_acc = 0.0
	var sum := 0.0
	var n := 0
	var sorted := PackedFloat32Array()
	for t in _times:
		if t > 0.0:
			sum += t
			n += 1
			sorted.append(t)
	if n == 0:
		return
	sorted.sort()
	var avg := sum / float(n)
	var worst := sorted[clampi(int(float(n) * 0.99), 0, n - 1)]
	var vp_rid := get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var vp_size := get_viewport().get_visible_rect().size
	var scale3d := get_viewport().scaling_3d_scale
	_label.text = "%d FPS   %.1f ms   1%%: %.1f ms\nGPU %.1f ms   %dx%d @ %d %%" % [
		roundi(1000.0 / avg), avg, worst, gpu, int(vp_size.x), int(vp_size.y), roundi(scale3d * 100.0)]


func _draw_graph() -> void:
	var h := _graph.size.y
	_graph.draw_rect(Rect2(Vector2.ZERO, _graph.size), Color(1, 1, 1, 0.06))
	# Hilfslinien: 60 FPS (16,7 ms) und 30 FPS (33,3 ms)
	for ref in [16.667, 33.333]:
		var y := h - h * float(ref) / GRAPH_MAX_MS
		_graph.draw_line(Vector2(0, y), Vector2(SAMPLES, y), Color(1, 1, 1, 0.18), 1.0)
	for i in SAMPLES:
		var t := _times[(_head + i) % SAMPLES]
		if t <= 0.0:
			continue
		var bh := minf(t / GRAPH_MAX_MS, 1.0) * h
		var col := Color(0.4, 1.0, 0.45) if t < 17.5 else (Color(1.0, 0.85, 0.3) if t < 34.0 else Color(1.0, 0.35, 0.3))
		_graph.draw_line(Vector2(i + 0.5, h), Vector2(i + 0.5, h - bh), col, 1.0)
