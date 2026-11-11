extends CanvasLayer
## Abschluss-Bildschirm nach einem Level (Welle 4, systeme-a): Zeit, Genauigkeit, Kopfschuesse, Sterne mit Animation.
## main.gd: var scr = ResultsScreen.new(); add_child(scr); await scr.run(result, info)
## Kurz (max. AUTO_CONTINUE s), mit Leertaste/Enter/Klick ueberspringbar. Unter --autopilot wird er nie angelegt.

const StarIcon = preload("res://game/progress/star_icon.gd")
const Progress = preload("res://game/progress/progress.gd")
const Difficulty = preload("res://game/progress/difficulty.gd")
const AUTO_CONTINUE := 9.0
const SKIP_DELAY := 0.5
const SFX_STAR := "res://assets/sfx/intro_beep.wav"
const SFX_TICK := "res://assets/sfx/intro_tick.wav"

signal closed

var _root: Control
var _frame: Control
var _bar: ColorRect
var _stars: Array = []
var _skip: bool = false
var _t0: int = 0
var _audio: AudioStreamPlayer


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	add_child(_audio)


func _sfx(path: String, db: float, pitch: float = 1.0) -> void:
	if not ResourceLoader.exists(path):
		return
	_audio.stream = load(path)
	_audio.volume_db = db
	_audio.pitch_scale = pitch
	_audio.play()


func _tw() -> Tween:
	var t := create_tween()
	t.set_ignore_time_scale(true)
	return t


## res = Progress.record(...), info = main.get_mission_info()
func run(res: Dictionary, info: Dictionary) -> void:
	_build(res, info)
	_t0 = Time.get_ticks_msec()
	_root.modulate.a = 0.0
	var tw := _tw()
	tw.tween_property(_root, "modulate:a", 1.0, 0.35)
	# Sterne nacheinander
	var ev: Array = res.get("stars", [false, false, false])
	var prev := int(res.get("prev_mask", 0))
	for i in 3:
		var at := 0.7 + 0.45 * i
		_pop_star(i, bool(ev[i]), ((prev >> i) & 1) == 1, at)
	var tree := get_tree()
	while not _skip:
		await tree.process_frame
		var el := (Time.get_ticks_msec() - _t0) / 1000.0
		_bar.scale.x = clampf(el / AUTO_CONTINUE, 0.0, 1.0)
		if el >= AUTO_CONTINUE:
			break
	var out := _tw()
	out.tween_property(_root, "modulate:a", 0.0, 0.3)
	await out.finished
	closed.emit()
	queue_free()


func _pop_star(i: int, on: bool, had: bool, delay: float) -> void:
	var s: Control = _stars[i]["icon"]
	var lab: Label = _stars[i]["label"]
	var tag: Label = _stars[i]["tag"]
	var tw := _tw()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		s.call("set_filled", on)
		s.scale = Vector2(0.3, 0.3) if on else Vector2.ONE
		lab.add_theme_color_override("font_color", UIStyle.C_TEXT if on else UIStyle.C_MUTED)
		tag.text = ("NEU" if on and not had else ("ERREICHT" if on else ("BEREITS ERREICHT" if had else "VERFEHLT")))
		tag.add_theme_color_override("font_color", UIStyle.C_AMBER if on and not had else (UIStyle.C_GREEN if on or had else UIStyle.C_MUTED))
		if on:
			_sfx(SFX_STAR, -14.0, 1.0 + 0.12 * i)
		else:
			_sfx(SFX_TICK, -20.0))
	if on:
		tw.tween_property(s, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(func(g: float) -> void: s.call("set_glow", g), 1.0, 0.0, 0.9)
	tw.parallel().tween_property(tag, "modulate:a", 1.0, 0.25)


func _input(event: InputEvent) -> void:
	var press: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if not press or _root == null:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if (Time.get_ticks_msec() - _t0) / 1000.0 < SKIP_DELAY:
		return
	if key == null or key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_E]:
		_skip = true


# ------------------------------------------------------------------ Aufbau

