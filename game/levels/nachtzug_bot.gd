extends RefCounted
## Mission 11 "Nachtzug": Test-Bot fuer den Autopiloten (nur mit --autopilot aktiv).
## Das Level meldet bot_drives_player() und liefert Aufgaben (bot_task):
##   walk -> Wegpunkte ablaufen, optional kaempfen; "prone" = hinlegen und stillhalten (Tunnel)
## Die Tuer-MG-Phase uebernimmt der RailRideBot (rail_ride.gd).
## Schusslinien-Pruefung: nie feuern, wenn Reisende (no_shoot) oder Lena in der Linie sind.

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
var _blocked_t: float = 0.0
var _side: float = 1.0
var _cur_yaw: float = 0.0
var _cur_pitch: float = 0.0

var _err_deg: float = 1.5
var _react: float = 0.45
var _turn: float = 260.0

func setup(level: Node3D, player: Node3D) -> void:
	lv = level
	pl = player
	skill = str(Game.arg("skill", "average"))
	rng.seed = int(Game.arg("seed", 1606)) if Game.arg("seed", null) != null else 1606
	match skill:
		"novice":
			_err_deg = 2.2
			_react = 0.7
			_turn = 160.0
		"veteran":
			_err_deg = 0.8
			_react = 0.3
			_turn = 360.0
		_:
			_err_deg = 1.4
			_react = 0.45
			_turn = 260.0
	_cur_yaw = float(pl.get("yaw"))
	_cur_pitch = float(pl.get("pitch"))
	if not Events.player_respawned.is_connected(_on_respawn):
		Events.player_respawned.connect(_on_respawn)

func _on_respawn() -> void:
	_route_key = ""
	_target = null
	_engage = null
	if pl != null and is_instance_valid(pl):
		_cur_yaw = float(pl.get("yaw"))
		_cur_pitch = float(pl.get("pitch"))

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
	if not bool(pl.call("is_alive")):
		return
	var task: Dictionary = lv.call("bot_task")
	if str(task.get("kind", "wait")) == "walk":
		if _weapon_id() == "pzf3":
			e["weapon"] = 1
		_walk(e, task, delta)
	_reload_if_empty(e)

func _weapon_id() -> String:
	var w: Node = pl.get("weapon")
	return str(w.get("weapon_id")) if w != null else ""

func _reload_if_empty(e: Dictionary) -> void:
	var w: Node = pl.get("weapon")
	if w != null and int(w.get("ammo_mag")) <= 0 and not bool(w.get("reloading")):
		e["reload"] = true
		e["fire"] = false

## Weiches Drehen statt Springen (Ziel-Grad pro Sekunde je Skill).
func _turn_to(yaw: float, pitch: float, delta: float, instant: bool = false) -> float:
	var dy := wrapf(yaw - _cur_yaw, -180.0, 180.0)
	var dp := pitch - _cur_pitch
	if instant:
		_cur_yaw = yaw
		_cur_pitch = pitch
	else:
		var step := _turn * delta
		_cur_yaw += clampf(dy, -step, step)
		_cur_pitch += clampf(dp, -step, step)
	pl.call("set_view", _cur_yaw, _cur_pitch)
	return Vector2(wrapf(yaw - _cur_yaw, -180.0, 180.0), pitch - _cur_pitch).length()

# ------------------------------------------------------------------ Laufen

func _walk(e: Dictionary, task: Dictionary, delta: float) -> void:
	var path: Array = task.get("path", [])
	var prone := bool(task.get("prone", false))
	if prone:
		e["prone"] = true
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
			_engage = _find_threat(float(task.get("fight_range", 30.0)))
		if _engage != null and is_instance_valid(_engage) and bool(_engage.call("is_alive")):
			_shoot_at(e, _engage, delta, prone)
			_stuck_ref = pl.global_position
			return
	if prone:
		# im Tunnel liegen bleiben, nach vorn schauen
		_turn_to(_cur_yaw, -2.0, delta)
		_stuck_ref = pl.global_position
		return
	if _ri >= path.size():
		_turn_to(0.0, -3.0, delta)
		return
	var tgt: Vector3 = path[_ri]
	var pos := pl.global_position
	var flat := Vector2(tgt.x - pos.x, tgt.z - pos.z)
	var reach: float = 0.5 if _ri < path.size() - 1 else 0.35
	if flat.length() < reach and absf(tgt.y - pos.y) < 1.4:
		_ri += 1
		return
	var yaw := rad_to_deg(atan2(-flat.x, -flat.y))
	var err := _turn_to(yaw, -4.0, delta)
	e["move"] = Vector2(0.0, (1.0 if flat.length() > 0.3 else 0.4) if err < 35.0 else 0.0)
	_stuck_check -= delta
	if _stuck_check <= 0.0:
		_stuck_check = 1.0
		if pos.distance_to(_stuck_ref) < 0.3:
			_stuck_t += 1.0
		else:
			_stuck_t = 0.0
		_stuck_ref = pos
	if _stuck_t >= 8.0:
		print("[nz-bot] haengt bei %s -> Wegpunkt %d" % [str(pos), _ri])
		pl.global_position = tgt + Vector3(0, 0.1, 0)
		_stuck_t = 0.0

