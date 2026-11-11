extends RefCounted
## Level 10 "Stimme der Ordnung": Test-Bot fuer den Autopiloten (nur mit --autopilot aktiv).
## Das Level meldet bot_drives_player() = true und liefert Aufgaben (bot_task):
##   walk  -> Wegpunkte ablaufen, optional kaempfen
##   hold  -> am Sendepult stehen bleiben, sichtbare Gegner bekaempfen, sonst Schalter halten
##   heli  -> Panzerfaust holen, auf die Terrasse, Hubschrauber mit Vorhalt bekaempfen
##   ride  -> im Lift stillstehen
## Skill: novice/average/veteran -> Zielfehler (Grad) und Reaktionszeit.

const ROCKET_SPEED := 72.0
const ROCKET_GRAV := 2.2

var lv: Node3D
var pl: Node3D
var skill: String = "average"
var rng := RandomNumberGenerator.new()

var _route_key: String = ""
var _ri: int = 0
var _stuck_t: float = 0.0
var _stuck_ref: Vector3 = Vector3.ZERO
var _stuck_check: float = 0.0
var _scan_t: float = 0.0
var _engage: Node3D = null
var _target: Node3D = null
var _aim_t: float = 0.0
var _burst_t: float = 0.0
var _err: Vector2 = Vector2.ZERO
var _holding: bool = false
var _interact_cd: float = 0.0
var _pzf_wait: float = 0.0
var _pzf_cd: float = 0.0

var _err_deg: float = 1.5
var _react: float = 0.45

func setup(level: Node3D, player: Node3D) -> void:
	lv = level
	pl = player
	skill = str(Game.arg("skill", "average"))
	rng.seed = int(Game.arg("seed", 2406)) if Game.arg("seed", null) != null else 2406
	match skill:
		"novice":
			_err_deg = 2.5
			_react = 0.7
		"veteran":
			_err_deg = 0.8
			_react = 0.3
		_:
			_err_deg = 1.5
			_react = 0.45
	if not Events.player_respawned.is_connected(_on_respawn):
		Events.player_respawned.connect(_on_respawn)

func _on_respawn() -> void:
	_route_key = ""
	_target = null
	_engage = null

func is_holding() -> bool:
	return _holding

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
	var e: Dictionary = pl.get("ext")
	_neutral(e)
	_holding = false
	if not bool(pl.call("is_alive")):
		return
	_interact_cd = maxf(0.0, _interact_cd - delta)
	_pzf_cd = maxf(0.0, _pzf_cd - delta)
	var task: Dictionary = lv.call("bot_task")
	match str(task.get("kind", "wait")):
		"walk":
			_ensure_rifle(e)
			_walk(e, task, delta)
		"hold":
			_ensure_rifle(e)
			_hold(e, task, delta)
		"heli":
			_heli(e, task, delta)
		"ride":
			pass
		_:
			pass
	_reload_if_empty(e)

func _weapon_id() -> String:
	var w: Node = pl.get("weapon")
	return str(w.get("weapon_id")) if w != null else ""

func _ensure_rifle(e: Dictionary) -> void:
	if _weapon_id() == "pzf3":
		e["weapon"] = 1

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
			_engage = _find_threat(float(task.get("fight_range", 40.0)))
		if _engage != null and is_instance_valid(_engage) and bool(_engage.call("is_alive")):
			_shoot_at(e, _engage, delta)
			_stuck_ref = pl.global_position
			return
	if _ri >= path.size():
		return
	var tgt: Vector3 = path[_ri]
	var pos := pl.global_position
	var flat := Vector2(tgt.x - pos.x, tgt.z - pos.z)
	var reach: float = 0.6 if _ri < path.size() - 1 else 0.4
	if flat.length() < reach and absf(tgt.y - pos.y) < 1.4:
		_ri += 1
		return
	var yaw := rad_to_deg(atan2(-flat.x, -flat.y))
	pl.call("set_view", yaw, -4.0)
	e["move"] = Vector2(0.0, 1.0 if flat.length() > 0.3 else 0.4)
	e["sprint"] = bool(task.get("sprint", false)) and flat.length() > 3.0
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
		print("[ft-bot] haengt bei %s -> Wegpunkt %d" % [str(pos), _ri])
		pl.global_position = tgt + Vector3(0, 0.1, 0)
		_stuck_t = 0.0

func _nearest_ahead(path: Array) -> int:
	var pos := pl.global_position
	var best := 0
	var bd := INF
	for i in path.size():
		var p: Vector3 = path[i]
		# Hoehe stark gewichten (Wendeltreppe: Punkte uebereinander)
		var d := Vector2(p.x - pos.x, p.z - pos.z).length() + absf(p.y - pos.y) * 4.0
		if d < bd:
			bd = d
			best = i
	if best < path.size() - 1:
		var a: Vector3 = path[best]
		var b: Vector3 = path[best + 1]
		if (b - a).dot(pos - a) > 0.0:
			best += 1
	return best

func _go_to(e: Dictionary, spot: Vector3, delta: float, key: String) -> bool:
	var pos := pl.global_position
	var flat := Vector2(spot.x - pos.x, spot.z - pos.z)
	if flat.length() < 0.55 and absf(spot.y - pos.y) < 1.4:
		return true
	_walk(e, {"path": [spot], "key": key}, delta)
	return false

# ------------------------------------------------------------------ Halten

func _hold(e: Dictionary, task: Dictionary, delta: float) -> void:
	var spot: Vector3 = task.get("pos", pl.global_position)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_engage = _find_threat(28.0)
	if _engage != null and is_instance_valid(_engage) and bool(_engage.call("is_alive")):
		_shoot_at(e, _engage, delta)
		return
	if not _go_to(e, spot, delta, "hold"):
		return
	_target = null
	_look_at(task.get("face", spot + Vector3(0, 1.0, 5.0)) as Vector3)
	_holding = true

