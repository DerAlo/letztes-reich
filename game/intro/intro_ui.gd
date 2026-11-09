extends Node
## 2D-Ebenen des Intros: TV-Filter, Senderlogo „EU24 Nachrichten“ (fiktiv), Bauchbinde, Laufband,
## Lagekarten-Kopf mit Datumsstempel, Untertitel, Ueberspringen-Hinweis und Schwarzblende.
## Alle Elemente liegen in einem 1920x1080-Rahmen, der auf die Fenstergroesse skaliert wird.

const TV_SHADER: Shader = preload("res://game/intro/tv_filter.gdshader")
const REF := Vector2(1920, 1080)

const C_NAVY := Color(0.04, 0.09, 0.22)
const C_NAVY2 := Color(0.07, 0.15, 0.34)
const C_AMBER := Color(0.98, 0.72, 0.16)
const C_RED := Color(0.82, 0.08, 0.08)
const C_WHITE := Color(0.96, 0.96, 0.94)

signal tick_sound

var tv: ColorRect
var tv_mat: ShaderMaterial
var black: ColorRect

var _root: Control
var _top: Control
var _ident: Control
var _ident_logo: Control
var _news: Control
var _lower: Control
var _lower_head: Label
var _lower_sub: Label
var _clock: Label
var _ticker: Control
var _ticker_label: Label
var _ticker_x: float = 0.0
var _map: Control
var _stamp_date: Label
var _stamp_text: Label
var _stamp_box: Control
var _sub: RichTextLabel
var _sub_tw: Tween
var _hint: Control
var _type_tw: Tween

func _ready() -> void:
	# Ebene 1: TV-Filter (liest das 3D-Bild)
	var l1 := _layer(1)
	tv = ColorRect.new()
	tv.set_anchors_preset(Control.PRESET_FULL_RECT)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv_mat = ShaderMaterial.new()
	tv_mat.shader = TV_SHADER
	tv.material = tv_mat
	l1.add_child(tv)
	# Ebene 2: Grafiken
	var l2 := _layer(2)
	_root = Control.new()
	_root.size = REF
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l2.add_child(_root)
	_build_news()
	_build_map()
	_build_ident()
	_build_subtitles()
	# Ebene 3: Schwarzblende + Hinweis
	var l3 := _layer(3)
	black = ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l3.add_child(black)
	_top = Control.new()
	_top.size = REF
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l3.add_child(_top)
	_build_hint()
	get_viewport().size_changed.connect(_fit)
	_fit()

func _process(delta: float) -> void:
	if _ticker.visible:
		_ticker_x -= 150.0 * delta
		var w := _ticker_label.get_minimum_size().x * 0.5
		if w > 0.0 and _ticker_x < -w:
			_ticker_x += w
		_ticker_label.position.x = 250.0 + _ticker_x

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := minf(vs.x / REF.x, vs.y / REF.y)
	var off := (vs - REF * s) * 0.5
	for c: Control in [_root, _top]:
		c.scale = Vector2(s, s)
		c.position = off

# --------------------------------------------------------------------------- Helfer

func _layer(n: int) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.layer = 80 + n
	add_child(l)
	return l

static func font(weight: int = 600, mono: bool = false) -> SystemFont:
	var f := SystemFont.new()
	if mono:
		f.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	else:
		f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Segoe UI", "Arial", "sans-serif"])
	f.font_weight = weight
	return f

