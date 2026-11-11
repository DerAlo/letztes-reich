extends Node
## Einstiegspunkt und Level-Abfolge (Kampagne).
## --level=<name> laedt ein Level direkt. Ohne Arg (und ohne --autopilot): optional Intro (game/intro/intro.tscn),
## dann das erste Level der Liste. --intro erzwingt das Intro auch mit --level.
## Titelkarte mit Briefing (Schreibmaschine, Leertaste ueberspringt; aus unter --autopilot/--debug-server/--no-briefing).
## Bei Events.level_completed: Abblende, naechstes vorhandenes Level (fehlende werden uebersprungen);
## Akt-Enden (StoryData.ACT_ENDINGS, z. B. nach berlin): Texttafeln, dann Zwischentitel und weiter mit Teil 2;
## nach dem letzten Akt "Fortsetzung folgt".
## Das Level bleibt direktes Kind von Main (Autopilot/Tools suchen es dort).

const LEVELS: Array[String] = ["baltic_night", "test_range", "river_crossing", "rail_yard", "berlin",
	"curfew", "overwatch", "gunship",
	"hafen", "alpenpass", "nachtzug", "villa",
	"spreebogen", "funkturm", "kanalisation", "kanzleramt", "bunker"]
const TITLES := {
	"baltic_night": ["Nacht an der Grenze", "Grenze Lettland–Russland", "14. März 2030, 03:40"],
	"test_range": ["Kriegsstraße", "Daugavpils, Lettland", "14. März 2030, 07:15"],
	"river_crossing": ["Die Brücke", "Fluss Welikaja bei Pskow", "22. März 2030, 05:50"],
	"rail_yard": ["Letzter Zug", "Güterbahnhof Pskow", "2. April 2030, 19:20"],
	"berlin": ["Das letzte Reich", "Berlin, Regierungsviertel", "1. Juni 2030, 22:10"],
	"curfew": ["Ausgangssperre", "Berlin-Mitte, besetzt", "3. Juni 2030, 01:40"],
	"overwatch": ["Kaltes Auge", "Stahlwerk Hennigsdorf, nördlich von Berlin", "6. Juni 2030, 05:20"],
	"gunship": ["Wächter", "Über dem Fliegerhorst Lindenau, Brandenburg", "9. Juni 2030, 02:30"],
	"hafen": ["Kräne", "Überseehafen Rostock", "12. Juni 2030, 23:10"],
	"alpenpass": ["Weißes Rauschen", "Grenzpass bei Mittenwald", "15. Juni 2030, 06:30"],
	"nachtzug": ["Nachtzug", "Nachtzug Innsbruck–Wien", "16. Juni 2030, 22:40"],
	"villa": ["Das Haus am See", "Villa am Traunsee, Österreich", "18. Juni 2030, 20:15"],
	"spreebogen": ["Spreebogen", "Berlin-Moabit, Belagerungsring", "24. Juni 2030, 05:10"],
	"funkturm": ["Stimme der Ordnung", "Funkturm, Berlin-Charlottenburg", "24. Juni 2030, 21:40"],
	"kanalisation": ["Unter dem Reichstag", "Kanalisation, Berlin-Tiergarten", "25. Juni 2030, 01:50"],
	"kanzleramt": ["Geiseln", "Kanzleramt, Berlin", "25. Juni 2030, 03:20"],
	"bunker": ["Letztes Gefecht", "Regierungsbunker unter dem Spreebogen", "25. Juni 2030, 04:40"],
}
## Sterne pro Level (Welle 4, game/progress/): 1 = abgeschlossen, 2 = Zeit <= "time" (Sekunden Einsatzzeit ohne
## Pause/Briefing), 3 = Herausforderung (Typen siehe game/progress/progress.gd). Zielzeiten grob aus telemetry/run_*.json
## (Bot "average", Median) plus Luft fuer menschliche Spieler; nachtzug/villa ohne Daten geschaetzt.
const STAR_GOALS := {
	"baltic_night": {"time": 150, "challenge": "headshots", "value": 0.3},
	"test_range": {"time": 150, "challenge": "no_deaths"},
	"river_crossing": {"time": 165, "challenge": "accuracy", "value": 0.4},
	"rail_yard": {"time": 180, "challenge": "no_deaths"},
	"berlin": {"time": 180, "challenge": "headshots", "value": 0.25},
	"curfew": {"time": 270, "challenge": "undetected"},
	"overwatch": {"time": 270, "challenge": "accuracy", "value": 0.6},
	"gunship": {"time": 390, "challenge": "no_deaths"},
	"hafen": {"time": 330, "challenge": "prop_zero", "prop": "_weber_hits", "label": "Weber nie getroffen"},
	"alpenpass": {"time": 360, "challenge": "no_deaths"},
	"nachtzug": {"time": 330, "challenge": "headshots", "value": 0.25},
	"villa": {"time": 390, "challenge": "no_deaths"},
	"spreebogen": {"time": 330, "challenge": "no_deaths"},
	"funkturm": {"time": 450, "challenge": "headshots", "value": 0.25},
	"kanalisation": {"time": 390, "challenge": "undetected"},
	"kanzleramt": {"time": 150, "challenge": "no_hostage_loss"},
	"bunker": {"time": 330, "challenge": "accuracy", "value": 0.4},
}
const Progress = preload("res://game/progress/progress.gd")
const Difficulty = preload("res://game/progress/difficulty.gd")
const RunTracker = preload("res://game/progress/run_tracker.gd")
const ResultsScreen = preload("res://game/progress/results_screen.gd")
const DifficultyPicker = preload("res://game/progress/difficulty_picker.gd")
const BriefingScreen = preload("res://game/briefing/briefing_screen.gd")   # Welle 4: Briefing-Karte
const Loadout = preload("res://game/loadout/loadout.gd")                    # Welle 4: Ausruestungswahl
const LoadoutScreen = preload("res://game/loadout/loadout_screen.gd")
const Episodes = preload("res://game/episodes/episodes.gd")             # Welle 5: Bonus-Episoden
const INTRO_PATH := "res://game/intro/intro.tscn"
const STORY_UI_PATH := "res://game/story/story_ui.gd"
const STORY_DIRECTOR_PATH := "res://game/story/story_director.gd"
const SFX_TYPE := "res://assets/sfx/story_type.ogg"
const SFX_DRONE := "res://assets/sfx/story_drone.ogg"
const BRIEFING_MAX := 8.0        # Sekunden gesamt (Tippen + Lesen); mit Sprecher bis Stimme fertig
## Vertonung (tools/gen_voice.py): res://assets/voice/<sha1(speaker|text)[:12]>.ogg, wie StoryUI.voice_id().
const VOICE_BRIEFING := "Lage"   # Sprecher-Schluessel der Lageberichte (Funk, Stabsoffizier)
const VOICE_ENDING := "Kerner"   # Endtafeln = Kerners innerer Monolog

