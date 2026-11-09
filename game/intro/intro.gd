extends Node
## Kampagnen-Intro (ca. 90 s) in Spielgrafik.
## Ablauf: Senderkennung „EU24 Nachrichten“ (fiktiv) -> Nachrichten-Montage mit TV-Filter (4 Aufnahmen)
## -> Signalabriss -> taktische 3D-Lagekarte des Baltikums -> Schlussbild in Level 1 (Kamera sinkt auf
## den Graben) -> Schwarzblende -> Signal finished.
## Leertaste oder Esc ueberspringt (Hinweis unten rechts nach 2 s). Sprecher: Hauptmann Weber (Piper TTS).
## Standalone (als Hauptszene gestartet) beendet sich das Intro nach finished selbst.

signal finished

const IntroUI = preload("res://game/intro/intro_ui.gd")
const IntroNews = preload("res://game/intro/intro_news.gd")
const IntroMap = preload("res://game/intro/intro_map.gd")
const IProps = preload("res://game/intro/intro_props.gd")
const LEVEL_SCENE := "res://game/levels/baltic_night.tscn"
const SFX := "res://assets/sfx/"
const SPEAKER := "Hptm. Weber (Funk)"

## Nachrichten-Aufnahmen: [Start, Uhrzeit im Senderlogo, Schlagzeile, Unterzeile]
const SHOTS: Array = [
	[2.5, "23:47", "Truppenaufmarsch an der lettischen Grenze", "Region Pskow, Russland  ·  18. November 2029"],
	[9.0, "19:12", "Moskau weist Ultimatum zurück", "Grenzübergang Terehova, Lettland  ·  2. März 2030"],
	[15.5, "21:05", "NATO-Gipfel ohne Einigung – EU stellt eigene Kampfgruppen auf", "Verlegung nach Lettland  ·  9. März 2030"],
	[22.0, "23:41", "Raketenstarts nahe der Grenze – Moskau spricht von Manöver", "Westrussland  ·  13. März 2030"],
]
const T_SIGNAL_LOST := 28.6
const T_MAP := 30.0
const T_MAP_OUT := 64.2
const T_LOAD := 67.4          ## Schwarzbild: Level 1 laden (Zeitachse pausiert waehrenddessen)
const T_FINAL := 68.5         ## Aufblenden Schlussbild (Musik Teil B beginnt mit Schlag)
const T_KERNER := 84.0
const T_END := 88.6
const DESCENT := 17.0         ## Dauer der Kamerafahrt herab

## Weber spricht nur ueber Funk (Filter in die WAVs gebacken, tools/piper/gen_intro_audio.py).
## Die Nachrichten-Montage hat keinen Sprecher, nur leises, unverstaendliches Stimmengewirr.
## USE_VOICE = false: nur Untertitel mit Funkklick und Rauschen.
const USE_VOICE := true
## [Zeit, Datei, Untertitel]
const VOICE: Array = [
	[35.0, "intro_vo2", "An alle Einheiten. Hier Weber."],
	[40.8, "intro_vo3", "03:12 Uhr. Sie sind über die Grenze."],
	[46.6, "intro_vo4", "Ihr Ziel ist Riga. Und die Ostsee."],
	[51.8, "intro_vo5", "Kampfgruppe Nord ist die erste Linie."],
	[57.2, "intro_vo6", "Wir halten, bis Verstärkung kommt."],
	[60.8, "intro_vo8", "Jede Stunde zählt. Weber, Ende."],
	[T_KERNER, "intro_vo7", "Kerner. … Sie kommen."],
]
const T_BABBLE := 3.0

var _ui: Node
var _shots: Array[Node3D] = []
var _map: Node3D
var _level: Node3D
var _final_cam: Camera3D
var _stage: Node3D
var _stage_t0: float = 0.0
var _t: float = 0.0
var _events: Array = []
var _ev_i: int = 0
var _running: bool = false
var _paused: bool = false
var _done: bool = false
var _hint_shown: bool = false
var _real_t: float = 0.0
var _music: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _babble: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_i: int = 0
var _final_movers: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 1403
	_ui = IntroUI.new()
	_ui.name = "UI"
	add_child(_ui)
	_ui.tick_sound.connect(func() -> void: _play_sfx("intro_tick", -14.0))
	_ui.call("set_tv", 0.0)
	_build_audio()
	# Vorbereiten hinter Schwarz: alle Aufnahmen und die Karte bauen
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	for i in SHOTS.size():
		var s: Node3D = IntroNews.new()
		s.set("shot", i)
		s.name = "Shot%d" % i
		add_child(s)
		_shots.append(s)
	_map = IntroMap.new()
	_map.name = "Map"
	add_child(_map)
	print("[intro] Aufbau %d ms" % (Time.get_ticks_msec() - t0))
	_schedule()
	await get_tree().process_frame
	_running = true
	# Test-Hilfe: --intro-t=<s> springt an eine Stelle der Zeitachse (nur fuer Aufnahmen)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--intro-t="):
			_process(float(a.get_slice("=", 1)))

