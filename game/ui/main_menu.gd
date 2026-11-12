extends CanvasLayer
## Hauptmenue beim normalen Spielstart (main.gd: _menu_allowed – nie mit --level/--autopilot/--debug-server/
## --capture/--phase/--intro/--no-menu). Seiten: main | missions | episodes | settings | confirm | credits.
## Hintergrund: gerenderte Level-Standbilder (assets/ui/menu/bg_*.jpg, erzeugt mit game/ui/tools/menu_bg_shot.tscn)
## mit Ken-Burns-Zoom, Grading und Glut (main_menu_bg.gdshader). Look wie Pausenmenue (UIStyle).
## Startet ueber main.gd: menu_state, mission_list, part_of, part_title, episode_list,
## menu_start_level, menu_new_campaign, menu_start_episode. Nach dem Aufruf entfernt main das Menue.
## Tastatur/Maus und Gamepad (ui_up/down/accept/cancel, LB/RB = Reiter in den Einstellungen).

const SETTINGS_MENU := preload("res://game/ui/settings_menu.gd")
const STAR_ICON := preload("res://game/progress/star_icon.gd")
const Progress = preload("res://game/progress/progress.gd")
const BG_SHADER := preload("res://game/ui/main_menu_bg.gdshader")
const BACKGROUNDS := ["res://assets/ui/menu/bg_strasse.jpg", "res://assets/ui/menu/bg_werk.jpg",
	"res://assets/ui/menu/bg_strasse2.jpg"]
## Bewegung je Bild (Ken Burns): Schwenkrichtung in UV pro Standzeit
const BG_PAN := [Vector2(0.018, -0.006), Vector2(-0.016, 0.004), Vector2(0.012, 0.006)]
const BG_HOLD := 15.0
const BG_FADE := 3.2
const MUSIC := "res://assets/sfx/intro_music_a.wav"
const MUSIC_DB := -11.0
const AMBIENCE := "res://assets/sfx/amb_wind.ogg"
const AMBIENCE_DB := -14.0
const SFX := {
	"move": "res://assets/sfx/intro_tick.wav",
	"tick": "res://assets/sfx/intro_tick.wav",
	"tab": "res://assets/sfx/intro_radio_click.wav",
	"accept": "res://assets/sfx/intro_beep.wav",
	"back": "res://assets/sfx/intro_radio_click.wav",
}
const SFX_DB := {"move": -24.0, "tick": -22.0, "tab": -14.0, "accept": -18.0, "back": -16.0}

var start_page: String = ""        ## von main gesetzt (z. B. "episodes" nach einer Episode)
var _main: Node
var _root: Control
var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _frame: Control
var _fade: ColorRect
var _head: Control
var _title_box: Control
var _status: Label
var _body: HBoxContainer
var _menu_col: VBoxContainer
var _side: VBoxContainer
var _settings_page: Control
var _info: Label
var _foot: Label
var _buttons: Dictionary = {}        # id -> Button
var _page: String = "main"
var _last_main_focus: String = "continue"
var _state: Dictionary = {}
var _busy: bool = false
var _music: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cache: Dictionary = {}
# Hintergrund-Wechsel
var _bg_tex: Array = []              # geladene Texturen (null = noch nicht geladen)
var _bg_cur: int = 0
var _bg_t: float = 0.0               # Zeit seit Beginn des aktuellen Bilds
var _bg_next_t: float = 0.0          # Zeit seit Beginn des naechsten Bilds (waehrend Ueberblendung)
var _bg_fading: bool = false
var _blink_t: float = 0.0


func _ready() -> void:
	layer = 98                     # ueber main._ui (90), unter Pausenmenue (100); Abspann (95) = Menue ausblenden
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = get_parent()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_state = _call("menu_state", {})
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)
	_start_audio()
	_show_page("main")
	if start_page == "episodes":
		_last_main_focus = "episodes"
		_show_page("episodes")
	# Einblenden
	_fade.color.a = 1.0
	_title_box.modulate.a = 0.0
	_title_box.position.x = -24.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_fade, "color:a", 0.0, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_title_box, "modulate:a", 1.0, 1.4).set_delay(0.35)
	tw.tween_property(_title_box, "position:x", 0.0, 1.6).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	print("[menu] Hauptmenue (Fortschritt: %s, Fortsetzen: %s)" % [_state.get("has_progress", false), _state.get("continue", "")])


func _call(method: String, default = null, args: Array = []):
	if _main == null or not _main.has_method(method):
		return default
	return _main.callv(method, args)