func _build(res: Dictionary, info: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIStyle.theme()
	add_child(_root)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)
	get_viewport().size_changed.connect(_layout)
	_layout()

	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(k, 260)
	m.add_theme_constant_override("margin_top", 150)
	m.add_theme_constant_override("margin_bottom", 120)
	_frame.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)

	var s: Dictionary = res.get("stats", {})
	var idx := int(info.get("index", -1))
	v.add_child(UIStyle.label("EINSATZ %s ABGESCHLOSSEN" % ("%02d" % (idx + 1) if idx >= 0 else ""), 16, UIStyle.C_AMBER, 700, true))
	v.add_child(UIStyle.label(str(info.get("title", "")), 60, UIStyle.C_TEXT, 700))
	var place := str(info.get("place", ""))
	var date := str(info.get("date", ""))
	v.add_child(UIStyle.label(place + ("   ·   " + date if date != "" else ""), 22, UIStyle.C_DIM, 500))
	var g0 := Control.new()
	g0.custom_minimum_size = Vector2(0, 18)
	v.add_child(g0)
	v.add_child(UIStyle.hline(UIStyle.C_LINE_HI))
	var g1 := Control.new()
	g1.custom_minimum_size = Vector2(0, 30)
	v.add_child(g1)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 80)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	# Links: Einsatzprotokoll
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	left.add_child(UIStyle.label("EINSATZPROTOKOLL", 15, UIStyle.C_AMBER, 700, true))
	left.add_child(UIStyle.hline())
	var t := float(s.get("time", 0.0))
	var goal_t := float(res.get("time_goal", 0.0))
	var best := float(res.get("prev_best", -1.0))
	var time_txt := Progress.clock(t)
	if bool(res.get("new_best", false)) and best >= 0.0:
		time_txt += "   NEUE BESTZEIT"
	elif best >= 0.0:
		time_txt += "   (Bestzeit %s)" % Progress.clock(best)
	var shots := int(s.get("shots", 0))
	var kills := int(s.get("kills", 0))
	var hs := int(s.get("headshot_kills", 0))
	var rows := [
		["EINSATZZEIT", time_txt, t <= goal_t and goal_t > 0.0],
		["ZIELZEIT", Progress.clock(goal_t), false],
		["GENAUIGKEIT", ("%d %%   (%d / %d)" % [roundi(float(s.get("accuracy", 0.0)) * 100.0), int(s.get("hits", 0)), shots]) if shots > 0 else "—", false],
		["KOPFSCHÜSSE", ("%d   (%d %% der Abschüsse)" % [hs, roundi(100.0 * hs / float(kills))]) if kills > 0 else "—", false],
		["ABSCHÜSSE", str(kills), false],
		["AUSFÄLLE", str(int(s.get("deaths", 0))), false],
		["SCHWIERIGKEIT", Difficulty.display_name(str(s.get("difficulty", "soldier"))), false],
	]
	for r in rows:
		var h := HBoxContainer.new()
		var k := UIStyle.label(str(r[0]), 15, UIStyle.C_MUTED, 600, true)
		k.custom_minimum_size = Vector2(200, 0)
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(k)
		h.add_child(UIStyle.label(str(r[1]), 24, UIStyle.C_AMBER if bool(r[2]) else UIStyle.C_TEXT, 600))
		left.add_child(h)

	# Rechts: Sterne
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	right.add_child(UIStyle.label("AUSZEICHNUNGEN", 15, UIStyle.C_AMBER, 700, true))
	right.add_child(UIStyle.hline())
	var texts := ["Mission abgeschlossen", str(res.get("time_text", "")), str(res.get("challenge_text", ""))]
	for i in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 26)
		row.custom_minimum_size = Vector2(0, 84)
		right.add_child(row)
		var holder := CenterContainer.new()
		holder.custom_minimum_size = Vector2(76, 76)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(holder)
		var icon: Control = StarIcon.new()
		icon.call("setup", 60.0, false)
		holder.add_child(icon)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		var lab := UIStyle.label(str(texts[i]), 26, UIStyle.C_DIM, 600)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(lab)
		var tag := UIStyle.label("", 14, UIStyle.C_MUTED, 700, true)
		tag.modulate.a = 0.0
		col.add_child(tag)
		_stars.append({"icon": icon, "label": lab, "tag": tag})
	var best_mask := int(res.get("best_mask", 0))
	var g2 := Control.new()
	g2.custom_minimum_size = Vector2(0, 8)
	right.add_child(g2)
	right.add_child(UIStyle.label("BESTWERT DIESER MISSION: %d / 3 STERNE" % Progress.popcount(best_mask), 15, UIStyle.C_MUTED, 600, true))

	# Fuss
	v.add_child(UIStyle.hline())
	var foot := HBoxContainer.new()
	foot.custom_minimum_size = Vector2(0, 40)
	v.add_child(foot)
	var note := UIStyle.label("" if Progress.save_path() != "" else "Testlauf – Fortschritt wird nicht gespeichert.", 17, UIStyle.C_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	foot.add_child(note)
	var hint := UIStyle.label("LEERTASTE  WEITER", 15, UIStyle.C_MUTED, 600, true)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	foot.add_child(hint)
	_bar = ColorRect.new()
	_bar.color = Color(UIStyle.C_AMBER, 0.5)
	_bar.custom_minimum_size = Vector2(0, 2)
	_bar.scale.x = 0.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_bar)


func _layout() -> void:
	if _frame != null:
		UIStyle.fit(_frame, get_viewport().get_visible_rect().size)
