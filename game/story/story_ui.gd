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
var _hroot: Control
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
var _obj_tw: Tween = null
var _clock: float = 0.0          # Spielzeit (pausiert mit, skaliert mit time_scale) fuer die Verzugs-Messung
var max_lag: float = 0.0         # groesster Verzug einer Zeile zwischen Signal und Anzeige (Diagnose)
var _cur: Array = []             # laufende Zeile (Eintrag wie in _queue), fuer Prioritaet/Unterbrechen
var _cur_end: float = 0.0        # _clock, zu dem die laufende Zeile ausgeblendet ist
var _log_radio: bool = "--log-radio" in OS.get_cmdline_user_args()   # Diagnose: Zeitstempel jeder Zeile
var _review: Node = null         # nur mit --review: game/debug/review.gd (radio.tsv)
## Gespraeche: Zeilen, die im selben Frame wie die vorige eingereiht werden, bilden eine Kette. Nur der Kopf steht
## in der Warteschlange; jede Folgezeile wird erst eingereiht, wenn ihre Vorgaengerin fertig (oder verworfen) ist.
## So schiebt sich eine Ereignis-Ansage zwischen zwei Gespraechszeilen, statt hinter dem ganzen Gespraech zu warten.
## Eintrag: [speaker, text, dur, t_queued, opts, folgezeile(Array oder []), durch(bool), t_born, resume_pos]
##   t_born     _clock beim say()-Aufruf (Alterung gegen Verhungern; t_queued wird bei Freigabe neu gesetzt)
##   resume_pos >0: unterbrochene Zeile, wird ab dieser Audioposition fortgesetzt
var _chain_frame: int = -1
var _chain_tail: Array = []
var _cutting: bool = false       # laufende Zeile blendet gerade wegen Abbruch/Unterbrechung aus
var _cur_t0: float = 0.0         # _clock beim Start der laufenden Zeile (Position ohne Sprachdatei)
var _force: Array = []           # Zeile, fuer die gerade unterbrochen wurde (cut/key): kommt als naechste dran

## --- Prioritaetsklassen (Funk-Timing, Runde voice3)
## kritisch  = Zeile mit max_age (Warnung, Rueckmeldung, Lage): geht vor, darf Erzaehlzeilen unterbrechen,
##             max_age mindestens CRIT_AGE (priority>=1: WARN_AGE), damit sie nicht knapp verfallen
## erzaehlt  = Zeile ohne max_age (Story, Anweisung): verfaellt nie, altert aber (AGE_STEP), damit sie nicht
##             hinter einem Strom hoeherer Prioritaet verhungert; unterbrochene Erzaehlzeilen werden fortgesetzt
## bark      = Feindfunk mit max_age (oder opts.bark): unterbricht nie, wird zuerst geopfert
const CRIT_AGE := 4.0
const WARN_AGE := 5.5
const AGE_STEP := 4.0            # Erzaehlzeile: +1 Rang (halbe Prioritaetsstufe) je AGE_STEP s Wartezeit
const LAG_CRIT := 2.0            # kritische Zeile unterbricht, wenn sie sonst spaeter als LAG_CRIT s startet
const LAG_STORY := 4.0           # hoeher priorisierte Erzaehlzeile unterbricht niedrigere ab LAG_STORY s Verzug
const RESUME_MIN := 1.5          # unterbrochene Erzaehlzeile mit mehr Rest wird fortgesetzt, sonst verworfen
const RESUME_BACK := 0.4         # beim Fortsetzen so viele s zurueckspringen (Wortanfang)
const RESUME_WAIT := 8.0         # unterbrochene Zeile, die so lange nicht wieder drankommt, verfaellt (Rest)
const BARK_SPEAKERS := ["Ordnungsfront-Funk", "Lautsprecher"]

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_PAUSABLE   # friert im Pausemenue mit ein
	add_to_group(&"story_ui")
	_review = get_node_or_null("/root/DebugServer/Review")
	_build()
	Events.story_radio.connect(_on_radio)
	Events.story_objective.connect(_on_objective)
	Events.story_cinematic.connect(set_cinematic)
	_init_options()