func _input(event: InputEvent) -> void:
	if _done:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		skip()

## Intro sofort beenden (Leertaste/Esc).
func skip() -> void:
	if _done:
		return
	print("[intro] uebersprungen bei %.1f s" % _t)
	_done = true
	_running = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_ui.get("black"), "color:a", 1.0, 0.25)
	for p: AudioStreamPlayer in [_music, _voice, _babble]:
		tw.tween_property(p, "volume_db", -60.0, 0.3)
	await tw.finished
	_emit_finished()

func _process(delta: float) -> void:
	_real_t += delta
	if not _hint_shown and _real_t > 2.0:
		_hint_shown = true
		_ui.call("show_hint")
	if not _running or _paused or _done:
		return
	_t += delta
	while _ev_i < _events.size() and float(_events[_ev_i][0]) <= _t:
		var c: Callable = _events[_ev_i][1]
		_ev_i += 1
		c.call()
		if _paused or _done:
			return
	if _stage != null and _stage.has_method("tick"):
		_stage.call("tick", _t - _stage_t0)
	if _final_cam != null:
		_tick_final(_t - T_FINAL, delta)

# --------------------------------------------------------------------------- Zeitplan

func _at(t: float, c: Callable) -> void:
	_events.append([t, c])

func _schedule() -> void:
	# Senderkennung
	_at(0.0, func() -> void:
		_ui.call("show_ident", 2.4)
		_ui.call("fade_black", 0.0, 0.25)
		_play_sfx("intro_sting", -3.0)
		_music.play())
	# Nachrichten-Aufnahmen
	for i in SHOTS.size():
		var s: Array = SHOTS[i]
		var idx := i
		_at(float(s[0]), func() -> void: _cut_to_shot(idx))
		_at(float(s[0]) + 0.7, func() -> void: _ui.call("set_headline", str(s[2]), str(s[3])))
	_at(T_BABBLE, func() -> void:
		if _babble.stream != null:
			_babble.play())
	_at(T_SIGNAL_LOST, func() -> void:
		_babble.stop()
		_play_sfx("intro_signal_lost", -6.0)
		_ui.call("hide_headline")
		_ui.call("set_tv", 1.0, 1.0))
	_at(T_SIGNAL_LOST + 1.1, func() -> void: _ui.call("fade_black", 1.0, 0.3))
	# Lagekarte
	_at(T_MAP, func() -> void:
		_ui.call("show_news", false)
		_set_stage(_map)
		_map.call("activate")
		_ui.call("set_tv", 0.35, 0.0, Color(0.85, 1.0, 1.05))
		_ui.call("tween_glitch", 0.6, 0.5)
		_ui.call("fade_black", 0.0, 0.6)
		_ui.call("show_map", true)
		_play_sfx("intro_whoosh", -8.0))
	_at(T_MAP + 0.3, func() -> void: _map.call("reveal", 3.2))
	_at(34.0, func() -> void:
		_ui.call("stamp", "13. MÄRZ 2030  ·  23:50", "Russische Verbände beziehen Bereitstellungsräume")
		_map.call("show_red_units")
		_play_sfx("intro_beep", -8.0))
	_at(40.0, func() -> void:
		_ui.call("stamp", "14. MÄRZ 2030  ·  03:12", "Russische Verbände überschreiten die Grenze")
		_map.call("start_red_arrows")
		_ui.call("tween_glitch", 0.35, 0.35)
		_play_sfx("intro_advance", -4.0)
		_play_sfx("intro_beep", -8.0))
	_at(51.0, func() -> void:
		_ui.call("stamp", "14. MÄRZ 2030  ·  03:20", "EU-Kampfgruppe Nord hält die Grenzlinie bei Lettgallen")
		_map.call("show_kg_nord")
		_play_sfx("intro_beep", -6.0))
	_at(56.0, func() -> void:
		_ui.call("stamp", "14. MÄRZ 2030  ·  03:30", "EU-Verbände verlegen nach Lettland")
		_map.call("start_blue_arrows")
		_play_sfx("intro_advance", -7.0)
		_play_sfx("intro_beep", -8.0))
	_at(T_MAP_OUT, func() -> void:
		_ui.call("fade_map", 1.6)
		_ui.call("fade_black", 1.0, 2.0))
	# Schlussbild
	_at(T_LOAD, _load_final)
	_at(T_FINAL, _start_final)
	_at(T_FINAL + 9.0, func() -> void: _flare(Vector3(-8.0, 48.0, -120.0)))
	_at(T_KERNER - 1.2, func() -> void: _flare(Vector3(9.0, 52.0, -95.0)))
	_at(T_END, func() -> void:
		_ui.call("fade_black", 1.0, 1.6)
		create_tween().tween_property(_music, "volume_db", -40.0, 2.0))
	_at(T_END + 2.0, func() -> void:
		_done = true
		_emit_finished())
	# Sprecher
	for v: Array in VOICE:
		var file := str(v[1])
		var text := str(v[2])
		_at(float(v[0]), func() -> void: _say(file, text))
	_events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

