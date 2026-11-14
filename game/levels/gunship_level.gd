extends "res://game/levels/level.gd"
## Level 8 "Waechter" (gunship): Nachts ueber dem Fliegerhorst Lindenau, Brandenburg, 09.06.2030, 02:30.
## Kerner sitzt am Feuerleitstand der "Waechter" (umgebauter A400M, Oberstlt. Brandt fliegt) und deckt Lenas und
## Voss' Trupp: Zaun -> Hangar/Tower -> fliehender Konvoi -> SAM/Taeuschkoerper -> Tanklager/Jets -> Sendemast.
## Eigener Spieler-Modus (game/gunship/*), der normale Player wird nicht gespawnt.

const GSWorld := preload("res://game/gunship/gs_world.gd")
const GSFx := preload("res://game/gunship/gs_fx.gd")
const GSController := preload("res://game/gunship/gs_controller.gd")
const GSHud := preload("res://game/gunship/gs_hud.gd")
const GSAudio := preload("res://game/gunship/gs_audio.gd")
const GSUnit := preload("res://game/gunship/gs_unit.gd")
const Base := preload("res://game/levels/gunship_base.gd")
const SH_POST := preload("res://game/gunship/thermal_post.gdshader")
const SD := preload("res://game/story/story_data.gd")

const PHASE_NAMES := ["", "PHASE 1  ZAUN", "PHASE 2  HANGAR / TOWER", "PHASE 3  KONVOI", "PHASE 4  LUFTABWEHR",
	"PHASE 5  TANKLAGER", "PHASE 6  SENDEMAST"]

var gw: GSWorld
var gfx: GSFx
var ctrl: GSController
var hud: GSHud
var audio: GSAudio
var post_mat: ShaderMaterial
var pts: Dictionary = {}

var phase: int = 0
var truck: GSUnit = null
var _time: float = 0.0
var _phase_t: float = 0.0
var _failed: String = ""
var _radio_end: float = 0.0
var _fail_count: int = 0
var _ff_cd: float = 0.0
var _check_escape: bool = false
var _taxi_jet: GSUnit = null
var _jet_rolling: bool = false
var _freeze: float = 0.0
var _mast_glow: float = 0.0
var _counting: bool = false
var _done: bool = false

func _init() -> void:
	level_name = "gunship"
	spawn_player = false
	spawn_enemies = false
	ambient_artillery = false
	default_faction = "reich"

func get_level_info() -> Dictionary:
	return {"name": level_name, "title": "Wächter", "waves": 6, "end_position": [-185.0, 0.0, -385.0], "waypoints": []}

func is_level_ready() -> bool:
	return _ready_done

func _ready() -> void:
	add_to_group("level")
	rng.seed = 2030
	_environment()
	pts = Base.build(self)
	gfx = GSFx.new()
	gfx.name = "FX"
	add_child(gfx)
	gw = GSWorld.new()
	gw.name = "Units"
	gw.fx = gfx
	add_child(gw)
	audio = GSAudio.new()
	audio.name = "Audio"
	add_child(audio)
	# Waermebild-Postprozess
	var pl := CanvasLayer.new()
	pl.name = "Thermal"
	pl.layer = 1
	add_child(pl)
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = SH_POST
	cr.material = post_mat
	pl.add_child(cr)
	ctrl = GSController.new()
	ctrl.name = "Waechter"
	ctrl.world = gw
	ctrl.fx = gfx
	ctrl.audio = audio
	ctrl.post_mat = post_mat
	ctrl.orbit_center = Vector3(-100, 0, 160)
	ctrl.orbit_target = ctrl.orbit_center
	ctrl.aim = Vector3(-150, 0, 215)
	add_child(ctrl)
	player = ctrl
	gfx.cam = ctrl.cam
	hud = GSHud.new()
	hud.name = "HUD"
	hud.ctrl = ctrl
	hud.world = gw
	add_child(hud)
	ctrl.aircraft_down.connect(func() -> void: _fail("aircraft"))
	gw.friendly_hit.connect(_on_friendly_hit)
	audio.loop("engine", true, -9.0)
	_ready_done = true
	_run()

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	env.fog_enabled = false
	env.ssao_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)