func _exit_tree() -> void:
	EnemyVoice.radio_active = false

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
	# Untertitel + Auftrag in 1080p-Pixeln unter einer skalierten Wurzel (kleine Fenster, z. B. 960x540)
	_hroot = UIStyle.HudRoot.new()
	add_child(_hroot)
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
	_hroot.add_child(_panel)
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
	_hroot.add_child(_obj_box)
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
	# Lage-Ansage mit "drop_live": erledigt sich die Lage waehrend sie laeuft, bricht sie ab
	if _showing and not _cutting and not _cur.is_empty() and bool(_opt(_cur, "drop_live", false)) and _clock < _cur_end - 0.9:
		var v: Variant = _opt(_cur, "valid", null)
		if v is Callable and not (v as Callable).is_null():
			var c := v as Callable
			if not c.is_valid() or not bool(c.call()):
				_log("cut", str(_cur[0]), str(_cur[1]))
				if _review != null:
					_review.call("radio_cut", _cur, "Lage erledigt (drop_live)")
				_release(_cur)
				_cur = []
				_cut_current()
	_check_preempt()

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
	say(speaker, text, duration, {})

## Haengt e an die Kette des aktuellen Frames (true) oder beginnt eine neue (false).
func _chain(e: Array) -> bool:
	var f := Engine.get_process_frames()
	var o: Dictionary = e[4]
	var chained := false
	if f == _chain_frame and _live(_chain_tail) and not bool(o.get("cut", false)) \
			and not bool(o.get("no_chain", false)) and int(o.get("priority", 0)) <= int(_opt(_chain_tail, "priority", 0)):
		_chain_tail[5] = e
		chained = true
	_chain_frame = f
	_chain_tail = e
	return chained

## Wartet e noch oder laeuft gerade (kann also noch eine Folgezeile freigeben)?
func _live(e: Array) -> bool:
	return e.size() > 6 and not bool(e[6])

## Folgezeile einer beendeten/verworfenen Zeile einreihen.
func _release(e: Array) -> void:
	if e.size() > 6:
		e[6] = true   # durch: kann keine weiteren Folgezeilen mehr aufnehmen
	if e.size() < 6 or not (e[5] is Array) or (e[5] as Array).is_empty():
		return
	var n: Array = e[5]
	e[5] = []
	n[3] = _clock   # faellig ab jetzt (Vorgaengerin ist durch)
	_insert(n, true)   # laufendes Gespraech geht vor wartende Zeilen gleicher Prioritaet

func _insert(e: Array, ahead_of_equal: bool = false) -> void:
	var pr := int(_opt(e, "priority", 0))
	var at := _queue.size()
	for i in _queue.size():
		var qp := int(_opt(_queue[i], "priority", 0))
		if qp < pr or (ahead_of_equal and qp == pr):
			at = i
			break
	_queue.insert(at, e)
	if _review != null:
		_review.call("radio_queued", e)
	_log("queue", str(e[0]), str(e[1]))

## Verwirft eine Zeile samt aller noch nicht eingereihten Folgezeilen (fuer die Review-Auswertung mitgezaehlt).
func _drop_chain_tail(e: Array, why: String) -> void:
	var n: Variant = e[5] if e.size() > 5 else []
	if e.size() > 5:
		e[5] = []
	if e.size() > 6:
		e[6] = true
	while n is Array and not (n as Array).is_empty():
		var a: Array = n
		a[6] = true
		if _review != null:
			_review.call("radio_queued", a)
			_review.call("radio_dropped", a, why)
		n = a[5]
		a[5] = []

