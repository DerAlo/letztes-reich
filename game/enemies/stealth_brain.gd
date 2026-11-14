extends Node
## Opt-in Schleich-KI fuer einen Gegner (Level "curfew"). Haengt als Kind am Enemy und setzt enemy.stealth.
## Uebernimmt nur den IDLE-Zustand des Gegners (Streife, Verdacht, Nachsehen, Suche); sobald der Gegner
## alarmiert ist (ALERT/ATTACK/...), kaempft die normale Enemy-KI. Alle anderen Level bleiben unberuehrt.
## Wahrnehmung: Sichtkegel (voll bis 52°, halb bis 80°), Licht am Spieler (Direktor), Hocken, Abstand,
## Bewegung, Geraeusche, Leichen. Verdacht steigt erst an ("Halt? Wer da?"), dann folgt der Alarm.

enum S { CALM, SUSPICIOUS, INVESTIGATE, SEARCH, BODY, RETURN, COMBAT, DEAD }

const SHOW_AT := 0.35          ## ab hier "verdaechtig" (Bark, stehen bleiben)
const MIN_SUSPECT_TIME := 1.3  ## so lange dauert es mindestens vom Verdacht bis zum Alarm (ausser sehr nah)
const INSTANT_DIST := 3.5     ## naeher dran: Entdeckung ohne Mindest-Vorwarnzeit
const CONE_FULL := 52.0
const CONE_HALF := 80.0
const FEEL_RADIUS := 1.6
const GAIN := 0.45

var enemy: Enemy
var director: Node
var route: Array = []          ## [{"p": Vector3, "wait": float, "yaw": float (NAN = egal)}]
var patrol_speed: float = 1.45
var has_flashlight: bool = true
var guard_name: String = ""

var state: S = S.CALM
var suspicion: float = 0.0
var _route_i: int = 0
var _wait_t: float = 0.0
var _state_t: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _look_base: float = 0.0
var _search_pts: Array[Vector3] = []
var _unseen_t: float = 0.0
var _body_scan_t: float = 0.0
var _body_target: Dictionary = {}
var _noise_cd: float = 0.0
var _label: Label3D
var _label_t: float = 0.0
var flashlight: SpotLight3D
var _lens: MeshInstance3D

func setup(e: Enemy, dir: Node, p_route: Array, flash: bool = true) -> void:
	enemy = e
	director = dir
	route = p_route
	has_flashlight = flash
	name = "StealthBrain"
	e.stealth = self
	# Leichen bleiben liegen (Fund = Alarm), kein Ausblenden
	e.cleanup_time = 1.0e6
	e.fade_start = 1.0e6
	e.add_child(self)

func _ready() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 44
	_label.pixel_size = 0.0045
	_label.outline_size = 10
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.modulate = Color(1.0, 0.86, 0.45)
	_label.shaded = false
	_label.position = Vector3(0, 2.3, 0)
	_label.visible = false
	enemy.add_child.call_deferred(_label)
	if has_flashlight:
		_build_flashlight()
	if director != null and director.has_method("register_watcher"):
		director.call("register_watcher", self)

func _build_flashlight() -> void:
	flashlight = SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.light_color = Color(1.0, 0.93, 0.8)
	flashlight.light_energy = 5.0
	flashlight.spot_range = 21.0
	flashlight.spot_angle = 21.0
	flashlight.spot_angle_attenuation = 0.9
	flashlight.spot_attenuation = 1.1
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.06
	flashlight.light_volumetric_fog_energy = 1.7
	flashlight.light_specular = 0.6
	flashlight.distance_fade_enabled = true
	flashlight.distance_fade_begin = 55.0
	flashlight.distance_fade_length = 12.0
	flashlight.position = Vector3(0.22, 1.33, -0.32)
	flashlight.rotation_degrees = Vector3(-11.0, 0, 0)
	flashlight.set_meta("stealth_light", true)
	enemy.add_child.call_deferred(flashlight)
	# Lampenkopf: kleiner Zylinder mit leuchtender Linse
	_lens = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.026
	cm.bottom_radius = 0.022
	cm.height = 0.14
	cm.radial_segments = 10
	_lens.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.035)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.92, 0.75)
	m.emission_energy_multiplier = 2.5
	_lens.material_override = m
	_lens.rotation_degrees = Vector3(90, 0, 0)
	_lens.position = Vector3(0, 0, 0.06)
	_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flashlight.add_child(_lens)
	var lm := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.025
	dm.bottom_radius = 0.025
	dm.height = 0.004
	lm.mesh = dm
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(4.0, 3.6, 3.0)
	lm.material_override = em
	lm.rotation_degrees = Vector3(90, 0, 0)
	lm.position = Vector3(0, 0, -0.012)
	flashlight.add_child(lm)