# ------------------------------------------------------------------ Hilfen

func _say(speaker: String, text: String, dur: float = 0.0) -> void:
	Events.story_radio.emit(speaker, text, dur)
	var d := dur if dur > 0.0 else clampf(1.6 + 0.055 * text.length(), 2.5, 8.0)
	_radio_end = maxf(_radio_end, _time) + d + 0.65

## Funkzeile mit StoryUI-Optionen (max_age/valid/priority/cut/key, siehe story_ui.gd say()).
func _say_opt(speaker: String, text: String, dur: float, opts: Dictionary) -> void:
	get_tree().call_group(&"story_ui", &"say", speaker, text, dur, opts)
	var d := dur if dur > 0.0 else clampf(1.6 + 0.055 * text.length(), 2.5, 8.0)
	_radio_end = maxf(_radio_end, _time) + d + 0.65

## Wartet, bis der Funk (geschaetzt) frei ist – hoechstens max_wait Sekunden.
func _radio_wait(max_wait: float = 12.0) -> bool:
	return await _sleep(clampf(_radio_end - _time, 0.0, max_wait))

func _obj(text: String) -> void:
	Events.story_objective.emit(text)

func _sleep(t: float) -> bool:
	var end := _time + t
	while _time < end:
		await get_tree().process_frame
		if _failed != "" or not is_inside_tree():
			return false
	return true

func _until(cond: Callable, timeout: float = -1.0) -> bool:
	var end := _time + timeout
	while not bool(cond.call()):
		await get_tree().process_frame
		if _failed != "" or not is_inside_tree():
			return false
		if timeout > 0.0 and _time >= end:
			return true
	return true

func _fail(reason: String) -> void:
	if _failed == "" and phase > 0 and not _done:
		_failed = reason

func _cleared(p: int) -> bool:
	return gw.alive_enemies(p).is_empty()

func _spawn(kind: String, pos: Vector3, yaw: float = 0.0, p: int = -1, req: bool = true) -> GSUnit:
	var u: GSUnit = gw.spawn(kind, "reich", pos, yaw, phase if p < 0 else p, req)
	return u

## Mehr Gegner: jede Infanterie-Gruppe ist um diesen Faktor groesser (aufgerundet).
const SQUAD_SCALE := 1.4

## Infanterie-Gruppe; mit Ziel laeuft sie dorthin (versetzt) und geht dort in Stellung, sonst sofort in Stellung.
func _squad(center: Vector3, n: int, to: Vector3 = Vector3.INF, spread: float = 5.0, via: Array = []) -> Array:
	var out: Array = []
	for i in ceili(n * SQUAD_SCALE):
		var off := Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		var u := _spawn("inf", center + off, rng.randf() * TAU)
		if to != Vector3.INF:
			var path: Array = []
			for v in via:
				path.append((v as Vector3) + off * 0.6)
			path.append(to + off * 1.4)
			u.set_path(path, u.speed * rng.randf_range(1.0, 1.3))
		else:
			u.state = "engage"
		out.append(u)
	return out

func _vehicle(kind: String, pos: Vector3, path: Array, spd: float = -1.0) -> GSUnit:
	var yaw := 0.0
	if not path.is_empty():
		var d: Vector3 = (path[0] as Vector3) - pos
		yaw = atan2(-d.x, -d.z)
	var u := _spawn(kind, pos, yaw)
	if not path.is_empty():
		u.set_path(path, spd)
	else:
		u.state = "engage"
	return u

# ------------------------------------------------------------------ Trupp

func _clear_team() -> void:
	var keep: Array = []
	for u in gw.units:
		var un: GSUnit = u
		if un.side == "team":
			un.queue_free()
		else:
			keep.append(un)
	gw.units = keep
	gw.team.clear()
	truck = null

func _spawn_team(at: Vector3, in_truck: bool = false, truck_yaw: float = 0.0) -> void:
	_clear_team()
	if in_truck:
		truck = gw.spawn("team_truck", "team", at, truck_yaw, 0, false)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		var off := Vector3(cos(a), 0, sin(a)) * (2.5 + float(i % 2) * 1.5)
		var u: GSUnit = gw.spawn("team", "team", at + off, rng.randf() * TAU, 0, false)
		u.formation = off
		u.engage_range = 130.0
		if in_truck:
			_board(u)