## Erweiterte Funkzeile (optional; Events.story_radio bleibt unveraendert). Fuer ereignisgebundene Ansagen,
## die nicht verspaetet kommen duerfen. opts (alle optional):
##   max_age  float     Zeile verwerfen, wenn sie laenger als max_age s auf ihren Start gewartet hat
##   valid    Callable  -> bool, beim Start geprueft: false = Lage hat sich erledigt -> verwerfen
##   priority int       hoehere Prioritaet ueberholt wartende Zeilen niedrigerer Prioritaet (Standard 0)
##   cut      bool      bricht die laufende Zeile ab, wenn deren Prioritaet niedriger ist
##   key      String    ersetzt eine noch wartende Zeile mit gleichem key (keine doppelten Ansagen)
##   drop_live bool     wird valid waehrend der Wiedergabe false, bricht die Zeile ab
##   bark     bool      Geplauder (Feindfunk mit max_age gilt automatisch so): unterbricht nie, wird zuerst geopfert
##   strict_age bool    max_age exakt nehmen (sonst Untergrenze CRIT_AGE/WARN_AGE fuer kritische Zeilen)
## Klassen und Unterbrechen: siehe CRIT_AGE ff. oben. Eine neue Zeile mit gleichem key ersetzt auch die gerade
## laufende (ab 0.8 s Laufzeit).
## Aufruf aus Leveln: get_tree().call_group(&"story_ui", &"say", speaker, text, dur, opts)
func say(speaker: String, text: String, duration: float = 0.0, opts: Dictionary = {}) -> void:
	var e := [speaker, text, duration if duration > 0.0 else auto_duration(text), _clock, opts, [], false, _clock, 0.0]
	var key := str(opts.get("key", ""))
	var replace_cur := false
	if key != "":
		for i in range(_queue.size() - 1, -1, -1):
			if str(_opt(_queue[i], "key", "")) == key:
				var old: Array = _queue[i]
				if _review != null:
					_review.call("radio_dropped", old, "ersetzt (key)")
				_queue.remove_at(i)
				_release(old)
		replace_cur = _showing and not _cutting and not _cur.is_empty() and str(_opt(_cur, "key", "")) == key \
				and _clock - _cur_t0 > 0.8
	var pr := int(opts.get("priority", 0))
	if replace_cur:
		_insert(e)
		_force = e
		_preempt("ersetzt (key): " + text.left(40), false)
		return
	if _chain(e):
		return   # Folgezeile eines Gespraechs: wird eingereiht, sobald die Vorgaengerin durch ist
	_insert(e)
	if not _showing:
		_next()
	elif bool(opts.get("cut", false)) and not _cur.is_empty() and not _cutting and int(_opt(_cur, "priority", 0)) < pr:
		_force = e
		_preempt("Prioritaet: " + text.left(40))
	else:
		_check_preempt()

# ---------------------------------------------------------------- Prioritaetsklassen / Unterbrechen

static func _born(e: Array) -> float:
	return float(e[7]) if e.size() > 7 else float(e[3])

static func _resume_pos(e: Array) -> float:
	return float(e[8]) if e.size() > 8 else 0.0

## Feindfunk-Geplauder: unterbricht nie, wird bei Stau zuerst geopfert.
static func _is_bark(e: Array) -> bool:
	if bool(_opt(e, "bark", false)):
		return true
	return float(_opt(e, "max_age", -1.0)) >= 0.0 and str(e[0]) in BARK_SPEAKERS

## Zeitgebundene Zeile (Warnung/Rueckmeldung/Lage): hat max_age und ist kein Geplauder.
static func _is_crit(e: Array) -> bool:
	return float(_opt(e, "max_age", -1.0)) >= 0.0 and not _is_bark(e)

## Wirksames max_age: kritische Zeilen bekommen eine Untergrenze je Klasse (Warnung/Rueckmeldung).
static func _max_age(e: Array) -> float:
	var ma := float(_opt(e, "max_age", -1.0))
	if ma < 0.0 or _is_bark(e) or bool(_opt(e, "strict_age", false)):
		return ma
	return maxf(ma, WARN_AGE if int(_opt(e, "priority", 0)) >= 1 else CRIT_AGE)

## Rang fuer die Auswahl der naechsten Zeile: kritische vor Erzaehlzeilen (kurz, zeitgebunden), Erzaehlzeilen nach
## Prioritaet + Alterung, Geplauder zuletzt.
func _score(e: Array) -> float:
	var pr := float(int(_opt(e, "priority", 0)))
	if _is_bark(e):
		return pr * 2.0 - 100.0
	if _is_crit(e):
		return pr * 2.0 + 100.0
	# Alter = Wartezeit seit faellig. Die Zeit, die eine Folgezeile hinter ihrem Gespraech wartete, zaehlt
	# nur bis knapp unter eine Prioritaetsstufe (Gespraech bleibt in Reihenfolge, ueberholt aber keine
	# wichtigere neue Zeile). Rest einer unterbrochenen Zeile behaelt sein volles Alter.
	if _resume_pos(e) > 0.0:
		return pr * 2.0 + (_clock - _born(e)) / AGE_STEP
	var due := float(e[3])
	return pr * 2.0 + (_clock - due) / AGE_STEP + minf(maxf(0.0, due - _born(e)) / AGE_STEP, 1.9)

