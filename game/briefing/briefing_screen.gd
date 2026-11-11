extends CanvasLayer
## Briefing mit taktischer Karte (Welle 4, systeme-b). Ersetzt fuer Level mit Eintrag in BriefingMaps die reine
## Texttafel: links die Karte (BriefingMap), rechts der getippte Lagebericht + Legende; Sprecher "Lage" wie bisher.
## main.gd: var s = Screen.new(); add_child(s); await s.run(level, text, TITLES[level])
## Spiel ist waehrenddessen pausiert (main setzt paused/_in_briefing). Ueberspringen: Leertaste/Enter/Esc/Klick.

const BriefingMaps = preload("res://game/briefing/briefing_maps.gd")
const BriefingMap = preload("res://game/briefing/briefing_map.gd")
const SFX_TYPE := "res://assets/sfx/story_type.ogg"
const SFX_MARK := "res://assets/sfx/intro_tick.wav"
const VOICE_SPEAKER := "Lage"
const MIN_TIME := 8.0

signal finished

var _root: Control
var _frame: Control
var _map: Control
var _text: Label
var _clock: Label
var _hint: Label
var _legend: VBoxContainer
var _sfx: AudioStreamPlayer
var _sfx2: AudioStreamPlayer
var _vo: AudioStreamPlayer
var _skip: bool = false
var _t: float = 0.0


func _ready() -> void:
	layer = 91
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bus := &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = bus
	add_child(_sfx)
	_sfx2 = AudioStreamPlayer.new()
	_sfx2.bus = bus
	add_child(_sfx2)
	_vo = AudioStreamPlayer.new()
	_vo.bus = StoryUI.voice_bus()
	add_child(_vo)


static func available(level: String) -> bool:
	return BriefingMaps.has_map(level)


func _play(p: AudioStreamPlayer, path: String, db: float) -> void:
	if ResourceLoader.exists(path):
		p.stream = load(path)
		p.volume_db = db
		p.play()


func _input(event: InputEvent) -> void:
	if _t < 0.25:
		return
	var key := event as InputEventKey
	if (key != null and key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		_skip = true
		get_viewport().set_input_as_handled()


## Laeuft bis Stimme/Text fertig oder uebersprungen; blendet sich selbst aus und gibt sich frei.
## max_override > 0 begrenzt die Dauer (Smoke-Tests).
func run(level: String, text: String, title: Array, max_override: float = -1.0) -> void:
	var map: Dictionary = BriefingMaps.get_map(level)
	_build(map, title)
	_map.call("setup", map, text)
	_text.text = text
	_text.visible_characters = 0
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.45)
	var n := text.length()
	var type_time := clampf(n / 40.0, 4.0, 14.0)
	var max_time := maxf(MIN_TIME, 0.7 + type_time + 2.4)
	var vs := StoryUI.voice_stream(VOICE_SPEAKER, text)
	var voice_started := vs == null
	if vs != null:
		var vl := vs.get_length()
		type_time = maxf(minf(type_time, vl), vl * 0.9)
		max_time = maxf(MIN_TIME, maxf(0.6 + vl + 0.9, 0.7 + type_time + 1.6))
		_vo.stream = vs
	if max_override > 0.0:
		max_time = max_override
		type_time = minf(type_time, max_override * 0.6)
	var last_click := 0
	while not _skip:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		_t += get_process_delta_time()
		if not voice_started and _t >= 0.6:
			voice_started = true
			_vo.play()
		var shown := clampi(int((_t - 0.7) / type_time * n), 0, n)
		_text.visible_characters = shown
		if shown - last_click >= 3 and shown < n:
			last_click = shown
			_play(_sfx, SFX_TYPE, -20.0)
		if int(_map.call("set_progress", shown)) > 0:
			_play(_sfx2, SFX_MARK, -22.0)
		_update_legend()
		_hint.modulate.a = clampf((_t - 0.8) / 0.5, 0.0, 0.8)
		_clock.text = "T+%02d:%02d" % [int(_t) / 60, int(_t) % 60]
		if _t >= max_time:
			break
	_text.visible_characters = -1
	_map.call("reveal_all")
	if _vo.playing:
		var vt := create_tween()
		vt.tween_property(_vo, "volume_db", -40.0, 0.25)
	var out := create_tween()
	out.tween_property(_root, "modulate:a", 0.0, 0.35)
	await out.finished
	finished.emit()
	queue_free()


# ------------------------------------------------------------------ Aufbau