func _board(u: GSUnit) -> void:
	u.state = "ride"
	u.hidden_in = truck
	u.visible = false

func _dismount() -> void:
	if truck == null:
		return
	var tp := truck.global_position
	var back := truck.global_transform.basis.z
	for u in gw.team:
		var un: GSUnit = u
		if not un.alive:
			continue
		un.hidden_in = null
		un.visible = true
		un.global_position = tp + back * 4.0 + un.formation * 0.8
		un.state = "engage"

func _team_move(pts_arr: Array, spd: float = 5.0) -> void:
	for u in gw.team:
		var un: GSUnit = u
		if un.alive and un.state != "ride":
			un.set_path(pts_arr, spd * rng.randf_range(0.95, 1.05))

func _team_arrived() -> bool:
	for u in gw.team:
		var un: GSUnit = u
		if un.alive and un.state == "move":
			return false
	return true

# ------------------------------------------------------------------ Ablauf

func _run() -> void:
	# Titelkarte/Briefing von main.gd abwarten (pausiert das Spiel)
	await get_tree().process_frame
	var start := clampi(int(Game.arg("phase", 1)), 1, 6)
	_spawn_team(pts["team_start"])
	if not await _sleep(1.5):
		pass
	if start == 1:
		await _intro()
	phase = start
	while phase <= 6 and is_inside_tree():
		_failed = ""
		_phase_t = 0.0
		hud.phase_label = PHASE_NAMES[phase]
		await _radio_wait(8.0)
		var ok: bool = await _phase(phase)
		if not is_inside_tree():
			return
		print("[gunship] Phase %d %s nach %.1f s (gesamt %.1f s, Zelle %.0f)" % [phase, "geschafft" if ok and _failed == "" else "FEHLER " + _failed, _phase_t, _time, ctrl.integrity])
		if ok and _failed == "":
			phase += 1
		else:
			await _retry()
	if is_inside_tree():
		await _finale()

func _phase(p: int) -> bool:
	match p:
		1: return await _p1()
		2: return await _p2()
		3: return await _p3()
		4: return await _p4()
		5: return await _p5()
		6: return await _p6()
	return true

func _intro() -> void:
	_say(SD.BRANDT, "Wächter auf Station. Zweieinhalbtausend Fuß, Linkskurve über Lindenau. Kerner, die Optik gehört Ihnen.")
	_say(SD.LENA, "Hier Lena. Wir liegen am Waldrand vor dem Südtor. Seht ihr die Blinker?")
	_say(SD.KERNER, "Sechs Blinker, Waldrand Süd. Ich hab euch.")
	await _radio_wait(20.0)

## Phasen-Neustart nach Fehlschlag: Funk, Bildstoerung, Einheiten der Phase zuruecksetzen.
func _retry() -> void:
	var reason := _failed
	_fail_count += 1
	get_tree().call_group(&"story_ui", &"interrupt")
	_radio_end = _time
	match reason:
		"friendly":
			_say(SD.LENA, "Eigene Verluste! Kerner, du hast uns getroffen!")
		"pressure":
			_say(SD.VOSS, "Wir werden überrannt! Rückzug, sofort!")
		"aircraft":
			_say(SD.BRANDT, "Triebwerk drei brennt, wir verlieren Höhe! Wir müssen abdrehen!")
		"escape":
			_say(SD.BRANDT, "Der Konvoi ist durch. Verdammt.")
		"jet":
			_say(SD.LENA, "Der Jet ist in der Luft! Er dreht auf Leipzig!")
	Events.player_died.emit()
	ctrl.input_enabled = false
	ctrl.hit_glitch = 1.0
	gw.pressure_active = false
	_check_escape = false
	_jet_rolling = false
	_counting = false
	hud.upload = -1.0
	hud.mark_targets = false
	await get_tree().create_timer(3.0, false).timeout
	_freeze = 1.0
	_say(SD.BRANDT, "Neu ansetzen. Wir fliegen die Kurve noch einmal.")
	gw.remove_phase(phase, false)
	gfx.clear_all()
	ctrl.missile = {}
	ctrl.missile_warn = false
	audio.loop("warn", false)
	ctrl.refill_all()
	ctrl.repair(70.0)
	ctrl.flares_left = maxi(ctrl.flares_left, 10)
	gw.pressure = 100.0
	ctrl.input_enabled = true
	await get_tree().create_timer(1.0, false).timeout