## Darf c die (laufende oder als naechste gewaehlte) Zeile u unterbrechen?
func _may_preempt(c: Array, u: Array) -> bool:
	if _is_bark(c):
		return false
	if _is_bark(u):
		return true
	var pc := int(_opt(c, "priority", 0))
	var pu := int(_opt(u, "priority", 0))
	if _is_crit(c):
		return pc > pu or (pc == pu and not _is_crit(u))
	if _is_crit(u):
		return pc > pu + 1   # kurze Lagezeile ist gleich durch; Erzaehlung wartet (ausser deutlich wichtiger)
	# Erzaehlzeile gegen Erzaehlzeile: hoehere Prioritaet, aber eine lange verdraengte (gealterte) Zeile bleibt dran
	return pc > pu and _score(c) > _score(u)

## Ab welchem Verzug c unterbrechen darf.
func _lag_limit(c: Array) -> float:
	return LAG_CRIT if _is_crit(c) else LAG_STORY

## Restdauer einer (noch nicht laufenden) Zeile.
static func _left_dur(e: Array) -> float:
	return maxf(0.5, float(e[2]) - _resume_pos(e))

## Index der naechsten Zeile: bester Rang (Gleichstand: die aeltere); wuerde eine andere wartende Zeile die
## gewaehlte sofort unterbrechen, kommt gleich diese dran (kein Anspielen und Abwuergen).
func _pick() -> int:
	var best := 0
	var bs := -INF
	for i in _queue.size():
		var s := _score(_queue[i])
		if s > bs + 0.001 or (absf(s - bs) <= 0.001 and _born(_queue[i]) < _born(_queue[best])):
			best = i
			bs = s
	var b: Array = _queue[best]
	var alt := -1
	for i in _queue.size():
		if i == best:
			continue
		var c: Array = _queue[i]
		if _may_preempt(c, b) and (_clock - float(c[3])) + _left_dur(b) > _lag_limit(c):
			if alt < 0 or _score(c) > _score(_queue[alt]):
				alt = i
	return alt if alt >= 0 else best

## Laufende Zeile unterbrechen, wenn eine wartende Zeile sonst zu spaet kaeme.
func _check_preempt() -> void:
	if not _showing or _cur.is_empty() or _cutting or _queue.is_empty():
		return
	var left := _cur_end - _clock
	if left < 0.8:
		return   # ist ohnehin gleich durch
	var c: Array = _queue[_pick()]
	if not _may_preempt(c, _cur):
		return
	if (_clock - float(c[3])) + left <= _lag_limit(c):
		return
	if _stale(c):
		return   # wird ohnehin verworfen
	_preempt("unterbrochen fuer: " + str(c[1]).left(40))

## Laufende Zeile abbrechen; Erzaehlzeilen mit genug Rest kommen danach ab der Abbruchstelle wieder.
func _preempt(why: String, allow_resume: bool = true) -> void:
	if _cur.is_empty() or _cutting:
		return
	var u := _cur
	var left := _cur_end - 0.65 - _clock
	if allow_resume and not _is_crit(u) and not _is_bark(u) and left > RESUME_MIN:
		var pos := _resume_pos(u) + maxf(0.0, _clock - _cur_t0 - 0.18)
		if _voice != null and _voice.playing:
			pos = _voice.get_playback_position()
		u[8] = maxf(0.01, pos - RESUME_BACK)
		u[3] = _clock   # ab jetzt zaehlt die Wartezeit bis zur Fortsetzung (RESUME_WAIT)
		if _review != null:
			_review.call("radio_cut", u, why + " -> wird fortgesetzt")
		_log("pause", str(u[0]), str(u[1]), "(@%.1f s) " % float(u[8]))
		_queue.insert(0, u)   # Folgezeilen bleiben an u haengen
		_cur = []
	else:
		if _review != null:
			_review.call("radio_cut", u, why)
		_log("cut", str(u[0]), str(u[1]))
	_cut_current()

## Geschaetzte Restzeit, bis Laufendes + Warteschlange gesprochen sind (Levels warten darauf statt fester Pausen).
func busy_left() -> float:
	var t := maxf(0.0, _cur_end - _clock) if _showing else 0.0
	if _showing and not _cur.is_empty():
		t += _chain_len(_cur)
	for e: Array in _queue:
		t += _left_dur(e) + 0.65 + _chain_len(e)
	return t

## Geschaetzte Dauer der noch nicht eingereihten Folgezeilen von e.
static func _chain_len(e: Array) -> float:
	var t := 0.0
	var n: Variant = e[5] if e.size() > 5 else []
	while n is Array and not (n as Array).is_empty():
		t += float(n[2]) + 0.65
		n = n[5]
	return t

