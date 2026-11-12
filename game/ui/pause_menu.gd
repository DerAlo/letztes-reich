extends CanvasLayer
## Pausenmenue (ESC). Wird von main.gd angelegt – nie unter --autopilot/--debug-server.
## Pausiert den Baum (dieses Menue laeuft mit PROCESS_MODE_ALWAYS), daempft Effekte/Umgebung,
## Funk/Stimmen pausieren mit (StoryUI ist PAUSABLE).
## Oeffnet nur, wenn main.can_pause() (kein Briefing, keine Titel-/Endsequenz, Level geladen).
## Eintraege: Fortsetzen · Letzter Checkpoint · Mission neu starten · Mission waehlen · Einstellungen · Spiel beenden.

const SETTINGS_MENU := preload("res://game/ui/settings_menu.gd")
const BLUR_SHADER := preload("res://game/ui/pause_blur.gdshader")
const STAR_ICON := preload("res://game/progress/star_icon.gd")   # Welle 4: Sterne in der Missionsauswahl
const Progress = preload("res://game/progress/progress.gd")      # Welle 5: Sternziel-Text der Episoden
const SFX := {
	"move": "res://assets/sfx/intro_tick.wav",
	"tick": "res://assets/sfx/intro_tick.wav",
	"tab": "res://assets/sfx/intro_radio_click.wav",
	"accept": "res://assets/sfx/intro_beep.wav",
	"back": "res://assets/sfx/intro_radio_click.wav",
	"open": "res://assets/sfx/story_radio_on.ogg",
	"close": "res://assets/sfx/story_radio_off.ogg",
}
const SFX_DB := {"move": -24.0, "tick": -22.0, "tab": -14.0, "accept": -18.0, "back": -16.0, "open": -12.0, "close": -12.0}

var is_open: bool = false
var _main: Node
var _root: Control
var _blur: ColorRect
var _blur_mat: ShaderMaterial
var _frame: Control
var _fade: ColorRect
var _tag: Label
var _title: Label
var _place: Label
var _obj_head: Label
var _obj: Label
var _body: HBoxContainer
var _menu_col: VBoxContainer
var _side: VBoxContainer
var _settings_page: Control
var _foot: Label
var _info: Label
var _buttons: Dictionary = {}       # id -> Button
var _objective: String = ""
var _page: String = "main"          # main | missions | episodes | confirm | settings
var _confirm_action: Callable
var _last_main_focus: String = "resume"
var _prev_mouse: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cache: Dictionary = {}
var _tw: Tween
var _busy: bool = false
# Einsatzprotokoll (nur Anzeige): Zeit/Checkpoints/Ausfaelle seit Levelstart
var _track_level: Node = null
var _mission_time: float = 0.0
var _cp_count: int = 0
var _cp_at: float = -1.0
var _deaths: int = 0


func _process(delta: float) -> void:
	if _main == null:
		return
	var lv = _main.get("_level")
	if lv != _track_level:
		_track_level = lv
		_mission_time = 0.0
		_cp_count = 0
		_cp_at = -1.0
		_deaths = 0
	if lv != null and not get_tree().paused:
		_mission_time += delta / maxf(Engine.time_scale, 0.01)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = get_parent()
	Events.story_objective.connect(func(t: String) -> void: _objective = t)
	Events.checkpoint_reached.connect(func(_id: String) -> void:
		_cp_count += 1
		_cp_at = _mission_time)
	Events.player_died.connect(func() -> void: _deaths += 1)
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_root.visible = false
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_players.append(p)


