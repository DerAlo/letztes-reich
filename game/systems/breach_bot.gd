extends RefCounted
## Breach-Bot (Runde 7, nur unter --autopilot): uebernimmt den Spieler an einer Breach-Tuer
## (Level.bot_drives_player() = true) und spielt die Sequenz: Tuer anlaufen -> Ladung anbringen (E halten)
## -> seitlich in Deckung -> Detonation -> Eingang (Zeitlupe) -> Bewacher ausschalten -> freigeben.
## Schiesst NUR, wenn die Schusslinie frei ist: erster Treffer = Bewacher UND jede Geisel liegt mit
## Sicherheitsabstand (0.3 m + Streukegel) neben der Linie. Sonst seitlich versetzen.

var player: Player
var room: Node                ## breach_room.gd
var flash: bool = false
var phase: String = "idle"    ## approach, plant, stack, wait, entry, fight, done
var reaction: float = 0.15
var _pt: float = 0.0
var _target: Enemy
var _target_seen: float = 0.0
var _fire_t: float = 0.0
var _strafe: float = 1.0
var _strafe_t: float = 0.0
var _entry_side: float = 0.0
var shots_blocked: int = 0
var shots_fired: int = 0

func _init(skill: String) -> void:
	reaction = 0.25 if skill == "novice" else (0.08 if skill == "veteran" else 0.13)

func begin(p: Player, r: Node, use_flash: bool) -> void:
	player = p
	room = r
	flash = use_flash
	phase = "approach"
	_pt = 0.0
	_target = null

func active() -> bool:
	return phase != "idle" and phase != "done"

func _door() -> Node3D:
	return room.get("door") as Node3D

func _out(ext: Dictionary, mv_world: Vector3, fire: bool, aim: bool, sprint: bool = false) -> void:
	var cam := player.get_camera()
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	ext["move"] = Vector2(mv_world.dot(right), mv_world.dot(fwd)).limit_length(1.0)
	ext["look"] = Vector2.ZERO
	ext["fire"] = fire
	ext["aim"] = aim
	ext["sprint"] = sprint
	ext["crouch"] = false

func _move_to(p: Vector3, tol: float = 0.35) -> Vector3:
	var d := p - player.global_position
	d.y = 0.0
	if d.length() < tol:
		return Vector3.ZERO
	return d.normalized() * clampf(d.length() / 0.8, 0.35, 1.0)

func release(ext: Dictionary) -> void:
	phase = "done"
	ext["move"] = Vector2.ZERO
	ext["look"] = Vector2.ZERO
	ext["fire"] = false
	ext["aim"] = false
	ext["sprint"] = false
	ext["crouch"] = false

func tick(delta: float) -> void:
	if player == null or not is_instance_valid(player) or room == null:
		return
	var ext: Dictionary = player.ext
	player.external_input = true
	_pt += delta
	if bool(player.get("dead")):
		release(ext)
		return
	var door := _door()
	match phase:
		"approach":
			# vor die Tuer, leicht seitlich (Spielerseite, in Reichweite)
			var stand := door.call("outside_point", 1.3, 0.55) as Vector3
			var mv := _move_to(stand, 0.3)
			player.look_at_point(door.global_position + Vector3.UP * 1.3)
			_out(ext, mv, false, false)
			if bool(room.call("is_breached")):
				phase = "entry"
				_pt = 0.0
			elif mv == Vector3.ZERO and bool(door.call("player_in_reach")):
				door.call("bot_plant", flash)
				phase = "plant"
				_pt = 0.0
			elif _pt > 12.0:
				# kommt nicht hin -> eintreten, falls in Reichweite
				if bool(door.call("player_in_reach")):
					door.call("bot_kick", flash)
					phase = "entry"
					_pt = 0.0
		"plant":
			player.look_at_point(door.global_position + Vector3.UP * 1.1)
			_out(ext, Vector3.ZERO, false, false)
			if int(door.get("state")) != 0:   # ARMED/OPEN
				phase = "stack"
				_pt = 0.0
			elif _pt > 4.0:
				door.call("bot_kick", flash)
				phase = "entry"
				_pt = 0.0
		"stack":
			# seitlich neben die Oeffnung (Mauer zwischen Ladung und Spieler)
			_entry_side = -1.0
			var st := door.call("outside_point", 1.0, -2.3) as Vector3
			player.look_at_point(door.global_position + Vector3.UP * 1.3)
			_out(ext, _move_to(st, 0.25), false, false, false)
			if bool(door.call("is_open")):
				phase = "entry"
				_pt = 0.0
		"entry":
			# kurz warten, bis der Staub die Tuer freigibt, dann hinein
			var inside := door.call("inside_point", 1.8, 0.0) as Vector3
			var mv2 := _move_to(inside, 0.4)
			if _pt < 0.15:
				mv2 = Vector3.ZERO
			_fight(ext, delta, mv2)
			if mv2 == Vector3.ZERO and _pt > 0.15:
				phase = "fight"
				_pt = 0.0
		"fight":
			var hold := door.call("inside_point", 2.2, 0.0) as Vector3
			_fight(ext, delta, _move_to(hold, 0.6))
			if bool(room.call("is_cleared")) or (room.call("alive_captors") as Array).is_empty():
				release(ext)
			elif not bool(room.call("is_breached")) and not bool(room.call("is_idle")):
				release(ext)   # gescheitert -> Level setzt zurueck
			elif _pt > 25.0:
				release(ext)