# ================================================================== Aufbau

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UIStyle.theme()
	add_child(_root)
	_build_background()
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_frame)

	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 120)
	m.add_theme_constant_override("margin_right", 120)
	m.add_theme_constant_override("margin_top", 64)
	m.add_theme_constant_override("margin_bottom", 46)
	_frame.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	m.add_child(v)

	# Kopf: Titel links, Funkstatus rechts
	_head = HBoxContainer.new()
	_head.custom_minimum_size = Vector2(0, 250)
	v.add_child(_head)
	var tb_holder := Control.new()
	tb_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb_holder.custom_minimum_size = Vector2(0, 250)
	_head.add_child(tb_holder)
	var tb := VBoxContainer.new()
	tb.add_theme_constant_override("separation", 0)
	tb.size = Vector2(1100, 250)
	_title_box = tb
	tb_holder.add_child(tb)
	tb.add_child(UIStyle.label("BUNDESREPUBLIK DEUTSCHLAND  //  LAGEZENTRUM  //  2030", 16, UIStyle.C_AMBER, 700, true))
	var title := UIStyle.label("LETZTES REICH", 134, UIStyle.C_TEXT, 700)
	var fv := FontVariation.new()
	fv.base_font = UIStyle.font(700)
	fv.spacing_glyph = 7
	title.add_theme_font_override("font", fv)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 18)
	title.add_theme_constant_override("line_spacing", -12)
	tb.add_child(title)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 18)
	tb.add_child(sub)
	var bar := ColorRect.new()
	bar.color = UIStyle.C_AMBER
	bar.custom_minimum_size = Vector2(96, 4)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_child(bar)
	sub.add_child(UIStyle.label("KAMPAGNE „NORD“   ·   VIER TEILE   ·   %d EINSÄTZE" % int(_state.get("total", 17)), 21, UIStyle.C_DIM, 600))
	var hr := VBoxContainer.new()
	hr.alignment = BoxContainer.ALIGNMENT_BEGIN
	hr.custom_minimum_size = Vector2(420, 0)
	hr.add_theme_constant_override("separation", 4)
	_head.add_child(hr)
	_status = UIStyle.label("●  FUNK BEREIT", 15, UIStyle.C_AMBER, 700, true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hr.add_child(_status)
	var diff := UIStyle.label("SCHWIERIGKEIT  %s" % str(_state.get("difficulty", "")).to_upper(), 15, UIStyle.C_MUTED, 600, true)
	diff.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hr.add_child(diff)

	var sp1 := Control.new()
	sp1.custom_minimum_size = Vector2(0, 30)
	v.add_child(sp1)

	# Rumpf: Menue links, rechts Infokarte bzw. Unterseite; Einstellungen ueber volle Breite
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
	_menu_col.add_theme_constant_override("separation", 2)
	_body.add_child(_menu_col)
	var has_prog := bool(_state.get("has_progress", false))
	var items := [
		["continue", "FORTSETZEN", "Weiter mit dem zuletzt erreichten Einsatz." if has_prog else "Noch kein Fortschritt – beginne eine neue Kampagne."],
		["new", "NEUE KAMPAGNE", "Die Kampagne von vorn beginnen, mit Intro."],
		["missions", "MISSIONSAUSWAHL", "Einen bereits erreichten Einsatz erneut spielen."],
		["episodes", "EPISODEN", "Bonus-Episoden: dieselbe Geschichte aus anderen Augen."],
		["settings", "EINSTELLUNGEN", "Steuerung, Tastenbelegung, Spiel, Audio und Grafik."],
		["credits", "MITWIRKENDE", "Der Abspann. Es sind nicht viele."],
		["quit", "BEENDEN", "Zurück zum Desktop."],
	]
	var prev: Button = null
	var first: Button = null
	for i in items.size():
		var it: Array = items[i]
		if it[0] == "settings" or it[0] == "quit":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 16)
			_menu_col.add_child(gap)
		var b := _menu_button("%02d" % (i + 1), it[1], it[2], it[0])
		b.pressed.connect(_on_item.bind(it[0]))
		_menu_col.add_child(b)
		_buttons[it[0]] = b
	var cb: Button = _buttons["continue"]
	cb.disabled = not has_prog
	cb.focus_mode = Control.FOCUS_NONE if cb.disabled else Control.FOCUS_ALL
	var mb: Button = _buttons["missions"]
	mb.disabled = not has_prog
	mb.focus_mode = Control.FOCUS_NONE if mb.disabled else Control.FOCUS_ALL
	if not has_prog:
		mb.set_meta("desc", "Noch keine Einsätze erreicht.")
	# Fokus-Ring: oben/unten umlaufend
	var order: Array = []
	for id in ["continue", "new", "missions", "episodes", "settings", "credits", "quit"]:
		order.append(_buttons[id])
	first = order[0]
	prev = order.back()
	first.focus_neighbor_top = first.get_path_to(prev)
	prev.focus_neighbor_bottom = prev.get_path_to(first)
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

	# Fuss
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
	_info.clip_text = true
	foot.add_child(_info)
	_foot = UIStyle.label("", 15, UIStyle.C_MUTED, 600, true)
	_foot.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	foot.add_child(_foot)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)