# --- Phase 1: Zaun und Wachtuerme
func _p1() -> bool:
	_spawn_team(pts["team_start"])
	_team_move([Vector3(-150, 0, 252)], 3.0)
	ctrl.set_orbit_center(Vector3(-10, 0, 150), Vector3(-150, 0, 200), 3.0)
	gw.pressure_active = false
	gw.drain_scale = 0.3
	for wx: float in [-450.0, -150.0, 150.0, 450.0]:
		_squad(Vector3(wx, 0, 186), 2, Vector3.INF, 2.5)
	_squad(Vector3(-135, 0, 178), 5, Vector3.INF, 6.0)
	_squad(Vector3(-40, 0, 170), 3, Vector3.INF, 4.0)
	var jeep := _vehicle("jeep", Vector3(-400, 0, 175), [Vector3(-200, 0, 175), Vector3(-100, 0, 172), Vector3(40, 0, 175)], 7.0)
	jeep.engage_range = 120.0
	var flak_a := _spawn("flak", Vector3(-330, 0, 80))
	var flak_b := _spawn("flak", Vector3(260, 0, 90))
	_obj("Zaun und Wachtürme am Südtor räumen")
	_say(SD.BRANDT, "Alles, was nicht blinkt, gehört Riedhammer. Räumen Sie den Zaun ab.")
	_counting = true
	if not await _until(func() -> bool: return _phase_t > 14.0 or gw.alive_enemies(1).size() < 13):
		return false
	flak_a.flak_active = true
	flak_b.flak_active = true
	gw.pressure_active = true
	_say(SD.BRANDT, "Leuchtspur links unten – Flak! Die schießen nach Gehör. Nehmen Sie sie raus.")
	_say(SD.ORDNUNG, "Wache Süd an Platz: Beschuss aus der Luft! Wir sehen nichts!")
	if not await _until(func() -> bool: return _cleared(1)):
		return false
	_counting = false
	_say(SD.VOSS, "Zaun ist frei. Wir fahren rein – haltet uns den Weg zum Hangar offen.")
	return await _sleep(3.0)