func _rect(parent: Control, pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

func _text(parent: Control, txt: String, pos: Vector2, size: int, col: Color, weight: int = 600, mono: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.add_theme_font_override("font", font(weight, mono))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _box(parent: Control, pos: Vector2, size: Vector2) -> Control:
	var c := Control.new()
	c.position = pos
	c.size = size
	c.clip_contents = true
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c

## Fiktives Senderlogo: blaues Quadrat „EU24“ mit Bernstein-Akzent, darunter „NACHRICHTEN“.
func _logo(parent: Control, pos: Vector2, s: float) -> Control:
	var c := Control.new()
	c.position = pos
	c.scale = Vector2(s, s)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	_rect(c, Vector2(0, 0), Vector2(150, 110), C_NAVY2)
	_rect(c, Vector2(0, 0), Vector2(10, 110), C_AMBER)
	_rect(c, Vector2(10, 96), Vector2(140, 14), C_NAVY)
	_text(c, "EU", Vector2(22, -6), 64, C_WHITE, 800)
	_text(c, "24", Vector2(92, 2), 46, C_AMBER, 800)
	var n := _text(c, "NACHRICHTEN", Vector2(22, 66), 22, Color(0.8, 0.86, 0.95), 600)
	n.add_theme_constant_override("outline_size", 0)
	return c

# --------------------------------------------------------------------------- Senderkennung (Vollbild)

func _build_ident() -> void:
	_ident = Control.new()
	_ident.size = REF
	_ident.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ident)
	var bg := TextureRect.new()
	var g := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.08, 0.17, 0.38))
	gr.set_color(1, Color(0.01, 0.03, 0.08))
	g.gradient = gr
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.45)
	g.fill_to = Vector2(1.1, 1.0)
	g.width = 256
	g.height = 144
	bg.texture = g
	bg.size = REF
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ident.add_child(bg)
	# Lichtstreifen
	for i in 6:
		var r := _rect(_ident, Vector2(-200 + i * 380, 0), Vector2(60, 1080), Color(0.3, 0.5, 0.9, 0.05))
		r.rotation = 0.35
	_ident_logo = _logo(_ident, Vector2(960 - 225, 540 - 200), 3.0)
	_ident_logo.pivot_offset = Vector2(75, 55)
	var sl := _text(_ident, "SONDERSENDUNG", Vector2(0, 760), 40, C_AMBER, 700)
	sl.size = Vector2(1920, 50)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ident.visible = false

func show_ident(dur: float) -> void:
	_ident.visible = true
	_ident.modulate.a = 1.0
	_ident_logo.scale = Vector2(2.6, 2.6)
	var tw := create_tween()
	tw.tween_property(_ident_logo, "scale", Vector2(3.0, 3.0), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func hide_ident() -> void:
	_ident.visible = false

# --------------------------------------------------------------------------- Nachrichten-Overlay

func _build_news() -> void:
	_news = Control.new()
	_news.size = REF
	_news.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_news)
	_logo(_news, Vector2(70, 56), 0.9)
	var live := _rect(_news, Vector2(1640, 64), Vector2(96, 40), C_RED)
	_text(live, "LIVE", Vector2(16, 2), 30, C_WHITE, 800)
	_clock = _text(_news, "23:47", Vector2(1750, 62), 32, C_WHITE, 600)
	# Bauchbinde
	_lower = _box(_news, Vector2(110, 800), Vector2(1500, 170))
	var tab := _rect(_lower, Vector2(0, 0), Vector2(250, 46), C_RED)
	_text(tab, "EILMELDUNG", Vector2(18, 4), 32, C_WHITE, 800)
	_rect(_lower, Vector2(0, 46), Vector2(1500, 74), Color(0.97, 0.97, 0.95, 0.96))
	_rect(_lower, Vector2(0, 46), Vector2(8, 74), C_AMBER)
	_lower_head = _text(_lower, "", Vector2(28, 52), 50, Color(0.05, 0.07, 0.14), 700)
	var sub_bg := _rect(_lower, Vector2(0, 120), Vector2(1500, 42), Color(C_NAVY.r, C_NAVY.g, C_NAVY.b, 0.92))
	_lower_sub = _text(sub_bg, "", Vector2(28, 4), 28, Color(0.85, 0.9, 1.0), 500)
	_lower.visible = false
	# Laufband
	_ticker = _box(_news, Vector2(0, 1010), Vector2(1920, 52))
	_rect(_ticker, Vector2(0, 0), Vector2(1920, 52), Color(0.02, 0.05, 0.13, 0.95))
	_ticker_label = _text(_ticker, "", Vector2(250, 6), 32, Color(0.92, 0.93, 0.96), 500)
	var tick_tab := _rect(_ticker, Vector2(0, 0), Vector2(230, 52), C_AMBER)
	_text(tick_tab, "EU24 +++", Vector2(22, 6), 32, C_NAVY, 800)
	var items: Array[String] = [
		"Lettland ruft den nationalen Notstand aus",
		"Flugverbot über dem gesamten Baltikum",
		"Satellitenbilder: Hunderte Panzer bei Pskow",
		"Evakuierung grenznaher Gemeinden in Lettgallen angeordnet",
		"EU-Kampfgruppen erhalten Marschbefehl",
		"Börsen auf Talfahrt, Gaspreis auf Rekordhoch",
		"Russische Marine verlegt Einheiten in die Ostsee",
		"Moskau: „Übungen verlaufen planmäßig“",
	]
	var t := "   +++   ".join(items) + "   +++   "
	_ticker_label.text = t + t
	_news.visible = false