# ------------------------------------------------------------------ Schnittstelle fuer Enemy

## Wird von Enemy._tick_idle aufgerufen. true = Brain hat den Tick uebernommen.
func tick_idle(delta: float) -> bool:
	if enemy == null or state == S.DEAD:
		return false
	if state == S.COMBAT:
		# Alarm vorbei, Gegner zurueck auf IDLE gesetzt -> heimkehren
		_enter(S.RETURN)
	enemy._aim_at_target = false
	enemy._stance_target = 0.0
	_state_t += delta
	_noise_cd = maxf(0.0, _noise_cd - delta)
	_perceive(delta)
	if state == S.COMBAT or state == S.DEAD:
		return true
	match state:
		S.CALM: _tick_patrol(delta)
		S.SUSPICIOUS: _tick_suspicious(delta)
		S.INVESTIGATE: _tick_investigate(delta)
		S.SEARCH: _tick_search(delta)
		S.BODY: _tick_body(delta)
		S.RETURN: _tick_return(delta)
	return true

## Schuss gehoert. true = Brain hat ihn behandelt (Standard-Alarm unterdruecken).
func on_weapon_fired(weapon: Node) -> bool:
	if enemy == null or state == S.DEAD:
		return false
	var pos: Vector3 = (weapon as Node3D).global_position if weapon is Node3D else enemy.global_position
	var d := pos.distance_to(enemy.global_position)
	if bool(weapon.get("suppressed")):
		if state != S.COMBAT and d <= 8.0:
			_hear(pos, "Was war das?")
		return true
	# lauter Schuss: Alarm im Viertel (Direktor), Standardreaktion des Gegners
	if director != null and d <= enemy.hear_weapon_range:
		director.call("raise_alarm", pos, "shot", false)
	return false

func on_owner_died() -> void:
	state = S.DEAD
	suspicion = 0.0
	_label.visible = false
	if flashlight != null and is_instance_valid(flashlight):
		_drop_flashlight()
	if director != null:
		director.call("register_body", enemy)

# ------------------------------------------------------------------ Watcher-Schnittstelle (HUD)

func get_suspicion() -> float:
	if state == S.COMBAT:
		return 1.0
	return suspicion

## 0 = ruhig, 1 = misstrauisch/sucht, 2 = Kampf
func get_watch_state() -> int:
	if state == S.DEAD:
		return -1
	if state == S.COMBAT:
		return 2
	if state in [S.SUSPICIOUS, S.INVESTIGATE, S.SEARCH, S.BODY] or suspicion > 0.05:
		return 1
	return 0

func get_watch_pos() -> Vector3:
	return enemy.global_position + Vector3.UP * 2.05

func is_watcher_alive() -> bool:
	return state != S.DEAD and enemy != null and is_instance_valid(enemy)

## Fuer den Takedown: weiss der Gegner von Kerner?
func is_aware() -> bool:
	return state == S.COMBAT or (state == S.SUSPICIOUS and suspicion > 0.75)

# ------------------------------------------------------------------ Direktor-Befehle