# ------------------------------------------------------------------ Schiessen (Gewehr)

func _shoot_at(e: Dictionary, t: Node3D, delta: float) -> void:
	if t != _target:
		_target = t
		_aim_t = 0.0
		_burst_t = 0.0
		_err = Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * _err_deg
	_aim_t += delta
	var aim := _aim_point(t)
	var cam: Camera3D = pl.call("get_camera")
	var dv := aim - cam.global_position
	var shrink := clampf(1.0 - _aim_t / 2.5, 0.35, 1.0)
	var yaw := rad_to_deg(atan2(-dv.x, -dv.z)) + _err.x * shrink + sin(_aim_t * 2.1) * _err_deg * 0.25
	var pitch := rad_to_deg(atan2(dv.y, Vector2(dv.x, dv.z).length())) + _err.y * shrink * 0.6
	pl.call("set_view", yaw, pitch)
	e["aim"] = true
	if _aim_t < _react:
		return
	_burst_t += delta
	var cyc := fmod(_burst_t, 0.75)
	e["fire"] = cyc < 0.3

func _aim_point(t: Node3D) -> Vector3:
	if t.has_method("get_aim_point"):
		return t.call("get_aim_point")
	return t.global_position + Vector3.UP * 1.25

func _find_threat(rng_max: float) -> Node3D:
	var cam: Camera3D = pl.call("get_camera")
	var from := cam.global_position
	var best: Node3D = null
	var bd := rng_max
	var heli: Node = lv.call("heli_node")
	for n in pl.get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or n == heli or (n as Node).is_in_group("vehicle"):
			continue
		if not bool(n.call("is_alive")):
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

func _look_at(p: Vector3) -> void:
	var cam: Camera3D = pl.call("get_camera")
	var dv := p - cam.global_position
	pl.call("set_view", rad_to_deg(atan2(-dv.x, -dv.z)), rad_to_deg(atan2(dv.y, Vector2(dv.x, dv.z).length())))

# ------------------------------------------------------------------ Hubschrauber

func _heli(e: Dictionary, task: Dictionary, delta: float) -> void:
	var heli: Node3D = task.get("heli", null)
	var lw: Node = pl.call("get_weapon", "pzf3")
	var spot: Vector3 = task.get("spot", pl.global_position)
	# 1) Panzerfaust holen
	if lw == null:
		var pzf: Vector3 = task.get("pzf", spot)
		var crate: Vector3 = task.get("crate", pzf)
		_pzf_wait += delta
		var tgt := pzf if _pzf_wait < 12.0 else crate
		if _go_to(e, tgt, delta, "pzf_%d" % (0 if _pzf_wait < 12.0 else 1)):
			if _interact_cd <= 0.0:
				e["interact"] = true
				_interact_cd = 0.5
		if _pzf_wait > 24.0:
			# Testhilfe: falls Aufheben scheitert
			print("[ft-bot] Panzerfaust nicht aufgenommen -> give_weapon")
			pl.call("give_weapon", "pzf3", 1, 2)
		return
	var ammo: int = int(lw.get("ammo_mag")) + int(lw.get("ammo_reserve"))
	if ammo <= 0:
		var crate2: Vector3 = task.get("crate", spot)
		if _go_to(e, crate2, delta, "crate"):
			if _interact_cd <= 0.0:
				e["interact"] = true
				_interact_cd = 0.5
		return
	# 2) Auf die Terrasse (ueber die Tuer)
	var pos := pl.global_position
	if pos.z < 2.4:
		var door_path: Array = [Vector3(0, pos.y, 0.8), Vector3(0, pos.y, 3.6), Vector3(spot.x, spot.y, 3.6), spot]
		_walk(e, {"path": door_path, "key": "to_terrace"}, delta)
		return
	if not _go_to(e, spot, delta, "terrace"):
		if Vector2(spot.x - pos.x, spot.z - pos.z).length() > 4.0:
			_walk(e, {"path": [Vector3(spot.x, spot.y, 3.6), spot], "key": "to_spot"}, delta)
		return
	if heli == null or not is_instance_valid(heli):
		_look_at(Vector3(-25, 66, 35))
		return
	# 3) Waffe waehlen
	if _weapon_id() != "pzf3":
		e["weapon"] = 3
		_aim_t = 0.0
		return
	if heli != _target:
		_target = heli
		_aim_t = 0.0
		_err = Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * _err_deg * 0.5
	_aim_t += delta
	var cam: Camera3D = pl.call("get_camera")
	var from := cam.global_position
	var aim := heli.global_position + Vector3.UP * 0.4
	var vel: Vector3 = Vector3.ZERO
	if heli.get("_vel") is Vector3:
		vel = heli.get("_vel")
	var d := from.distance_to(aim)
	var tof := d / ROCKET_SPEED
	aim += vel * tof + Vector3.UP * (0.5 * ROCKET_GRAV * tof * tof)
	var dv := aim - from
	var settle := clampf(1.0 - _aim_t / 1.6, 0.25, 1.0)
	var yaw := rad_to_deg(atan2(-dv.x, -dv.z)) + _err.x * settle
	var pitch := rad_to_deg(atan2(dv.y, Vector2(dv.x, dv.z).length())) + _err.y * settle
	pl.call("set_view", yaw, pitch)
	e["aim"] = true
	var w: Node = pl.get("weapon")
	var ready: bool = w != null and int(w.get("ammo_mag")) > 0 and not bool(w.get("reloading"))
	if ready and _aim_t > 1.2 + _react and _pzf_cd <= 0.0:
		e["fire"] = true
		_pzf_cd = 1.5
		_aim_t = 0.0
		_err = Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * _err_deg * 0.5