func show_news(on: bool) -> void:
	_news.visible = on
	_ticker.visible = on

func set_clock(txt: String) -> void:
	_clock.text = txt

## Neue Bauchbinde: schiebt sich von links herein.
func set_headline(head: String, sub: String) -> void:
	_lower.visible = true
	_lower_head.text = head
	_lower_sub.text = sub
	_lower.size.x = 0.0
	var tw := create_tween()
	tw.tween_property(_lower, "size:x", 1500.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func hide_headline() -> void:
	_lower.visible = false

# --------------------------------------------------------------------------- Lagekarte

func _build_map() -> void:
	_map = Control.new()
	_map.size = REF
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map)
	var mc := Color(0.55, 0.85, 1.0)
	_rect(_map, Vector2(70, 60), Vector2(6, 78), mc)
	_text(_map, "LAGEBILD BALTIKUM", Vector2(92, 52), 48, Color(0.85, 0.95, 1.0), 700)
	_text(_map, "EU-KAMPFGRUPPE NORD  ·  VS – NUR FÜR DEN DIENSTGEBRAUCH", Vector2(94, 108), 22, Color(0.5, 0.75, 0.9), 500, true)
	# Legende
	var lg := Control.new()
	lg.position = Vector2(1530, 70)
	_map.add_child(lg)
	_rect(lg, Vector2(0, 8), Vector2(28, 18), Color(1.0, 0.15, 0.1))
	_text(lg, "Russische Verbände", Vector2(40, 0), 24, Color(0.85, 0.9, 0.95), 500)
	_rect(lg, Vector2(0, 46), Vector2(28, 18), Color(0.25, 0.55, 1.0))
	_text(lg, "EU-Verbände", Vector2(40, 38), 24, Color(0.85, 0.9, 0.95), 500)
	# Rahmen-Ecken
	for p: Vector2 in [Vector2(40, 30), Vector2(1840, 30), Vector2(40, 1010), Vector2(1840, 1010)]:
		_rect(_map, p, Vector2(40, 3), Color(mc.r, mc.g, mc.b, 0.6))
		_rect(_map, p + Vector2(0 if p.x < 960 else 37, 0 if p.y < 540 else -37), Vector2(3, 40), Color(mc.r, mc.g, mc.b, 0.6))
	_text(_map, "N 56°57′  E 027°10′", Vector2(1560, 925), 22, Color(0.45, 0.7, 0.85), 500, true)
	# Datumsstempel
	_stamp_box = Control.new()
	_stamp_box.position = Vector2(90, 800)
	_map.add_child(_stamp_box)
	_rect(_stamp_box, Vector2(0, 0), Vector2(1100, 118), Color(0.0, 0.02, 0.05, 0.72))
	_rect(_stamp_box, Vector2(0, 0), Vector2(6, 118), C_AMBER)
	_stamp_date = _text(_stamp_box, "", Vector2(26, 10), 36, C_AMBER, 700, true)
	_stamp_text = _text(_stamp_box, "", Vector2(26, 60), 32, Color(0.9, 0.94, 1.0), 500, true)
	_stamp_box.visible = false
	_map.visible = false