func _build_background() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color.BLACK
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = BG_SHADER
	_bg.material = _bg_mat
	_root.add_child(_bg)
	_bg_tex.resize(BACKGROUNDS.size())
	# erstes Bild = Fortschritt-abhaengig (Teil 1/2 Strasse, sonst Werk) – einfach: zufaellig, aber stabil pro Start
	_bg_cur = randi() % BACKGROUNDS.size()
	if Game.arg("menu-bg", null) != null:
		_bg_cur = clampi(int(Game.arg("menu-bg", 0)), 0, BACKGROUNDS.size() - 1)
	var t := _bg_texture(_bg_cur)
	if t != null:
		_bg_mat.set_shader_parameter("img_a", t)
		_bg_mat.set_shader_parameter("img_aspect", float(t.get_width()) / float(maxi(t.get_height(), 1)))
	# Folgebilder im Hintergrund laden (kein Ruckler beim Wechsel)
	for i in BACKGROUNDS.size():
		if i != _bg_cur and ResourceLoader.exists(BACKGROUNDS[i]):
			ResourceLoader.load_threaded_request(BACKGROUNDS[i])
	_bg_t = 4.0
	_apply_bg_motion()
	# Glut / Asche: steigt von unten auf (additiv)
	var em := CPUParticles2D.new()
	em.amount = 70
	em.lifetime = 9.0
	em.preprocess = 9.0
	em.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	em.emission_rect_extents = Vector2(1100, 20)
	em.position = Vector2(1150, 1120)
	em.direction = Vector2(0.15, -1)
	em.spread = 22.0
	em.gravity = Vector2(10, -6)
	em.initial_velocity_min = 28.0
	em.initial_velocity_max = 85.0
	em.angular_velocity_min = -40
	em.angular_velocity_max = 40
	em.scale_amount_min = 0.05
	em.scale_amount_max = 0.16
	em.texture = _dot_texture()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.62, 0.22, 0.0))
	ramp.set_color(1, Color(1.0, 0.45, 0.15, 0.0))
	ramp.add_point(0.12, Color(1.0, 0.7, 0.3, 0.85))
	ramp.add_point(0.7, Color(1.0, 0.42, 0.12, 0.45))
	em.color_ramp = ramp
	em.hue_variation_min = -0.03
	em.hue_variation_max = 0.03
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	em.material = cm
	_bg.add_child(em)
	_bg.resized.connect(func() -> void:
		var s := _bg.size
		em.position = Vector2(s.x * 0.6, s.y + 40.0)
		em.emission_rect_extents = Vector2(s.x * 0.58, 20.0))


func _dot_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.75))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	return gt


func _bg_texture(i: int) -> Texture2D:
	if _bg_tex[i] != null:
		return _bg_tex[i]
	var path: String = BACKGROUNDS[i]
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = null
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return null                   # noch nicht fertig: Wechsel verschieben
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		t = ResourceLoader.load_threaded_get(path) as Texture2D
	else:
		t = load(path) as Texture2D
	_bg_tex[i] = t
	return t


func _apply_bg_motion() -> void:
	var dur := BG_HOLD + BG_FADE * 2.0
	var ka := clampf(_bg_t / dur, 0.0, 1.0)
	_bg_mat.set_shader_parameter("zoom_a", 1.035 + 0.075 * ka)
	_bg_mat.set_shader_parameter("pan_a", (BG_PAN[_bg_cur] as Vector2) * (ka - 0.5))
	var nx := (_bg_cur + 1) % BACKGROUNDS.size()
	var kb := clampf(_bg_next_t / dur, 0.0, 1.0)
	_bg_mat.set_shader_parameter("zoom_b", 1.035 + 0.075 * kb)
	_bg_mat.set_shader_parameter("pan_b", (BG_PAN[nx] as Vector2) * (kb - 0.5))


