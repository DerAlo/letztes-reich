extends Node
## Einstiegspunkt und Level-Abfolge (Kampagne).
## --level=<name> laedt ein Level direkt. Ohne Arg (und ohne --autopilot): optional Intro (game/intro/intro.tscn),
## dann das erste Level der Liste. --intro erzwingt das Intro auch mit --level.
## Titelkarte mit Briefing (Schreibmaschine, Leertaste ueberspringt; aus unter --autopilot/--debug-server/--no-briefing).
## Bei Events.level_completed: Abblende, naechstes vorhandenes Level (fehlende werden uebersprungen);
## nach dem letzten Level (berlin) Endsequenz "Fortsetzung folgt".
## Das Level bleibt direktes Kind von Main (Autopilot/Tools suchen es dort).

const LEVELS: Array[String] = ["baltic_night", "test_range", "river_crossing", "rail_yard", "berlin"]
const TITLES := {
	"baltic_night": ["Nacht an der Grenze", "Grenze Lettland–Russland", "14. März 2030, 03:40"],
	"test_range": ["Kriegsstraße", "Daugavpils, Lettland", "14. März 2030, 07:15"],
	"river_crossing": ["Die Brücke", "Fluss Welikaja bei Pskow", "22. März 2030, 05:50"],
	"rail_yard": ["Letzter Zug", "Güterbahnhof Pskow", "2. April 2030, 19:20"],
	"berlin": ["Das letzte Reich", "Berlin, Regierungsviertel", "1. Juni 2030, 22:10"],
}
const INTRO_PATH := "res://game/intro/intro.tscn"
const STORY_UI_PATH := "res://game/story/story_ui.gd"
const STORY_DIRECTOR_PATH := "res://game/story/story_director.gd"
const SFX_TYPE := "res://assets/sfx/story_type.ogg"
const SFX_DRONE := "res://assets/sfx/story_drone.ogg"
const BRIEFING_MAX := 8.0        # Sekunden gesamt (Tippen + Lesen)

var _level: Node = null
var _level_name: String = ""
var _ui: CanvasLayer
var _black: ColorRect
var _title: Label
var _sub: Label
var _brief: Label
var _hint: Label
var _audio: AudioStreamPlayer
var _busy: bool = false
var _skip: bool = false
var _in_briefing: bool = false

func _ready() -> void:
	# Main laeuft immer (Briefing bei pausiertem Baum); das Level wird explizit PAUSABLE gesetzt.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if ResourceLoader.exists(STORY_UI_PATH):
		var sui: Node = (load(STORY_UI_PATH) as GDScript).new()
		sui.name = "StoryUI"
		add_child(sui)
	Events.level_completed.connect(_on_level_completed)
	var has_level := Game.arg("level", null) != null
	var want_intro: bool = bool(Game.arg("intro", false)) or (not has_level and not bool(Game.arg("autopilot", false)))
	if want_intro and ResourceLoader.exists(INTRO_PATH):
		await _play_intro()
	var level_name: String = str(Game.arg("level", "")) if has_level else _first_existing(0)
	_load_level(level_name)

## Kampagnen-Intro (anderer Agent): Wurzel mit signal finished, ueberspringt sich selbst.
func _play_intro() -> void:
	var intro: Node = (load(INTRO_PATH) as PackedScene).instantiate()
	if not intro.has_signal("finished"):
		push_warning("[main] intro.tscn ohne Signal 'finished' – uebersprungen")
		intro.free()
		return
	add_child(intro)
	print("[main] Intro laeuft")
	await intro.finished
	if is_instance_valid(intro):
		intro.queue_free()
	_black.color.a = 1.0

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 90
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_black)
	_title = _make_label(40, 0.5, -28.0)
	_sub = _make_label(22, 0.5, 26.0)
	_brief = _make_label(19, 0.5, 150.0)
	_brief.anchor_left = 0.5
	_brief.anchor_right = 0.5
	_brief.offset_left = -440.0
	_brief.offset_right = 440.0
	_brief.offset_bottom = _brief.offset_top + 140.0
	_brief.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief.add_theme_color_override("font_color", Color(0.78, 0.8, 0.78))
	_hint = _make_label(14, 1.0, -40.0)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.58))
	_hint.text = "[Leertaste] überspringen"
	_audio = AudioStreamPlayer.new()
	_audio.bus = "SFX"
	add_child(_audio)

func _make_label(font_size: int, anchor_y: float, offset_y: float) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = anchor_y
	l.anchor_bottom = anchor_y
	l.offset_top = offset_y - 30.0
	l.offset_bottom = offset_y + 30.0
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.92, 0.92, 0.9))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(l)
	return l

