extends CanvasLayer
## Schwierigkeitswahl beim Start einer neuen Kampagne (Welle 4, systeme-a).
## main.gd zeigt sie nach dem Intro, solange "game/difficulty" noch nie gesetzt wurde (erster Kampagnenstart);
## danach aenderbar im Pausenmenue unter Einstellungen > Spiel. Nie unter --autopilot/Tools.
## var p = Picker.new(); add_child(p); await p.run()  -> setzt Settings "game/difficulty".

const Difficulty = preload("res://game/progress/difficulty.gd")
const SFX_MOVE := "res://assets/sfx/intro_tick.wav"
const SFX_OK := "res://assets/sfx/intro_beep.wav"

signal chosen(id: String)

var _root: Control
var _frame: Control
var _desc: Label
var _buttons: Array[Button] = []
var _done: bool = false
var _audio: AudioStreamPlayer


func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	add_child(_audio)


func _sfx(path: String, db: float) -> void:
	if ResourceLoader.exists(path):
		_audio.stream = load(path)
		_audio.volume_db = db
		_audio.play()


func run() -> String:
	var prev_mouse := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.4)
	_buttons[1].grab_focus()
	var id: String = await chosen
	Difficulty.set_current(id)
	var out := create_tween()
	out.tween_property(_root, "modulate:a", 0.0, 0.35)
	await out.finished
	Input.mouse_mode = prev_mouse
	queue_free()
	return id


func _pick(id: String) -> void:
	if _done:
		return
	_done = true
	_sfx(SFX_OK, -16.0)
	chosen.emit(id)


func _build() -> void:
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
		m.add_theme_constant_override(k, 420)
	m.add_theme_constant_override("margin_top", 230)
	m.add_theme_constant_override("margin_bottom", 160)
	_frame.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	v.add_child(UIStyle.label("NEUE KAMPAGNE", 16, UIStyle.C_AMBER, 700, true))
	v.add_child(UIStyle.label("Schwierigkeitsgrad", 56, UIStyle.C_TEXT, 700))
	v.add_child(UIStyle.label("Jederzeit änderbar unter Einstellungen › Spiel.", 21, UIStyle.C_DIM))
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, 22)
	v.add_child(g)
	v.add_child(UIStyle.hline(UIStyle.C_LINE_HI))
	var g2 := Control.new()
	g2.custom_minimum_size = Vector2(0, 16)
	v.add_child(g2)
	for i in Difficulty.IDS.size():
		var id: String = Difficulty.IDS[i]
		var b := Button.new()
		b.text = "%02d    %s" % [i + 1, Difficulty.display_name(id).to_upper()]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 66)
		b.add_theme_font_override("font", UIStyle.font(700))
		b.add_theme_font_size_override("font_size", 30)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(_pick.bind(id))
		b.focus_entered.connect(func() -> void:
			_desc.text = str(Difficulty.DESCRIPTIONS.get(id, ""))
			_sfx(SFX_MOVE, -24.0))
		b.mouse_entered.connect(func() -> void:
			if not b.has_focus():
				b.grab_focus())
		v.add_child(b)
		_buttons.append(b)
	var g3 := Control.new()
	g3.custom_minimum_size = Vector2(0, 18)
	v.add_child(g3)
	v.add_child(UIStyle.hline())
	_desc = UIStyle.label("", 22, UIStyle.C_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(0, 70)
	v.add_child(_desc)
	v.add_child(UIStyle.label("↑↓  AUSWAHL     ENTER  BESTÄTIGEN", 15, UIStyle.C_MUTED, 600, true))


func _layout() -> void:
	if _frame != null:
		UIStyle.fit(_frame, get_viewport().get_visible_rect().size)