# --- Phase 2: Trupp zum Hangar, dann zum Tower
func _p2() -> bool:
	_spawn_team(Vector3(-150, 0, 215), true, 0.0)
	gw.pressure_active = true
	gw.pressure = 100.0
	gw.drain_scale = 0.35
	ctrl.set_orbit_center(Vector3(-110, 0, -110), Vector3(-150, 0, 120), 4.0)
	_obj("Den Trupp zum Hangar 2 eskortieren")
	truck.set_path([Vector3(-150, 0, 185), Vector3(-150, 0, 20), Vector3(-150, 0, -85), Vector3(-145, 0, -172)], 11.0)
	# Sperre am Rollweg, Posten am Vorfeld
	_squad(Vector3(-205, 0, -95), 4, Vector3.INF, 5.0)
	_squad(Vector3(-60, 0, -120), 3, Vector3.INF, 5.0)
	_counting = true
	if not await _sleep(6.0):
		return false
	_say(SD.ORDNUNG, "Alarm, Alarm! Fahrzeug durchbricht das Südtor! Alle Kräfte zu den Hangars!")
	# Welle aus den Kasernen
	_squad(Vector3(-20, 0, -280), 6, Vector3(-95, 0, -175), 6.0, [Vector3(-20, 0, -255), Vector3(-60, 0, -240)])
	_squad(Vector3(60, 0, -280), 5, Vector3(-40, 0, -165), 6.0, [Vector3(40, 0, -250)])
	if not await _until(func() -> bool: return truck.at_path_end()):
		return false
	_dismount()
	_say(SD.LENA, "Absitzen! Hangar zwei, los, los!")
	_team_move([Vector3(-155, 0, -192)], 4.5)
	var apc := _vehicle("apc", Vector3(130, 0, -300), [Vector3(150, 0, -255), Vector3(0, 0, -255), Vector3(-40, 0, -175)], 8.0)
	apc.engage_range = 150.0
	if not await _sleep(4.0):
		return false
	_say(SD.BRANDT, "Schützenpanzer kommt aus dem Fahrzeugpark. Den knacken nur die Hundertfünfer.")
	if not await _until(func() -> bool: return _cleared(2)):
		return false
	_say(SD.LENA, "Hangar gesichert. Wir gehen rüber zum Tower.")
	_obj("Den Trupp zum Tower decken")
	_team_move([Vector3(-100, 0, -178), Vector3(-20, 0, -180), Vector3(30, 0, -184)], 5.0)
	_squad(Vector3(120, 0, -150), 5, Vector3(55, 0, -170), 6.0)
	_squad(Vector3(60, 0, -250), 4, Vector3(35, 0, -215), 4.0)
	var jeep := _vehicle("jeep", Vector3(180, 0, -255), [Vector3(100, 0, -255), Vector3(70, 0, -210)], 11.0)
	jeep.engage_range = 140.0
	if not await _sleep(3.0):
		return false
	# Feindfunk nur aktuell – liegt er hinter anderen Zeilen, entfaellt er
	_say_opt(SD.ORDNUNG, "Tower an Wache: Sie kommen über das Vorfeld! Haltet die Treppe!", 0.0, {"max_age": 3.0})
	if not await _until(func() -> bool: return _cleared(2) and _team_arrived()):
		return false
	_counting = false
	gw.pressure_active = false
	_say(SD.VOSS, "Tower ist unser. Und der Platzkommandant hat sich abgesetzt – Konvoi Richtung Nordtor!")
	return await _sleep(2.0)

# --- Phase 3: fliehender Konvoi
func _p3() -> bool:
	_spawn_team(Vector3(22, 0, -186))
	gw.pressure_active = false
	ctrl.set_orbit_center(Vector3(250, 0, -520), Vector3(250, 0, -300), 4.0)
	_obj("Den Konvoi stoppen, bevor er das Dorf verlässt")
	var route := [Vector3(160, 0, -255), Vector3(300, 0, -255), Vector3(300, 0, -430), Vector3(300, 0, -660),
		Vector3(262, 0, -860), Vector3(240, 0, -1150), Vector3(226, 0, -1650)]
	var kinds := ["jeep", "truck", "apc", "truck"]
	for i in kinds.size():
		var start := Vector3(150.0 - i * 2.0, 0, -300.0 + i * 1.0)
		var u := _vehicle(kinds[i], start + Vector3(0, 0, i * 16.0), [Vector3(150, 0, -270 + i * 4.0)] + route, 10.0)
		u.engage_range = 0.0
		u.speed = 10.0
		u.path_i = 0
		# versetzt anfahren
		u.set_meta("delay", float(i) * 2.2)
		u.state = "idle"
	gw.escape_z = -1000.0
	_check_escape = true
	_counting = true
	_say(SD.BRANDT, "Ich ziehe die Kurve nach Norden. Der Konvoi darf das Dorf nicht verlassen.")
	# Startverzoegerung
	var t0 := _time
	while _time - t0 < 9.0:
		await get_tree().process_frame
		if _failed != "":
			return false
		for u in gw.alive_enemies(3):
			var un: GSUnit = u
			if un.state == "idle" and _time - t0 > 2.5 + float(un.get_meta("delay", 0.0)):
				un.state = "move"
	if not await _sleep(10.0):
		return false
	_say(SD.KERNER, "Konvoi auf der Straße nach Norden. Ich bleibe von den Häusern weg.")
	if not await _until(func() -> bool: return _cleared(3)):
		return false
	_check_escape = false
	_counting = false
	_say(SD.BRANDT, "Konvoi steht. Saubere Arbeit, Kerner.")
	return await _sleep(2.5)