var _level: Node = null
var _level_name: String = ""
var _ui: CanvasLayer
var _black: ColorRect
var _title: Label
var _sub: Label
var _brief: Label
var _hint: Label
var _audio: AudioStreamPlayer
var _vo: AudioStreamPlayer
var _busy: bool = false
var _skip: bool = false
var _in_briefing: bool = false
var _tracker: Node = null          ## game/progress/run_tracker.gd des laufenden Levels
var _episode: bool = false         ## Welle 5: laufendes Level ist eine Bonus-Episode (kein Kampagnenfortschritt)
var _campaign_level: String = ""   ## zuletzt gespielte Kampagnenmission (Ruecksprung nach einer Episode)

func _ready() -> void:
	# Main laeuft immer (Briefing bei pausiertem Baum); das Level wird explizit PAUSABLE gesetzt.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if ResourceLoader.exists(STORY_UI_PATH):
		var sui: Node = (load(STORY_UI_PATH) as GDScript).new()
		sui.name = "StoryUI"
		add_child(sui)
	_add_pause_menu()
	Events.level_completed.connect(_on_level_completed)
	var has_level := Game.arg("level", null) != null
	var want_intro: bool = bool(Game.arg("intro", false)) or (not has_level and not bool(Game.arg("autopilot", false)))
	if want_intro and ResourceLoader.exists(INTRO_PATH):
		await _play_intro()
	if not has_level and _briefing_allowed():
		await _maybe_pick_difficulty()
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
	_vo = AudioStreamPlayer.new()
	_vo.bus = &"Voice" if AudioServer.get_bus_index("Voice") >= 0 else &"SFX"
	add_child(_vo)

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