static func _opt(e: Array, k: String, def: Variant) -> Variant:
	if e.size() > 4 and e[4] is Dictionary:
		return (e[4] as Dictionary).get(k, def)
	return def

## Ist eine wartende Zeile ueberholt (zu alt oder Lage erledigt)?
func _stale(e: Array) -> bool:
	if _resume_pos(e) > 0.0:
		return _clock - float(e[3]) > RESUME_WAIT or not _valid_ok(e)
	var ma := _max_age(e)
	if ma >= 0.0 and _clock - float(e[3]) > ma:
		return true
	return not _valid_ok(e)

## valid-Callable der Zeile (fehlt sie: true).
static func _valid_ok(e: Array) -> bool:
	var v: Variant = _opt(e, "valid", null)
	if v is Callable and not (v as Callable).is_null():
		var c := v as Callable
		if not c.is_valid() or not bool(c.call()):
			return false
	return true

func _cut_current() -> void:
	_cutting = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _voice != null:
		_voice.stop()
	_cur_end = _clock + 0.1
	var tw := create_tween()
	_tween = tw
	tw.tween_property(_panel, "modulate:a", 0.0, 0.1)
	tw.tween_callback(_next)

func _log(what: String, speaker: String, text: String, extra: String = "") -> void:
	if _log_radio:
		print("[radio] %7.2f %-5s %s%s: %s" % [_clock, what, extra, speaker, text.left(60)])

func clear_queue() -> void:
	_review_drop_all("clear_queue")
	_queue.clear()
	_chain_tail = []
	if _voice != null:
		_voice.stop()
	EnemyVoice.radio_active = false

## Bricht laufende Zeile + Warteschlange ab (z. B. Explosion schneidet Rede/Geplauder ab).
## Aufruf aus Leveln: get_tree().call_group(&"story_ui", &"interrupt")
func interrupt() -> void:
	_review_drop_all("interrupt")
	_queue.clear()
	_cur = []
	_chain_tail = []
	_cutting = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _voice != null:
		_voice.stop()
	_showing = false
	EnemyVoice.radio_active = false
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 0.0, 0.12)

func _review_drop_all(why: String) -> void:
	for q: Array in _queue:
		if _review != null:
			_review.call("radio_dropped", q, why)
		_drop_chain_tail(q, why)
	if not _cur.is_empty():
		if _showing and _review != null:
			_review.call("radio_cut", _cur, why)
		_drop_chain_tail(_cur, why)

## Ueberholte Zeilen (zu alt / Lage erledigt) aus der ganzen Warteschlange werfen; deren Folgezeilen ruecken nach.
func _purge() -> void:
	var guard := 0
	while guard < 64:
		guard += 1
		var hit := -1
		for i in _queue.size():
			if _stale(_queue[i]):
				hit = i
				break
		if hit < 0:
			return
		var d: Array = _queue[hit]
		_queue.remove_at(hit)
		_log("drop", str(d[0]), str(d[1]), "(%.1f s alt) " % (_clock - float(d[3])))
		if _review != null:
			var ma := _max_age(d)
			var why := ("max_age %.1f s" % ma) if ma >= 0.0 and _clock - float(d[3]) > ma else "valid=false"
			if _resume_pos(d) > 0.0:
				why = "Rest nach Unterbrechung verfallen" if _valid_ok(d) else "Rest: valid=false"
			_review.call("radio_dropped", d, why)
		_release_after_drop(d)

## Verworfene Zeile: kurze Reaktionen darauf (Folgezeilen mit max_age <= WARN_AGE) entfallen mit,
## die erste Folgezeile ohne max_age (Erzaehlung) rueckt nach. Auf einen verworfenen Bark folgt die Zeile
## trotzdem (der Bark ist nur Kulisse, die Reaktion traegt die Information).
func _release_after_drop(d: Array) -> void:
	var guard := 0
	while guard < 16 and not _is_bark(d) and d.size() > 5 and d[5] is Array and not (d[5] as Array).is_empty():
		guard += 1
		var n: Array = d[5]
		var nma := float(_opt(n, "max_age", -1.0))
		if nma < 0.0 or nma > WARN_AGE:
			break
		d[5] = []
		d[6] = true
		_log("drop", str(n[0]), str(n[1]), "(Reaktion auf verworfene Zeile) ")
		if _review != null:
			_review.call("radio_queued", n)
			_review.call("radio_dropped", n, "Vorgaengerzeile verworfen")
		d = n
	_release(d)