# ================================================================== Aufbau

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UIStyle.theme()
	add_child(_root)
	_blur = ColorRect.new()
	_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = BLUR_SHADER
	_blur.material = _blur_mat
	_root.add_child(_blur)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_frame)

	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 120)
	m.add_theme_constant_override("margin_right", 120)
	m.add_theme_constant_override("margin_top", 70)
	m.add_theme_constant_override("margin_bottom", 46)
	_frame.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	m.add_child(v)

	# Kopf: Missionstitel / Ort | aktueller Auftrag
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	head.custom_minimum_size = Vector2(0, 170)
	v.add_child(head)
	var hl := VBoxContainer.new()
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.add_theme_constant_override("separation", 2)
	head.add_child(hl)
	_tag = UIStyle.label("", 16, UIStyle.C_AMBER, 700, true)
	hl.add_child(_tag)
	_title = UIStyle.label("", 60, UIStyle.C_TEXT, 700)
	hl.add_child(_title)
	_place = UIStyle.label("", 22, UIStyle.C_DIM, 500)
	hl.add_child(_place)
	var hr := VBoxContainer.new()
	hr.custom_minimum_size = Vector2(600, 0)
	hr.alignment = BoxContainer.ALIGNMENT_END
	hr.add_theme_constant_override("separation", 6)
	head.add_child(hr)
	_obj_head = UIStyle.label("AKTUELLER AUFTRAG", 15, UIStyle.C_AMBER, 700, true)
	hr.add_child(_obj_head)
	_obj = UIStyle.label("", 23, UIStyle.C_TEXT, 500)
	_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj.custom_minimum_size = Vector2(600, 0)
	hr.add_child(_obj)
	var sp0 := Control.new()
	sp0.custom_minimum_size = Vector2(0, 18)
	v.add_child(sp0)
	v.add_child(UIStyle.hline(UIStyle.C_LINE_HI))
	var sp1 := Control.new()
	sp1.custom_minimum_size = Vector2(0, 26)
	v.add_child(sp1)

	# Rumpf: Menue links, Seitenbereich rechts (Missionen/Bestaetigung); Einstellungen ueber volle Breite
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(stack)
	_body = HBoxContainer.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.add_theme_constant_override("separation", 70)
	stack.add_child(_body)
	_menu_col = VBoxContainer.new()
	_menu_col.custom_minimum_size = Vector2(520, 0)
	_menu_col.add_theme_constant_override("separation", 4)
	_body.add_child(_menu_col)
	var items := [
		["resume", "FORTSETZEN", "Zurück in den Einsatz."],
		["checkpoint", "LETZTER CHECKPOINT", "Am zuletzt erreichten Kontrollpunkt neu ansetzen (wie nach einem Tod)."],
		["restart", "MISSION NEU STARTEN", "Die aktuelle Mission von vorn beginnen."],
		["missions", "MISSION WÄHLEN", "Eine bereits erreichte Mission spielen."],
		["episodes", "EPISODEN", "Bonus-Episoden: dieselbe Geschichte aus anderen Augen."],
		["settings", "EINSTELLUNGEN", "Steuerung, Tastenbelegung, Spiel, Audio und Grafik."],
		["mainmenu", "HAUPTMENÜ", "Den Einsatz verlassen und zum Hauptmenü zurückkehren."],
		["quit", "SPIEL BEENDEN", "Zurück zum Desktop."],
	]
	if _main == null or not _main.has_method("return_to_main_menu") or not _main.has_method("_menu_allowed") \
			or not bool(_main.call("_menu_allowed")):
		items = items.filter(func(it: Array) -> bool: return it[0] != "mainmenu")
	for i in items.size():
		var it: Array = items[i]
		if it[0] == "mainmenu" or (it[0] == "quit" and not _buttons.has("mainmenu")):
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 22)
			_menu_col.add_child(gap)
		var b := _menu_button("%02d" % (i + 1), it[1], it[2])
		b.pressed.connect(_on_item.bind(it[0]))
		_menu_col.add_child(b)
		_buttons[it[0]] = b
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.add_theme_constant_override("separation", 6)
	_body.add_child(_side)
	_settings_page = SETTINGS_MENU.new()
	_settings_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_page.visible = false
	_settings_page.connect("back_requested", func() -> void: _show_page("main", "settings"))
	_settings_page.connect("ui_sound", _sfx)
	stack.add_child(_settings_page)

	# Fuss: Hinweise / Statuszeile
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 14)
	v.add_child(sp2)
	v.add_child(UIStyle.hline())
	var foot := HBoxContainer.new()
	foot.custom_minimum_size = Vector2(0, 40)
	v.add_child(foot)
	_info = UIStyle.label("", 19, UIStyle.C_DIM)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	foot.add_child(_info)
	_foot = UIStyle.label("", 15, UIStyle.C_MUTED, 600, true)
	_foot.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	foot.add_child(_foot)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _menu_button(num: String, text: String, desc: String) -> Button:
	var b := Button.new()
	b.text = "%s    %s" % [num, text]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_override("font", UIStyle.font(700))
	b.add_theme_font_size_override("font_size", 30)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("desc", desc)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and not b.has_focus():
			b.grab_focus())
	b.focus_entered.connect(func() -> void:
		_info.text = str(b.get_meta("desc"))
		_sfx("move"))
	return b


