class_name Cutscene
extends Node
## Zwischensequenz in der Engine (Welle 4): deklarative Folge von Schritten, die nacheinander abgespielt wird.
##
##   var cs := Cutscene.new()
##   cs.shot(Vector3(2, 1.7, 6), Vector3(1, 1.6, 3), 4.0, {"look": weber, "look_offset": Vector3(0, 1.6, 0),
##           "fov": 45.0, "shake": 0.4, "dof": true, "async": true})
##   cs._say(SD.WEBER, "Kerner. Sie geben nicht auf, was?")     # wartet, bis die Zeile durch ist
##   cs.walk_to(weber, Vector3(0, 0, -4), 2.5)
##   cs.call_step(func(): door.open(), true)                      # true = auch beim Überspringen ausführen
##   var skipped: bool = await cs.play(self)                      # self = Level (Elternknoten)
##
## Während der Sequenz: eigene Camera3D ist aktiv, Letterbox (Events.story_cinematic), HUD + Viewmodel aus,
## Spielereingabe gesperrt (external_input + leeres ext). Überspringen: Esc / Leertaste / Enter / Pad-Start halten
## (SKIP_HOLD s, Fortschrittsring). Danach wird alles wiederhergestellt und die Spielerkamera wieder aktiv.
## Sofort übersprungen (ohne Kamera/HUD/Eingabe anzufassen): --autopilot, --skip-cutscenes, --no-cutscenes
## oder Settings "game/skip_cutscenes" = true.
##
## Zeilen: Methode heißt bewusst `_say(SD.X, "…")` – tools/voice_lines.py findet nur `_say(`/`_radio(`-Aufrufe.
## Beim Überspringen entfallen noch nicht gesprochene Zeilen (außer opts.essential), laufende werden abgebrochen.

signal finished(skipped: bool)

const SKIP_HOLD := 0.8
const RING_RADIUS := 22.0

## Optionen der ganzen Sequenz (vor play() setzen oder per set_option())
var letterbox: bool = true
var keep_letterbox: bool = false    # am Ende KEIN story_cinematic(false) senden (Level macht danach selbst Kino weiter)
var hide_hud: bool = true
var lock_input: bool = true
var skippable: bool = true
var keep_fade: bool = false         # Abblende am Ende stehen lassen (Schwarzbild bis zum Levelende/Epilog)

var _steps: Array[Dictionary] = []
var _level: Node = null
var _player = null                  # Player (untypisiert: dynamischer Zugriff auf external_input/ext)
var _cam: Camera3D = null
var _attrs: CameraAttributesPractical = null
var _running: bool = false
var _skipping: bool = false
var _skipped: bool = false
var _active: int = 0                # laufende asynchrone Schritte
var _time: float = 0.0
var _restore: Dictionary = {}

# Kamera-Zustand (wird jeden Frame in _process angewendet)
var _base: Transform3D = Transform3D.IDENTITY
var _look_a: Dictionary = {}        # {"t": Node3D|Vector3, "off": Vector3} – Blickziel am Shot-Anfang
var _look_b: Dictionary = {}        # aktuelles Blickziel
var _look_k: float = 1.0
var _shake: float = 0.0
var _dof: Variant = null            # null = aus, float = feste Schärfeentfernung, true = Autofokus aufs Blickziel

# Überspringen
var _held: Dictionary = {}
var _hold: float = 0.0
var _ui: CanvasLayer = null
var _ring: _Ring = null
var _hint: Label = null
var _last_line_end: float = -1.0
var _fade: ColorRect = null


# ================================================================= Builder (alle geben self zurück)

## Kamerafahrt. from/to: Transform3D, Node3D (dessen Transform), Vector3 (nur Position) oder null (= aktuelle Kamera).
## opts: fov (Ziel), fov_from, look (Node3D|Vector3), look_offset, ease (Tween.EASE_*), trans (Tween.TRANS_*),
##       path (Array[Vector3] Zwischenpunkte, Catmull-Rom), shake (0..1 Handkamera), dof (float|true|false),
##       async (true = nicht warten, nächste Schritte laufen parallel)
func shot(from: Variant, to: Variant, duration: float, opts: Dictionary = {}) -> Cutscene:
	_steps.append({"k": "shot", "from": from, "to": to, "dur": maxf(duration, 0.0), "o": opts,
		"async": bool(opts.get("async", false))})
	return self

