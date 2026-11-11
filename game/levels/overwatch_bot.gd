extends RefCounted
## Level 7 "Kaltes Auge": Test-Bot fuer den Autopiloten (nur mit --autopilot aktiv).
## Der Player meldet autopilot_self_driven() = true, solange das Level fahren will; dann steuert dieser Bot
## ueber player.ext. Aufgaben liefert das Level (bot_task): "walk" (Wegpunkte, optional kaempfend),
## "snipe" (Position halten, Ziele ueber den Ballistik-Loeser der Waffe mit Fall/Wind/Vorhalt bekaempfen), "wait".
## Skill: novice/average/veteran -> Zielfehler (mrad) und Ruhezeit vor dem Schuss.

const GRAV := 9.81

var lv: Node3D
var pl: Node3D
var skill: String = "average"
var rng := RandomNumberGenerator.new()

var _route_key: String = ""
var _ri: int = 0
var _stuck_t: float = 0.0
var _stuck_ref: Vector3 = Vector3.ZERO
var _stuck_check: float = 0.0
var _target: Node3D = null
var _aim_t: float = 0.0
var _err: Vector2 = Vector2.ZERO          # mrad
var _err_drift: Vector2 = Vector2.ZERO
var _fire_cd: float = 0.0
var _scan_t: float = 0.0
var _engage: Node3D = null
var _shots_at_target: int = 0
var _log_t: float = 0.0

var _err_mrad: float = 0.5
var _settle: float = 1.2

func setup(level: Node3D, player: Node3D) -> void:
	lv = level
	pl = player
	skill = str(Game.arg("skill", "average"))
	rng.seed = int(Game.arg("seed", 7)) if Game.arg("seed", null) != null else 2030
	match skill:
		"novice":
			_err_mrad = 0.9
			_settle = 2.0
		"veteran":
			_err_mrad = 0.3
			_settle = 0.8
		_:
			_err_mrad = 0.5
			_settle = 1.25
	if not Events.player_respawned.is_connected(_on_respawn):
		Events.player_respawned.connect(_on_respawn)

func _on_respawn() -> void:
	_route_key = ""
	_target = null
	_engage = null

func _ext() -> Dictionary:
	return pl.get("ext")

func _neutral(e: Dictionary) -> void:
	e["move"] = Vector2.ZERO
	e["look"] = Vector2.ZERO
	e["fire"] = false
	e["aim"] = false
	e["sprint"] = false
	e["crouch"] = false
	e["prone"] = false

func tick(delta: float) -> void:
	if pl == null or not is_instance_valid(pl):
		return
	pl.set("external_input", true)
	var e := _ext()
	_neutral(e)
	if not bool(pl.call("is_alive")):
		return
	_fire_cd = maxf(0.0, _fire_cd - delta)
	var task: Dictionary = lv.call("bot_task")
	var kind: String = str(task.get("kind", "wait"))
	match kind:
		"walk":
			_walk(e, task, delta)
		"snipe":
			_snipe(e, task, delta)
		_:
			pass
	_reload_if_empty(e)

func _reload_if_empty(e: Dictionary) -> void:
	var w: Node = pl.get("weapon")
	if w != null and int(w.get("ammo_mag")) <= 0 and not bool(w.get("reloading")):
		e["reload"] = true
		e["fire"] = false

# ------------------------------------------------------------------ Laufen

func _walk(e: Dictionary, task: Dictionary, delta: float) -> void:
	var path: Array = task.get("path", [])
	if path.is_empty():
		return
	var key: String = str(task.get("key", "route"))
	if key != _route_key:
		_route_key = key
		_ri = _nearest_ahead(path)
		_stuck_t = 0.0
		_stuck_ref = pl.global_position
	if bool(task.get("fight", false)):
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = 0.25
			_engage = _find_threat(float(task.get("fight_range", 65.0)))
		if _engage != null and is_instance_valid(_engage) and bool(_engage.call("is_alive")):
			_shoot_at(e, _engage, delta, false)
			return
	if _ri >= path.size():
		if task.has("face"):
			_look_at(task["face"] as Vector3, 0.0)
		return
	var tgt: Vector3 = path[_ri]
	var pos := pl.global_position
	var flat := Vector2(tgt.x - pos.x, tgt.z - pos.z)
	var reach: float = 0.45 if _ri < path.size() - 1 else 0.35
	if flat.length() < reach and absf(tgt.y - pos.y) < 1.4:
		_ri += 1
		return
	var yaw := rad_to_deg(atan2(-flat.x, -flat.y))
	pl.call("set_view", yaw, -4.0)
	e["move"] = Vector2(0.0, 1.0 if flat.length() > 0.25 else 0.4)
	e["sprint"] = bool(task.get("sprint", false)) and flat.length() > 4.0
	# Festhaengen: springen, dann (Testhilfe) auf den Wegpunkt setzen
	_stuck_check -= delta
	if _stuck_check <= 0.0:
		_stuck_check = 1.0
		if pos.distance_to(_stuck_ref) < 0.35:
			_stuck_t += 1.0
			e["jump"] = true
		else:
			_stuck_t = 0.0
		_stuck_ref = pos
	if _stuck_t >= 4.0:
		print("[ow-bot] haengt bei %s -> Wegpunkt %d" % [str(pos), _ri])
		pl.global_position = tgt + Vector3(0, 0.1, 0)
		_stuck_t = 0.0

func _nearest_ahead(path: Array) -> int:
	var pos := pl.global_position
	var best := 0
	var bd := INF
	for i in path.size():
		var p: Vector3 = path[i]
		var d := pos.distance_to(p)
		if d < bd:
			bd = d
			best = i
	# Liegt der naechste Punkt hinter uns (Richtung zum Folgepunkt zeigt weg), gleich weiter
	if best < path.size() - 1:
		var a: Vector3 = path[best]
		var b: Vector3 = path[best + 1]
		if (b - a).dot(pos - a) > 0.0:
			best += 1
	return best