## Gesprochene Fassung eines Textes (null, wenn nicht vertont).
func _voice_stream(speaker: String, text: String) -> AudioStream:
	return StoryUI.voice_stream(speaker, text)

func _stop_voice(fade: float = 0.25) -> void:
	if not _vo.playing:
		return
	var tw := create_tween()
	tw.tween_property(_vo, "volume_db", -40.0, fade)
	tw.tween_callback(func() -> void:
		_vo.stop()
		_vo.volume_db = 0.0)

func _level_path(level_name: String) -> String:
	if Episodes.available(level_name):
		return str(Episodes.find(level_name)["scene"])
	return "res://game/levels/%s.tscn" % level_name

## Welle 5: Titelzeile/Sternziel fuer Kampagnenmissionen (TITLES/STAR_GOALS) und Episoden (episodes.gd).
func _titles_of(level_name: String) -> Array:
	if Episodes.is_episode(level_name):
		return Episodes.title_of(level_name)
	return TITLES.get(level_name, [level_name, "", ""])

func _goal_of(level_name: String) -> Dictionary:
	if Episodes.is_episode(level_name):
		return Episodes.goal_of(level_name)
	return STAR_GOALS.get(level_name, {})

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
	_episode = Episodes.is_episode(level_name)
	if not _episode:
		_campaign_level = level_name
		_mark_unlocked(level_name)
	_level = (load(path) as PackedScene).instantiate()
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_level)
	_start_tracker(level_name)
	var lvl := _level
	var briefed: bool = await _show_title_card(level_name)
	if lvl != _level or not is_instance_valid(lvl):
		return
	_apply_loadout(level_name)
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
	var t: Array = _titles_of(level_name)
	_title.text = str(t[1])
	_sub.text = str(t[2]) + ("\n" + str(t[0]) if str(t[0]) != "" else "")
	_black.color.a = 1.0
	var text: String = StoryData.BRIEFINGS.get(level_name, "")
	var briefed := text != "" and _briefing_allowed() and not _skip_brief_once
	_skip_brief_once = false
	if briefed:
		if not await _run_map_briefing(level_name, text):
			await _run_briefing(text)
		await _run_loadout(level_name)
	var tw := _ui.create_tween()
	_title_tw = tw
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

## Welle 4: Briefing mit taktischer Karte (game/briefing), falls fuer das Level ein Karteneintrag existiert.
## Gibt false zurueck, wenn nicht -> altes Text-Briefing. Pausiert wie _run_briefing.
func _run_map_briefing(level_name: String, text: String) -> bool:
	if not BriefingScreen.available(level_name):
		return false
	var tree := get_tree()
	tree.paused = true
	_in_briefing = true
	var scr := BriefingScreen.new()
	add_child(scr)
	await scr.run(level_name, text, _titles_of(level_name))
	_in_briefing = false
	tree.paused = false
	return true

## Welle 4: Ausruestungswahl nach dem Briefing (nur freie Level, nie unter Bots/Tools). Spiel bleibt pausiert.
func _run_loadout(level_name: String) -> void:
	if not Loadout.choice_allowed(level_name):
		return
	var tree := get_tree()
	tree.paused = true
	_in_briefing = true
	var scr := LoadoutScreen.new()
	add_child(scr)
	await scr.run(level_name, LEVELS, unlocked_levels(), TITLES)
	_in_briefing = false
	tree.paused = false

