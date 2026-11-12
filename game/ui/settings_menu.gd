extends Control
## Einstellungsmenue (Reiter): Steuerung · Tasten · Spiel · Audio · Grafik.
## Alle Werte wirken sofort und werden ueber das Autoload Settings gespeichert (CONTRACTS.md "Runde 6").
## Bedienung: Maus oder Tastatur – Pfeile hoch/runter waehlen, links/rechts aendern, Q/E bzw. Bild hoch/runter
## wechseln den Reiter, Entf setzt eine Taste frei, ESC zurueck (bricht eine Tastenzuweisung ab).
## Wird vom Pausenmenue eingebettet; signal back_requested, wenn der Nutzer zurueck will.

signal back_requested
signal ui_sound(kind: String)

const TABS := ["STEUERUNG", "TASTEN", "SPIEL", "AUDIO", "GRAFIK"]
const LABEL_W := 560.0

var _tab: int = 0
var _tab_buttons: Array[Button] = []
var _tab_bar: HBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _desc: Label
var _note: Label
var _reset_btn: Button
var _back_btn: Button
var _rows: Array = []                  # OptRow / BindRow
var _capture: Dictionary = {}          # {"action","slot","button","t"}
var _confirm_reset: bool = false
var _note_t: float = 0.0


func _ready() -> void:
	theme = UIStyle.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	var st := _settings()
	if st != null:
		st.connect("changed", _on_setting_changed)
	show_tab(0)


func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _graphics() -> Node:
	return get_node_or_null("/root/Graphics")


# ================================================================== Aufbau

func _build() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 0)
	add_child(v)
	# Reiterleiste
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	v.add_child(bar)
	_tab_bar = bar
	var q := UIStyle.label("Q", 17, UIStyle.C_DIM, 700, true)
	q.custom_minimum_size = Vector2(34, 34)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_stylebox_override("normal", UIStyle.box(Color(0, 0, 0, 0.25), UIStyle.C_LINE_HI, 1, 0))
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(q)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UIStyle.font(700))
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(170, 52)
		b.pressed.connect(func() -> void:
			ui_sound.emit("tab")
			show_tab(i))
		bar.add_child(b)
		_tab_buttons.append(b)
	var e := UIStyle.label("E", 17, UIStyle.C_DIM, 700, true)
	e.custom_minimum_size = Vector2(34, 34)
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_stylebox_override("normal", UIStyle.box(Color(0, 0, 0, 0.25), UIStyle.C_LINE_HI, 1, 0))
	e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(e)
	v.add_child(UIStyle.hline(UIStyle.C_LINE_HI))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap)
	# Liste
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)
	# Fusszeile: Beschreibung + Knoepfe
	v.add_child(UIStyle.hline(UIStyle.C_LINE_HI))
	var foot := HBoxContainer.new()
	foot.custom_minimum_size = Vector2(0, 92)
	foot.add_theme_constant_override("separation", 18)
	v.add_child(foot)
	var dbox := VBoxContainer.new()
	dbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dbox.add_theme_constant_override("separation", 4)
	foot.add_child(dbox)
	_desc = UIStyle.label("", 20, UIStyle.C_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(900, 0)
	dbox.add_child(_desc)
	_note = UIStyle.label("", 18, UIStyle.C_AMBER, 600)
	dbox.add_child(_note)
	_reset_btn = _foot_button("ZURÜCKSETZEN")
	_reset_btn.pressed.connect(_on_reset_pressed)
	foot.add_child(_reset_btn)
	_back_btn = _foot_button("ZURÜCK")
	_back_btn.pressed.connect(func() -> void: back_requested.emit())
	foot.add_child(_back_btn)


func _foot_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", UIStyle.font(700))
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(0, 50)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.focus_entered.connect(func() -> void:
		ui_sound.emit("move")
		if b == _reset_btn:
			set_desc("Setzt alle Werte dieses Reiters auf den Standard zurück." if not _confirm_reset
					else "Noch einmal bestätigen, um zurückzusetzen.")
		else:
			set_desc("Zurück zum Menü. Alle Änderungen sind bereits gespeichert."))
	return b


func set_desc(t: String) -> void:
	_desc.text = t


func note(t: String, sec: float = 3.5) -> void:
	_note.text = t
	_note_t = sec


func _process(delta: float) -> void:
	if _note_t > 0.0:
		_note_t -= delta
		if _note_t <= 0.0:
			_note.text = ""
	if not _capture.is_empty():
		var b: Button = _capture["button"]
		if is_instance_valid(b):
			b.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 260.0))