# --- Phase 4: SAM-Start, Taeuschkoerper, Luftabwehr ausschalten
func _p4() -> bool:
	_spawn_team(Vector3(22, 0, -186))
	gw.pressure_active = false
	ctrl.set_orbit_center(Vector3(90, 0, -100), Vector3(300, 0, -150), 5.0)
	var sam_a := _spawn("sam", Vector3(580, 0, -110), PI * 0.5)
	var sam_b := _spawn("sam", Vector3(-160, 0, 110), -PI * 0.5)
	var radar := _spawn("radar", Vector3(-340, 0, -300))
	var fa := _spawn("flak", Vector3(-330, 0, -245))
	var fb := _spawn("flak", Vector3(330, 0, -260))
	_squad(Vector3(560, 0, -95), 3, Vector3.INF, 8.0)
	_squad(Vector3(-175, 0, 120), 3, Vector3.INF, 8.0)
	for u in _squad(Vector3(-330, 0, -310), 2, Vector3.INF, 6.0):
		(u as GSUnit).required = false
	_say(SD.BRANDT, "Moment – Feuerleitradar! Wir sind aufgeschaltet!")
	if not await _sleep(2.5):
		return false
	ctrl.launch_missile(sam_a.global_position)
	_obj("Täuschkörper ausstoßen [F]")
	if not await _until(func() -> bool: return ctrl.missile.is_empty()):
		return false
	fa.flak_active = true
	fb.flak_active = true
	_say(SD.BRANDT, "Das war knapp. Nehmen Sie die Stellungen und das Radar raus, sonst kommt die nächste.")
	_obj("SAM-Stellungen und Radar zerstören")
	_counting = true
	var next_launch := _time + 26.0
	while not _cleared(4):
		await get_tree().process_frame
		if _failed != "":
			return false
		if _time >= next_launch and ctrl.missile.is_empty():
			var src: GSUnit = null
			for s in [sam_a, sam_b]:
				if (s as GSUnit).alive:
					src = s
			if src != null and radar.alive:
				_say(SD.ORDNUNG, "Feuerleitung Lindenau: Ziel erfasst, Start!")
				ctrl.launch_missile(src.global_position)
			elif src != null:
				_say(SD.ORDNUNG, "Radar ausgefallen! Optisch nachführen, Start!")
				ctrl.launch_missile(src.global_position)
			next_launch = _time + 28.0
	_counting = false
	_say(SD.BRANDT, "Luftraum sauber. Danke, Kerner.")
	return await _sleep(2.5)

# --- Phase 5: Tanklager und Jets
func _p5() -> bool:
	_spawn_team(Vector3(22, 0, -186))
	gw.pressure_active = false
	ctrl.set_orbit_center(Vector3(330, 0, -210), Vector3(300, 0, -200), 4.0)
	for p: Vector3 in [Vector3(430, 0, -265), Vector3(490, 0, -265), Vector3(430, 0, -315), Vector3(490, 0, -315)]:
		_spawn("fuel", p, rng.randf() * TAU)
	var jets: Array = []
	for x: float in [175.0, 215.0, 255.0, 295.0]:
		jets.append(_spawn("jet", Vector3(x, 0, -142), PI))
	_spawn("bowser", Vector3(195, 0, -162), PI * 0.5)
	_spawn("bowser", Vector3(275, 0, -162), -PI * 0.5)
	for u in _squad(Vector3(235, 0, -150), 6, Vector3.INF, 30.0):
		(u as GSUnit).required = false
	_say(SD.VOSS, "Vom Tower sehen wir das Betankungsvorfeld. Vier Jets, voll bewaffnet – die sollen heute Nacht Leipzig angreifen.")
	_obj("Tanklager und Jets zerstören")
	_counting = true
	if not await _until(func() -> bool: return _phase_t > 13.0 or _cleared(5)):
		return false
	_taxi_jet = null
	for j in jets:
		if (j as GSUnit).alive:
			_taxi_jet = j
			break
	if _taxi_jet != null:
		var jp := _taxi_jet.global_position
		_taxi_jet.taxiing = true
		_taxi_jet.set_path([jp + Vector3(0, 0, 30), Vector3(jp.x, 0, -85), Vector3(450, 0, -85), Vector3(450, 0, -30), Vector3(445, 0, 0)], 9.0)
		_say(SD.LENA, "Ein Jet rollt! Er will zur Bahn!")
		_say(SD.BRANDT, "Der darf nicht abheben. Vierzig Millimeter, aufs Fahrwerk!")
	while not _cleared(5):
		await get_tree().process_frame
		if _failed != "":
			return false
		if _taxi_jet != null and _taxi_jet.alive:
			if not _jet_rolling and _taxi_jet.at_path_end():
				_jet_rolling = true
				_taxi_jet.set_path([Vector3(250, 0, 0), Vector3(-450, 0, 0)], 38.0)
			elif _jet_rolling and _taxi_jet.at_path_end():
				_fail("jet")
				return false
	_jet_rolling = false
	_counting = false
	_say(SD.ORDNUNG, "Tanklager brennt … Lindenau, bitte kommen … Lindenau?")
	return await _sleep(3.0)