## Harter Schnitt auf eine Einstellung (Position/Transform + optional Blickziel).
func cut(where: Variant, opts: Dictionary = {}) -> Cutscene:
	var o := opts.duplicate()
	o["async"] = false
	return shot(where, where, 0.0, o)

## Funkzeile über das Untertitel-System. opts: dur (Anzeigedauer, 0 = automatisch), async (nicht warten),
## essential (wird auch beim Überspringen gesendet), hold (zusätzliche Pause danach)
func _say(speaker: String, text: String, opts: Dictionary = {}) -> Cutscene:
	_steps.append({"k": "say", "speaker": speaker, "text": text, "dur": float(opts.get("dur", 0.0)),
		"async": bool(opts.get("async", false)), "essential": bool(opts.get("essential", false)),
		"hold": float(opts.get("hold", 0.0))})
	return self

func say(speaker: String, text: String, opts: Dictionary = {}) -> Cutscene:
	return _say(speaker, text, opts)

func wait(seconds: float) -> Cutscene:
	_steps.append({"k": "wait", "t": seconds, "async": false})
	return self

## Wartet, bis das Untertitel-System alle Zeilen gezeigt hat (max. max_t s).
func wait_radio(max_t: float = 15.0) -> Cutscene:
	_steps.append({"k": "wait_radio", "t": max_t, "async": false})
	return self

## Beliebiger Aufruf. always = true: wird auch beim Überspringen ausgeführt (Zustand, den der Ablauf braucht).
func call_step(fn: Callable, always: bool = false) -> Cutscene:
	_steps.append({"k": "call", "fn": fn, "always": always, "async": false})
	return self

## Puppe läuft linear zu pos (global), dreht sich in Laufrichtung. Beim Überspringen: sofort am Ziel.
func walk_to(puppet: Node3D, pos: Vector3, duration: float, opts: Dictionary = {}) -> Cutscene:
	_steps.append({"k": "walk", "n": puppet, "pos": pos, "dur": duration,
		"face": bool(opts.get("face", true)), "async": bool(opts.get("async", true))})
	return self

## Puppe dreht sich (Gier) zum Ziel (Node3D oder Vector3).
func aim(puppet: Node3D, target: Variant, duration: float = 0.4, opts: Dictionary = {}) -> Cutscene:
	_steps.append({"k": "aim", "n": puppet, "target": target, "dur": duration,
		"async": bool(opts.get("async", true))})
	return self

## Pose: Eigenschaft eines Knotens tweenen, z. B. pose(arms, "rotation:x", PI * 0.9, 1.2).
func pose(node: Node, property: String, value: Variant, duration: float = 0.5, opts: Dictionary = {}) -> Cutscene:
	_steps.append({"k": "pose", "n": node, "prop": property, "val": value, "dur": duration,
		"async": bool(opts.get("async", true))})
	return self

## Bild ab-/aufblenden (alpha 1 = schwarz). async = true: nicht warten.
func fade(alpha: float, duration: float = 0.6, opts: Dictionary = {}) -> Cutscene:
	_steps.append({"k": "fade", "a": alpha, "dur": duration, "col": opts.get("color", Color.BLACK),
		"async": bool(opts.get("async", false))})
	return self

func set_option(key: String, value: Variant) -> Cutscene:
	set(key, value)
	return self


# ================================================================= Abspielen

