extends Node3D
## Breach-Raum (wiederverwendbar, Runde 7): verbindet Breach-Tuer, Geiseln und Bewacher zu einer Geiselbefreiung.
##
## Aufbau (im Level, nach dem Navmesh-Bake):
##   var r := RoomScript.new(); r.room_id = "saal"; add_child(r)
##   r.setup_door(xf, slowmo)                 # xf: Ursprung = Boden/Mitte der Oeffnung, -Z zeigt in den Raum
##   var h := r.add_hostage(pos, yaw, "seat", {...})
##   r.add_captor("rifleman", pos, h_index)   # Bewacher hinter "seiner" Geisel
##   r.arm()                                  # Bewacher spawnen
##
## Ablauf:
##   IDLE      Bewacher bedrohen ihre Geiseln. Wer zu lange vor der Tuer zoegert, riskiert eine Exekution
##             (Warnung bei warn_after, Exekution bei kill_after Sekunden im Annaeherungsbereich).
##   BREACHED  Tuer gesprengt/eingetreten. Bewacher reagieren nach react_time (+Betaeubung bei Ladung,
##             +Blendgranate). Erreicht der Spieler den Eingang -> Zeitlupe. Wer bis exec_time noch lebt,
##             erschiesst seine Geisel.
##   CLEARED   alle Bewacher tot -> cleared
##   FAILED    Geisel tot (Bewacher oder Spieler) -> failed(reason); das Level setzt per reset() zurueck.
## Kein class_name: preload("res://game/systems/breach_room.gd").

signal breached(kind: String, flash: bool)
signal cleared(room: Node)
signal failed(room: Node, reason: String)
signal warned(room: Node)

const DoorScript = preload("res://game/systems/breach_door.gd")
const HostageScript = preload("res://game/systems/breach_hostage.gd")
const CaptorScript = preload("res://game/systems/breach_captor.gd")
const ENEMY_PATH := "res://game/enemies/%s.tscn"

enum RoomState { IDLE, BREACHED, CLEARED, FAILED }

@export var room_id: String = "room"
@export var react_time: float = 0.9          ## Grundreaktion der Bewacher nach dem Breach (Spielsekunden)
@export var charge_stun: float = 0.9         ## Zusatz bei Sprengladung (Druckwelle)
@export var flash_stun: float = 2.4          ## Zusatz bei Blendgranate
@export var exec_kick: float = 3.0           ## Exekution nach dem Breach (Eintreten)
@export var exec_charge: float = 3.8         ## Exekution nach dem Breach (Ladung)
@export var exec_flash_bonus: float = 2.6
@export var slowmo_seconds: float = 2.6      ## Basis-Sekunden (~Echtzeit)
@export var slowmo_factor: float = 0.3
@export var approach_radius: float = 11.0
@export var warn_after: float = 50.0
@export var kill_after: float = 80.0
@export var captor_accuracy: float = 0.6

var state: RoomState = RoomState.IDLE
var door: Node3D
var slowmo: Node
var hostages: Array[Node3D] = []
var captors: Array[Enemy] = []
var brains: Array = []
var _captor_defs: Array[Dictionary] = []
var _t_breach: float = 0.0
var _exec_at: float = 0.0
var _exec_done: Dictionary = {}
var _slowmo_used: bool = false
var _approach_t: float = 0.0
var _warned: bool = false
var _kind: String = ""
var _flash: bool = false
var _entry: Area3D
var _armed: bool = false

# ------------------------------------------------------------------ Aufbau

func setup_door(xf: Transform3D, slowmo_node: Node, w: float = 1.6, h: float = 2.45) -> Node3D:
	slowmo = slowmo_node
	door = DoorScript.new()
	door.name = "Door_" + room_id
	door.set("width", w)
	door.set("height", h)
	add_child(door)
	door.global_transform = xf
	door.connect("breached", _on_door_breached)
	# Eingangszone (Raumseite direkt hinter der Oeffnung): loest die Zeitlupe aus
	_entry = Area3D.new()
	_entry.collision_layer = 0
	_entry.collision_mask = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w + 1.4, 2.4, 2.4)
	cs.shape = bs
	_entry.add_child(cs)
	door.add_child(_entry)
	_entry.position = Vector3(0, 1.2, -0.9)
	_entry.body_entered.connect(_on_entry)
	return door

func add_hostage(pos: Vector3, yaw_deg: float, pose: String, look: Dictionary = {}) -> Node3D:
	var h := HostageScript.new()
	h.name = "Hostage_%s_%d" % [room_id, hostages.size()]
	h.set("pose", pose)
	for k: String in look:
		h.set(k, look[k])
	add_child(h)
	h.global_position = pos
	h.rotation_degrees.y = yaw_deg
	h.connect("shot_by_player", _on_hostage_shot)
	h.connect("executed", _on_hostage_executed)
	hostages.append(h)
	return h

func add_captor(type: String, pos: Vector3, hostage_index: int) -> void:
	_captor_defs.append({"type": type, "pos": pos, "h": hostage_index})

## Bewacher spawnen (nach dem Navmesh-Bake aufrufen).
func arm() -> void:
	_armed = true
	_spawn_captors()

func _spawn_captors() -> void:
	captors.clear()
	brains.clear()
	for d: Dictionary in _captor_defs:
		var scene := load(ENEMY_PATH % str(d["type"])) as PackedScene
		if scene == null:
			continue
		var e := scene.instantiate() as Enemy
		e.set_meta("faction", "reich")
		e.alert_neighbor_radius = 0.0
		get_parent().add_child(e)
		e.global_position = d["pos"]
		e.accuracy_scale = captor_accuracy
		var hi: int = int(d["h"])
		var h: Node3D = hostages[hi] if hi >= 0 and hi < hostages.size() else null
		if h != null:
			var dd := h.global_position - e.global_position
			e.rotation.y = atan2(-dd.x, -dd.z)
		var b := CaptorScript.new()
		b.setup(e, h)
		captors.append(e)
		brains.append(b)

