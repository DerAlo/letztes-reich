class_name UIStyle
extends RefCounted
## Gemeinsamer Look fuer Pause- und Einstellungsmenue: Funk-/Lagezentrum-Aesthetik
## (Bahnschrift wie Intro/Titelkarten, Bernstein-Akzent wie "AUFTRAG", dunkles Oliv-Grau, feine Linien).

const REF := Vector2(1920, 1080)

const C_BG := Color(0.035, 0.045, 0.04, 0.86)
const C_PANEL := Color(0.05, 0.062, 0.056, 0.92)
const C_PANEL_HI := Color(0.09, 0.105, 0.095, 0.95)
const C_LINE := Color(0.62, 0.66, 0.6, 0.22)
const C_LINE_HI := Color(0.62, 0.66, 0.6, 0.45)
const C_TEXT := Color(0.9, 0.91, 0.87)
const C_DIM := Color(0.58, 0.61, 0.57)
const C_MUTED := Color(0.38, 0.4, 0.37)
const C_AMBER := Color(1.0, 0.72, 0.28)
const C_AMBER_DIM := Color(1.0, 0.72, 0.28, 0.16)
const C_RED := Color(1.0, 0.36, 0.28)
const C_GREEN := Color(0.55, 0.9, 0.6)

static var _fonts: Dictionary = {}
static var _theme: Theme = null


static func font(weight: int = 500, mono: bool = false) -> Font:
	var key := "%d_%s" % [weight, mono]
	if _fonts.has(key):
		return _fonts[key]
	var f := SystemFont.new()
	if mono:
		f.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	else:
		f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Segoe UI", "Arial", "sans-serif"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_fonts[key] = f
	return f


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, margin: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = false
	return sb


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 22
	# Label
	t.set_color("font_color", "Label", C_TEXT)
	# Button (Textknopf mit Bernstein-Balken links bei Fokus/Hover)
	var bn := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0)
	bn.content_margin_left = 16
	bn.content_margin_right = 16
	bn.content_margin_top = 8
	bn.content_margin_bottom = 8
	var bh := bn.duplicate() as StyleBoxFlat
	bh.bg_color = C_AMBER_DIM
	bh.border_color = C_AMBER
	bh.border_width_left = 3
	var bp := bh.duplicate() as StyleBoxFlat
	bp.bg_color = Color(1.0, 0.72, 0.28, 0.28)
	var bd := bn.duplicate() as StyleBoxFlat
	for st in ["normal", "disabled"]:
		t.set_stylebox(st, "Button", bn if st == "normal" else bd)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("focus", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("hover_pressed", "Button", bp)
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_AMBER)
	t.set_color("font_focus_color", "Button", C_AMBER)
	t.set_color("font_pressed_color", "Button", C_AMBER)
	t.set_color("font_hover_pressed_color", "Button", C_AMBER)
	t.set_color("font_disabled_color", "Button", C_MUTED)
	# Slider
	var track := box(Color(0.6, 0.64, 0.58, 0.18))
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := box(C_AMBER)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _grabber_tex(C_TEXT))
	t.set_icon("grabber_highlight", "HSlider", _grabber_tex(C_AMBER))
	t.set_icon("grabber_disabled", "HSlider", _grabber_tex(C_MUTED))
	t.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())
	# Scrollbar
	var sbg := box(Color(1, 1, 1, 0.04))
	sbg.content_margin_left = 3
	sbg.content_margin_right = 3
	var sgr := box(Color(0.62, 0.66, 0.6, 0.35))
	sgr.content_margin_left = 3
	sgr.content_margin_right = 3
	var sgh := box(C_AMBER)
	t.set_stylebox("scroll", "VScrollBar", sbg)
	t.set_stylebox("grabber", "VScrollBar", sgr)
	t.set_stylebox("grabber_highlight", "VScrollBar", sgh)
	t.set_stylebox("grabber_pressed", "VScrollBar", sgh)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	# Tooltips
	t.set_stylebox("panel", "TooltipPanel", box(C_PANEL, C_LINE_HI, 1, 8))
	t.set_color("font_color", "TooltipLabel", C_TEXT)
	_theme = t
	return t


static func _grabber_tex(col: Color) -> Texture2D:
	var img := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	img.fill(col)
	for y in 22:
		img.set_pixel(0, y, col.darkened(0.4))
		img.set_pixel(11, y, col.darkened(0.4))
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 22, col: Color = C_TEXT, weight: int = 500, mono: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, mono))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func hline(col: Color = C_LINE, h: int = 1) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Einen Kontrollknoten auf 1920x1080 auslegen und auf die Fenstergroesse skalieren (zentriert).
static func fit(c: Control, vs: Vector2) -> void:
	var s := minf(vs.x / REF.x, vs.y / REF.y)
	c.size = REF
	c.scale = Vector2(s, s)
	c.position = (vs - REF * s) * 0.5


## HUD-Skalierung: Faktor, mit dem ein fuer 1920x1080 gebautes HUD auf die aktuelle Ansicht skaliert wird.
## Hoehe ist massgeblich (16:9, 21:9 -> HUD gleich hoch, mehr Breite); bei schmalen Fenstern (< 4:3) begrenzt die Breite.
static func hud_scale(vs: Vector2) -> float:
	return clampf(minf(vs.y / REF.y, vs.x / 1440.0), 0.2, 4.0)


## Mindestschriftgroesse: liefert eine Groesse (in HUD-Pixeln), die nach Skalierung mit factor nicht unter
## min_px echte Pixel faellt (kleine Fenster wie 960x540 -> Texte bleiben lesbar).
static func min_fs(fs: int, factor: float, min_px: float = 9.0) -> int:
	return maxi(fs, ceili(min_px / maxf(factor, 0.01)))


## Wurzel fuer HUD-Elemente einer CanvasLayer: virtuelle Flaeche mit 1080 px Hoehe (Breite folgt dem Seitenverhaeltnis),
## per scale auf die echte Ansicht gebracht. Kinder mit Ankern/Offsets in 1080p-Pixeln skalieren damit sauber in jedem
## Fenster (z. B. 960x540 bei --bg). Nicht fuer Zeichnungen mit unproject_position() benutzen (die liefern echte Pixel).
## Gebrauch: var root := UIStyle.HudRoot.new(); layer.add_child(root); root.add_child(...)
class HudRoot extends Control:
	var factor: float = 1.0
	var _min_fonts: Array = []   ## [Control, Basisgroesse, min_px]

	func _init() -> void:
		name = "HudRoot"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		get_viewport().size_changed.connect(_fit)
		_fit()

	## Schriftgroesse eines Labels/Controls (in HUD-Pixeln) so halten, dass sie nach Skalierung nicht unter
	## min_px echte Pixel faellt; wird bei jeder Fensteraenderung neu angewandt.
	func keep_min_font(c: Control, base: int, min_px: float = 9.0) -> void:
		_min_fonts.append([c, base, min_px])
		c.add_theme_font_size_override("font_size", UIStyle.min_fs(base, factor, min_px))

	func _fit() -> void:
		var vs: Vector2 = get_viewport().get_visible_rect().size
		if vs.x < 1.0 or vs.y < 1.0:
			return
		factor = UIStyle.hud_scale(vs)
		position = Vector2.ZERO
		scale = Vector2(factor, factor)
		size = vs / factor
		for e: Array in _min_fonts:
			if is_instance_valid(e[0]):
				(e[0] as Control).add_theme_font_size_override("font_size", UIStyle.min_fs(int(e[1]), factor, float(e[2])))