## Welle 4: gespeicherte/gewaehlte Ausruestung auf den Spieler anwenden (Default -> nichts aendern).
func _apply_loadout(level_name: String) -> void:
	var choice: Dictionary = Loadout.effective_choice(level_name, LEVELS, unlocked_levels())
	if choice == Loadout.DEFAULT:
		return
	# Der Spieler spawnt erst, wenn das Navmesh steht (level.gd wartet Physikframes) -> kurz auf ihn warten.
	var lvl := _level
	for i in 600:
		if lvl != _level or not is_instance_valid(lvl):
			return
		var pl := get_tree().get_first_node_in_group("player")
		if pl != null and lvl.is_ancestor_of(pl) and not (pl.get("weapons") as Array).is_empty():
			Loadout.apply(pl, choice)
			return
		await get_tree().process_frame

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
	var max_time := BRIEFING_MAX
	var vs := _voice_stream(VOICE_BRIEFING, text)
	var voice_started := vs == null
	if vs != null:
		# Sprecher liest den Lagebericht: Tippen folgt ungefaehr der Stimme, Karte bleibt bis zum Ende stehen
		var vl := vs.get_length()
		max_time = maxf(BRIEFING_MAX, 0.6 + vl + 0.9)
		type_time = maxf(type_time, vl * 0.9)
		_vo.stream = vs
		_vo.volume_db = 0.0
	var start := Time.get_ticks_msec() / 1000.0
	var last_click := 0
	while not _skip:
		await tree.process_frame
		var el := Time.get_ticks_msec() / 1000.0 - start
		if not voice_started and el >= 0.6:
			voice_started = true
			_vo.play()
		var shown := clampi(int((el - 0.7) / type_time * n), 0, n)
		_brief.visible_characters = shown
		if shown - last_click >= 3 and shown < n:
			last_click = shown
			_play(SFX_TYPE, -20.0)
		if el >= max_time:
			break
	tw.kill()
	_stop_voice()
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
	var res := _record_progress()
	# Autopilot/Simulation werten das Levelende selbst aus und beenden Godot.
	if Game.arg("autopilot", false):
		return
	_busy = true
	if _episode:
		await _finish_episode(res)
		return
	var nxt := _next_level_name()
	var tw := _ui.create_tween()
	tw.tween_property(_black, "color:a", 1.0, 1.2)
	await tw.finished
	await _show_results(res)
	if StoryData.ACT_ENDINGS.has(_level_name):
		_free_level()
		await _ending_sequence(_act_variant(StoryData.ACT_ENDINGS[_level_name]), nxt)
		if nxt == "":
			await _back_to_menu()
			return
		_busy = false
		_load_level(nxt)
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
		await _back_to_menu()
		return
	await _fade_labels(0.0, 0.5, [_title, _sub])
	print("[main] lade naechstes Level: " + nxt)
	_busy = false
	_load_level(nxt)

## Akt-Ende: Texttafeln auf Schwarz (act.cards), dann Zwischentitel des naechsten Teils (act.next_title/next_sub)
## oder, wenn kein Level mehr folgt, "Fortsetzung folgt" (act.end_sub).
## Akt-Ende mit Varianten (z. B. bunker: "variant_key" = Settings-Schluessel, "variants" = {wert: karten}).
## Ohne gespeicherten/bekannten Wert bleiben die Standardkarten ("cards").
func _act_variant(act: Dictionary) -> Dictionary:
	if not act.has("variant_key"):
		return act
	var st := get_node_or_null("/root/Settings")
	var v := str(st.call("get_value", str(act["variant_key"]), "")) if st != null else ""
	var vars: Dictionary = act.get("variants", {})
	print("[main] Endsequenz Variante: %s" % (v if vars.has(v) else "standard"))
	if not vars.has(v):
		return act
	var out := act.duplicate()
	out["cards"] = vars[v]
	print("[main] Endkarten: %d, letzte: %s" % [(vars[v] as Array).size(), str((vars[v] as Array).back()[0]).left(60)])
	return out

