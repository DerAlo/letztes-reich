extends CanvasLayer
class_name StoryUI
## Story-Overlay: Funk-Untertitel (Warteschlange), Missionsziel oben links, Letterbox-Balken.
## Hoert auf Events.story_radio / story_objective / story_cinematic. Wird von main.gd instanziiert.
## Sprachausgabe: zu jeder Zeile wird res://assets/voice/<voice_id>.ogg abgespielt (falls vorhanden; erzeugt mit
## tools/gen_voice.py). Die Anzeigedauer verlaengert sich auf Audiolaenge + VOICE_TAIL. Fehlt die Datei: stumm wie bisher.

const SPEAKER_COLORS := {
	"Weber": Color(0.55, 0.78, 1.0),
	"Aksoy": Color(0.38, 0.92, 0.74),
	"Lena": Color(0.38, 0.92, 0.74),
	"Kerner": Color(1.0, 0.9, 0.42),
	"Riedhammer": Color(1.0, 0.64, 0.16),
	"Ordnungsfront": Color(1.0, 0.64, 0.16),
	"Lautsprecher": Color(1.0, 0.64, 0.16),
}
const DEFAULT_COLOR := Color(0.78, 0.8, 0.82)
const SFX_ON := "res://assets/sfx/story_radio_on.ogg"
const SFX_OFF := "res://assets/sfx/story_radio_off.ogg"
const SFX_TYPE := "res://assets/sfx/story_type.ogg"
const VOICE_DIR := "res://assets/voice/"
const VOICE_TAIL := 0.3
const VOICE_DB := 0.0

var _queue: Array = []
var _showing: bool = false
var _panel: PanelContainer
var _text: RichTextLabel
var _obj_box: VBoxContainer
var _obj_head: Label
var _obj_text: Label
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _audio: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _streams: Dictionary = {}
var _tween: Tween
var _cinematic: bool = false
var _clock: float = 0.0          # Spielzeit (pausiert mit, skaliert mit time_scale) fuer die Verzugs-Messung
var max_lag: float = 0.0         # groesster Verzug einer Zeile zwischen Signal und Anzeige (Diagnose)

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_PAUSABLE   # friert im Pausemenue mit ein
	add_to_group(&"story_ui")
	_build()
	Events.story_radio.connect(_on_radio)
	Events.story_objective.connect(_on_objective)
	Events.story_cinematic.connect(set_cinematic)
	_init_options()

# --- Optionen (Settings, Runde 6): Untertitel an/aus und Groesse. Stimmen laufen unabhaengig weiter.
func _init_options() -> void:
	var st := get_node_or_null("/root/Settings")
	if st == null:
		return
	_apply_options(st)
	st.connect("changed", func(_k: String, _v) -> void: _apply_options(st))

func _apply_options(st: Node) -> void:
	if not is_instance_valid(st) or _panel == null:
		return
	var on = st.call("get_value", "game/subtitles", true)
	_panel.visible = bool(on) if on != null else true
	var sz = st.call("get_value", "game/subtitle_size", 1.0)
	var k := clampf(float(sz) if sz != null else 1.0, 0.6, 2.0)
	var fs := roundi(21.0 * k)
	_text.add_theme_font_size_override("normal_font_size", fs)
	_text.add_theme_font_size_override("bold_font_size", fs)
	var w := roundf(824.0 * minf(k, 1.3))
	_text.custom_minimum_size = Vector2(w, 0)
	_panel.offset_left = -(w * 0.5 + 18.0)
	_panel.offset_right = w * 0.5 + 18.0

func _build() -> void:
	_bar_top = _bar(true)
	_bar_bot = _bar(false)
	# --- Untertitel unten mittig (ueber HUD-Leiste)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.03, 0.62)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -430
	_panel.offset_right = 430
	_panel.offset_top = -168
	_panel.offset_bottom = -104
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	add_child(_panel)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(824, 0)
	_text.add_theme_font_size_override("normal_font_size", 21)
	_text.add_theme_font_size_override("bold_font_size", 21)
	_text.add_theme_color_override("default_color", Color(0.95, 0.95, 0.93))
	_text.add_theme_constant_override("outline_size", 4)
	_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_text)
	# --- Missionsziel oben links
	_obj_box = VBoxContainer.new()
	_obj_box.position = Vector2(28, 26)
	_obj_box.add_theme_constant_override("separation", 2)
	_obj_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_obj_box.modulate.a = 0.0
	add_child(_obj_box)
	_obj_head = _label(14, Color(1.0, 0.72, 0.3))
	_obj_head.text = "AUFTRAG"
	_obj_text = _label(20, Color(0.95, 0.95, 0.92))
	_obj_text.custom_minimum_size = Vector2(460, 0)
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_box.add_child(_obj_head)
	_obj_box.add_child(_obj_text)
	_audio = AudioStreamPlayer.new()
	_audio.bus = "SFX"
	_audio.volume_db = -6.0
	add_child(_audio)
	_voice = AudioStreamPlayer.new()
	_voice.bus = voice_bus()
	_voice.volume_db = VOICE_DB
	add_child(_voice)

func _process(delta: float) -> void:
	_clock += delta