# ================================================================== Reiter

func show_tab(i: int) -> void:
	_cancel_capture()
	_confirm_reset = false
	_reset_btn.text = "ZURÜCKSETZEN"
	_tab = wrapi(i, 0, TABS.size())
	for k in _tab_buttons.size():
		var b := _tab_buttons[k]
		var on := k == _tab
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.72, 0.28, 0.1) if on else Color(0, 0, 0, 0)
		sb.border_color = UIStyle.C_AMBER
		sb.border_width_bottom = 3 if on else 0
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		var sh := sb.duplicate() as StyleBoxFlat
		sh.bg_color = Color(1.0, 0.72, 0.28, 0.14)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.add_theme_color_override("font_color", UIStyle.C_AMBER if on else UIStyle.C_DIM)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	match _tab:
		0: _build_controls()
		1: _build_keys()
		2: _build_game()
		3: _build_audio()
		4: _build_graphics()
	_scroll.scroll_vertical = 0
	_wire_focus()
	focus_first()


func focus_first() -> void:
	for r in _rows:
		var f: Control = r.first_focus()
		if f != null:
			f.grab_focus()
			return
	_back_btn.grab_focus()


func _wire_focus() -> void:
	# Letzte Zeile -> Fusszeile, Fusszeile hoch -> letzte Zeile (sonst springt der Fokus zufaellig)
	var last: Control = null
	for r in _rows:
		var f: Control = r.first_focus()
		if f != null:
			last = f
	if last != null:
		_reset_btn.focus_neighbor_top = _reset_btn.get_path_to(last)
		_back_btn.focus_neighbor_top = _back_btn.get_path_to(last)
	_reset_btn.focus_neighbor_right = _reset_btn.get_path_to(_back_btn)
	_back_btn.focus_neighbor_left = _back_btn.get_path_to(_reset_btn)


func _section(title: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if _list.get_child_count() > 0:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 18)
		box.add_child(sp)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var tick := ColorRect.new()
	tick.color = UIStyle.C_AMBER
	tick.custom_minimum_size = Vector2(6, 6)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tick)
	h.add_child(UIStyle.label(title.to_upper(), 16, UIStyle.C_AMBER, 700, true))
	box.add_child(h)
	box.add_child(UIStyle.hline())
	_list.add_child(box)


func _add_row(def: Dictionary) -> OptRow:
	var r := OptRow.new(def, self)
	_list.add_child(r)
	_rows.append(r)
	return r


func _placeholder(text: String) -> void:
	var l := UIStyle.label(text, 22, UIStyle.C_MUTED)
	l.custom_minimum_size = Vector2(0, 120)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(l)


# ------------------------------------------------------------------ Steuerung

func _build_controls() -> void:
	_section("Maus")
	_add_row({"key": "controls/sensitivity", "label": "Mausempfindlichkeit", "type": "float",
		"min": 0.1, "max": 4.0, "step": 0.05, "default": 1.0, "fmt": "x",
		"tooltip": "Grundempfindlichkeit beim Umsehen. Gilt auch für das Gunship-Visier."})
	_add_row({"key": "controls/ads_sensitivity", "label": "Empfindlichkeit beim Zielen", "type": "float",
		"min": 0.2, "max": 2.0, "step": 0.05, "default": 1.0, "fmt": "x",
		"tooltip": "Faktor auf die Empfindlichkeit über Kimme/Rotpunkt (rechte Maustaste)."})
	_add_row({"key": "controls/scope_sensitivity", "label": "Empfindlichkeit im Zielfernrohr", "type": "float",
		"min": 0.2, "max": 2.0, "step": 0.05, "default": 1.0, "fmt": "x",
		"tooltip": "Faktor im Zielfernrohr des Scharfschützengewehrs. Die Zoomstufe wird bereits ausgeglichen."})
	_add_row({"key": "controls/invert_y", "label": "Y-Achse invertieren", "type": "bool", "default": false,
		"tooltip": "Maus nach vorn schieben = nach unten sehen. Gilt auch für Zielfernrohr und Gunship."})
	_section("Verhalten")
	_add_row({"key": "controls/crouch_hold", "label": "Ducken", "type": "enum", "values": [false, true],
		"labels": ["Umschalten", "Halten"], "default": false,
		"tooltip": "Umschalten: Taste einmal drücken. Halten: geduckt, solange die Taste gedrückt ist. Sprinten + Ducken rutscht in beiden Fällen."})
	_add_row({"key": "controls/aim_toggle", "label": "Zielen", "type": "enum", "values": [false, true],
		"labels": ["Halten", "Umschalten"], "default": false,
		"tooltip": "Halten: zielen, solange die Taste gedrückt ist. Umschalten: einmal drücken zum Anlegen, noch einmal zum Absetzen."})