func _next() -> void:
	_cutting = false
	if not _cur.is_empty():
		_release(_cur)   # Gespraech: Folgezeile der eben beendeten Zeile ist jetzt dran
		_cur = []
	_purge()
	if _queue.is_empty():
		_showing = false
		_cur = []
		EnemyVoice.radio_active = false
		return
	EnemyVoice.radio_active = true
	_showing = true
	var e: Array = _queue[_pick()]
	if not _force.is_empty() and _queue.has(_force):
		e = _force
	_force = []
	_queue.erase(e)
	_cur = e
	var rpos := _resume_pos(e)
	var speaker: String = e[0]
	var col := speaker_color(speaker).to_html(false)
	var body := str(e[1]).replace("[", "[lb]")
	_text.text = ("[b][color=#%s]%s:[/color][/b]  %s" % [col, speaker, body]) if speaker != "" else body
	var dur := float(e[2])
	var lag := _clock - float(e[3])
	if rpos <= 0.0:
		if lag > max_lag:
			max_lag = lag
		if lag > 2.0 and OS.is_debug_build():
			print("[story] Funkzeile %.1f s verspaetet (Warteschlange %d): %s" % [lag, _queue.size(), str(e[1]).left(48)])
	var vs := voice_stream(speaker, str(e[1]))
	if vs != null:
		# Funk-Klick/Squelch bzw. Lautsprecher-Klang sind in der Datei enthalten -> keine UI-Klicks
		_voice.stream = vs
		var vlen := vs.get_length()
		if rpos > 0.0 and rpos < vlen - 0.3:
			_voice.play(rpos)
			dur = maxf(0.6, vlen - rpos + VOICE_TAIL)
		else:
			_voice.play()
			dur = maxf(dur, vlen + VOICE_TAIL)
	else:
		_sfx(SFX_ON, -8.0)
		if rpos > 0.0:
			dur = maxf(0.6, dur - rpos)
	_cur_t0 = _clock
	_cur_end = _clock + dur + 0.65
	if _review != null:
		if rpos > 0.0 and _review.has_method("radio_resume"):
			_review.call("radio_resume", e, dur)
		elif rpos <= 0.0:
			_review.call("radio_play", e, dur)
	_log("play" if rpos <= 0.0 else "resum", speaker, str(e[1]), "(+%.1f s) " % lag)
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
	if _obj_tw != null and _obj_tw.is_valid():
		_obj_tw.kill()
	if text == "":
		_obj_text.text = ""   # sonst blendet set_cinematic(false) den alten Auftrag wieder ein
	elif _cinematic:
		_obj_text.text = text   # waehrend Zwischensequenzen nur merken, Einblenden nach set_cinematic(false)
		_obj_head.text = "AUFTRAG"
		return
	if text == "" and _obj_box.modulate.a <= 0.01:
		return   # nichts sichtbar, nichts zu tun (leerer Tween wuerde warnen)
	var tw := create_tween()
	_obj_tw = tw
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
	if _obj_tw != null and _obj_tw.is_valid():
		_obj_tw.kill()
	var h := get_viewport().get_visible_rect().size.y * 0.11 if active else 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_bar_top, "offset_bottom", h, 0.7)
	tw.tween_property(_bar_bot, "offset_top", -h, 0.7)
	tw.tween_property(_obj_box, "modulate:a", 0.0 if active else (1.0 if _obj_text.text != "" else 0.0), 0.5)
	# Kinoformat: Untertitel in den unteren schwarzen Balken (nicht halbtransparent ueber dem Bild);
	# ausserhalb wieder ueber der HUD-Leiste. Mehrzeilig waechst das Panel nach oben (grow BEGIN).
	var hv := h / maxf((_hroot as UIStyle.HudRoot).factor, 0.01)   # Balkenhoehe in HUD-Einheiten (Panel liegt unter _hroot)
	var pb := -maxf(6.0, hv * 0.5 - 22.0) if active else -104.0
	tw.tween_property(_panel, "offset_bottom", pb, 0.7)
	tw.tween_property(_panel, "offset_top", pb - (44.0 if active else 64.0), 0.7)
	var psb := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if psb != null:
		tw.tween_property(psb, "bg_color:a", 0.0 if active else 0.62, 0.5)
