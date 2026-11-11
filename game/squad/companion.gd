extends RefCounted
## Squad-Befehle light: generischer Begleiter-Baustein. Erfuellt das Begleiter-Interface fuer squad_orders.gd
## und steuert eine Puppen-Figur (overwatch_actor/hafen_actor: walk_to, arrived, puppet_fire, muzzle_pos, crouch).
##
## Interface (jeder Begleiter, auch ein eigenes Level-Objekt, muss das koennen):
##   order_follow() -> bool          Folgen bzw. zurueck auf die Skript-Route
##   order_hold(pos) -> bool         Position halten (pos = aktuelle Position des Begleiters)
##   order_move(pos) -> bool         dort hin, danach halten
##   order_attack(target) -> bool    Feuer auf Ziel (Bewegungsbefehl bleibt bestehen)
##   current_order() -> String       "follow" | "hold" | "move" | "return"
##   is_available() -> bool          darf gerade befehligt werden
##   marker() -> Dictionary          {"pos": Vector3} fuer den Zielmarker (leer = keiner)
##   attack_target() -> Node3D       aktuelles Feuerziel (oder null)
##   reject_reason: String           nach false: "blocked" | "friendly" | "unavailable" | "invalid"
## Optional: signal event(kind) mit "arrived", "target_down", "auto_follow" (squad_orders spricht dazu eine Funkzeile).
##
## Benutzung im Level (siehe nachtzug.gd / hafen.gd):
##   var c := Companion.new(); c.actor = lena; c.move_filter = _my_filter; c.available_cb = func() -> bool: ...
##   squad.companion = c;  pro Physik-Tick c.tick(delta);  Folgen-Logik des Levels nur wenn c.is_following().
## Ohne Befehl (mode "follow", kein Ziel) tut tick() nichts -> das bisherige Verhalten des Levels bleibt exakt gleich.

signal event(kind: String)
signal order_changed(kind: String)

var actor: Node3D = null
## Bewegung
var move_speed: float = 3.0
var use_nav: bool = false            ## Navmesh fuer Befehls-Wege (sonst geradeaus, dann Sichtlinie pruefen)
var crouch_on_hold: bool = false     ## beim Halten in die Hocke (Level, die Haltung selbst steuern: false)
var move_timeout: float = 10.0       ## haengt der Weg fest, wird nach dieser Zeit gehalten
var hold_timeout: float = 0.0        ## > 0: nach so vielen Sekunden Halten selbststaendig wieder folgen
var resume_anchor: bool = false      ## Folgen = erst zurueck zum Ausgangspunkt (fuer Skript-Routen)
var check_line: bool = true          ## ohne Navmesh: Weg muss frei sein (Ray Brust -> Ziel)
var max_move_dist: float = 0.0       ## > 0: Befehlsziel hoechstens so weit vom Begleiter
## Feuer auf Ziel
var fire_interval: Vector2 = Vector2(0.8, 1.3)
var fire_spread: float = 0.3
var hit_chance: float = 0.4
var damage: float = 8.0
var fire_range: float = 40.0
var ray_mask: int = 1 | 4
## Level-Hooks (optional)
var available_cb: Callable           ## () -> bool
var move_filter: Callable            ## (Vector3) -> Variant: angepasster Punkt oder null = geht nicht
var attack_filter: Callable          ## (Node3D) -> bool

var mode: String = "follow"
var reject_reason: String = ""
var anchor: Vector3 = Vector3.ZERO   ## Position beim Verlassen von "follow"
var has_anchor: bool = false
var target: Node3D = null
var order_pos: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _fire_cd: float = 0.0
var _crouch_before: bool = false

# ------------------------------------------------------------------ Interface

func is_available() -> bool:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return false
	if actor.has_method("is_alive") and not bool(actor.call("is_alive")):
		return false
	return not available_cb.is_valid() or bool(available_cb.call())

func current_order() -> String:
	return mode

func is_following() -> bool:
	return mode == "follow"

func has_target() -> bool:
	return _target_ok(target)

func attack_target() -> Node3D:
	return target if _target_ok(target) else null

func marker() -> Dictionary:
	if mode == "hold" or mode == "move":
		return {"pos": order_pos}
	if mode == "return":
		return {"pos": anchor}
	return {}

func order_follow() -> bool:
	reject_reason = ""
	if not is_available():
		reject_reason = "unavailable"
		return false
	if mode == "follow":
		return true
	if resume_anchor and has_anchor:
		_set_mode("return")
		actor.set("crouch", false)
		actor.call("walk_to", anchor, move_speed, use_nav)
		order_pos = anchor
	else:
		_restore_crouch()
		_set_mode("follow")
		has_anchor = false
	return true

