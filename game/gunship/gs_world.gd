extends Node3D
## Einheiten-Verwaltung der Gunship-Mission: Spawnen, Detonationsschaden (Abstand + Panzerung), Kettenreaktionen,
## Feindfeuer-"Druck" auf den Trupp, Flak-Treffer auf das Flugzeug, Eigenbeschuss-Erkennung.

signal friendly_hit(unit: Node3D, killed: bool)
signal unit_killed(unit: Node3D)

const GSUnit := preload("res://game/gunship/gs_unit.gd")
const DRAIN := {"inf": 0.42, "jeep": 1.2, "apc": 2.0, "tank": 3.2}

var fx = null
var time: float = 0.0
var aircraft_pos: Vector3 = Vector3(0, 760, 0)
var units: Array = []               # alle (auch tote, bis clear)
var team: Array = []
var pressure: float = 100.0         # Lage des Trupps (0 = ueberrannt)
var pressure_active: bool = false
var pressure_drain: float = 0.0
var drain_scale: float = 1.0       # je Phase (Schwierigkeit)
var flak_hits: float = 0.0          # vom Flugzeug abzuholender Flak-Schaden
var escape_z: float = -1e9          # Fahrzeuge mit z < escape_z gelten als entkommen
var _seed: int = 1
var _chain: Array = []              # [zeit, pos, radius, dmg]

func spawn(kind: String, side: String, pos: Vector3, yaw: float = 0.0, phase: int = 0, required: bool = true) -> GSUnit:
	var u: GSUnit = GSUnit.new()
	_seed += 1
	u.name = "%s_%d" % [kind, _seed]
	add_child(u)
	u.setup(kind, side, Vector3(pos.x, 0.0, pos.z), yaw, _seed * 7919)
	u.phase = phase
	u.required = required and side == "reich"
	units.append(u)
	if side == "team" and kind == "team":
		team.append(u)
	return u

## Entfernt alle Einheiten einer Phase (Phasen-Neustart). Wracks/Tote anderer Phasen bleiben.
func remove_phase(p: int, keep_dead: bool = true) -> void:
	var keep: Array = []
	for u in units:
		var un: GSUnit = u
		if un.phase == p and un.side == "reich" and (un.alive or not keep_dead):
			un.queue_free()
		else:
			keep.append(un)
	units = keep

func alive_enemies(p: int = -1, only_required: bool = true) -> Array:
	var out: Array = []
	for u in units:
		var un: GSUnit = u
		if un.alive and un.side == "reich" and (p < 0 or un.phase == p) and (not only_required or un.required):
			out.append(un)
	return out

func team_alive() -> Array:
	var out: Array = []
	for u in team:
		if (u as GSUnit).alive:
			out.append(u)
	return out

func team_center() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in team:
		var un: GSUnit = u
		if un.alive:
			c += un.global_position
			n += 1
	return c / float(n) if n > 0 else Vector3.ZERO

func nearest_hostile(from: GSUnit, rng: float) -> GSUnit:
	var best: GSUnit = null
	var bd := rng * rng
	var p := from.global_position
	var list: Array = team if from.side == "reich" else units
	for u in list:
		var un: GSUnit = u
		if not un.alive or un.side == from.side or un.state == "ride":
			continue
		if from.side == "team" and not un.is_infantry() and un.kind != "jeep":
			continue
		var d := p.distance_squared_to(un.global_position)
		if d < bd:
			bd = d
			best = un
	return best

## Detonation. weapon: 0 = 25 mm, 1 = 40 mm, 2 = 105 mm (Panzerung). Liefert {"friendly": n, "kills": n}.
func blast(pos: Vector3, radius: float, dmg: float, weapon: int, by_player: bool = true) -> Dictionary:
	var res := {"friendly": 0, "kills": 0, "hits": 0}
	for u in units.duplicate():
		var un: GSUnit = u
		if not is_instance_valid(un) or not un.alive:
			continue
		if un.state == "ride":
			continue
		var c: Vector3 = un.hit_center()
		var d := maxf(0.0, pos.distance_to(c) - un.hit_r)
		if d < radius:
			var f := 1.0 - (d / radius) * (d / radius) * 0.8
			var dealt: float = un.damage(dmg * f, weapon)
			if dealt > 0.0:
				res["hits"] += 1
				if un.side == "reich" and by_player:
					Events.enemy_damaged.emit(un, dealt)
				if un.side == "team":
					res["friendly"] += 1
			if un.hp <= 0.0:
				_kill(un, pos)
				res["kills"] += 1
				if un.side == "team":
					friendly_hit.emit(un, true)
			elif dealt > 0.0 and un.side == "team":
				friendly_hit.emit(un, false)
			elif un.alive:
				un.suppress(pos, randf_range(2.0, 4.0))
		elif d < radius * 2.4 and un.is_infantry():
			un.suppress(pos, randf_range(1.5, 3.5) * (1.0 if weapon > 0 else 0.6))
	return res

func team_hit(target: GSUnit, dmg: float) -> void:
	if target == null or not is_instance_valid(target) or not target.alive or target.side != "reich":
		return
	if not target.is_infantry() and target.kind != "jeep":
		return
	target.damage(dmg, 0)
	if target.hp <= 0.0:
		_kill(target, Vector3.INF)

func flak_shot(_u: GSUnit) -> void:
	flak_hits += 0.11

func _kill(un: GSUnit, from: Vector3) -> void:
	un.kill(fx, from)
	unit_killed.emit(un)
	if un.side == "reich":
		Events.enemy_killed.emit(un)
	match un.kind:
		"fuel":
			_chain.append([time + randf_range(0.5, 1.2), un.global_position, 34.0, 520.0])
			_chain.append([time + randf_range(1.6, 2.6), un.global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), 24.0, 300.0])
		"bowser":
			_chain.append([time + randf_range(0.3, 0.8), un.global_position, 16.0, 260.0])
		"jet":
			_chain.append([time + randf_range(0.4, 1.0), un.global_position, 12.0, 160.0])

func _process(delta: float) -> void:
	time += delta
	var drain := 0.0
	for u in units:
		var un: GSUnit = u
		if not is_instance_valid(un):
			continue
		un.tick(delta, self)
		if un.alive and un.side == "reich":
			if pressure_active and un.state == "engage" and un._target != null and un._panic_t <= 0.0:
				drain += float(DRAIN.get(un.kind, 0.0))
			if un.is_vehicle() and un.global_position.z < escape_z:
				un.escaped = true
	drain *= drain_scale
	pressure_drain = drain
	if pressure_active:
		if drain > 0.0:
			pressure = maxf(0.0, pressure - drain * delta)
		else:
			pressure = minf(100.0, pressure + 3.5 * delta)
	var i := 0
	while i < _chain.size():
		var c: Array = _chain[i]
		if time >= float(c[0]):
			_chain.remove_at(i)
			fx.explosion(c[1], clampf(float(c[2]) / 9.0, 1.4, 4.0), float(c[2]) > 20.0)
			blast(c[1], float(c[2]), float(c[3]), 2, true)
			continue
		i += 1