func _bar(top: bool) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.0 if top else 1.0
	r.anchor_bottom = 0.0 if top else 1.0
	r.offset_top = 0.0
	r.offset_bottom = 0.0
	add_child(r)
	return r

func _label(fs: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _sfx(path: String, vol: float = -6.0) -> void:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	if _streams[path] == null:
		return
	_audio.stream = _streams[path]
	_audio.volume_db = vol
	_audio.play()

static func speaker_color(speaker: String) -> Color:
	for k in SPEAKER_COLORS:
		if speaker.contains(k):
			return SPEAKER_COLORS[k]
	return DEFAULT_COLOR

## Stabile ID einer gesprochenen Zeile (identisch mit tools/voice_lines.py: sha1(speaker|text)[:12]).
static func voice_id(speaker: String, text: String) -> String:
	return (speaker + "|" + text).sha1_text().substr(0, 12)

## Vertonung einer Zeile laden (null, wenn es keine gibt).
static func voice_stream(speaker: String, text: String) -> AudioStream:
	if "--no-voice" in OS.get_cmdline_user_args():   # Diagnose: Timing ohne Sprachausgabe vergleichen
		return null
	var path := VOICE_DIR + voice_id(speaker, text) + ".ogg"
	return load(path) as AudioStream if ResourceLoader.exists(path) else null

## Eigener Bus "Voice" (mit Ducking von SFX/Ambient), sonst SFX.
static func voice_bus() -> StringName:
	return &"Voice" if AudioServer.get_bus_index("Voice") >= 0 else &"SFX"

static func auto_duration(text: String) -> float:
	return clampf(1.6 + 0.055 * text.length(), 2.5, 8.0)

# ---------------------------------------------------------------- Funk

func _on_radio(speaker: String, text: String, duration: float) -> void:
	_queue.append([speaker, text, duration if duration > 0.0 else auto_duration(text), _clock])
	if not _showing:
		_next()

func clear_queue() -> void:
	_queue.clear()
	if _voice != null:
		_voice.stop()

## Bricht laufende Zeile + Warteschlange ab (z. B. Explosion schneidet Rede/Geplauder ab).
## Aufruf aus Leveln: get_tree().call_group(&"story_ui", &"interrupt")
func interrupt() -> void:
	_queue.clear()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _voice != null:
		_voice.stop()
	_showing = false
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 0.0, 0.12)

func _next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var e: Array = _queue.pop_front()
	var speaker: String = e[0]
	var col := speaker_color(speaker).to_html(false)
	var body := str(e[1]).replace("[", "[lb]")
	_text.text = ("[b][color=#%s]%s:[/color][/b]  %s" % [col, speaker, body]) if speaker != "" else body
	var dur := float(e[2])
	var lag := _clock - float(e[3])
	if lag > max_lag:
		max_lag = lag
	if lag > 2.0 and OS.is_debug_build():
		print("[story] Funkzeile %.1f s verspaetet (Warteschlange %d): %s" % [lag, _queue.size(), str(e[1]).left(48)])
	var vs := voice_stream(speaker, str(e[1]))
	if vs != null:
		# Funk-Klick/Squelch bzw. Lautsprecher-Klang sind in der Datei enthalten -> keine UI-Klicks
		_voice.stream = vs
		_voice.play()
		dur = maxf(dur, vs.get_length() + VOICE_TAIL)
	else:
		_sfx(SFX_ON, -8.0)
	var tw := create_tween()
	_tween = tw
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18)
	tw.tween_interval(dur)
	if vs == null:
		tw.tween_callback(_sfx.bind(SFX_OFF, -10.0))
	tw.tween_property(_panel, "modulate:a", 0.0, 0.22)
	tw.tween_interval(0.25)
	tw.tween_callback(_next)

# ---------------------------------------------------------------- Ziel

func _on_objective(text: String) -> void:
	if text == "" and _obj_box.modulate.a <= 0.01:
		return   # nichts sichtbar, nichts zu tun (leerer Tween wuerde warnen)
	var tw := create_tween()
	if _obj_box.modulate.a > 0.01:
		tw.tween_property(_obj_box, "modulate:a", 0.0, 0.35)
	if text == "":
		return
	tw.tween_callback(func() -> void:
		_obj_text.text = text
		_obj_head.text = "NEUER AUFTRAG"
		_obj_box.position.x = 10.0
		_sfx(SFX_TYPE, -12.0))
	tw.set_parallel(true)
	tw.tween_property(_obj_box, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_obj_box, "position:x", 28.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(3.0)
	tw.chain().tween_callback(func() -> void: _obj_head.text = "AUFTRAG")

# ---------------------------------------------------------------- Letterbox

func set_cinematic(active: bool) -> void:
	if active == _cinematic:
		return
	_cinematic = active
	var h := get_viewport().get_visible_rect().size.y * 0.11 if active else 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_bar_top, "offset_bottom", h, 0.7)
	tw.tween_property(_bar_bot, "offset_top", -h, 0.7)
	tw.tween_property(_obj_box, "modulate:a", 0.0 if active else (1.0 if _obj_text.text != "" else 0.0), 0.5)