func _play(path: String, vol: float) -> void:
	if not ResourceLoader.exists(path):
		return
	_audio.stream = load(path)
	_audio.volume_db = vol
	_audio.play()

func _level_path(level_name: String) -> String:
	return "res://game/levels/%s.tscn" % level_name

## Erstes vorhandenes Level ab Index i ("" wenn keins mehr). Noch nicht gebaute Level werden uebersprungen.
func _first_existing(i: int) -> String:
	while i < LEVELS.size():
		if ResourceLoader.exists(_level_path(LEVELS[i])):
			return LEVELS[i]
		print("[main] Level fehlt noch, uebersprungen: " + LEVELS[i])
		i += 1
	return ""

func _load_level(level_name: String) -> void:
	var path := _level_path(level_name)
	if not ResourceLoader.exists(path):
		push_error("Level nicht gefunden: " + path)
		return
	_level_name = level_name
	_level = (load(path) as PackedScene).instantiate()
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_level)
	var lvl := _level
	var briefed: bool = await _show_title_card(level_name)
	if lvl != _level or not is_instance_valid(lvl):
		return
	if ResourceLoader.exists(STORY_DIRECTOR_PATH) and StoryData.SCRIPTS.has(level_name):
		var dir: Node = (load(STORY_DIRECTOR_PATH) as GDScript).new()
		dir.name = "StoryDirector"
		lvl.add_child(dir)
		dir.call("setup", level_name, 2.4 if briefed else 3.2)
	# Debug: --teleport-end=<s> setzt den Spieler nach s Sekunden in den LevelEnd-Trigger
	var tp := float(Game.arg("teleport-end", -1.0))
	if tp >= 0.0:
		_debug_teleport_end(tp)

func _debug_teleport_end(delay: float) -> void:
	await get_tree().create_timer(delay, false).timeout
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var end := get_tree().get_first_node_in_group("level_end") as Node3D
	if pl == null or end == null:
		push_warning("[main] teleport-end: player/level_end fehlt")
		return
	print("[main] teleport-end -> " + str(end.global_position))
	pl.global_position = end.global_position + Vector3(0, -0.8, 0)

## Kein Briefing (und keine Pause) fuer Bots/Tools: der DebugServer steuert die Pause selbst.
func _briefing_allowed() -> bool:
	for a in ["autopilot", "debug-server", "no-briefing", "start-paused"]:
		if Game.arg(a, false):
			return false
	return true

## Titelkarte beim Levelstart: Ort/Zeit (+ Briefing bei pausiertem Spiel), dann Aufblende.
## Gibt true zurueck, wenn ein Briefing lief.
func _show_title_card(level_name: String) -> bool:
	var t: Array = TITLES.get(level_name, [level_name, "", ""])
	_title.text = str(t[1])
	_sub.text = str(t[2]) + ("\n" + str(t[0]) if str(t[0]) != "" else "")
	_black.color.a = 1.0
	var text: String = StoryData.BRIEFINGS.get(level_name, "")
	var briefed := text != "" and _briefing_allowed()
	if briefed:
		await _run_briefing(text)
	var tw := _ui.create_tween()
	tw.set_parallel(true)
	if briefed:
		tw.tween_property(_black, "color:a", 0.0, 1.6)
		tw.tween_property(_brief, "modulate:a", 0.0, 0.6)
		tw.tween_property(_title, "modulate:a", 0.0, 1.0).set_delay(0.6)
		tw.tween_property(_sub, "modulate:a", 0.0, 1.0).set_delay(0.6)
		return true
	tw.tween_property(_black, "color:a", 0.0, 2.2).set_delay(0.4)
	tw.tween_property(_title, "modulate:a", 1.0, 0.8).set_delay(0.3)
	tw.tween_property(_sub, "modulate:a", 1.0, 0.8).set_delay(0.7)
	tw.chain().tween_interval(1.6)
	tw.chain().set_parallel(true)
	tw.tween_property(_title, "modulate:a", 0.0, 1.0)
	tw.tween_property(_sub, "modulate:a", 0.0, 1.0)
	return false

