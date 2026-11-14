extends RefCounted
## Mission 11 "Nachtzug": Test-Bot fuer den Autopiloten (nur mit --autopilot aktiv).
## Das Level meldet bot_drives_player() und liefert Aufgaben (bot_task):
##   walk -> Wegpunkte ablaufen, optional kaempfen; "prone" = hinlegen und stillhalten (Tunnel)
## Die Tuer-MG-Phase uebernimmt der RailRideBot (rail_ride.gd).
## Schusslinien-Pruefung: nie feuern, wenn Reisende (no_shoot) oder Lena in der Linie sind.
## Deckung (14.11.2026): liefert die Aufgabe "cover" (Punkte hinter Kisten), zieht sich der Bot bei
## wenig Leben dorthin zurueck, duckt sich, laedt nach und wartet die Regeneration ab - wie ein Mensch,
## statt im offenen Gang nachzuladen. "crouch_fight" = geduckt schiessen (Gegner treffen x0.7).

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
var _recover: bool = false
var _recover_t: float = 0.0
var _cover_pt: Vector3 = Vector3.ZERO
var _crouch_fight: bool = false
var _block_name: String = ""
var _lena_aside_ms: int = 0       ## Lena per "Dort hin" zur Seite geschickt (0 = nein)
var _idle_t: float = 0.0           ## Zeit am Routenende ohne sichtbares Ziel (-> Abteile absuchen)
var _skip: Dictionary = {}          ## Ziel -> Zeit (ms), bis zu der es wegen blockierter Linie ignoriert wird

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
	_recover = false
	_lena_aside_ms = 0
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
	# nach dem "Zur Seite"-Befehl wieder folgen lassen (wie ein Spieler, der [H] Folgen drueckt)
	if _lena_aside_ms > 0 and Time.get_ticks_msec() > _lena_aside_ms + 6000:
		_lena_aside_ms = 0
		var c: Object = lv.get("_lena_c")
		if c != null:
			c.call("order_follow")

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
	_crouch_fight = bool(task.get("crouch_fight", false))
	var covers: Array = task.get("cover", [])
	if not covers.is_empty() and not prone:
		if _recover:
			if _recover_tick(e, delta):
				return
		elif _hp_frac() < 0.5 and _engage != null and is_instance_valid(_engage) and bool(_engage.call("is_alive")):
			var c: Variant = _pick_cover(covers)
			if c != null:
				_cover_pt = c
				_recover = true
				_recover_t = 0.0
				print("[nz-bot] Deckung bei %s (Leben %.0f %%)" % [str(_cover_pt), _hp_frac() * 100.0])
				return
	elif _recover:
		_recover = false
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
		_idle_t += delta
		var doors: Array = task.get("search_doors", [])
		if not doors.is_empty() and _idle_t > 3.0 and _search(e, doors, float(task.get("search_x", 0.5)), delta):
			return
		_turn_to(0.0, -3.0, delta)
		return
	_idle_t = 0.0
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

## Routenende, aber noch Gegner da (z. B. im Abteil verschanzt, ohne Sicht vom Gang): wie ein Spieler
## den Gang bis vor die Abteiltuer gehen und hineinschauen. Gang bei x = sx, Abteile bei x < -0.1.
func _search(e: Dictionary, doors: Array, sx: float, delta: float) -> bool:
	var pos := pl.global_position
	var best: Node3D = null
	var bd := 20.0
	for n in pl.get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or (n as Node).is_in_group("vehicle") or not bool(n.call("is_alive")):
			continue
		var d := (n as Node3D).global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = n
	if best == null:
		return false
	var ep := best.global_position
	var dz: float = doors[0]
	for z: float in doors:
		if absf(z - ep.z) < absf(dz - ep.z):
			dz = z
	var tgt := Vector3(sx, pos.y, dz) if absf(pos.z - dz) > 0.3 and pos.x > -0.1 else Vector3(ep.x, pos.y, dz)
	var flat := Vector2(tgt.x - pos.x, tgt.z - pos.z)
	if flat.length() < 0.25:
		_turn_to(rad_to_deg(atan2(-(ep.x - pos.x), -(ep.z - pos.z))), -3.0, delta)
		return true
	var yaw := rad_to_deg(atan2(-flat.x, -flat.y))
	var err := _turn_to(yaw, -4.0, delta)
	e["move"] = Vector2(0.0, 0.7 if err < 35.0 else 0.0)
	return true

func _hp_frac() -> float:
	return float(pl.get("health")) / maxf(float(pl.get("max_health")), 1.0)

## Naechster Deckungspunkt auf Hoehe des Spielers oder dahinter (Gegner kommen von -Z).
func _pick_cover(covers: Array) -> Variant:
	var pos := pl.global_position
	var best: Variant = null
	var bd := 14.0
	for c: Vector3 in covers:
		if c.z < pos.z - 1.0 or absf(c.y - pos.y) > 1.4:
			continue
		var d := Vector2(c.x - pos.x, c.z - pos.z).length()
		if d < bd:
			bd = d
			best = c
	return best