# --- Phase 6: zum Sendemast, Sendung halten
func _p6() -> bool:
	_spawn_team(Vector3(28, 0, -205), true, PI)
	gw.pressure_active = true
	gw.pressure = 100.0
	gw.drain_scale = 0.3
	ctrl.set_orbit_center(Vector3(-130, 0, -300), Vector3(-60, 0, -255), 4.0)
	_say(SD.LENA, "Jetzt der Sender. Wir fahren zum Funkbunker – Webers Protokolle gehen auf allen Frequenzen raus.")
	_obj("Den Trupp zum Funkbunker eskortieren")
	truck.set_path([Vector3(20, 0, -255), Vector3(-240, 0, -255), Vector3(-240, 0, -330), Vector3(-205, 0, -352)], 13.0)
	_squad(Vector3(-110, 0, -270), 5, Vector3.INF, 8.0)
	_squad(Vector3(-255, 0, -300), 3, Vector3.INF, 5.0)
	_counting = true
	if not await _until(func() -> bool: return _phase_t > 9.0 or truck.at_path_end()):
		return false
	# Strassensperre am Kasernenblock: Jeep plus Trupp versuchen, den LKW zu stoppen
	var block := _vehicle("jeep", Vector3(-60, 0, -345), [Vector3(-150, 0, -300), Vector3(-185, 0, -262)], 9.0)
	block.engage_range = 110.0
	_squad(Vector3(-20, 0, -330), 4, Vector3(-175, 0, -268), 4.0)
	_say(SD.ORDNUNG, "Kaserne Nord: LKW auf der Ringstraße! Sperre errichten, sofort!")
	if not await _until(func() -> bool: return truck.at_path_end()):
		return false
	_dismount()
	_team_move([Vector3(-200, 0, -357)], 4.0)
	_say(SD.VOSS, "Wir sind drin. Einspeisung läuft. Haltet sie uns vom Leib!")
	_obj("Den Bunker halten, bis die Sendung läuft")
	hud.upload_label = "SENDUNG"
	hud.upload = 0.0
	var upload := 0.0
	var wave := 0
	var t0 := _time
	var manpads := false
	while upload < 1.0:
		await get_tree().process_frame
		if _failed != "":
			return false
		var dt := get_process_delta_time()
		upload = minf(1.0, upload + dt / 50.0)
		hud.upload = upload
		var el := _time - t0
		if wave == 0 and el > 3.0:
			wave = 1
			_say(SD.ORDNUNG, "Alle Einheiten zum Sendemast! Der Mast darf nicht fallen!")
			_squad(Vector3(40, 0, -320), 7, Vector3(-120, 0, -350), 7.0, [Vector3(0, 0, -322), Vector3(-80, 0, -330)])
		elif wave == 1 and el > 15.0:
			wave = 2
			_squad(Vector3(-345, 0, -290), 5, Vector3(-260, 0, -345), 6.0)
			var jp := _vehicle("jeep", Vector3(-480, 0, -418), [Vector3(-300, 0, -418), Vector3(-255, 0, -395)], 11.0)
			jp.engage_range = 140.0
		elif wave == 2 and el > 27.0:
			wave = 3
			var tank := _vehicle("tank", Vector3(130, 0, -320), [Vector3(130, 0, -255), Vector3(-40, 0, -255), Vector3(-90, 0, -320)], 6.0)
			tank.engage_range = 170.0
			_squad(Vector3(100, 0, -255), 4, Vector3(-80, 0, -300), 6.0, [Vector3(-20, 0, -262)])
			_say(SD.BRANDT, "Kampfpanzer aus dem Fahrzeugpark, Richtung Bunker. Hundertfünf bereithalten.")
		if not manpads and upload > 0.55:
			manpads = true
			_say_opt(SD.BRANDT, "Schulterrakete vom Kasernendach! Täuschkörper!", 0.0, {"priority": 2, "cut": true})
			ctrl.launch_missile(Vector3(60, 12, -345))
	hud.upload = 1.0
	_counting = false
	_mast_glow = 1.0
	return true