func _build(map: Dictionary, title: Array) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	var t0 := str(title[0]) if title.size() > 0 else ""
	var t1 := str(title[1]) if title.size() > 1 else ""
	var t2 := str(title[2]) if title.size() > 2 else ""
	_place(UIStyle.label("LAGEBESPRECHUNG  ·  VS – NUR FÜR DEN DIENSTGEBRAUCH", 15, UIStyle.C_AMBER, 700, true), Vector2(60, 40))
	_place(UIStyle.label(t1 if t1 != "" else t0, 46, UIStyle.C_TEXT, 700), Vector2(60, 62))
	_place(UIStyle.label((t0 + "   ·   " if t0 != "" and t1 != "" else "") + t2.replace("\n", "  ·  "), 20, UIStyle.C_DIM),
			Vector2(62, 122))
	_clock = UIStyle.label("T+00:00", 15, UIStyle.C_MUTED, 600, true)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_clock, Vector2(1560, 40), Vector2(300, 20))

	_map = BriefingMap.new()
	_map.position = Vector2(60, 168)
	_map.size = Vector2(1180, 840)
	_frame.add_child(_map)

	var col_x := 1290.0
	var col_w := 570.0
	_place(UIStyle.label("LAGE", 15, UIStyle.C_AMBER, 700, true), Vector2(col_x, 168))
	var hl := UIStyle.hline(UIStyle.C_LINE_HI)
	_place(hl, Vector2(col_x, 194), Vector2(col_w, 1))
	_text = UIStyle.label("", 24, UIStyle.C_TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_place(_text, Vector2(col_x, 210), Vector2(col_w, 520))
	_text.clip_text = false

	_place(UIStyle.label("LEGENDE", 15, UIStyle.C_AMBER, 700, true), Vector2(col_x, 776))
	_place(UIStyle.hline(UIStyle.C_LINE_HI), Vector2(col_x, 802), Vector2(col_w, 1))
	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override("separation", 2)
	_place(_legend, Vector2(col_x, 812), Vector2(col_w, 190))
	_build_legend(map)

	_hint = UIStyle.label("LEERTASTE / ENTER   ÜBERSPRINGEN", 15, UIStyle.C_MUTED, 600, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate.a = 0.0
	_place(_hint, Vector2(1360, 1030), Vector2(500, 20))


func _place(c: Control, pos: Vector2, sz: Vector2 = Vector2.ZERO) -> void:
	c.position = pos
	if sz != Vector2.ZERO:
		c.size = sz
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(c)


const LEGEND_NAMES := {
	"friend": "Eigene / verbündete Kräfte", "enemy": "Feind", "objective": "Auftrag / Ziel",
	"hvt": "Zielperson", "neutral": "Neutral / Zivil", "charge": "Sprengladung", "hostage": "Geisel",
	"route": "Marschweg",
}
var _legend_rows: Dictionary = {}   # kind -> Control (erscheint, sobald ein Symbol dieser Art auf der Karte ist)


func _build_legend(map: Dictionary) -> void:
	var kinds: Array[String] = []
	for c in map.get("cues", []):
		var cd: Dictionary = c
		var k: String = "route" if cd.get("t", "") == "arrow" and cd.get("k", "") == "route" else str(cd.get("k", ""))
		if cd.get("t", "") == "zone" or cd.get("t", "") == "line":
			continue
		if LEGEND_NAMES.has(k) and not kinds.has(k):
			kinds.append(k)
	for k in kinds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var icon := _LegendIcon.new()
		icon.kind = k
		icon.custom_minimum_size = Vector2(48, 30)
		row.add_child(icon)
		var l := UIStyle.label(str(LEGEND_NAMES[k]), 18, UIStyle.C_DIM)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		row.modulate.a = 0.25
		_legend.add_child(row)
		_legend_rows[k] = row


func _update_legend() -> void:
	# Legendenzeile hellt auf, sobald ihr erstes Symbol auf der Karte erschienen ist.
	var lit: Dictionary = _map.call("revealed_kinds")
	for k in _legend_rows:
		var row: Control = _legend_rows[k]
		row.modulate.a = move_toward(row.modulate.a, 1.0 if lit.has(k) else 0.25, 0.05)


func _layout() -> void:
	if _frame != null:
		UIStyle.fit(_frame, get_viewport().get_visible_rect().size)


class _LegendIcon extends Control:
	var kind: String = ""
	var _t: float = 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var mid := size * 0.5
		if kind == "route":
			draw_line(Vector2(4, mid.y), Vector2(size.x - 12, mid.y), BriefingMap.COL_OBJ, 4.0)
			draw_colored_polygon(PackedVector2Array([Vector2(size.x - 2, mid.y), Vector2(size.x - 14, mid.y - 8),
					Vector2(size.x - 14, mid.y + 8)]), BriefingMap.COL_OBJ)
		else:
			BriefingMap.draw_symbol(self, kind, mid, 0.85, 1.0, _t)