## Spielt die Sequenz als Kind von `level` ab. Rückgabe (await): true = übersprungen.
func play(level: Node) -> bool:
	_level = level
	if not is_inside_tree():
		level.add_child(self)
	_player = level.get("player") if "player" in level else null
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if instant_skip():
		_skipping = true
		_skipped = true
		for s in _steps:
			_skip_step(s)
		finished.emit(true)
		queue_free()
		return true
	_begin()
	print("[cutscene] Start (%d Schritte)" % _steps.size())
	for s in _steps:
		if not is_inside_tree():
			return _skipped
		if _skipping:
			_skip_step(s)
		elif s["async"]:
			_exec(s)
		else:
			await _exec(s)
	while _active > 0 and not _skipping and is_inside_tree():
		await get_tree().process_frame
	_end()
	print("[cutscene] Ende%s nach %.1f s" % [" (übersprungen)" if _skipped else "", _time])
	finished.emit(_skipped)
	queue_free()
	return _skipped

## Von außen abbrechen (Tests, Level-Ereignis).
func request_skip() -> void:
	if not _running or _skipping:
		return
	_skipping = true
	_skipped = true
	if _time < _last_line_end + 0.3:
		get_tree().call_group(&"story_ui", &"interrupt")

func is_running() -> bool:
	return _running

func get_camera() -> Camera3D:
	return _cam

## true, wenn Sequenzen sofort übersprungen werden sollen (Autopilot/Sim, Debug-Arg, Einstellung).
static func instant_skip() -> bool:
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	var g: Node = root.get_node_or_null("Game")
	if g != null:
		for k in ["autopilot", "skip-cutscenes", "no-cutscenes"]:
			if str(g.call("arg", k, "")) not in ["", "false", "0"]:
				return true
	var st: Node = root.get_node_or_null("Settings")
	if st != null and bool(st.call("get_value", "game/skip_cutscenes", false)):
		return true
	return false


# ================================================================= Ablauf intern

func _begin() -> void:
	_running = true
	var pcam: Camera3D = _player_cam()
	_cam = Camera3D.new()
	_cam.name = "CutsceneCam"
	add_child(_cam)
	_cam.top_level = true
	if pcam != null:
		_cam.fov = pcam.fov
		_cam.near = pcam.near
		_cam.far = pcam.far
		_cam.cull_mask = pcam.cull_mask
		_base = pcam.global_transform
	_cam.global_transform = _base
	_cam.current = true
	if letterbox:
		Events.story_cinematic.emit(true)
	if _player != null:
		if hide_hud:
			for n in ["HUD", "WeaponLayer"]:
				var layer := _player.get_node_or_null(n) as CanvasLayer
				if layer != null:
					_restore[n] = layer.visible
					layer.visible = false
		if lock_input and "external_input" in _player:
			_restore["external_input"] = _player.external_input
			_player.external_input = true
			_clear_ext()
	if skippable:
		_build_skip_ui()

func _end() -> void:
	_running = false
	if _player != null and is_instance_valid(_player):
		for n in ["HUD", "WeaponLayer"]:
			if _restore.has(n):
				var layer := _player.get_node_or_null(n) as CanvasLayer
				if layer != null:
					layer.visible = _restore[n]
		if _restore.has("external_input"):
			_clear_ext()
			_player.external_input = _restore["external_input"]
	var pcam: Camera3D = _player_cam()
	if _cam != null:
		_cam.current = false
	if pcam != null:
		pcam.current = true
	if _cam != null:
		_cam.queue_free()
		_cam = null
	if letterbox and not keep_letterbox:
		Events.story_cinematic.emit(false)
	if _ui != null:
		_ui.queue_free()
		_ui = null
	if _fade != null:
		var layer := _fade.get_parent()
		if keep_fade and _fade.color.a > 0.01 and _level != null and is_instance_valid(_level):
			layer.reparent(_level)     # Schwarzbild bleibt, bis das Level endet
		else:
			layer.queue_free()
		_fade = null

func _player_cam() -> Camera3D:
	if _player == null or not is_instance_valid(_player):
		return null
	if _player.has_method("get_camera"):
		return _player.call("get_camera") as Camera3D
	return _player.get_node_or_null("Head/Camera3D") as Camera3D