# ------------------------------------------------------------------ Abfragen

func is_idle() -> bool:
	return state == RoomState.IDLE

func is_breached() -> bool:
	return state == RoomState.BREACHED

func is_cleared() -> bool:
	return state == RoomState.CLEARED

func alive_captors() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in captors:
		if is_instance_valid(e) and e.is_alive():
			out.append(e)
	return out

func alive_hostages() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for h in hostages:
		if is_instance_valid(h) and bool(h.call("is_alive")):
			out.append(h)
	return out

func time_since_breach() -> float:
	return _t_breach if state == RoomState.BREACHED else -1.0

## Restzeit bis zur Exekution (nur BREACHED), sonst -1.
func time_to_execution() -> float:
	return _exec_at - _t_breach if state == RoomState.BREACHED else -1.0

# ------------------------------------------------------------------ Ablauf

func _on_door_breached(kind: String, flash: bool) -> void:
	if state != RoomState.IDLE:
		return
	state = RoomState.BREACHED
	_kind = kind
	_flash = flash
	_t_breach = 0.0
	_exec_done.clear()
	_slowmo_used = false
	var react := react_time
	if kind == "charge":
		react += charge_stun
	if flash:
		react += flash_stun
	_exec_at = (exec_charge if kind == "charge" else exec_kick) + (exec_flash_bonus if flash else 0.0)
	for i in brains.size():
		var b: Variant = brains[i]
		# leichte Streuung: nicht alle reagieren im selben Frame
		b.call("breach", react + 0.12 * i)
	breached.emit(kind, flash)
	# Ist der Spieler schon im Eingang (Eintreten aus kurzer Distanz), sofort Zeitlupe
	var p := Game.get_player() as Node3D
	if p != null and _entry != null and _entry.overlaps_body(p):
		_start_slowmo()

func _on_entry(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if state == RoomState.BREACHED and _t_breach < 6.0:
		_start_slowmo()

func _start_slowmo() -> void:
	if _slowmo_used or slowmo == null:
		return
	_slowmo_used = true
	slowmo.call("start", slowmo_seconds, slowmo_factor)
	print("[breach] %s: Zeitlupe %.1f s (x%.2f)" % [room_id, slowmo_seconds, slowmo_factor])

func _physics_process(delta: float) -> void:
	if not _armed:
		return
	match state:
		RoomState.IDLE:
			_hold_captors()
			_tick_approach(delta)
		RoomState.BREACHED:
			_t_breach += delta
			if alive_captors().is_empty():
				_clear()
				return
			if _t_breach >= _exec_at:
				var i := 0
				for b: Variant in brains:
					var e: Enemy = b.get("e")
					if _exec_done.has(i) or e == null or not is_instance_valid(e) or not e.is_alive():
						i += 1
						continue
					if _t_breach >= _exec_at + 0.35 * i:
						_exec_done[i] = true
						b.call("execute_hostage")
					i += 1
		_:
			pass

## Vor dem Breach: Bewacher bleiben auf Posten (Kameraden-Alarm aus der Lobby holt sie nicht weg).
func _hold_captors() -> void:
	for b: Variant in brains:
		var e: Enemy = b.get("e")
		if e == null or not is_instance_valid(e) or not e.is_alive():
			continue
		if e.state != Enemy.State.IDLE and str(b.get("mode")) == "hold":
			e._set_state(Enemy.State.IDLE)
			e._has_last_known = false
			e.velocity = Vector3.ZERO

func _tick_approach(delta: float) -> void:
	if door == null or kill_after <= 0.0:
		return
	var p := Game.get_player() as Node3D
	if p == null or not p.is_inside_tree():
		return
	var near := p.global_position.distance_to(door.global_position) < approach_radius and absf(p.global_position.y - door.global_position.y) < 3.0
	if not near:
		return
	_approach_t += delta
	if not _warned and _approach_t >= warn_after:
		_warned = true
		warned.emit(self)
	if _approach_t >= kill_after:
		# Zoegern: ein Bewacher macht seine Drohung wahr
		for b: Variant in brains:
			if bool(b.call("execute_hostage")):
				return

func _clear() -> void:
	state = RoomState.CLEARED
	if slowmo != null and bool(slowmo.get("active")):
		slowmo.call("stop")
	cleared.emit(self)

func _on_hostage_shot(_h: Node) -> void:
	_fail("shot")

func _on_hostage_executed(_h: Node) -> void:
	_fail("executed")

func _fail(reason: String) -> void:
	if state == RoomState.FAILED or state == RoomState.CLEARED:
		return
	state = RoomState.FAILED
	if slowmo != null:
		slowmo.call("stop")
	failed.emit(self, reason)

## Raum auf Anfang: Bewacher neu, Geiseln auf, Tuer zu.
func reset() -> void:
	if state == RoomState.CLEARED:
		return
	for e in captors:
		if is_instance_valid(e):
			e.queue_free()
	captors.clear()
	brains.clear()
	for h in hostages:
		if is_instance_valid(h):
			h.call("reset")
	if door != null:
		door.call("reset")
	state = RoomState.IDLE
	_t_breach = 0.0
	_exec_done.clear()
	_slowmo_used = false
	_approach_t = 0.0
	_warned = false
	if _armed:
		_spawn_captors()