## Ziel waehlen, Schusslinie pruefen, schiessen oder versetzen. base_mv = gewuenschte Bewegung ohne Ziel.
func _fight(ext: Dictionary, delta: float, base_mv: Vector3) -> void:
	var cam := player.get_camera()
	var eye := cam.global_position
	# naechster sichtbarer Bewacher (Bedrohung zuerst: wer schon kaempft)
	var best: Enemy = null
	var best_score := INF
	for e: Enemy in room.call("alive_captors"):
		var ap := _aim_point(e)
		if not _los(eye, ap, e):
			continue
		var sc := eye.distance_to(ap)
		if e.state != Enemy.State.IDLE:
			sc -= 6.0
		if sc < best_score:
			best_score = sc
			best = e
	if best != _target:
		_target = best
		_target_seen = 0.0
	if _target == null:
		var look := _door().call("inside_point", 6.0, 0.0) as Vector3
		player.look_at_point(look + Vector3.UP * 1.3)
		_out(ext, base_mv, false, true)
		return
	_target_seen += delta
	var ap2 := _aim_point(_target)
	player.look_at_point(ap2)
	if _target_seen < reaction:
		_out(ext, Vector3.ZERO, false, true)
		return
	if _line_clear(eye, ap2):
		_fire_t += delta
		# kurze Feuerstoesse (Tap): 2 Frames an, 2 aus -> wenig Streuung
		var on := fmod(_fire_t, 0.16) < 0.08
		if on:
			shots_fired += 1
		_out(ext, Vector3.ZERO, on, true)
	else:
		shots_blocked += 1
		# Geisel in der Linie: seitlich versetzen (Richtung wechselt alle ~1.2 s)
		_strafe_t += delta
		if _strafe_t > 1.2:
			_strafe_t = 0.0
			_strafe = -_strafe
		var to_t := ap2 - eye
		to_t.y = 0.0
		var side := Vector3(-to_t.z, 0.0, to_t.x).normalized() * _strafe
		_out(ext, side * 0.8, false, true)

func _aim_point(e: Enemy) -> Vector3:
	if e.has_method("get_aim_point"):
		return e.call("get_aim_point")
	var hb: Node3D = e.get("_head_hitbox")
	if hb != null and is_instance_valid(hb):
		return hb.global_position
	return e.global_position + Vector3.UP * 1.55

func _los(from: Vector3, to: Vector3, e: Enemy) -> bool:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
	q.collide_with_areas = true
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	var c: Node = hit.get("collider")
	var n := c
	for i in 6:
		if n == null:
			break
		if n == e:
			return true
		n = n.get_parent()
	return false

## Keine Geisel nahe der Schusslinie (Streukegel 2.2 Grad + 0.3 m Rand).
func _line_clear(from: Vector3, to: Vector3) -> bool:
	var seg := to - from
	var L := seg.length()
	if L < 0.01:
		return false
	var dir := seg / L
	for h: Node3D in room.call("alive_hostages"):
		for p: Vector3 in h.call("clearance_points"):
			var t := (p - from).dot(dir)
			if t < 0.0:
				continue
			var tt := minf(t, L + 3.0)
			var closest := from + dir * tt
			var margin := 0.3 + tt * tan(deg_to_rad(2.2))
			if closest.distance_to(p) < margin:
				return false
	return true