func _set_stage(s: Node3D) -> void:
	if _stage != null and _stage != s:
		_stage.queue_free()
	_stage = s
	_stage_t0 = _t

func _cut_to_shot(i: int) -> void:
	if i == 0:
		_ui.call("hide_ident")
		_ui.call("show_news", true)
	_ui.call("set_clock", str(SHOTS[i][1]))
	_ui.call("set_tv", 1.0)
	_ui.call("tween_glitch", 0.9 if i == 0 else 0.6, 0.35)
	_play_sfx("intro_static", -10.0)
	var s := _shots[i]
	_set_stage(s)
	s.call("activate")

# --------------------------------------------------------------------------- Schlussbild

func _load_final() -> void:
	_paused = true
	if _stage != null:
		_stage.queue_free()
		_stage = null
	_map = null
	_ui.call("show_map", false)
	_ui.call("set_tv", 0.0)
	var t0 := Time.get_ticks_msec()
	if ResourceLoader.exists(LEVEL_SCENE):
		var ps := load(LEVEL_SCENE) as PackedScene
		_level = ps.instantiate() as Node3D
		_level.set("spawn_player", false)
		_level.set("spawn_enemies", false)
		add_child(_level)
		var waited := 0
		while _level.has_method("is_level_ready") and not bool(_level.call("is_level_ready")) and waited < 600:
			await get_tree().process_frame
			waited += 1
			if _done:
				return
	else:
		_level = _fallback_scene()
		add_child(_level)
	_final_cam = Camera3D.new()
	_final_cam.fov = 62.0
	_final_cam.far = 600.0
	add_child(_final_cam)
	_final_cam.make_current()
	_build_final_threat()
	_tick_final(0.0, 0.0)
	# ein paar Frames rendern, damit Shader kompiliert sind, bevor aufgeblendet wird
	for i in 4:
		await get_tree().process_frame
	print("[intro] Level 1 geladen in %d ms" % (Time.get_ticks_msec() - t0))
	if _done:
		return
	_t = T_LOAD + 0.01
	_paused = false

func _start_final() -> void:
	_music.stream = _load_stream("intro_music_b")
	_music.volume_db = -5.0
	_music.play()
	_ui.call("fade_black", 0.0, 2.6)

## Feindliche Annaeherung im Hintergrund: Hubschrauber mit Suchscheinwerfern, Panzer mit Licht.
func _build_final_threat() -> void:
	var extras := Node3D.new()
	extras.name = "FinalExtras"
	add_child(extras)
	var helis: Array = [[Vector3(-45, 32, -330), Vector3(-14, 26, -95)], [Vector3(40, 38, -360), Vector3(16, 30, -110)]]
	for h: Array in helis:
		var from: Vector3 = h[0]
		var to: Vector3 = h[1]
		var real := IProps.try_vehicle(IProps.HELI_SCENE)
		var yaw := atan2(-(to - from).x, -(to - from).z)
		if real != null:
			real.set("faction", "ru")
			real.set("searchlight", true)
			real.position = from
			real.rotation.y = yaw
			extras.add_child(real)
			var pts: Array[Vector3] = [to]
			real.call("fly_path", pts, 14.0, false)
			real.set("_vel", (to - from).normalized() * 14.0)
		else:
			var sil := IProps.heli()
			sil.rotation.y = yaw
			var sl := SpotLight3D.new()
			sl.light_energy = 14.0
			sl.spot_range = 90.0
			sl.spot_angle = 9.0
			sl.light_volumetric_fog_energy = 4.0
			sl.rotation_degrees = Vector3(-55, 0, 0)
			sil.add_child(sl)
			sil.position = from
			extras.add_child(sil)
			_final_movers.append({"node": sil, "from": from, "vel": (to - from) / 20.0})
	for i in 4:
		var from := Vector3(-24.0 + i * 15.0 + _rng.randf_range(-3, 3), 0, -205.0 - _rng.randf_range(0, 20))
		var vel := Vector3(0, 0, 2.6)
		var real := IProps.try_vehicle(IProps.TANK_SCENE)
		if real != null:
			real.set("faction", "ru")
			real.position = from
			real.rotation.y = PI
			extras.add_child(real)
			IProps.headlight(real, Vector3(0, 1.3, -3.9), 6.0, 34.0)
			IProps.lamp_pair(real, -3.7, 1.2, 1.1)
			var pts: Array[Vector3] = [from + vel * 40.0]
			real.call("drive_path", pts, vel.length())
		else:
			var tk := IProps.tank()
			tk.rotation.y = PI
			tk.position = from
			extras.add_child(tk)
			_final_movers.append({"node": tk, "from": from, "vel": vel})