## Alarm nach Sichtung: Gegner in der Naehe gehen in den Kampf.
func join_combat(pos: Vector3) -> void:
	if state == S.DEAD or enemy.state == Enemy.State.DEAD:
		return
	enemy.alert(pos, false)
	state = S.COMBAT

## Leichenfund/Alarm ohne Sichtkontakt: Umgebung absuchen.
func start_search(pos: Vector3) -> void:
	if state == S.DEAD or state == S.COMBAT:
		return
	_target_pos = pos
	_search_pts.clear()
	for i in 3:
		var a := randf() * TAU
		_search_pts.append(pos + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 8.0))
	_enter(S.SEARCH)

## Geraeusch (z. B. abgestuerzte Drohne): nachsehen, wenn nah genug.
func hear_noise(pos: Vector3, radius: float) -> void:
	if state in [S.DEAD, S.COMBAT] or enemy.global_position.distance_to(pos) > radius:
		return
	_hear(pos, "Was war das?")

## Alarm abgeklungen: aus dem Kampf zurueck auf Streife.
func stand_down() -> void:
	if state == S.DEAD or enemy.state == Enemy.State.DEAD:
		return
	if enemy.state != Enemy.State.IDLE:
		enemy._release_cover()
		enemy._burst_left = 0
		enemy._set_state(Enemy.State.IDLE)
	enemy._has_last_known = false
	suspicion = minf(suspicion, 0.2)
	_enter(S.RETURN)

## Nach Neustart am Checkpoint: zurueck an den Streifenanfang.
func reset_home() -> void:
	if state == S.DEAD or enemy.state == Enemy.State.DEAD:
		return
	stand_down()
	if not route.is_empty():
		enemy.global_position = route[0]["p"]
		enemy.velocity = Vector3.ZERO
		var y: float = route[0].get("yaw", NAN)
		if not is_nan(y):
			enemy.rotation.y = y
	_route_i = 0
	_wait_t = 0.0
	suspicion = 0.0
	_enter(S.CALM)

# ------------------------------------------------------------------ Ablauf

func _physics_process(delta: float) -> void:
	if enemy == null or state == S.DEAD:
		return
	if enemy.state != Enemy.State.IDLE and enemy.state != Enemy.State.DEAD and state != S.COMBAT:
		state = S.COMBAT
		suspicion = 1.0
		_say("", 0.0)
	if _label_t > 0.0:
		_label_t -= delta
		if _label_t <= 0.0:
			_label.visible = false
		else:
			_label.modulate.a = clampf(_label_t / 0.4, 0.0, 1.0)

func _enter(s: S) -> void:
	state = s
	_state_t = 0.0
	_wait_t = 0.0

func _say(text: String, dur: float = 2.4) -> void:
	if _label == null:
		return
	if text == "":
		_label.visible = false
		_label_t = 0.0
		return
	_label.text = text
	_label.visible = true
	_label.modulate.a = 1.0
	_label_t = dur

func _perceive(delta: float) -> void:
	var rate := _sight_rate()
	if rate > 0.0:
		_unseen_t = 0.0
		suspicion = minf(1.0, suspicion + rate * GAIN * delta)
		_target_pos = enemy._player.global_position
	else:
		_unseen_t += delta
		var decay := 0.05 if state in [S.SUSPICIOUS, S.INVESTIGATE] else 0.12
		suspicion = maxf(0.0, suspicion - decay * delta)
	# Verdacht -> stehen bleiben, nachfragen
	if rate > 0.0 and suspicion >= SHOW_AT and state in [S.CALM, S.RETURN, S.SEARCH]:
		_enter(S.SUSPICIOUS)
		_say("Halt? Wer da?")
		enemy._play_sfx("curfew_suspicion")
	# Entdeckt
	if suspicion >= 1.0 and rate > 0.0:
		var d := enemy._dist_to_player()
		if state != S.SUSPICIOUS or _state_t >= MIN_SUSPECT_TIME or d < INSTANT_DIST:
			_spot()
			return
	# Geraeusche (laufen, rennen)
	if _noise_cd <= 0.0 and director != null and rate <= 0.0 and enemy._target_alive():
		var nr: float = director.get("noise_radius")
		if nr > 0.0 and enemy._dist_to_player() <= nr and state in [S.CALM, S.RETURN, S.SEARCH, S.INVESTIGATE]:
			_hear(enemy._player.global_position, "Hm? Ist da wer?")
	# Leichen
	_body_scan_t -= delta
	if _body_scan_t <= 0.0:
		_body_scan_t = 0.35
		if state in [S.CALM, S.RETURN, S.INVESTIGATE, S.SEARCH]:
			_scan_bodies()