func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE and _page != "credits":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_blink_t += delta
	if _status != null:
		_status.modulate.a = 0.55 + 0.45 * absf(cos(_blink_t * 1.6))
	if _bg_mat == null or BACKGROUNDS.size() < 2 or Game.arg("menu-bg", null) != null:
		return
	_bg_t += delta
	if _bg_fading:
		_bg_next_t += delta
		var k := clampf(_bg_next_t / BG_FADE, 0.0, 1.0)
		_bg_mat.set_shader_parameter("mix_ab", k * k * (3.0 - 2.0 * k))
		if k >= 1.0:
			# naechstes Bild wird Bild A
			_bg_cur = (_bg_cur + 1) % BACKGROUNDS.size()
			_bg_mat.set_shader_parameter("img_a", _bg_tex[_bg_cur])
			_bg_mat.set_shader_parameter("mix_ab", 0.0)
			_bg_t = _bg_next_t
			_bg_next_t = 0.0
			_bg_fading = false
	elif _bg_t >= BG_HOLD + BG_FADE:
		var nx := (_bg_cur + 1) % BACKGROUNDS.size()
		var t := _bg_texture(nx)
		if t != null:
			_bg_mat.set_shader_parameter("img_b", t)
			_bg_next_t = 0.0
			_bg_fading = true
	_apply_bg_motion()


func _menu_button(num: String, text: String, desc: String, id: String) -> Button:
	var b := Button.new()
	b.text = "%s    %s" % [num, text]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 62)
	b.add_theme_font_override("font", UIStyle.font(700))
	b.add_theme_font_size_override("font_size", 30)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("desc", desc)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and not b.has_focus() and not _busy:
			b.grab_focus())
	b.focus_entered.connect(func() -> void:
		_info.text = str(b.get_meta("desc"))
		if _page == "main":
			_last_main_focus = id
			_build_card(id)
		_sfx("move"))
	return b


func _side_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(300, 58)
	b.add_theme_font_override("font", UIStyle.font(600))
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", UIStyle.box(Color(0, 0, 0, 0.3), UIStyle.C_LINE_HI, 1, 8))
	b.add_theme_stylebox_override("hover", UIStyle.box(Color(1.0, 0.72, 0.28, 0.16), UIStyle.C_AMBER, 2, 8))
	b.add_theme_stylebox_override("focus", UIStyle.box(Color(1.0, 0.72, 0.28, 0.16), UIStyle.C_AMBER, 2, 8))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and not b.has_focus() and not _busy:
			b.grab_focus())
	b.focus_entered.connect(func() -> void: _sfx("move"))
	return b