func _ending_sequence(act: Dictionary, nxt: String) -> void:
	print("[main] Endsequenz")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play(SFX_DRONE, -4.0)
	_title.modulate.a = 0.0
	_sub.modulate.a = 0.0
	await _wait(1.0)
	var keep := [_brief.offset_top, _brief.offset_bottom, _brief.vertical_alignment]
	_brief.offset_top = -80.0
	_brief.offset_bottom = 80.0
	_brief.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_brief.add_theme_font_size_override("font_size", 24)
	_brief.add_theme_color_override("font_color", Color(0.86, 0.86, 0.84))
	for card in act.get("cards", []):
		_brief.text = str(card[0])
		_brief.visible_characters = -1
		var hold := float(card[1])
		var vs := _voice_stream(VOICE_ENDING, str(card[0]))
		if vs != null:
			_vo.stream = vs
			_vo.volume_db = 0.0
			_vo.play()
			hold = maxf(hold, vs.get_length() - 0.9 + 0.5)   # nach dem Einblenden (0,9 s) ausreden lassen
		await _fade_labels(1.0, 0.9, [_brief])
		await _wait(hold)
		await _fade_labels(0.0, 0.8, [_brief])
		if not _audio.playing:
			_play(SFX_DRONE, -8.0)
	await _wait(0.8)
	_brief.text = ""
	_brief.offset_top = keep[0]
	_brief.offset_bottom = keep[1]
	_brief.vertical_alignment = keep[2]
	_brief.remove_theme_font_size_override("font_size")
	_brief.add_theme_color_override("font_color", Color(0.78, 0.8, 0.78))
	if nxt != "":
		_title.text = str(act.get("next_title", ""))
		_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25))
		_sub.text = str(act.get("next_sub", ""))
		await _fade_labels(1.0, 1.4, [_title])
		await _fade_labels(1.0, 1.0, [_sub])
		await _wait(2.6)
		await _fade_labels(0.0, 0.8, [_title, _sub])
		_title.remove_theme_color_override("font_color")
		_audio.stop()
		print("[main] Akt-Ende -> " + nxt)
		return
	# Kampagnen-Ende (bunker): "Ende" + Abspann statt "Fortsetzung folgt"
	_title.text = str(act.get("end_title", "Fortsetzung folgt"))
	_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25))
	_sub.text = str(act.get("end_sub", ""))
	await _fade_labels(1.0, 1.6, [_title])
	await _fade_labels(1.0, 1.0, [_sub])
	print("[main] " + _title.text)
	if bool(act.get("credits", false)):
		await _wait(3.0)
		await _fade_labels(0.0, 1.0, [_title, _sub])
		await (load("res://game/ui/credits.gd") as GDScript).play(self)
		_title.text = "Danke fürs Spielen."
		_sub.text = ""
		await _fade_labels(1.0, 1.2, [_title])

## Kampagne ganz durch (nach Abspann): zurueck ins Menue statt auf Schwarz stehen zu bleiben.
## Es gibt kein eigenes Hauptmenue -> erste Mission still laden und das Pausenmenue darueber oeffnen
## (Missionen, Episoden, Einstellungen, Beenden).
func _back_to_menu() -> void:
	await _wait(3.0)
	await _fade_labels(0.0, 1.0, [_title, _sub])
	_busy = false
	_skip_brief_once = true
	var first := _first_existing(0)
	print("[main] Kampagne beendet -> Menue (" + first + ")")
	_load_level(first)
	var pm := get_node_or_null("PauseMenu")
	if pm == null or not pm.has_method("open"):
		return
	for i in 60:
		await _wait(0.25)
		if can_pause():
			pm.call("open")
			return

# ================================================================== Pausenmenue-Schnittstelle (Runde 6)
## game/ui/pause_menu.gd ruft diese Funktionen; nie aktiv unter --autopilot/--debug-server.
const PAUSE_MENU_PATH := "res://game/ui/pause_menu.gd"
var _skip_brief_once: bool = false
var _title_tw: Tween

func _add_pause_menu() -> void:
	if Game.arg("autopilot", false) or Game.arg("debug-server", false):
		return
	if not ResourceLoader.exists(PAUSE_MENU_PATH):
		return
	var pm: Node = (load(PAUSE_MENU_PATH) as GDScript).new()
	pm.name = "PauseMenu"
	add_child(pm)

## Pause nur im laufenden Level: nicht waehrend Briefing, Intro, Levelwechsel/Abspann oder fremder Pause.
func can_pause() -> bool:
	return not _in_briefing and not _busy and _level != null and is_instance_valid(_level) 		and _level.is_inside_tree() and not get_tree().paused

func get_mission_info() -> Dictionary:
	var t: Array = _titles_of(_level_name)
	return {"level": _level_name, "title": str(t[0]), "place": str(t[1]), "date": str(t[2]),
		"index": LEVELS.find(_level_name)}

## Erreichte Missionen (Settings "game/unlocked"); das erste vorhandene Level ist immer offen.
func unlocked_levels() -> Array[String]:
	var saved: Array = []
	var st := get_node_or_null("/root/Settings")
	if st != null:
		var raw = st.call("get_value", "game/unlocked", [])
		if raw is Array:
			saved = raw
	var out: Array[String] = []
	var first := true
	for l in LEVELS:
		if not ResourceLoader.exists(_level_path(l)):
			continue
		if first or l in saved or l == _level_name:
			out.append(l)
		first = false
	return out