func _clear_ext() -> void:
	if _player == null or not ("ext" in _player):
		return
	var e: Dictionary = _player.ext
	for k in e.keys():
		var v: Variant = e[k]
		if v is Vector2:
			e[k] = Vector2.ZERO
		elif v is bool:
			e[k] = false
	e.erase("weapon")

func _exec(s: Dictionary) -> void:
	var is_async: bool = s["async"]
	if is_async:
		_active += 1
	match String(s["k"]):
		"shot":
			await _run_shot(s)
		"say":
			await _run_say(s)
		"wait":
			await _sleep(float(s["t"]))
		"wait_radio":
			await _wait_ui_idle(float(s["t"]))
		"call":
			var fn: Callable = s["fn"]
			if fn.is_valid():
				fn.call()
		"walk":
			await _run_walk(s)
		"aim":
			await _run_aim(s)
		"pose":
			await _run_pose(s)
		"fade":
			await _run_fade(s)
	if is_async:
		_active -= 1

## Endzustand eines Schritts ohne Abspielen herstellen (Überspringen / Autopilot).
func _skip_step(s: Dictionary) -> void:
	match String(s["k"]):
		"say":
			if s["essential"]:
				Events.story_radio.emit(s["speaker"], s["text"], s["dur"])
		"call":
			var fn: Callable = s["fn"]
			if s["always"] and fn.is_valid():
				fn.call()
		"walk":
			var n: Node3D = s["n"]
			if is_instance_valid(n):
				_face(n, s["pos"])
				n.global_position = s["pos"]
		"aim":
			var n2: Node3D = s["n"]
			if is_instance_valid(n2):
				_face(n2, _point(s["target"], Vector3.ZERO))
		"pose":
			var n3: Node = s["n"]
			if is_instance_valid(n3):
				n3.set_indexed(NodePath(s["prop"]), s["val"])
		"fade":
			if _running:
				var fr := _fade_rect(s["col"])
				fr.color.a = float(s["a"])

func _sleep(t: float) -> void:
	var e := 0.0
	while e < t and not _skipping and is_inside_tree():
		await get_tree().process_frame
		e += get_process_delta_time()

func _story_ui() -> Node:
	return get_tree().get_first_node_in_group(&"story_ui") if is_inside_tree() else null

func _ui_busy() -> bool:
	var ui := _story_ui()
	if ui == null:
		return false
	return bool(ui.get("_showing")) or not (ui.get("_queue") as Array).is_empty()

func _wait_ui_idle(max_t: float) -> void:
	var e := 0.0
	while e < max_t and not _skipping and is_inside_tree():
		if e > 0.15 and not _ui_busy():
			return
		await get_tree().process_frame
		e += get_process_delta_time()

func _run_say(s: Dictionary) -> void:
	var text: String = s["text"]
	var speaker: String = s["speaker"]
	var est: float = float(s["dur"]) if float(s["dur"]) > 0.0 else StoryUI.auto_duration(text)
	var vs: AudioStream = StoryUI.voice_stream(speaker, text)
	if vs != null:
		est = maxf(est, vs.get_length() + 0.6)
	Events.story_radio.emit(speaker, text, float(s["dur"]))
	_last_line_end = maxf(_last_line_end, _time) + est
	if s["async"]:
		return
	if _story_ui() != null:
		# Warteschlange kann ältere Zeilen enthalten -> Obergrenze großzügig
		await _wait_ui_idle(est + 8.0)
	else:
		await _sleep(est)
	if float(s["hold"]) > 0.0:
		await _sleep(float(s["hold"]))