## Missionseintrag wie im Pausenmenue: Nummer | Titel + Ort/Datum | Sterne + Bestzeit.
func _mission_button(nr: int, title: String, sub: String, star_mask: int, best: String, highlight: String = "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 74)
	b.focus_mode = Control.FOCUS_ALL
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
	var t := UIStyle.label(title, 26, UIStyle.C_TEXT, 600)
	v.add_child(t)
	v.add_child(UIStyle.label(sub, 18, UIStyle.C_DIM))
	if highlight != "":
		var c := UIStyle.label(highlight, 15, UIStyle.C_AMBER, 700, true)
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.size_flags_vertical = Control.SIZE_FILL
		h.add_child(c)
	if star_mask >= 0:
		var sv := VBoxContainer.new()
		sv.alignment = BoxContainer.ALIGNMENT_CENTER
		sv.add_theme_constant_override("separation", 2)
		sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sv.add_child(_stars(star_mask, 20.0))
		var bt := UIStyle.label(best if best != "" else "—", 14, UIStyle.C_MUTED, 600, true)
		bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sv.add_child(bt)
		h.add_child(sv)
	var paint := func(on: bool) -> void:
		t.add_theme_color_override("font_color", UIStyle.C_AMBER if on else UIStyle.C_TEXT)
		n.add_theme_color_override("font_color", UIStyle.C_AMBER if on else UIStyle.C_MUTED)
	b.focus_entered.connect(func() -> void:
		paint.call(true)
		_sfx("move"))
	b.focus_exited.connect(func() -> void: paint.call(false))
	b.mouse_entered.connect(func() -> void:
		if not b.has_focus() and not _busy:
			b.grab_focus())
	return b


func _stars(mask: int, size: float) -> HBoxContainer:
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	sh.alignment = BoxContainer.ALIGNMENT_END
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var st: Control = STAR_ICON.new()
		st.call("setup", size, ((mask >> i) & 1) == 1)
		sh.add_child(st)
	return sh


func _layout() -> void:
	UIStyle.fit(_frame, get_viewport().get_visible_rect().size)


# ================================================================== Seiten

func _show_page(page: String, focus_id: String = "") -> void:
	_page = page
	_clear_side()
	var settings := page == "settings"
	_settings_page.visible = settings
	_body.visible = not settings
	_head.visible = not settings
	_set_dim(0.0 if page == "main" else 1.0)
	match page:
		"main":
			_foot.text = "↑↓  AUSWAHL     ENTER / Ⓐ  BESTÄTIGEN"
			_set_menu_enabled(true)
			var fid := focus_id if focus_id != "" else _last_main_focus
			if not _buttons.has(fid) or (_buttons[fid] as Button).disabled:
				fid = "new"
			_last_main_focus = fid
			(_buttons[fid] as Button).grab_focus()
			_build_card(fid)
		"missions":
			_foot.text = "↑↓  AUSWAHL     ENTER / Ⓐ  STARTEN     ESC / Ⓑ  ZURÜCK"
			_build_missions()
		"episodes":
			_foot.text = "↑↓  AUSWAHL     ENTER / Ⓐ  STARTEN     ESC / Ⓑ  ZURÜCK"
			_build_episodes()
		"confirm":
			_foot.text = "←→  AUSWAHL     ENTER / Ⓐ  BESTÄTIGEN     ESC / Ⓑ  ZURÜCK"
		"settings":
			_foot.text = "↑↓  AUSWAHL     ←→  ÄNDERN     Q / E · LB / RB  REITER     ESC / Ⓑ  ZURÜCK"
			_info.text = ""
			_settings_page.call("show_tab", 0)


var _dim_tw: Tween
var _dim_val: float = 0.0

func _set_dim(v: float) -> void:
	if _bg_mat == null:
		return
	if _dim_tw != null and _dim_tw.is_valid():
		_dim_tw.kill()
	_dim_tw = create_tween()
	_dim_tw.tween_method(func(x: float) -> void: _dim_val = x; _bg_mat.set_shader_parameter("dim", x),
		_dim_val, v, 0.35)


func _clear_side() -> void:
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()


func _set_menu_enabled(on: bool) -> void:
	for id in _buttons:
		var b: Button = _buttons[id]
		b.modulate.a = 1.0 if on else 0.42
		if not on:
			b.focus_mode = Control.FOCUS_NONE
		elif not b.disabled:
			b.focus_mode = Control.FOCUS_ALL


func _side_header(title: String, sub: String = "") -> void:
	_side.add_child(UIStyle.label(title, 15, UIStyle.C_AMBER, 700, true))
	if sub != "":
		var s := UIStyle.label(sub, 20, UIStyle.C_DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side.add_child(s)
	_side.add_child(UIStyle.hline())
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_side.add_child(gap)


## Infokarte rechts unten (Hauptseite): folgt dem Fokus.
func _build_card(id: String) -> void:
	if _page != "main":
		return
	_clear_side()
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(fill)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_box())
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	card.custom_minimum_size = Vector2(600, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(card)
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(k, 30)
	m.add_theme_constant_override("margin_top", 24)
	m.add_theme_constant_override("margin_bottom", 26)
	card.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var st := _state
	match id:
		"continue":
			if not bool(st.get("has_progress", false)):
				_card_text(v, "FORTSETZEN", "Noch kein Einsatz begonnen.", "Wähle »Neue Kampagne«, um mit dem Intro zu beginnen.")
				return
			v.add_child(UIStyle.label("NÄCHSTER EINSATZ  //  %s" % str(st.get("part_title", "")).to_upper(), 15, UIStyle.C_AMBER, 700, true))
			v.add_child(UIStyle.hline())
			var tl := UIStyle.label(str(st.get("title", "")), 44, UIStyle.C_TEXT, 700)
			v.add_child(tl)
			v.add_child(UIStyle.label(str(st.get("place", "")), 22, UIStyle.C_DIM, 500))
			v.add_child(UIStyle.label(str(st.get("date", "")), 18, UIStyle.C_MUTED, 600, true))
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 6)
			v.add_child(gap)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 16)
			v.add_child(row)
			var nr := UIStyle.label("EINSATZ %02d / %02d" % [int(st.get("index", 0)) + 1, int(st.get("total", 0))], 16, UIStyle.C_DIM, 700, true)
			nr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nr)
			row.add_child(_stars(int(st.get("star_mask", 0)), 22.0))
		"new":
			var t := "Von vorn: Intro, Schwierigkeitswahl, dann Einsatz 01 – »%s«." % str(st.get("first_title", ""))
			var w := ""
			if bool(st.get("has_progress", false)):
				w = "Setzt die erreichten Einsätze zurück (Rückfrage folgt). Sterne und Bestzeiten bleiben erhalten."
			_card_text(v, "NEUE KAMPAGNE", "Kampagne „Nord“", t, w)
		"missions":
			_card_head(v, "EINSATZÜBERSICHT")
			_card_row(v, "ERREICHT", "%d / %d Einsätze" % [int(st.get("reached", 0)), int(st.get("total", 0))])
			_card_row(v, "STERNE", "%d / %d" % [int(st.get("stars", 0)), int(st.get("stars_total", 0))])
			for p: Dictionary in st.get("parts", []):
				_card_row(v, str(p["short"]).to_upper(), "%s   %d / %d" % [str(p["name"]), int(p["reached"]), int(p["count"])],
					UIStyle.C_TEXT if int(p["reached"]) > 0 else UIStyle.C_MUTED)
		"episodes":
			_card_head(v, "BONUS-EPISODEN")
			_card_row(v, "VERFÜGBAR", "%d / %d freigeschaltet" % [int(st.get("episodes_open", 0)), int(st.get("episodes_total", 0))])
			var d := UIStyle.label("Kurze Einsätze abseits der Kampagne – andere Figuren, andere Orte. Freischaltung über den Kampagnenfortschritt.", 20, UIStyle.C_DIM)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(d)
		"settings":
			_card_head(v, "EINSTELLUNGEN")
			_card_row(v, "SCHWIERIGKEIT", str(st.get("difficulty", "")))
			var d2 := UIStyle.label("Steuerung, Tastenbelegung, Spiel, Audio und Grafik. Änderungen werden sofort gespeichert.", 20, UIStyle.C_DIM)
			d2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(d2)
		"credits":
			_card_text(v, "MITWIRKENDE", "Abspann", "Alle, die an diesem Spiel beteiligt waren. Leertaste beschleunigt, Esc überspringt.")
		"quit":
			_card_text(v, "BEENDEN", "Zurück zum Desktop", "Erreichte Einsätze, Sterne und Einstellungen sind gespeichert.")