# ------------------------------------------------------------------ Tasten

func _build_keys() -> void:
	InputConfig.ensure_actions()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var spacer := UIStyle.label("", 15)
	spacer.custom_minimum_size = Vector2(LABEL_W, 0)
	head.add_child(spacer)
	for t in ["PRIMÄR", "SEKUNDÄR"]:
		var l := UIStyle.label(t, 15, UIStyle.C_MUTED, 700, true)
		l.custom_minimum_size = Vector2(300, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(l)
	_list.add_child(head)
	var group := ""
	for a in InputConfig.ACTIONS:
		if a[2] != group:
			group = a[2]
			_section(group)
		var r := BindRow.new(a[0], a[1], self)
		_list.add_child(r)
		_rows.append(r)
	_section("Fest")
	var fixed := HBoxContainer.new()
	fixed.add_theme_constant_override("separation", 12)
	var fl := UIStyle.label("Pausenmenü", 22, UIStyle.C_DIM)
	fl.custom_minimum_size = Vector2(LABEL_W, 46)
	fl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fixed.add_child(fl)
	var fk := UIStyle.label("Esc", 21, UIStyle.C_DIM, 600)
	fk.custom_minimum_size = Vector2(300, 46)
	fk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fixed.add_child(fk)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(28, 0)
	fixed.add_child(pad)
	_list.add_child(fixed)
	refresh_binds()


func refresh_binds() -> void:
	var conf := InputConfig.all_conflicts()
	for r in _rows:
		if r is BindRow:
			(r as BindRow).refresh(conf)


func start_capture(action: String, slot: int, b: Button) -> void:
	_cancel_capture()
	_capture = {"action": action, "slot": slot, "button": b, "t": Time.get_ticks_msec()}
	b.text = "Taste drücken …"
	b.add_theme_color_override("font_color", UIStyle.C_AMBER)
	b.add_theme_color_override("font_focus_color", UIStyle.C_AMBER)
	set_desc("Taste oder Maustaste für »%s« drücken.  Esc bricht ab." % InputConfig.action_label(action))
	ui_sound.emit("accept")


func is_capturing() -> bool:
	return not _capture.is_empty()


func _cancel_capture() -> void:
	if _capture.is_empty():
		return
	var b: Button = _capture["button"]
	_capture = {}
	if is_instance_valid(b):
		b.modulate.a = 1.0
	refresh_binds()


func _finish_capture(ev: InputEvent) -> void:
	var action: String = _capture["action"]
	var slot: int = _capture["slot"]
	var b: Button = _capture["button"]
	_capture = {}
	if is_instance_valid(b):
		b.modulate.a = 1.0
	var swap := InputConfig.assign(action, slot, ev)
	var name := InputConfig.event_label(ev)
	if not swap.is_empty() and swap[0] != action:
		note("»%s« war »%s« zugewiesen – Belegungen getauscht." % [name, InputConfig.action_label(swap[0])], 5.0)
	elif not swap.is_empty():
		note("Primär- und Sekundärbelegung getauscht.")
	else:
		note("»%s« → %s" % [InputConfig.action_label(action), name], 2.5)
	refresh_binds()
	ui_sound.emit("accept")
	if is_instance_valid(b):
		b.grab_focus()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not _capture.is_empty():
		# Zuweisung: alles abfangen (ausser Mausbewegung)
		if event is InputEventMouseMotion:
			return
		get_viewport().set_input_as_handled()
		if Time.get_ticks_msec() - int(_capture["t"]) < 120:
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var k := event as InputEventKey
			if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
				_cancel_capture()
				note("Zuweisung abgebrochen.", 2.0)
				ui_sound.emit("back")
				return
			_finish_capture(k)
		elif event is InputEventMouseButton and event.pressed:
			_finish_capture(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k2 := event as InputEventKey
		match k2.physical_keycode:
			KEY_Q, KEY_PAGEUP:
				ui_sound.emit("tab")
				show_tab(_tab - 1)
				get_viewport().set_input_as_handled()
			KEY_E, KEY_PAGEDOWN:
				ui_sound.emit("tab")
				show_tab(_tab + 1)
				get_viewport().set_input_as_handled()


## ESC aus dem Pausenmenue: true, wenn intern verbraucht (Zuweisung abbrechen).
func handle_back() -> bool:
	if not _capture.is_empty():
		_cancel_capture()
		return true
	return false


# ------------------------------------------------------------------ Spiel

func _build_game() -> void:
	# Welle 4: Schwierigkeitsgrad (game/progress/difficulty.gd liest "game/difficulty", wirkt sofort)
	_section("Kampagne")
	_add_row({"key": "game/difficulty", "label": "Schwierigkeitsgrad", "type": "enum", "values": ["recruit", "soldier", "veteran"],
		"labels": ["Rekrut", "Soldat", "Veteran"], "default": "soldier",
		"tooltip": "Rekrut: Gegner zielen und reagieren langsamer, weniger Schaden, schnellere Heilung. Soldat: ausgewogen (Standard). Veteran: Gegner treffen härter, zielen besser und reagieren schneller, Heilung setzt später ein."})
	_section("Ansicht")
	_add_row({"key": "game/fov", "label": "Sichtfeld (FOV)", "type": "int", "min": 70, "max": 110, "step": 1,
		"default": 76, "fmt": "deg", "tooltip": "Horizontaler Blickwinkel der Ego-Kamera (Standard 76°). Zielen und Zielfernrohr zoomen wie gewohnt."})
	_add_row({"key": "game/head_bob", "label": "Kopfbewegung", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
		"default": 1.0, "fmt": "pct", "tooltip": "Stärke des Kopfwippens und Neigens beim Gehen und Sprinten."})
	_add_row({"key": "game/screen_shake", "label": "Kamerawackeln", "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
		"default": 1.0, "fmt": "pct", "tooltip": "Erschütterung durch Explosionen, Treffer und Rückstoß-Wackeln der Kamera."})
	_section("Anzeige")
	_add_row({"key": "game/crosshair", "label": "Fadenkreuz", "type": "enum", "values": [0, 1, 2, 3, 4],
		"labels": ["Standard", "Punkt", "Kreuz ohne Punkt", "Kreis", "Aus"], "default": 0,
		"tooltip": "Form des Fadenkreuzes beim Schießen aus der Hüfte."})
	_add_row({"key": "game/crosshair_color", "label": "Fadenkreuz-Farbe", "type": "enum", "values": [0, 1, 2, 3, 4, 5],
		"labels": ["Weiß", "Grün", "Gelb", "Cyan", "Rot", "Magenta"], "default": 0, "swatch": true,
		"tooltip": "Farbe des Fadenkreuzes. Kräftige Farben sind vor hellen Wänden besser zu sehen."})
	_add_row({"key": "game/hitmarkers", "label": "Trefferanzeige", "type": "bool", "default": true,
		"tooltip": "Markierung am Fadenkreuz bei Treffern, Kopftreffern und Abschüssen."})
	_add_row({"key": "game/sniper_assist", "label": "Zielhilfe Scharfschütze", "type": "enum", "values": [0, 1],
		"labels": ["Realistisch", "Unterstützt"], "default": 0,
		"tooltip": "Unterstützt: Das Zielfernrohr zeigt einen Haltepunkt, der Geschossfall und Wind für die gemessene Entfernung schon einrechnet. Realistisch: Du schätzt den Vorhalt selbst über Strichplatte, Windanzeige und Windsäcke."})
	_add_row({"key": "game/subtitles", "label": "Untertitel", "type": "bool", "default": true,
		"tooltip": "Funksprüche und Dialoge als Text einblenden. Die Sprachausgabe läuft unabhängig davon."})
	_add_row({"key": "game/subtitle_size", "label": "Untertitel-Größe", "type": "enum", "values": [0.85, 1.0, 1.25, 1.5],
		"labels": ["Klein", "Normal", "Groß", "Sehr groß"], "default": 1.0, "tooltip": "Schriftgröße der Funk-Untertitel."})
	_add_row({"key": "game/skip_cutscenes", "label": "Zwischensequenzen überspringen", "type": "bool", "default": false,
		"tooltip": "Kamerafahrten automatisch überspringen. Einzelne Sequenzen lassen sich auch mit gehaltener Leertaste/Esc abbrechen."})
	_section("System")
	_add_row({"key": "game/pause_on_focus", "label": "Pause bei Fensterwechsel", "type": "bool", "default": true,
		"tooltip": "Öffnet automatisch das Pausenmenü, wenn das Spielfenster den Fokus verliert (Alt+Tab)."})


# ------------------------------------------------------------------ Audio

func _build_audio() -> void:
	_section("Lautstärke")
	var defs := [
		["audio/master", "Master", "Gesamtlautstärke", "Regelt alles gemeinsam."],
		["audio/music", "Music", "Musik", "Musik und Stimmungsflächen."],
		["audio/sfx", "SFX", "Effekte", "Waffen, Explosionen, Schritte, Fahrzeuge."],
		["audio/voice", "Voice", "Sprache / Funk", "Funksprüche, Dialoge und Lageberichte."],
		["audio/ambient", "Ambient", "Umgebung", "Wind, Regen, Stadt- und Kampflärm im Hintergrund."],
	]
	for d in defs:
		if AudioServer.get_bus_index(d[1]) < 0:
			continue
		_add_row({"key": d[0], "label": d[2], "type": "float", "min": 0.0, "max": 1.0, "step": 0.05,
			"default": 1.0, "fmt": "pct", "tooltip": str(d[3]) + "  (Lautstärkekurve in dB, 50 % ≈ −12 dB)"})


# ------------------------------------------------------------------ Grafik

func _build_graphics() -> void:
	var g := _graphics()
	var opts: Array = []
	if g != null and g.has_method("get_options"):
		var raw = g.call("get_options")
		if raw is Array:
			opts = raw
	if opts.is_empty():
		_placeholder("—")
		return
	# Preset-Auswahl oben – nur wenn Graphics sie nicht schon selbst als Option liefert
	var own_preset := false
	for o in opts:
		if o is Dictionary and str(o.get("key", "")).ends_with("preset"):
			own_preset = true
	if g.has_method("apply_preset") and not own_preset:
		_section("Voreinstellung")
		var cur := ""
		if g.has_method("get_preset"):
			cur = str(g.call("get_preset"))
		var pr := _add_row({"key": "", "label": "Qualitätsstufe", "type": "enum",
			"values": ["", "niedrig", "mittel", "hoch", "ultra"],
			"labels": ["Benutzerdefiniert", "Niedrig", "Mittel", "Hoch", "Ultra"], "default": "",
			"tooltip": "Setzt alle Grafikwerte auf eine Stufe. Einzelwerte lassen sich danach weiter anpassen."})
		pr.preset_value = cur
		pr.on_choose = func(v) -> void:
			if str(v) != "":
				g.call("apply_preset", str(v))
				note("Voreinstellung »%s« angewendet." % str(v).capitalize(), 2.5)
				for r in _rows:
					if r is OptRow:
						(r as OptRow).refresh()
		pr.refresh()
	var section := ""
	for o in opts:
		if not (o is Dictionary) or not o.has("key"):
			continue
		var s := str(o.get("section", "Grafik"))
		if s != section:
			section = s
			_section(s)
		var def: Dictionary = (o as Dictionary).duplicate()
		if bool(def.get("requires_restart", false)):
			def["tooltip"] = str(def.get("tooltip", "")) + "  (Wirkt nach Neustart.)"
		_add_row(def)


func _on_reset_pressed() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_reset_btn.text = "WIRKLICH?"
		set_desc("Noch einmal bestätigen, um alle Werte des Reiters »%s« zurückzusetzen." % TABS[_tab].capitalize())
		return
	_confirm_reset = false
	_reset_btn.text = "ZURÜCKSETZEN"
	var st := _settings()
	match _tab:
		0:
			if st: st.call("reset_section", "controls")
		1:
			InputConfig.reset_all()
		2:
			if st:
				var unlocked = st.call("get_value", "game/unlocked", []) if bool(st.call("has", "game/unlocked")) else null
				st.call("reset_section", "game")
				if unlocked != null:
					st.call("set_value", "game/unlocked", unlocked)
		3:
			if st: st.call("reset_section", "audio")
		4:
			if st: st.call("reset_section", "graphics")
			var g := _graphics()
			if g != null and g.has_method("apply_all"):
				g.call("apply_all")
	note("Reiter »%s« auf Standard zurückgesetzt." % TABS[_tab].capitalize())
	ui_sound.emit("accept")
	var keep := _tab
	show_tab(keep)


func _on_setting_changed(key: String, _value) -> void:
	if not is_visible_in_tree():
		return
	for r in _rows:
		if r is OptRow and (r as OptRow).key == key:
			(r as OptRow).refresh()


# ================================================================== Zeilen

## Einstellungszeile: Name links, Regler/Auswahl rechts. Die Zeile selbst hat den Fokus;
## links/rechts aendert den Wert, Enter/Klick schaltet Auswahlen weiter.
class OptRow extends PanelContainer:
	var def: Dictionary
	var key: String
	var menu: Control
	var kind: String
	var slider: HSlider
	var value_label: Label
	var name_label: Label
	var swatch: ColorRect
	var on_choose: Callable
	var preset_value = null
	var _sb_n: StyleBoxFlat
	var _sb_f: StyleBoxFlat
	var _updating: bool = false

	const SWATCH := [Color(1, 1, 1), Color(0.3, 1.0, 0.35), Color(1.0, 0.92, 0.2), Color(0.25, 0.95, 1.0),
		Color(1.0, 0.25, 0.2), Color(1.0, 0.3, 0.95)]

	func _init(d: Dictionary, m: Control) -> void:
		def = d
		key = str(d.get("key", ""))
		menu = m
		var t := str(d.get("type", "float"))
		kind = "slider" if t in ["float", "int"] else "choice"
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 54)
		_sb_n = StyleBoxFlat.new()
		_sb_n.bg_color = Color(0, 0, 0, 0)
		_sb_n.content_margin_left = 22
		_sb_n.content_margin_right = 22
		_sb_n.border_color = Color(0, 0, 0, 0)
		_sb_n.border_width_left = 3
		_sb_f = _sb_n.duplicate() as StyleBoxFlat
		_sb_f.bg_color = Color(1.0, 0.72, 0.28, 0.1)
		_sb_f.border_color = UIStyle.C_AMBER
		add_theme_stylebox_override("panel", _sb_n)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		name_label = UIStyle.label(str(d.get("label", key)), 22, UIStyle.C_TEXT)
		name_label.custom_minimum_size = Vector2(540, 0)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(name_label)
		if kind == "slider":
			slider = HSlider.new()
			slider.min_value = float(d.get("min", 0.0))
			slider.max_value = float(d.get("max", 1.0))
			slider.step = float(d.get("step", 0.01 if t == "float" else 1.0))
			slider.custom_minimum_size = Vector2(420, 26)
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.focus_mode = Control.FOCUS_NONE
			slider.value_changed.connect(_on_slider)
			h.add_child(slider)
			value_label = UIStyle.label("", 21, UIStyle.C_AMBER, 600)
			value_label.custom_minimum_size = Vector2(110, 0)
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			h.add_child(value_label)
		else:
			var lb := _arrow("◀", -1)
			h.add_child(lb)
			var mid := HBoxContainer.new()
			mid.custom_minimum_size = Vector2(380, 0)
			mid.alignment = BoxContainer.ALIGNMENT_CENTER
			mid.add_theme_constant_override("separation", 10)
			mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(mid)
			if bool(d.get("swatch", false)):
				swatch = ColorRect.new()
				swatch.custom_minimum_size = Vector2(16, 16)
				swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
				mid.add_child(swatch)
			value_label = UIStyle.label("", 21, UIStyle.C_AMBER, 600)
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			mid.add_child(value_label)
			h.add_child(_arrow("▶", 1))
		focus_entered.connect(_on_focus.bind(true))
		focus_exited.connect(_on_focus.bind(false))
		mouse_entered.connect(func() -> void:
			if not has_focus():
				grab_focus())

	func _ready() -> void:
		refresh()

	func first_focus() -> Control:
		return self

	func _arrow(txt: String, dir: int) -> Button:
		var b := Button.new()
		b.text = txt
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", UIStyle.C_DIM)
		b.custom_minimum_size = Vector2(40, 40)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void:
			grab_focus()
			step(dir))
		return b

	func _on_focus(on: bool) -> void:
		add_theme_stylebox_override("panel", _sb_f if on else _sb_n)
		name_label.add_theme_color_override("font_color", UIStyle.C_AMBER if on else UIStyle.C_TEXT)
		if on:
			menu.call("set_desc", str(def.get("tooltip", "")))
			menu.emit_signal("ui_sound", "move")

	func _settings() -> Node:
		return get_node_or_null("/root/Settings")

	func current():
		if key == "":
			return preset_value if preset_value != null else def.get("default")
		var st := _settings()
		var v = def.get("default")
		if st != null:
			if bool(st.call("has", key)):
				v = st.call("get_value", key, v)
		return v

	func refresh() -> void:
		var v = current()
		_updating = true
		if kind == "slider":
			slider.value = float(v)
			value_label.text = _fmt(float(v))
		else:
			var i := _index_of(v)
			var labels: Array = def.get("labels", [])
			if str(def.get("type")) == "bool":
				value_label.text = "AN" if bool(v) else "AUS"
				value_label.add_theme_color_override("font_color", UIStyle.C_AMBER if bool(v) else UIStyle.C_DIM)
			else:
				value_label.text = str(labels[i]) if i >= 0 and i < labels.size() else str(v)
			if swatch != null:
				swatch.color = SWATCH[clampi(int(v), 0, SWATCH.size() - 1)]
		_updating = false

	func _index_of(v) -> int:
		var vals: Array = def.get("values", [])
		for i in vals.size():
			if typeof(vals[i]) == typeof(v) and vals[i] == v:
				return i
			if (typeof(vals[i]) in [TYPE_INT, TYPE_FLOAT]) and (typeof(v) in [TYPE_INT, TYPE_FLOAT]) \
					and is_equal_approx(float(vals[i]), float(v)):
				return i
			if str(vals[i]) == str(v):
				return i
		return -1

	func _fmt(v: float) -> String:
		match str(def.get("fmt", "")):
			"pct":
				return "%d %%" % roundi(v * 100.0)
			"x":
				return "× %.2f" % v
			"deg":
				return "%d°" % roundi(v)
		if str(def.get("type")) == "int":
			return str(roundi(v))
		var st := float(def.get("step", 0.01))
		var dec := 0 if st >= 1.0 else (1 if st >= 0.1 else 2)
		return String.num(v, dec)

	func _write(v) -> void:
		if key == "":
			preset_value = v
			refresh()
			if on_choose.is_valid():
				on_choose.call(v)
			return
		var st := _settings()
		if st != null:
			st.call("set_value", key, v)
		refresh()

	func _on_slider(v: float) -> void:
		if _updating:
			return
		_write(roundi(v) if str(def.get("type")) == "int" else v)
		value_label.text = _fmt(v)

	func step(dir: int) -> void:
		if kind == "slider":
			slider.value = clampf(slider.value + slider.step * dir, slider.min_value, slider.max_value)
			menu.emit_signal("ui_sound", "tick")
			return
		var t := str(def.get("type"))
		if t == "bool":
			_write(not bool(current()))
		else:
			var vals: Array = def.get("values", [])
			if vals.is_empty():
				return
			var i := _index_of(current())
			_write(vals[wrapi(i + dir, 0, vals.size())])
		menu.emit_signal("ui_sound", "tick")

	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left", true):
			step(-1)
			accept_event()
		elif event.is_action_pressed("ui_right", true):
			step(1)
			accept_event()
		elif event.is_action_pressed("ui_accept") and kind == "choice":
			step(1)
			accept_event()
		elif event is InputEventMouseButton and event.pressed and kind == "choice" \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			step(1)
			accept_event()