func _sight_rate() -> float:
	if not enemy._los or not enemy._target_alive() or director == null:
		return 0.0
	var pl := enemy._player
	var to := pl.global_position - enemy.global_position
	to.y = 0.0
	var d := to.length()
	var periph := 1.0
	if d > 0.1:
		var fwd := -enemy.global_transform.basis.z
		fwd.y = 0.0
		var ang := rad_to_deg(fwd.normalized().angle_to(to / d))
		if ang <= CONE_FULL:
			periph = 1.0
		elif ang <= CONE_HALF:
			periph = 0.45
		else:
			periph = 0.0
	if d < FEEL_RADIUS:
		periph = maxf(periph, 0.8)
	if periph <= 0.0:
		return 0.0
	var light: float = director.get("player_light")
	var r := lerpf(5.0, 34.0, light)
	if enemy._player_crouching():
		r *= 0.55
	var spd := Vector2(enemy._player_vel.x, enemy._player_vel.z).length()
	if bool(pl.get("_sprinting")):
		r *= 1.25
	elif spd < 0.3:
		r *= 0.85
	r *= float(director.call("alert_mult"))
	if d > r:
		return 0.0
	return ((1.0 - d / r) * 2.4 + 0.3) * periph

func _hear(pos: Vector3, text: String) -> void:
	_noise_cd = 2.5
	_target_pos = pos
	suspicion = maxf(suspicion, 0.4)
	if state != S.INVESTIGATE:
		_say(text)
		enemy._play_sfx("curfew_suspicion")
	_enter(S.INVESTIGATE)

func _spot() -> void:
	var pos := enemy._player.global_position
	state = S.COMBAT
	suspicion = 1.0
	_say("Da! Stehen bleiben!", 2.0)
	enemy._spotting = true
	enemy.alert(pos, true)
	enemy._spotting = false
	if director != null:
		director.call("raise_alarm", pos, "spotted", true)

func _scan_bodies() -> void:
	if director == null:
		return
	var bodies: Array = director.get("bodies")
	var eye := enemy._eye_pos()
	var fwd := -enemy.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for b: Dictionary in bodies:
		if b["found"] or b.get("claimed", null) != null:
			continue
		var bp: Vector3 = b["pos"]
		var to := bp - enemy.global_position
		to.y = 0.0
		var d := to.length()
		var light: float = director.call("light_at", bp + Vector3.UP * 0.3)
		var r := lerpf(6.0, 22.0, light)
		if d > r:
			continue
		if d > 1.5 and rad_to_deg(fwd.angle_to(to / d)) > CONE_FULL:
			continue
		if not enemy._ray(eye, bp + Vector3.UP * 0.35, 1).is_empty():
			continue
		b["claimed"] = self
		_body_target = b
		_say("Was ist das …?")
		enemy._play_sfx("curfew_suspicion")
		_enter(S.BODY)
		return

func _face(yaw: float, delta: float, speed: float = 3.0) -> void:
	enemy.rotation.y = lerp_angle(enemy.rotation.y, yaw, clampf(speed * delta, 0.0, 1.0))

func _face_point(p: Vector3, delta: float, speed: float = 4.0) -> void:
	var f := p - enemy.global_position
	f.y = 0.0
	if f.length() > 0.05:
		_face(atan2(-f.x, -f.z), delta, speed)

