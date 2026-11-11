extends CanvasLayer
## Ausruestungswahl nach dem Briefing (Welle 4, systeme-b). Nur fuer Level mit freier Ausruestung (Loadout.FIXED).
## main.gd: var s = Screen.new(); add_child(s); var choice: Dictionary = await s.run(level, LEVELS, unlocked, TITLES)
## Vorauswahl = gespeicherte Wahl bzw. Default; Enter/Leertaste/Esc bestaetigt -> unveraendert spielen.
## Speichert die Wahl in Settings "loadout/<level>".

const Loadout = preload("res://game/loadout/loadout.gd")
const SFX_MOVE := "res://assets/sfx/intro_tick.wav"
const SFX_OK := "res://assets/sfx/intro_beep.wav"

signal confirmed(choice: Dictionary)

var _root: Control
var _frame: Control
var _audio: AudioStreamPlayer
var _rows: Array = []          # [{key, title_label, opts, chips, sel, locked}]
var _row: int = 0
var _desc: Label
var _scope: Label
var _note: Label
var _done: bool = false
var _t: float = 0.0
var _levels: Array = []
var _unlocked: Array = []
var _titles: Dictionary = {}


func _ready() -> void:
	layer = 91
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	add_child(_audio)


func _process(delta: float) -> void:
	_t += delta


func _sfx(path: String, db: float) -> void:
	if ResourceLoader.exists(path):
		_audio.stream = load(path)
		_audio.volume_db = db
		_audio.play()


## Gibt die bestaetigte Wahl zurueck. auto_confirm > 0: bestaetigt nach so vielen Sekunden (Smoke-Tests).
func run(level: String, levels: Array, unlocked: Array, titles: Dictionary, auto_confirm: float = -1.0) -> Dictionary:
	_levels = levels
	_unlocked = unlocked
	_titles = titles
	var prev_mouse := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var start := Loadout.effective_choice(level, levels, unlocked)
	_build(level, start)
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.35)
	if auto_confirm > 0.0:
		get_tree().create_timer(auto_confirm, true, false, true).timeout.connect(_confirm)
	var choice: Dictionary = await confirmed
	Loadout.save_choice(level, choice)
	var out := create_tween()
	out.tween_property(_root, "modulate:a", 0.0, 0.3)
	await out.finished
	Input.mouse_mode = prev_mouse
	queue_free()
	return choice


func current_choice() -> Dictionary:
	var c := Loadout.DEFAULT.duplicate()
	for r in _rows:
		if not r["locked"]:
			c[r["key"]] = r["opts"][r["sel"]]
	return c


func _confirm() -> void:
	if _done:
		return
	_done = true
	_sfx(SFX_OK, -16.0)
	confirmed.emit(current_choice())


func _key(event: InputEvent, codes: Array) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.keycode in codes


func _input(event: InputEvent) -> void:
	if _done or _t < 0.4:
		return
	var handled := true
	if event.is_action_pressed("ui_left") or _key(event, [KEY_A]):
		_step(-1)
	elif event.is_action_pressed("ui_right") or _key(event, [KEY_D]):
		_step(1)
	elif event.is_action_pressed("ui_up") or _key(event, [KEY_W]):
		_move_row(-1)
	elif event.is_action_pressed("ui_down") or _key(event, [KEY_S]):
		_move_row(1)
	elif _key(event, [KEY_R]):
		_reset_default()
	elif event.is_action_pressed("ui_accept") or _key(event, [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]):
		_confirm()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _move_row(d: int) -> void:
	var n := _rows.size()
	for i in n:
		_row = (_row + d + n) % n
		if not _rows[_row]["locked"]:
			break
	_sfx(SFX_MOVE, -24.0)
	_refresh()


func _step(d: int) -> void:
	var r: Dictionary = _rows[_row]
	if r["locked"]:
		return
	var opts: Array = r["opts"]
	var s: int = r["sel"]
	for i in opts.size():
		s = (s + d + opts.size()) % opts.size()
		if Loadout.is_unlocked(opts[s], _levels, _unlocked):
			break
	if s != int(r["sel"]):
		r["sel"] = s
		_sfx(SFX_MOVE, -24.0)
	_refresh()


func _select(ri: int, oi: int) -> void:
	if _done or _t < 0.4:
		return
	var r: Dictionary = _rows[ri]
	if r["locked"] or not Loadout.is_unlocked(r["opts"][oi], _levels, _unlocked):
		return
	_row = ri
	r["sel"] = oi
	_sfx(SFX_MOVE, -24.0)
	_refresh()


func _reset_default() -> void:
	for r in _rows:
		if not r["locked"]:
			r["sel"] = maxi(0, (r["opts"] as Array).find(Loadout.DEFAULT[r["key"]]))
	_sfx(SFX_MOVE, -24.0)
	_refresh()


func _opt_name(key: String, id: String) -> String:
	if key == "primary":
		return WeaponDefs.display_name(id)
	return str(Loadout.GRENADE_NAMES.get(id, id))


func _opt_desc(key: String, id: String) -> String:
	if key == "primary":
		return str(Loadout.PRIMARY_DESC.get(id, ""))
	return str(Loadout.GRENADE_DESC.get(id, ""))