func _side_button(text: String, sub: String = "") -> Button:
	var b := Button.new()
	b.text = text if sub == "" else "%s\n%s" % [text, sub]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 74 if sub != "" else 58)
	b.add_theme_font_override("font", UIStyle.font(600))
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and not b.has_focus():
			b.grab_focus())
	b.focus_entered.connect(func() -> void: _sfx("move"))
	return b


## Missionseintrag: Nummer | Titel (gross) + Ort/Datum (klein); Farben folgen dem Fokus.
func _mission_button(nr: int, title: String, sub: String, open_: bool, current: bool, star_mask: int = -1, best: String = "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 76)
	b.focus_mode = Control.FOCUS_ALL if open_ else Control.FOCUS_NONE
	b.disabled = not open_
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 22
	h.offset_right = -22
	h.add_theme_constant_override("separation", 22)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var n := UIStyle.label("%02d" % nr, 22, UIStyle.C_MUTED, 700, true)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.size_flags_vertical = Control.SIZE_FILL
	h.add_child(n)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := UIStyle.label(title, 26, UIStyle.C_TEXT if open_ else UIStyle.C_MUTED, 600)
	v.add_child(t)
	var sl := UIStyle.label(sub, 18, UIStyle.C_DIM if open_ else UIStyle.C_MUTED)
	v.add_child(sl)
	if open_ and star_mask >= 0:
		# Sterne (erledigt / Zielzeit / Herausforderung) + Bestzeit
		var sv := VBoxContainer.new()
		sv.alignment = BoxContainer.ALIGNMENT_CENTER
		sv.add_theme_constant_override("separation", 2)
		sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := HBoxContainer.new()
		sh.add_theme_constant_override("separation", 4)
		sh.alignment = BoxContainer.ALIGNMENT_END
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 3:
			var st: Control = STAR_ICON.new()
			st.call("setup", 20.0, ((star_mask >> i) & 1) == 1)
			sh.add_child(st)
		sv.add_child(sh)
		var bt := UIStyle.label(best if best != "" else "—", 14, UIStyle.C_MUTED, 600, true)
		bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sv.add_child(bt)
		h.add_child(sv)
	if current:
		var c := UIStyle.label("AKTUELL", 15, UIStyle.C_AMBER, 700, true)
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.size_flags_vertical = Control.SIZE_FILL
		h.add_child(c)
	if not open_:
		var lock := UIStyle.label("GESPERRT", 15, UIStyle.C_MUTED, 700, true)
		lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock.size_flags_vertical = Control.SIZE_FILL
		h.add_child(lock)
	var paint := func(on: bool) -> void:
		if not open_:
			return
		t.add_theme_color_override("font_color", UIStyle.C_AMBER if on else UIStyle.C_TEXT)
		n.add_theme_color_override("font_color", UIStyle.C_AMBER if on else UIStyle.C_MUTED)
	b.focus_entered.connect(func() -> void:
		paint.call(true)
		_sfx("move"))
	b.focus_exited.connect(func() -> void: paint.call(false))
	b.mouse_entered.connect(func() -> void:
		if open_ and not b.has_focus():
			b.grab_focus())
	return b


func _layout() -> void:
	UIStyle.fit(_frame, get_viewport().get_visible_rect().size)


# ================================================================== Oeffnen / Schliessen

func _input(event: InputEvent) -> void:
	if _busy:
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	var esc: bool = event is InputEventKey and event.pressed and not event.echo \
		and ((event as InputEventKey).physical_keycode == KEY_ESCAPE or (event as InputEventKey).keycode == KEY_ESCAPE)
	if not esc:
		return
	if is_open:
		get_viewport().set_input_as_handled()
		_back()
	elif _can_open():
		get_viewport().set_input_as_handled()
		open()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not is_open and not _busy and _can_open() 			and not Game.arg("capture", false):
		var st := get_node_or_null("/root/Settings")
		var on := true
		if st != null:
			on = bool(st.call("get_value", "game/pause_on_focus", true))
		if on:
			open()


func _can_open() -> bool:
	if _main == null or not _main.has_method("can_pause"):
		return false
	return bool(_main.call("can_pause"))


func open() -> void:
	if is_open:
		return
	is_open = true
	_prev_mouse = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_audio_pause(true)
	_refresh_header()
	_root.visible = true
	_root.modulate.a = 0.0
	_blur_mat.set_shader_parameter("amount", 0.0)
	if _tw:
		_tw.kill()
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_root, "modulate:a", 1.0, 0.16)
	_tw.tween_method(func(x: float) -> void: _blur_mat.set_shader_parameter("amount", x), 0.0, 1.0, 0.28)
	_show_page("main")
	_last_main_focus = "resume"
	_buttons["resume"].grab_focus()
	_sfx("open")