func _run_shot(s: Dictionary) -> void:
	var o: Dictionary = s["o"]
	# from = null: an der tatsächlich gezeigten Einstellung weitermachen (inkl. Blickrichtung eines Blickziels)
	var cur: Transform3D = _base
	if not _look_b.is_empty() and _cam != null:
		cur = Transform3D(_cam.global_transform.basis.orthonormalized(), _base.origin)
	var a: Transform3D = _to_xf(s["from"], cur)
	var b: Transform3D = _to_xf(s["to"], a)
	var dur: float = s["dur"]
	var ease_t := int(o.get("ease", Tween.EASE_IN_OUT)) as Tween.EaseType
	var trans_t := int(o.get("trans", Tween.TRANS_SINE)) as Tween.TransitionType
	var pts: Array = [a.origin]
	for p in o.get("path", []):
		pts.append(p)
	pts.append(b.origin)
	var fov_a: float = float(o.get("fov_from", _cam.fov))
	var fov_b: float = float(o.get("fov", fov_a))
	if o.has("shake"):
		_shake = float(o["shake"])
	if o.has("dof"):
		_set_dof(o["dof"])
	# Blickziel: weich vom bisherigen Ziel zum neuen schwenken (bei Schnitt sofort)
	if o.has("look"):
		var nl := {"t": o["look"], "off": o.get("look_offset", Vector3.ZERO)}
		_look_a = _look_b if (dur > 0.0 and not _look_b.is_empty()) else {}
		_look_b = nl
		_look_k = 0.0 if not _look_a.is_empty() else 1.0
	elif bool(o.get("free", false)):
		_look_a = {}
		_look_b = {}
	if dur <= 0.0:
		_base = b
		_base.origin = pts[-1]
		_cam.fov = fov_b
		_look_k = 1.0
		return
	var e := 0.0
	while e < dur and not _skipping and is_inside_tree():
		var k: float = Tween.interpolate_value(0.0, 1.0, e, dur, trans_t, ease_t)
		_base = Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), k)),
			_path_point(pts, k))
		_cam.fov = lerpf(fov_a, fov_b, k)
		if not _look_a.is_empty():
			_look_k = k
		await get_tree().process_frame
		e += get_process_delta_time()
	_base = Transform3D(b.basis, pts[-1])
	_cam.fov = fov_b
	_look_k = 1.0

func _run_walk(s: Dictionary) -> void:
	var n: Node3D = s["n"]
	if not is_instance_valid(n):
		return
	var from: Vector3 = n.global_position
	var to: Vector3 = s["pos"]
	if s["face"]:
		_face(n, to)
	var dur: float = maxf(float(s["dur"]), 0.01)
	var e := 0.0
	while e < dur and not _skipping and is_instance_valid(n) and is_inside_tree():
		n.global_position = from.lerp(to, e / dur)
		await get_tree().process_frame
		e += get_process_delta_time()
	if is_instance_valid(n):
		n.global_position = to

func _run_aim(s: Dictionary) -> void:
	var n: Node3D = s["n"]
	if not is_instance_valid(n):
		return
	var p: Vector3 = _point(s["target"], Vector3.ZERO)
	var d: Vector3 = p - n.global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var y0: float = n.global_rotation.y
	var y1: float = atan2(-d.x, -d.z)
	var dur: float = maxf(float(s["dur"]), 0.01)
	var e := 0.0
	while e < dur and not _skipping and is_instance_valid(n) and is_inside_tree():
		n.global_rotation.y = lerp_angle(y0, y1, e / dur)
		await get_tree().process_frame
		e += get_process_delta_time()
	if is_instance_valid(n):
		n.global_rotation.y = y1

func _run_pose(s: Dictionary) -> void:
	var n: Node = s["n"]
	if not is_instance_valid(n):
		return
	var path := NodePath(s["prop"])
	var v0: Variant = n.get_indexed(path)
	var v1: Variant = s["val"]
	var dur: float = maxf(float(s["dur"]), 0.01)
	var e := 0.0
	while e < dur and not _skipping and is_instance_valid(n) and is_inside_tree():
		n.set_indexed(path, Tween.interpolate_value(v0, v1 - v0, e, dur, Tween.TRANS_SINE, Tween.EASE_IN_OUT))
		await get_tree().process_frame
		e += get_process_delta_time()
	if is_instance_valid(n):
		n.set_indexed(path, v1)