func _refresh() -> void:
	for ri in _rows.size():
		var r: Dictionary = _rows[ri]
		if r["locked"]:
			continue
		var chips: Array = r["chips"]
		for oi in chips.size():
			var chip: PanelContainer = chips[oi]
			var id: String = r["opts"][oi]
			var free := Loadout.is_unlocked(id, _levels, _unlocked)
			var sel: bool = oi == int(r["sel"])
			var focus := sel and ri == _row
			var border := UIStyle.C_AMBER if focus else (UIStyle.C_LINE_HI if sel else UIStyle.C_LINE)
			var bg := UIStyle.C_AMBER_DIM if focus else (UIStyle.C_PANEL_HI if sel else UIStyle.C_PANEL)
			chip.add_theme_stylebox_override("panel", UIStyle.box(bg, border, 2 if sel else 1, 14.0))
			var l: Label = chip.get_child(0)
			l.add_theme_color_override("font_color", UIStyle.C_TEXT if sel else (UIStyle.C_DIM if free else UIStyle.C_MUTED))
			l.text = _opt_name(r["key"], id).to_upper() + ("" if free else "   ·  GESPERRT")
		(r["title_label"] as Label).add_theme_color_override("font_color", UIStyle.C_AMBER if ri == _row else UIStyle.C_DIM)
	var cur: Dictionary = _rows[_row]
	var cur_id: String = cur["opts"][cur["sel"]]
	_desc.text = _opt_desc(cur["key"], cur_id)
	for oi in (cur["opts"] as Array).size():
		var oid: String = cur["opts"][oi]
		if not Loadout.is_unlocked(oid, _levels, _unlocked):
			_desc.text += "\n" + _opt_name(cur["key"], oid) + ": " + Loadout.unlock_text(oid, _titles)
	var prim: String = current_choice()["primary"]
	_scope.text = "ZIELFERNROHR  ·  FEST MONTIERT" if prim == "g28" else "ROTPUNKTVISIER  ·  FEST MONTIERT"


func _build(level: String, start: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIStyle.theme()
	add_child(_root)
	_frame = Control.new()
	_root.add_child(_frame)
	get_viewport().size_changed.connect(_layout)
	_layout()
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(k, 300)
	m.add_theme_constant_override("margin_top", 150)
	m.add_theme_constant_override("margin_bottom", 110)
	_frame.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	var t: Array = _titles.get(level, [level, "", ""])
	v.add_child(UIStyle.label("AUSRÜSTUNG  ·  " + str(t[0]).to_upper(), 16, UIStyle.C_AMBER, 700, true))
	v.add_child(UIStyle.label("Waffenkammer", 56, UIStyle.C_TEXT, 700))
	v.add_child(UIStyle.label("Die Wahl wird für diesen Einsatz gespeichert. Ohne Änderung: Standardausrüstung.", 21, UIStyle.C_DIM))
	_gap(v, 18)
	v.add_child(UIStyle.hline(UIStyle.C_LINE_HI))
	_gap(v, 12)
	_add_row(v, "primary", "PRIMÄRWAFFE", Loadout.PRIMARIES, str(start["primary"]))
	# Visier: Optik ist pro Waffe fest verbaut -> nur gesperrte Anzeige
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 20)
	var st := UIStyle.label("VISIER", 18, UIStyle.C_MUTED, 700, true)
	st.custom_minimum_size = Vector2(250, 60)
	st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	srow.add_child(st)
	_scope = UIStyle.label("", 22, UIStyle.C_MUTED, 600, true)
	_scope.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scope.custom_minimum_size = Vector2(0, 60)
	srow.add_child(_scope)
	v.add_child(srow)
	_rows.append({"key": "scope", "locked": true})
	_add_row(v, "grenade", "GRANATEN  4×", Loadout.GRENADES, str(start["grenade"]))
	_gap(v, 14)
	v.add_child(UIStyle.hline())
	_desc = UIStyle.label("", 22, UIStyle.C_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(0, 110)
	v.add_child(_desc)
	_note = UIStyle.label(str(Loadout.NOTES.get(level, "")), 20, UIStyle.C_AMBER)
	v.add_child(_note)
	var ok := Button.new()
	ok.text = "EINSATZ BEGINNEN"
	ok.custom_minimum_size = Vector2(420, 62)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ok.add_theme_font_override("font", UIStyle.font(700))
	ok.add_theme_font_size_override("font_size", 26)
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(func() -> void:
		if _t >= 0.4:
			_confirm())
	v.add_child(ok)
	v.add_child(UIStyle.label("←→  WECHSELN     ↑↓  ZEILE     R  STANDARD     ENTER  EINSATZ BEGINNEN", 15, UIStyle.C_MUTED, 600, true))
	_row = 0
	_refresh()


func _gap(v: Control, h: int) -> void:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	v.add_child(g)


func _add_row(v: VBoxContainer, key: String, title: String, opts: Array[String], sel_id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var tl := UIStyle.label(title, 18, UIStyle.C_DIM, 700, true)
	tl.custom_minimum_size = Vector2(250, 60)
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tl)
	var chips: Array = []
	var ri := _rows.size()
	for oi in opts.size():
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(0, 60)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var l := UIStyle.label("", 22, UIStyle.C_TEXT, 700, true)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(l)
		var idx := oi
		chip.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_select(ri, idx))
		row.add_child(chip)
		chips.append(chip)
	v.add_child(row)
	_rows.append({"key": key, "title_label": tl, "opts": opts, "chips": chips,
			"sel": maxi(0, opts.find(sel_id)), "locked": false})


func _layout() -> void:
	if _frame != null:
		UIStyle.fit(_frame, get_viewport().get_visible_rect().size)