## Alle vorhandenen Missionen in Kampagnenreihenfolge mit Titeln und Freischalt-Status.
func mission_list() -> Array[Dictionary]:
	var open := unlocked_levels()
	var out: Array[Dictionary] = []
	for l in LEVELS:
		if not ResourceLoader.exists(_level_path(l)):
			continue
		var t: Array = TITLES.get(l, [l, "", ""])
		out.append({"level": l, "title": str(t[0]), "place": str(t[1]), "date": str(t[2]), "unlocked": l in open,
			"stars": Progress.stars(l), "star_mask": Progress.mask(l), "best_time": Progress.best_time(l),
			"goal": STAR_GOALS.get(l, {}), "challenge_text": Progress.challenge_text(STAR_GOALS.get(l, {}))})
	return out

func _mark_unlocked(level_name: String) -> void:
	var st := get_node_or_null("/root/Settings")
	if st == null:
		return
	var raw = st.call("get_value", "game/unlocked", [])
	var arr: Array = (raw as Array).duplicate() if raw is Array else []
	if not level_name in arr:
		arr.append(level_name)
		st.call("set_value", "game/unlocked", arr)

## Aktuelle Mission neu starten (Titelkarte ja, Lagebericht nicht noch einmal).
func restart_level() -> void:
	goto_level(_level_name, true)

## Mission wechseln/neu laden; sofort schwarz, dann wie ein normaler Levelstart.
func goto_level(level_name: String, skip_briefing: bool = false) -> void:
	if _busy or _in_briefing or not ResourceLoader.exists(_level_path(level_name)):
		return
	_busy = true
	if _title_tw != null and _title_tw.is_valid():
		_title_tw.kill()
	Engine.time_scale = 1.0
	get_tree().paused = false
	_stop_voice(0.05)
	_free_level()
	_black.color.a = 1.0
	_title.modulate.a = 0.0
	_sub.modulate.a = 0.0
	_brief.modulate.a = 0.0
	_hint.modulate.a = 0.0
	await get_tree().process_frame
	_busy = false
	_skip_brief_once = skip_briefing
	print("[main] Pausenmenue -> Level " + level_name)
	_load_level(level_name)

# ================================================================== Fortschritt / Sterne / Schwierigkeit (Welle 4)
## game/progress/: Run-Tracker pro Level, Auswertung + user://progress.cfg, Abschluss-Bildschirm, Schwierigkeitswahl.

func _start_tracker(level_name: String) -> void:
	if _tracker != null and is_instance_valid(_tracker):
		_tracker.queue_free()
	_tracker = RunTracker.new()
	_tracker.name = "RunTracker"
	_tracker.call("setup", _level, level_name, _goal_of(level_name))
	add_child(_tracker)

## Lauf auswerten und speichern (Tool-Laeufe: nur im Speicher, ausser --progress-file). {} ohne Tracker.
func _record_progress() -> Dictionary:
	if _tracker == null or not is_instance_valid(_tracker) or bool(_tracker.get("finished")):
		return {}
	var stats: Dictionary = _tracker.call("finish", Difficulty.current())
	var res := Progress.record(_level_name, _goal_of(_level_name), stats)
	var ev: Array = res["stars"]
	print("[progress] %s: Sterne %d/3 [%s|%s|%s] Zeit %s (Ziel %s) Genauigkeit %d%% Kopfschuss-Kills %d/%d Tode %d Alarme %d Geisel %d Schwierigkeit %s -> %s" % [
		_level_name, ev.count(true), "X" if ev[0] else "-", "X" if ev[1] else "-", "X" if ev[2] else "-",
		Progress.clock(float(stats["time"])), Progress.clock(float(res["time_goal"])), roundi(float(stats["accuracy"]) * 100.0),
		int(stats["headshot_kills"]), int(stats["kills"]), int(stats["deaths"]), int(stats["alarms"]),
		int(stats["hostage_incidents"]), str(stats["difficulty"]),
		("gespeichert: " + str(res["path"])) if bool(res["saved"]) else "nur im Speicher (Tool-Lauf)"])
	return res