func _fade_rect(col: Color) -> ColorRect:
	if _fade == null:
		var layer := CanvasLayer.new()
		layer.name = "CutsceneFade"
		layer.layer = 24
		add_child(layer)
		_fade = ColorRect.new()
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.color = Color(col.r, col.g, col.b, 0.0)
		layer.add_child(_fade)
	else:
		_fade.color = Color(col.r, col.g, col.b, _fade.color.a)
	return _fade

func _run_fade(s: Dictionary) -> void:
	var r := _fade_rect(s["col"])
	var a0: float = r.color.a
	var a1: float = s["a"]
	var dur: float = maxf(float(s["dur"]), 0.01)
	var e := 0.0
	while e < dur and not _skipping and is_inside_tree():
		r.color.a = lerpf(a0, a1, e / dur)
		await get_tree().process_frame
		e += get_process_delta_time()
	r.color.a = a1

## Figur (Gier) zu einem Punkt drehen. Konvention wie Player: Blickrichtung -Z.
func _face(n: Node3D, p: Vector3) -> void:
	var d: Vector3 = p - n.global_position
	if Vector2(d.x, d.z).length() > 0.01:
		n.global_rotation.y = atan2(-d.x, -d.z)


# ================================================================= Kamera

func _to_xf(v: Variant, fallback: Transform3D) -> Transform3D:
	if v is Transform3D:
		return v
	if v is Node3D and is_instance_valid(v):
		return (v as Node3D).global_transform
	if v is Vector3:
		return Transform3D(fallback.basis, v)
	return fallback

func _point(t: Variant, off: Vector3) -> Vector3:
	if t is Node3D and is_instance_valid(t):
		return (t as Node3D).global_position + off
	if t is Vector3:
		return t + off
	return Vector3.ZERO

func _look_point() -> Vector3:
	var pb: Vector3 = _point(_look_b["t"], _look_b["off"])
	if _look_a.is_empty() or _look_k >= 1.0:
		return pb
	return _point(_look_a["t"], _look_a["off"]).lerp(pb, _look_k)

## Catmull-Rom durch alle Punkte, k in 0..1 (gleich lange Segmente)
func _path_point(pts: Array, k: float) -> Vector3:
	var n: int = pts.size()
	if n == 2:
		return (pts[0] as Vector3).lerp(pts[1], k)
	var f: float = clampf(k, 0.0, 1.0) * float(n - 1)
	var i: int = mini(int(f), n - 2)
	var t: float = f - float(i)
	var p0: Vector3 = pts[maxi(i - 1, 0)]
	var p1: Vector3 = pts[i]
	var p2: Vector3 = pts[i + 1]
	var p3: Vector3 = pts[mini(i + 2, n - 1)]
	return p1.cubic_interpolate(p2, p0, p3, t)

func _set_dof(v: Variant) -> void:
	if v == null or (v is bool and not v):
		_dof = null
		if _cam != null:
			_cam.attributes = null
		return
	_dof = v
	if _attrs == null:
		var base: CameraAttributes = null
		var pcam := _player_cam()
		if pcam != null and pcam.attributes != null:
			base = pcam.attributes
		elif _cam.get_world_3d() != null and _cam.get_world_3d().camera_attributes != null:
			base = _cam.get_world_3d().camera_attributes
		_attrs = (base.duplicate() as CameraAttributesPractical) if base is CameraAttributesPractical \
			else CameraAttributesPractical.new()
		if not (base is CameraAttributesPractical):
			_attrs.auto_exposure_enabled = false
		_attrs.dof_blur_amount = 0.07
	_cam.attributes = _attrs

func _update_dof() -> void:
	if _dof == null or _attrs == null:
		return
	var focus: float = float(_dof) if (_dof is float or _dof is int) else \
		(_cam.global_position.distance_to(_look_point()) if not _look_b.is_empty() else 6.0)
	focus = maxf(focus, 0.5)
	_attrs.dof_blur_far_enabled = true
	_attrs.dof_blur_far_distance = focus + maxf(1.0, focus * 0.25)
	_attrs.dof_blur_far_transition = maxf(2.0, focus * 0.8)
	_attrs.dof_blur_near_enabled = focus > 2.0
	_attrs.dof_blur_near_distance = focus * 0.45
	_attrs.dof_blur_near_transition = maxf(0.3, focus * 0.3)