func _card_box() -> StyleBoxFlat:
	var sb := UIStyle.box(Color(0.03, 0.04, 0.036, 0.72), UIStyle.C_LINE, 1, 0)
	sb.border_width_left = 3
	sb.border_color = UIStyle.C_LINE_HI
	return sb


func _card_head(v: VBoxContainer, head: String) -> void:
	v.add_child(UIStyle.label(head, 15, UIStyle.C_AMBER, 700, true))
	v.add_child(UIStyle.hline())


func _card_text(v: VBoxContainer, head: String, title: String, text: String, warn: String = "") -> void:
	_card_head(v, head)
	v.add_child(UIStyle.label(title, 36, UIStyle.C_TEXT, 700))
	var t := UIStyle.label(text, 20, UIStyle.C_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	if warn != "":
		var w := UIStyle.label(warn, 18, UIStyle.C_AMBER, 500)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(w)


func _card_row(v: VBoxContainer, key: String, val: String, col: Color = UIStyle.C_TEXT) -> void:
	var h := HBoxContainer.new()
	var k := UIStyle.label(key, 15, UIStyle.C_MUTED, 600, true)
	k.custom_minimum_size = Vector2(170, 0)
	h.add_child(k)
	h.add_child(UIStyle.label(val, 22, col, 600))
	v.add_child(h)


func _build_missions() -> void:
	_set_menu_enabled(false)
	_side_header("MISSIONSAUSWAHL", "Erreicht: %d / %d Einsätze   ·   Sterne: %d / %d" % [int(_state.get("reached", 0)),
		int(_state.get("total", 0)), int(_state.get("stars", 0)), int(_state.get("stars_total", 0))])
	var missions: Array = _call("mission_list", [])
	var cont := str(_state.get("continue", ""))
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
	var focus_btn: Button = null
	var last_part := -1
	var nr := 0
	for m: Dictionary in missions:
		nr += 1
		if not bool(m.get("unlocked", false)):
			continue          # nur freigeschaltete Einsaetze
		var lv := str(m["level"])
		var part := int(_call("part_of", 0, [lv]))
		if part != last_part:
			last_part = part
			var ph := UIStyle.label(str(_call("part_title", "Teil %d" % part, [part])).to_upper(), 15, UIStyle.C_AMBER, 700, true)
			var pm := MarginContainer.new()
			pm.add_theme_constant_override("margin_top", 14 if list.get_child_count() > 0 else 2)
			pm.add_theme_constant_override("margin_bottom", 4)
			pm.add_theme_constant_override("margin_left", 22)
			pm.add_child(ph)
			list.add_child(pm)
		var title := str(m["title"])
		var best := float(m.get("best_time", 0.0))
		var b := _mission_button(nr, title, "%s  ·  %s" % [str(m["place"]), str(m["date"])], int(m.get("star_mask", 0)),
			Progress.clock(best) if best > 0.0 else "", "ZULETZT" if lv == cont else "")
		var goal_txt := ""
		var g: Dictionary = m.get("goal", {})
		if not g.is_empty():
			goal_txt = "   Sterne: Abschluss · Zeit unter %s · %s." % [Progress.clock(float(g.get("time", 0.0))), str(m.get("challenge_text", ""))]
		var lname: String = lv
		b.pressed.connect(func() -> void:
			_sfx("accept")
			_launch("menu_start_level", [lname]))
		b.focus_entered.connect(func() -> void: _info.text = "Einsatz »%s« starten (mit Lagebericht)." % title + goal_txt)
		list.add_child(b)
		if first == null:
			first = b
		if lv == cont:
			focus_btn = b
	var f := focus_btn if focus_btn != null else first
	if f != null:
		f.grab_focus()


func _build_episodes() -> void:
	_set_menu_enabled(false)
	var eps: Array = _call("episode_list", [])
	var earned := 0
	var total := 0
	for e: Dictionary in eps:
		if bool(e.get("available", false)):
			earned += int(e.get("stars", 0))
			total += 3
	_side_header("EPISODEN", "Dieselbe Geschichte aus anderen Augen. Kein Einfluss auf die Kampagne.   Sterne: %d / %d" % [earned, total])
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
	var nr := 0
	for e: Dictionary in eps:
		nr += 1
		var id := str(e["id"])
		var title := str(e["title"])
		var avail := bool(e.get("available", false))
		var open_ := bool(e.get("unlocked", false))
		var b: Button
		if open_:
			var best := float(e.get("best_time", 0.0))
			b = _mission_button(nr, title, "%s  ·  %s" % [str(e["place"]), str(e["date"])], int(e.get("star_mask", 0)),
				Progress.clock(best) if best > 0.0 else "")
			var eid := id
			b.pressed.connect(func() -> void:
				_sfx("accept")
				_launch("menu_start_episode", [eid]))
			var desc := str(e.get("sub", ""))
			var goal_txt := ""
			var g: Dictionary = e.get("goal", {})
			if not g.is_empty():
				goal_txt = "   Sterne: Abschluss · Zeit unter %s · %s." % [Progress.clock(float(g.get("time", 0.0))), Progress.challenge_text(g)]
			b.focus_entered.connect(func() -> void: _info.text = desc + goal_txt)
			if first == null:
				first = b
		else:
			var why := "In Vorbereitung"
			if avail:
				why = "Freigeschaltet nach »%s«" % str((_call("_titles_of", [""], [str(e.get("unlock_after", ""))]) as Array)[0])
			b = _locked_button(nr, why)
		list.add_child(b)
	if first != null:
		first.grab_focus()
	else:
		_info.text = "Noch keine Episode freigeschaltet."


## Gesperrter Eintrag (nicht fokussierbar): Titel bleibt geheim.
func _locked_button(nr: int, why: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 74)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = true
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
	h.add_child(v)
	v.add_child(UIStyle.label("Gesperrt", 26, UIStyle.C_MUTED, 600))
	v.add_child(UIStyle.label(why, 18, UIStyle.C_MUTED))
	var lock := UIStyle.label("GESPERRT", 15, UIStyle.C_MUTED, 700, true)
	lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock.size_flags_vertical = Control.SIZE_FILL
	h.add_child(lock)
	return b


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
	by.add_theme_color_override("font_color", UIStyle.C_RED)
	by.pressed.connect(func() -> void:
		_sfx("accept")
		action.call())
	row.add_child(by)
	var bn := _side_button("ABBRECHEN")
	bn.pressed.connect(func() -> void:
		_sfx("back")
		_show_page("main", _last_main_focus))
	row.add_child(bn)
	by.focus_neighbor_right = by.get_path_to(bn)
	bn.focus_neighbor_left = bn.get_path_to(by)
	by.focus_neighbor_left = by.get_path_to(bn)
	bn.focus_neighbor_right = bn.get_path_to(by)
	for x: Button in [by, bn]:
		x.focus_neighbor_top = x.get_path()
		x.focus_neighbor_bottom = x.get_path()
		x.focus_entered.connect(func() -> void: _info.text = "")
	bn.grab_focus()


# ================================================================== Aktionen

func _on_item(id: String) -> void:
	if _busy:
		return
	_last_main_focus = id
	_sfx("accept")
	match id:
		"continue":
			var lv := str(_state.get("continue", ""))
			if lv != "":
				_launch("menu_start_level", [lv])
		"new":
			if bool(_state.get("has_progress", false)):
				_confirm("NEUE KAMPAGNE BEGINNEN?",
					"Die erreichten Einsätze werden zurückgesetzt – Missionsauswahl und »Fortsetzen« beginnen wieder bei Einsatz 01. Sterne, Bestzeiten und Einstellungen bleiben erhalten.",
					"NEU BEGINNEN", func() -> void: _launch("menu_new_campaign", [true]))
			else:
				_launch("menu_new_campaign", [false])
		"missions":
			_show_page("missions")
		"episodes":
			_show_page("episodes")
		"settings":
			_show_page("settings")
		"credits":
			_play_credits()
		"quit":
			_confirm("SPIEL BEENDEN?", "Erreichte Einsätze, Sterne und Einstellungen sind gespeichert.", "BEENDEN",
				func() -> void: _quit())


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
		"main":
			# Esc auf der Hauptseite: Fokus auf "Beenden" (kein Sofort-Beenden)
			if not (_buttons["quit"] as Button).has_focus():
				_sfx("back")
				(_buttons["quit"] as Button).grab_focus()


## Abblenden (Bild + Musik), dann main.<method> aufrufen; main entfernt das Menue und laedt wie gewohnt.
func _launch(method: String, args: Array) -> void:
	if _busy:
		return
	_busy = true
	_set_menu_enabled(false)
	print("[menu] -> %s %s" % [method, str(args)])
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_fade, "color:a", 1.0, 0.55)
	if _music != null:
		tw.tween_property(_music, "volume_db", -60.0, 0.6)
	if _amb != null:
		tw.tween_property(_amb, "volume_db", -60.0, 0.6)
	await tw.finished
	await get_tree().process_frame
	_call(method, null, args)