## Lagebericht im Schreibmaschinenstil, insgesamt max. BRIEFING_MAX s; das Spiel ist so lange pausiert.
func _run_briefing(text: String) -> void:
	var tree := get_tree()
	tree.paused = true
	_in_briefing = true
	_skip = false
	_brief.text = text
	_brief.visible_characters = 0
	_brief.modulate.a = 1.0
	var tw := _ui.create_tween().set_parallel(true)
	tw.tween_property(_title, "modulate:a", 1.0, 0.5)
	tw.tween_property(_sub, "modulate:a", 1.0, 0.5).set_delay(0.25)
	tw.tween_property(_hint, "modulate:a", 0.8, 0.5).set_delay(0.8)
	var n := text.length()
	var type_time := minf(n / 52.0, BRIEFING_MAX - 2.6)
	var start := Time.get_ticks_msec() / 1000.0
	var last_click := 0
	while not _skip:
		await tree.process_frame
		var el := Time.get_ticks_msec() / 1000.0 - start
		var shown := clampi(int((el - 0.7) / type_time * n), 0, n)
		_brief.visible_characters = shown
		if shown - last_click >= 3 and shown < n:
			last_click = shown
			_play(SFX_TYPE, -20.0)
		if el >= BRIEFING_MAX:
			break
	tw.kill()
	_title.modulate.a = 1.0
	_sub.modulate.a = 1.0
	_brief.visible_characters = -1
	_hint.modulate.a = 0.0
	_in_briefing = false
	tree.paused = false

func _unhandled_input(event: InputEvent) -> void:
	if not _in_briefing:
		return
	var key := event as InputEventKey
	if (key != null and key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]) \
			or (event is InputEventMouseButton and event.pressed):
		_skip = true
		get_viewport().set_input_as_handled()

func _next_level_name() -> String:
	var i := LEVELS.find(_level_name)
	if i < 0:
		return ""
	return _first_existing(i + 1)

func _free_level() -> void:
	if _level != null and is_instance_valid(_level):
		_level.process_mode = Node.PROCESS_MODE_DISABLED
		remove_child(_level)
		_level.queue_free()
		_level = null
	Events.story_objective.emit("")
	Events.story_cinematic.emit(false)
	var sui := get_node_or_null("StoryUI")
	if sui != null:
		sui.call("clear_queue")

func _fade_labels(a: float, d: float, labels: Array) -> void:
	var tw := _ui.create_tween().set_parallel(true)
	for l in labels:
		tw.tween_property(l, "modulate:a", a, d)
	await tw.finished

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _on_level_completed() -> void:
	if _busy:
		return
	# Autopilot/Simulation werten das Levelende selbst aus und beenden Godot.
	if Game.arg("autopilot", false):
		return
	_busy = true
	var nxt := _next_level_name()
	var tw := _ui.create_tween()
	tw.tween_property(_black, "color:a", 1.0, 1.2)
	await tw.finished
	if nxt == "" and _level_name == "berlin":
		_free_level()
		await _ending_sequence()
		return
	_title.text = "Abschnitt abgeschlossen"
	_sub.text = ("Nächster Einsatz: " + str(TITLES.get(nxt, [nxt])[0])) if nxt != "" else ""
	await _fade_labels(1.0, 0.6, [_title, _sub])
	_free_level()
	await _wait(2.2)
	if nxt == "":
		_title.text = "Ende des Prototyps"
		_sub.text = "Danke fürs Spielen."
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		print("[main] Ende des Prototyps")
		return
	await _fade_labels(0.0, 0.5, [_title, _sub])
	print("[main] lade naechstes Level: " + nxt)
	_busy = false
	_load_level(nxt)

## Cliffhanger nach Berlin: Texttafeln auf Schwarz, dann "Fortsetzung folgt".
func _ending_sequence() -> void:
	print("[main] Endsequenz")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play(SFX_DRONE, -4.0)
	_title.modulate.a = 0.0
	_sub.modulate.a = 0.0
	await _wait(1.0)
	_brief.offset_top = -80.0
	_brief.offset_bottom = 80.0
	_brief.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_brief.add_theme_font_size_override("font_size", 24)
	_brief.add_theme_color_override("font_color", Color(0.86, 0.86, 0.84))
	for card in StoryData.ENDING:
		_brief.text = str(card[0])
		_brief.visible_characters = -1
		await _fade_labels(1.0, 0.9, [_brief])
		await _wait(float(card[1]))
		await _fade_labels(0.0, 0.8, [_brief])
		if not _audio.playing:
			_play(SFX_DRONE, -8.0)
	await _wait(0.8)
	_title.text = "Fortsetzung folgt"
	_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25))
	_sub.text = "Kampagne „Nord“ – Ende von Teil 1"
	await _fade_labels(1.0, 1.6, [_title])
	await _fade_labels(1.0, 1.0, [_sub])
	print("[main] Fortsetzung folgt")