func close(resume_mouse: bool = true) -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	_settings_page.visible = false
	_audio_pause(false)
	get_tree().paused = false
	if resume_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_sfx("close")


func _audio_pause(on: bool) -> void:
	var ap := get_node_or_null("/root/Game/AudioPrefs")
	if ap != null and ap.has_method("set_paused"):
		ap.call("set_paused", on)


func _back() -> void:
	match _page:
		"settings":
			if bool(_settings_page.call("handle_back")):
				return
			_sfx("back")
			_show_page("main", "settings")
		"missions", "confirm", "episodes":
			_sfx("back")
			_show_page("main", _last_main_focus)
		_:
			close()


func _refresh_header() -> void:
	var info: Dictionary = {}
	if _main != null and _main.has_method("get_mission_info"):
		info = _main.call("get_mission_info")
	var idx := int(info.get("index", -1))
	_tag.text = "EINSATZ %s PAUSIERT  //  FUNKSTILLE" % ("%02d" % (idx + 1) if idx >= 0 else "")
	_title.text = str(info.get("title", ""))
	var place := str(info.get("place", ""))
	var date := str(info.get("date", ""))
	_place.text = place + ("   ·   " + date if date != "" else "")
	_obj_head.visible = _objective != ""
	_obj.text = _objective
	# Checkpoint verfuegbar?
	var cp := _checkpoint_target()
	var b: Button = _buttons["checkpoint"]
	b.disabled = cp == null
	b.focus_mode = Control.FOCUS_NONE if b.disabled else Control.FOCUS_ALL
	b.set_meta("desc", "Am zuletzt erreichten Kontrollpunkt neu ansetzen (wie nach einem Tod)." if cp != null
		else "In dieser Mission nicht verfügbar – nach einem Fehlschlag setzt die Besatzung selbst neu an.")
	var mb: Button = _buttons["missions"]
	var n := 0
	if _main != null and _main.has_method("unlocked_levels"):
		n = (_main.call("unlocked_levels") as Array).size()
	mb.disabled = n <= 0
	mb.focus_mode = Control.FOCUS_NONE if mb.disabled else Control.FOCUS_ALL
	# Welle 5: Episoden (Liste immer sichtbar, Sperrstatus pro Eintrag)
	var eb: Button = _buttons["episodes"]
	eb.disabled = _main == null or not _main.has_method("episode_list")
	eb.focus_mode = Control.FOCUS_NONE if eb.disabled else Control.FOCUS_ALL
	if _main != null and _main.has_method("is_episode_running") and bool(_main.call("is_episode_running")):
		_tag.text = "EPISODE PAUSIERT  //  FUNKSTILLE"


func _show_page(page: String, focus_id: String = "") -> void:
	_page = page
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()
	var settings := page == "settings"
	_settings_page.visible = settings
	_body.visible = not settings
	_obj.get_parent().visible = not settings
	match page:
		"main":
			_foot.text = "↑↓  AUSWAHL     ENTER  BESTÄTIGEN     ESC  FORTSETZEN"
			_set_menu_enabled(true)
			var fid := focus_id if focus_id != "" else _last_main_focus
			var fb: Button = _buttons.get(fid, _buttons["resume"])
			if fb.disabled:
				fb = _buttons["resume"]
			fb.grab_focus()
			_build_log()
		"missions":
			_foot.text = "↑↓  AUSWAHL     ENTER  STARTEN     ESC  ZURÜCK"
			_build_missions()
		"episodes":
			_foot.text = "↑↓  AUSWAHL     ENTER  STARTEN     ESC  ZURÜCK"
			_build_episodes()
		"confirm":
			_foot.text = "ENTER  BESTÄTIGEN     ESC  ZURÜCK"
		"settings":
			_foot.text = "↑↓  AUSWAHL     ←→  ÄNDERN     Q / E  REITER     ESC  ZURÜCK"
			_info.text = ""
			_settings_page.call("show_tab", 0)