# ------------------------------------------------------------------ Schiessen

func _snipe(e: Dictionary, task: Dictionary, delta: float) -> void:
	var spot: Vector3 = task.get("pos", pl.global_position)
	var pos := pl.global_position
	var flat := Vector2(spot.x - pos.x, spot.z - pos.z)
	if flat.length() > 0.7:
		_walk(e, {"path": [spot], "key": "spot_%s" % str(spot)}, delta)
		return
	var targets: Array = task.get("targets", [])
	_aim_h = float(task.get("aim_h", -1.0))
	var t: Node3D = null
	for n in targets:
		if n is Node3D and is_instance_valid(n) and bool(n.call("is_alive")):
			t = n
			break
	if t == null:
		_target = null
		if bool(task.get("hide", false)):
			e["prone"] = true
		if task.has("face"):
			_look_at(task["face"] as Vector3, 0.0)
		if bool(task.get("preaim", false)):
			e["aim"] = true      # Zielfernrohr oben halten, bis das Ziel auftaucht
		return
	_shoot_at(e, t, delta, true)

func _shoot_at(e: Dictionary, t: Node3D, delta: float, scoped: bool) -> void:
	if t != _target:
		_target = t
		_aim_t = 0.0
		_shots_at_target = 0
		_err = Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * _err_mrad * 1.6
		_err_drift = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	_aim_t += delta
	# Zielfehler zieht sich beim Ruhigwerden zusammen, bleibt aber nie null
	var settle_k := clampf(_aim_t / _settle, 0.0, 1.0)
	var jitter := Vector2(sin(_aim_t * 1.7 + _err_drift.x * 3.0), cos(_aim_t * 1.3 + _err_drift.y * 3.0)) * _err_mrad * 0.6
	var err := _err * (1.0 - 0.6 * settle_k) + jitter
	var cam: Camera3D = pl.call("get_camera")
	var from: Vector3 = cam.global_position
	var aim := _aim_point(t)
	var d := from.distance_to(aim)
	var vel: Vector3 = t.get("velocity") if t.get("velocity") is Vector3 else Vector3.ZERO
	var w: Node = pl.get("weapon")
	if w != null and w.has_method("solve_aim"):
		# Ballistik-Loeser der Waffe: Fall mit Luftwiderstand, Nullpunkt, aktueller Wind und Vorhalt
		aim = w.call("solve_aim", from, aim, vel)
	else:
		var tof := d / 790.0
		var tof0 := 150.0 / 790.0
		var lift := 0.5 * GRAV * tof0 * tof0 / 150.0
		var drop := 0.5 * GRAV * tof * tof - lift * d
		aim += Vector3.UP * drop + vel * tof
	var dv := aim - from
	var yaw := rad_to_deg(atan2(-dv.x, -dv.z))
	var pitch := rad_to_deg(atan2(dv.y, Vector2(dv.x, dv.z).length()))
	var sway := Vector2.ZERO
	if w != null and w.get("_sway_off") is Vector2:
		sway = w.get("_sway_off")
	pl.call("set_view", yaw - sway.x + rad_to_deg(err.x * 0.001), pitch - sway.y + rad_to_deg(err.y * 0.001))
	e["aim"] = true
	var ads: float = float(w.get("scoped_amount")) if w != null and w.get("scoped_amount") != null else 1.0
	var steady: bool = w == null or w.get("holding_breath") == null or bool(w.get("holding_breath")) or float(w.get("_exhausted")) > 0.0
	e["sprint"] = ads > 0.5 and _aim_t > _settle * 0.4     # Atem anhalten
	if not scoped and d < 30.0:
		steady = true
	if _aim_t >= _settle and ads > 0.9 and steady and _fire_cd <= 0.0 and _clear_of_friendlies(from, aim):
		e["fire"] = true
		_fire_cd = 0.75
		_shots_at_target += 1
		_aim_t = _settle * 0.35
		_err = Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * _err_mrad

var _aim_h: float = -1.0

func _aim_point(t: Node3D) -> Vector3:
	if _aim_h > 0.0:
		return t.global_position + Vector3.UP * _aim_h
	var st: float = 0.0
	if t.get("_stance") != null:
		st = float(t.get("_stance"))
	return t.global_position + Vector3.UP * lerpf(1.3, 0.85, st)

func _clear_of_friendlies(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * 2.0, 1 | 4, [pl.get_rid()])
	var r: Dictionary = pl.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return true
	var c: Object = r.collider
	if c is Node and (c as Node).has_method("get_enemy"):
		c = (c as Node).call("get_enemy")
	return not (c is Node and (c as Node).is_in_group("friendly"))

func _find_threat(rng_max: float) -> Node3D:
	var cam: Camera3D = pl.call("get_camera")
	var from := cam.global_position
	var best: Node3D = null
	var bd := rng_max
	for n in pl.get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or not bool(n.call("is_alive")):
			continue
		var p := (n as Node3D).global_position + Vector3.UP * 1.2
		var d := from.distance_to(p)
		if d >= bd:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, p, 1, [pl.get_rid()])
		if not pl.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		bd = d
		best = n
	return best

func _look_at(p: Vector3, _pitch_bias: float) -> void:
	var cam: Camera3D = pl.call("get_camera")
	var dv := p - cam.global_position
	pl.call("set_view", rad_to_deg(atan2(-dv.x, -dv.z)), rad_to_deg(atan2(dv.y, Vector2(dv.x, dv.z).length())))