func order_hold(pos: Vector3) -> bool:
	reject_reason = ""
	if not is_available():
		reject_reason = "unavailable"
		return false
	_leave_follow()
	order_pos = actor.global_position if pos == Vector3.INF else pos
	actor.call("walk_to", actor.global_position, 1.0, false)   # sofort stehen bleiben
	if crouch_on_hold:
		actor.set("crouch", true)
	_set_mode("hold")
	return true

func order_move(pos: Vector3) -> bool:
	reject_reason = ""
	if not is_available():
		reject_reason = "unavailable"
		return false
	var p := pos
	if max_move_dist > 0.0 and _flat(p - actor.global_position).length() > max_move_dist:
		reject_reason = "blocked"
		return false
	if move_filter.is_valid():
		var r: Variant = move_filter.call(p)
		if not (r is Vector3):
			reject_reason = "blocked"
			return false
		p = r
	elif check_line and not use_nav and not _line_free(p):
		reject_reason = "blocked"
		return false
	_leave_follow()
	order_pos = p
	actor.set("crouch", false)
	actor.call("walk_to", p, move_speed, use_nav)
	_set_mode("move")
	return true

func order_attack(t: Node3D) -> bool:
	reject_reason = ""
	if not is_available():
		reject_reason = "unavailable"
		return false
	if t == null or not is_instance_valid(t):
		reject_reason = "invalid"
		return false
	if t.is_in_group("friendly") or t.is_in_group("no_shoot") or t.is_in_group("player"):
		reject_reason = "friendly"
		return false
	if not _target_ok(t) or (attack_filter.is_valid() and not bool(attack_filter.call(t))):
		reject_reason = "invalid"
		return false
	target = t
	_fire_cd = minf(_fire_cd, 0.35)
	order_changed.emit("attack")
	return true

## Stiller Rueckfall auf "folgen" (Teleport, Respawn, Neustart, Fahrzeug): kein Funk, kein Ziel.
func reset() -> void:
	target = null
	has_anchor = false
	if mode != "follow":
		_restore_crouch()
		_set_mode("follow")

# ------------------------------------------------------------------ Takt (vom Level pro Physik-Tick)

func tick(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	_t += delta
	match mode:
		"move":
			if bool(actor.call("arrived")) or _t > move_timeout:
				actor.call("walk_to", actor.global_position, 1.0, false)
				order_pos = actor.global_position
				if crouch_on_hold:
					actor.set("crouch", true)
				_set_mode("hold")
				event.emit("arrived")
		"hold":
			if hold_timeout > 0.0 and _t > hold_timeout:
				if order_follow():
					event.emit("auto_follow")
		"return":
			if bool(actor.call("arrived")) or _t > move_timeout:
				if not bool(actor.call("arrived")):
					actor.global_position = anchor + Vector3(0, 0.05, 0)   # Notnagel
					actor.call("walk_to", anchor, 1.0, false)
				has_anchor = false
				_restore_crouch()
				_set_mode("follow")
	if target != null:
		if not _target_ok(target):
			var died := is_instance_valid(target)
			target = null
			order_changed.emit("attack_end")
			if died:
				event.emit("target_down")
		else:
			_tick_fire(delta)

func _tick_fire(delta: float) -> void:
	_fire_cd -= delta
	if _fire_cd > 0.0:
		return
	_fire_cd = randf_range(fire_interval.x, fire_interval.y)
	var from: Vector3 = actor.call("muzzle_pos")
	var aim := target.global_position + Vector3.UP * 1.2
	if from.distance_to(aim) > fire_range:
		return
	var ex: Array[RID] = []
	if actor is CollisionObject3D:
		ex.append((actor as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, aim, ray_mask, ex)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and not _is_part_of(hit.get("collider") as Node, target):
		return
	actor.call("puppet_fire", aim, fire_spread)
	if randf() < hit_chance and target.has_method("take_damage"):
		target.call("take_damage", damage, actor, aim, (from - aim).normalized())

# ------------------------------------------------------------------ intern

func _set_mode(m: String) -> void:
	mode = m
	_t = 0.0
	order_changed.emit(m)

func _leave_follow() -> void:
	if mode == "follow":
		anchor = actor.global_position
		has_anchor = true
		_crouch_before = bool(actor.get("crouch"))

func _restore_crouch() -> void:
	if crouch_on_hold and actor != null and is_instance_valid(actor):
		actor.set("crouch", _crouch_before)

func _target_ok(t: Variant) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var n := t as Node
	if not n.is_inside_tree() or not n.is_in_group("enemy"):
		return false
	if n.has_method("is_alive"):
		return bool(n.call("is_alive"))
	return not bool(n.get("dead"))

func _line_free(p: Vector3) -> bool:
	var from := actor.global_position + Vector3.UP * 1.0
	var to := p + Vector3.UP * 1.0
	var ex: Array[RID] = []
	if actor is CollisionObject3D:
		ex.append((actor as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, ex)
	return actor.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

static func _is_part_of(n: Node, root: Node) -> bool:
	while n != null:
		if n == root:
			return true
		n = n.get_parent()
	return false

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