func _nearest_ahead(path: Array) -> int:
	var pos := pl.global_position
	var best := 0
	var bd := INF
	for i in path.size():
		var p: Vector3 = path[i]
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

# ------------------------------------------------------------------ Schiessen

func _shoot_at(e: Dictionary, t: Node3D, delta: float, prone: bool) -> void:
	if t != _target:
		_target = t
		_aim_t = 0.0
		_burst_t = 0.0
		_blocked_t = 0.0
		_err = Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * _err_deg
	_aim_t += delta
	var aim := _aim_point(t)
	var cam: Camera3D = pl.call("get_camera")
	var dv := aim - cam.global_position
	var shrink := clampf(1.0 - _aim_t / 2.5, 0.3, 1.0)
	var yaw := rad_to_deg(atan2(-dv.x, -dv.z)) + _err.x * shrink + sin(_aim_t * 2.1) * _err_deg * 0.2
	var pitch := rad_to_deg(atan2(dv.y, Vector2(dv.x, dv.z).length())) + _err.y * shrink * 0.6
	var err := _turn_to(yaw, pitch, delta)
	e["aim"] = true
	if _aim_t < _react or err > 2.5:
		return
	# Schusslinie frei? Die tatsaechliche Blickrichtung zaehlt (nicht das Ziel).
	var fwd := -cam.global_transform.basis.z
	var end := cam.global_position + fwd * (cam.global_position.distance_to(aim) + 1.0)
	if not _line_clear(cam.global_position, end, t):
		_blocked_t += delta
		if _blocked_t > 1.0 and not prone:
			e["move"] = Vector2(_side, 0.0)
		if _blocked_t > 3.0:
			print("[nz-bot] Schusslinie blockiert -> %s, Spieler %s" % [str(t.name), str(pl.global_position.snapped(Vector3.ONE * 0.1))])
			_side = -_side
			_blocked_t = 1.0
		return
	_blocked_t = 0.0
	_burst_t += delta
	e["fire"] = fmod(_burst_t, 0.7) < 0.28

func _aim_point(t: Node3D) -> Vector3:
	if t.has_method("get_aim_point"):
		return t.call("get_aim_point")
	return t.global_position + Vector3.UP * 1.25

## Nichts Schutzwuerdiges naeher als 0.75 m an der Linie und erster Treffer ist kein Reisender/Lena.
func _line_clear(from: Vector3, to: Vector3, target: Node3D) -> bool:
	var seg := to - from
	var len2 := seg.length_squared()
	if len2 < 0.01:
		return true
	var tree := pl.get_tree()
	var guarded: Array = tree.get_nodes_in_group("no_shoot") + tree.get_nodes_in_group("friendly")
	for n in guarded:
		if not (n is Node3D) or n == pl or n == target:
			continue
		var pts: Array = []
		if (n as Node).has_method("clearance_points"):
			pts = n.call("clearance_points")
		else:
			var b := (n as Node3D).global_position
			pts = [b + Vector3.UP * 0.4, b + Vector3.UP * 1.0, b + Vector3.UP * 1.5]
		for p: Vector3 in pts:
			var tt := (p - from).dot(seg) / len2
			if tt <= 0.0 or tt >= 1.0:
				continue
			if (from + seg * tt).distance_to(p) < 0.75:
				return false
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [pl.get_rid()])
	var hit := pl.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit.get("collider")
		if c is Node and ((c as Node).is_in_group("no_shoot") or (c as Node).is_in_group("friendly")):
			return false
	return true

func _find_threat(rng_max: float) -> Node3D:
	var cam: Camera3D = pl.call("get_camera")
	var from := cam.global_position
	var best: Node3D = null
	var bd := rng_max
	for n in pl.get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or (n as Node).is_in_group("vehicle"):
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
