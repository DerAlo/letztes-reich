extends Node
## Lautloser Takedown [F] (Level "curfew"): von hinten (oder an einer ahnungslosen Wache vorbei) bis ~2 m.
## Kurze Sperre der Eingabe, Kamera folgt der Wache zu Boden, leiser Sound. Kein Alarm, die Leiche bleibt
## aber liegen (Fund = Alarm). Eigene Eingabe-Aktion "takedown" (F) wird bei Bedarf angelegt.

signal performed(enemy: Node3D)

const RANGE := 2.1
const LOCK_TIME := 0.75

var director: Node
var candidate: Node3D = null       ## fuer die HUD-Anzeige
var _victim: Node3D = null
var _t: float = -1.0
var _locked: bool = false
var _start_pos: Vector3
var _goal_pos: Vector3
var _bot: bool = false

func _ready() -> void:
	name = "Takedown"
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	if not InputMap.has_action("takedown"):
		InputMap.add_action("takedown")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.action_add_event("takedown", ev)

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func busy() -> bool:
	return _t >= 0.0

func _physics_process(delta: float) -> void:
	var pl := _player()
	if pl == null:
		return
	if _t >= 0.0:
		_animate(pl, delta)
		return
	candidate = _find(pl) if pl.is_alive() else null
	if candidate != null and not _bot and Input.is_action_just_pressed("takedown"):
		_start(pl, candidate)

func _find(pl: Player) -> Node3D:
	if director == null:
		return null
	var cam := pl.get_camera()
	var cfwd := -cam.global_transform.basis.z
	var best: Node3D = null
	var best_d := RANGE
	for w in director.get("watchers"):
		if not is_instance_valid(w) or not w.has_method("is_aware"):
			continue
		var e: Enemy = w.get("enemy")
		if e == null or not is_instance_valid(e) or not e.is_alive():
			continue
		var to := e.global_position - pl.global_position
		if absf(to.y) > 1.2:
			continue
		to.y = 0.0
		var d := to.length()
		if d > best_d or d < 0.05:
			continue
		var chest := e.global_position + Vector3.UP * 1.1
		if cfwd.dot((chest - cam.global_position).normalized()) < 0.55:
			continue
		var efwd := -e.global_transform.basis.z
		efwd.y = 0.0
		var behind := efwd.normalized().dot(-to / d)
		var aware := bool(w.call("is_aware"))
		if behind < -0.25 or (not aware and behind < 0.5):
			best = e
			best_d = d
	return best

func _start(pl: Player, e: Node3D) -> void:
	_victim = e
	candidate = null   # sonst startet try_auto() nach der Animation erneut auf die Leiche (Endlosschleife)
	_t = 0.0
	_start_pos = pl.global_position
	var efwd := -e.global_transform.basis.z
	efwd.y = 0.0
	_goal_pos = e.global_position - efwd.normalized() * 0.75
	_goal_pos.y = pl.global_position.y
	if not _bot:
		_locked = true
		pl.external_input = true
		pl.ext["move"] = Vector2.ZERO
		pl.ext["look"] = Vector2.ZERO
		pl.ext["fire"] = false
		pl.ext["aim"] = false
		pl.ext["sprint"] = false
		pl.ext["jump"] = false
		pl.ext["crouch"] = pl.is_crouching
	pl.add_trauma(0.18)
	pl.play_sfx("curfew_takedown")
	# Wache erstarrt
	(e as Enemy).velocity = Vector3.ZERO
	performed.emit(e)

func _animate(pl: Player, delta: float) -> void:
	_t += delta
	var e := _victim
	if e != null and is_instance_valid(e):
		var k := clampf(_t / 0.22, 0.0, 1.0)
		var p := _start_pos.lerp(_goal_pos, k * k * (3.0 - 2.0 * k))
		pl.global_position = Vector3(p.x, pl.global_position.y, p.z)
		var en := e as Enemy
		if en.is_alive():
			en.velocity = Vector3.ZERO
			pl.look_at_point(en.global_position + Vector3.UP * 1.45)
			if _t >= 0.28:
				en._last_hit_dir = (en.global_position - pl.global_position).normalized()
				en.health = 0.0
				en._die()
				pl.add_trauma(0.22)
		else:
			# Kamera folgt dem Koerper nach unten
			var drop := clampf((_t - 0.28) / 0.4, 0.0, 1.0)
			pl.look_at_point(en.global_position + Vector3.UP * lerpf(1.3, 0.35, drop))
	if _t >= LOCK_TIME:
		_t = -1.0
		_victim = null
		if _locked:
			_locked = false
			pl.ext["look"] = Vector2.ZERO
			pl.external_input = false

## Bot: Takedown ausloesen, wenn moeglich (fuer Tests).
func try_auto() -> bool:
	var pl := _player()
	if pl == null or _t >= 0.0 or candidate == null:
		return false
	if not is_instance_valid(candidate) or not (candidate as Enemy).is_alive():
		candidate = null
		return false
	_start(pl, candidate)
	return true
