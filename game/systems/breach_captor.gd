extends RefCounted
## Bewacher-KI (wiederverwendbar, Runde 7): haengt sich ueber den Opt-in-Hook enemy.stealth an einen Gegner.
## "hold"  : steht hinter seiner Geisel, Waffe auf sie gerichtet, ignoriert Wahrnehmung und Schuesse
## "react" : nach dem Breach (Zeit = Schreck/Betaeubung), dann normale Kampf-KI gegen den Spieler
## "fight" : Standardverhalten (stealth-Hook abgegeben)
## Die Exekution steuert der Raum (breach_room.gd) per execute_hostage().

var e: Enemy
var hostage: Node3D
var mode: String = "hold"
var _react: float = 0.0

func setup(enemy: Enemy, h: Node3D) -> void:
	e = enemy
	hostage = h
	e.stealth = self

func _valid() -> bool:
	return e != null and is_instance_valid(e) and e.is_alive()

func _face(p: Vector3) -> void:
	var d := p - e.global_position
	d.y = 0.0
	if d.length() > 0.05:
		e.rotation.y = atan2(-d.x, -d.z)

# --- enemy.stealth-Hook

func tick_idle(delta: float) -> bool:
	if not _valid():
		return false
	match mode:
		"hold":
			if hostage != null and is_instance_valid(hostage):
				_face(hostage.global_position)
			e._aim_at_target = false
			e._stance_target = 0.0
			return true
		"react":
			_react -= delta
			if _react <= 0.0:
				_engage()
				return false
			return true
	return false

func on_weapon_fired(_weapon: Node) -> bool:
	return mode != "fight"

func on_owner_died() -> void:
	if e != null and is_instance_valid(e):
		e._bark("death", 1.0, true)

# --- Raum-Steuerung

## Breach erkannt: nach `react` s (Spielzeit) greift er an.
func breach(react: float) -> void:
	if mode != "hold":
		return
	mode = "react"
	_react = react

func _engage() -> void:
	mode = "fight"
	if not _valid():
		return
	e.stealth = null
	var p := Game.get_player() as Node3D
	if p != null:
		e.alert(p.global_position, false)
		e._alert_timer = 0.12

## Erschiesst seine Geisel (Verzoegerung des Spielers). Gibt true zurueck, wenn geschossen wurde.
func execute_hostage() -> bool:
	if not _valid() or hostage == null or not is_instance_valid(hostage):
		return false
	if not bool(hostage.call("is_alive")):
		return false
	var head: Vector3 = hostage.call("head_point")
	_face(head)
	e._flash_timer = 0.06
	e._recoil = 1.0
	e._play_sfx(e.sfx_shot)
	if e._muzzle != null:
		e._spawn_tracer(e._muzzle.global_position, head)
	hostage.call("execute", e.global_position)
	return true