func _tick_patrol(delta: float) -> void:
	if route.is_empty():
		return
	var wp: Dictionary = route[_route_i]
	var p: Vector3 = wp["p"]
	if _wait_t > 0.0:
		_wait_t -= delta
		var y: float = wp.get("yaw", NAN)
		if not is_nan(y):
			# beim Warten leicht umherschauen
			_face(y + sin(_state_t * 0.5) * 0.35, delta, 2.0)
		if _wait_t <= 0.0:
			_route_i = (_route_i + 1) % route.size()
		return
	if enemy._move_to(p, patrol_speed, delta):
		_wait_t = maxf(float(wp.get("wait", 0.0)), 0.01)
		if route.size() == 1:
			_wait_t = 9999.0

func _tick_suspicious(delta: float) -> void:
	_face_point(_target_pos, delta, 5.0)
	if _unseen_t > 1.2:
		_enter(S.INVESTIGATE)
	elif suspicion < SHOW_AT * 0.5 and _state_t > 2.0:
		_return_line()

func _tick_investigate(delta: float) -> void:
	if _wait_t <= 0.0:
		if _state_t < 0.6:
			_face_point(_target_pos, delta, 5.0)   # erst hinsehen, dann losgehen
			return
		if enemy._move_to(_target_pos, 1.9, delta) or _state_t > 20.0:
			_wait_t = 4.0
			_look_base = enemy.rotation.y
		return
	_wait_t -= delta
	_face(_look_base + sin((4.0 - _wait_t) * 1.6) * 1.1, delta, 3.0)
	if _wait_t <= 0.0:
		_return_line()

func _tick_search(delta: float) -> void:
	if _search_pts.is_empty():
		_return_line()
		return
	if _wait_t > 0.0:
		_wait_t -= delta
		_face(_look_base + sin((2.5 - _wait_t) * 1.8) * 1.0, delta, 3.0)
		if _wait_t <= 0.0:
			_search_pts.remove_at(0)
		return
	if enemy._move_to(_search_pts[0], 2.6, delta) or _state_t > 25.0:
		_state_t = 0.0
		_wait_t = 2.5
		_look_base = enemy.rotation.y

func _tick_body(delta: float) -> void:
	if _body_target.is_empty() or _body_target["found"]:
		_enter(S.RETURN)
		return
	var bp: Vector3 = _body_target["pos"]
	if enemy._move_to(bp, 2.8, delta) or enemy.global_position.distance_to(bp) < 1.6 or _state_t > 15.0:
		_say("Mann am Boden! Alarm!", 2.5)
		enemy._bark("mandown", 1.0, true)
		if director != null:
			director.call("report_body", _body_target, enemy.global_position)
		_body_target = {}

func _tick_return(delta: float) -> void:
	if route.is_empty():
		_enter(S.CALM)
		return
	var p: Vector3 = route[_route_i]["p"]
	if enemy._move_to(p, patrol_speed, delta):
		_enter(S.CALM)
		_wait_t = maxf(float(route[_route_i].get("wait", 0.0)), 0.01)
		if route.size() == 1:
			_wait_t = 9999.0

func _return_line() -> void:
	var lines := ["Muss der Wind gewesen sein.", "Nichts. Ratten wahrscheinlich.", "Hier ist niemand."]
	_say(lines[randi() % lines.size()], 2.6)
	_enter(S.RETURN)

func _drop_flashlight() -> void:
	var fl := flashlight
	var lvl := enemy.get_parent()
	var gp := fl.global_position
	fl.get_parent().remove_child(fl)
	lvl.add_child(fl)
	var yaw := enemy.rotation.y + randf_range(-1.2, 1.2)
	fl.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-4.0)), Vector3(gp.x, enemy.global_position.y + 0.12, gp.z))
	fl.light_energy = 2.6
	fl.spot_range = 9.0
	fl.shadow_enabled = false
	fl.light_volumetric_fog_energy = 1.5