## Rueckzug in Deckung: rueckwaerts hinlaufen (Blick bleibt nach vorn), dort ducken, nachladen,
## bis ~90 % Leben regeneriert sind. true = Bot ist beschaeftigt.
func _recover_tick(e: Dictionary, delta: float) -> bool:
	_recover_t += delta
	var pos := pl.global_position
	var flat := Vector2(_cover_pt.x - pos.x, _cover_pt.z - pos.z)
	var hp := _hp_frac()
	if (hp >= 0.9 and flat.length() < 0.6) or _recover_t > 14.0:
		_recover = false
		print("[nz-bot] Deckung verlassen nach %.1f s (Leben %.0f %%)" % [_recover_t, hp * 100.0])
		return false
	_turn_to(0.0, -2.0, delta)
	_stuck_ref = pos
	if flat.length() > 0.3:
		# Weltrichtung in Eingabe (x = rechts, y = vor) relativ zum Blick umrechnen
		var yr := deg_to_rad(_cur_yaw)
		var fwd := Vector2(-sin(yr), -cos(yr))
		var right := Vector2(cos(yr), -sin(yr))
		var d := flat.normalized()
		e["move"] = Vector2(d.dot(right), d.dot(fwd)) * (1.0 if flat.length() > 0.8 else 0.5)
		if _recover_t > 6.0:
			pl.global_position = Vector3(_cover_pt.x, pos.y, _cover_pt.z)
	else:
		e["crouch"] = true
		var w: Node = pl.get("weapon")
		if w != null and not bool(w.get("reloading")) and int(w.get("ammo_mag")) < int(w.get("mag_size")) * 0.8:
			e["reload"] = true
	return true

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
	if _crouch_fight and not prone:
		e["crouch"] = true
	if _aim_t < _react or err > 2.5:
		return
	# Schusslinie frei? Die tatsaechliche Blickrichtung zaehlt (nicht das Ziel).
	var fwd := -cam.global_transform.basis.z
	var end := cam.global_position + fwd * (cam.global_position.distance_to(aim) + 1.0)
	if not _line_clear(cam.global_position, end, t):
		_blocked_t += delta
		if _blocked_t > 1.0 and not prone:
			e["move"] = Vector2(_side, 0.0)
		if _block_name == "Lena" and _blocked_t > 1.2 and _lena_aside_ms == 0:
			_lena_aside(t)
		if _blocked_t > 2.0:
			# Mensch wuerde das naechste freie Ziel nehmen statt seitlich vor einem Pulk hin und her zu treten
			print("[nz-bot] Schusslinie blockiert (%s) -> %s %s, Spieler %s" % [_block_name, str(t.name), str(t.global_position.snapped(Vector3.ONE * 0.1)), str(pl.global_position.snapped(Vector3.ONE * 0.1))])
			_side = -_side
			_blocked_t = 1.0
			_skip[t.get_instance_id()] = Time.get_ticks_msec() + 3000
			_engage = null
			_scan_t = 0.0
		return
	_blocked_t = 0.0
	_burst_t += delta
	e["fire"] = fmod(_burst_t, 0.7) < 0.28

## Squad-Befehl "Dort hin" wie ein Spieler: Lena auf die andere Gangseite, weg von der Schusslinie.
func _lena_aside(t: Node3D) -> void:
	var c: Object = lv.get("_lena_c")
	var lena: Node3D = lv.get("lena")
	if c == null or lena == null or not is_instance_valid(lena):
		return
	var a := pl.global_position
	var b := t.global_position
	var lp := lena.global_position
	var k := clampf((lp.z - a.z) / (b.z - a.z), 0.0, 1.0) if absf(b.z - a.z) > 0.1 else 0.0
	var line_x := lerpf(a.x, b.x, k)
	var inside := a.y < 3.0
	var lo := -0.2 if inside else -0.8
	var hi := 1.3 if inside else 0.8
	var nx := lo if absf(lo - line_x) > absf(hi - line_x) else hi
	if bool(c.call("order_move", Vector3(nx, lp.y, lp.z))):
		_lena_aside_ms = Time.get_ticks_msec()
		print("[nz-bot] Lena zur Seite (x %.1f -> %.1f)" % [lp.x, nx])

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
		# Reisende 0,75 m Sicherheitsabstand; an Lena (Profi, unverwundbar) schiesst ein Mensch auch
		# knapp vorbei - mit 0,75 m stand der Bot minutenlang, wenn ein Gegner neben ihr stand.
		var clear_r := 0.4 if (n as Node).is_in_group("friendly") and not (n as Node).is_in_group("no_shoot") else 0.75
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
			if (from + seg * tt).distance_to(p) < clear_r:
				_block_name = str((n as Node).name)
				return false
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [pl.get_rid()])
	var hit := pl.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit.get("collider")
		if c is Node and ((c as Node).is_in_group("no_shoot") or (c as Node).is_in_group("friendly")):
			_block_name = str((c as Node).name)
			return false
	return true

func _find_threat(rng_max: float) -> Node3D:
	var cam: Camera3D = pl.call("get_camera")
	var from := cam.global_position
	var best: Node3D = null
	var bd := rng_max
	var now := Time.get_ticks_msec()
	var fallback: Node3D = null
	for n in pl.get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or (n as Node).is_in_group("vehicle"):
			continue
		if not bool(n.call("is_alive")):
			continue
		if int(_skip.get(n.get_instance_id(), 0)) > now:
			if fallback == null:
				fallback = n
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
	return best if best != null else fallback