func _quit() -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	if _music != null:
		tw.tween_property(_music, "volume_db", -60.0, 0.4)
	await tw.finished
	get_tree().quit()


func _play_credits() -> void:
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	await tw.finished
	_page = "credits"
	_root.visible = false
	_busy = false
	await Credits.play(self)
	_root.visible = true
	_show_page("main", "credits")
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.6)


func _input(event: InputEvent) -> void:
	if _busy:
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	if _page == "credits":
		# Gamepad: B/Start ueberspringt den Abspann (Tastatur fragt credits.gd selbst ab)
		if event is InputEventJoypadButton and event.pressed:
			for c in get_children():
				if c.has_method("_finish"):
					c.call("_finish")
			get_viewport().set_input_as_handled()
		return
	if _page == "settings" and event is InputEventJoypadButton and event.pressed:
		var jb := (event as InputEventJoypadButton).button_index
		if jb == JOY_BUTTON_LEFT_SHOULDER or jb == JOY_BUTTON_RIGHT_SHOULDER:
			_sfx("tab")
			_settings_page.call("show_tab", int(_settings_page.get("_tab")) + (1 if jb == JOY_BUTTON_RIGHT_SHOULDER else -1))
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel") and not (event is InputEventKey and (event as InputEventKey).echo):
		get_viewport().set_input_as_handled()
		_back()