func _tick_final(lt: float, _delta: float) -> void:
	for m in _final_movers:
		(m["node"] as Node3D).position = (m["from"] as Vector3) + (m["vel"] as Vector3) * maxf(lt, 0.0)
	var k := clampf(lt / DESCENT, 0.0, 1.0)
	var e := k * k * k * (k * (k * 6.0 - 15.0) + 10.0)   # smootherstep
	var p0 := Vector3(18.0, 78.0, 70.0)
	var p1 := Vector3(12.0, 34.0, 34.0)
	var p2 := Vector3(4.0, 6.0, 7.0)
	var p3 := Vector3(2.7, 0.92, 0.35)
	var u := 1.0 - e
	var pos := p0 * u * u * u + p1 * 3.0 * u * u * e + p2 * 3.0 * u * e * e + p3 * e * e * e
	var look := Vector3(0, 0, -25.0).lerp(Vector3(1.8, 1.5, -70.0), smoothstep(0.35, 1.0, k))
	# leichtes Handkamera-Wackeln, staerker am Ende
	var shake := 0.012 + 0.02 * k
	pos += Vector3(sin(lt * 1.3) * shake, sin(lt * 1.9 + 1.0) * shake, 0)
	_final_cam.position = pos
	_final_cam.look_at(look, Vector3.UP)
	_final_cam.fov = lerpf(55.0, 68.0, e)

func _flare(pos: Vector3) -> void:
	if _level == null:
		return
	var fx := _level.get("fx") as Node
	if fx != null and fx.has_method("spawn_flare"):
		fx.call("spawn_flare", pos, true)

## Minimal-Kulisse, falls Level 1 fehlt.
func _fallback_scene() -> Node3D:
	var root := Node3D.new()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.04)
	env.ambient_light_color = Color(0.2, 0.25, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_density = 0.02
	we.environment = env
	root.add_child(we)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.75, 0.78, 0.85)
	g.material_override = gm
	root.add_child(g)
	return root

# --------------------------------------------------------------------------- Audio

func _build_audio() -> void:
	_music = AudioStreamPlayer.new()
	_music.stream = _load_stream("intro_music_a")
	_music.volume_db = -5.0
	add_child(_music)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = 3.0
	add_child(_voice)
	_babble = AudioStreamPlayer.new()
	_babble.stream = _load_stream("intro_babble")
	_babble.volume_db = -21.0
	add_child(_babble)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)

func _load_stream(n: String) -> AudioStream:
	var path := SFX + n + ".wav"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

func _play_sfx(n: String, db: float = 0.0) -> void:
	var s := _load_stream(n)
	if s == null:
		return
	var p := _sfx[_sfx_i]
	_sfx_i = (_sfx_i + 1) % _sfx.size()
	p.stream = s
	p.volume_db = db
	p.play()

func _say(file: String, text: String) -> void:
	var s := _load_stream(file) if USE_VOICE else null
	var dur := 2.2 + text.length() * 0.055
	if s != null:
		_voice.stream = s
		dur = s.get_length()
	else:
		# Fallback: Funkrauschen fuer die Dauer des Untertitels, Klick am Ende
		_voice.stream = _load_stream("intro_radio_bed")
		get_tree().create_timer(dur).timeout.connect(func() -> void:
			if _voice.stream != null and _voice.stream.resource_path.ends_with("intro_radio_bed.wav"):
				_voice.stop()
				_play_sfx("intro_radio_click", -4.0))
	_voice.play()
	var y := 900.0 if _final_cam != null else 690.0
	_ui.call("subtitle", SPEAKER, text, dur, y)

func _emit_finished() -> void:
	_music.stop()
	_voice.stop()
	_babble.stop()
	print("[intro] fertig")
	finished.emit()
	if get_tree().current_scene == self:
		get_tree().quit()