## Abschluss-Bildschirm (kurz, ueberspringbar). Nie unter --autopilot (dort kehrt _on_level_completed vorher zurueck),
## aus mit --no-results, --debug-server oder --capture.
func _show_results(res: Dictionary) -> void:
	if res.is_empty():
		return
	for a in ["autopilot", "debug-server", "capture", "no-results"]:
		if Game.arg(a, false):
			return
	var scr: Node = ResultsScreen.new()
	scr.name = "ResultsScreen"
	add_child(scr)
	await scr.call("run", res, get_mission_info())

## Erster Kampagnenstart: Schwierigkeit waehlen, solange "game/difficulty" nie gesetzt wurde.
func _maybe_pick_difficulty() -> void:
	var st := get_node_or_null("/root/Settings")
	if st == null or bool(st.call("has", Difficulty.KEY)) or Game.arg("difficulty", null) != null:
		return
	_black.color.a = 1.0
	var p: Node = DifficultyPicker.new()
	p.name = "DifficultyPicker"
	add_child(p)
	var id: String = await p.call("run")
	print("[main] Schwierigkeit gewaehlt: " + id)

## Sterne gesamt / moeglich (vorhandene Level) fuer Missionsauswahl.
func star_summary() -> Dictionary:
	var lv: Array = []
	for l in LEVELS:
		if ResourceLoader.exists(_level_path(l)):
			lv.append(l)
	return {"earned": Progress.total_stars(lv), "total": lv.size() * 3}

## Ziele der laufenden Mission (Pausenmenue-Protokoll).
func current_goal_info() -> Dictionary:
	var g: Dictionary = _goal_of(_level_name)
	if g.is_empty():
		return {}
	return {"time": float(g.get("time", 0.0)), "time_text": Progress.time_text(g), "challenge_text": Progress.challenge_text(g),
		"stars": Progress.stars(_level_name), "difficulty": Difficulty.display_name()}

# ================================================================== Bonus-Episoden (Welle 5)
## game/episodes/episodes.gd: Liste, Freischaltung, Titel. Episoden laufen wie Level, aber ohne _mark_unlocked und
## ohne Folgemission; nach dem Abschluss-Bildschirm geht es zur letzten Kampagnenmission + Episodenmenue zurueck.

## Inhalt von Settings "game/unlocked" (unveraendert).
func _saved_unlocked() -> Array:
	var st := get_node_or_null("/root/Settings")
	if st == null:
		return []
	var raw = st.call("get_value", "game/unlocked", [])
	return raw if raw is Array else []

## Episodenliste fuers Pausenmenue: Titel, Sperrstatus, Sterne.
func episode_list() -> Array[Dictionary]:
	return Episodes.menu_list(_saved_unlocked())

func is_episode_running() -> bool:
	return _episode

## Episode starten (nur freigeschaltete). Kampagnenstand bleibt unberuehrt.
func start_episode(id: String) -> void:
	if not Episodes.is_unlocked(id, _saved_unlocked()):
		return
	goto_level(id)

## Rueckweg nach einer Episode: letzte Kampagnenmission (sonst die zuletzt erreichte) ohne Lagebericht.
func _campaign_return_level() -> String:
	if _campaign_level != "" and ResourceLoader.exists(_level_path(_campaign_level)):
		return _campaign_level
	var open := unlocked_levels()
	return open.back() if not open.is_empty() else _first_existing(0)

func _finish_episode(res: Dictionary) -> void:
	var tw := _ui.create_tween()
	tw.tween_property(_black, "color:a", 1.0, 1.2)
	await tw.finished
	await _show_results(res)
	_title.text = "Episode abgeschlossen"
	_sub.text = str(_titles_of(_level_name)[0])
	await _fade_labels(1.0, 0.6, [_title, _sub])
	_free_level()
	await _wait(2.0)
	await _fade_labels(0.0, 0.5, [_title, _sub])
	_busy = false
	var back := _campaign_return_level()
	if back == "":
		return
	print("[main] Episode beendet -> " + back)
	_skip_brief_once = true
	_load_level(back)
	# Episodenmenue oeffnen, sobald die Titelkarte durch ist
	await _wait(3.0)
	var pm := get_node_or_null("PauseMenu")
	if pm != null and pm.has_method("open_episodes") and can_pause():
		pm.call("open_episodes")