# ================================================================== Klang

func _start_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if ResourceLoader.exists(MUSIC):
		_music = AudioStreamPlayer.new()
		_music.stream = load(MUSIC)
		_music.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
		_music.volume_db = -40.0
		add_child(_music)
		_music.finished.connect(func() -> void:
			if not _busy:
				_music.play())
		_music.play()
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", _music_db(), 3.0)
		var st := get_node_or_null("/root/Settings")
		if st != null:
			st.connect("changed", func(key: String, _v) -> void:
				if key in ["audio/music", "audio/master"] and _music != null and not _busy:
					_music.volume_db = _music_db())
	if ResourceLoader.exists(AMBIENCE):
		_amb = AudioStreamPlayer.new()
		_amb.stream = load(AMBIENCE)
		_amb.bus = "Ambient" if AudioServer.get_bus_index("Ambient") >= 0 else "Master"
		_amb.volume_db = -50.0
		add_child(_amb)
		_amb.finished.connect(func() -> void:
			if not _busy:
				_amb.play())
		_amb.play()
		var tw2 := create_tween()
		tw2.tween_property(_amb, "volume_db", AMBIENCE_DB, 4.0)


## Kein eigener Musik-Bus im Layout: Regler "Musik" hier direkt anwenden (Master-Regler wirkt ueber den Bus).
func _music_db() -> float:
	if _music != null and _music.bus == "Music":
		return MUSIC_DB
	var st := get_node_or_null("/root/Settings")
	var v := 1.0
	if st != null:
		var raw = st.call("get_value", "audio/music", 1.0)
		v = clampf(float(raw) if raw != null else 1.0, 0.0, 1.0)
	if v <= 0.001:
		return -80.0
	return MUSIC_DB + linear_to_db(v * v)


func _sfx(kind: String) -> void:
	var path: String = SFX.get(kind, "")
	if path == "" or not ResourceLoader.exists(path) or _sfx_players.is_empty():
		return
	if not _sfx_cache.has(path):
		_sfx_cache[path] = load(path)
	var p: AudioStreamPlayer = null
	for q in _sfx_players:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _sfx_players[0]
	p.stream = _sfx_cache[path]
	p.volume_db = float(SFX_DB.get(kind, -18.0))
	p.pitch_scale = 1.15 if kind == "tick" else 1.0
	p.play()