func _process(delta: float) -> void:
	if not _running:
		return
	_time += delta
	if _cam != null:
		var xf: Transform3D = _base
		if not _look_b.is_empty():
			var lp: Vector3 = _look_point()
			var d: Vector3 = lp - xf.origin
			if d.length() > 0.01:
				var up: Vector3 = Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.FORWARD
				xf.basis = Basis.looking_at(d, up)
		if _shake > 0.0:
			# Handkamera: langsames, unregelmäßiges Schwanken (Summe von Sinus, kein Rauschen nötig)
			var t := _time
			var yaw := (sin(t * 1.3) * 0.6 + sin(t * 2.9 + 1.7) * 0.3 + sin(t * 7.1) * 0.08) * _shake
			var pit := (sin(t * 1.1 + 0.4) * 0.5 + sin(t * 3.3 + 2.2) * 0.3 + sin(t * 6.3) * 0.08) * _shake
			var rol := sin(t * 0.9 + 3.0) * 0.4 * _shake
			xf.basis = xf.basis * Basis.from_euler(Vector3(deg_to_rad(pit), deg_to_rad(yaw), deg_to_rad(rol)))
		_cam.global_transform = xf
		_update_dof()
	if skippable and not _skipping:
		if _held.is_empty():
			_hold = maxf(0.0, _hold - delta * 2.5)
		else:
			_hold += delta
			if _hold >= SKIP_HOLD:
				request_skip()
	if _ring != null:
		_ring.progress = clampf(_hold / SKIP_HOLD, 0.0, 1.0)
		_ring.queue_redraw()
	if _hint != null:
		_hint.modulate.a = 0.85 if _hold > 0.0 else clampf(0.55 - maxf(0.0, _time - 4.0) * 0.1, 0.25, 0.55)

func _physics_process(_delta: float) -> void:
	if _running and _restore.has("external_input") and _player != null and is_instance_valid(_player):
		_player.external_input = true
		_clear_ext()


# ================================================================= Überspringen (Halten)

func _input(event: InputEvent) -> void:
	if not _running or not skippable:
		return
	var id: String = ""
	if event is InputEventKey and not (event as InputEventKey).echo:
		var kc: int = (event as InputEventKey).physical_keycode
		if kc == 0:
			kc = (event as InputEventKey).keycode
		if kc in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			id = "k%d" % kc
	elif event is InputEventJoypadButton:
		var b: int = (event as InputEventJoypadButton).button_index
		if b in [JOY_BUTTON_START, JOY_BUTTON_B]:
			id = "j%d" % b
	if id == "":
		return
	if event.is_pressed():
		_held[id] = true
	else:
		_held.erase(id)
	# Esc darf während der Sequenz nicht das Pausemenü öffnen
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_held.clear()

func _build_skip_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "CutsceneSkip"
	_ui.layer = 25
	add_child(_ui)
	var box := HBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -330.0
	box.offset_right = -28.0
	box.offset_top = -64.0
	box.offset_bottom = -14.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(box)
	_hint = Label.new()
	_hint.text = "Leertaste / Esc halten: überspringen"
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.size_flags_vertical = Control.SIZE_FILL
	box.add_child(_hint)
	_ring = _Ring.new()
	_ring.custom_minimum_size = Vector2(RING_RADIUS * 2.0 + 6.0, RING_RADIUS * 2.0 + 6.0)
	box.add_child(_ring)


class _Ring extends Control:
	var progress: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(c.x, c.y) - 3.0
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.22), 3.0, true)
		if progress > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, Color(1.0, 0.86, 0.45, 0.95), 4.0, true)
		# kleines "Vorspul"-Symbol in der Mitte
		var s := r * 0.32
		var col := Color(1, 1, 1, 0.5 + 0.5 * progress)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.1, -s), c + Vector2(0, 0), c + Vector2(-s * 1.1, s)]), col)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 1.1, 0), c + Vector2(0, s)]), col)