## Tastenbelegung: Name + zwei Belegungsknoepfe (Primaer/Sekundaer). Enter/Klick = neu belegen,
## Entf/Ruecktaste = Slot leeren, Rechtsklick = Slot leeren.
class BindRow extends PanelContainer:
	var action: String
	var menu: Control
	var buttons: Array[Button] = []
	var name_label: Label
	var _sb_n: StyleBoxFlat
	var _sb_f: StyleBoxFlat

	func _init(a: String, label_text: String, m: Control) -> void:
		action = a
		menu = m
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(0, 50)
		_sb_n = StyleBoxFlat.new()
		_sb_n.bg_color = Color(0, 0, 0, 0)
		_sb_n.content_margin_left = 22
		_sb_n.content_margin_right = 22
		_sb_n.border_width_left = 3
		_sb_n.border_color = Color(0, 0, 0, 0)
		_sb_f = _sb_n.duplicate() as StyleBoxFlat
		_sb_f.bg_color = Color(1.0, 0.72, 0.28, 0.06)
		_sb_f.border_color = UIStyle.C_AMBER
		add_theme_stylebox_override("panel", _sb_n)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		name_label = UIStyle.label(label_text, 22)
		name_label.custom_minimum_size = Vector2(538, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(name_label)
		for i in InputConfig.SLOTS:
			var b := Button.new()
			b.custom_minimum_size = Vector2(300, 42)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.focus_mode = Control.FOCUS_ALL
			b.clip_text = true
			b.add_theme_font_override("font", UIStyle.font(600))
			b.add_theme_font_size_override("font_size", 20)
			var n := UIStyle.box(Color(0.1, 0.115, 0.105, 0.9), UIStyle.C_LINE_HI, 1, 6)
			var f := UIStyle.box(Color(1.0, 0.72, 0.28, 0.16), UIStyle.C_AMBER, 2, 6)
			b.add_theme_stylebox_override("normal", n)
			b.add_theme_stylebox_override("hover", f)
			b.add_theme_stylebox_override("focus", f)
			b.add_theme_stylebox_override("pressed", f)
			b.add_theme_stylebox_override("hover_pressed", f)
			var slot := i
			b.gui_input.connect(func(ev: InputEvent) -> void: _btn_input(ev, slot))
			b.pressed.connect(func() -> void: menu.call("start_capture", action, slot, b))
			b.focus_entered.connect(func() -> void: _focus(true))
			b.focus_exited.connect(func() -> void: _focus(false))
			b.mouse_entered.connect(func() -> void:
				if not menu.call("is_capturing") and not b.has_focus():
					b.grab_focus())
			h.add_child(b)
			buttons.append(b)
		var dflt := Label.new()
		dflt.custom_minimum_size = Vector2(28, 0)
		dflt.name = "Mark"
		dflt.add_theme_font_override("font", UIStyle.font(700, true))
		dflt.add_theme_font_size_override("font_size", 16)
		dflt.add_theme_color_override("font_color", UIStyle.C_AMBER)
		dflt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dflt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(dflt)

	func first_focus() -> Control:
		return buttons[0]

	func _btn_input(ev: InputEvent, slot: int) -> void:
		if menu.call("is_capturing"):
			return
		var clear := false
		if ev is InputEventKey and ev.pressed and not ev.echo:
			var k := ev as InputEventKey
			clear = k.keycode in [KEY_DELETE, KEY_BACKSPACE]
		elif ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			clear = true
		if clear:
			InputConfig.set_binding(action, slot, null)
			menu.call("note", "»%s« %s geleert." % [InputConfig.action_label(action), "Primärbelegung" if slot == 0 else "Sekundärbelegung"], 2.5)
			menu.call("refresh_binds")
			menu.emit_signal("ui_sound", "back")
			buttons[slot].accept_event()

	func _focus(on: bool) -> void:
		var any := false
		for b in buttons:
			any = any or b.has_focus()
		on = on or any
		add_theme_stylebox_override("panel", _sb_f if on else _sb_n)
		name_label.add_theme_color_override("font_color", UIStyle.C_AMBER if on else UIStyle.C_TEXT)
		if on and not menu.call("is_capturing"):
			var conf := ""
			for i in buttons.size():
				var ev := InputConfig.get_binding(action, i)
				var c := InputConfig.find_conflict(ev, action, i)
				if not c.is_empty() and c[0] != action:
					conf = "  Achtung: »%s« ist auch »%s« zugewiesen." % [InputConfig.event_label(ev), InputConfig.action_label(c[0])]
			menu.call("set_desc", "Enter oder Klick: neu belegen (Taste, Maustaste oder Mausrad).  Entf oder Rechtsklick: leeren." + conf)
			menu.emit_signal("ui_sound", "move")

	func refresh(conflicts: Dictionary) -> void:
		for i in buttons.size():
			var b := buttons[i]
			var ev := InputConfig.get_binding(action, i)
			var t := InputConfig.event_label(ev)
			b.text = t if t != "" else "—"
			b.modulate.a = 1.0
			var bad := conflicts.has("%s:%d" % [action, i])
			var col := UIStyle.C_RED if bad else (UIStyle.C_TEXT if t != "" else UIStyle.C_MUTED)
			b.add_theme_color_override("font_color", col)
			b.add_theme_color_override("font_focus_color", UIStyle.C_RED if bad else UIStyle.C_AMBER)
			b.add_theme_color_override("font_hover_color", UIStyle.C_RED if bad else UIStyle.C_AMBER)
			b.tooltip_text = ""
		var mark := get_node_or_null("HBoxContainer/Mark") as Label
		if mark == null:
			for c in get_children():
				if c is HBoxContainer:
					mark = c.get_node_or_null("Mark") as Label
		if mark != null:
			mark.text = "" if InputConfig.is_default(action) else "●"
			mark.tooltip_text = "geändert"