func _finale() -> void:
	_done = true
	_obj("")
	_say(SD.VOSS, "Wir sind auf Sendung. Landesweit.")
	_say(SD.ORDNUNG, "An alle Einheiten: Empfang auf allen Frequenzen sofort einstellen! Das ist Feindpropaganda!")
	_say(SD.LENA, "Zu spät. Das ganze Land hört Weber zu – mit seiner eigenen Stimme.")
	_say(SD.BRANDT, "Wächter dreht ab. Kerner, Feuerleitung sichern. Gute Jagd.")
	ctrl.weapons_free = false
	gw.pressure_active = false
	ctrl.set_orbit_center(Vector3(-150, 0, -330))
	await get_tree().create_timer(18.0, false).timeout
	hud.upload = -1.0
	Events.level_completed.emit()

# ------------------------------------------------------------------ Laufend

func _on_friendly_hit(_u: Node3D, killed: bool) -> void:
	if killed:
		_fail("friendly")
		return
	hud.ff_warn = 3.0
	if _ff_cd <= 0.0:
		_ff_cd = 8.0
		_say(SD.LENA, "Feuer einstellen! Das sind wir!")

func _process(delta: float) -> void:
	if not _ready_done:
		return
	_time += delta
	_phase_t += delta
	if Game.arg("autopilot") and int(_time / 30.0) != int((_time - delta) / 30.0):
		var rest: Array[String] = []
		for u in gw.alive_enemies(phase):
			var un: GSUnit = u
			rest.append("%s(%.0f,%.0f)" % [un.kind, un.global_position.x, un.global_position.z])
		print("[gunship] t=%.0f Phase %d offen: %s" % [_time, phase, ", ".join(rest)])
	_ff_cd = maxf(0.0, _ff_cd - delta)
	if phase > 0 and _failed == "" and not _done:
		if gw.pressure_active and gw.pressure <= 0.0:
			_fail("pressure")
		if _check_escape:
			for u in gw.alive_enemies(3):
				if (u as GSUnit).escaped:
					_fail("escape")
					break
	# Zielanzeige
	if _counting:
		var left := gw.alive_enemies(phase).size()
		hud.targets_left = left
		hud.mark_targets = left <= 3 or _phase_t > 75.0
	else:
		hud.targets_left = -1
		hud.mark_targets = false
	# Kalibrier-Blitz nach Neustart
	if _freeze > 0.0:
		_freeze = maxf(0.0, _freeze - delta * 1.4)
		post_mat.set_shader_parameter("freeze", _freeze)
	# Flugbefeuerung am Mast, Sendung
	var mt: Vector3 = pts["mast_top"]
	if fmod(_time, 1.5) < 0.18:
		gfx.glow(mt + Vector3(0, 8, 0), 2.0, 2.4)
		gfx.glow(mt + Vector3(0, -38, 0), 1.6, 2.0)
	if _mast_glow > 0.0:
		var k := 0.5 + 0.5 * sin(_time * 7.0)
		for i in 3:
			gfx.glow(mt + Vector3(0, -10.0 - i * 18.0, 0), 3.0 + k * 2.0, 1.2 + k * 0.6, 0.0, Vector3.ZERO, 0.0, 0.0, 0.6)
