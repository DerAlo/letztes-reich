class_name Credits
extends CanvasLayer
## Abspann nach dem Kampagnen-Ende (Nutzerwunsch: lustig, fast alles "Alfons Riedhammer").
## Rollt von unten nach oben ueber Schwarz. Leertaste/Enter/Klick = schneller, Esc = ueberspringen.
## Nutzung: await Credits.play(parent)   (im Autopilot/headless sofort fertig)

signal done

const NAME := "Alfons Riedhammer"
const SPEED := 46.0          # px/s
const FAST := 6.0            # Faktor bei gedrueckter Taste

## [Rolle, Name] – Name "" = Zwischenueberschrift, Rolle "" = Leerzeile/Freitext
const ROLES := [
	["LETZTES REICH", ""],
	["", ""],
	["Eine Produktion von", NAME],
	["Nach einer Idee von", NAME],
	["Drehbuch", NAME],
	["Regie", NAME],
	["", ""],
	["DARSTELLER", ""],
	["General von Riedhammer", NAME],
	["Bösewicht (ganz allgemein)", NAME],
	["Bösewicht (Nahaufnahme)", NAME],
	["Riedhammers Bart", NAME],
	["Riedhammers Glatze", NAME + " (ohne Mütze)"],
	["Spöttisches Lächeln", NAME],
	["Garde-Soldat Nr. 1 bis 412", NAME],
	["Mann, der hinter dem Geländer kauert", NAME],
	["Scharfschütze am Kühlturm (nie getroffen)", NAME],
	["Leiche im Hintergrund", NAME],
	["Andere Leiche im Hintergrund", NAME + " (anderer Hut)"],
	["", ""],
	["TON", ""],
	["Musik", NAME],
	["Sterbegeräusche", NAME],
	["Erbärmliches Röcheln", NAME + " (aufm Klo)"],
	["Heldenhaftes Röcheln", NAME + " (auch aufm Klo)"],
	["Explosionen", NAME + " (mit dem Mund)"],
	["Patronenhülsen-Klimpern (leiser gedreht)", NAME],
	["Herzschlag beim Luftanhalten", NAME + " (Treppe hoch)"],
	["Funkrauschen", NAME + " (Staubsauger)"],
	["", ""],
	["TECHNIK", ""],
	["Geschossabfall (halbiert)", NAME],
	["Geschossabfall (vorher, viel zu krass)", "ebenfalls " + NAME],
	["Physik", NAME + " und die Schwerkraft"],
	["Kameraarbeit", NAME + " (Selfie-Arm)"],
	["Beleuchtung", "die Sonne, " + NAME],
	["Bodenflimmern", "leider auch " + NAME],
	["", ""],
	["STUNTS", ""],
	["Sturz vom Funkturm", NAME],
	["Sprung vom Nachtzug", NAME],
	["Fahrt im Lastenaufzug", NAME + " (hat Angst gehabt)"],
	["Sich selbst in die Luft sprengen", NAME + " (ein Take)"],
	["", ""],
	["VERPFLEGUNG", ""],
	["Catering", NAME],
	["Abwasch", "niemand"],
	["", ""],
	["BESONDERER DANK", ""],
	["Mama von", NAME],
	["Spieletester", NAME],
	["Spieletester, der sich beschwert hat", NAME],
	["", ""],
	["MIT FREUNDLICHER UNTERSTÜTZUNG VON", ""],
	["Engine", "Godot Engine"],
	["Physik (die echte)", "Jolt Physics"],
	["Stimmen", "Chatterbox TTS"],
	["Code-Gehilfe", "Claude (tat, was " + NAME + " sagte)"],
	["", ""],
	["WAFFENMODELLE (CC BY 4.0, Sketchfab)", ""],
	["AK-74M", "creationwasteland"],
	["FPS AK-74m animations (Waffe + Arme)", "Cransh (ccransh)"],
	["HK G36", "r4m"],
	["", ""],
	["SOLDATENMODELL (Sketchfab Standard License)", ""],
	["S.W.A.T. Operator – Remastered", "Mateusz Woliński (jeandiz)"],
	["", ""],
	["", "Kein General wurde bei der Produktion dieses Spiels verletzt."],
	["", "Außer einem."],
	["", ""],
	["", "Alle Figuren sind frei erfunden. Ähnlichkeiten mit " + NAME + " sind volle Absicht."],
	["", ""],
	["", ""],
	["ENDE", ""],
]

var _scroll: VBoxContainer
var _bg: ColorRect
var _end_y: float = 0.0
var _finished: bool = false

static func play(parent: Node) -> void:
	var c: Node = (load("res://game/ui/credits.gd") as GDScript).new()
	parent.add_child(c)
	if not bool(c.get("_finished")):
		await c.done
	c.queue_free()

func _ready() -> void:
	layer = 95          # ueber der Schwarzblende von main.gd (_ui, Layer 90), unter dem Pausenmenue (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" or Game.arg("autopilot", false):
		_finished = true
		print("[credits] uebersprungen (headless/autopilot)")
		return
	print("[credits] Abspann")
	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_scroll = VBoxContainer.new()
	_scroll.add_theme_constant_override("separation", 6)
	add_child(_scroll)
	var vp := get_viewport().get_visible_rect().size
	_scroll.position = Vector2(0, vp.y + 20.0)
	_scroll.size = Vector2(vp.x, 0)
	for row in ROLES:
		_scroll.add_child(_make_row(str(row[0]), str(row[1]), vp.x))
	await get_tree().process_frame
	_end_y = -_scroll.size.y + vp.y * 0.5 - 40.0

func _make_row(role: String, who: String, w: float) -> Control:
	if role == "" and who == "":
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(w, 34)
		return sp
	if who == "":      # Ueberschrift
		var h := Label.new()
		h.text = role
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.custom_minimum_size = Vector2(w, 0)
		var big := role == "LETZTES REICH" or role == "ENDE"
		h.add_theme_font_size_override("font_size", 56 if big else 26)
		h.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25) if big else Color(0.95, 0.62, 0.2))
		return h
	if role == "":     # Freitext
		var t := Label.new()
		t.text = who
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(w, 0)
		t.add_theme_font_size_override("font_size", 22)
		t.add_theme_color_override("font_color", Color(0.8, 0.8, 0.78))
		return t
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(w, 0)
	hb.add_theme_constant_override("separation", 28)
	var l := Label.new()
	l.text = role
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = 1.0
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.62, 0.64, 0.62))
	var r := Label.new()
	r.text = who
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_stretch_ratio = 1.0
	r.add_theme_font_size_override("font_size", 24)
	r.add_theme_color_override("font_color", Color(0.94, 0.94, 0.9))
	hb.add_child(l)
	hb.add_child(r)
	return hb

func _process(delta: float) -> void:
	if _finished or _scroll == null:
		return
	var fast := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if Input.is_key_pressed(KEY_ESCAPE):
		_finish()
		return
	if _end_y == 0.0:
		return
	_scroll.position.y -= SPEED * delta * (FAST if fast else 1.0)
	if _scroll.position.y <= _end_y:
		_scroll.position.y = _end_y
		set_process(false)
		await get_tree().create_timer(3.5, true).timeout
		_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("[credits] Ende")
	done.emit()
