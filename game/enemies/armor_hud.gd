extends CanvasLayer
## Zusatz-HUD fuer gepanzerte Gegner: Abpraller-Marker (stahlblau statt weissem Treffer-X),
## kurze Meldungen ("PANZERUNG DURCHSCHLAGEN", "VISIER GEBROCHEN") und die Boss-Leiste des Juggernauts.
## Wird bei Bedarf einmal pro Szene erzeugt (ArmorHud.get_hud(node)); eigenstaendig, aendert hud.gd nicht.

static var _inst: CanvasLayer = null

var _overlay: Control = null
var _label: Label = null
var _deflect_t: float = 0.0
var _msg_t: float = 0.0
var _boss: Node = null
var _boss_name: String = ""
var _boss_vis: float = 0.0
var _boss_shown: float = 1.0
var _boss_flash: float = 0.0
var _ticks: Array[float] = []
var _time: float = 0.0

const DEFLECT_TIME := 0.22
const STEEL := Color(0.62, 0.78, 0.92)
const AMBER := Color(1.0, 0.68, 0.22)

static func get_hud(from: Node) -> CanvasLayer:
	if _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	if from == null or not from.is_inside_tree():
		return null
	var root: Node = from.get_tree().current_scene
	if root == null:
		root = from.get_tree().root
	var h := CanvasLayer.new()
	h.set_script(load("res://game/enemies/armor_hud.gd"))
	h.name = "ArmorHud"
	root.add_child(h)
	_inst = h
	return h

func _ready() -> void:
	layer = 6
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", AMBER)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("outline_size", 5)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.position = Vector2(-300, 46)
	_label.size = Vector2(600, 30)
	_label.modulate.a = 0.0
	_overlay.add_child(_label)

## Kugel prallt an Panzerung ab (nur fuer Treffer des Spielers).
func show_deflect() -> void:
	_deflect_t = DEFLECT_TIME

func show_message(text: String, seconds: float = 1.6) -> void:
	_label.text = text
	_msg_t = seconds

## Boss-Leiste: boss muss health/max_health haben. ticks = Schwellen (0..1) fuer Taumel-Markierungen.
func set_boss(boss: Node, title: String, ticks: Array[float] = []) -> void:
	_boss = boss
	_boss_name = title
	_ticks = ticks
	_boss_shown = 1.0

func boss_hit() -> void:
	_boss_flash = 1.0

func _process(delta: float) -> void:
	_time += delta
	_deflect_t = maxf(_deflect_t - delta, 0.0)
	_boss_flash = maxf(_boss_flash - delta * 4.0, 0.0)
	if _msg_t > 0.0:
		_msg_t -= delta
		_label.modulate.a = clampf(_msg_t * 3.0, 0.0, 1.0)
		_label.scale = Vector2.ONE
	else:
		_label.modulate.a = 0.0
	var want := 0.0
	if _boss != null and is_instance_valid(_boss):
		var alive: bool = _boss.has_method("is_alive") and bool(_boss.call("is_alive"))
		var engaged: bool = bool(_boss.get("boss_engaged")) if _boss.get("boss_engaged") != null else true
		if engaged and alive:
			want = 1.0
		var r := clampf(float(_boss.get("health")) / maxf(float(_boss.get("max_health")), 1.0), 0.0, 1.0)
		_boss_shown = move_toward(_boss_shown, r, delta * 0.6)
		if not alive:
			_boss_shown = 0.0
	_boss_vis = move_toward(_boss_vis, want, delta * (2.0 if want > 0.0 else 0.8))
	_overlay.queue_redraw()

func _draw_overlay() -> void:
	var size := _overlay.size
	var c := size * 0.5
	if _deflect_t > 0.0:
		var k := _deflect_t / DEFLECT_TIME
		var al := minf(1.0, k * 1.8)
		var col := Color(STEEL.r, STEEL.g, STEEL.b, al)
		var sh := Color(0, 0, 0, al * 0.5)
		# Raute aus vier kurzen Strichen (statt X), leicht gespreizt
		var r0 := 6.0 + (1.0 - k) * 4.0
		var r1 := r0 + 7.0
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_overlay.draw_line(c + d * r0 + Vector2(1, 1), c + d * r1 + Vector2(1, 1), sh, 3.0, true)
			_overlay.draw_line(c + d * r0, c + d * r1, col, 2.0, true)
		_overlay.draw_arc(c, r1 + 3.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, al * 0.45), 1.2, true)
	if _boss_vis > 0.01 and _boss != null and is_instance_valid(_boss):
		var a := _boss_vis
		var w := minf(560.0, size.x - 64.0)
		var x0 := c.x - w * 0.5
		var y := 54.0
		var h := 9.0
		var r := clampf(float(_boss.get("health")) / maxf(float(_boss.get("max_health")), 1.0), 0.0, 1.0)
		var font := ThemeDB.fallback_font
		var title_col := Color(1, 1, 1, 0.9 * a)
		_overlay.draw_string_outline(font, Vector2(x0, y - 10.0), _boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0, 0.6 * a))
		_overlay.draw_string(font, Vector2(x0, y - 10.0), _boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, title_col)
		var status := ""
		if _boss.has_method("boss_status"):
			status = str(_boss.call("boss_status"))
		if status != "":
			_overlay.draw_string_outline(font, Vector2(x0, y - 10.0), status, HORIZONTAL_ALIGNMENT_RIGHT, w, 13, 4, Color(0, 0, 0, 0.6 * a))
			_overlay.draw_string(font, Vector2(x0, y - 10.0), status, HORIZONTAL_ALIGNMENT_RIGHT, w, 13, Color(AMBER.r, AMBER.g, AMBER.b, 0.9 * a))
		_overlay.draw_rect(Rect2(x0 - 2.0, y - 2.0, w + 4.0, h + 4.0), Color(0, 0, 0, 0.55 * a))
		_overlay.draw_rect(Rect2(x0, y, w, h), Color(1, 1, 1, 0.08 * a))
		# verzoegerter Schaden (hell) + aktueller Wert
		_overlay.draw_rect(Rect2(x0, y, w * _boss_shown, h), Color(1.0, 0.85, 0.6, 0.55 * a))
		var bar := Color(0.86, 0.2, 0.12, 0.95 * a).lerp(Color(1, 1, 1, a), _boss_flash * 0.6)
		_overlay.draw_rect(Rect2(x0, y, w * r, h), bar)
		for t in _ticks:
			var tx := x0 + w * t
			_overlay.draw_line(Vector2(tx, y - 3.0), Vector2(tx, y + h + 3.0), Color(0, 0, 0, 0.8 * a), 2.0)