func _set_menu_enabled(on: bool) -> void:
	for id in _buttons:
		var b: Button = _buttons[id]
		b.modulate.a = 1.0 if on else 0.45
		if not on:
			b.focus_mode = Control.FOCUS_NONE
		elif not b.disabled:
			b.focus_mode = Control.FOCUS_ALL


static func _clock(t: float) -> String:
	var sec := int(t)
	if sec >= 3600:
		return "%d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]
	return "%02d:%02d" % [sec / 60, sec % 60]


## Rechte Seite der Hauptseite: kleines Einsatzprotokoll.
func _build_log() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.box(Color(0.05, 0.06, 0.055, 0.55), UIStyle.C_LINE, 1, 0))
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	card.custom_minimum_size = Vector2(560, 0)
	_side.add_child(card)
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(k, 28)
	m.add_theme_constant_override("margin_top", 22)
	m.add_theme_constant_override("margin_bottom", 24)
	card.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	v.add_child(UIStyle.label("EINSATZPROTOKOLL", 15, UIStyle.C_AMBER, 700, true))
	v.add_child(UIStyle.hline())
	var info: Dictionary = _main.call("get_mission_info") if _main.has_method("get_mission_info") else {}
	var total := 0
	if _main.has_method("mission_list"):
		total = (_main.call("mission_list") as Array).size()
	var idx := int(info.get("index", -1))
	var rows := [
		["EINSATZ", ("%02d / %02d" % [idx + 1, total]) if idx >= 0 and total > 0 else "—"],
		["EINSATZZEIT", _clock(_mission_time)],
		["CHECKPOINTS", ("%d   (zuletzt vor %s)" % [_cp_count, _clock(_mission_time - _cp_at)]) if _cp_count > 0 else "keiner erreicht"],
		["AUSFÄLLE", str(_deaths)],
	]
	var goal: Dictionary = _main.call("current_goal_info") if _main.has_method("current_goal_info") else {}
	if not goal.is_empty():
		rows.append(["ZIELZEIT", str(goal.get("time_text", ""))])
		rows.append(["HERAUSFORDERUNG", str(goal.get("challenge_text", ""))])
		rows.append(["STERNE", "%d / 3   ·   %s" % [int(goal.get("stars", 0)), str(goal.get("difficulty", ""))]])
	for r in rows:
		var h := HBoxContainer.new()
		var k := UIStyle.label(str(r[0]), 15, UIStyle.C_MUTED, 600, true)
		k.custom_minimum_size = Vector2(190, 0)
		h.add_child(k)
		var val := UIStyle.label(str(r[1]), 22, UIStyle.C_TEXT, 600)
		h.add_child(val)
		v.add_child(h)


