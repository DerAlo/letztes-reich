extends CanvasLayer
## Squad-Befehle light: kleine Anzeige unten links (Begleiter + aktueller Befehl + Tasten), Zielmarker im Raum
## (Raute fuer "dort hin"/"halten", rote Klammern ueber dem Feuerziel) und der einmalige Tutorial-Hinweis.
## Wird von squad_orders.gd erzeugt und gefuettert; eigene Ebene, hud.gd bleibt unberuehrt.

const C_TEXT := Color(0.9, 0.93, 0.9, 0.85)
const C_DIM := Color(0.8, 0.84, 0.8, 0.55)
const C_LENA := Color(0.38, 0.92, 0.74)      ## wie StoryUI "Lena"
const C_FIRE := Color(1.0, 0.36, 0.25)

var orders: Node = null                       ## squad_orders.gd
var _root: Control
var _canvas: Control
var _sroot: Control
var _box: VBoxContainer
var _title: Label
var _state: Label
var _keys: Label
var _hint: Label
var _hint_t: float = 0.0
var _flash_t: float = 0.0
var _flash_text: String = ""

func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_markers)
	_root.add_child(_canvas)
	# Textfelder in 1080p-Pixeln skaliert (kleine Fenster); _canvas bleibt in echten Pixeln (unproject_position)
	_sroot = UIStyle.HudRoot.new()
	_root.add_child(_sroot)
	_box = VBoxContainer.new()
	_box.anchor_left = 0.0
	_box.anchor_right = 0.0
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_left = 36.0
	_box.offset_right = 420.0
	_box.offset_top = -150.0
	_box.offset_bottom = -40.0
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 0)
	_sroot.add_child(_box)
	_title = _label(13, C_DIM)
	_state = _label(19, C_TEXT)
	_keys = _label(12, C_DIM)
	_box.add_child(_title)
	_box.add_child(_state)
	_box.add_child(_keys)
	_hint = _label(17, Color(1.0, 0.86, 0.5, 0.95))
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.offset_left = -380.0
	_hint.offset_right = 380.0
	_hint.offset_top = 128.0
	_hint.offset_bottom = 190.0
	_hint.visible = false
	_sroot.add_child(_hint)

func _label(fs: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func show_hint(text: String, dur: float = 10.0) -> void:
	_hint.text = text
	_hint_t = dur

## Kurze Rueckmeldung im Statusfeld (z. B. "KEIN ZIEL"), auch wenn der Funk schweigt.
func flash(text: String, dur: float = 1.4) -> void:
	_flash_text = text
	_flash_t = dur

func _process(delta: float) -> void:
	_hint_t = maxf(0.0, _hint_t - delta)
	_flash_t = maxf(0.0, _flash_t - delta)
	_hint.visible = _hint_t > 0.0
	_hint.modulate.a = clampf(_hint_t / 0.8, 0.0, 1.0)
	var c: Object = orders.get("companion") if orders != null else null
	var on := orders != null and bool(orders.call("is_active"))
	_box.visible = on
	if on:
		var name_s := str(orders.get("companion_name")).to_upper()
		_title.text = name_s
		_title.add_theme_color_override("font_color", Color(C_LENA, 0.8))
		var st: String = orders.call("order_label")
		if _flash_t > 0.0:
			st = _flash_text
		_state.text = st
		var fire := c != null and c.call("attack_target") != null
		_state.add_theme_color_override("font_color", C_FIRE if fire and _flash_t <= 0.0 else C_TEXT)
		_keys.text = "[%s] Feuer / Dort hin   [%s] Halt / Folgen" % [orders.call("key_name", "squad_order"), orders.call("key_name", "squad_hold")]
	_canvas.queue_redraw()

func _draw_markers() -> void:
	if orders == null or not bool(orders.call("is_active")):
		return
	var c: Object = orders.get("companion")
	var cam := get_viewport().get_camera_3d()
	if c == null or cam == null:
		return
	var m: Dictionary = c.call("marker") if c.has_method("marker") else {}
	if m.has("pos"):
		var wp: Vector3 = m["pos"]
		_draw_world_diamond(cam, wp + Vector3.UP * 0.15, C_LENA, str(orders.call("order_short")))
	var t: Node3D = c.call("attack_target") if c.has_method("attack_target") else null
	if t != null and is_instance_valid(t):
		_draw_world_brackets(cam, t.global_position + Vector3.UP * 1.0)

func _draw_world_diamond(cam: Camera3D, wp: Vector3, col: Color, text: String) -> void:
	if cam.is_position_behind(wp):
		return
	var sp := cam.unproject_position(wp)
	var r := 9.0
	var pts := PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0), sp + Vector2(0, -r)])
	_canvas.draw_polyline(pts, Color(0, 0, 0, 0.6), 4.0, true)
	_canvas.draw_polyline(pts, col, 2.0, true)
	var d := cam.global_position.distance_to(wp)
	var font := ThemeDB.fallback_font
	var s := "%s  %d m" % [text, roundi(d)]
	_canvas.draw_string_outline(font, sp + Vector2(-40, -16), s, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, 4, Color(0, 0, 0, 0.8))
	_canvas.draw_string(font, sp + Vector2(-40, -16), s, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, col)

func _draw_world_brackets(cam: Camera3D, wp: Vector3) -> void:
	if cam.is_position_behind(wp):
		return
	var sp := cam.unproject_position(wp)
	var d := maxf(cam.global_position.distance_to(wp), 1.0)
	var h := clampf(900.0 / d, 10.0, 60.0)
	var w := h * 0.55
	var k := h * 0.3
	var col := C_FIRE
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := sp + Vector2(w * sx, h * sy)
			_canvas.draw_line(corner, corner + Vector2(-k * sx, 0), col, 2.0, true)
			_canvas.draw_line(corner, corner + Vector2(0, -k * sy), col, 2.0, true)