func show_map(on: bool) -> void:
	_map.visible = on
	if on:
		_map.modulate.a = 0.0
		create_tween().tween_property(_map, "modulate:a", 1.0, 1.5)

func fade_map(dur: float) -> void:
	create_tween().tween_property(_map, "modulate:a", 0.0, dur)

## Datumsstempel im Fernschreiber-Stil (Zeichen fuer Zeichen).
func stamp(date_line: String, text_line: String) -> void:
	_stamp_box.visible = true
	_stamp_date.text = date_line
	_stamp_text.text = text_line
	_stamp_date.visible_characters = 0
	_stamp_text.visible_characters = 0
	if _type_tw != null and _type_tw.is_valid():
		_type_tw.kill()
	_type_tw = create_tween()
	var n1 := date_line.length()
	var n2 := text_line.length()
	_type_tw.tween_method(func(v: float) -> void: _type(_stamp_date, v), 0.0, float(n1), n1 * 0.035)
	_type_tw.tween_method(func(v: float) -> void: _type(_stamp_text, v), 0.0, float(n2), n2 * 0.028)

func _type(l: Label, v: float) -> void:
	var n := int(v)
	if n != l.visible_characters:
		l.visible_characters = n
		if n % 2 == 0:
			tick_sound.emit()

# --------------------------------------------------------------------------- Untertitel / Hinweis

func _build_subtitles() -> void:
	_sub = RichTextLabel.new()
	_sub.bbcode_enabled = true
	_sub.fit_content = true
	_sub.scroll_active = false
	_sub.position = Vector2(260, 880)
	_sub.size = Vector2(1400, 120)
	_sub.add_theme_font_override("normal_font", font(500))
	_sub.add_theme_font_override("bold_font", font(700))
	_sub.add_theme_font_size_override("normal_font_size", 36)
	_sub.add_theme_font_size_override("bold_font_size", 36)
	_sub.add_theme_color_override("default_color", Color(0.95, 0.95, 0.92))
	_sub.add_theme_constant_override("outline_size", 8)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.modulate.a = 0.0
	_root.add_child(_sub)

## Untertitel; y-Lage haengt vom Abschnitt ab (ueber der Bauchbinde bzw. dem Stempel).
func subtitle(speaker: String, text: String, dur: float, y: float = 690.0) -> void:
	_sub.position.y = y
	_sub.text = "[b][color=#f2c14e]%s:[/color][/b] %s" % [speaker, text]
	if _sub_tw != null and _sub_tw.is_valid():
		_sub_tw.kill()
	_sub_tw = create_tween()
	_sub_tw.tween_property(_sub, "modulate:a", 1.0, 0.2)
	_sub_tw.tween_interval(maxf(dur - 0.5, 0.5))
	_sub_tw.tween_property(_sub, "modulate:a", 0.0, 0.3)

func _build_hint() -> void:
	_hint = Control.new()
	_hint.position = Vector2(1500, 966)
	_hint.modulate.a = 0.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(_hint)
	var key := _rect(_hint, Vector2(0, 0), Vector2(150, 40), Color(0.0, 0.0, 0.0, 0.55))
	var k := _text(key, "LEERTASTE", Vector2(0, 4), 24, Color(0.95, 0.95, 0.92), 700)
	k.size = Vector2(150, 34)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text(_hint, "Überspringen", Vector2(164, 3), 26, Color(0.9, 0.9, 0.88), 500)

func show_hint() -> void:
	create_tween().tween_property(_hint, "modulate:a", 0.85, 0.6)

## TV-Filter einstellen: Staerke 0 = aus.
func set_tv(strength: float, glitch: float = 0.0, tint: Color = Color.WHITE) -> void:
	tv.visible = strength > 0.001 or glitch > 0.001
	tv_mat.set_shader_parameter("strength", strength)
	tv_mat.set_shader_parameter("glitch", glitch)
	tv_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))

func tween_glitch(peak: float, dur: float) -> void:
	tv.visible = true
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: tv_mat.set_shader_parameter("glitch", v), peak, 0.0, dur)

func fade_black(to: float, dur: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(black, "color:a", to, dur)
	return tw