func _side_header(title: String, sub: String = "") -> void:
	var h := UIStyle.label(title, 15, UIStyle.C_AMBER, 700, true)
	_side.add_child(h)
	if sub != "":
		var s := UIStyle.label(sub, 20, UIStyle.C_DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side.add_child(s)
	_side.add_child(UIStyle.hline())
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_side.add_child(gap)


# ================================================================== Aktionen

func _on_item(id: String) -> void:
	if _busy:
		return
	_last_main_focus = id
	_sfx("accept")
	match id:
		"resume":
			close()
		"checkpoint":
			_reload_checkpoint()
		"restart":
			_confirm("MISSION NEU STARTEN?", "Der Fortschritt in dieser Mission geht verloren.", "NEU STARTEN",
				func() -> void: _transition(func() -> void: _main.call("restart_level")))
		"missions":
			_show_page("missions")
		"episodes":
			_show_page("episodes")
		"settings":
			_show_page("settings")
		"mainmenu":
			_confirm("ZUM HAUPTMENÜ?", "Der Fortschritt in dieser Mission geht verloren. Erreichte Missionen und Einstellungen bleiben gespeichert.",
				"HAUPTMENÜ", func() -> void: _transition(func() -> void: _main.call("return_to_main_menu")))
		"quit":
			_confirm("SPIEL BEENDEN?", "Der Fortschritt in dieser Mission geht verloren. Erreichte Missionen und Einstellungen bleiben gespeichert.",
				"BEENDEN", func() -> void: get_tree().quit())


func _confirm(title: String, text: String, yes: String, action: Callable) -> void:
	_show_page("confirm")
	_set_menu_enabled(false)
	_side_header("BESTÄTIGUNG ERFORDERLICH")
	_side.add_child(UIStyle.label(title, 44, UIStyle.C_TEXT, 700))
	var t := UIStyle.label(text, 24, UIStyle.C_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(700, 0)
	_side.add_child(t)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	_side.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_side.add_child(row)
	var by := _side_button(yes)
	by.custom_minimum_size = Vector2(300, 58)
	by.add_theme_color_override("font_color", UIStyle.C_RED)
	by.pressed.connect(func() -> void:
		_sfx("accept")
		action.call())
	row.add_child(by)
	var bn := _side_button("ABBRECHEN")
	bn.custom_minimum_size = Vector2(300, 58)
	for cb: Button in [by, bn]:
		cb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		cb.add_theme_stylebox_override("normal", UIStyle.box(Color(0, 0, 0, 0.3), UIStyle.C_LINE_HI, 1, 8))
		cb.add_theme_stylebox_override("hover", UIStyle.box(Color(1.0, 0.72, 0.28, 0.16), UIStyle.C_AMBER, 2, 8))
		cb.add_theme_stylebox_override("focus", UIStyle.box(Color(1.0, 0.72, 0.28, 0.16), UIStyle.C_AMBER, 2, 8))
	bn.pressed.connect(func() -> void:
		_sfx("back")
		_show_page("main", _last_main_focus))
	row.add_child(bn)
	by.focus_neighbor_right = by.get_path_to(bn)
	bn.focus_neighbor_left = bn.get_path_to(by)
	by.focus_entered.connect(func() -> void: _info.text = "")
	bn.focus_entered.connect(func() -> void: _info.text = "")
	bn.grab_focus()


func _build_missions() -> void:
	_set_menu_enabled(false)
	var star_sub := ""
	if _main.has_method("star_summary"):
		var ss: Dictionary = _main.call("star_summary")
		star_sub = "Sterne gesamt: %d / %d" % [int(ss.get("earned", 0)), int(ss.get("total", 0))]
	_side_header("MISSION WÄHLEN", star_sub)
	var missions: Array = _main.call("mission_list") if _main.has_method("mission_list") else []
	var cur := str((_main.call("get_mission_info") as Dictionary).get("level", ""))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_side.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var first: Button = null
	var cur_btn: Button = null
	var nr := 0
	for m: Dictionary in missions:
		nr += 1
		var lv := str(m["level"])
		var title := str(m["title"])
		var open_ := bool(m["unlocked"])
		var b := _mission_button(nr, title if open_ else "Gesperrt",
			("%s  ·  %s" % [str(m["place"]), str(m["date"])]) if open_ else "Noch nicht erreicht", open_, lv == cur,
			int(m.get("star_mask", -1)), (_clock(float(m.get("best_time", 0.0))) if float(m.get("best_time", 0.0)) > 0.0 else ""))
		var goal_txt := ""
		var g: Dictionary = m.get("goal", {})
		if not g.is_empty():
			goal_txt = "   Sterne: Abschluss · Zeit unter %s · %s." % [_clock(float(g.get("time", 0.0))), str(m.get("challenge_text", ""))]
		if lv == cur:
			cur_btn = b
		var lname: String = lv
		b.pressed.connect(func() -> void:
			_sfx("accept")
			_transition(func() -> void: _main.call("goto_level", lname)))
		b.focus_entered.connect(func() -> void:
			var msg := "Die aktuelle Mission von vorn beginnen (mit Lagebericht)."
			if lname != cur:
				msg = "Mission »%s« starten (mit Lagebericht)." % title
			_info.text = msg + goal_txt)
		list.add_child(b)
		if first == null and open_:
			first = b
	var f := cur_btn if cur_btn != null else first
	if f != null:
		f.grab_focus()


## Welle 5: Bonus-Episoden (main.episode_list -> game/episodes/episodes.gd). Gleicher Stil wie die Missionsauswahl.
func _build_episodes() -> void:
	_set_menu_enabled(false)
	var eps: Array = _main.call("episode_list") if _main.has_method("episode_list") else []
	var earned := 0
	var total := 0
	for e: Dictionary in eps:
		if bool(e.get("available", false)):
			earned += int(e.get("stars", 0))
			total += 3
	_side_header("EPISODEN", "Dieselbe Geschichte aus anderen Augen. Kein Einfluss auf die Kampagne.   Sterne: %d / %d" % [earned, total])
	var cur := str((_main.call("get_mission_info") as Dictionary).get("level", ""))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_side.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var first: Button = null
	var cur_btn: Button = null
	var nr := 0
	for e: Dictionary in eps:
		nr += 1
		var id := str(e["id"])
		var title := str(e["title"])
		var avail := bool(e.get("available", false))
		var open_ := bool(e.get("unlocked", false))
		var sub := "%s  ·  %s" % [str(e["place"]), str(e["date"])]
		if not avail:
			sub = "In Vorbereitung"
		elif not open_:
			sub = "Freigeschaltet nach »%s«" % str(_main.call("_titles_of", str(e["unlock_after"]))[0]) if _main.has_method("_titles_of") else "Noch nicht freigeschaltet"
		var b := _mission_button(nr, title, sub, open_, id == cur,
			int(e.get("star_mask", -1)), (_clock(float(e.get("best_time", 0.0))) if float(e.get("best_time", 0.0)) > 0.0 else ""))
		var goal_txt := ""
		var g: Dictionary = e.get("goal", {})
		if not g.is_empty():
			goal_txt = "   Sterne: Abschluss · Zeit unter %s · %s." % [_clock(float(g.get("time", 0.0))), Progress.challenge_text(g)]
		if id == cur:
			cur_btn = b
		var eid: String = id
		var desc := str(e.get("sub", ""))
		b.pressed.connect(func() -> void:
			_sfx("accept")
			_transition(func() -> void: _main.call("start_episode", eid)))
		b.focus_entered.connect(func() -> void:
			_info.text = desc + goal_txt)
		list.add_child(b)
		if first == null and open_:
			first = b
	var f := cur_btn if cur_btn != null else first
	if f != null:
		f.grab_focus()


## Von main.gd nach einer Episode: Menue direkt auf der Episodenseite oeffnen.
func open_episodes() -> void:
	if not is_open:
		open()
	_last_main_focus = "episodes"
	_show_page("episodes")


## Abblenden, Aktion ausfuehren (Level neu laden), Menue schliessen, aufblenden.
func _transition(action: Callable) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	await tw.finished
	close()
	action.call()
	await get_tree().process_frame
	await get_tree().process_frame
	_busy = false
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.25)


func _checkpoint_target() -> Node:
	var lv := get_tree().get_first_node_in_group("level")
	if lv == null and _main != null:
		lv = _main.get("_level") as Node
	if lv != null and is_instance_valid(lv) and lv.has_method("menu_reload_checkpoint"):
		return lv
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("respawn") and pl is Player:
		return pl
	return null


func _reload_checkpoint() -> void:
	var target := _checkpoint_target()
	if target == null or _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	await tw.finished
	close()
	if target.has_method("menu_reload_checkpoint"):
		target.call("menu_reload_checkpoint")
	else:
		target.call("respawn")
	await get_tree().create_timer(0.15).timeout
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.45)
	await tw2.finished
	_busy = false


# ================================================================== Klang

func _sfx(kind: String) -> void:
	var path: String = SFX.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	if not _sfx_cache.has(path):
		_sfx_cache[path] = load(path)
	var p: AudioStreamPlayer = null
	for q in _sfx_players:
		if not q.playing:
			p = q
			break
	if p == null:
		if _sfx_players.is_empty():
			return
		p = _sfx_players[0]
	p.stream = _sfx_cache[path]
	p.volume_db = float(SFX_DB.get(kind, -18.0))
	p.pitch_scale = 1.15 if kind == "tick" else 1.0
	p.play()
